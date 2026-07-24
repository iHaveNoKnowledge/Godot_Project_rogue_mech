class_name EnemyStateMachine
extends Node

## Manages enemy AI states. Attach as child of enemy CharacterBody3D.

var current_state: EnemyState
var enemy: CharacterBody3D


func _ready() -> void:
	enemy = get_parent() as CharacterBody3D
	# Initialize all child states
	for child in get_children():
		if child is EnemyState:
			child.enemy = enemy
			child.state_machine = self


func _physics_process(delta: float) -> void:
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
