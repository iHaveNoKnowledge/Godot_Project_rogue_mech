extends CharacterBody3D
class_name WarPilotAgent

## =============================================================================
## WAR PILOT AGENT — Symmetric Pilot AI (Pilot-Centric Warfare Simulation)
## =============================================================================
## The Pilot is the primary actor. Pilots spawn on foot at Barracks, dynamically
## evaluate battlefield requirements, walk to the Hangar/Vehicle Bay to board
## available Valkren mechas (GM vs Zaku) or Combat Tanks, and emergency-eject
## when their vehicles are breached.
##
## Used identically by BOTH factions:
##   • team == "friendly": Fights for Friendly Base (GM / Federation Archetype)
##   • team == "enemy":    Fights for Enemy Base (Zaku / Outlaw Archetype)
## =============================================================================

enum PilotState {
	SPAWNED_AT_BARRACKS,
	ON_FOOT_SEEKING_VEHICLE,
	PILOTING_COMBAT,
	EJECTED_SURVIVAL
}

@export var team: String = "friendly"
@export var pilot_name: String = "Pilot"
@export var assigned_role: String = "assault"
@export var walk_speed: float = 6.5

var state: int = PilotState.SPAWNED_AT_BARRACKS
var current_vehicle: Node3D = null
var target_destination: Vector3 = Vector3.ZERO
var combat_target: Node3D = null

var _decision_timer: float = 0.0
var _desired_tier: String = "line"
var _health: float = 100.0
var _visual_mesh: MeshInstance3D = null


func _ready() -> void:
	add_to_group("pilot")
	add_to_group(team)
	_build_pilot_visual()
	_evaluate_battlefield_need()
	state = PilotState.ON_FOOT_SEEKING_VEHICLE


func _build_pilot_visual() -> void:
	# Capsule collision
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	col.shape = shape
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	# Visual model
	_visual_mesh = MeshInstance3D.new()
	var c_mesh := CapsuleMesh.new()
	c_mesh.radius = 0.38
	c_mesh.height = 1.75
	_visual_mesh.mesh = c_mesh
	_visual_mesh.position = Vector3(0, 0.9, 0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.55, 0.9) if team == "friendly" else Color(0.9, 0.3, 0.25)
	mat.roughness = 0.5
	_visual_mesh.material_override = mat
	add_child(_visual_mesh)

	# Pilot floating tag
	var lbl := Label3D.new()
	lbl.text = "[%s] %s" % [team.to_upper(), pilot_name]
	lbl.font_size = 18
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0, 2.1, 0)
	add_child(lbl)


func _evaluate_battlefield_need() -> void:
	# Dynamic assessment of battlefield needs:
	# Count heavy vehicles vs agile scouts on the field
	var allies := get_tree().get_nodes_in_group(team) if get_tree() else []
	var enemies := get_tree().get_nodes_in_group("enemy" if team == "friendly" else "friendly") if get_tree() else []

	var tank_count := 0
	for a in allies:
		if a.is_in_group("tank") or a.is_in_group("iron"):
			tank_count += 1

	if tank_count < 1 and randf() < 0.4:
		_desired_tier = "iron"  # Need heavy armor / frontline tank
	elif enemies.size() > allies.size() and randf() < 0.3:
		_desired_tier = "strike" # Need fast hit-and-run / capture
	else:
		_desired_tier = "line"   # Standard issue backbone


func _physics_process(delta: float) -> void:
	_decision_timer -= delta

	match state:
		PilotState.SPAWNED_AT_BARRACKS:
			_evaluate_battlefield_need()
			state = PilotState.ON_FOOT_SEEKING_VEHICLE

		PilotState.ON_FOOT_SEEKING_VEHICLE:
			_process_seeking_vehicle(delta)

		PilotState.PILOTING_COMBAT:
			_process_piloting_combat(delta)

		PilotState.EJECTED_SURVIVAL:
			_process_ejected_survival(delta)


func _process_seeking_vehicle(delta: float) -> void:
	# Determine Hangar Bay coordinates for our faction
	var hangar_pos := Vector3(0, 0, -780) if team == "friendly" else Vector3(0, 0, 780)
	target_destination = hangar_pos

	var dist := global_position.distance_to(hangar_pos)
	if dist > 8.0:
		# Run toward Hangar Bay
		var dir: Vector3 = (hangar_pos - global_position).normalized()
		dir.y = 0.0
		dir = dir.normalized()
		velocity.x = dir.x * walk_speed
		velocity.z = dir.z * walk_speed
		if not is_on_floor():
			velocity.y -= 9.8 * delta
		move_and_slide()
		# Face move direction
		if dir.length_squared() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 10.0 * delta)
	else:
		# Reached Hangar: claim vehicle and board
		_claim_and_board_vehicle()


func _claim_and_board_vehicle() -> void:
	# 1. Check for nearby unoccupied mecha or tank in staging area
	var nearby_unoccupied := _find_nearest_unoccupied_vehicle(25.0)
	if nearby_unoccupied != null:
		_board_existing_vehicle(nearby_unoccupied)
		return

	# 2. Spawn a fresh machine from Hangar Stock
	var parent_scene = get_parent()
	if parent_scene == null:
		return

	var spawn_pos = global_position + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
	spawn_pos = WarBiomeGenerator.snap_to_ground(spawn_pos, 0.05)

	# If iron requested and tank is available, or Valkren line
	var scene = load("res://scenes/mecha/mecha_base.tscn")
	if scene:
		var mech = scene.instantiate()
		mech.name = "%s_Valkren_%d" % [team.capitalize(), randi() % 1000]
		mech.position = spawn_pos
		parent_scene.add_child(mech)

		# Apply Faction Archetype: GM for friendly, Zaku for enemy
		WarFactionVisual.apply_faction_archetype(mech, team, _desired_tier)
		mech.add_to_group(team)

		_board_existing_vehicle(mech)


func _board_existing_vehicle(vehicle: Node3D) -> void:
	current_vehicle = vehicle
	state = PilotState.PILOTING_COMBAT

	# Board handshake with decoupled vehicle interface
	if vehicle.has_method("board_pilot"):
		vehicle.board_pilot(self)

	# Hide on-foot pilot mesh and disable physical collisions while seated inside
	visible = false
	collision_layer = 0
	collision_mask = 0

	# Reparent pilot inside vehicle
	reparent(vehicle)
	position = Vector3(0, 1.2, 0)

	# Connect vehicle destruction signal for emergency eject
	var hs = vehicle.get_node_or_null("HealthSystem")
	if hs and hs.has_signal("destroyed"):
		hs.destroyed.connect(_on_vehicle_destroyed)


func _process_piloting_combat(delta: float) -> void:
	if current_vehicle == null or not is_instance_valid(current_vehicle):
		_emergency_eject()
		return

	# Keep pilot position synced with vehicle
	global_position = current_vehicle.global_position

	# Periodic strategic AI decision
	if _decision_timer <= 0.0:
		_decision_timer = randf_range(0.8, 1.4)
		_acquire_combat_target()

	var move_dir := Vector3.ZERO
	var aim_point := Vector3.ZERO
	var fire_l := false
	var fire_r := false
	var wants_dash := false

	if combat_target != null and is_instance_valid(combat_target):
		var target_pos = combat_target.global_position
		aim_point = target_pos + Vector3(0, 1.5, 0)
		var dist_to_target = current_vehicle.global_position.distance_to(target_pos)

		if dist_to_target > 25.0:
			# Advance toward target
			move_dir = (target_pos - current_vehicle.global_position).normalized()
			if dist_to_target > 50.0 and randf() < 0.2:
				wants_dash = true
		elif dist_to_target < 12.0:
			# Tactical strafe / backup
			move_dir = -(target_pos - current_vehicle.global_position).normalized()
		else:
			# Circle strafe
			var to_tgt = (target_pos - current_vehicle.global_position).normalized()
			move_dir = Vector3(-to_tgt.z, 0, to_tgt.x)

		# Fire weapons when target is in line of sight and within combat range (< 65m)
		if dist_to_target <= 65.0:
			fire_l = true
			fire_r = (dist_to_target <= 40.0)
	else:
		# Advance toward enemy territory
		var enemy_base_z: float = 750.0 if team == "friendly" else -750.0
		var objective_pos := Vector3(randf_range(-100, 100), 0, enemy_base_z)
		move_dir = (objective_pos - current_vehicle.global_position).normalized()
		aim_point = current_vehicle.global_position + move_dir * 30.0

	# Feed commands into decoupled vehicle interface
	if current_vehicle.has_method("set_drive_commands"):
		current_vehicle.set_drive_commands(move_dir, aim_point, fire_l, fire_r, wants_dash)


func _acquire_combat_target() -> void:
	combat_target = null
	var enemy_group: String = "enemy" if team == "friendly" else "friendly"
	var hostile_nodes := get_tree().get_nodes_in_group(enemy_group) if get_tree() else []

	var best_dist := 180.0
	var my_pos = current_vehicle.global_position if current_vehicle else global_position

	for h in hostile_nodes:
		if h == self or not (h is Node3D):
			continue
		if h.has_method("_is_downed") and h._is_downed():
			continue
		var d = my_pos.distance_to((h as Node3D).global_position)
		if d < best_dist:
			best_dist = d
			combat_target = h as Node3D


func _on_vehicle_destroyed() -> void:
	_emergency_eject()


func _emergency_eject() -> void:
	if state == PilotState.EJECTED_SURVIVAL:
		return

	state = PilotState.EJECTED_SURVIVAL
	var eject_pos := global_position
	if current_vehicle and is_instance_valid(current_vehicle):
		eject_pos = current_vehicle.global_position + Vector3(randf_range(-3, 3), 1.0, randf_range(-3, 3))
		if current_vehicle.has_method("eject_pilot"):
			current_vehicle.eject_pilot()

	# Restore on-foot pilot
	var world_root = get_tree().current_scene if get_tree() else null
	if world_root:
		reparent(world_root)
	global_position = WarBiomeGenerator.snap_to_ground(eject_pos, 0.05)
	visible = true
	collision_layer = 1
	collision_mask = 1
	current_vehicle = null

	# Trigger eject audio and VFX
	if AudioManager and AudioManager.has_method("play_eject"):
		AudioManager.play_eject()


func _process_ejected_survival(delta: float) -> void:
	# Scan for unoccupied vehicle nearby
	var vehicle = _find_nearest_unoccupied_vehicle(60.0)
	if vehicle != null:
		# Run toward it to re-board
		var dir: Vector3 = (vehicle.global_position - global_position).normalized()
		dir.y = 0.0
		dir = dir.normalized()
		velocity.x = dir.x * (walk_speed * 1.2) # adrenaline sprint
		velocity.z = dir.z * (walk_speed * 1.2)
		if not is_on_floor():
			velocity.y -= 9.8 * delta
		move_and_slide()

		if global_position.distance_to(vehicle.global_position) < 3.5:
			_board_existing_vehicle(vehicle)
	else:
		# Retreat toward friendly base
		var base_pos := Vector3(0, 0, -780) if team == "friendly" else Vector3(0, 0, 780)
		var dir: Vector3 = (base_pos - global_position).normalized()
		dir.y = 0.0
		dir = dir.normalized()
		velocity.x = dir.x * walk_speed
		velocity.z = dir.z * walk_speed
		if not is_on_floor():
			velocity.y -= 9.8 * delta
		move_and_slide()

		if global_position.distance_to(base_pos) < 15.0:
			# Reached safety of base -> cycle back to seeking a fresh machine
			state = PilotState.ON_FOOT_SEEKING_VEHICLE


func _find_nearest_unoccupied_vehicle(max_range: float) -> Node3D:
	var mechas := get_tree().get_nodes_in_group("mecha") if get_tree() else []
	var best: Node3D = null
	var best_d := max_range

	for m in mechas:
		if m == current_vehicle or not (m is Node3D):
			continue
		if m.has_meta("is_unoccupied") and bool(m.get_meta("is_unoccupied")):
			var d = global_position.distance_to((m as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = m as Node3D
	return best
