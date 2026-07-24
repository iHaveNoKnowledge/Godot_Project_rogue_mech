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
	var mechas = enemy.get_tree().get_nodes_in_group("mecha")
	for mecha in mechas:
		if is_instance_valid(mecha):
			var dist = enemy.global_position.distance_to(mecha.global_position)
			if dist < 50.0:  # Detection range
				enemy.target = mecha
				state_machine.transition_to("StateChase")
				return
