extends Node

## War Mode Phase 3D: Failure & Recovery Integrity Audit & Verification
## Proves that abnormal, cancelled, defeated, interrupted, or repeatedly failed
## gameplay transitions do not corrupt authoritative WAR Mode state.

const WarBalance = preload("res://scripts/war/war_balance.gd")
const WarDeploymentManager = preload("res://scripts/war/war_deployment_manager.gd")
const WarLaunchSetupUI = preload("res://scripts/war/war_launch_setup_ui.gd")
const MechaController = preload("res://scripts/mecha/mecha_controller.gd")
const CombatRewardsUI = preload("res://scripts/ui/combat_rewards_ui.gd")

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
	print("WAR MODE PHASE 3D: FAILURE & RECOVERY AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("WAR_PHASE_3D_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nWAR_PHASE_3D_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("WAR MODE PHASE 3D TEST SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failures.is_empty():
		print("FAILED ASSERTIONS:")
		for f in _failures:
			print("  - %s" % f)
	print("==================================================")


func _run_all_tests() -> void:
	await _test_scenario_1_cancel_before_deployment()
	await _test_scenario_2_repeated_open_close_launch_setup()
	await _test_scenario_3_combat_defeat_and_reward_separation()
	await _test_scenario_4_deployment_destruction_and_cooldown_recovery()
	await _test_scenario_5_player_authority_release_and_reclaim_on_failure()
	await _test_scenario_6_repeated_failure_and_recovery_cycles()
	await _test_scenario_7_result_dismissal_idempotency()


# --- Scenario 1: Cancel Before Deployment ---
func _test_scenario_1_cancel_before_deployment() -> void:
	print("\n-- [1] Launch Setup Cancellation Integrity --")
	GameManager.current_state = GameManager.State.BOARD
	GlobalData.currency.credits = 600
	GlobalData.currency.scrap = 150
	GlobalData.fuel.mech_energy = 90.0

	var dm = WarDeploymentManager.new()
	var launch_scene = load("res://scenes/war/war_launch_setup_ui.tscn")
	var launch: WarLaunchSetupUI = launch_scene.instantiate()
	launch._deployment = dm
	add_child(launch)

	var signal_fired := false
	launch.launch_requested.connect(func(_cat, _fit): signal_fired = true)

	# Open setup, modify multiple slots, then cancel
	launch.open_setup("Ace_Temp")
	launch._on_change_fitting("backpack")
	launch._on_change_fitting("main_hand")
	launch._on_change_fitting("off_hand")
	launch._on_close()

	_assert(signal_fired == false, "1.1: No launch signal emitted on cancel")
	_assert(dm.available_stock("line") == 5, "1.2: Line available stock remains 5/5")
	_assert(dm.deployed["line"] == 0, "1.3: 0 line units deployed")
	_assert(GlobalData.currency.credits == 600, "1.4: Credits untouched on cancel (600)")
	_assert(GlobalData.currency.scrap == 150, "1.5: Scrap untouched on cancel (150)")
	_assert(GlobalData.fuel.mech_energy == 90.0, "1.6: Mech energy untouched on cancel (90.0)")
	_assert(launch.visible == false, "1.7: Launch UI hidden after cancel")

	launch.queue_free()
	await get_tree().process_frame


# --- Scenario 2: Repeated Open/Close Without Multiplying Callbacks ---
func _test_scenario_2_repeated_open_close_launch_setup() -> void:
	print("\n-- [2] Repeated Launch UI Open/Close Idempotency --")
	var dm = WarDeploymentManager.new()
	var launch_scene = load("res://scenes/war/war_launch_setup_ui.tscn")
	var launch: WarLaunchSetupUI = launch_scene.instantiate()
	launch._deployment = dm
	add_child(launch)

	var launch_tracker: Array[int] = [0]
	launch.launch_requested.connect(func(_cat, _fit): launch_tracker[0] += 1)

	# Open and close 4 times in rapid succession
	for i in range(4):
		launch.open_setup()
		_assert(launch.visible == true, "2.1.%d: Opened iteration %d" % [i + 1, i + 1])
		launch._on_close()
		_assert(launch.visible == false, "2.2.%d: Closed iteration %d" % [i + 1, i + 1])
		_assert(launch._ace_timer.is_stopped() == true, "2.3.%d: Timer stopped iteration %d" % [i + 1, i + 1])

	# Finally open and launch once
	launch.open_setup()
	launch._on_launch("strike")

	_assert(launch_tracker[0] == 1, "2.4: Exactly 1 launch signal emitted (got %d) despite 4 prior open/close cycles" % launch_tracker[0])
	_assert(dm.deployed["strike"] == 1, "2.5: Exactly 1 strike unit deployed")
	_assert(dm.available_stock("strike") == 2, "2.6: Strike stock decremented to 2/3")

	launch.queue_free()
	await get_tree().process_frame


# --- Scenario 3: Combat Defeat & Strict Reward Separation ---
func _test_scenario_3_combat_defeat_and_reward_separation() -> void:
	print("\n-- [3] Combat Defeat Outcome & Zero-Victory-Reward Guarantee --")
	GameManager.current_state = GameManager.State.COMBAT
	GlobalData.currency.credits = 750
	GlobalData.currency.scrap = 200

	var rewards_scene = load("res://scenes/ui/combat_rewards_ui.tscn")
	var rewards_ui: CombatRewardsUI = rewards_scene.instantiate()
	add_child(rewards_ui)

	# Trigger DEFEAT (is_player_win = false)
	rewards_ui._on_combat_ended(false)

	_assert(GlobalData.currency.credits == 750, "3.1: Credits unchanged on defeat (750 == 750)")
	_assert(GlobalData.currency.scrap == 200, "3.2: Scrap unchanged on defeat (200 == 200)")
	_assert(rewards_ui.title_label.text.find("DEFEAT") != -1 or rewards_ui.title_label.text.find("DESTROYED") != -1 or rewards_ui.title_label.text.find("M.I.A") != -1, "3.3: Defeat title displayed")

	# Duplicate defeat trigger attempt
	rewards_ui._on_combat_ended(false)
	_assert(GlobalData.currency.credits == 750, "3.4: Credits remain 750 after duplicate defeat event")

	rewards_ui.queue_free()
	await get_tree().process_frame


# --- Scenario 4: Deployment Destruction & Cooldown Recovery ---
func _test_scenario_4_deployment_destruction_and_cooldown_recovery() -> void:
	print("\n-- [4] Deployment Destruction, Cooldown & Quota Recovery --")
	var dm = WarDeploymentManager.new()

	# Deploy 3 Line units
	dm.on_deployed("line")
	dm.on_deployed("line")
	dm.on_deployed("line")
	_assert(dm.deployed["line"] == 3, "4.1: 3 line units deployed")
	_assert(dm.available_stock("line") == 2, "4.2: Available line stock == 2")

	# 1 unit destroyed in battle
	dm.on_destroyed("line")
	_assert(dm.deployed["line"] == 2, "4.3: Deployed count reduced to 2 on destruction")
	_assert(dm.get_cooldown_remaining("line") > 25.0, "4.4: Line cooldown started (~30s)")

	# Cooldown in progress (15s elapsed)
	dm.tick(15.0)
	_assert(dm.get_cooldown_remaining("line") > 0.0, "4.5: Line cooldown still active at 15s")
	_assert(dm.available_stock("line") == 2, "4.6: Stock remains 2 while replenishing")

	# Cooldown completes (+20s elapsed, total 35s)
	dm.tick(20.0)
	_assert(dm.get_cooldown_remaining("line") == 0.0, "4.7: Cooldown cleared")
	_assert(dm.available_stock("line") == 3, "4.8: Stock recovered to 3 (3 available + 2 deployed = 5 total cap)")
	_assert(dm.available_stock("line") + dm.deployed["line"] == 5, "4.9: Total quota preserved at exactly 5 (no inflation)")


# --- Scenario 5: Player Authority Teardown & Reclaim Across Failures ---
func _test_scenario_5_player_authority_release_and_reclaim_on_failure() -> void:
	print("\n-- [5] Player Authority Isolation Across Failed Combats --")
	# Combat 1: Starts and ends in defeat/abort
	var mech_scene = load("res://scenes/mecha/mecha_base.tscn")
	var mech1 = mech_scene.instantiate() as MechaController
	mech1.is_player_driven = true
	add_child(mech1)
	mech1.claim_player_authority()

	_assert(MechaController.active_player == mech1, "5.1: Combat 1 mecha owns active_player")

	# Defeat / abort teardown
	mech1.release_player_authority()
	mech1.queue_free()
	mech1 = null
	await get_tree().process_frame

	_assert(MechaController.active_player == null, "5.2: active_player cleanly reset to null on defeat")

	# Combat 2: Re-enter combat
	var mech2 = mech_scene.instantiate() as MechaController
	mech2.is_player_driven = true
	add_child(mech2)
	mech2.claim_player_authority()

	_assert(MechaController.active_player == mech2, "5.3: Combat 2 mecha successfully claimed active_player")
	_assert(MechaController.active_player != null, "5.4: active_player is valid")

	mech2.release_player_authority()
	mech2.queue_free()
	await get_tree().process_frame
	_assert(MechaController.active_player == null, "5.5: Final active_player reset to null")


# --- Scenario 6: Repeated 3x Failure & Recovery Cycles ---
func _test_scenario_6_repeated_failure_and_recovery_cycles() -> void:
	print("\n-- [6] Multi-Cycle Failure & Recovery Stability --")
	var dm = WarDeploymentManager.new()

	for cycle in range(3):
		# 1. Deploy Valkyrion (1/1 cap)
		_assert(dm.can_deploy("valkyrion"), "6.1.%d: Valkyrion deployable start of Cycle %d" % [cycle + 1, cycle + 1])
		dm.on_deployed("valkyrion")
		_assert(dm.deployed["valkyrion"] == 1, "6.2.%d: Valkyrion deployed (1/1)" % [cycle + 1])
		_assert(dm.can_deploy("valkyrion") == false, "6.3.%d: Valkyrion blocked at cap" % [cycle + 1])

		# 2. Destroy in combat
		dm.on_destroyed("valkyrion")
		_assert(dm.deployed["valkyrion"] == 0, "6.4.%d: Valkyrion count reset on destruction" % [cycle + 1])
		_assert(dm.get_cooldown_remaining("valkyrion") > 150.0, "6.5.%d: Valkyrion 180s cooldown started" % [cycle + 1])

		# 3. Recover after 180-300s cooldown
		dm.tick(310.0)
		_assert(dm.get_cooldown_remaining("valkyrion") == 0.0, "6.6.%d: Valkyrion cooldown cleared" % [cycle + 1])
		_assert(dm.available_stock("valkyrion") == 1, "6.7.%d: Valkyrion stock restored to 1" % [cycle + 1])
		_assert(dm.available_stock("valkyrion") + dm.deployed["valkyrion"] == 1, "6.8.%d: Valkyrion cap preserved (no inflation)" % [cycle + 1])


# --- Scenario 7: Result Dismissal Idempotency ---
func _test_scenario_7_result_dismissal_idempotency() -> void:
	print("\n-- [7] Result Dismissal Idempotency --")
	var rewards_scene = load("res://scenes/ui/combat_rewards_ui.tscn")
	var rewards_ui: CombatRewardsUI = rewards_scene.instantiate()
	add_child(rewards_ui)

	GlobalData.currency.credits = 1000
	rewards_ui._on_combat_ended(true)
	var credits_after_first = GlobalData.currency.credits

	# Simulate 3 rapid button press / dismiss events
	for i in range(3):
		rewards_ui._on_combat_ended(true)
		_assert(GlobalData.currency.credits == credits_after_first, "7.1.%d: Duplicate grant %d rejected" % [i + 1, i + 1])

	rewards_ui.queue_free()
	await get_tree().process_frame
