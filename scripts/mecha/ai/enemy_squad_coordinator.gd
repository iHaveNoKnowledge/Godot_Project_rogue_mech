class_name EnemySquadCoordinator
extends Node

## Manages tactical squad formations, role coordination, dynamic flanking slots,
## and mutual anti-blobbing separation for an enemy fleet / fireteam.

signal member_killed(mech: Node3D, pilot_data: Dictionary)
signal commander_killed(mech: Node3D)

var squad_id: String = ""
var squad_name: String = ""
var commander_mech: Node3D = null
var members: Array[Node3D] = []
var pilot_registry: Dictionary = {} # mech -> pilot_data Dictionary

# Formation offset table (Wedge formation)
const WEDGE_OFFSETS: Array[Vector3] = [
	Vector3(0, 0, 0),        # Commander (Tip)
	Vector3(-6.5, 0, 6.0),   # Left Wing 1
	Vector3(6.5, 0, 6.0),    # Right Wing 1
	Vector3(-13.0, 0, 12.0), # Left Wing 2
	Vector3(13.0, 0, 12.0),  # Right Wing 2
	Vector3(0, 0, 15.0),     # Rear Center
	Vector3(-7.0, 0, 18.0),  # Rear Left
	Vector3(7.0, 0, 18.0),   # Rear Right
]


func setup_squad(id: String, name_str: String) -> void:
	squad_id = id
	squad_name = name_str


func register_member(mech: Node3D, pilot: Dictionary) -> void:
	if mech == null or not is_instance_valid(mech):
		return
	if not members.has(mech):
		members.append(mech)
	pilot_registry[mech] = pilot

	if pilot.get("squad_role") == "commander" or commander_mech == null:
		commander_mech = mech

	if not mech.tree_exiting.is_connected(_on_member_exiting):
		mech.tree_exiting.connect(_on_member_exiting.bind(mech))


func unregister_member(mech: Node3D) -> void:
	if members.has(mech):
		members.erase(mech)
	var pilot: Dictionary = pilot_registry.get(mech, {})
	pilot_registry.erase(mech)

	if mech == commander_mech:
		commander_mech = null
		commander_killed.emit(mech)
		_promote_new_commander()

	member_killed.emit(mech, pilot)


func _on_member_exiting(mech: Node3D) -> void:
	unregister_member(mech)


func _promote_new_commander() -> void:
	# Promote highest surviving rank or first living member to leader
	for m in members:
		if is_instance_valid(m):
			commander_mech = m
			if pilot_registry.has(m):
				pilot_registry[m]["squad_role"] = "commander"
				pilot_registry[m]["tactical_role"] = "commander"
			if m.get("squad_role") != null:
				m.set("squad_role", "commander")
			break


func get_living_count() -> int:
	var count := 0
	for m in members:
		if is_instance_valid(m) and not (m.get("health_system") != null and m.health_system.get("is_destroyed")):
			count += 1
	return count


## Returns the patrol formation offset relative to the commander
func get_formation_offset(mech: Node3D) -> Vector3:
	var idx := members.find(mech)
	if idx < 0:
		return Vector3.ZERO
	return WEDGE_OFFSETS[idx % WEDGE_OFFSETS.size()]


## Computes adaptive tactical flanking angle around the target based on living squad size and role
func get_tactical_flank_angle(mech: Node3D) -> float:
	var living := get_living_count()
	var role := "vanguard"
	if pilot_registry.has(mech):
		role = str(pilot_registry[mech].get("tactical_role", "vanguard"))

	# Solo Ace / Lone survivor
	if living <= 1:
		return 0.0

	# Duo Pair: Hammer & Anvil
	if living == 2:
		if mech == commander_mech or role in ["commander", "vanguard", "guardian"]:
			return 0.0 # Frontal pressure
		else:
			return deg_to_rad(85.0) # Lateral flanker

	# 3-4 Mechs: Pincer & Overwatch
	if living in [3, 4]:
		match role:
			"commander", "guardian":
				return 0.0
			"vanguard":
				return deg_to_rad(-25.0)
			"flanker_left":
				return deg_to_rad(-75.0)
			"flanker_right":
				return deg_to_rad(75.0)
			"fire_support":
				return deg_to_rad(140.0) # Rear overwatch
			_:
				var idx := members.find(mech)
				return deg_to_rad((idx * 60.0) - 60.0)

	# 5+ Mechs: Full 8-Point Encirclement Ring
	var idx := members.find(mech)
	if idx < 0:
		idx = 0
	var step := TAU / float(maxi(living, 5))
	return idx * step


## Computes the optimal surround waypoint coordinate around the combat target
func get_tactical_waypoint(mech: Node3D, target: Node3D, ideal_distance: float) -> Vector3:
	if target == null or not is_instance_valid(target):
		return mech.global_position

	var target_pos: Vector3 = target.global_position
	var flank_angle := get_tactical_flank_angle(mech)

	# Face direction from target towards mech as baseline angle
	var diff: Vector3 = mech.global_position - target_pos
	diff.y = 0.0
	var base_yaw: float = atan2(diff.x, diff.z) if diff.length_squared() > 0.01 else 0.0
	var final_yaw: float = base_yaw + flank_angle

	var offset := Vector3(sin(final_yaw), 0, cos(final_yaw)) * ideal_distance
	return target_pos + offset


## Calculates Boids mutual repulsion force from friendly squadmates to prevent blobbing
func get_separation_vector(mech: Node3D, radius: float = 6.5) -> Vector3:
	if mech == null or not is_instance_valid(mech):
		return Vector3.ZERO

	var separation := Vector3.ZERO
	var pos: Vector3 = mech.global_position

	for other in members:
		if other == mech or not is_instance_valid(other):
			continue
		var other_hs = other.get("health_system")
		if other_hs != null and other_hs.get("is_destroyed"):
			continue

		var diff: Vector3 = pos - other.global_position
		diff.y = 0.0
		var dist := diff.length()
		if dist < radius and dist > 0.01:
			# Inverse distance quadratic repulsion
			var strength: float = (radius - dist) / radius
			separation += diff.normalized() * strength

	return separation
