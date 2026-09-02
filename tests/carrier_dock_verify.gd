extends Node

const CarrierDock = preload("res://scripts/war/carrier_dock.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("=== Starting Carrier Docking (Anti-Physics Jitter) Verification ===")
	_test_carrier_structure_and_bays()
	_test_characterbody_dock_and_freeze()
	_test_rigidbody_dock_and_freeze()
	_test_anti_jitter_movement_sync()
	_test_undock_and_physics_restoration()

	print("=== Carrier Docking Finished: %d passed, %d failed ===" % [_passed, _failed])
	if _failed == 0:
		print("ALL_CARRIER_DOCK_TESTS_PASSED")
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("CARRIER_DOCK_OK: %s" % label)
	else:
		_failed += 1
		push_error("CARRIER_DOCK_FAIL: %s" % label)


func _test_carrier_structure_and_bays() -> void:
	var dock := CarrierDock.new()
	var carrier = dock.create_carrier(Vector3(0, 0, 0))
	add_child(carrier)

	_assert(carrier != null, "Carrier hull created")
	_assert(carrier.is_in_group("carrier"), "Carrier is in 'carrier' group")

	var dock0 = carrier.get_node_or_null("Dock0") as Area3D
	var dock1 = carrier.get_node_or_null("Dock1") as Area3D
	_assert(dock0 != null, "Carrier has Dock Bay 0 Area3D")
	_assert(dock1 != null, "Carrier has Dock Bay 1 Area3D")
	_assert(dock0.position.x < 0, "Bay 0 is positioned on Left side (X = %.2f)" % dock0.position.x)
	_assert(dock1.position.x > 0, "Bay 1 is positioned on Right side (X = %.2f)" % dock1.position.x)

	carrier.queue_free()


func _test_characterbody_dock_and_freeze() -> void:
	var world := Node3D.new()
	world.name = "World"
	add_child(world)

	var dock := CarrierDock.new()
	var carrier = dock.create_carrier(Vector3(10, 0, 10))
	world.add_child(carrier)

	var mecha_scene = load("res://scenes/mecha/mecha_base.tscn")
	_assert(mecha_scene != null, "mecha_base.tscn loaded")
	var mecha = mecha_scene.instantiate() as CharacterBody3D
	mecha.name = "TestValkren"
	mecha.collision_layer = 1
	mecha.collision_mask = 3
	world.add_child(mecha)
	mecha.global_position = Vector3(8, 0, 10)

	# Execute Dock
	var dock_success = dock.dock_mech(mecha, carrier, 0)
	_assert(dock_success, "Valkren successfully docked into Bay 0")
	_assert(dock.is_bay_occupied(0), "Bay 0 registered as occupied")
	_assert(dock.get_docked_mech(0) == mecha, "get_docked_mech(0) returns Valkren")

	# Anti-Jitter Invariants
	_assert(not mecha.is_physics_processing(), "Physics process is FROZEN (is_physics_processing == false)")
	_assert(mecha.collision_layer == 0, "Collision layer disabled (0) to eliminate deck collision fighting")
	_assert(mecha.collision_mask == 0, "Collision mask disabled (0)")
	_assert(mecha.get_parent() == carrier.get_node("Dock0"), "Valkren reparented as child of Dock0")
	_assert(mecha.position == Vector3.ZERO, "Valkren local position snapped to ZERO on bay pad")
	_assert(mecha.rotation == Vector3.ZERO, "Valkren local rotation aligned with bay")
	_assert(bool(mecha.get_meta("is_docked")), "Valkren has 'is_docked' metadata flag")

	world.queue_free()


func _test_rigidbody_dock_and_freeze() -> void:
	var world := Node3D.new()
	add_child(world)

	var dock := CarrierDock.new()
	var carrier = dock.create_carrier(Vector3(0, 0, 0))
	world.add_child(carrier)

	var rb := RigidBody3D.new()
	rb.name = "TestTankRigidBody"
	rb.collision_layer = 1
	rb.collision_mask = 1
	world.add_child(rb)

	var dock_success = dock.dock_mech(rb, carrier, 1)
	_assert(dock_success, "RigidBody vehicle successfully docked into Bay 1")
	_assert(rb.freeze, "RigidBody physics is frozen (freeze == true)")
	_assert(rb.freeze_mode == RigidBody3D.FREEZE_MODE_STATIC, "RigidBody freeze mode is STATIC")
	_assert(rb.collision_layer == 0, "RigidBody collision layer disabled")
	_assert(rb.get_parent() == carrier.get_node("Dock1"), "RigidBody reparented as child of Dock1")

	world.queue_free()


func _test_anti_jitter_movement_sync() -> void:
	var world := Node3D.new()
	add_child(world)

	var dock := CarrierDock.new()
	var carrier = dock.create_carrier(Vector3(0, 0, 0))
	world.add_child(carrier)

	var mecha := CharacterBody3D.new()
	mecha.name = "SyncTestMecha"
	world.add_child(mecha)

	dock.dock_mech(mecha, carrier, 0)

	# Simulate heavy Carrier moving 100 meters across rugged terrain
	var move_offset := Vector3(25.0, 5.0, 100.0)
	carrier.global_position += move_offset

	# Valkren must move in perfect lockstep with ZERO relative delta (eliminating jitter)
	_assert(mecha.position == Vector3.ZERO, "Valkren local position remains ZERO while Carrier moves")
	var expected_global = carrier.get_node("Dock0").global_position
	var dist_diff = mecha.global_position.distance_to(expected_global)
	_assert(dist_diff < 0.001, "Valkren global position is perfectly synchronized with Carrier (diff = %.6f)" % dist_diff)

	world.queue_free()


func _test_undock_and_physics_restoration() -> void:
	var world := Node3D.new()
	add_child(world)

	var dock := CarrierDock.new()
	var carrier = dock.create_carrier(Vector3(50, 0, 50))
	world.add_child(carrier)

	var mecha := CharacterBody3D.new()
	mecha.name = "UndockMecha"
	mecha.collision_layer = 1
	mecha.collision_mask = 2
	world.add_child(mecha)

	dock.dock_mech(mecha, carrier, 0)
	_assert(dock.is_bay_occupied(0), "Bay 0 occupied before undock")

	# Move carrier before undocking
	carrier.global_position += Vector3(0, 0, 20.0)
	var expected_deck_pos = carrier.get_node("Dock0").global_position

	# Execute Undock
	var undocked_mech = dock.undock_mech(0, carrier)
	_assert(undocked_mech == mecha, "undock_mech(0) cleanly returned the Valkren")
	_assert(not dock.is_bay_occupied(0), "Bay 0 cleared and available after undock")
	_assert(mecha.get_parent() == world, "Valkren reparented back to world scene")
	_assert(mecha.is_physics_processing(), "Valkren physics process restored (is_physics_processing == true)")
	_assert(mecha.collision_layer == 1, "Valkren collision layer restored to 1")
	_assert(mecha.collision_mask == 2, "Valkren collision mask restored to 2")
	_assert(not mecha.has_meta("is_docked"), "'is_docked' metadata cleared")

	# Verify it stays on the deck pad ready for player drive-off
	var pad_dist = mecha.global_position.distance_to(expected_deck_pos)
	_assert(pad_dist < 0.01, "Undocked Valkren remains exactly in-place on deck launch pad (dist = %.4f)" % pad_dist)

	world.queue_free()
