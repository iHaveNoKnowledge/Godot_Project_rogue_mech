extends Node

var _failed := 0
var _passed := 0


func _ready() -> void:
	_clear_global_state()
	_test_part_stat()
	_test_durability_helpers()
	_test_repair_cost_consistency()
	_test_loadout_weight()
	_test_slot_paths()
	print("REPAIR_QA_RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _clear_global_state() -> void:
	GlobalData.part_damage.clear()
	GlobalData.equipped_parts.clear()
	GlobalData.equipped_frames.clear()
	GlobalData.weapon_loadout.clear()
	GlobalData.reset_run_data()


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + name)


func _test_part_stat() -> void:
	var dict_entry := {"hp": 40.0, "armor": 20.0, "weight": 3.5}
	_check(is_equal_approx(GlobalData.part_stat(dict_entry, "hp"), 40.0), "part_stat dict hp")
	_check(is_equal_approx(GlobalData.part_stat(dict_entry, "max_hp"), 40.0), "part_stat dict max_hp alias")
	_check(is_equal_approx(GlobalData.part_stat(dict_entry, "armor"), 20.0), "part_stat dict armor")
	_check(is_equal_approx(GlobalData.part_stat(dict_entry, "weight"), 3.5), "part_stat dict weight")

	var inst := GlobalData.get_armor_instance("qa_part")
	inst["hp"] = 55.0
	_check(is_equal_approx(GlobalData.part_stat(inst, "max_hp"), 55.0), "part_stat instance max_hp")

	var empty: Dictionary = {}
	_check(is_equal_approx(GlobalData.part_stat(empty, "hp", 7.0), 7.0), "part_stat default fallback")


func _test_durability_helpers() -> void:
	var inst := GlobalData.get_armor_instance("qa_durability")
	inst["durability"] = 0.4
	_check(is_equal_approx(GlobalData.get_durability_ratio(inst), 0.4), "get_durability_ratio reads durability")

	GlobalData.part_damage["head"] = 0.25
	GlobalData.part_damage["head_frame"] = 0.5
	_check(is_equal_approx(GlobalData.get_part_durability("head"), 0.75), "get_part_durability live cache")
	_check(is_equal_approx(GlobalData.get_part_durability("body"), 1.0), "get_part_durability undamaged default")


func _test_repair_cost_consistency() -> void:
	GlobalData.part_damage.clear()
	var inst := GlobalData.get_armor_instance("qa_repair")
	inst["hp"] = 50.0
	inst["max_hp"] = 50.0
	GlobalData.equipped_parts["head"] = inst
	GlobalData.equipped_frames["head"] = {"hp": 30.0, "max_hp": 30.0, "weight": 3.0}

	GlobalData.part_damage["head"] = 0.0
	GlobalData.part_damage["head_frame"] = 0.0
	_check(GlobalData.get_repair_cost("head") == 0, "repair cost 0 when undamaged")

	GlobalData.part_damage["head"] = 1.0
	GlobalData.part_damage["head_frame"] = 0.0
	var expected_armor := int(ceil(1.0 * 50.0 * GlobalData.REPAIR_COST_PER_HP))
	_check(GlobalData.get_repair_cost("head") == maxi(1, expected_armor), "armor-only cost matches safehouse formula")

	GlobalData.part_damage["head_frame"] = 1.0
	var expected_frame := int(ceil(1.0 * 30.0 * GlobalData.REPAIR_COST_PER_HP))
	_check(GlobalData.get_repair_cost("head") == maxi(1, expected_armor + expected_frame), "armor+frame cost summed")

	# 25% armor damage on a 50 HP part should cost 25 * 0.5 = 12.5 -> 13
	GlobalData.part_damage["head"] = 0.25
	GlobalData.part_damage["head_frame"] = 0.0
	_check(GlobalData.get_repair_cost("head") == maxi(1, int(ceil(0.25 * 50.0 * 0.5))), "25% dmg cost")


func _test_loadout_weight() -> void:
	GlobalData.weapon_loadout.clear()
	var left = load(GlobalData.DEFAULT_LEFT_WEAPON_PATH)
	var right = load(GlobalData.DEFAULT_RIGHT_WEAPON_PATH)
	var carry = load(GlobalData.DEFAULT_CARRY_WEAPON_PATH)
	GlobalData.set_hand_weapon("left", GlobalData.DEFAULT_LEFT_WEAPON_PATH)
	GlobalData.set_hand_weapon("right", GlobalData.DEFAULT_RIGHT_WEAPON_PATH)
	GlobalData.add_carry_weapon(GlobalData.DEFAULT_CARRY_WEAPON_PATH)
	var expected := float(left.weight) + float(right.weight) + float(carry.weight)
	_check(is_equal_approx(GlobalData.get_loadout_weapons_total(), expected), "loadout weight sums weapons")
	_check(is_equal_approx(GlobalData.get_loadout_weapon_weight(), GlobalData.get_loadout_weapons_total()), "weight alias matches")


func _test_slot_paths() -> void:
	_check(GlobalData.get_slot_node_path("head") == "Head", "slot path head")
	_check(GlobalData.get_slot_node_path("arm_left") == "ArmLeft", "slot path arm_left")
	_check(GlobalData.get_slot_node_path("bogus") == "", "slot path unknown empty")
	_check(GlobalData.MECHA_SLOTS.size() == 6, "MECHA_SLOTS has 6 slots")
	_check("leg_right" in GlobalData.MECHA_SLOTS, "MECHA_SLOTS contains leg_right")
