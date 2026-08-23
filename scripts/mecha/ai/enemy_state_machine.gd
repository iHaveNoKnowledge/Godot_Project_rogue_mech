class_name EnemyStateMachine
extends Node

## Manages enemy AI states. Attach as child of enemy CharacterBody3D.

var current_state: EnemyState
var enemy: CharacterBody3D


func initialize_states() -> void:
	enemy = get_parent() as CharacterBody3D
	for child in get_children():
		if child is EnemyState:
			child.enemy = enemy
			child.state_machine = self


var _emp_stun_timer: float = 0.0


func _physics_process(delta: float) -> void:
	# GDD §7: EWar EMP stun — enemies frozen while stunned
	if GlobalData.ewar != null and GlobalData.ewar.is_active(GlobalData.ewar.Ability.EMP):
		_emp_stun_timer = GlobalData.ewar.emp_stun_duration()
	if _emp_stun_timer > 0.0:
		_emp_stun_timer = maxf(_emp_stun_timer - delta, 0.0)
		return  # Skip AI processing while stunned
	if current_state:
		current_state.physics_process(delta)


func transition_to(state_name: String) -> void:
	var new_state = get_node_or_null(state_name) as EnemyState
	if new_state == null or new_state == current_state:
		return

	if current_state:
		current_state.exit()

	current_state = new_state
	current_state.enter()
