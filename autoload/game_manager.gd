extends Node

enum State { MENU, BOARD, COMBAT, SAFEHOUSE, HANGAR, EJECT, PILOT }

var current_state: State = State.MENU


var is_boss_combat: bool = false

# True while the player is abandoning a battle via an escape zone, so the
# death/defeat path can't fire at the same time as the retreat.
var is_escaping: bool = false


# Central lookup for the active player mecha. Avoids repeating fragile
# `current_scene.get_node_or_null("Mecha")` string paths across scripts.
func get_player_mecha() -> Node3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("Mecha") as Node3D


func transition_to(new_state: State) -> void:
	get_tree().paused = false
	var old_name = State.keys()[current_state]
	current_state = new_state
	var new_name = State.keys()[new_state]
	EventBus.game_state_changed.emit(old_name, new_name)


func enter_board() -> void:
	get_tree().change_scene_to_file("res://scenes/board/game_board.tscn")
	transition_to(State.BOARD)


var combat_node_type: String = "grunt"


func enter_combat(combat_type: String = "grunt") -> void:
	combat_node_type = combat_type
	is_boss_combat = (combat_type == "boss")
	is_escaping = false
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")
	transition_to(State.COMBAT)
	EventBus.combat_intensity_changed.emit(1.0)
	AudioManager.play_combat_music(combat_type)


func advance_to_next_sector() -> void:
	is_boss_combat = false
	GlobalData.current_sector += 1
	GlobalData.current_tile = Vector2i.ZERO
	GlobalData.board_seed = randi()
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
	get_tree().change_scene_to_file("res://scenes/ui/hangar_scene.tscn")
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
