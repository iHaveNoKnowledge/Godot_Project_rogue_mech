extends EnemyState

## Idle state: scan for targets. While unspotted the enemy actively hunts the
## battlefield instead of standing still — it patrols toward the arena center
## (where the player engages) and transitions to chase the moment it spots one.

var scan_timer: float = 0.0
const SCAN_INTERVAL: float = 0.5

# Search/hunt behavior for unspotted enemies.
var search_target: Vector3 = Vector3.ZERO
var has_search_target: bool = false
var repath_timer: float = 0.0
const REPATH_INTERVAL: float = 0.7
const SEARCH_RADIUS: float = 40.0
const ARENA_RADIUS: float = 110.0
var path: PackedVector3Array = []
var path_index: int = 0


func enter() -> void:
	scan_timer = 0.0
	has_search_target = false
	repath_timer = 0.0
	path = []
	path_index = 0


func physics_process(delta: float) -> void:
	# Apply gravity
	enemy.velocity.y -= 10.0 * delta

	scan_timer -= delta
	if scan_timer <= 0.0:
		scan_timer = SCAN_INTERVAL
		if _find_target():
			return

	# Unspotted: move to find the player instead of idling in place.
	_pick_search_target_if_needed()
	_move_to_search_target(delta)

	enemy.move_and_slide()


# Returns true (and transitions to chase) when a target is within detection
# range. Unspotted enemies keep hunting otherwise.
func _find_target() -> bool:
	# Enemies prioritize the player mecha, but will also engage fielded allies.
	var mechas = enemy.get_tree().get_nodes_in_group("mecha")
	var allies = enemy.get_tree().get_nodes_in_group("ally")
	var nearest: Node3D = null
	var nearest_dist: float = 50.0
	for candidate in mechas + allies:
		if not is_instance_valid(candidate):
			continue
		var dist = enemy.global_position.distance_to(candidate.global_position)
		if dist < nearest_dist:
			nearest = candidate
			nearest_dist = dist
	if nearest:
		enemy.target = nearest
		state_machine.transition_to("StateChase")
		return true
	return false


# Picks a destination for the current hunt. Biased toward the arena center
# where the player fights, with a random offset so unspotted enemies fan out
# across the battlefield instead of stacking on one spot.
func _pick_search_target_if_needed() -> void:
	if has_search_target:
		return
	var flat := Vector3(
		randf_range(-SEARCH_RADIUS, SEARCH_RADIUS),
		0.0,
		randf_range(-SEARCH_RADIUS, SEARCH_RADIUS)
	)
	if flat.length() > ARENA_RADIUS * 0.85:
		flat = flat.normalized() * ARENA_RADIUS * 0.85
	search_target = Vector3(flat.x, enemy.global_position.y, flat.z)
	has_search_target = true
	repath_timer = 0.0
	path = []
	path_index = 0


func _move_to_search_target(delta: float) -> void:
	if not has_search_target:
		return

	# Repath periodically so walls/cover don't pin the enemy in place.
	repath_timer -= delta
	if repath_timer <= 0.0 or path.is_empty():
		repath_timer = REPATH_INTERVAL
		_update_search_path()

	if path.is_empty():
		_direct_search_move(delta)
		return

	if path_index >= path.size():
		path_index = path.size() - 1

	var waypoint: Vector3 = path[path_index]
	var direction: Vector3 = waypoint - enemy.global_position
	direction.y = 0.0

	if direction.length() < 1.5:
		path_index += 1
		if path_index >= path.size():
			# Reached the search destination; pick a new one next frame.
			has_search_target = false
			enemy.velocity.x = 0.0
			enemy.velocity.z = 0.0
			return
		waypoint = path[path_index]
		direction = waypoint - enemy.global_position
		direction.y = 0.0

	if direction.length() > 0.1:
		var dir := direction.normalized()
		enemy.velocity.x = dir.x * enemy.move_speed
		enemy.velocity.z = dir.z * enemy.move_speed
		enemy.rotation.y = lerp_angle(enemy.rotation.y, atan2(direction.x, direction.z), 5.0 * delta)
	else:
		enemy.velocity.x = 0.0
		enemy.velocity.z = 0.0


func _update_search_path() -> void:
	var maps = NavigationServer3D.get_maps()
	if maps.is_empty():
		path = PackedVector3Array()
		return
	path = NavigationServer3D.map_get_path(maps[0], enemy.global_position, search_target, true)
	path_index = 0


# Fallback when no navigation map is available: walk straight at the target.
func _direct_search_move(delta: float) -> void:
	var direction: Vector3 = search_target - enemy.global_position
	direction.y = 0.0
	if direction.length() > 0.1:
		var dir := direction.normalized()
		enemy.velocity.x = dir.x * enemy.move_speed
		enemy.velocity.z = dir.z * enemy.move_speed
		enemy.rotation.y = lerp_angle(enemy.rotation.y, atan2(direction.x, direction.z), 5.0 * delta)
	else:
		enemy.velocity.x = 0.0
		enemy.velocity.z = 0.0