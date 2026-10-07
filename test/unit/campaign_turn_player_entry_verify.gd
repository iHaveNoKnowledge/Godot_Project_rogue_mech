extends Node
## PHASE 5W CAMPAIGN TURN PLAYER ENTRY v1 VERIFY.
##
## Proves the player-facing campaign turn completion contract:
##   - UI reads current canonical turn from CampaignTurnExecutive (A)
##   - Player-facing End Turn control exists and is wired (B)
##   - End Turn calls CampaignTurnExecutive directly without bypass (C)
##   - UI does NOT call individual turn phases directly (D)
##   - Successful turn advance: Turn N -> N+1 (E)
##   - Exactly once: one action advances exactly one turn (F)
##   - Re-entry protection from executive remains effective (G)
##   - UI displays canonical executive receipt (H)
##   - Full loop: Move -> End Turn works (I)
##   - Full loop: Inspect -> End Turn works (J)
##   - Inspection refreshes canonical state after turn (K)
##   - CampaignForce preserved: no unintended force mutations (L)
##   - CampaignTerritory preserved: no unintended territory mutations (M)
##   - CampaignBase preserved: no unintended base mutations (N)
##   - CampaignBattle preserved: no battles created/resolved (O)
##   - Faction relations preserved: no allegiance/relation shifts (P)
##   - No supply state created (Q)
##   - No detection state created (R)
##   - No orders state created (S)
##   - No Player Force fabricated (T)
##   - Save/load preserves turn progression (U)
##   - Reset clears turn and UI cleanly (V)
##   - Fresh UI instance has no stale receipt/turn state (W)
##   - Confirmation & multiple click guard (X)
##   - Source text guards on production UI script

const CITY := "node_s1_city_2_2"
const SAFE := "node_s1_safehouse_2_3"

const TurnPanelScript = preload("res://scripts/ui/campaign_turn_panel.gd")
const MovePanelScript = preload("res://scripts/ui/campaign_force_movement_panel.gd")
const InspectPanelScript = preload("res://scripts/ui/campaign_node_inspection_panel.gd")

var _fails: int = 0
var _checks: int = 0
var _backup: String = ""
var _turn_panel: Control
var _move_panel: Control
var _inspect_panel: Control


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("TURN_ENTRY OK: " + name)
	else:
		_fails += 1
		printerr("TURN_ENTRY FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()

	_turn_panel = TurnPanelScript.new()
	add_child(_turn_panel)
	_move_panel = MovePanelScript.new()
	add_child(_move_panel)
	_inspect_panel = InspectPanelScript.new()
	add_child(_inspect_panel)
	await get_tree().process_frame

	_test_turn_display_and_widgets()
	_test_executive_call_and_single_advance()
	_test_reentry_protection()
	_test_confirmation_flow()
	_test_composition_with_movement_and_inspection()
	_test_side_effects_isolation()
	_test_save_load_persistence()
	_test_reset_and_fresh_instance()
	_test_source_guards()

	_turn_panel.queue_free()
	_move_panel.queue_free()
	_inspect_panel.queue_free()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()

	print("CAMPAIGN_TURN_PLAYER_ENTRY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_TURN_PLAYER_ENTRY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CAMPAIGN_TURN_PLAYER_ENTRY_TESTS_PASSED")
		get_tree().quit(0)


func _seed_world() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTurnExecutive.reset()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "safehouse")
	CampaignNodeRegistry.register_route(CITY, SAFE)

	CampaignTerritory.register_territory("terr_s1_test", [CITY, SAFE])
	CampaignBase.register_base("base_s1_test", CITY, "OUTPOST")

	CampaignForce.register_force("force_alpha", "PATROL", "federation", CITY, "", 3, 15)
	CampaignForce.register_force("force_beta", "CONVOY", "zeon", SAFE, "", 2, 8)


# Tests A, B, H
func _test_turn_display_and_widgets() -> void:
	_check(_turn_panel.get_current_turn() == 0, "[A] Turn display reads canonical turn (starts at 0)")
	var btn: Button = _turn_panel.get_node_or_null("TurnPanel/EndTurnButton")
	_check(btn != null, "[B] Player-facing EndTurnButton exists in UI tree")
	_check(not btn.disabled, "[B] EndTurnButton enabled when idle")

	var lbl: Label = _turn_panel.get_node_or_null("TurnPanel/TurnLabel")
	_check(lbl != null and lbl.text.contains("Turn: 0"), "[A] TurnLabel displays current turn 0")

	var lines: Array = _turn_panel.get_summary_lines()
	_check(lines.size() >= 1 and str(lines[0]).contains("Current Turn: 0"), "[H] Summary lines format current turn")


# Tests C, E, F, H
func _test_executive_call_and_single_advance() -> void:
	var turn_before: int = CampaignTurnExecutive.get_turn()
	var receipt: Dictionary = _turn_panel.end_turn("player_end_turn", {"day_boundary": true})

	_check(bool(receipt.get("ok", false)), "[C] End turn call returns ok receipt from CampaignTurnExecutive")
	_check(int(receipt.get("turn", 0)) == turn_before + 1, "[E] Turn advanced exactly from N to N+1")
	_check(CampaignTurnExecutive.get_turn() == turn_before + 1, "[E] Executive canonical turn matches receipt")
	_check(_turn_panel.get_current_turn() == turn_before + 1, "[A] Panel current turn reflects advance")

	var stored_receipt: Dictionary = _turn_panel.get_last_receipt()
	_check(int(stored_receipt.get("turn", 0)) == turn_before + 1, "[H] Panel stores canonical receipt")
	_check(str(stored_receipt.get("reason", "")) == "player_end_turn", "[C] Receipt carries reason string")

	var phases: Array = stored_receipt.get("phases", [])
	_check(phases.has("begin_turn") and phases.has("end_turn"), "[C] Receipt carries canonical turn phase sequence")

	var status_lbl: Label = _turn_panel.get_node_or_null("TurnPanel/StatusLabel")
	_check(status_lbl != null and status_lbl.text.contains("Turn 1 completed"), "[H] Status label reflects completed turn")


# Tests G, X
func _test_reentry_protection() -> void:
	var turn_before: int = _turn_panel.get_current_turn()
	CampaignTurnExecutive._executing = true

	var reject_receipt: Dictionary = _turn_panel.end_turn("reentrant_click", {})
	_check(not bool(reject_receipt.get("ok", true)), "[G] Nested or in-flight end_turn rejected")
	_check(str(reject_receipt.get("error", "")) == "reentrant", "[G] Rejection returns canonical reentrant error")
	_check(_turn_panel.get_current_turn() == turn_before, "[X] Reentrant attempt advances zero turns")

	CampaignTurnExecutive._executing = false
	_turn_panel.refresh()
	_check(_turn_panel.get_current_turn() == turn_before, "[G] Counter unchanged after clearing simulated lock")


# Tests X (Confirmation)
func _test_confirmation_flow() -> void:
	_turn_panel.set_requires_confirmation(true)
	_check(_turn_panel.requires_confirmation(), "[X] requires_confirmation enabled")
	_check(not _turn_panel.is_confirming(), "[X] initially not confirming")

	var turn_before: int = _turn_panel.get_current_turn()
	var req_receipt: Dictionary = _turn_panel.end_turn("first_press")
	_check(not bool(req_receipt.get("ok", true)), "[X] First press with confirmation required does not advance")
	_check(str(req_receipt.get("reason", "")) == "confirmation_required", "[X] Receipt indicates confirmation_required")
	_check(_turn_panel.is_confirming(), "[X] Panel entered confirming state")
	_check(_turn_panel.get_current_turn() == turn_before, "[X] Zero turn advance before confirmation")

	# Cancel confirmation
	_turn_panel.cancel_confirmation()
	_check(not _turn_panel.is_confirming(), "[X] cancel_confirmation resets state")
	_check(_turn_panel.get_current_turn() == turn_before, "[X] Cancelled confirmation preserves turn")

	# Now perform confirmed turn
	var confirm_receipt: Dictionary = _turn_panel.confirm_end_turn("confirmed_press")
	_check(bool(confirm_receipt.get("ok", false)), "[X] confirm_end_turn completes turn")
	_check(_turn_panel.get_current_turn() == turn_before + 1, "[X] Confirmed turn advances to N+1")
	_check(not _turn_panel.is_confirming(), "[X] Confirming state cleared after completion")

	_turn_panel.set_requires_confirmation(false)


# Tests I, J, K
func _test_composition_with_movement_and_inspection() -> void:
	# 1. Inspect before movement & turn
	var insp1: Dictionary = _inspect_panel.inspect_node(CITY)
	_check(bool(insp1.get("ok", false)), "[J] Node inspection succeeds before turn")
	var forces_at_city: Array = insp1.get("forces", [])
	_check(forces_at_city.size() == 1 and str((forces_at_city[0] as Dictionary).get("id", "")) == "force_alpha",
		"[J] Inspection reads force_alpha at CITY")

	# 2. Movement before turn
	_move_panel.select_force("force_alpha")
	_move_panel.select_destination(SAFE)
	var move_res: Dictionary = _move_panel.execute_move()
	_check(bool(move_res.get("ok", false)), "[I] Move before turn succeeds")
	_check(str(CampaignForce.get_force("force_alpha").get("node_id", "")) == SAFE,
		"[I] force_alpha moved to SAFE")

	# 3. End turn after movement
	var turn_before: int = _turn_panel.get_current_turn()
	var turn_res: Dictionary = _turn_panel.end_turn("post_move_end_turn")
	_check(bool(turn_res.get("ok", false)), "[I] End turn succeeds after movement")
	_check(_turn_panel.get_current_turn() == turn_before + 1, "[I] Turn increments after movement")

	# 4. Re-inspect after turn (K)
	_inspect_panel.refresh()
	var insp2: Dictionary = _inspect_panel.inspect_node(SAFE)
	_check(bool(insp2.get("ok", false)), "[K] Node inspection succeeds after turn")
	var forces_at_safe: Array = insp2.get("forces", [])
	var force_ids: Array = []
	for f in forces_at_safe:
		force_ids.append(str((f as Dictionary).get("id", "")))
	_check(force_ids.has("force_alpha") and force_ids.has("force_beta"),
		"[K] Inspection after turn accurately reflects both forces at SAFE")


# Tests L, M, N, O, P, Q, R, S, T
func _test_side_effects_isolation() -> void:
	var f_alpha_before: Dictionary = CampaignForce.get_force("force_alpha")
	var terr_before: Dictionary = CampaignTerritory.get_territory("terr_s1_test")
	var base_before: Dictionary = CampaignBase.get_base("base_s1_test")
	var battle_count_before: int = CampaignBattle.get_battles().size()

	_turn_panel.end_turn("isolation_check_turn")

	var f_alpha_after: Dictionary = CampaignForce.get_force("force_alpha")
	_check(int(f_alpha_after.get("unit_count", 0)) == int(f_alpha_before.get("unit_count", 0)),
		"[L] unit_count preserved (no attrition)")
	_check(int(f_alpha_after.get("strength", 0)) == int(f_alpha_before.get("strength", 0)),
		"[L] strength preserved (no casualty)")
	_check(int(f_alpha_after.get("state", -1)) == int(f_alpha_before.get("state", -1)),
		"[L] operational state preserved")
	_check(str(f_alpha_after.get("faction", "")) == str(f_alpha_before.get("faction", "")),
		"[P] faction allegiance untouched")
	_check(not f_alpha_after.has("supply") and not f_alpha_after.has("supplies"),
		"[Q] No supply fields on force")
	_check(not f_alpha_after.has("detection") and not f_alpha_after.has("detected"),
		"[R] No detection fields on force")
	_check(not f_alpha_after.has("orders") and not f_alpha_after.has("order"),
		"[S] No order fields on force")

	var terr_after: Dictionary = CampaignTerritory.get_territory("terr_s1_test")
	_check(int(terr_after.get("control", -1)) == int(terr_before.get("control", -1)),
		"[M] Territory control state unchanged by turn")

	var base_after: Dictionary = CampaignBase.get_base("base_s1_test")
	_check(int(base_after.get("state", -1)) == int(base_before.get("state", -1)),
		"[N] Base state unchanged by turn")

	_check(CampaignBattle.get_battles().size() == battle_count_before,
		"[O] Zero battles created by turn")

	# No player force
	for f in CampaignForce.get_forces():
		var fid: String = str((f as Dictionary).get("id", ""))
		_check(not fid.begins_with("player") and not fid.begins_with("hangar"),
			"[T] No PlayerForce fabricated")


# Tests U, V, W
func _test_save_load_persistence() -> void:
	var turn_saved: int = _turn_panel.get_current_turn()
	_check(SaveGameIO.save_run(), "[U] Save run succeeds")

	CampaignTurnExecutive.reset()
	_turn_panel.refresh()
	_check(_turn_panel.get_current_turn() == 0, "[V] Reset returns canonical starting state 0")

	_check(SaveGameIO.load_run(), "[U] Load run succeeds")
	_turn_panel.refresh()
	_check(_turn_panel.get_current_turn() == turn_saved, "[U] Turn survives save/load exactly")


func _test_reset_and_fresh_instance() -> void:
	var fresh_panel: Control = TurnPanelScript.new()
	add_child(fresh_panel)
	_check(fresh_panel.get_last_receipt().is_empty(), "[W] Fresh UI instance has empty receipt")
	_check(not fresh_panel.is_confirming(), "[W] Fresh UI instance is not in confirming state")
	_check(fresh_panel.get_current_turn() == CampaignTurnExecutive.get_turn(),
		"[W] Fresh UI reads current executive turn")
	fresh_panel.queue_free()


# Test D & Source text guards
func _test_source_guards() -> void:
	var file := FileAccess.open("res://scripts/ui/campaign_turn_panel.gd", FileAccess.READ)
	_check(file != null, "campaign_turn_panel.gd accessible for audit")
	if file != null:
		var content := file.get_as_text()
		file.close()

		# Guard against bypassing CampaignTurnExecutive
		_check(not content.contains("_advance_calendar_day"),
			"[D] UI does not call BoardManager._advance_calendar_day")
		_check(not content.contains("advance_day_economy"),
			"[D] UI does not call FactionEconomySystem directly")
		_check(not content.contains("roll_spy_event"),
			"[D] UI does not call EnemyFactionSystem spy directly")
		_check(not content.contains("advance_rival_turn"),
			"[D] UI does not call RivalProgressionSystem directly")
		_check(not content.contains("advance_war_turn"),
			"[D] UI does not call EraProgressionSystem directly")
		_check(not content.contains("advance_turn"),
			"[D] UI does not call ScavengerSystem directly")
		_check(not content.contains("CampaignTurnExecutive.new"),
			"[D] UI does not instantiate CampaignTurnExecutive.new()")
		_check(content.contains("CampaignTurnExecutive.advance_campaign_turn"),
			"[C] UI calls CampaignTurnExecutive.advance_campaign_turn")
