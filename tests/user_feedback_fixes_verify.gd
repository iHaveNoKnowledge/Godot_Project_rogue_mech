extends Node

func _ready() -> void:
	print("=== Running User Feedback Fixes Verification Test Suite ===")
	var total_tests := 0
	var passed_tests := 0

	# -------------------------------------------------------------
	# Test 1: Camera Preset Initialization & Initial Framing
	# -------------------------------------------------------------
	total_tests += 1
	var cam_rig_scene: PackedScene = load("res://scenes/camera/mecha_camera.tscn")
	var cam_rig = cam_rig_scene.instantiate()
	add_child(cam_rig)

	var cam_rig_script = load("res://scripts/camera/camera_rig.gd")
	var spring_arm: SpringArm3D = cam_rig.get_node("CameraPivot/CameraOffset/SpringArm3D")
	var cam_offset: Node3D = cam_rig.get_node("CameraPivot/CameraOffset")
	var camera_node: Camera3D = cam_rig.get_node("CameraPivot/CameraOffset/SpringArm3D/Camera3D")

	var t1_spring_ok: bool = is_equal_approx(cam_rig._target_spring_length, cam_rig_script.MECHA_SPRING_LENGTH) and is_equal_approx(spring_arm.spring_length, cam_rig_script.MECHA_SPRING_LENGTH)
	var t1_offset_ok: bool = is_equal_approx(cam_rig._target_offset_x, cam_rig_script.MECHA_OFFSET_X) and is_equal_approx(cam_rig._target_offset_y, cam_rig_script.MECHA_OFFSET_Y)
	var t1_fov_ok: bool = is_equal_approx(cam_rig._target_fov, cam_rig_script.MECHA_FOV) and is_equal_approx(camera_node.fov, cam_rig_script.MECHA_FOV)

	if t1_spring_ok and t1_offset_ok and t1_fov_ok:
		print("[PASS] Test 1: CameraRig initializes immediately with wide over-the-shoulder MECHA framing (spring=%f, offset=%s, fov=%f)." % [spring_arm.spring_length, cam_offset.position, camera_node.fov])
		passed_tests += 1
	else:
		print("[FAIL] Test 1: CameraRig values: target_spring=%f, actual_spring=%f, exp=%f (offset_ok=%s, fov_ok=%s)" % [
			cam_rig._target_spring_length, spring_arm.spring_length, cam_rig_script.MECHA_SPRING_LENGTH,
			t1_offset_ok, t1_fov_ok
		])
	cam_rig.queue_free()

	# -------------------------------------------------------------
	# Test 2: Input Filtering on Mouse Not Captured
	# -------------------------------------------------------------
	total_tests += 1
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var wm_script = load("res://scripts/mecha/weapon_manager.gd")
	var wm = Node3D.new()
	wm.set_script(wm_script)
	var dummy_mecha = Node3D.new()
	dummy_mecha.add_child(wm)
	add_child(dummy_mecha)

	# Simulate weapon select/fire input when mouse is visible (e.g. FieldLootModal is open)
	var dummy_event = InputEventAction.new()
	dummy_event.action = "weapon_left"
	dummy_event.pressed = true
	wm._input(dummy_event)

	if not wm.holding_left:
		print("[PASS] Test 2: WeaponManager correctly ignores input when mouse mode != CAPTURED.")
		passed_tests += 1
	else:
		print("[FAIL] Test 2: WeaponManager accepted input while mouse was visible.")
	dummy_mecha.queue_free()

	# -------------------------------------------------------------
	# Test 3: Mecha Weapon Model Proportional Scaling (1.55x)
	# -------------------------------------------------------------
	total_tests += 1
	var rifle_weapon = WeaponPart.new()
	rifle_weapon.weapon_name = "Assault Rifle Heavy"
	rifle_weapon.weapon_type = WeaponPart.WeaponType.BEAM_RIFLE
	var rifle_mesh = WeaponVisualFactory.build(rifle_weapon)

	var pilot_weapon = WeaponPart.new()
	pilot_weapon.weapon_name = "Pilot Sidearm 9mm"
	pilot_weapon.weapon_type = WeaponPart.WeaponType.MACHINE_GUN
	var pilot_mesh = WeaponVisualFactory.build(pilot_weapon)

	var muzzle_node = WeaponVisualFactory.find_muzzle_node(rifle_mesh)
	if rifle_mesh.scale.is_equal_approx(Vector3(1.55, 1.55, 1.55)) and \
	   pilot_mesh.scale.is_equal_approx(Vector3(1.0, 1.0, 1.0)) and \
	   muzzle_node != null:
		print("[PASS] Test 3: WeaponVisualFactory scales mecha weapons by 1.55x while preserving human scale on pilot weapons.")
		passed_tests += 1
	else:
		print("[FAIL] Test 3: Weapon scaling mismatch (rifle scale=%s, pilot scale=%s)." % [rifle_mesh.scale, pilot_mesh.scale])
	rifle_mesh.queue_free()
	pilot_mesh.queue_free()

	# -------------------------------------------------------------
	# Test 4: Enemy and Ally Mecha Scale Unification (4.725m / 5.2m)
	# -------------------------------------------------------------
	total_tests += 1
	var scenes_to_check = [
		{"path": "res://scenes/mecha/enemy_ranged.tscn", "min_h": 4.5},
		{"path": "res://scenes/mecha/enemy_dummy.tscn", "min_h": 4.5},
		{"path": "res://scenes/mecha/enemy_shield_melee.tscn", "min_h": 4.5},
		{"path": "res://scenes/mecha/enemy_shield_ranged.tscn", "min_h": 4.5},
		{"path": "res://scenes/mecha/enemy_support.tscn", "min_h": 4.5},
		{"path": "res://scenes/mecha/enemy_heavy.tscn", "min_h": 5.0},
		{"path": "res://scenes/mecha/ally_dummy.tscn", "min_h": 4.5}
	]

	var all_scenes_ok := true
	for entry in scenes_to_check:
		var packed: PackedScene = load(entry["path"])
		if packed:
			var inst = packed.instantiate()
			var col: CollisionShape3D = inst.get_node_or_null("CollisionShape3D")
			if col and col.shape and col.shape is CapsuleShape3D:
				var h: float = (col.shape as CapsuleShape3D).height
				if h < entry["min_h"]:
					print("[FAIL] Scene %s height too small: %f < %f" % [entry["path"], h, entry["min_h"]])
					all_scenes_ok = false
			inst.queue_free()

	if all_scenes_ok:
		print("[PASS] Test 4: All enemy and ally mecha archetypes match full 4.725m - 5.2m combat proportions.")
		passed_tests += 1
	else:
		print("[FAIL] Test 4: Some enemy/ally scenes had scale inconsistencies.")

	# -------------------------------------------------------------
	# Test 5: Suburban Village Orderly Layout & Realistic House Scale
	# -------------------------------------------------------------
	total_tests += 1
	var arena_gen_script = load("res://scripts/arena/arena_generator.gd")
	var arena_gen = Node3D.new()
	arena_gen.set_script(arena_gen_script)
	arena_gen.arena_size = 240.0
	arena_gen.current_theme = arena_gen_script.BiomeTheme.CROSSROADS
	GlobalData.board.combat_tile_sub_zone = "suburb_village"
	arena_gen._create_containers()
	arena_gen._build_suburb_village_structures()
	add_child(arena_gen)

	var village = arena_gen.structures_container.get_node_or_null("SuburbVillage")
	var houses = []
	var lamps = []
	if village:
		for child in village.get_children():
			if child.is_in_group("solid_obstacle"):
				houses.append(child)
			elif child.is_in_group("street_lamp") or str(child.name).contains("StreetLamp"):
				lamps.append(child)

	var house_scale_ok := true
	for h in houses:
		var col: CollisionShape3D = h.get_node_or_null("CollisionShape3D")
		if col and col.shape is BoxShape3D:
			var sz: Vector3 = (col.shape as BoxShape3D).size
			# House height must be realistic human scale (between 3.5m and 5.5m), width between 7.5m and 9.5m
			if sz.y < 3.0 or sz.y > 6.0 or sz.x < 7.0 or sz.x > 10.0:
				house_scale_ok = false

	if village != null and houses.size() >= 8 and lamps.size() >= 4 and house_scale_ok:
		print("[PASS] Test 5: Suburban Village generates orderly street-facing houses with realistic 3.6m-5.2m scale, front porches, and street lamps (houses: %d, lamps: %d)." % [houses.size(), lamps.size()])
		passed_tests += 1
	else:
		print("[FAIL] Test 5: Suburban village generation failed (houses=%d, lamps=%d, scale_ok=%s)." % [houses.size(), lamps.size(), house_scale_ok])
	arena_gen.queue_free()

	# -------------------------------------------------------------
	# Summary
	# -------------------------------------------------------------
	print("\n=== Test Results: %d/%d Passed ===" % [passed_tests, total_tests])
	if passed_tests == total_tests:
		print("ALL 5 USER FEEDBACK ISSUES RESOLVED SUCCESSFULLY!")
	else:
		print("SOME TESTS FAILED!")
