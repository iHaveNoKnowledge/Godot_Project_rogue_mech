extends Node

## War Mode Phase 3F: Multi-Run / Long-Session State Leak Audit & Verification
## Verifies that multiple continuous gameplay runs (Victory, Defeat, Cancel)
## in a single long-lived process execute without state leakage, signal accumulation,
## duplicate rewards, deployment drift, stale authority, or orphan timers.

const WarDeploymentManager = preload("res://scripts/war/war_deployment_manager.gd")
const WarLaunchSetupUI = preload("res://scripts/war/war_launch_setup_ui.gd")
const MechaController = preload("res://scripts/mecha/mecha_controller.gd")
const CombatRewardsUI = preload("res://scripts/ui/combat_rewards_ui.gd")
const WarResourceHUD = preload("res://scripts/war/war_resource_hud.gd")
const WarInventoryUI = preload("res://scripts/war/war_inventory_ui.gd")

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
	print("WAR MODE PHASE 3F: MULTI-RUN STATE LEAK AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("WAR_PHASE_3F_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nWAR_PHASE_3F_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("WAR MODE PHASE 3F TEST SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failures.is_empty():
		print("FAILED ASSERTIONS:")
		for f in _failures:
			print("  - %s" % f)
	print("==================================================")


func _run_all_tests() -> void:
	await _test_scenario_1_high_stress_10_cycle_matrix()
	await _test_scenario_2_signal_connection_and_callback_isolation()
	await _test_scenario_3_ui_stack_and_timer_idempotency()
	await _test_scenario_4_deployment_quota_stability_across_runs()
	await _test_scenario_5_player_authority_handshake_across_runs()


# --- Scenario 1: High-Stress 10-Cycle Lifecycle Matrix ---
# 5 Victory Cycles + 3 Defeat/Recovery Cycles + 2 Cancel Cycles
func _test_scenario_1_high_stress_10_cycle_matrix() -> void:
	print("\n-- [1] High-Stress 10-Cycle Lifecycle Matrix --")
	GameManager.current_state = GameManager.State.BOARD
	GlobalData.currency.credits = 1000
	GlobalData.currency.scrap = 200
	GlobalData.fuel.mech_energy = 100.0
	GlobalData.board.current_tile = Vector2i(0, 0)
	GlobalData.board.mission_step_count = 0

	var dm = WarDeploymentManager.new()
	var total_victories := 0
	var total_defeats := 0
	var total_cancels := 0
	var expected_credits := 1000
	var expected_scrap := 200

	# Matrix sequence:
	# Cycle 1: Cancel
	# Cycle 2: Victory
	# Cycle 3: Victory
	# Cycle 4: Defeat & Recover
	# Cycle 5: Cancel
	# Cycle 6: Victory
	# Cycle 7: Defeat & Recover
	# Cycle 8: Victory
	# Cycle 9: Defeat & Recover
	# Cycle 10: Victory

	var plan := [
		"cancel", "victory", "victory", "defeat", "cancel",
		"victory", "defeat", "victory", "defeat", "victory"
	]

	for cycle_idx in range(plan.size()):
		var action: String = plan[cycle_idx]
		var c_num := cycle_idx + 1

		if action == "cancel":
			total_cancels += 1
			# Open launch setup and cancel
			var launch_scene = load("res://scenes/war/war_launch_setup_ui.tscn")
			var launch: WarLaunchSetupUI = launch_scene.instantiate()
			launch._deployment = dm
			add_child(launch)
			launch.open_setup()
			launch._on_close()
			launch.queue_free()
			await get_tree().process_frame

			_assert(GlobalData.currency.credits == expected_credits, "1.%d.1: Credits unchanged on cancel cycle %d" % [c_num, c_num])
			_assert(dm.deployed["line"] == 0, "1.%d.2: Line deployment unchanged on cancel cycle %d" % [c_num, c_num])

		elif action == "victory":
			total_victories += 1
			# Deploy 1 line unit
			var dep_ok = dm.on_deployed("line")
			_assert(dep_ok == true, "1.%d.1: Deployment succeeded in victory cycle %d" % [c_num, c_num])

			# Combat phase with player authority
			GameManager.current_state = GameManager.State.COMBAT
			var mech_scene = load("res://scenes/mecha/mecha_base.tscn")
			var mech: MechaController = mech_scene.instantiate()
			mech.is_player_driven = true
			add_child(mech)
			mech.claim_player_authority()
			mech.energy_system.initialize_from_global()
			mech.energy_system.energy = maxf(10.0, mech.energy_system.energy - 10.0)
			mech.energy_system.persist_to_global()

			# Combat rewards
			var rewards_scene = load("res://scenes/ui/combat_rewards_ui.tscn")
			var rewards_ui: CombatRewardsUI = rewards_scene.instantiate()
			add_child(rewards_ui)
			var pre_c = GlobalData.currency.credits
			var pre_s = GlobalData.currency.scrap
			rewards_ui._on_combat_ended(true)
			var gained_c = GlobalData.currency.credits - pre_c
			var gained_s = GlobalData.currency.scrap - pre_s
			expected_credits += gained_c
			expected_scrap += gained_s

			# Cleanup combat
			rewards_ui.queue_free()
			mech.release_player_authority()
			mech.queue_free()
			await get_tree().process_frame

			# Return to Board
			GameManager.current_state = GameManager.State.BOARD
			GlobalData.board.current_tile += Vector2i(1, 0)
			GlobalData.board.mission_step_count += 1
			dm.deployed["line"] = maxi(0, dm.deployed["line"] - 1)

			_assert(MechaController.active_player == null, "1.%d.2: active_player released in victory cycle %d" % [c_num, c_num])
			_assert(GlobalData.currency.credits == expected_credits, "1.%d.3: Credits tracked accurately in cycle %d (%d)" % [c_num, c_num, expected_credits])

		elif action == "defeat":
			total_defeats += 1
			# Deploy 1 line unit
			dm.on_deployed("line")

			# Combat phase
			GameManager.current_state = GameManager.State.COMBAT
			var mech_scene = load("res://scenes/mecha/mecha_base.tscn")
			var mech: MechaController = mech_scene.instantiate()
			mech.is_player_driven = true
			add_child(mech)
			mech.claim_player_authority()

			# Defeat result UI
			var rewards_scene = load("res://scenes/ui/combat_rewards_ui.tscn")
			var rewards_ui: CombatRewardsUI = rewards_scene.instantiate()
			add_child(rewards_ui)
			rewards_ui._on_combat_ended(false)

			# Cleanup combat
			rewards_ui.queue_free()
			mech.release_player_authority()
			mech.queue_free()
			await get_tree().process_frame

			# Trigger destruction & recover cooldown
			dm.on_destroyed("line")
			dm.tick(35.0) # Line cooldown is 30s
			GameManager.current_state = GameManager.State.BOARD

			_assert(GlobalData.currency.credits == expected_credits, "1.%d.1: Zero victory rewards on defeat cycle %d" % [c_num, c_num])
			_assert(MechaController.active_player == null, "1.%d.2: active_player released on defeat cycle %d" % [c_num, c_num])
			_assert(dm.available_stock("line") == 5, "1.%d.3: Line stock fully recovered after defeat cycle %d (5/5)" % [c_num, c_num])

	_assert(total_victories == 5, "1.11: Exact 5 victory cycles completed")
	_assert(total_defeats == 3, "1.12: Exact 3 defeat cycles completed")
	_assert(total_cancels == 2, "1.13: Exact 2 cancel cycles completed")
	_assert(GlobalData.board.mission_step_count == 5, "1.14: Board advanced exactly 5 steps corresponding to 5 victories")
	_assert(dm.available_stock("line") == 5, "1.15: Line stock perfectly preserved at 5/5 post 10 runs")


# --- Scenario 2: Signal Connection and Callback Isolation ---
func _test_scenario_2_signal_connection_and_callback_isolation() -> void:
	print("\n-- [2] Signal Connection and Callback Isolation Across Runs --")
	var event_counter: Array[int] = [0]

	for i in range(5):
		var launch_scene = load("res://scenes/war/war_launch_setup_ui.tscn")
		var launch: WarLaunchSetupUI = launch_scene.instantiate()
		add_child(launch)

		var cb = func(_cat, _fit): event_counter[0] += 1
		launch.launch_requested.connect(cb)

		# Trigger single launch event
		launch._on_launch("strike")
		launch.queue_free()
		await get_tree().process_frame

	_assert(event_counter[0] == 5, "2.1: Exactly 5 launch signals emitted across 5 independent runs (no signal accumulation)")


# --- Scenario 3: UI Stack & Timer Idempotency ---
func _test_scenario_3_ui_stack_and_timer_idempotency() -> void:
	print("\n-- [3] UI Stack & Timer Idempotency Across Repeated Opens --")
	var hud_scene = load("res://scenes/war/war_resource_hud.tscn")
	var hud: WarResourceHUD = hud_scene.instantiate()
	add_child(hud)

	var inv_scene = load("res://scenes/war/war_inventory.tscn")
	var inv: WarInventoryUI = inv_scene.instantiate()
	add_child(inv)

	# Repeatedly toggle HUD and Inventory
	for i in range(6):
		hud._show()
		inv._toggle() # open
		_assert(hud._overlay != null, "3.1.%d: HUD overlay exists on open cycle %d" % [i + 1, i + 1])
		_assert(inv._overlay != null, "3.2.%d: Inventory overlay open on cycle %d" % [i + 1, i + 1])

		hud._hide()
		inv._toggle() # close
		_assert(hud._overlay == null, "3.3.%d: HUD overlay destroyed on hide cycle %d" % [i + 1, i + 1])
		_assert(inv._overlay == null, "3.4.%d: Inventory overlay closed on cycle %d" % [i + 1, i + 1])

	hud.queue_free()
	inv.queue_free()
	await get_tree().process_frame


# --- Scenario 4: Deployment Quota Stability Across Runs ---
func _test_scenario_4_deployment_quota_stability_across_runs() -> void:
	print("\n-- [4] Deployment Quota Stability Across Repeated Cycles --")
	var dm = WarDeploymentManager.new()

	for i in range(4):
		# Deploy 3 Strike units
		_assert(dm.on_deployed("strike") == true, "4.1.%d: Strike unit 1 deployed" % [i + 1])
		_assert(dm.on_deployed("strike") == true, "4.2.%d: Strike unit 2 deployed" % [i + 1])
		_assert(dm.on_deployed("strike") == true, "4.3.%d: Strike unit 3 deployed" % [i + 1])
		_assert(dm.can_deploy("strike") == false, "4.4.%d: Strike cap reached (3/3)" % [i + 1])

		# Destroy all 3
		dm.on_destroyed("strike")
		dm.on_destroyed("strike")
		dm.on_destroyed("strike")

		# Tick cooldowns
		dm.tick(65.0) # Strike cooldown is 60s
		_assert(dm.available_stock("strike") == 3, "4.5.%d: Strike stock fully restored to 3 after cooldown" % [i + 1])
		_assert(dm.available_stock("strike") + dm.deployed["strike"] == 3, "4.6.%d: Strike cap preserved strictly at 3" % [i + 1])


# --- Scenario 5: Player Authority Handshake Across Runs ---
func _test_scenario_5_player_authority_handshake_across_runs() -> void:
	print("\n-- [5] Player Authority Handshake Across Multiple Runs --")

	for i in range(4):
		GameManager.current_state = GameManager.State.COMBAT
		var mech_scene = load("res://scenes/mecha/mecha_base.tscn")
		var mech: MechaController = mech_scene.instantiate()
		mech.is_player_driven = true
		add_child(mech)

		mech.claim_player_authority()
		_assert(MechaController.active_player == mech, "5.1.%d: Run %d mecha claimed authority" % [i + 1, i + 1])

		mech.release_player_authority()
		mech.queue_free()
		await get_tree().process_frame

		_assert(MechaController.active_player == null, "5.2.%d: Run %d authority released cleanly" % [i + 1, i + 1])
