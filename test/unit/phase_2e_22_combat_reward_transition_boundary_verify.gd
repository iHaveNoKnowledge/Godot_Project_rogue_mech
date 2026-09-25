extends Node

const CombatRewardsUICls = preload("res://scripts/ui/combat_rewards_ui.gd")
const SpawnManagerCls = preload("res://scripts/systems/spawn_manager.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	print("\n=== STARTING PHASE 2E-22 COMBAT REWARD & TRANSITION BOUNDARY VERIFICATION ===")
	await _run_all_tests()
	await get_tree().process_frame
	_print_summary()
	if _failed == 0:
		print("PHASE_2E_22_SUCCESS")
		get_tree().quit(0)
	else:
		push_error("PHASE_2E_22_FAILED with %d errors" % _failed)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % message)
	else:
		_failed += 1
		push_error("  [FAIL] %s" % message)


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-22 COMBAT REWARD & TRANSITION BOUNDARY SUMMARY:")
	print("  Passed: %d" % _passed)
	print("  Failed: %d" % _failed)
	print("==================================================")


func _run_all_tests() -> void:
	await _test_rewards_exact_once_and_idempotency()
	await _test_loot_claim_wreckage_and_cleanup()
	await _test_continue_debounce()
	await _test_wreckage_save_load()
	await _test_cross_combat_state_isolation()
	await _test_defeat_isolation()
	await _test_encounter_type_matrix()
	await _test_suppress_scene_change()


# --- [TEST 1 & 2] Reward Exactly Once & Duplicate Idempotency ---
func _test_rewards_exact_once_and_idempotency() -> void:
	print("\n-- [TEST 1 & 2] Reward Exactly Once & Duplicate Idempotency --")
	var rewards_ui = CombatRewardsUICls.new()
	add_child(rewards_ui)
	rewards_ui.reset_reward_state()

	var cr_initial: int = GlobalData.currency.credits
	var sc_initial: int = GlobalData.currency.scrap

	# Test 1: First reward display awards resources exactly once
	rewards_ui._show_victory_rewards()
	var cr_first: int = GlobalData.currency.credits
	var sc_first: int = GlobalData.currency.scrap
	_check(cr_first > cr_initial, "[T1-1] First _show_victory_rewards grants credits")
	_check(sc_first > sc_initial, "[T1-2] First _show_victory_rewards grants scrap")
	_check(rewards_ui._rewards_claimed == true, "[T1-3] _rewards_claimed latch is committed to true")
	_check(rewards_ui.rewards.has("credits") and rewards_ui.rewards["credits"] > 0, "[T1-4] rewards dictionary populated with credits")

	# Test 2: Duplicate direct call does NOT award duplicate resources
	rewards_ui._show_victory_rewards()
	var cr_second: int = GlobalData.currency.credits
	var sc_second: int = GlobalData.currency.scrap
	_check(cr_second == cr_first, "[T2-1] Direct duplicate _show_victory_rewards does NOT duplicate credits")
	_check(sc_second == sc_first, "[T2-2] Direct duplicate _show_victory_rewards does NOT duplicate scrap")

	# Simulate duplicate EventBus.combat_ended.emit(true)
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame
	_check(GlobalData.currency.credits == cr_first, "[T2-3] Repeated EventBus.combat_ended signal does NOT duplicate credits")
	_check(GlobalData.currency.scrap == sc_first, "[T2-4] Repeated EventBus.combat_ended signal does NOT duplicate scrap")

	get_tree().paused = false
	rewards_ui.queue_free()
	await get_tree().process_frame


# --- [TEST 3, 4, 5, 7] Loot Claim, Wreckage Isolation & Battle Loot Cleanup ---
func _test_loot_claim_wreckage_and_cleanup() -> void:
	print("\n-- [TEST 3, 4, 5, 7] Loot Claim, Wreckage Isolation & Cleanup --")
	var rewards_ui = CombatRewardsUICls.new()
	add_child(rewards_ui)
	rewards_ui.reset_reward_state()

	var test_tile := Vector2i(5, 5)
	GlobalData.board.current_tile = test_tile
	ScavengerSystem.claim_tile_wreckage(test_tile)

	var w_claimed: WeaponPart = load("res://resources/mech/stock/weapon_beam_rifle.tres")
	var w_unclaimed: WeaponPart = load("res://resources/mech/stock/weapon_machine_gun.tres")
	var a_claimed: Dictionary = {"uid": "armor_test_claim_22", "name": "Claimed Plate", "max_hp": 60.0}

	# Claimed items in _right_items; unclaimed in _left_items
	rewards_ui._right_items = [
		{"type": "weapon", "weapon": w_claimed},
		{"type": "armor", "instance": a_claimed}
	]
	rewards_ui._left_items = [
		{"type": "weapon", "weapon": w_unclaimed}
	]
	GlobalData.weapons.battle_loot = [
		{"type": "weapon", "weapon": w_claimed},
		{"type": "weapon", "weapon": w_unclaimed},
		{"type": "armor", "instance": a_claimed}
	]

	var stash_before: int = GlobalData.weapons.weapon_inventory.size()
	var armor_before: int = GlobalData.weapons.armor_inventory.size()

	# Finalize loot via _grant_take_back_loot()
	rewards_ui._grant_take_back_loot()

	# Test 3: Claimed loot transferred exactly once
	var stash_after: int = GlobalData.weapons.weapon_inventory.size()
	var armor_after: int = GlobalData.weapons.armor_inventory.size()
	_check(stash_after == stash_before + 1, "[T3-1] Claimed weapon registered into weapon_inventory")
	_check(armor_after == armor_before + 1, "[T3-2] Claimed armor appended to armor_inventory")

	# Test 4: Unclaimed loot becomes wreckage on current tile
	_check(ScavengerSystem.has_wreckage_at(test_tile), "[T4-1] Unclaimed loot registered as wreckage at current tile")
	var wr := ScavengerSystem.get_wreckage_at(test_tile)
	var wr_items: Array = wr.get("items", [])
	_check(wr_items.size() == 1, "[T4-2] Wreckage has exactly 1 unclaimed item")

	var wr_weapon: WeaponPart = wr_items[0].get("weapon")
	_check(wr_weapon != null and wr_weapon.weapon_name == w_unclaimed.weapon_name, "[T4-3] Wreckage item matches unclaimed weapon")

	# Test 5: Claimed loot does NOT become wreckage
	_check(wr_weapon.weapon_name != w_claimed.weapon_name, "[T5-1] Claimed weapon is NOT present in wreckage")

	# Test 7: Battle loot and internal item arrays cleared
	_check(GlobalData.weapons.battle_loot.is_empty(), "[T7-1] GlobalData.weapons.battle_loot cleared after finalization")
	_check(rewards_ui._left_items.is_empty(), "[T7-2] rewards_ui._left_items cleared after finalization")
	_check(rewards_ui._right_items.is_empty(), "[T7-3] rewards_ui._right_items cleared after finalization")

	# Idempotency: Re-calling _grant_take_back_loot does not re-add items or wreckage
	rewards_ui._grant_take_back_loot()
	_check(GlobalData.weapons.weapon_inventory.size() == stash_after, "[T3-3] Secondary _grant_take_back_loot does not duplicate stash")
	_check(GlobalData.weapons.armor_inventory.size() == armor_after, "[T3-4] Secondary _grant_take_back_loot does not duplicate armor")
	_check(ScavengerSystem.get_wreckage_at(test_tile).get("items", []).size() == 1, "[T4-4] Secondary _grant_take_back_loot does not duplicate wreckage entries")

	# Clean up test wreckage
	ScavengerSystem.claim_tile_wreckage(test_tile)
	rewards_ui.queue_free()
	await get_tree().process_frame


# --- [TEST 6] Continue Debounce Prevents Duplicate Transition ---
func _test_continue_debounce() -> void:
	print("\n-- [TEST 6] Continue Debounce Prevents Duplicate Transition --")
	var rewards_ui = CombatRewardsUICls.new()
	add_child(rewards_ui)
	rewards_ui.reset_reward_state()

	GameManager.suppress_scene_change = true
	var transition_data := {"count": 0}
	var on_transition = func(_old_st, _new_st) -> void:
		transition_data["count"] += 1
	EventBus.game_state_changed.connect(on_transition)

	_check(rewards_ui._continue_processing == false, "[T6-1] _continue_processing initially false")
	rewards_ui._on_continue_pressed()
	_check(rewards_ui._continue_processing == true, "[T6-2] _continue_processing becomes true immediately")
	_check(rewards_ui.continue_button.disabled == true, "[T6-3] continue_button disabled immediately on click")

	# Immediate rapid second call
	rewards_ui._on_continue_pressed()
	_check(transition_data["count"] == 1, "[T6-4] Rapid double Continue generates exactly one transition request")

	EventBus.game_state_changed.disconnect(on_transition)
	GameManager.suppress_scene_change = false
	get_tree().paused = false
	rewards_ui.queue_free()
	await get_tree().process_frame


# --- [TEST 8] Wreckage Survives Save/Load ---
func _test_wreckage_save_load() -> void:
	print("\n-- [TEST 8] Wreckage Survives Save/Load --")
	var test_pos := Vector2i(4, 8)
	var test_weapon: WeaponPart = load("res://resources/mech/stock/weapon_beam_rifle.tres")
	var drop_items: Array = [
		{"type": "weapon", "weapon": test_weapon, "drop_chance": 1.0},
		{"type": "armor", "instance": {"name": "Test Plate", "max_hp": 75.0}, "drop_chance": 1.0}
	]

	ScavengerSystem.claim_tile_wreckage(test_pos)
	ScavengerSystem.register_tile_wreckage(test_pos, drop_items, 30)
	_check(ScavengerSystem.has_wreckage_at(test_pos), "[T8-1] Wreckage marker registered at (4,8) before save")

	SaveGameIO.save_run()

	# Wipe runtime memory state
	ScavengerSystem.set_tile_wreckages({})
	_check(not ScavengerSystem.has_wreckage_at(test_pos), "[T8-2] Wreckage cleared from runtime memory")

	var load_ok := SaveGameIO.load_run()
	_check(load_ok, "[T8-3] SaveGameIO.load_run succeeded")
	_check(ScavengerSystem.has_wreckage_at(test_pos), "[T8-4] Wreckage restored after load")

	var wr := ScavengerSystem.get_wreckage_at(test_pos)
	_check(int(wr.get("scrap", 0)) == 30, "[T8-5] Restored scrap amount is 30")
	var items: Array = wr.get("items", [])
	_check(items.size() == 2, "[T8-6] Restored wreckage contains 2 items")

	var wp_valid := false
	for it in items:
		if it.get("type") == "weapon" and it.get("weapon") is WeaponPart:
			wp_valid = true
	_check(wp_valid, "[T8-7] Weapon Part resource properly reloaded as WeaponPart")

	# Clean up test wreckage
	ScavengerSystem.claim_tile_wreckage(test_pos)
	SaveGameIO.save_run()


# --- [TEST 9] Combat A State Does Not Leak into Combat B ---
func _test_cross_combat_state_isolation() -> void:
	print("\n-- [TEST 9] Combat A State Does Not Leak into Combat B --")
	# Simulate Combat A finish
	SpawnManagerCls._fallback_empty_completed = true
	GlobalData._combat_xp_awarded = true
	GlobalData.weapons.battle_loot = [{"type": "weapon", "weapon": null}]

	# Begin Combat B via GameManager.enter_combat
	GameManager.suppress_scene_change = true
	GameManager.enter_combat("grunt")
	GameManager.suppress_scene_change = false

	_check(SpawnManagerCls._fallback_empty_completed == false, "[T9-1] Fallback state reset for Combat B")
	_check(GlobalData._combat_xp_awarded == false, "[T9-2] Pilot XP award latch reset for Combat B")

	# Fresh CombatRewardsUI instantiated in Combat B scene
	var rewards_ui_b = CombatRewardsUICls.new()
	add_child(rewards_ui_b)
	rewards_ui_b.reset_reward_state()

	_check(rewards_ui_b._rewards_claimed == false, "[T9-3] Combat B rewards_claimed is false")
	_check(rewards_ui_b._continue_processing == false, "[T9-4] Combat B continue_processing is false")
	_check(rewards_ui_b.continue_button.disabled == false, "[T9-5] Combat B continue_button is enabled")

	rewards_ui_b.queue_free()
	await get_tree().process_frame


# --- [TEST 10] Defeat Does Not Enter Victory Reward Flow ---
func _test_defeat_isolation() -> void:
	print("\n-- [TEST 10] Defeat Does Not Enter Victory Reward Flow --")
	var rewards_ui = CombatRewardsUICls.new()
	add_child(rewards_ui)
	rewards_ui.reset_reward_state()

	var cr_before: int = GlobalData.currency.credits
	var sc_before: int = GlobalData.currency.scrap
	var tech_id := "tech_patrol_victory_test"
	var prog_before: float = TechnologySystem.get_research_progress(tech_id)

	# Trigger Defeat
	rewards_ui._on_combat_ended(false)
	_check(rewards_ui.title_label.text == "DEFEATED", "[T10-1] Defeat screen displayed with title DEFEATED")
	_check(GlobalData.currency.credits == cr_before, "[T10-2] Defeat did not grant credits")
	_check(GlobalData.currency.scrap == sc_before, "[T10-3] Defeat did not grant scrap")

	var prog_after: float = TechnologySystem.get_research_progress(tech_id)
	_check(is_equal_approx(prog_after, prog_before), "[T10-4] Defeat did not grant research progress")

	get_tree().paused = false
	rewards_ui.queue_free()
	await get_tree().process_frame


# --- [TEST 11] Encounter Type Matrix ---
func _test_encounter_type_matrix() -> void:
	print("\n-- [TEST 11] Encounter Type Matrix (Normal, Patrol, Duel, Enemy Base, Fuel Depot) --")
	TechnologySystem.reset_discovery_states()
	var tech_id := "tech_boundary_matrix_test"
	TechnologySystem.register_technology({
		"tech_id": tech_id,
		"name": "Boundary Tech Test",
		"generation": 2,
		"technology_family": TechnologySystem.FAMILY_BALLISTIC,
		"era_phase_req": 1,
		"origin_lineage": TechnologySystem.LINEAGE_VALKREN,
		"prerequisites": [],
		"research_metadata": {
			"research_time": 10.0
		}
	})
	TechnologySystem.record_technology_encountered(tech_id)
	TechnologySystem.record_technology_salvaged(tech_id)
	TechnologySystem.add_technology_evidence(tech_id, 1.0)
	TechnologySystem.record_technology_identified(tech_id)
	TechnologySystem.start_research(tech_id)

	# 1. Normal combat
	var p_before: float = TechnologySystem.get_research_progress(tech_id)
	GlobalData._combat_xp_awarded = false
	GlobalData.board.board_patrol_engagement = -1
	GameManager.combat_node_type = "grunt"
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame
	_check(is_equal_approx(TechnologySystem.get_research_progress(tech_id), p_before + 20.0), "[T11-normal] Normal combat victory advances research")

	# 2. Patrol combat
	p_before = TechnologySystem.get_research_progress(tech_id)
	GlobalData._combat_xp_awarded = false
	GlobalData.board.board_patrol_engagement = 88
	GlobalData.board.board_patrols = [{"id": 88, "pos": Vector2i(1, 1), "commander": {"name": "Rival", "rivalry_count": 0, "bounty": 50}}]
	GameManager.combat_node_type = "grunt"
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame
	_check(is_equal_approx(TechnologySystem.get_research_progress(tech_id), p_before + 20.0), "[T11-patrol] Patrol victory advances research")
	_check(GlobalData.board.board_patrol_engagement == -1, "[T11-patrol] Patrol engagement cleared")

	# 3. Duel combat
	p_before = TechnologySystem.get_research_progress(tech_id)
	GlobalData._combat_xp_awarded = false
	GlobalData.board.board_patrol_engagement = -1
	GlobalData.hangar.pending_duel = {"character_id": "test_duelist"}
	GameManager.combat_node_type = "duel"
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame
	_check(is_equal_approx(TechnologySystem.get_research_progress(tech_id), p_before + 20.0), "[T11-duel] Duel victory advances research")
	_check(GlobalData.hangar.pending_duel.is_empty(), "[T11-duel] Pending duel cleared")

	# 4. Enemy Base
	p_before = TechnologySystem.get_research_progress(tech_id)
	GlobalData._combat_xp_awarded = false
	GlobalData.board.board_patrol_engagement = -1
	GlobalData.narrative.enemy_base_active = true
	GameManager.combat_node_type = "enemy_base"
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame
	_check(is_equal_approx(TechnologySystem.get_research_progress(tech_id), p_before + 20.0), "[T11-base] Enemy base victory advances research")
	_check(GlobalData.narrative.enemy_base_active == false, "[T11-base] Enemy base marked inactive")

	# 5. Fuel Depot
	p_before = TechnologySystem.get_research_progress(tech_id)
	GlobalData._combat_xp_awarded = false
	GlobalData.board.board_patrol_engagement = -1
	GlobalData.fuel.fuel_depot_approach = "precise"
	GlobalData.fuel.mech_fuel_inventory.reset([{"type": 0, "capacity": 100.0, "current": 0.0}])
	GameManager.combat_node_type = "fuel_depot"
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame
	_check(is_equal_approx(TechnologySystem.get_research_progress(tech_id), p_before + 20.0), "[T11-fuel] Fuel depot victory advances research")
	_check(GlobalData.fuel.fuel_depot_approach == "", "[T11-fuel] Fuel depot approach cleared")


# --- [TEST 12] suppress_scene_change Production Isolation ---
func _test_suppress_scene_change() -> void:
	print("\n-- [TEST 12] suppress_scene_change Production Isolation --")
	_check(GameManager.suppress_scene_change == false, "[T12-1] suppress_scene_change defaults to false in production")

	GameManager.suppress_scene_change = true
	_check(GameManager.suppress_scene_change == true, "[T12-2] suppress_scene_change can be toggled by tests")
	GameManager.suppress_scene_change = false
	_check(GameManager.suppress_scene_change == false, "[T12-3] suppress_scene_change reverts cleanly to false")
