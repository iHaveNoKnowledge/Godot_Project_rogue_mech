extends Node

func _ready() -> void:
	print("--- Running shoulder_weapons_verify ---")
	_test_loadout_shoulder_methods()
	_test_shoulder_weight_calculation()
	_test_weapon_visual_mounting()
	_test_weapon_manager_shoulder_integration()
	_test_weapon_hud_shoulder_nodes()
	print("All shoulder_weapons_verify tests passed successfully!")
	get_tree().quit(0)

func _check(condition: bool, msg: String) -> void:
	if condition:
		print("  PASS: %s" % msg)
	else:
		push_error("  FAIL: %s" % msg)
		assert(condition, msg)

func _test_loadout_shoulder_methods() -> void:
	print("Testing LoadoutSystem shoulder equip & persistence...")
	GlobalData.weapons.reset()
	var test_path := "res://resources/mech/stock/weapon_combat_shotgun.tres"
	_check(ResourceLoader.exists(test_path), "Test weapon resource exists: " + test_path)

	# Register 2 instances of combat shotgun
	var uid1 = LoadoutSystem.register_weapon(test_path, "Shotgun 1")
	var uid2 = LoadoutSystem.register_weapon(test_path, "Shotgun 2")

	LoadoutSystem.set_shoulder_weapon("left", uid1)
	_check(LoadoutSystem.get_equipped_shoulder("left") != null, "get_equipped_shoulder('left') returns weapon resource")
	_check(LoadoutSystem.get_equipped_shoulder_uid("left") == uid1, "get_equipped_shoulder_uid('left') matches set uid")
	_check(LoadoutSystem.weapon_equipped_slot_by_uid(uid1) == "shoulder_left", "weapon_equipped_slot_by_uid detects shoulder_left")
	_check(LoadoutSystem.weapon_equipped_slot(test_path) == "shoulder_left", "weapon_equipped_slot detects shoulder_left")

	LoadoutSystem.set_shoulder_weapon("right", uid2)
	_check(LoadoutSystem.get_equipped_shoulder("right") != null, "get_equipped_shoulder('right') returns weapon resource")
	_check(LoadoutSystem.weapon_equipped_slot_by_uid(uid2) == "shoulder_right", "weapon_equipped_slot_by_uid detects shoulder_right")
	_check(LoadoutSystem.weapon_equipped_slot_ref(uid1) == "shoulder_left", "weapon_equipped_slot_ref finds shoulder_left")
	_check(LoadoutSystem.weapon_equipped_slot_ref(uid2) == "shoulder_right", "weapon_equipped_slot_ref finds shoulder_right")

	LoadoutSystem.set_shoulder_weapon("left", "")
	_check(LoadoutSystem.get_equipped_shoulder("left") == null, "get_equipped_shoulder('left') cleared to null")
	_check(LoadoutSystem.weapon_equipped_slot(test_path) == "shoulder_right", "weapon_equipped_slot now points to shoulder_right")

	LoadoutSystem.set_shoulder_weapon("right", "")

func _test_shoulder_weight_calculation() -> void:
	print("Testing LoadoutSystem weight includes shoulder weapons...")
	GlobalData.weapons.reset()
	var test_path := "res://resources/mech/stock/weapon_combat_shotgun.tres"
	var res = load(test_path)
	var weapon_weight: float = float(res.weight) if ("weight" in res and res.weight != null) else 0.0

	var base_weight = LoadoutSystem.get_loadout_weapons_total()
	var uid1 = LoadoutSystem.register_weapon(test_path, "Shotgun L")
	var uid2 = LoadoutSystem.register_weapon(test_path, "Shotgun R")

	LoadoutSystem.set_shoulder_weapon("left", uid1)
	var with_left = LoadoutSystem.get_loadout_weapons_total()
	_check(is_equal_approx(with_left, base_weight + weapon_weight), "Equipping shoulder_left increases loadout weapons total by weapon weight")

	LoadoutSystem.set_shoulder_weapon("right", uid2)
	var with_both = LoadoutSystem.get_loadout_weapons_total()
	_check(is_equal_approx(with_both, base_weight + weapon_weight * 2.0), "Equipping shoulder_right increases loadout weapons total by weapon weight * 2")

	LoadoutSystem.set_shoulder_weapon("left", "")
	LoadoutSystem.set_shoulder_weapon("right", "")

func _test_weapon_visual_mounting() -> void:
	print("Testing WeaponVisualFactory.mount_shoulder...")
	var dummy_mecha = Node3D.new()
	add_child(dummy_mecha)

	var test_path := "res://resources/mech/stock/weapon_combat_shotgun.tres"
	var res = load(test_path)
	WeaponVisualFactory.mount_shoulder(dummy_mecha, "left", res, "WeaponVisual_shoulder_left")
	var m_left = dummy_mecha.get_node_or_null("WeaponVisual_shoulder_left")
	_check(m_left != null, "Mounted shoulder left visual on mecha")
	if m_left:
		_check(is_equal_approx(m_left.position.x, WeaponVisualFactory.SHOULDER_LEFT_POS.x), "Shoulder left visual position.x matches SHOULDER_LEFT_POS.x")
		_check(m_left.get_child_count() > 0, "Shoulder left visual has model children")

	WeaponVisualFactory.mount_shoulder(dummy_mecha, "right", res, "WeaponVisual_shoulder_right")
	var m_right = dummy_mecha.get_node_or_null("WeaponVisual_shoulder_right")
	_check(m_right != null, "Mounted shoulder right visual on mecha")
	if m_right:
		_check(is_equal_approx(m_right.position.x, WeaponVisualFactory.SHOULDER_RIGHT_POS.x), "Shoulder right visual position.x matches SHOULDER_RIGHT_POS.x")
		_check(m_right.get_child_count() > 0, "Shoulder right visual has model children")

	dummy_mecha.queue_free()

func _test_weapon_manager_shoulder_integration() -> void:
	print("Testing WeaponManager shoulder weapon loading and firing core...")
	GlobalData.weapons.reset()
	var test_path := "res://resources/mech/stock/weapon_combat_shotgun.tres"
	var uid_l = LoadoutSystem.register_weapon(test_path, "Shotgun L")
	var uid_r = LoadoutSystem.register_weapon(test_path, "Shotgun R")
	LoadoutSystem.set_shoulder_weapon("left", uid_l)
	LoadoutSystem.set_shoulder_weapon("right", uid_r)

	var wm_scene = Node3D.new()
	wm_scene.set_script(load("res://scripts/mecha/weapon_manager.gd"))
	add_child(wm_scene)

	_check(wm_scene.shoulder_left != null, "WeaponManager loaded shoulder_left from loadout")
	_check(wm_scene.shoulder_right != null, "WeaponManager loaded shoulder_right from loadout")

	# Test durability degradation for shoulder
	GlobalData.degrade_weapon_durability("shoulder_left", 0.05)
	var inst_l = LoadoutSystem.get_weapon_instance(uid_l)
	var dur_ratio = GlobalData.get_durability_ratio(inst_l)
	_check(dur_ratio < 0.999, "GlobalData.degrade_weapon_durability degrades shoulder_left durability")

	GlobalData.restore_weapon_durability("shoulder_left", 1.0)
	dur_ratio = GlobalData.get_durability_ratio(inst_l)
	_check(is_equal_approx(dur_ratio, 1.0), "GlobalData.restore_weapon_durability restores shoulder_left durability")

	wm_scene.queue_free()
	LoadoutSystem.set_shoulder_weapon("left", "")
	LoadoutSystem.set_shoulder_weapon("right", "")

func _test_weapon_hud_shoulder_nodes() -> void:
	print("Testing WeaponHUD shoulder panel structure...")
	var hud = CanvasLayer.new()
	hud.set_script(load("res://scripts/ui/weapon_hud.gd"))
	add_child(hud)

	_check(hud.left_shoulder_panel != null, "left_shoulder_panel exists")
	_check(hud.right_shoulder_panel != null, "right_shoulder_panel exists")
	_check(hud.left_shoulder_ammo_label != null, "left_shoulder_ammo_label exists")
	_check(hud.right_shoulder_ammo_label != null, "right_shoulder_ammo_label exists")

	hud.queue_free()
