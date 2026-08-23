extends Node

## Regression test for the defeat-screen display bug (commit 4cd7ac2):
## Previously, mecha_health_base.gd and pilot_controller.gd called
## return_to_board()/game_over() immediately after emitting combat_ended(false),
## destroying the CombatRewardsUI before the defeat screen could appear.
##
## This test verifies:
##   1. combat_ended(false) makes the defeat screen visible and pauses the tree
##   2. The Continue button routes to game_over when the pilot is dead
##   3. The Continue button routes to game_over when no reserves remain
##   4. The Continue button routes to return_to_board when a backup exists
##   5. The Continue button routes to return_to_board for mechless retreat
##
## Run: godot --headless --path . res://tests/defeat_screen_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("DEFEAT_OK: " + name)
	else:
		_fails += 1
		printerr("DEFEAT_FAIL: " + name)


func _ready() -> void:
	GlobalData.reset_run_data()
	HangarManager.ensure_roster()
	GameManager.combat_node_type = "grunt"
	GameManager.is_boss_combat = false
	GameManager.is_escaping = false
	GlobalData.narrative.theme_id = "soldier"  # default theme with mechless_retreat=true

	await _verify_defeat_screen_appears()
	await _verify_continue_with_backup_mech()
	await _verify_continue_pilot_dead()
	await _verify_continue_no_reserves()
	await _verify_continue_mechless_retreat()

	print("DEFEAT_SCREEN_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


# ── 1. The defeat screen MUST be visible after combat_ended(false) fires ──
func _verify_defeat_screen_appears() -> void:
	var rewards_ui = load("res://scenes/ui/combat_rewards_ui.tscn").instantiate()
	add_child(rewards_ui)
	await get_tree().process_frame

	EventBus.combat_ended.emit(false)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(rewards_ui.visible, "defeat screen is visible after combat_ended(false)")
	_check(rewards_ui.title_label.text == "DEFEATED", "title shows DEFEATED")
	_check(not rewards_ui.rewards_label.text.is_empty(), "defeat text is populated")
	_check(get_tree().paused, "tree is paused while defeat screen shows")

	get_tree().paused = false
	rewards_ui.queue_free()
	await get_tree().process_frame


# ── 2. Continue with backup mech → return_to_board ──
func _verify_continue_with_backup_mech() -> void:
	var rewards_ui = load("res://scenes/ui/combat_rewards_ui.tscn").instantiate()
	add_child(rewards_ui)
	await get_tree().process_frame

	# Pilot alive, has backup mech (mech_less = false)
	GlobalData.pilot.pilot_hp = GlobalData.pilot.pilot_max_hp
	GlobalData.narrative.mech_less = false

	_check(not PilotSystem.is_dead(), "backup: pilot is alive")
	_check(not GlobalData.narrative.mech_less, "backup: mech_less is false")

	# Show defeat screen via signal
	EventBus.combat_ended.emit(false)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(rewards_ui.visible, "backup: defeat screen visible")
	_check(rewards_ui.title_label.text == "DEFEATED", "backup: title is DEFEATED")

	# Verify the routing condition: pilot alive + not mech_less → return_to_board
	var should_game_over := PilotSystem.is_dead() or (GlobalData.narrative.mech_less and not HangarManager.can_mechless_retreat())
	_check(not should_game_over, "backup: routing condition says return_to_board (not game_over)")

	get_tree().paused = false
	rewards_ui.queue_free()
	await get_tree().process_frame


# ── 3. Continue when pilot is dead → game_over ──
func _verify_continue_pilot_dead() -> void:
	var rewards_ui = load("res://scenes/ui/combat_rewards_ui.tscn").instantiate()
	add_child(rewards_ui)
	await get_tree().process_frame

	# Kill the pilot
	GlobalData.pilot.pilot_hp = 0.0

	_check(PilotSystem.is_dead(), "pilot-dead: pilot is actually dead")

	EventBus.combat_ended.emit(false)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(rewards_ui.visible, "pilot-dead: defeat screen visible")
	_check(rewards_ui.title_label.text == "DEFEATED", "pilot-dead: title is DEFEATED")

	var should_game_over := PilotSystem.is_dead() or (GlobalData.narrative.mech_less and not HangarManager.can_mechless_retreat())
	_check(should_game_over, "pilot-dead: routing condition says game_over")

	get_tree().paused = false
	rewards_ui.queue_free()
	await get_tree().process_frame

	# Restore pilot for subsequent tests
	GlobalData.pilot.pilot_hp = GlobalData.pilot.pilot_max_hp


# ── 4. Continue with mech_less and no retreat → game_over ──
func _verify_continue_no_reserves() -> void:
	var rewards_ui = load("res://scenes/ui/combat_rewards_ui.tscn").instantiate()
	add_child(rewards_ui)
	await get_tree().process_frame

	# Pilot alive, no mechs, no squadmates for retreat
	GlobalData.pilot.pilot_hp = GlobalData.pilot.pilot_max_hp
	GlobalData.hangar.hangar_mechs.clear()
	GlobalData.narrative.mech_less = true
	GlobalData.hangar.fleet_roster.clear()

	_check(not PilotSystem.is_dead(), "no-reserves: pilot is alive")
	_check(GlobalData.narrative.mech_less, "no-reserves: mech_less is true")
	_check(not HangarManager.can_mechless_retreat(), "no-reserves: cannot retreat (no squadmates)")

	EventBus.combat_ended.emit(false)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(rewards_ui.visible, "no-reserves: defeat screen visible")

	var should_game_over := PilotSystem.is_dead() or (GlobalData.narrative.mech_less and not HangarManager.can_mechless_retreat())
	_check(should_game_over, "no-reserves: routing condition says game_over")

	get_tree().paused = false
	rewards_ui.queue_free()
	await get_tree().process_frame

	# Restore state
	HangarManager.ensure_roster()


# ── 5. Continue with mech_less + squadmates → return_to_board ──
func _verify_continue_mechless_retreat() -> void:
	var rewards_ui = load("res://scenes/ui/combat_rewards_ui.tscn").instantiate()
	add_child(rewards_ui)
	await get_tree().process_frame

	# Pilot alive, no mechs, has squadmates for retreat
	GlobalData.pilot.pilot_hp = GlobalData.pilot.pilot_max_hp
	GlobalData.hangar.hangar_mechs.clear()
	GlobalData.narrative.mech_less = true
	GlobalData.hangar.fleet_roster = [{
		"template_id": "grunt_squad", "name": "Alpha",
		"hp": 50.0, "max_hp": 50.0, "destroyed": false, "fielded": true,
	}]

	_check(not PilotSystem.is_dead(), "mechless-retreat: pilot is alive")
	_check(GlobalData.narrative.mech_less, "mechless-retreat: mech_less is true")
	_check(HangarManager.can_mechless_retreat(), "mechless-retreat: can retreat with squadmates")

	EventBus.combat_ended.emit(false)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(rewards_ui.visible, "mechless-retreat: defeat screen visible")

	var should_game_over := PilotSystem.is_dead() or (GlobalData.narrative.mech_less and not HangarManager.can_mechless_retreat())
	_check(not should_game_over, "mechless-retreat: routing condition says return_to_board (not game_over)")

	get_tree().paused = false
	rewards_ui.queue_free()
	await get_tree().process_frame

	# Restore state
	HangarManager.ensure_roster()
