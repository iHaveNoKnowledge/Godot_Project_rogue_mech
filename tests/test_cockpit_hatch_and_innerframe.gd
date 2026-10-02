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
	# Deterministic baseline: fresh mechs spawn with the hatch OPEN when
	# unoccupied, so force closed before asserting the closed start pose.
	pmm.set_cockpit_open(false, false)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Test 1: Verify CockpitTub exists under Body/FrameMesh
	var body_parent = mecha.get_node_or_null("Body")
	assert(body_parent != null, "Body container node must exist on Mecha")
	var frame_mesh = body_parent.get_node_or_null("FrameMesh")
	assert(frame_mesh != null, "Body FrameMesh container must exist")
	var tub = frame_mesh.get_node_or_null("CockpitTub")
	assert(tub != null, "CockpitTub must exist inside Body FrameMesh")
	print("  [PASS] CockpitTub container verified")

	# Test 2: Verify Cockpit Tub Interior Details (Seat, Controls, Holo HUD, Rails)
	var holo = tub.find_child("HoloHUD_Display", true, false)
	assert(holo != null, "HoloHUD_Display must exist inside CockpitTub")
	assert(holo is MeshInstance3D, "HoloHUD must be a MeshInstance3D")
	var pilot = tub.get_node_or_null("CockpitPilot")
	assert(pilot != null, "CockpitPilot mannequin must exist inside CockpitTub")
	print("  [PASS] Cockpit Interior elements (Holo HUD, pilot mannequin, seat) verified")

	# Test 2.5: Verify WaistCore articulated ball joint sub-node exists under Body FrameMesh
	var waist_core = frame_mesh.get_node_or_null("WaistCore")
	assert(waist_core != null, "WaistCore sub-node must exist inside Body FrameMesh")
	print("  [PASS] Articulated WaistCore hemispherical joint node verified")

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

	var expected_pos := Vector3(0.0, -0.22, -0.44)
	var expected_rot := Vector3(10.0, 0.0, 0.0)
	assert(frame_carriage.position.is_equal_approx(expected_pos), "Frame carriage position must match extended forward-down offset %s vs %s" % [frame_carriage.position, expected_pos])
	assert(armor_carriage.position.is_equal_approx(expected_pos), "Armor carriage position must match extended forward-down offset %s vs %s" % [armor_carriage.position, expected_pos])
	assert(frame_carriage.rotation_degrees.is_equal_approx(expected_rot), "Frame carriage tilt must match %s" % expected_rot)
	assert(armor_carriage.rotation_degrees.is_equal_approx(expected_rot), "Armor carriage tilt must match %s" % expected_rot)
	print("  [PASS] Cockpit hatch extension (forward -0.44m, down -0.22m, tilt 10 deg) verified on both frame and armor")

	# Test 5.1: Verify Articulated Hatch Hydraulic Piston Pivots
	var piv_tub_l = tub.find_child("HatchPivotTub_L", true, false)
	var piv_tub_r = tub.find_child("HatchPivotTub_R", true, false)
	var piv_car_l = frame_carriage.find_child("HatchPivotCarriage_L", true, false)
	var piv_car_r = frame_carriage.find_child("HatchPivotCarriage_R", true, false)
	assert(piv_tub_l != null and piv_tub_r != null, "Tub hydraulic cylinder pivots must exist")
	assert(piv_car_l != null and piv_car_r != null, "Carriage hydraulic rod pivots must exist")
	print("  [PASS] Articulated hatch hydraulic cylinder & rod clevis pivots verified")

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

	# Test 10: Test Stance Mode cycling
	var anim = mecha.get_node_or_null("MechaAnimation")
	assert(anim != null, "MechaAnimation must exist on Mecha")
	assert(anim.stance_mode == "combat_crouch", "Default stance must be combat_crouch")
	anim.set_stance_mode("upright_formal")
	assert(anim.stance_mode == "upright_formal", "Stance must switch to upright_formal")
	anim.set_stance_mode("wide_squat")
	assert(anim.stance_mode == "wide_squat", "Stance must switch to wide_squat")
	anim.set_stance_mode("combat_crouch")
	print("  [PASS] Stance Mode cycling (Kenbu combat_crouch, upright_formal, wide_squat) verified")

	# Test 11: Multi-frame inner frame resolution (Series decoupling)
	# frame_body_04 (Titan Heavy Frame) does not have model_path, should use procedural fallback
	var heavy_frame = ArmorSystem.get_frame_catalog_entry("frame_body_04")
	pmm.initialize_slot("body", null, false, heavy_frame)
	frame_mesh = body_parent.get_node_or_null("FrameMesh")
	var heavy_tub = frame_mesh.get_node_or_null("CockpitTub")
	assert(heavy_tub != null, "Heavy frame CockpitTub must exist via procedural fallback")
	var heavy_waist_core = frame_mesh.get_node_or_null("WaistCore")
	assert(heavy_waist_core == null, "WaistCore (Kenbu asset) must NOT exist on procedural fallback frame_body_04")
	print("  [PASS] frame_body_04 successfully uses procedural fallback skeleton without loading Kenbu asset")

	# Re-initialize with frame_body_01 (Standard Core Structure with Kenbu 3D model)
	var std_frame = ArmorSystem.get_frame_catalog_entry("frame_body_01")
	pmm.initialize_slot("body", null, false, std_frame)
	frame_mesh = body_parent.get_node_or_null("FrameMesh")
	var std_tub = frame_mesh.get_node_or_null("CockpitTub")
	var std_waist_core = frame_mesh.get_node_or_null("WaistCore")
	assert(std_tub != null, "frame_body_01 CockpitTub must exist")
	assert(std_waist_core != null, "frame_body_01 WaistCore must exist from 3D model")
	print("  [PASS] frame_body_01 successfully loads dedicated 3D cockpit model asset")

	print("\n=== ALL COCKPIT HATCH & INNERFRAME TESTS PASSED (100%) ===\n")
	get_tree().quit(0)
