extends Node

class MockHangarController extends Node:
	var selected_slot: String = "body"
	var status_message_label: Label = null
	var total_stats_label: Control = null
	var weight_bar: Control = null
	var garage_panel = null
	var stats_panel = null
	var persist_panel = null
	var part_list_panel = null

	func refresh_after_part_mutation(_slot: String = "") -> void:
		pass

func _ready() -> void:
	print("--- Running durability_rebalance_verify ---")
	_test_armor_break_penalty_rebalance()
	_test_field_patch_penalty_rebalance()
	_test_hangar_repair_zero_penalty()
	_test_hangar_overhaul_durability_restoration()
	print("All durability_rebalance_verify tests passed successfully!")
	get_tree().quit(0)

func _check(condition: bool, msg: String) -> void:
	if condition:
		print("  PASS: %s" % msg)
	else:
		push_error("  FAIL: %s" % msg)
		assert(condition, msg)

func _test_armor_break_penalty_rebalance() -> void:
	print("Testing Armor Break penalty is 3%...")
	GlobalData.weapons.equipped_parts["body"] = {"name": "Test Plate", "uid": "arm_test_1", "durability": 1.0}
	var new_dur = ArmorSystem.degrade_equipped_armor("body", 0.03)
	_check(is_equal_approx(new_dur, 0.97), "Armor break reduces durability by exactly 3% (1.0 -> 0.97)")

func _test_field_patch_penalty_rebalance() -> void:
	print("Testing Field Scrap Patch penalty is 2%...")
	GlobalData.currency.scrap = 100
	GlobalData.weapons.equipped_parts["arm_left"] = {"name": "Test Arm Armor", "uid": "arm_test_2", "durability": 1.0, "max_hp": 50.0}
	GlobalData.weapons.equipped_frames["arm_left"] = {"name": "Test Arm Frame", "uid": "frame_test_2", "durability": 1.0, "max_hp": 50.0}
	GlobalData.weapons.part_damage["arm_left"] = 0.5
	var patch = RepairSystem.apply_emergency_repair("arm_left")
	var dur = GlobalData.get_durability_ratio(GlobalData.weapons.equipped_parts["arm_left"])
	_check(is_equal_approx(dur, 0.98), "Field scrap patch reduces durability by exactly 2% (1.0 -> 0.98)")

func _test_hangar_repair_zero_penalty() -> void:
	print("Testing Hangar Repair has 0% permanent wear penalty...")
	GlobalData.currency.credits = 1000
	GlobalData.weapons.equipped_parts["body"] = {"name": "Test Body Plate", "uid": "arm_test_body", "durability": 0.90}
	GlobalData.weapons.equipped_frames["body"] = {"name": "Test Frame", "uid": "frame_body", "durability": 0.85}
	GlobalData.weapons.part_damage["body"] = 0.50
	GlobalData.weapons.part_damage["body_frame"] = 0.50

	var mock_ctrl := MockHangarController.new()
	add_child(mock_ctrl)
	var lbl := Label.new()
	mock_ctrl.add_child(lbl)
	mock_ctrl.status_message_label = lbl

	var repair_panel := HangarRepairPanel.new()
	repair_panel.controller = mock_ctrl

	repair_panel.repair_part()

	var part_dur = GlobalData.get_durability_ratio(GlobalData.weapons.equipped_parts["body"])
	var frame_dur = GlobalData.get_durability_ratio(GlobalData.weapons.equipped_frames["body"])
	_check(is_equal_approx(part_dur, 0.90), "Hangar part repair does not degrade armor durability (retains 0.90)")
	_check(is_equal_approx(frame_dur, 0.85), "Hangar part repair does not degrade frame durability (retains 0.85)")

	mock_ctrl.queue_free()

func _test_hangar_overhaul_durability_restoration() -> void:
	print("Testing Hangar Overhaul restores durability to 100%...")
	GlobalData.currency.credits = 1000
	GlobalData.currency.scrap = 500
	GlobalData.weapons.equipped_parts["body"] = {"name": "Test Body Plate", "uid": "arm_test_body", "durability": 0.70}
	GlobalData.weapons.equipped_frames["body"] = {"name": "Test Frame", "uid": "frame_body", "durability": 0.65}
	GlobalData.weapons.weapon_loadout["left"] = "wpn_left_1"
	GlobalData.weapons.weapon_inventory = [{"name": "Heavy Rifle", "uid": "wpn_left_1", "durability": 0.60}]

	var mock_ctrl := MockHangarController.new()
	add_child(mock_ctrl)
	var lbl := Label.new()
	mock_ctrl.add_child(lbl)
	mock_ctrl.status_message_label = lbl

	var repair_panel := HangarRepairPanel.new()
	repair_panel.controller = mock_ctrl

	repair_panel.full_overhaul()

	var part_dur = GlobalData.get_durability_ratio(GlobalData.weapons.equipped_parts["body"])
	var frame_dur = GlobalData.get_durability_ratio(GlobalData.weapons.equipped_frames["body"])
	var wpn_dur = GlobalData.get_durability_ratio(GlobalData.weapons.weapon_inventory[0])

	_check(is_equal_approx(part_dur, 1.0), "Overhaul restored armor durability to 1.0 (100%)")
	_check(is_equal_approx(frame_dur, 1.0), "Overhaul restored frame durability to 1.0 (100%)")
	_check(is_equal_approx(wpn_dur, 1.0), "Overhaul restored weapon durability to 1.0 (100%)")

	mock_ctrl.queue_free()
