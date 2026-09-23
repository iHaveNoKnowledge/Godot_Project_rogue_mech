extends Node
class_name MissileLockOnSystem

## Missile Lock-on & Multi-Target Swarm System
## Handles hold-and-sweep targeting, lock stacking per enemy, audio cues, and salvo dispatch.

signal lock_updated(targets: Dictionary)
signal lock_acquired(target: Node3D, current_stack: int)
signal lock_cleared()

var weapon_manager: Node = null
var active_slot: String = ""
var locking_weapon: WeaponPart = null
var is_locking: bool = false
var hold_duration: float = 0.0
var tap_threshold: float = 0.22

var locked_targets: Dictionary = {}        # Node3D -> int (missile count)
var target_lock_progress: Dictionary = {}  # Node3D -> float (seconds accumulated)

var lock_interval: float = 0.16           # time in seconds to add 1 missile to lock stack
var effective_range: float = 100.0
# Per-target cap is per POD MODEL (set in start_locking from weapon.max_ammo),
# 8 is only the fallback for weapons with no magazine size.
var max_locks_per_target: int = 8
var max_total_locks: int = 8
var lock_cone_degrees: float = 16.0


func _ready() -> void:
	set_physics_process(true)


func start_locking(slot: String, weapon: WeaponPart, current_ammo: int) -> void:
	active_slot = slot
	locking_weapon = weapon
	is_locking = true
	hold_duration = 0.0
	locked_targets.clear()
	target_lock_progress.clear()
	effective_range = weapon.range_distance if ("range_distance" in weapon and weapon.range_distance > 0.0) else 100.0
	var mag_limit := weapon.max_ammo if ("max_ammo" in weapon and weapon.max_ammo > 0) else 8
	# Total locks never exceed the pod's magazine (current ammo or pod max,
	# whichever is smaller); each single target may take up to the FULL pod,
	# so locks split across targets by sweep time (4/8+4/8, 1/8+3/8+4/8, ...).
	max_total_locks = mini(current_ammo, mag_limit)
	max_locks_per_target = mag_limit
	lock_updated.emit(locked_targets)


func stop_locking() -> Dictionary:
	var result := {
		"slot": active_slot,
		"weapon": locking_weapon,
		"hold_duration": hold_duration,
		"is_tap": hold_duration < tap_threshold,
		"targets": locked_targets.duplicate(),
		"total_locks": get_total_locks()
	}
	is_locking = false
	active_slot = ""
	locking_weapon = null
	locked_targets.clear()
	target_lock_progress.clear()
	lock_cleared.emit()
	return result


func cancel_locking() -> void:
	is_locking = false
	active_slot = ""
	locking_weapon = null
	locked_targets.clear()
	target_lock_progress.clear()
	lock_cleared.emit()


func get_total_locks() -> int:
	var total := 0
	for count in locked_targets.values():
		total += int(count)
	return total


func _physics_process(delta: float) -> void:
	if not is_locking:
		return

	hold_duration += delta

	# 1. Prune dead or destroyed targets
	var keys_to_remove: Array = []
	for target in locked_targets.keys():
		if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion():
			keys_to_remove.append(target)
		elif "is_destroyed" in target and target.is_destroyed:
			keys_to_remove.append(target)
	if not keys_to_remove.is_empty():
		for k in keys_to_remove:
			locked_targets.erase(k)
			target_lock_progress.erase(k)
		lock_updated.emit(locked_targets)

	var tree := get_tree()
	if tree == null:
		return

	var vp := tree.root.get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return

	var cam_pos: Vector3 = cam.global_position
	var cam_forward: Vector3 = -cam.global_transform.basis.z.normalized()

	# 2. Find eligible enemies in cone
	var enemies := tree.get_nodes_in_group("enemy")
	var space_state := cam.get_world_3d().direct_space_state if (cam.get_world_3d() and cam.get_world_3d().direct_space_state) else null

	for enemy in enemies:
		if not (enemy is Node3D) or not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		if "is_destroyed" in enemy and enemy.is_destroyed:
			continue

		var enemy_center: Vector3 = enemy.global_position + Vector3(0.0, 1.2, 0.0)
		var dist: float = cam_pos.distance_to(enemy_center)
		if dist > effective_range or dist < 1.0:
			continue

		var to_enemy: Vector3 = (enemy_center - cam_pos).normalized()
		var dot_fwd: float = clampf(cam_forward.dot(to_enemy), -1.0, 1.0)
		var angle_deg: float = rad_to_deg(acos(dot_fwd))
		if angle_deg > lock_cone_degrees:
			continue

		# Line of sight check
		if space_state:
			var query := PhysicsRayQueryParameters3D.create(cam_pos, enemy_center)
			query.collision_mask = 1 | 4  # World terrain / obstacles
			var hit := space_state.intersect_ray(query)
			if hit and hit.get("collider") != enemy and hit.get("collider") != null:
				continue

		# Enemy is valid and in crosshair cone!
		if get_total_locks() < max_total_locks:
			var prog: float = float(target_lock_progress.get(enemy, 0.0)) + delta
			if prog >= lock_interval:
				prog = 0.0
				var cur_count: int = int(locked_targets.get(enemy, 0))
				if cur_count < max_locks_per_target and get_total_locks() < max_total_locks:
					cur_count += 1
					locked_targets[enemy] = cur_count
					if AudioManager:
						AudioManager.play_lock_on_beep(cur_count)
					lock_acquired.emit(enemy, cur_count)
					lock_updated.emit(locked_targets)
			target_lock_progress[enemy] = prog
