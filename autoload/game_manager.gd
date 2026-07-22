extends Node

enum State { MENU, BOARD, COMBAT, SAFEHOUSE, HANGAR, EJECT, PILOT }

var current_state: State = State.MENU
var game_world_scene: PackedScene = preload("res://scenes/game_world.tscn")
var board_scene: PackedScene = preload("res://scenes/board/game_board.tscn")


func transition_to(new_state: State) -> void:
	var old_name = State.keys()[current_state]
	current_state = new_state
	var new_name = State.keys()[new_state]
	EventBus.game_state_changed.emit(old_name, new_name)


func enter_combat() -> void:
	transition_to(State.COMBAT)


func enter_board() -> void:
	# Load game world if not already loaded
	var world = get_tree().current_scene
	if world == null or world.name != "GameWorld":
		get_tree().change_scene_to_file("res://scenes/game_world.tscn")
	transition_to(State.BOARD)


func enter_safehouse() -> void:
	transition_to(State.SAFEHOUSE)


func enter_hangar() -> void:
	transition_to(State.HANGAR)


func enter_eject() -> void:
	transition_to(State.EJECT)


func end_run(victory: bool) -> void:
	EventBus.run_ended.emit(victory)
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	transition_to(State.MENU)
