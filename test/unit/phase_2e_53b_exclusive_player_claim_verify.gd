extends Node

## Phase 2E-53B: Exclusive Player Claim Audit
## Proves that ONLY an explicitly claimed player instance may become active_player,
## that name == "Mecha" is insufficient for player authority, and that non-player
## instances cannot read from or write to persistent GlobalData.

const MechaController = preload("res://scripts/mecha/mecha_controller.gd")
const BoardUnit3D = preload("res://scripts/board/board_unit_3d.gd")
const EnemyDummy = preload("res://scripts/mecha/enemy_dummy.gd")

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
		print("  [FAIL] %s" % message)


func _ready() -> void:
	print("\n==================================================")
	print("PHASE 2E-53B: EXCLUSIVE PLAYER CLAIM AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("PHASE_2E_53B_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_53B_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-53B TEST SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failures.is_empty():
		print("FAILED ASSERTIONS:")
		for f in _failures:
			print("  - %s" % f)
	print("==================================================")


func _run_all_tests() -> void:
	var p_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")

	# ===========================================================================
	# Scenario 1: Critical Test — Player-Named Non-Player (name == "Mecha")
	# ===========================================================================
	print("\n-- Scenario 1: Player-Named Non-Player (name == 'Mecha' without player group) --")
	GlobalData.fuel.mech_energy = 85.0
	GlobalData.fuel.mech_max_energy = 100.0

	var named_mech = p_scene.instantiate()
	named_mech.name = "Mecha" # Has player name BUT no player group and is_player_driven=false
	add_child(named_mech)

	_assert(named_mech.is_player_driven == false, "1.1: Player-named non-player is_player_driven == false")
	_assert(MechaController.active_player == null, "1.2: Player-named non-player did NOT obtain active_player")
	_assert(not named_mech.is_in_group("player"), "1.3: Player-named non-player is NOT in group 'player'")

	if named_mech.energy_system:
		named_mech.energy_system.energy = 10.0

	remove_child(named_mech)
	named_mech.free()

	_assert(GlobalData.fuel.mech_energy == 85.0, "1.4: Player-named non-player teardown did NOT mutate GlobalData (retains 85.0)")

	# ===========================================================================
	# Scenario 2: Non-Enemy Non-Player (Unconfigured Neutral)
	# ===========================================================================
	print("\n-- Scenario 2: Non-Enemy Non-Player (Unconfigured Neutral) --")
	GlobalData.fuel.mech_energy = 85.0

	var neutral_mech = p_scene.instantiate()
	neutral_mech.name = "NeutralDrone"
	add_child(neutral_mech)

	_assert(neutral_mech.is_player_driven == false, "2.1: Neutral drone is_player_driven == false")
	_assert(MechaController.active_player == null, "2.2: Neutral drone did NOT obtain active_player")

	remove_child(neutral_mech)
	neutral_mech.free()

	_assert(GlobalData.fuel.mech_energy == 85.0, "2.3: Neutral drone teardown did NOT mutate GlobalData (retains 85.0)")

	# ===========================================================================
	# Scenario 3: Reserve Mecha Coexistence & Teardown
	# ===========================================================================
	print("\n-- Scenario 3: Reserve Mecha Coexistence & Teardown --")
	GlobalData.fuel.mech_energy = 60.0

	var p1 = p_scene.instantiate()
	p1.name = "PlayerMecha"
	p1.add_to_group("player")
	add_child(p1)

	_assert(p1.is_player_driven == true, "3.1: P1 is player driven")
	_assert(MechaController.active_player == p1, "3.2: active_player is P1")
	p1.energy = 60.0

	var r1 = p_scene.instantiate()
	r1.name = "ReserveMech"
	r1.add_to_group("backup_mech")
	add_child(r1)

	_assert(r1.is_player_driven == false, "3.3: Reserve R1 is NOT player driven")
	_assert(MechaController.active_player == p1, "3.4: active_player remains P1 with R1 present")

	# Destroy reserve R1
	remove_child(r1)
	r1.free()

	_assert(GlobalData.fuel.mech_energy == 60.0, "3.5: R1 destruction did not mutate GlobalData")
	_assert(MechaController.active_player == p1, "3.6: active_player remains P1 after R1 destruction")

	# ===========================================================================
	# Scenario 4: Second Non-Player Named "Mecha" While Player Active
	# ===========================================================================
	print("\n-- Scenario 4: Second Non-Player Named 'Mecha' While Player Active --")
	var second_named = p_scene.instantiate()
	second_named.name = "Mecha" # Same name as player, but unconfigured
	add_child(second_named)

	_assert(second_named.is_player_driven == false, "4.1: Second named 'Mecha' is NOT player driven")
	_assert(MechaController.active_player == p1, "4.2: active_player remains P1 (not stolen by second named instance)")

	remove_child(second_named)
	second_named.free()

	_assert(GlobalData.fuel.mech_energy == 60.0, "4.3: Second named instance destruction did not mutate GlobalData")
	_assert(MechaController.active_player == p1, "4.4: active_player remains P1")

	# Clean up P1
	remove_child(p1)
	p1.free()
	_assert(MechaController.active_player == null, "4.5: active_player cleared after P1 teardown")

	# ===========================================================================
	# Scenario 5: Explicit Player Replacement & Stale Teardown Lifecycle
	# ===========================================================================
	print("\n-- Scenario 5: Explicit Player Replacement & Stale Teardown Lifecycle --")
	GlobalData.fuel.mech_energy = 11.0

	var old_player = p_scene.instantiate()
	old_player.name = "OldPlayer"
	old_player.add_to_group("player")
	add_child(old_player)
	old_player.energy = 11.0

	_assert(MechaController.active_player == old_player, "5.1: Old player is active_player")

	var new_player = p_scene.instantiate()
	new_player.name = "NewPlayer"
	new_player.add_to_group("player")
	add_child(new_player)
	new_player.energy = 77.0
	GlobalData.fuel.mech_energy = 77.0

	_assert(MechaController.active_player == new_player, "5.2: New player superseded old player as active_player")

	# Stale old player exits tree
	remove_child(old_player)
	old_player.free()

	_assert(GlobalData.fuel.mech_energy == 77.0, "5.3: Stale old player teardown did NOT overwrite GlobalData (retains 77.0)")
	_assert(MechaController.active_player == new_player, "5.4: active_player remains new_player after stale player free")

	# New player exits tree
	remove_child(new_player)
	new_player.free()

	_assert(GlobalData.fuel.mech_energy == 77.0, "5.5: Authoritative new player teardown committed 77.0")
	_assert(MechaController.active_player == null, "5.6: active_player reset to null")

	# ===========================================================================
	# Scenario 6: Explicit Authority Claim & Release API Verification
	# ===========================================================================
	print("\n-- Scenario 6: Explicit Authority Claim & Release API Verification --")
	GlobalData.fuel.mech_energy = 92.0

	var manual_player = p_scene.instantiate()
	manual_player.name = "ManualUnit"
	add_child(manual_player)

	_assert(manual_player.is_player_driven == false, "6.1: Initial manual unit is NOT player driven")
	_assert(MechaController.active_player == null, "6.2: Initial active_player is null")

	# Explicitly claim player authority via API
	manual_player.claim_player_authority()
	_assert(manual_player.is_player_driven == true, "6.3: claim_player_authority() enabled is_player_driven")
	_assert(manual_player.is_in_group("player"), "6.4: claim_player_authority() added group 'player'")
	_assert(MechaController.active_player == manual_player, "6.5: claim_player_authority() registered active_player")

	# Explicitly release player authority via API
	manual_player.release_player_authority()
	_assert(MechaController.active_player == null, "6.6: release_player_authority() cleared active_player")

	remove_child(manual_player)
	manual_player.free()

	_assert(GlobalData.fuel.mech_energy == 92.0, "6.7: Released player teardown did NOT mutate GlobalData (retains 92.0)")
