extends Node

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	print("=== Starting War Mode Combat & Hangar Camera Verification ===")
	_test_hangar_camera_coordinates()
	_test_hangar_building_dimensions()
	_test_war_world_combat_and_weapon_hud_integration()

	print("=== War Combat & Hangar Cam Finished: %d passed, %d failed ===" % [_passed, _failed])
	if _failed == 0:
		print("ALL_WAR_COMBAT_AND_HANGAR_TESTS_PASSED")
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("WAR_COMBAT_OK: %s" % label)
	else:
		_failed += 1
		push_error("WAR_COMBAT_FAIL: %s" % label)


func _test_hangar_camera_coordinates() -> void:
	var cams: Dictionary = MechaScaleSystem.HANGAR_CAM

	# Mecha faces -Z in Godot 3D.
	# Front features (head, body, arms, legs) must be at negative Z looking toward +Z.
	_assert(cams["head"]["pos"].z < 0.0, "Head camera pos Z is negative (front of mecha): %.2f" % cams["head"]["pos"].z)
	_assert(cams["body"]["pos"].z < 0.0, "Body camera pos Z is negative (front of mecha): %.2f" % cams["body"]["pos"].z)
	_assert(cams["arm_left"]["pos"].z < 0.0, "Left Arm camera pos Z is negative (front of mecha): %.2f" % cams["arm_left"]["pos"].z)
	_assert(cams["arm_right"]["pos"].z < 0.0, "Right Arm camera pos Z is negative (front of mecha): %.2f" % cams["arm_right"]["pos"].z)
	_assert(cams["leg_left"]["pos"].z < 0.0, "Left Leg camera pos Z is negative (front of mecha): %.2f" % cams["leg_left"]["pos"].z)
	_assert(cams["leg_right"]["pos"].z < 0.0, "Right Leg camera pos Z is negative (front of mecha): %.2f" % cams["leg_right"]["pos"].z)

	# Backpack / Weapon Carry is behind the mecha, so camera pos Z must be positive.
	_assert(cams["weapon_carry"]["pos"].z > 0.0, "Backpack / Carry camera pos Z is positive (behind mecha): %.2f" % cams["weapon_carry"]["pos"].z)
	_assert(cams["default"]["pos"].z < 0.0, "Default camera pos Z is negative (front perspective): %.2f" % cams["default"]["pos"].z)


func _test_hangar_building_dimensions() -> void:
	var base := ForwardBase.new()
	add_child(base)
	base.spawn_base("fortified", Vector3.ZERO)

	var hangar = base.get_node_or_null("Mech_Hangar")
	_assert(hangar != null, "Mech_Hangar exists in fortified ForwardBase")

	# Check interior clearance dimensions
	var col_shape: CollisionShape3D = null
	for child in hangar.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			col_shape = child
			break

	# Check against the updated hangar size (18.0 x 10.0 x 22.0)
	var hangar_def: Dictionary = {}
	for d in ForwardBase.BUILDINGS_FORTIFIED:
		if d.get("name") == "Mech Hangar":
			hangar_def = d
			break

	var size: Vector3 = hangar_def.get("size", Vector3.ZERO)
	_assert(size.x >= 16.0, "Hangar width is spacious (size.x = %.1f >= 16.0m)" % size.x)
	_assert(size.y >= 9.0, "Hangar height has high vertical clearance (size.y = %.1f >= 9.0m)" % size.y)
	_assert(size.z >= 20.0, "Hangar depth accommodates camera travel without clipping (size.z = %.1f >= 20.0m)" % size.z)

	# Check that all camera offsets fit well within half-extents of the enlarged hangar
	var half_w: float = size.x * 0.5 - 0.5
	var half_d: float = size.z * 0.5 - 0.5
	var all_fit: bool = true
	for slot in MechaScaleSystem.HANGAR_CAM:
		var slot_val = MechaScaleSystem.HANGAR_CAM[slot]
		if slot_val is Dictionary and slot_val.has("pos"):
			var p: Vector3 = slot_val["pos"]
			if absf(p.x) >= half_w or absf(p.z) >= half_d:
				all_fit = false
				push_error("Camera offset for slot %s exceeds hangar walls: %s" % [slot, str(p)])
	_assert(all_fit, "All camera focus positions remain safely inside the hangar interior without clipping walls")

	base.queue_free()


func _test_war_world_combat_and_weapon_hud_integration() -> void:
	var world_scene = load("res://scenes/war/war_world.tscn")
	_assert(world_scene != null, "war_world.tscn loaded successfully")

	var world = world_scene.instantiate()
	add_child(world)

	_assert(GameManager.current_state == GameManager.State.WAR, "GameManager.current_state is set to State.WAR")

	var mecha: Node3D = world.get_node_or_null("Mecha")
	_assert(mecha != null, "Mecha node exists in War World")

	var wm = mecha.get_node_or_null("WeaponManager")
	_assert(wm != null, "Mecha has WeaponManager child node attached")

	_assert(GameManager.active_player_mecha == mecha, "GameManager.active_player_mecha points to player Mecha")

	# Weapons must be equipped
	_assert(wm.left_hand != null, "WeaponManager has weapon in left hand: %s" % (wm.left_hand.weapon_name if wm.left_hand else "null"))
	_assert(wm.right_hand != null, "WeaponManager has weapon in right hand: %s" % (wm.right_hand.weapon_name if wm.right_hand else "null"))
	_assert(wm.carry.size() >= 1, "WeaponManager has weapon in back carry: %d items" % wm.carry.size())
	_assert(wm.battle_reserve.size() > 0, "WeaponManager has battle reserve ammo allocated")

	# WeaponHUD integration
	var whud = world.get_node_or_null("WeaponHUD")
	_assert(whud != null, "WeaponHUD exists in War World")
	_assert(whud.weapon_manager == wm, "WeaponHUD successfully bound to player Mecha's WeaponManager")

	whud._update_display()
	_assert(whud.left_name_label.text != "" and not whud.left_name_label.text.begins_with("BARE FIST"), "WeaponHUD left label displays equipped weapon: %s" % whud.left_name_label.text)
	_assert(whud.right_name_label.text != "" and not whud.right_name_label.text.begins_with("BARE FIST"), "WeaponHUD right label displays equipped weapon: %s" % whud.right_name_label.text)

	# Carry swap panel interaction
	wm._start_selection("left")
	_assert(wm._selecting_left == true, "Selecting left hand weapon swap is active")
	whud._show_carry("left")
	_assert(whud.carry_panel.visible == true, "WeaponHUD carry panel opens on weapon swap key")
	whud._hide_carry()
	wm._commit_selection("left")

	world.queue_free()
