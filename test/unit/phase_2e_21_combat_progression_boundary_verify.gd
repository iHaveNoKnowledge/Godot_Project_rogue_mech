extends Node

## ===========================================================================
## PHASE 2E-21 COMBAT VICTORY -> RUN PROGRESSION BOUNDARY VERIFICATION SUITE
## ===========================================================================

const TechSys = preload("res://scripts/systems/technology_system.gd")
const ResProgSys = preload("res://scripts/systems/research_progression_system.gd")
const PilotSkillSys = preload("res://scripts/systems/pilot_skill_system.gd")
const SpawnManagerCls = preload("res://scripts/systems/spawn_manager.gd")
const CombatRewardsUICls = preload("res://scripts/ui/combat_rewards_ui.gd")

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n=== STARTING PHASE 2E-21 COMBAT PROGRESSION BOUNDARY VERIFICATION ===")
	await _run_all_tests()
	_print_summary()
	if _fail_count == 0:
		print("PHASE_2E_21_SUCCESS")
		get_tree().quit(0)
	else:
		push_error("PHASE_2E_21_FAILED with %d errors" % _fail_count)
		get_tree().quit(1)


func _run_all_tests() -> void:
	await _test_patrol_victory_research_and_tech()
	await _test_duel_victory_progression()
	await _test_enemy_base_victory_progression()
	await _test_fuel_depot_victory_progression()
	await _test_defeat_isolation()
	await _test_rewards_ui_idempotency_and_debounce()
	await _test_fallback_lifecycle_reset()
	await _test_wreckage_persistence()


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % test_name)
	else:
		_fail_count += 1
		push_error("  [FAIL] %s" % test_name)


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-21 COMBAT PROGRESSION VERIFICATION SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	print("==================================================")


# --- [TEST A & B] Patrol Victory Research & Tech Escalation (F-01) ---
func _test_patrol_victory_research_and_tech() -> void:
	print("\n-- [TEST A & B] Patrol Victory Research & Tech Escalation (F-01) --")
	TechSys.reset_discovery_states()
	var tech_id := "tech_patrol_victory_test"
	TechSys.register_technology({
		"tech_id": tech_id,
		"name": "Patrol Tech Test",
		"generation": 2,
		"technology_family": TechSys.FAMILY_BALLISTIC,
		"era_phase_req": 1,
		"origin_lineage": TechSys.LINEAGE_VALKREN,
		"prerequisites": [],
		"research_metadata": {
			"research_time": 10.0
		}
	})
	TechSys.record_technology_encountered(tech_id)
	TechSys.record_technology_salvaged(tech_id)
	TechSys.add_technology_evidence(tech_id, 1.0)
	TechSys.record_technology_identified(tech_id)
	TechSys.start_research(tech_id)

	var init_prog: float = TechSys.get_research_progress(tech_id)
	_check(is_equal_approx(init_prog, 0.0), "[A1] Research starts at 0.0%")

	# Create a mock patrol engagement
	var patrol_id := 42
	GlobalData.board.board_patrols = [{
		"id": patrol_id,
		"pos": Vector2i(2, 2),
		"name": "Test Vanguard",
		"fleet_count": 1,
		"commander": {"name": "Ace Tester", "bounty": 150}
	}]
	GlobalData.board.board_patrol_engagement = patrol_id
	GameManager.combat_node_type = "grunt"
	GlobalData._combat_xp_awarded = false
	GlobalData.set_friendly_damage_ratio(0.2) # Decisive victory (< 0.5)
	GlobalData.narrative.enemy_tech_tier = 1
	GlobalData.narrative.pending_escalation_event = false

	# Emit victory
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame

	var post_prog: float = TechSys.get_research_progress(tech_id)
	_check(is_equal_approx(post_prog, 20.0), "[A2] Patrol victory advances research by exactly 20% (2.0 points)")
	_check(GlobalData.board.board_patrol_engagement == -1, "[A3] Patrol engagement reset to -1")
	_check(GlobalData.board.board_patrols.is_empty(), "[A4] Patrol removed from board_patrols")
	_check(GlobalData.narrative.enemy_tech_tier == 2, "[B1] Decisive patrol victory escalates enemy tech tier (1 -> 2)")
	_check(GlobalData.narrative.pending_escalation_event == true, "[B2] Pending escalation event flagged")

	# Test idempotency: repeated combat_ended(true) does not double-award XP
	var xp_before: int = PilotSkillSys.get_xp()
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame
	var xp_after: int = PilotSkillSys.get_xp()
	_check(xp_before == xp_after, "[A5] Repeated combat_ended does not double-award Pilot XP")


# --- [TEST C] Duel Victory Progression (F-01) ---
func _test_duel_victory_progression() -> void:
	print("\n-- [TEST C] Duel Victory Progression (F-01) --")
	var tech_id := "tech_patrol_victory_test"
	var prog_before: float = TechSys.get_research_progress(tech_id)

	GlobalData.hangar.pending_duel = {
		"character_id": "test_rival",
		"intent": "respect"
	}
	GameManager.combat_node_type = "duel"
	GlobalData._combat_xp_awarded = false
	GlobalData.set_friendly_damage_ratio(0.2)

	EventBus.combat_ended.emit(true)
	await get_tree().process_frame

	_check(GlobalData.hangar.pending_duel.is_empty(), "[C1] Pending duel cleared upon duel victory")
	var prog_after: float = TechSys.get_research_progress(tech_id)
	_check(is_equal_approx(prog_after, prog_before + 20.0), "[C2] Duel victory advances research progression by 2.0 points")


# --- [TEST D] Enemy Base Victory Progression (F-01) ---
func _test_enemy_base_victory_progression() -> void:
	print("\n-- [TEST D] Enemy Base Victory Progression (F-01) --")
	var tech_id := "tech_patrol_victory_test"
	var prog_before: float = TechSys.get_research_progress(tech_id)

	GameManager.combat_node_type = "enemy_base"
	GlobalData.narrative.enemy_base_active = true
	GlobalData.narrative.enemy_base_tile_pos = Vector2i(4, 4)
	var grunt_level_before: int = GlobalData.narrative.enemy_grunt_upgrade_level
	GlobalData._combat_xp_awarded = false

	EventBus.combat_ended.emit(true)
	await get_tree().process_frame

	_check(GlobalData.narrative.enemy_base_active == false, "[D1] Enemy base marked inactive upon victory")
	_check(GlobalData.narrative.enemy_grunt_upgrade_level == grunt_level_before + 1, "[D2] Grunt upgrade level incremented")
	var prog_after: float = TechSys.get_research_progress(tech_id)
	_check(is_equal_approx(prog_after, prog_before + 20.0), "[D3] Enemy base victory advances research progression by 2.0 points")


# --- [TEST E] Fuel Depot Victory Progression (F-01) ---
func _test_fuel_depot_victory_progression() -> void:
	print("\n-- [TEST E] Fuel Depot Victory Progression (F-01) --")
	var tech_id := "tech_patrol_victory_test"
	var prog_before: float = TechSys.get_research_progress(tech_id)

	GameManager.combat_node_type = "fuel_depot"
	GlobalData.fuel.fuel_depot_approach = "precise"
	GlobalData.fuel.mech_max_energy = 500.0
	GlobalData.fuel.mech_energy = 50.0
	GlobalData.fuel.mech_fuel_inventory.reset([{"type": 0, "capacity": 100.0, "current": 0.0}])
	var energy_before: float = GlobalData.fuel.mech_energy
	GlobalData._combat_xp_awarded = false

	EventBus.combat_ended.emit(true)
	await get_tree().process_frame

	_check(GlobalData.fuel.fuel_depot_approach == "", "[E1] Fuel depot approach cleared upon resolution")
	_check(GlobalData.fuel.mech_energy > energy_before, "[E2] Fuel depot energy bonus granted")
	var prog_after: float = TechSys.get_research_progress(tech_id)
	_check(is_equal_approx(prog_after, prog_before + 20.0), "[E3] Fuel depot victory advances research progression by 2.0 points")


# --- [TEST F] Defeat Isolation (F-01) ---
func _test_defeat_isolation() -> void:
	print("\n-- [TEST F] Defeat Isolation (F-01) --")
	var tech_id := "tech_patrol_victory_test"
	var prog_before: float = TechSys.get_research_progress(tech_id)
	var tier_before: int = GlobalData.narrative.enemy_tech_tier
	var xp_before: int = PilotSkillSys.get_xp()

	GlobalData.board.board_patrol_engagement = 99
	GlobalData.board.board_patrols = [{
		"id": 99,
		"pos": Vector2i(1, 1),
		"commander": {"name": "Rival Nemesis", "rivalry_count": 0, "bounty": 100}
	}]
	GameManager.combat_node_type = "grunt"
	GlobalData.set_friendly_damage_ratio(0.8) # Non-decisive / defeat

	EventBus.combat_ended.emit(false)
	await get_tree().process_frame

	var prog_after: float = TechSys.get_research_progress(tech_id)
	_check(is_equal_approx(prog_after, prog_before), "[F1] Defeat does NOT advance research progression")
	_check(GlobalData.narrative.enemy_tech_tier == tier_before, "[F2] Defeat does NOT escalate enemy tech tier")
	_check(PilotSkillSys.get_xp() == xp_before, "[F3] Defeat does NOT award Pilot XP")
	_check(GlobalData.board.board_patrol_engagement == -1, "[F4] Engagement cleared on defeat")


# --- [TEST F-02] Combat Rewards Idempotency & Continue Debounce ---
func _test_rewards_ui_idempotency_and_debounce() -> void:
	print("\n-- [TEST F-02] Combat Rewards Idempotency & Debounce --")
	var rewards_ui = CombatRewardsUICls.new()
	add_child(rewards_ui)
	rewards_ui.reset_reward_state()

	var cr_initial: int = GlobalData.currency.credits
	var sc_initial: int = GlobalData.currency.scrap

	# First victory rewards display
	rewards_ui._show_victory_rewards()
	var cr_first: int = GlobalData.currency.credits
	var sc_first: int = GlobalData.currency.scrap
	_check(cr_first > cr_initial, "[F02-1] First _show_victory_rewards grants credits")
	_check(sc_first > sc_initial, "[F02-2] First _show_victory_rewards grants scrap")
	_check(rewards_ui._rewards_claimed == true, "[F02-3] _rewards_claimed latch is true")

	# Second invocation (simulating duplicate combat_ended delivery)
	rewards_ui._show_victory_rewards()
	var cr_second: int = GlobalData.currency.credits
	var sc_second: int = GlobalData.currency.scrap
	_check(cr_second == cr_first, "[F02-4] Duplicate _show_victory_rewards does NOT award duplicate credits")
	_check(sc_second == sc_first, "[F02-5] Duplicate _show_victory_rewards does NOT award duplicate scrap")

	# Test continue button debounce
	GameManager.suppress_scene_change = true
	var transition_data := {"count": 0}
	var on_transition = func(_old_st, _new_st) -> void:
		transition_data["count"] += 1
	EventBus.game_state_changed.connect(on_transition)

	_check(rewards_ui._continue_processing == false, "[F02-6] _continue_processing initially false")
	rewards_ui._on_continue_pressed()
	_check(rewards_ui._continue_processing == true, "[F02-7] _continue_processing set to true on continue")
	_check(rewards_ui.continue_button.disabled == true, "[F02-8] continue_button disabled immediately on click")

	# Second rapid continue call (simulating spam/double-click)
	rewards_ui._on_continue_pressed()
	_check(transition_data["count"] == 1, "[F02-9] Rapid double continue generates exactly one transition request")

	EventBus.game_state_changed.disconnect(on_transition)
	GameManager.suppress_scene_change = false

	rewards_ui.queue_free()
	get_tree().paused = false
	await get_tree().process_frame


# --- [TEST F-03] Fallback Lifecycle Reset ---
func _test_fallback_lifecycle_reset() -> void:
	print("\n-- [TEST F-03] Fallback Lifecycle Reset --")
	SpawnManagerCls.reset_fallback_state()

	var fallback_data := {"emissions": 0}
	var cb := func(victory: bool) -> void:
		if victory:
			fallback_data["emissions"] += 1
	EventBus.combat_ended.connect(cb)

	# Combat A: static fallback empty check emits victory once
	SpawnManagerCls.check_all_enemies_defeated()
	_check(fallback_data["emissions"] == 1, "[F03-1] Combat A static fallback empty encounter emits victory once")
	SpawnManagerCls.check_all_enemies_defeated()
	_check(fallback_data["emissions"] == 1, "[F03-2] Combat A repeated fallback check remains idempotent")

	# Combat B: entering combat resets fallback lifecycle
	GameManager.suppress_scene_change = true
	GameManager.enter_combat("grunt")
	SpawnManagerCls.check_all_enemies_defeated()
	_check(fallback_data["emissions"] == 2, "[F03-3] Combat B after enter_combat successfully resolves independently")

	SpawnManagerCls.check_all_enemies_defeated()
	_check(fallback_data["emissions"] == 2, "[F03-4] Combat B repeated check remains idempotent")
	GameManager.suppress_scene_change = false

	EventBus.combat_ended.disconnect(cb)


# --- [TEST F-04] Wreckage Persistence ---
func _test_wreckage_persistence() -> void:
	print("\n-- [TEST F-04] Wreckage Persistence --")
	var test_pos := Vector2i(7, 9)
	var test_weapon: WeaponPart = load("res://resources/mech/stock/weapon_beam_rifle.tres")
	var drop_items: Array = [
		{"type": "weapon", "weapon": test_weapon, "drop_chance": 1.0},
		{"type": "armor", "instance": {"name": "Test Plate", "max_hp": 80.0}, "drop_chance": 1.0}
	]

	ScavengerSystem.set_tile_wreckages({})
	ScavengerSystem.register_tile_wreckage(test_pos, drop_items, 25)
	_check(ScavengerSystem.has_wreckage_at(test_pos), "[F04-1] Wreckage marker registered before save")

	# Save run
	SaveGameIO.save_run()

	# Wipe runtime memory state
	ScavengerSystem.set_tile_wreckages({})
	_check(not ScavengerSystem.has_wreckage_at(test_pos), "[F04-2] Wreckage cleared from runtime memory")

	# Load run
	var load_ok := SaveGameIO.load_run()
	_check(load_ok, "[F04-3] SaveGameIO.load_run succeeded")
	_check(ScavengerSystem.has_wreckage_at(test_pos), "[F04-4] Wreckage marker restored from save at (7,9)")

	var restored_wr := ScavengerSystem.get_wreckage_at(test_pos)
	_check(int(restored_wr.get("scrap", 0)) == 25, "[F04-5] Restored wreckage scrap amount is 25")
	var items: Array = restored_wr.get("items", [])
	_check(items.size() == 2, "[F04-6] Restored wreckage has 2 items")

	var weapon_found := false
	for it in items:
		if it.get("type") == "weapon" and it.get("weapon") != null:
			var w = it["weapon"]
			if w is WeaponPart and w.weapon_name == test_weapon.weapon_name:
				weapon_found = true
	_check(weapon_found, "[F04-7] Weapon item restored as valid WeaponPart resource")

	# Clean up test wreckage
	ScavengerSystem.claim_tile_wreckage(test_pos)
	SaveGameIO.save_run()
