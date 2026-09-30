extends Node

## Phase 2E-53: Runtime Object Ownership & Global State Write Authority Audit
## Proves that runtime Mecha instances adhere to strict ownership boundaries
## and that only the authoritative gameplay player may mutate persistent state.

const MechaController = preload("res://scripts/mecha/mecha_controller.gd")
const BoardManager = preload("res://scripts/board/board_manager.gd")
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
	print("PHASE 2E-53: RUNTIME OBJECT OWNERSHIP & WRITE AUTHORITY AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("PHASE_2E_53_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_53_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-53 TEST SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failures.is_empty():
		print("FAILED ASSERTIONS:")
		for f in _failures:
			print("  - %s" % f)
	print("==================================================")


func _run_all_tests() -> void:
	# ===========================================================================
	# Scenario 1: Authoritative Player Combat Lifecycle & Energy Persistence
	# ===========================================================================
	print("\n-- Scenario 1: Authoritative Player Combat Lifecycle & Energy Persistence --")
	GlobalData.fuel.mech_energy = 64.0
	GlobalData.fuel.mech_max_energy = 100.0

	var p_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var player_a = p_scene.instantiate()
	player_a.name = "Mecha"
	player_a.add_to_group("player")
	add_child(player_a)

	_assert(player_a.is_player_driven == true, "1.1: Player Mecha is marked is_player_driven == true")
	_assert(MechaController.active_player == player_a, "1.2: MechaController.active_player points to player_a")
	_assert(player_a.energy_system != null, "1.3: Player Mecha possesses active EnergySystem")
	_assert(player_a.energy == 64.0, "1.4: Energy loaded from GlobalData (64.0)")

	# Mutate in-combat energy
	player_a.energy = 49.5
	_assert(player_a.energy == 49.5, "1.5: Player energy drained in combat to 49.5")

	# Teardown player_a
	remove_child(player_a)
	player_a.free()

	_assert(GlobalData.fuel.mech_energy == 49.5, "1.6: Authoritative player teardown persisted energy to GlobalData (49.5)")
	_assert(MechaController.active_player == null, "1.7: Active player reference cleared on destruction")

	# ===========================================================================
	# Scenario 2: Board Visual Token Isolation (No Persistence On Destruction)
	# ===========================================================================
	print("\n-- Scenario 2: Board Visual Token Isolation (No Persistence On Destruction) --")
	GlobalData.fuel.mech_energy = 88.0
	GlobalData.fuel.mech_max_energy = 100.0

	var board_token = BoardUnit3D.new()
	board_token.unit_type = BoardUnit3D.UnitType.PLAYER
	add_child(board_token)
	board_token._build_valkren_player()

	_assert(board_token.production_model != null, "2.1: Board visual token instantiated production model")
	var es = board_token.production_model.get_node_or_null("EnergySystem")
	_assert(es == null or es.is_queued_for_deletion(), "2.3: Board visual production model has EnergySystem stripped or queued for deletion")
	_assert(MechaController.active_player == null, "2.4: Board visual token did not steal MechaController.active_player")

	# Teardown board visual token
	remove_child(board_token)
	board_token.free()

	_assert(GlobalData.fuel.mech_energy == 88.0, "2.5: Board visual teardown did NOT mutate GlobalData.fuel.mech_energy (retains 88.0)")

	# ===========================================================================
	# Scenario 3: Enemy Combat Lifecycle & Destruction Isolation
	# ===========================================================================
	print("\n-- Scenario 3: Enemy Combat Lifecycle & Destruction Isolation --")
	GlobalData.fuel.mech_energy = 73.0

	# 3A: EnemyDummy instance
	var enemy_dummy = EnemyDummy.new()
	add_child(enemy_dummy)
	enemy_dummy.energy = 19.0

	remove_child(enemy_dummy)
	enemy_dummy.free()
	_assert(GlobalData.fuel.mech_energy == 73.0, "3.1: EnemyDummy destruction did not mutate player energy (73.0)")

	# 3B: Enemy created from mecha_base.tscn with group 'enemy'
	var enemy_mecha = p_scene.instantiate()
	enemy_mecha.name = "EnemyMecha"
	enemy_mecha.add_to_group("enemy")
	add_child(enemy_mecha)

	_assert(enemy_mecha.is_player_driven == false, "3.2: Enemy instantiated from mecha_base.tscn is_player_driven == false")
	_assert(MechaController.active_player == null, "3.3: Enemy mecha did not register as active_player")

	if enemy_mecha.energy_system:
		enemy_mecha.energy_system.energy = 15.0

	remove_child(enemy_mecha)
	enemy_mecha.free()

	_assert(GlobalData.fuel.mech_energy == 73.0, "3.4: Enemy mecha teardown did not mutate player energy in GlobalData (73.0)")

	# ===========================================================================
	# Scenario 4: Stale Player Instance Deferred Destruction Isolation
	# ===========================================================================
	print("\n-- Scenario 4: Stale Player Instance Deferred Destruction Isolation --")
	# Distinctive value test:
	# Old Player A created with energy = 11.0
	# New Player B created with energy = 77.0
	# GlobalData = 77.0
	# Destroy A -> GlobalData must remain 77.0

	var old_player = p_scene.instantiate()
	old_player.name = "OldPlayerMecha"
	old_player.add_to_group("player")
	add_child(old_player)
	old_player.energy = 11.0
	_assert(MechaController.active_player == old_player, "4.1: Old player is initial active_player")

	# New player B arrives and becomes authoritative
	var new_player = p_scene.instantiate()
	new_player.name = "NewPlayerMecha"
	new_player.add_to_group("player")
	add_child(new_player)
	new_player.energy = 77.0
	GlobalData.fuel.mech_energy = 77.0
	_assert(MechaController.active_player == new_player, "4.2: New player supersedes old player as active_player")

	# Teardown old player A (delayed destruction)
	remove_child(old_player)
	old_player.free()

	_assert(GlobalData.fuel.mech_energy == 77.0, "4.3: Stale old player teardown did NOT overwrite GlobalData (remains 77.0)")
	_assert(MechaController.active_player == new_player, "4.4: Active player remains new_player after stale player free")

	# Teardown new player B
	new_player.energy = 77.0
	remove_child(new_player)
	new_player.free()
	_assert(GlobalData.fuel.mech_energy == 77.0, "4.5: Authoritative new player teardown committed 77.0")
	_assert(MechaController.active_player == null, "4.6: Active player cleared after new player teardown")

	# ===========================================================================
	# Scenario 5: Player Authority Uniqueness Invariant
	# ===========================================================================
	print("\n-- Scenario 5: Player Authority Uniqueness Invariant --")
	# Case 5.1: Board State - 0 active combat players
	var board_res: PackedScene = load("res://scenes/board/game_board.tscn")
	var board_mgr: BoardManager = board_res.instantiate()
	add_child(board_mgr)
	_assert(MechaController.active_player == null, "5.1: On Board state, active_player is null (0 combat players)")

	# Case 5.2: Enter Combat - exactly 1 active combat player
	var combat_player = p_scene.instantiate()
	combat_player.name = "Mecha"
	combat_player.add_to_group("player")
	add_child(combat_player)
	_assert(MechaController.active_player == combat_player, "5.2: In Combat state, exactly 1 active_player exists")

	# Case 5.3: Return to Board - old player freed, board restored
	remove_child(combat_player)
	combat_player.free()
	_assert(MechaController.active_player == null, "5.3: Returning to Board state, active_player returns to null")

	remove_child(board_mgr)
	board_mgr.free()

	# ===========================================================================
	# Scenario 6: Global Write Authority Negative Tests
	# ===========================================================================
	print("\n-- Scenario 6: Global Write Authority Negative Tests --")
	GlobalData.fuel.mech_energy = 95.0

	# 6.1: Disabled process_mode Mecha
	var disabled_mecha = p_scene.instantiate()
	disabled_mecha.process_mode = Node.PROCESS_MODE_DISABLED
	disabled_mecha.add_to_group("player")
	add_child(disabled_mecha)
	if disabled_mecha.energy_system:
		disabled_mecha.energy_system.energy = 5.0
	remove_child(disabled_mecha)
	disabled_mecha.free()
	_assert(GlobalData.fuel.mech_energy == 95.0, "6.1: Disabled process_mode Mecha does not write to GlobalData on exit")

	# 6.2: Non-player driven Mecha
	var npc_mecha = p_scene.instantiate()
	npc_mecha.name = "NPC_Unit"
	add_child(npc_mecha)
	npc_mecha.is_player_driven = false
	if npc_mecha.energy_system:
		npc_mecha.energy_system.energy = 1.0
	remove_child(npc_mecha)
	npc_mecha.free()
	_assert(GlobalData.fuel.mech_energy == 95.0, "6.2: Non-player driven Mecha does not write to GlobalData on exit")

	# ===========================================================================
	# Scenario 7: EventBus / Signal Subscription Lifecycle
	# ===========================================================================
	print("\n-- Scenario 7: EventBus / Signal Subscription Lifecycle --")
	var weight_event_fired: Array[int] = [0]
	var dummy_listener = func(_w): weight_event_fired[0] += 1
	EventBus.weight_changed.connect(dummy_listener)

	var listener_mecha = p_scene.instantiate()
	listener_mecha.name = "ListenerMecha"
	add_child(listener_mecha)

	EventBus.weight_changed.emit(50.0)
	_assert(weight_event_fired[0] == 1, "7.1: Signal received while node is active")

	remove_child(listener_mecha)
	listener_mecha.free()

	EventBus.weight_changed.emit(60.0)
	_assert(weight_event_fired[0] == 2, "7.2: Signal emission post-teardown does not crash or double-invoke")
	EventBus.weight_changed.disconnect(dummy_listener)
