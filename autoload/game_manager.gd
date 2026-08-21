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
	# The intermission music is bound to the board state, not to the UI panel:
	# it plays (or resumes the saved track) every time the board becomes the
	# active state, so a popup that stays on the board never restarts it.
	AudioManager.play_intermission_music()


var combat_node_type: String = "grunt"


func enter_combat(combat_type: String = "grunt") -> void:
	combat_node_type = combat_type
	is_boss_combat = (combat_type == "boss")
	is_escaping = false
	# A wounded driver never pilots into battle: if the active mech's pilot is
	# recovering, park that berth and switch to a healthy backup before the
	# combat scene loads. Only on real board/event entries — eject re-boarding
	# (the pilot climbing back into a specific machine) must never be overridden.
	if current_state == State.BOARD:
		var swapped_id := HangarManager.auto_park_wounded_active()
		if swapped_id != "":
			GlobalData.save_run()
			var name := str(HangarManager.get_active_mech().get("name", "the backup mech"))
			GlobalData.board.run_notice = "The piloted mech's driver was wounded, so it was parked. You're piloting %s instead." % name
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")
	transition_to(State.COMBAT)
	EventBus.combat_intensity_changed.emit(1.0)
	AudioManager.play_combat_music(combat_type)


func advance_to_next_sector() -> void:
	is_boss_combat = false
	GlobalData.board.current_sector += 1
	GlobalData.board.current_tile = Vector2i.ZERO
	GlobalData.board.board_seed = randi()
	GlobalData.board.board_day = 1
	GlobalData.board.board_mp = GlobalData.board.board_mp_max
	GlobalData.board.board_objective_id = BoardConfig.get_objective(BoardConfig.theme_for_sector(GlobalData.board.current_sector))["id"]
	GlobalData.board.board_objective_progress = 0
	GlobalData.board.board_objective_required = BoardConfig.get_objective(BoardConfig.theme_for_sector(GlobalData.board.current_sector))["required"]
	GlobalData.board.board_objective_intro_consumed = false
	GlobalData.board.board_patrols.clear()
	GlobalData.board.board_patrol_engagement = -1
	# Route through HeatWantedSystem so the HUD signals, wanted escalation floor
	# and enemy mobilization capacity all stay in sync (never mutate directly).
	HeatWantedSystem.modify_heat(-2)
	HeatWantedSystem.escalate_wanted(1, 5)
	GlobalData.save_run()
	EventBus.combat_intensity_changed.emit(0.0)
	AudioManager.stop_music()
	get_tree().change_scene_to_file("res://scenes/board/game_board.tscn")
	transition_to(State.BOARD)
	AudioManager.play_intermission_music()


func return_to_board() -> void:
	is_boss_combat = false
	GlobalData.save_run()
	EventBus.combat_intensity_changed.emit(0.0)
	AudioManager.stop_music()
	get_tree().change_scene_to_file("res://scenes/board/game_board.tscn")
	transition_to(State.BOARD)
	AudioManager.play_intermission_music()


func enter_safehouse() -> void:
	transition_to(State.SAFEHOUSE)


func enter_hangar() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/hangar_scene.tscn")
	transition_to(State.HANGAR)


func enter_eject() -> void:
	transition_to(State.EJECT)


# Re-boarding after eject: return to the CURRENT battle in place. Unlike
# enter_combat() this deliberately does NOT change scene — reloading the
# combat world would restart the whole fight (new arena, respawned enemies),
# kicking the player out of the battle they were in.
func resume_combat() -> void:
	transition_to(State.COMBAT)


func game_over() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	transition_to(State.MENU)


func end_run(victory: bool) -> void:
	EventBus.run_ended.emit(victory)
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	transition_to(State.MENU)
