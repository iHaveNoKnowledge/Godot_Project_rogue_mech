extends EnemyState

## Idle state: stand still, scan for targets.

var scan_timer: float = 0.0
const SCAN_INTERVAL: float = 0.5


func enter() -> void:
	scan_timer = 0.0


func physics_process(delta: float) -> void:
	# Apply gravity
	enemy.velocity.y -= 10.0 * delta
	enemy.move_and_slide()

	scan_timer -= delta
	if scan_timer <= 0.0:
		scan_timer = SCAN_INTERVAL
		_find_target()


func _find_target() -> void:
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
