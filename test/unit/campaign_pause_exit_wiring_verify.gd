class_name CampaignPauseExitWiringVerify
extends Node

## ---------------------------------------------------------------------------
## GATE 3D — PAUSE EXIT WIRING & BASE DEFENSE RECOVERY VERIFICATION.
## Tests-only; zero production changes.
##
##   A. Pause UI wiring: the REAL buttons built by pause_menu.gd are connected
##      to _on_abandon / _on_main_menu / _on_restart, and pressing Abandon /
##      Main Menu clears only the Attack pending slot through the production
##      funnels (no fabricated outcome, Defense untouched). Restart is
##      wiring-only: invoking it would reload this test scene.
##   B. Defense abandon recovery: signal-less abandon preserves the Defense
##      engagement; Attack entry is mutex-blocked; re-dispatching Defend
##      through the production handler rebinds the SAME battle (no duplicate).
##   C. Fallback-guard reset: a prior encounter's static fallback-completion
##      state is cleared by real combat entry (enter_combat), so it cannot
##      suppress the new encounter's fallback.
## ---------------------------------------------------------------------------

const PauseMenuScript = preload("res://scripts/ui/pause_menu.gd")
const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")

var _total_assertions: int = 0
var _passed_assertions: int = 0
var _failed_assertions: int = 0
var _save_backup := ""
var _ended_count := 0
var _escaped_count := 0


func _ready() -> void:
	print("--- BEGIN GATE 3D PAUSE EXIT WIRING VERIFY ---")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _assert_true(condition: bool, message: String) -> void:
	_total_assertions += 1
	if condition:
		_passed_assertions += 1
	else:
		_failed_assertions += 1
		printerr("FAIL: " + message)


func _assert_false(condition: bool, message: String) -> void:
	_assert_true(not condition, message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_total_assertions += 1
	if actual == expected:
		_passed_assertions += 1
	else:
		_failed_assertions += 1
		printerr("FAIL: %s | Expected: %s, Got: %s" % [message, str(expected), str(actual)])


func _setup_clean_campaign_environment() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTurnExecutive.reset()
	FactionSystem.reset_relations()
	FactionSystem.set_player_faction("federation")
	CampaignBaseDefense.reset_defense_state()
	CampaignAttackBridge.reset_attack_state()
	CampaignPlayerDispatch.clear_handlers()
	CampaignPlayerDispatch.register_default_handlers()
	# Headless: suppress real scene swaps (same pattern as the defend suite).
	GameManager.suppress_scene_change = true
	GlobalData.current_campaign_player_node_id = ""
	if GlobalData != null and GlobalData.board != null:
		GlobalData.board.current_sector = 1
		GlobalData.board.current_tile = Vector2i(0, 0)
		GlobalData.board.board_patrol_engagement = -1


## Live Defense engagement via direct domain calls (mirrors the defend-suite
## fixture): assaulted player base, intervention recorded. Returns context.
func _setup_live_defense(tag: String, tile: Vector2i) -> Dictionary:
	var node_id := CampaignNodeRegistry.register_node(1, tile, "safehouse")
	var terr_id := CampaignTerritory.register_territory("terr_" + tag, [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_" + tag, node_id, "OUTPOST", "federation", terr_id)
	var attacker_id := CampaignForce.register_force("force_zeon_" + tag, "PATROL", "zeon", node_id)
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	CampaignPlayerMovement.set_current_node_id(node_id)
	GlobalData.board.current_tile = tile
	var atk := CampaignBaseDefense.start_base_attack(base_id, attacker_id)
	if not bool(atk.get("ok", false)):
		_assert_true(false, "setup defense assault for %s" % tag)
		return {}
	var battle_id := str(atk.get("battle_id", ""))
	if not bool(CampaignBaseDefense.intervene(battle_id).get("ok", false)):
		_assert_true(false, "setup defense intervene for %s" % tag)
		return {}
	if not CampaignBaseDefense.record_defense_engagement(battle_id, base_id):
		_assert_true(false, "setup defense record for %s" % tag)
		return {}
	CampaignBaseDefense.ensure_defense_result_hook()
	return {"node_id": node_id, "base_id": base_id, "battle_id": battle_id,
		"attacker_id": attacker_id}


## Live Attack engagement via direct domain calls. Returns context.
func _setup_live_attack(tag: String, tile: Vector2i) -> Dictionary:
	var node_id := CampaignNodeRegistry.register_node(1, tile, "city")
	var fid := CampaignForce.register_force("force_zeon_" + tag, "PATROL", "zeon", node_id)
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	var battle_id := CampaignBattle.make_battle_id(1, "atk_" + node_id)
	CampaignBattle.register_battle(battle_id, node_id, [fid])
	CampaignBattle.prepare_launch(battle_id)
	if not CampaignAttackBridge.record_attack_engagement(battle_id, [fid]):
		_assert_true(false, "setup attack record for %s" % tag)
		return {}
	CampaignAttackBridge.ensure_attack_result_hook()
	return {"node_id": node_id, "battle_id": battle_id, "targets": [fid]}


func _take_state_snapshot() -> Dictionary:
	return {
		"credits": GlobalData.currency.credits if GlobalData and GlobalData.currency else 0,
		"scrap": GlobalData.currency.scrap if GlobalData and GlobalData.currency else 0,
		"battles": JSON.stringify(CampaignBattle.get_battles()),
		"forces": JSON.stringify(CampaignForce.get_forces()),
		"turn": CampaignTurnExecutive.get_turn(),
		"controller": "",
	}


func _on_bus_ended(_victory: bool) -> void:
	_ended_count += 1


func _on_bus_escaped() -> void:
	_escaped_count += 1


func _find_pause_button(pm: CanvasLayer, text: String) -> Button:
	for n in pm.find_children("*", "Button", true, false):
		var b := n as Button
		if b != null and b.text == text:
			return b
	return null


func _run_all_tests() -> void:
	_test_pause_button_wiring_and_abandon()
	_test_main_menu_wiring_and_cleanup()
	_test_defense_abandon_block_and_recovery()
	_test_fallback_guard_reset_on_entry()


# ---------------------------------------------------------------------------
# A. Real pause-button wiring + Abandon funnel behavior.
# ---------------------------------------------------------------------------
func _test_pause_button_wiring_and_abandon() -> void:
	_setup_clean_campaign_environment()
	# Co-live slots constructed directly (production entries forbid this via
	# the mutex) to prove the funnel clears ONLY the Attack-owned slot.
	var def := _setup_live_defense("pa_def", Vector2i(4, 4))
	var atk := _setup_live_attack("pa_atk", Vector2i(7, 7))
	var def_battle := str(def.get("battle_id", ""))
	var atk_battle := str(atk.get("battle_id", ""))
	var atk_fid := str((atk.get("targets", []) as Array)[0])

	var pm: CanvasLayer = PauseMenuScript.new()
	add_child(pm)
	# Real wiring proof: each production button is connected to its handler.
	var abandon_btn := _find_pause_button(pm, "Abandon Run")
	var menu_btn := _find_pause_button(pm, "Main Menu")
	var restart_btn := _find_pause_button(pm, "Restart Combat")
	_assert_true(abandon_btn != null, "A: Abandon Run button exists")
	_assert_true(menu_btn != null, "A: Main Menu button exists")
	_assert_true(restart_btn != null, "A: Restart Combat button exists")
	_assert_true(abandon_btn.pressed.is_connected(Callable(pm, "_on_abandon")),
		"A: Abandon button wired to _on_abandon")
	_assert_true(menu_btn.pressed.is_connected(Callable(pm, "_on_main_menu")),
		"A: Main Menu button wired to _on_main_menu")
	_assert_true(restart_btn.pressed.is_connected(Callable(pm, "_on_restart")),
		"A: Restart button wired to _on_restart (wiring only — invoking it would reload this scene)")

	# Emission counters prove no fabricated outcome leaves the funnel.
	_ended_count = 0
	_escaped_count = 0
	EventBus.combat_ended.connect(_on_bus_ended)
	EventBus.combat_escaped.connect(_on_bus_escaped)
	GameManager.transition_to(GameManager.State.COMBAT)

	# Press the REAL Abandon button (not the handler directly).
	abandon_btn.pressed.emit()
	_assert_eq(CampaignAttackBridge.get_pending_attack_battle_id(), "",
		"A: Abandon clears Attack pending through the funnel")
	_assert_eq(CampaignBaseDefense.get_pending_defense_battle_id(), def_battle,
		"A: Abandon leaves Defense pending untouched")
	_assert_eq(_ended_count, 0, "A: Abandon emits no victory/defeat")
	_assert_eq(_escaped_count, 0, "A: Abandon emits no escape")
	_assert_true(CampaignBattle.is_active(atk_battle),
		"A: Abandoned Attack battle stays ACTIVE")
	_assert_eq(CampaignForce.get_state(atk_fid), CampaignForce.ForceState.ACTIVE,
		"A: Attack target untouched by Abandon")
	_assert_true(CampaignBattle.is_active(def_battle),
		"A: Defense battle stays ACTIVE")
	_assert_eq(GameManager.current_state, GameManager.State.BOARD,
		"A: Abandon returns to board")

	EventBus.combat_ended.disconnect(_on_bus_ended)
	EventBus.combat_escaped.disconnect(_on_bus_escaped)
	pm.queue_free()
	GameManager.transition_to(GameManager.State.BOARD)


# ---------------------------------------------------------------------------
# A2. Real Main Menu button wiring + funnel behavior.
# ---------------------------------------------------------------------------
func _test_main_menu_wiring_and_cleanup() -> void:
	_setup_clean_campaign_environment()
	var def := _setup_live_defense("mm_def", Vector2i(4, 4))
	var atk := _setup_live_attack("mm_atk", Vector2i(7, 7))
	var def_battle := str(def.get("battle_id", ""))
	var atk_battle := str(atk.get("battle_id", ""))

	var pm: CanvasLayer = PauseMenuScript.new()
	add_child(pm)
	var menu_btn := _find_pause_button(pm, "Main Menu")
	_assert_true(menu_btn != null and menu_btn.pressed.is_connected(Callable(pm, "_on_main_menu")),
		"A2: Main Menu button wired to _on_main_menu")

	_ended_count = 0
	_escaped_count = 0
	EventBus.combat_ended.connect(_on_bus_ended)
	EventBus.combat_escaped.connect(_on_bus_escaped)
	GameManager.transition_to(GameManager.State.COMBAT)

	# Press the REAL Main Menu button (not the handler directly).
	menu_btn.pressed.emit()
	_assert_eq(CampaignAttackBridge.get_pending_attack_battle_id(), "",
		"A2: Main Menu clears Attack pending through game_over()")
	_assert_eq(CampaignBaseDefense.get_pending_defense_battle_id(), def_battle,
		"A2: Main Menu leaves Defense pending untouched")
	_assert_eq(_ended_count, 0, "A2: Main Menu emits no combat outcome")
	_assert_eq(_escaped_count, 0, "A2: Main Menu emits no escape")
	_assert_true(CampaignBattle.is_active(atk_battle),
		"A2: Abandoned Attack battle stays ACTIVE")
	_assert_eq(GameManager.current_state, GameManager.State.MENU,
		"A2: Main Menu reaches menu state")

	EventBus.combat_ended.disconnect(_on_bus_ended)
	EventBus.combat_escaped.disconnect(_on_bus_escaped)
	pm.queue_free()
	GameManager.transition_to(GameManager.State.BOARD)


# ---------------------------------------------------------------------------
# B. Defense abandon → Attack blocked → same-base Defend recovery.
# ---------------------------------------------------------------------------
func _test_defense_abandon_block_and_recovery() -> void:
	_setup_clean_campaign_environment()
	var def := _setup_live_defense("rec", Vector2i(4, 4))
	var home := str(def.get("node_id", ""))
	var base_id := str(def.get("base_id", ""))
	var def_battle := str(def.get("battle_id", ""))

	# 1-2. Signal-less abandon through the REAL production funnel.
	var pm: CanvasLayer = PauseMenuScript.new()
	add_child(pm)
	GameManager.transition_to(GameManager.State.COMBAT)
	_find_pause_button(pm, "Abandon Run").pressed.emit()
	pm.queue_free()
	_assert_eq(CampaignBaseDefense.get_pending_defense_battle_id(), def_battle,
		"B: Defense pending survives signal-less Abandon")
	_assert_true(CampaignBattle.is_active(def_battle),
		"B: Defense battle remains ACTIVE")
	_assert_eq(CampaignBattle.get_session_ref(def_battle),
		"session_intervention_" + def_battle, "B: Defense session marker intact")

	# 3-4. Far-node Attack through the real campaign handler is mutex-blocked.
	var far := CampaignNodeRegistry.register_node(1, Vector2i(7, 7), "city")
	CampaignForce.register_force("force_zeon_recfar", "PATROL", "zeon", far)
	CampaignPlayerMovement.set_current_node_id(far)
	GlobalData.board.current_tile = Vector2i(7, 7)
	# Snapshot AFTER far-side fixture setup, so the comparison isolates the
	# Abandon + re-intervention segment (the blocked dispatch is proven
	# mutation-free separately by the battle-count check below).
	var snap_before := _take_state_snapshot()
	snap_before["controller"] = str(CampaignBase.get_base(base_id).get("controller", ""))
	var battles_before := CampaignBattle.get_battles().size()
	var blocked := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("attack", far))
	_assert_false(bool(blocked.get("ok", false)), "B: Attack blocked during live Defense")
	_assert_eq(str(blocked.get("reason", "")), "defense_engagement_active",
		"B: Block reason is defense_engagement_active")
	_assert_eq(CampaignBattle.get_battles().size(), battles_before,
		"B: Blocked Attack creates no battle")

	# 5-6. Re-dispatch Defend through the production handler rebinds the SAME
	# battle instead of duplicating it.
	CampaignPlayerMovement.set_current_node_id(home)
	GlobalData.board.current_tile = Vector2i(4, 4)
	var redone := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("defend", home))
	_assert_true(bool(redone.get("ok", false)), "B: Re-Defend succeeds after Abandon")
	_assert_eq(str(redone.get("battle_id", "")), def_battle,
		"B: Recovery rebinds the same battle (no duplicate)")
	_assert_eq(CampaignBattle.get_battles().size(), battles_before,
		"B: No second battle registered")
	_assert_eq(CampaignBaseDefense.get_pending_defense_battle_id(), def_battle,
		"B: Defense pending still tracks the same battle")

	# 7. Hook registration stays single (no duplicate callbacks).
	CampaignBaseDefense.ensure_defense_result_hook()
	CampaignBaseDefense.ensure_defense_result_hook()
	var hook_count := 0
	for c in EventBus.combat_ended.get_connections():
		if str((c as Dictionary).get("callable", "")) == str(Callable(CampaignBaseDefense, "_on_defense_combat_ended")):
			hook_count += 1
	_assert_eq(hook_count, 1, "B: Defense result hook connected exactly once")

	# 8. Abandon + re-intervention changed no controller/turn/reward-adjacent state.
	var snap_after := _take_state_snapshot()
	snap_after["controller"] = str(CampaignBase.get_base(base_id).get("controller", ""))
	_assert_eq(snap_after, snap_before,
		"B: Abandon + re-intervention mutates no controller/turn/economy/battle state")

	# Resolution still applies exactly once afterwards (defense semantics intact).
	EventBus.combat_ended.emit(true)
	_assert_eq(CampaignBattle.get_state(def_battle), CampaignBattle.BattleState.RESOLVED,
		"B: Post-recovery victory resolves")
	var snap_mid := _take_state_snapshot()
	EventBus.combat_ended.emit(true)
	_assert_eq(_take_state_snapshot(), snap_mid, "B: Duplicate delivery changes nothing")
	GameManager.transition_to(GameManager.State.BOARD)


# ---------------------------------------------------------------------------
# C. Fallback-guard reset on real combat entry (no production changes).
# ---------------------------------------------------------------------------
func _test_fallback_guard_reset_on_entry() -> void:
	_setup_clean_campaign_environment()
	# Simulate a prior encounter's leftover static fallback-completion state.
	SpawnManager._completed_fallback_enemy_ids = {12345678: true}
	SpawnManager._fallback_empty_completed = true

	# Real production entry clears it.
	GameManager.enter_combat("grunt")
	_assert_true((SpawnManager._completed_fallback_enemy_ids as Dictionary).is_empty(),
		"C: Combat entry clears prior fallback enemy ids")
	_assert_false(bool(SpawnManager._fallback_empty_completed),
		"C: Combat entry clears prior fallback empty-completed flag")
	GameManager.transition_to(GameManager.State.BOARD)


func _restore_save_backup() -> void:
	CampaignAttackBridge.reset_attack_state()
	CampaignBaseDefense.reset_defense_state()
	GameManager.suppress_scene_change = false
	GameManager.transition_to(GameManager.State.BOARD)
	GlobalData.reset_run_data()
	if _save_backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_backup)
			f.flush()
			f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)


func _print_summary() -> void:
	print("---------------------------------------------------------------------------")
	print("CAMPAIGN PAUSE EXIT WIRING VERIFY (GATE 3D) RESULTS:")
	print("  TOTAL ASSERTIONS : %d" % _total_assertions)
	print("  PASSED           : %d" % _passed_assertions)
	print("  FAILED           : %d" % _failed_assertions)
	print("---------------------------------------------------------------------------")
	if _failed_assertions == 0:
		print("PASSED: Gate 3D pause wiring and defense recovery strictly satisfied.")
	else:
		printerr("FAILED: Gate 3D pause wiring and recovery has %d failures!" % _failed_assertions)
	get_tree().quit(0 if _failed_assertions == 0 else 1)
