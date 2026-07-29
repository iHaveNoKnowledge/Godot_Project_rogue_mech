extends Node

enum State { MENU, BOARD, COMBAT, SAFEHOUSE, HANGAR, EJECT, PILOT }

var current_state: State = State.MENU


var is_boss_combat: bool = false


func transition_to(new_state: State) -> void:
	var old_name = State.keys()[current_state]
	current_state = new_state
	var new_name = State.keys()[new_state]
	EventBus.game_state_changed.emit(old_name, new_name)


func enter_board() -> void:
	get_tree().change_scene_to_file("res://scenes/board/game_board.tscn")
	transition_to(State.BOARD)


func enter_combat(combat_type: String = "grunt") -> void:
	is_boss_combat = (combat_type == "boss")
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")
	transition_to(State.COMBAT)
	EventBus.combat_intensity_changed.emit(1.0)
	AudioManager.play_combat_music(combat_type)


func advance_to_next_sector() -> void:
	is_boss_combat = false
	GlobalData.current_sector += 1
	GlobalData.current_tile = Vector2i.ZERO
	GlobalData.heat = max(0, GlobalData.heat - 2)
	GlobalData.wanted_level = min(GlobalData.wanted_level + 1, 5)
	GlobalData.save_run()
	EventBus.combat_intensity_changed.emit(0.0)
	AudioManager.stop_music()
	get_tree().change_scene_to_file("res://scenes/board/game_board.tscn")
	transition_to(State.BOARD)


func return_to_board() -> void:
	is_boss_combat = false
	GlobalData.save_run()
	EventBus.combat_intensity_changed.emit(0.0)
	AudioManager.stop_music()
	get_tree().change_scene_to_file("res://scenes/board/game_board.tscn")
	transition_to(State.BOARD)


func enter_safehouse() -> void:
	transition_to(State.SAFEHOUSE)


func enter_hangar() -> void:
	transition_to(State.HANGAR)


func enter_eject() -> void:
	transition_to(State.EJECT)


func game_over() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	transition_to(State.MENU)


func end_run(victory: bool) -> void:
	EventBus.run_ended.emit(victory)
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	transition_to(State.MENU)
