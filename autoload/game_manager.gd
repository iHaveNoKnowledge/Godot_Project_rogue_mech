extends Node

enum State { MENU, BOARD, COMBAT, SAFEHOUSE, HANGAR, EJECT, PILOT }

var current_state: State = State.MENU


func transition_to(new_state: State) -> void:
	var old_name = State.keys()[current_state]
	current_state = new_state
	var new_name = State.keys()[new_state]
	EventBus.game_state_changed.emit(old_name, new_name)


func enter_combat() -> void:
	transition_to(State.COMBAT)


func enter_board() -> void:
	transition_to(State.BOARD)


func enter_safehouse() -> void:
	transition_to(State.SAFEHOUSE)


func enter_hangar() -> void:
	transition_to(State.HANGAR)


func enter_eject() -> void:
	transition_to(State.EJECT)


func end_run(victory: bool) -> void:
	EventBus.run_ended.emit(victory)
	transition_to(State.MENU)
