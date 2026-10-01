extends Node

## Phase 2E-53A: Player Authority Implementation Audit
## Proves that runtime Mecha instances require explicit player authorization
## and that non-player, reserve, preview, enemy, or stale instances cannot mutate GlobalData.

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
	print("PHASE 2E-53A: PLAYER AUTHORITY IMPLEMENTATION AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("PHASE_2E_53A_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_53A_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-53A TEST SUMMARY:")
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
	# Scenario 1: Critical Negative Test — Pure Neutral Unconfigured mecha_base.tscn
	# ===========================================================================
	print("\n-- Scenario 1: Critical Negative Test (Unconfigured mecha_base.tscn) --")
	GlobalData.fuel.mech_energy = 85.0
	GlobalData.fuel.mech_max_energy = 100.0

	var neutral_mech = p_scene.instantiate()
	# Do NOT add group "enemy", do NOT add group "player", do NOT set is_player_driven
	add_child(neutral_mech)

	_assert(neutral_mech.is_player_driven == false, "1.1: Unconfigured mecha_base is NOT player driven by default")
	var es = neutral_mech.get_node_or_null("EnergySystem")
	_assert(es == null or not neutral_mech.is_player_driven, "1.3: Unconfigured mecha_base did NOT acquire player energy authority")

	remove_child(neutral_mech)
	neutral_mech.free()

	_assert(GlobalData.fuel.mech_energy == 85.0, "1.4: Neutral unconfigured mech teardown did NOT mutate GlobalData (retains 85.0)")

	# ===========================================================================
	# Scenario 2: Reserve / Backup Mecha Authority Isolation
	# ===========================================================================
	print("\n-- Scenario 2: Reserve / Backup Mecha Authority Isolation --")
	GlobalData.fuel.mech_energy = 60.0

	# 2A: Coexisting Player and Reserve
	var player_mech = p_scene.instantiate()
	player_mech.name = "Mecha"
	player_mech.add_to_group("player")
	add_child(player_mech)

	_assert(player_mech.is_player_driven == true, "2.1: Player mecha is player driven")
	_assert(MechaController.active_player == player_mech, "2.2: active_player points to player_mech")
	player_mech.energy = 60.0

	var reserve_mech = p_scene.instantiate()
	reserve_mech.name = "ReserveMech"
	reserve_mech.add_to_group("backup_mech")
	add_child(reserve_mech)

	_assert(reserve_mech.is_player_driven == false, "2.3: Reserve mech is NOT player driven")
	_assert(MechaController.active_player == player_mech, "2.4: active_player remains player_mech despite reserve existence")

	# Destroy reserve mech while player is alive
	remove_child(reserve_mech)
	reserve_mech.free()

	_assert(GlobalData.fuel.mech_energy == 60.0, "2.5: Reserve destruction did not mutate GlobalData")
	_assert(MechaController.active_player == player_mech, "2.6: active_player remains player_mech after reserve destruction")

	# 2B: Reverse Destruction Order (Player destroyed first, then reserve)
	var reserve_b = p_scene.instantiate()
	reserve_b.name = "ReserveMechB"
	reserve_b.add_to_group("backup_mech")
	add_child(reserve_b)

	player_mech.energy = 55.0
	remove_child(player_mech)
	player_mech.free()

	_assert(GlobalData.fuel.mech_energy == 55.0, "2.7: Authoritative player teardown persisted energy (55.0)")
	_assert(MechaController.active_player == null, "2.8: active_player is null after player teardown")

	remove_child(reserve_b)
	reserve_b.free()

	_assert(GlobalData.fuel.mech_energy == 55.0, "2.9: Subsequent reserve teardown did NOT overwrite GlobalData (retains 55.0)")

	# ===========================================================================
	# Scenario 3: Hangar / Preview Mannequin Isolation
	# ===========================================================================
	print("\n-- Scenario 3: Hangar / Preview Mannequin Isolation --")
	GlobalData.fuel.mech_energy = 90.0

	var mannequin = p_scene.instantiate()
	mannequin.set_script(null)
	add_child(mannequin)

	remove_child(mannequin)
	mannequin.free()

	_assert(GlobalData.fuel.mech_energy == 90.0, "3.1: Preview mannequin destruction did NOT mutate GlobalData (retains 90.0)")
	_assert(MechaController.active_player == null, "3.2: active_player remains null")

	# ===========================================================================
	# Scenario 4: Enemy Combat Mecha Authority Isolation
	# ===========================================================================
	print("\n-- Scenario 4: Enemy Combat Mecha Authority Isolation --")
	GlobalData.fuel.mech_energy = 72.0

	var enemy_mecha = p_scene.instantiate()
	enemy_mecha.name = "EnemyGrunt"
	enemy_mecha.add_to_group("enemy")
	add_child(enemy_mecha)

	_assert(enemy_mecha.is_player_driven == false, "4.1: Enemy mecha is_player_driven == false")
	_assert(MechaController.active_player == null, "4.2: Enemy mecha cannot become active_player")

	remove_child(enemy_mecha)
	enemy_mecha.free()

	_assert(GlobalData.fuel.mech_energy == 72.0, "4.3: Enemy mecha teardown did NOT mutate GlobalData (retains 72.0)")

	# ===========================================================================
	# Scenario 5: Board Visual Token Isolation
	# ===========================================================================
	print("\n-- Scenario 5: Board Visual Token Isolation --")
	GlobalData.fuel.mech_energy = 88.0

	var board_unit = BoardUnit3D.new()
	board_unit.unit_type = BoardUnit3D.UnitType.PLAYER
	add_child(board_unit)
	board_unit._build_valkren_player()

	_assert(board_unit.production_model != null, "5.1: Board visual token instantiated production model")
	_assert(board_unit.production_model.is_player_driven == false, "5.2: Board visual production model is_player_driven == false")
	_assert(MechaController.active_player == null, "5.3: Board visual token did NOT acquire active_player")

	remove_child(board_unit)
	board_unit.free()

	_assert(GlobalData.fuel.mech_energy == 88.0, "5.4: Board visual teardown did NOT mutate GlobalData (retains 88.0)")

	# ===========================================================================
	# Scenario 6: Stale Player Instance Teardown / Replacement Authority Transition
	# ===========================================================================
	print("\n-- Scenario 6: Stale Player Instance Teardown / Replacement Authority Transition --")
	# P1 created: energy 11.0
	var p1 = p_scene.instantiate()
	p1.name = "Player_P1"
	p1.add_to_group("player")
	add_child(p1)
	p1.energy = 11.0
	_assert(MechaController.active_player == p1, "6.1: P1 is initial active_player")

	# P2 created: energy 77.0
	var p2 = p_scene.instantiate()
	p2.name = "Player_P2"
	p2.add_to_group("player")
	add_child(p2)
	p2.energy = 77.0
	GlobalData.fuel.mech_energy = 77.0
	_assert(MechaController.active_player == p2, "6.2: P2 explicitly supersedes P1 as active_player")

	# Teardown P1 while P2 is active
	remove_child(p1)
	p1.free()

	_assert(GlobalData.fuel.mech_energy == 77.0, "6.3: Stale P1 teardown did NOT overwrite GlobalData (retains 77.0)")
	_assert(MechaController.active_player == p2, "6.4: active_player remains P2 after P1 teardown")

	# Teardown P2
	remove_child(p2)
	p2.free()

	_assert(GlobalData.fuel.mech_energy == 77.0, "6.5: Authoritative P2 teardown committed 77.0")
	_assert(MechaController.active_player == null, "6.6: active_player is null after P2 teardown")

	# ===========================================================================
	# Scenario 7: Explicit Player Authorization Round-Trip
	# ===========================================================================
	print("\n-- Scenario 7: Explicit Player Authorization Round-Trip --")
	GlobalData.fuel.mech_energy = 95.0

	var authorized_player = p_scene.instantiate()
	authorized_player.name = "Mecha"
	authorized_player.is_player_driven = true
	add_child(authorized_player)

	_assert(authorized_player.is_player_driven == true, "7.1: Explicitly authorized player is player driven")
	_assert(MechaController.active_player == authorized_player, "7.2: Explicitly authorized player is active_player")
	_assert(authorized_player.energy == 95.0, "7.3: Energy loaded from GlobalData (95.0)")

	authorized_player.energy = 42.0
	remove_child(authorized_player)
	authorized_player.free()

	_assert(GlobalData.fuel.mech_energy == 42.0, "7.4: Authorized player persisted mutated energy (42.0)")
	_assert(MechaController.active_player == null, "7.5: active_player cleanly reset to null")
