extends Node

enum State { MENU, BOARD, COMBAT, SAFEHOUSE, HANGAR, EJECT, PILOT, WAR }

var current_state: State = State.MENU


var is_boss_combat: bool = false

# True while the player is abandoning a battle via an escape zone, so the
# death/defeat path can't fire at the same time as the retreat.
var is_escaping: bool = false

## Optional flag to suppress scene change during unit tests
var suppress_scene_change: bool = false

var active_player_mecha: Node3D = null


# Central lookup for the active player mecha. Supports dynamic mech switching in combat.
func get_player_mecha() -> Node3D:
	if active_player_mecha and is_instance_valid(active_player_mecha):
		return active_player_mecha
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var m = scene.get_node_or_null("Mecha") as Node3D
	if m and is_instance_valid(m):
		active_player_mecha = m
		return m
	var mechas = get_tree().get_nodes_in_group("mecha")
	for mech in mechas:
		if is_instance_valid(mech) and not mech.has_meta("is_unoccupied") and not mech.has_meta("is_parked"):
			active_player_mecha = mech
			return mech
	return null


func transition_to(new_state: State) -> void:
	get_tree().paused = false
	var old_name = State.keys()[current_state]
	current_state = new_state
	var new_name = State.keys()[new_state]
	EventBus.game_state_changed.emit(old_name, new_name)


func enter_board() -> void:
	# Ensure hangar edits are flushed to the roster before leaving hangar (so board->combat keeps the same loadout)
	if current_state == State.HANGAR:
		HangarManager.save_active()
	# Deferred to avoid Vulkan swap_chain_resize ERR_CANT_CREATE when called
	# from input_event (_on_input_event → move_to_tile → _request_combat) or
	# physics. Immediate change_scene during input can tear down the viewport
	# while the driver is still presenting.
	if not suppress_scene_change:
		get_tree().call_deferred("change_scene_to_file", "res://scenes/board/game_board.tscn")
	transition_to(State.BOARD)
	# The intermission music is bound to the board state, not to the UI panel:
	# it plays (or resumes the saved track) every time the board becomes the
	# active state, so a popup that stays on the board never restarts it.
	AudioManager.play_intermission_music()


func enter_node_map() -> void:
	if current_state == State.HANGAR:
		HangarManager.save_active()
	if not suppress_scene_change:
		get_tree().call_deferred("change_scene_to_file", "res://scenes/ui/campaign_node_map.tscn")
	transition_to(State.BOARD)
	AudioManager.play_intermission_music()


var combat_node_type: String = "grunt"
var combat_fleet_count: int = 1


func enter_combat(combat_type: String = "grunt") -> void:
	combat_node_type = combat_type
	is_boss_combat = (combat_type == "boss")
	is_escaping = false
	GlobalData._combat_xp_awarded = false
	SpawnManager.reset_fallback_state()
	# Ensure carry/left/right not lost on the way to battle: if GlobalData's working set is empty but the active hangar berth has a loadout, restore it
	var active_mech := HangarManager.get_active_mech()
	if active_mech and active_mech.has("weapon_loadout"):
		var saved_loadout: Dictionary = active_mech.get("weapon_loadout", {})
		var cur_loadout: Dictionary = GlobalData.weapons.weapon_loadout
		for hand in ["left", "right"]:
			if str(cur_loadout.get(hand, "")) == "" and str(saved_loadout.get(hand, "")) != "":
				cur_loadout[hand] = saved_loadout[hand]
		var cur_carry = cur_loadout.get("carry", [])
		var saved_carry = saved_loadout.get("carry", [])
		if cur_carry is Array and saved_carry is Array and cur_carry.is_empty() and not saved_carry.is_empty():
			cur_loadout["carry"] = saved_carry.duplicate(true)
		var cur_ammo = cur_loadout.get("ammo", {})
		var saved_ammo = saved_loadout.get("ammo", {})
		if cur_ammo is Dictionary and saved_ammo is Dictionary and cur_ammo.is_empty() and not saved_ammo.is_empty():
			cur_loadout["ammo"] = saved_ammo.duplicate(true)
	# Preserve loadout so it isn't thrown into inventory after battle (user request: stay equipped)
	GlobalData.pre_combat_weapon_loadout = GlobalData.weapons.weapon_loadout.duplicate(true)
	var _ec_l := str(GlobalData.weapons.weapon_loadout.get("left", ""))
	var _ec_r := str(GlobalData.weapons.weapon_loadout.get("right", ""))
	var _ec_c = GlobalData.weapons.weapon_loadout.get("carry", [])
	var _ec_cn := (_ec_c as Array).size() if _ec_c is Array else -1
	print("[LOADOUT] enter_combat(%s): hands=(%s,%s) carry=%d" % [combat_type, _ec_l, _ec_r, _ec_cn])

	# Resolve how many fleets are engaged from the board token
	if GlobalData.board.board_patrol_engagement >= 0:
		var p: Dictionary = PatrolSystem.get_patrol_by_id(GlobalData.board.board_patrol_engagement)
		if not p.is_empty():
			combat_fleet_count = maxi(int(p.get("fleet_count", 1)), 1)
		else:
			combat_fleet_count = 1
	else:
		combat_fleet_count = 1
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
	if not suppress_scene_change:
		get_tree().call_deferred("change_scene_to_file", "res://scenes/game_world.tscn")
	transition_to(State.COMBAT)
	EventBus.combat_intensity_changed.emit(1.0)
	AudioManager.play_combat_music(combat_type, 1.5, false, str(GlobalData.board.board_theme_id))


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
	# Fresh sector = fresh mission: clear the previous contract so the board
	# shows the select screen once, then tiles until extraction/boss.
	GlobalData.board.active_contract.clear()
	GlobalData.board.primary_objective_done = false
	GlobalData.board.secondary_objectives_status.clear()
	GlobalData.board.extraction_zone_pos = Vector2i(-1, -1)
	GlobalData.board.extraction_unlocked = false
	GlobalData.board.mission_step_count = 0
	GlobalData.board.board_patrols.clear()
	GlobalData.board.board_patrol_engagement = -1
	# Route through HeatWantedSystem so the HUD signals, wanted escalation floor
	# and enemy mobilization capacity all stay in sync (never mutate directly).
	HeatWantedSystem.modify_heat(-2)
	HeatWantedSystem.escalate_wanted(1, 5)
	HangarManager.save_active()
	GlobalData.save_run()
	EventBus.combat_intensity_changed.emit(0.0)
	AudioManager.stop_music()
	if not suppress_scene_change:
		get_tree().call_deferred("change_scene_to_file", "res://scenes/board/game_board.tscn")
	transition_to(State.BOARD)
	AudioManager.play_intermission_music()


func return_to_board() -> void:
	is_boss_combat = false
	HangarManager.save_active()
	GlobalData.save_run()
	EventBus.combat_intensity_changed.emit(0.0)
	AudioManager.stop_music()
	if not suppress_scene_change:
		get_tree().call_deferred("change_scene_to_file", "res://scenes/board/game_board.tscn")
	transition_to(State.BOARD)
	AudioManager.play_intermission_music()


func return_to_node_map() -> void:
	is_boss_combat = false
	HangarManager.save_active()
	GlobalData.save_run()
	EventBus.combat_intensity_changed.emit(0.0)
	AudioManager.stop_music()
	if not suppress_scene_change:
		get_tree().call_deferred("change_scene_to_file", "res://scenes/ui/campaign_node_map.tscn")
	transition_to(State.BOARD)
	AudioManager.play_intermission_music()


func enter_safehouse() -> void:
	transition_to(State.SAFEHOUSE)


func enter_hangar() -> void:
	# Flush the current working-set weapon loadout (which sync_loadout_to_global
	# may have updated after the last combat) into the active mech's roster entry
	# BEFORE the scene changes. This ensures load_mech_state() in the customize
	# page always restores the correct post-combat weapon state.
	HangarManager.save_active()
	get_tree().call_deferred("change_scene_to_file", "res://scenes/ui/hangar_scene.tscn")
	transition_to(State.HANGAR)


func enter_eject() -> void:
	transition_to(State.EJECT)


func enter_war() -> void:
	if current_state == State.HANGAR:
		HangarManager.save_active()
	get_tree().call_deferred("change_scene_to_file", "res://scenes/war/war_world.tscn")
	transition_to(State.WAR)
	AudioManager.play_combat_music("war")


func return_to_menu() -> void:
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main_menu/main_menu.tscn")
	transition_to(State.MENU)
	AudioManager.play_menu_music()


func enter_eject_war() -> void:
	transition_to(State.EJECT)


# Re-boarding after eject: return to the CURRENT battle in place. Unlike
# enter_combat() this deliberately does NOT change scene — reloading the
# combat world would restart the whole fight (new arena, respawned enemies),
# kicking the player out of the battle they were in.
func resume_combat() -> void:
	transition_to(State.COMBAT)


func game_over() -> void:
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main_menu/main_menu.tscn")
	transition_to(State.MENU)


func end_run(victory: bool) -> void:
	EventBus.run_ended.emit(victory)
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main_menu/main_menu.tscn")
	transition_to(State.MENU)
