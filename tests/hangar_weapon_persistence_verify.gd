extends Node3D

## Verification test for Weapon Persistence during Armor Customization in Hangar.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("WEAPON_PERSIST_OK: %s" % msg)
	else:
		_fails += 1
		print("WEAPON_PERSIST_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Hangar Weapon Persistence Verification ---")

	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha = mecha_scene.instantiate()
	add_child(mecha)

	await get_tree().physics_frame
	await get_tree().process_frame

	var pmm = mecha.get_node_or_null("PartMeshManager")
	_check(pmm != null, "PartMeshManager exists")

	# 1. Mount weapons
	var blade := WeaponPart.new()
	blade.weapon_name = "Heat Blade"
	blade.weapon_type = WeaponPart.WeaponType.MELEE

	var rifle := WeaponPart.new()
	rifle.weapon_name = "Beam Rifle"
	rifle.weapon_type = WeaponPart.WeaponType.BEAM_RIFLE

	var w_left = WeaponVisualFactory.mount_hand(mecha, "left", blade, "WeaponVisual_left")
	var w_right = WeaponVisualFactory.mount_hand(mecha, "right", rifle, "WeaponVisual_right")

	_check(w_left != null and w_left.visible, "Left weapon mounted and visible")
	_check(w_right != null and w_right.visible, "Right weapon mounted and visible")

	# 2. Simulate customizing and swapping armor across all slots in Hangar
	for slot in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
		var armor := ArmorPart.new()
		armor.part_name = "Heavy Plate " + slot
		armor.max_hp = 150.0
		pmm.initialize_slot(slot, armor)

	await get_tree().process_frame

	# 3. Check if weapons are STILL visible and NOT hidden by armor swapping
	var forearm_left = mecha.get_node_or_null("ArmLeft/ForearmLeft")
	var forearm_right = mecha.get_node_or_null("ArmRight/ForearmRight")

	var active_w_left = forearm_left.get_node_or_null("WeaponVisual_left") if forearm_left else null
	var active_w_right = forearm_right.get_node_or_null("WeaponVisual_right") if forearm_right else null

	_check(active_w_left != null, "Left weapon still exists on ForearmLeft after armor swap")
	_check(active_w_left != null and active_w_left.visible, "Left weapon is STILL VISIBLE after armor swap")

	_check(active_w_right != null, "Right weapon still exists on ForearmRight after armor swap")
	_check(active_w_right != null and active_w_right.visible, "Right weapon is STILL VISIBLE after armor swap")

	print("--- Hangar Weapon Persistence Verification Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_WEAPON_PERSISTENCE_TESTS_PASSED")
