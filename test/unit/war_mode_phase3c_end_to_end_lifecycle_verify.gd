extends Node

## War Mode Phase 3C: End-to-End Gameplay Lifecycle Audit & Verification
## Proves the complete multi-cycle transition loop:
## Board -> Launch Setup -> Deployment -> Combat -> Victory/Rewards -> Hangar -> Board -> Second Deployment
## Verifies that authoritative gameplay state survives every transition exactly once.

const WarBalance = preload("res://scripts/war/war_balance.gd")
const WarDeploymentManager = preload("res://scripts/war/war_deployment_manager.gd")
const WarLaunchSetupUI = preload("res://scripts/war/war_launch_setup_ui.gd")
const MechaController = preload("res://scripts/mecha/mecha_controller.gd")
const CombatRewardsUI = preload("res://scripts/ui/combat_rewards_ui.gd")
const FleetSystem = preload("res://scripts/systems/fleet_system.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % message)
	else:
		_fail_count += 1
		_failures.append(message)
		push_error("Assertion failed: %s" % message)
		print("  [FAIL] %s" % message)


func _ready() -> void:
	print("\n==================================================")
	print("WAR MODE PHASE 3C: END-TO-END GAMEPLAY LIFECYCLE AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("WAR_PHASE_3C_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nWAR_PHASE_3C_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("WAR MODE PHASE 3C TEST SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failures.is_empty():
		print("FAILED ASSERTIONS:")
		for f in _failures:
			print("  - %s" % f)
	print("==================================================")


func _run_all_tests() -> void:
	await _test_scenario_1_board_setup_and_snapshot()
	await _test_scenario_2_launch_cancellation_idempotency()
	await _test_scenario_3_deployment_transaction_and_payload()
	await _test_scenario_4_combat_entry_and_player_authority()
	await _test_scenario_5_combat_victory_and_exactly_once_rewards()
	await _test_scenario_6_hangar_intermission_handoff()
	await _test_scenario_7_board_return_and_state_preservation()
	await _test_scenario_8_second_deployment_cycle()
	await _test_scenario_9_defeat_and_negative_paths()


# --- Scenario 1: Initial Board State Snapshot ---
var _init_credits := 500
var _init_scrap := 120
var _init_energy := 80.0
var _init_security_level := 1
var _init_security_pts := 25.0

func _test_scenario_1_board_setup_and_snapshot() -> void:
	print("\n-- [1] Board Setup & Authoritative State Snapshot --")
	GameManager.current_state = GameManager.State.BOARD
	GlobalData.currency.credits = _init_credits
	GlobalData.currency.scrap = _init_scrap
	GlobalData.fuel.mech_energy = _init_energy
	GlobalData.narrative.security_upgrade_level = _init_security_level
	GlobalData.narrative.fleet_security = _init_security_pts
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	_assert(GameManager.current_state == GameManager.State.BOARD, "1.1: GameManager state is State.BOARD")
	_assert(GlobalData.currency.credits == 500, "1.2: Baseline credits snapshot == 500")
	_assert(GlobalData.currency.scrap == 120, "1.3: Baseline scrap snapshot == 120")
	_assert(GlobalData.fuel.mech_energy == 80.0, "1.4: Baseline energy snapshot == 80.0")
	_assert(GlobalData.narrative.security_upgrade_level == 1, "1.5: Canonical security level == 1")


# --- Scenario 2: Launch Cancellation Idempotency ---
func _test_scenario_2_launch_cancellation_idempotency() -> void:
	print("\n-- [2] Launch Setup Cancellation Transaction Integrity --")
	var launch_scene = load("res://scenes/war/war_launch_setup_ui.tscn")
	var launch: WarLaunchSetupUI = launch_scene.instantiate()
	add_child(launch)

	var dm = WarDeploymentManager.new()
	launch._deployment = dm

	# Open setup and modify fittings
	launch.open_setup("Ace_01")
	launch._on_change_fitting("backpack")
	launch._on_change_fitting("shoulder_left")

	_assert(dm.available_stock("line") == 5, "2.1: Line available stock remains 5 during setup preview")
	_assert(dm.deployed["line"] == 0, "2.2: 0 line units deployed during preview")

	# Cancel launch
	launch._on_close()
	_assert(dm.available_stock("line") == 5, "2.3: Line available stock unchanged after cancellation (5/5)")
	_assert(GlobalData.currency.credits == 500, "2.4: Credits untouched on cancel (%d == 500)" % GlobalData.currency.credits)
	_assert(GlobalData.fuel.mech_energy == 80.0, "2.5: Energy untouched on cancel (%.1f == 80.0)" % GlobalData.fuel.mech_energy)

	launch.queue_free()
	await get_tree().process_frame


# --- Scenario 3: Deployment Transaction & Payload ---
var _shared_dm: WarDeploymentManager = null
var _emitted_launch_cat := ""
var _emitted_fitting := {}

func _test_scenario_3_deployment_transaction_and_payload() -> void:
	print("\n-- [3] Confirmed Deployment Transaction & Payload Hand-off --")
	var launch_scene = load("res://scenes/war/war_launch_setup_ui.tscn")
	var launch: WarLaunchSetupUI = launch_scene.instantiate()
	add_child(launch)

	_shared_dm = WarDeploymentManager.new()
	launch._deployment = _shared_dm

	launch.launch_requested.connect(func(cat: String, fit: Dictionary):
		_emitted_launch_cat = cat
		_emitted_fitting = fit
	)

	launch.open_setup()
	launch._on_change_fitting("backpack") # select 'booster'
	launch._on_launch("line")

	_assert(_emitted_launch_cat == "line", "3.1: Emitted launch category is 'line'")
	_assert(str(_emitted_fitting.get("backpack", "")) != "", "3.2: Custom fitting payload passed successfully")
	_assert(_shared_dm.deployed["line"] == 1, "3.3: Deployment manager committed 1 line unit")
	_assert(_shared_dm.available_stock("line") == 4, "3.4: Line stock decremented to 4")

	launch.queue_free()
	await get_tree().process_frame


# --- Scenario 4: Combat Scene Entry & Player Authority ---
var _combat_player_mech: MechaController = null

func _test_scenario_4_combat_entry_and_player_authority() -> void:
	print("\n-- [4] Combat Scene Entry & Authoritative Player Mecha --")
	GameManager.current_state = GameManager.State.COMBAT

	var mech_scene = load("res://scenes/mecha/mecha_base.tscn")
	var mech_node = mech_scene.instantiate()
	_combat_player_mech = mech_node as MechaController
	_combat_player_mech.is_player_driven = true
	add_child(mech_node)

	_combat_player_mech.claim_player_authority()
	_combat_player_mech.energy_system.initialize_from_global()
	GameManager.active_player_mecha = _combat_player_mech

	_assert(_combat_player_mech.is_player_driven == true, "4.1: Combat mecha has explicit player authority")
	_assert(MechaController.active_player == _combat_player_mech, "4.2: MechaController.active_player bound")
	_assert(_combat_player_mech.energy_system.energy == 80.0, "4.3: Combat mecha loaded 80.0 energy from GlobalData")


# --- Scenario 5: Combat Victory & Exactly-Once Rewards ---
func _test_scenario_5_combat_victory_and_exactly_once_rewards() -> void:
	print("\n-- [5] In-Combat Mutation, Victory & Exactly-Once Rewards --")
	# Mutate in-combat energy (spend 17.5 energy -> 62.5 remaining)
	_combat_player_mech.energy_system.energy = 62.5
	_combat_player_mech.energy_system.persist_to_global()
	_assert(GlobalData.fuel.mech_energy == 62.5, "5.1: Mutated energy (62.5) persisted to GlobalData")

	# Teardown combat player mech
	_combat_player_mech.release_player_authority()
	GameManager.active_player_mecha = null
	_combat_player_mech.queue_free()
	_combat_player_mech = null
	await get_tree().process_frame
	_assert(GlobalData.fuel.mech_energy == 62.5, "5.2: Energy intact (62.5) after player teardown")

	# Apply combat victory rewards via CombatRewardsUI
	var rewards_scene = load("res://scenes/ui/combat_rewards_ui.tscn")
	var rewards_ui = rewards_scene.instantiate()
	add_child(rewards_ui)

	var pre_reward_credits = GlobalData.currency.credits
	var pre_reward_scrap = GlobalData.currency.scrap

	# First reward grant (victory)
	rewards_ui._on_combat_ended(true)
	var credits_after_first = GlobalData.currency.credits
	var scrap_after_first = GlobalData.currency.scrap
	_assert(credits_after_first > pre_reward_credits, "5.3: Credits increased (%d -> %d) after victory reward" % [pre_reward_credits, credits_after_first])
	_assert(scrap_after_first > pre_reward_scrap, "5.4: Scrap increased (%d -> %d) after victory reward" % [pre_reward_scrap, scrap_after_first])

	# Attempt duplicate reward trigger (must be blocked by _rewards_claimed guard)
	rewards_ui._on_combat_ended(true)
	_assert(GlobalData.currency.credits == credits_after_first, "5.5: Duplicate reward call rejected (credits unchanged)")
	_assert(GlobalData.currency.scrap == scrap_after_first, "5.6: Duplicate reward call rejected (scrap unchanged)")

	rewards_ui.queue_free()
	await get_tree().process_frame


# --- Scenario 6: Hangar / Intermission Handoff ---
func _test_scenario_6_hangar_intermission_handoff() -> void:
	print("\n-- [6] Hangar / Intermission Handoff & State Integrity --")
	GameManager.current_state = GameManager.State.HANGAR

	_assert(GlobalData.fuel.mech_energy == 62.5, "6.1: Fuel energy survives into Hangar (62.5)")
	_assert(GlobalData.narrative.security_upgrade_level == 1, "6.2: Security upgrade level remains 1")
	_assert(_shared_dm.available_stock("line") == 4, "6.3: Deployment stock remains 4/5")

	# Test security upgrade inside hangar
	var pre_upgrade_credits = GlobalData.currency.credits
	var cost = FleetSystem.get_security_upgrade_cost()
	_assert(cost == 35, "6.4: Level 1 security upgrade cost is 35")
	var upgraded = FleetSystem.upgrade_fleet_security()
	_assert(upgraded, "6.5: Fleet security upgraded in hangar")
	_assert(GlobalData.narrative.security_upgrade_level == 2, "6.6: Canonical security level incremented to 2")
	_assert(GlobalData.currency.credits == pre_upgrade_credits - 35, "6.7: Exact 35 credits deducted for upgrade")


# --- Scenario 7: Board Return & State Preservation ---
func _test_scenario_7_board_return_and_state_preservation() -> void:
	print("\n-- [7] Return to Board & Destination Tile Advance --")
	GameManager.current_state = GameManager.State.BOARD
	GlobalData.board.current_tile = Vector2i(3, 2) # Player stepped onto next node

	_assert(GameManager.current_state == GameManager.State.BOARD, "7.1: Returned to State.BOARD")
	_assert(GlobalData.board.current_tile == Vector2i(3, 2), "7.2: Board tile advanced to (3, 2)")
	_assert(GlobalData.fuel.mech_energy == 62.5, "7.3: Energy intact on board return (62.5)")
	_assert(GlobalData.narrative.security_upgrade_level == 2, "7.4: Hardening level 2 persisted across transitions")


# --- Scenario 8: Second Complete Deployment Cycle ---
func _test_scenario_8_second_deployment_cycle() -> void:
	print("\n-- [8] Second Complete Deployment Cycle from Updated State --")
	# Cycle 2: Launch second line unit
	_assert(_shared_dm.can_deploy("line"), "8.1: Can deploy second unit from remaining stock (4/5)")
	_shared_dm.on_deployed("line")
	_assert(_shared_dm.deployed["line"] == 2, "8.2: 2 line units deployed in Cycle 2")
	_assert(_shared_dm.available_stock("line") == 3, "8.3: Stock decremented to 3")

	# Cycle 2 Combat
	GameManager.current_state = GameManager.State.COMBAT
	var mech_scene = load("res://scenes/mecha/mecha_base.tscn")
	var mech2 = mech_scene.instantiate() as MechaController
	mech2.is_player_driven = true
	add_child(mech2)
	mech2.claim_player_authority()
	mech2.energy_system.initialize_from_global()
	GameManager.active_player_mecha = mech2

	_assert(mech2.energy_system.energy == 62.5, "8.4: Cycle 2 combat loads 62.5 energy from Cycle 1")

	# Spend energy down to 45.0
	mech2.energy_system.energy = 45.0
	mech2.energy_system.persist_to_global()
	mech2.release_player_authority()
	GameManager.active_player_mecha = null
	mech2.queue_free()
	await get_tree().process_frame

	_assert(GlobalData.fuel.mech_energy == 45.0, "8.5: Cycle 2 mutated energy (45.0) persisted")

	# Return to Board after Cycle 2
	GameManager.current_state = GameManager.State.BOARD
	_assert(GlobalData.fuel.mech_energy == 45.0, "8.6: Final board energy == 45.0 after Cycle 2")


# --- Scenario 9: Defeat & Negative Boundary Paths ---
func _test_scenario_9_defeat_and_negative_paths() -> void:
	print("\n-- [9] Defeat & Negative Boundary Verification --")
	# Defeat: on_destroyed moves unit into cooldown
	_shared_dm.on_destroyed("line")
	_assert(_shared_dm.deployed["line"] == 1, "9.1: Deployed line count decreased to 1 on destruction")
	_assert(_shared_dm.get_cooldown_remaining("line") > 20.0, "9.2: Destroyed unit entered cooldown (~30s)")

	# Tick cooldown to completion
	_shared_dm.tick(35.0)
	_assert(_shared_dm.get_cooldown_remaining("line") == 0.0, "9.3: Cooldown cleared after tick")
	_assert(_shared_dm.available_stock("line") == 4, "9.4: Stock restored to 4 after cooldown")
