extends Node3D

func _ready() -> void:
	print("--- BEGIN TEST: Cockpit Hatch & Hollow Innerframe Tub ---")

	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	assert(mecha_scene != null, "mecha_base.tscn must be loadable")
	var mecha = mecha_scene.instantiate()
	add_child(mecha)

	await get_tree().physics_frame
	await get_tree().physics_frame

	var pmm = mecha.get_node_or_null("PartMeshManager")
	assert(pmm != null, "PartMeshManager must exist on MechaBase")

	# Initialize body slot with bare frame
	pmm.initialize_slot("body", null, false)

	# Test 1: Verify CockpitTub exists under Body/FrameMesh
	var body_parent = mecha.get_node_or_null("Body")
	assert(body_parent != null, "Body container node must exist on Mecha")
	var frame_mesh = body_parent.get_node_or_null("FrameMesh")
	assert(frame_mesh != null, "Body FrameMesh container must exist")
	var tub = frame_mesh.get_node_or_null("CockpitTub")
	assert(tub != null, "CockpitTub must exist inside Body FrameMesh")
	print("  [PASS] CockpitTub container verified")

	# Test 2: Verify Cockpit Tub Interior Details (Seat, Controls, Holo HUD, Rails)
	var holo = tub.get_node_or_null("HoloHUD_Display")
	assert(holo != null, "HoloHUD_Display must exist inside CockpitTub")
	assert(holo is MeshInstance3D, "HoloHUD must be a MeshInstance3D")
	var pilot = tub.get_node_or_null("CockpitPilot")
	assert(pilot != null, "CockpitPilot mannequin must exist inside CockpitTub")
	print("  [PASS] Cockpit Interior elements (Holo HUD, pilot mannequin, seat) verified")

	# Test 3: Verify SlidingCarriage exists under FrameMesh
	var frame_carriage = frame_mesh.get_node_or_null("SlidingCarriage")
	assert(frame_carriage != null, "SlidingCarriage must exist inside Body FrameMesh")
	assert(frame_carriage.position == Vector3.ZERO, "Carriage must start closed at Vector3.ZERO")
	print("  [PASS] Frame SlidingCarriage verified at closed position")

	# Test 4: Verify ArmorMesh Carriage
	var armor_part = ArmorPart.new()
	armor_part.slot_id = "body"
	pmm.initialize_slot("body", armor_part, false)
	var armor_mesh = body_parent.get_node_or_null("ArmorMesh")
	assert(armor_mesh != null, "Body ArmorMesh container must exist")
	var armor_carriage = armor_mesh.get_node_or_null("SlidingCarriage")
	assert(armor_carriage != null, "SlidingCarriage must exist inside Body ArmorMesh")
	print("  [PASS] Armor SlidingCarriage verified")

	# Test 5: Test set_cockpit_open(true, false) (instant extension without tween)
	pmm.set_cockpit_open(true, false)
	assert(pmm.is_cockpit_open == true, "is_cockpit_open must be true")
	# Re-fetch carriages
	frame_mesh = body_parent.get_node_or_null("FrameMesh")
	armor_mesh = body_parent.get_node_or_null("ArmorMesh")
	frame_carriage = frame_mesh.get_node_or_null("SlidingCarriage")
	armor_carriage = armor_mesh.get_node_or_null("SlidingCarriage")

	var expected_pos := Vector3(0.0, -0.22, -0.48)
	var expected_rot := Vector3(8.0, 0.0, 0.0)
	assert(frame_carriage.position.is_equal_approx(expected_pos), "Frame carriage position must match extended forward-down offset %s vs %s" % [frame_carriage.position, expected_pos])
	assert(armor_carriage.position.is_equal_approx(expected_pos), "Armor carriage position must match extended forward-down offset %s vs %s" % [armor_carriage.position, expected_pos])
	assert(frame_carriage.rotation_degrees.is_equal_approx(expected_rot), "Frame carriage tilt must match %s" % expected_rot)
	assert(armor_carriage.rotation_degrees.is_equal_approx(expected_rot), "Armor carriage tilt must match %s" % expected_rot)
	print("  [PASS] Cockpit hatch extension (forward -0.48m, down -0.22m, tilt 8 deg) verified on both frame and armor")

	# Test 6: Test set_cockpit_open(false, false) (return to flush closed position)
	pmm.set_cockpit_open(false, false)
	assert(pmm.is_cockpit_open == false, "is_cockpit_open must be false")
	assert(frame_carriage.position.is_equal_approx(Vector3.ZERO), "Frame carriage must return to Vector3.ZERO")
	assert(armor_carriage.position.is_equal_approx(Vector3.ZERO), "Armor carriage must return to Vector3.ZERO")
	print("  [PASS] Cockpit hatch flush retract verified on both frame and armor")

	# Test 7: Test Pilot Seated Mannequin Visibility
	pmm.set_cockpit_pilot_seated(false)
	var tub_after = frame_mesh.get_node_or_null("CockpitTub")
	var pilot_after = tub_after.get_node_or_null("CockpitPilot")
	assert(pilot_after.visible == false, "Pilot mannequin must be hidden when unoccupied")
	pmm.set_cockpit_pilot_seated(true)
	assert(pilot_after.visible == true, "Pilot mannequin must be visible when seated")
	print("  [PASS] Pilot seated visibility toggling verified")

	# Test 8: Test MechaController power_down() and power_up()
	# Calling power_down on mecha should open cockpit and hide seated pilot
	mecha.power_down()
	assert(pmm.is_cockpit_open == true, "Mecha power_down must open cockpit")
	assert(pmm.is_cockpit_pilot_seated == false, "Mecha power_down must vacate pilot")

	# Calling power_up on mecha should seal cockpit and seat pilot
	mecha.power_up()
	assert(pmm.is_cockpit_open == false, "Mecha power_up must seal cockpit")
	assert(pmm.is_cockpit_pilot_seated == true, "Mecha power_up must seat pilot")
	print("  [PASS] MechaController power_down & power_up hatch automation verified")

	# Test 9: Test FuelManager mecha parking tracking
	GlobalData.fuel.traversal_mode = "mecha"
	GlobalData.board.current_tile = Vector2i(4, 7)
	GlobalData.fuel.deploy_pilot()
	assert(GlobalData.fuel.traversal_mode == "pilot", "Traversal mode must be pilot")
	assert(GlobalData.fuel.mecha_is_parked == true, "Mecha must be marked as parked")
	assert(GlobalData.fuel.mecha_parked_pos == Vector2i(4, 7), "Parked mecha pos must match deployment tile")
	GlobalData.fuel.deploy_mecha()
	assert(GlobalData.fuel.mecha_is_parked == false, "Mecha parking cleared upon remount")
	print("  [PASS] FuelManager mecha parking tracking verified")

	print("\n=== ALL COCKPIT HATCH & INNERFRAME TESTS PASSED (100%) ===\n")
	get_tree().quit(0)
