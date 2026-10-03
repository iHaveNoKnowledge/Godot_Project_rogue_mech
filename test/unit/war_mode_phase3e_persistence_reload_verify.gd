extends Node

## War Mode Phase 3E: Persistence / Save-Reload Integrity Audit & Verification
## Audits save/reload round-trip, state restoration across restarts,
## idempotent double-load safety, and runtime manager reconstruction.

const SaveGameIO = preload("res://scripts/systems/save_game_io.gd")
const WarDeploymentManager = preload("res://scripts/war/war_deployment_manager.gd")
const MechaController = preload("res://scripts/mecha/mecha_controller.gd")
const CombatRewardsUI = preload("res://scripts/ui/combat_rewards_ui.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _failures: Array[String] = []

var _backup_save_data: String = ""
var _had_existing_save: bool = false


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
	print("WAR MODE PHASE 3E: PERSISTENCE & RELOAD AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	_backup_user_save()
	await _run_all_tests()
	_restore_user_save()
	_print_summary()
	if _fail_count > 0:
		push_error("WAR_PHASE_3E_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nWAR_PHASE_3E_SUCCESS")
		get_tree().quit(0)


func _backup_user_save() -> void:
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_had_existing_save = true
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.READ)
		if f:
			_backup_save_data = f.get_as_text()
			f.close()


func _restore_user_save() -> void:
	if _had_existing_save and _backup_save_data != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_string(_backup_save_data)
			f.flush()
			f.close()
	elif not _had_existing_save and FileAccess.file_exists(GlobalData.SAVE_PATH):
		DirAccess.remove_absolute(GlobalData.SAVE_PATH)


func _print_summary() -> void:
	print("\n==================================================")
	print("WAR MODE PHASE 3E TEST SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failures.is_empty():
		print("FAILED ASSERTIONS:")
		for f in _failures:
			print("  - %s" % f)
	print("==================================================")


func _run_all_tests() -> void:
	await _test_scenario_1_controlled_state_save()
	await _test_scenario_2_reload_restoration_verification()
	await _test_scenario_3_repeated_double_load_idempotency()
	await _test_scenario_4_runtime_reconstruction_and_authority()
	await _test_scenario_5_post_reward_save_and_exact_once_reload()


# --- Scenario 1: Controlled State Snapshot & Save ---
func _test_scenario_1_controlled_state_save() -> void:
	print("\n-- [1] Controlled State Construction & Save Execution --")
	GameManager.current_state = GameManager.State.BOARD

	# Currency
	GlobalData.currency.credits = 1234
	GlobalData.currency.scrap = 567
	GlobalData.currency.data_cores = 3

	# Fuel
	GlobalData.fuel.mech_energy = 73.5
	GlobalData.fuel.mech_max_energy = 150.0
	GlobalData.fuel.convoy_fuel_reserve = 88.0

	# Narrative & Security
	GlobalData.narrative.security_upgrade_level = 3
	GlobalData.narrative.fleet_security = 53.0
	GlobalData.narrative.mech_less = false

	# Board & Progression
	GlobalData.board.current_sector = 2
	GlobalData.board.current_tile = Vector2i(4, 3)
	GlobalData.board.board_day = 5
	GlobalData.board.time_hour = 16.5
	GlobalData.board.board_seed = 777888
	GlobalData.board.board_theme_id = "quarry"

	# Hangar & Inventory
	GlobalData.hangar.hangar_mechs = [
		{"id": "alpha_01", "name": "Alpha Frame", "chassis": "valkren", "slot": 1, "pilot": "driver_01"},
		{"id": "beta_02", "name": "Beta Frame", "chassis": "ironclad", "slot": 2, "pilot": "driver_02"}
	]
	GlobalData.hangar.active_hangar_mech_id = "alpha_01"
	GlobalData.hangar.research_unlocked = ["tech_energy_siphon", "tech_armor_hardening"]
	GlobalData.weapons.weapon_inventory = [
		{"id": "wep_beam_rifle", "uid": "w_001", "durability": 1.0, "upgrade_level": 1},
		{"id": "wep_heat_blade", "uid": "w_002", "durability": 1.0, "upgrade_level": 1}
	]

	# Execute Save
	SaveGameIO.save_run()

	_assert(FileAccess.file_exists(GlobalData.SAVE_PATH), "1.1: Save file successfully written to disk")


# --- Scenario 2: Reload Restoration Verification ---
func _test_scenario_2_reload_restoration_verification() -> void:
	print("\n-- [2] State Clear & Reload Restoration Verification --")
	# Wipe in-memory state to defaults
	GlobalData.currency.credits = 0
	GlobalData.currency.scrap = 0
	GlobalData.currency.data_cores = 0
	GlobalData.fuel.mech_energy = 0.0
	GlobalData.fuel.convoy_fuel_reserve = 0.0
	GlobalData.narrative.security_upgrade_level = 1
	GlobalData.narrative.fleet_security = 25.0
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i.ZERO
	GlobalData.board.board_day = 1
	GlobalData.board.time_hour = 8.0
	GlobalData.hangar.hangar_mechs = []
	GlobalData.hangar.active_hangar_mech_id = ""
	GlobalData.hangar.research_unlocked = []
	GlobalData.weapons.weapon_inventory = []

	# Execute Load
	var loaded = SaveGameIO.load_run()
	_assert(loaded == true, "2.1: SaveGameIO.load_run() returned true")

	# Verify Currency
	_assert(GlobalData.currency.credits == 1234, "2.2: Restored credits == 1234")
	_assert(GlobalData.currency.scrap == 567, "2.3: Restored scrap == 567")
	_assert(GlobalData.currency.data_cores == 3, "2.4: Restored data_cores == 3")

	# Verify Fuel
	_assert(GlobalData.fuel.mech_energy == 73.5, "2.5: Restored mech_energy == 73.5")
	_assert(GlobalData.fuel.convoy_fuel_reserve == 88.0, "2.6: Restored convoy_fuel_reserve == 88.0")

	# Verify Narrative & Security
	_assert(GlobalData.narrative.security_upgrade_level == 3, "2.7: Restored security_upgrade_level == 3")
	_assert(GlobalData.narrative.fleet_security == 53.0, "2.8: Restored fleet_security == 53.0")

	# Verify Board & Progression
	_assert(GlobalData.board.current_sector == 2, "2.9: Restored current_sector == 2")
	_assert(GlobalData.board.current_tile == Vector2i(4, 3), "2.10: Restored current_tile == (4, 3)")
	_assert(GlobalData.board.board_day == 5, "2.11: Restored board_day == 5")
	_assert(GlobalData.board.time_hour == 16.5, "2.12: Restored time_hour == 16.5")

	# Verify Hangar & Inventory
	_assert(GlobalData.hangar.hangar_mechs.size() == 2, "2.13: Restored hangar_mechs count == 2")
	_assert(GlobalData.hangar.active_hangar_mech_id == "alpha_01", "2.14: Restored active_hangar_mech_id == 'alpha_01'")
	_assert(GlobalData.hangar.research_unlocked.size() == 2, "2.15: Restored research_unlocked count == 2")
	_assert(GlobalData.weapons.weapon_inventory.size() == 2, "2.16: Restored weapon_inventory count == 2")


# --- Scenario 3: Repeated Double-Load Idempotency ---
func _test_scenario_3_repeated_double_load_idempotency() -> void:
	print("\n-- [3] Repeated Double-Load Idempotency --")
	# Perform 2 successive load operations
	SaveGameIO.load_run()
	SaveGameIO.load_run()

	_assert(GlobalData.currency.credits == 1234, "3.1: Credits not multiplied on double load (1234)")
	_assert(GlobalData.currency.scrap == 567, "3.2: Scrap not multiplied on double load (567)")
	_assert(GlobalData.hangar.hangar_mechs.size() == 2, "3.3: Hangar mechs not duplicated on double load (2)")
	_assert(GlobalData.weapons.weapon_inventory.size() == 2, "3.4: Weapon inventory not duplicated on double load (%d == 2)" % GlobalData.weapons.weapon_inventory.size())
	_assert(GlobalData.hangar.research_unlocked.size() == 2, "3.5: Research not duplicated on double load (2)")


# --- Scenario 4: Runtime Reconstruction & Authority ---
func _test_scenario_4_runtime_reconstruction_and_authority() -> void:
	print("\n-- [4] Runtime Reconstruction & Authority Post-Reload --")
	# Runtime deployment manager initializes cleanly from restored state
	var dm = WarDeploymentManager.new()
	_assert(dm.available_stock("line") == 5, "4.1: Deployment manager initialized with full line stock (5/5)")
	_assert(dm.available_stock("valkyrion") == 1, "4.2: Deployment manager initialized with full valkyrion stock (1/1)")

	# MechaController claims fresh authority without stale references
	GameManager.current_state = GameManager.State.COMBAT
	var mech_scene = load("res://scenes/mecha/mecha_base.tscn")
	var mech = mech_scene.instantiate() as MechaController
	mech.is_player_driven = true
	add_child(mech)

	mech.claim_player_authority()
	mech.energy_system.initialize_from_global()

	_assert(MechaController.active_player == mech, "4.3: Fresh mecha successfully claimed active_player after reload")
	_assert(mech.energy_system.energy == 73.5, "4.4: Mecha energy system initialized to restored 73.5 energy")

	mech.release_player_authority()
	mech.queue_free()
	await get_tree().process_frame
	_assert(MechaController.active_player == null, "4.5: active_player released cleanly")


# --- Scenario 5: Post-Reward Save & Exact-Once Reload ---
func _test_scenario_5_post_reward_save_and_exact_once_reload() -> void:
	print("\n-- [5] Post-Reward Save & Exactly-Once Reload --")
	var rewards_scene = load("res://scenes/ui/combat_rewards_ui.tscn")
	var rewards_ui: CombatRewardsUI = rewards_scene.instantiate()
	add_child(rewards_ui)

	# Grant combat victory reward
	var pre_reward_credits = GlobalData.currency.credits
	rewards_ui._on_combat_ended(true)
	var post_reward_credits = GlobalData.currency.credits
	_assert(post_reward_credits > pre_reward_credits, "5.1: Credits increased after combat reward (%d -> %d)" % [pre_reward_credits, post_reward_credits])

	# Save post-reward state
	SaveGameIO.save_run()

	# Wipe and Reload
	GlobalData.currency.credits = 0
	SaveGameIO.load_run()

	_assert(GlobalData.currency.credits == post_reward_credits, "5.2: Restored exact post-reward credits (%d)" % post_reward_credits)

	rewards_ui.queue_free()
	await get_tree().process_frame
