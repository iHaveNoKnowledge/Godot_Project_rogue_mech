extends Node
## FRAME CAPABILITY & COMPATIBILITY VERIFICATION (PHASE 2B-1)
## Validates the authoritative Frame capability system:
## 1. Frame definition lookup
## 2. Frame HP
## 3. Frame weight
## 4. Carry capacity
## 5. Recoil resistance
## 6. Module socket lookup
## 7. Different socket layouts
## 8. Head socket
## 9. Generator compatibility
## 10. Backpack compatibility
## 11. "all" compatibility
## 12. Frame tags
## 13. Base frame ID
## 14. Frame modifications persistence
## 15. Unlocked capabilities persistence
## 16. Old frame data fallback
## 17. Existing arm-frame heavy weapon gating
## 18. Total weight consistency
## 19. Backpack weight included once
## 20. Generator weight included once
## 21. Armor weight included once
## 22. Weapon weight included once

var _fails: int = 0
var _checks: int = 0

const FrameSys = preload("res://scripts/systems/frame_system.gd")
const MechaControllerScript = preload("res://scripts/mecha/mecha_controller.gd")

func _check(cond: bool, test_name: String) -> void:
	_checks += 1
	if cond:
		print("FRAME_OK: " + test_name)
	else:
		_fails += 1
		printerr("FRAME_FAIL: " + test_name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	print("\n=== STARTING FRAME CAPABILITY & STAT VERIFICATION (PHASE 2B-1) ===")
	_test_frame_definition_and_core_stats()
	_test_module_sockets_and_layouts()
	_test_generator_and_backpack_compatibility()
	_test_frame_tags_and_metadata()
	_test_frame_instance_and_modifications_persistence()
	_test_old_frame_data_fallback()
	_test_arm_frame_heavy_weapon_gating()
	_test_total_weight_consistency_and_breakdown()

	print("\n=== FRAME CAPABILITY TEST SUMMARY ===")
	print("Checks: %d, Failures: %d" % [_checks, _fails])
	if _fails == 0:
		print("ALL_FRAME_CAPABILITY_TESTS_PASSED")
		get_tree().quit(0)
	else:
		printerr("FRAME_CAPABILITY_TESTS_FAILED")
		get_tree().quit(1)


func _test_frame_definition_and_core_stats() -> void:
	print("\n-- [1-5] Frame Definition & Core Stats --")
	# 1. Frame definition lookup
	var def_body := FrameSys.get_frame_definition("frame_body_01")
	_check(not def_body.is_empty(), "[1] Frame definition lookup succeeded for frame_body_01")
	_check(def_body.get("id") == "frame_body_01", "[1b] Frame definition has correct ID")

	# 2. Frame HP
	var hp := FrameSys.get_frame_hp("frame_body_01")
	_check(hp == 40.0, "[2] Frame HP resolves correctly (40.0 for frame_body_01)")

	# 3. Frame weight
	var weight := FrameSys.get_frame_weight("frame_body_01")
	_check(weight == 6.0, "[3] Frame weight resolves correctly (6.0 kg for frame_body_01)")

	# 4. Carry capacity
	var carry := FrameSys.get_frame_carry_capacity("frame_body_01")
	_check(carry == 8.0, "[4] Frame carry capacity resolves correctly (8.0 for frame_body_01)")

	# 5. Recoil resistance
	var recoil := FrameSys.get_frame_recoil_resistance("frame_body_01")
	_check(recoil >= 0.0, "[5] Frame recoil resistance is a valid non-negative float")


func _test_module_sockets_and_layouts() -> void:
	print("\n-- [6-8] Module Sockets & Different Layouts --")
	# 6. Module socket lookup
	var body_sockets := FrameSys.get_frame_module_slots("frame_body_01", "body")
	_check(body_sockets == 3, "[6] Body frame module slots lookup returns 3")

	# 7. Different socket layouts (Frame A vs Frame B)
	var frame_a := {
		"id": "frame_custom_a",
		"module_slots": {
			"head": 1, "body": 3, "arm_left": 1, "arm_right": 1, "leg_left": 1, "leg_right": 1
		}
	}
	var frame_b := {
		"id": "frame_custom_b",
		"module_slots": {
			"head": 0, "body": 2, "arm_left": 2, "arm_right": 0, "leg_left": 1, "leg_right": 1
		}
	}
	_check(FrameSys.get_frame_module_slots(frame_a, "head") == 1, "[7a] Frame A head sockets == 1")
	_check(FrameSys.get_frame_module_slots(frame_b, "head") == 0, "[7b] Frame B head sockets == 0")
	_check(FrameSys.get_frame_module_slots(frame_a, "arm_left") == 1, "[7c] Frame A arm_left sockets == 1")
	_check(FrameSys.get_frame_module_slots(frame_b, "arm_left") == 2, "[7d] Frame B arm_left sockets == 2")
	_check(FrameSys.get_frame_module_slots(frame_b, "arm_right") == 0, "[7e] Frame B arm_right sockets == 0")

	# 8. Head socket lookup
	var head_def := FrameSys.get_frame_definition("frame_head_01")
	var head_sockets := FrameSys.get_frame_module_slots(head_def, "head")
	_check(head_sockets == 1, "[8] Standard head frame module slots == 1")


func _test_generator_and_backpack_compatibility() -> void:
	print("\n-- [9-11] Generator & Backpack Compatibility --")
	# 9. Generator compatibility (restricted frame vs universal)
	var frame_diesel_only := {
		"id": "frame_diesel",
		"generator_compatibility": ["combustion"]
	}
	_check(FrameSys.can_equip_generator(frame_diesel_only, "combustion"), "[9a] Frame accepts compatible combustion generator")
	_check(not FrameSys.can_equip_generator(frame_diesel_only, "hybrid"), "[9b] Frame rejects incompatible hybrid generator")
	_check(not FrameSys.can_equip_generator(frame_diesel_only, "ancient"), "[9c] Frame rejects incompatible ancient generator")

	# 10. Backpack compatibility (restricted frame)
	var frame_light := {
		"id": "frame_light_scout",
		"backpack_compatibility": ["booster"]
	}
	_check(FrameSys.can_equip_backpack(frame_light, "booster"), "[10a] Light frame accepts booster backpack")
	_check(not FrameSys.can_equip_backpack(frame_light, "cargo"), "[10b] Light frame rejects cargo backpack")

	# 11. "all" compatibility
	var frame_universal := {
		"id": "frame_standard_core",
		"generator_compatibility": ["all"],
		"backpack_compatibility": ["all"]
	}
	_check(FrameSys.can_equip_generator(frame_universal, "combustion"), "[11a] Universal frame accepts combustion generator")
	_check(FrameSys.can_equip_generator(frame_universal, "hybrid"), "[11b] Universal frame accepts hybrid generator")
	_check(FrameSys.can_equip_generator(frame_universal, "ancient"), "[11c] Universal frame accepts ancient generator")
	_check(FrameSys.can_equip_backpack(frame_universal, "cargo"), "[11d] Universal frame accepts cargo backpack")
	_check(FrameSys.can_equip_backpack(frame_universal, "booster"), "[11e] Universal frame accepts booster backpack")
	_check(FrameSys.can_equip_backpack(frame_universal, "combat"), "[11f] Universal frame accepts combat backpack")


func _test_frame_tags_and_metadata() -> void:
	print("\n-- [12] Frame Tags --")
	# 12. Frame tags
	var heavy_frame := FrameSys.get_frame_definition("frame_body_04")
	var tags_heavy := FrameSys.get_frame_tags(heavy_frame)
	_check("heavy" in tags_heavy, "[12a] Fortress frame has 'heavy' tag")

	var standard_frame := FrameSys.get_frame_definition("frame_body_01")
	var tags_std := FrameSys.get_frame_tags(standard_frame)
	_check("standard" in tags_std, "[12b] Standard frame has 'standard' tag")


func _test_frame_instance_and_modifications_persistence() -> void:
	print("\n-- [13-15] Base Frame ID & Modifications Persistence --")
	# 13. Base frame ID
	var inst := FrameSys.make_frame_instance("frame_body_01", ["reinforced_spine", "auxiliary_socket"], ["quick_eject"])
	_check(inst.get("base_frame_id") == "frame_body_01", "[13] Frame instance stores base_frame_id correctly")

	# 14. Frame modifications persistence
	var mods: Array = inst.get("modifications", [])
	_check(mods.size() == 2, "[14a] Frame instance has 2 modifications")
	_check("reinforced_spine" in mods, "[14b] 'reinforced_spine' modification is present")
	_check("auxiliary_socket" in mods, "[14c] 'auxiliary_socket' modification is present")

	# 15. Unlocked capabilities persistence
	var caps: Array = inst.get("unlocked_capabilities", [])
	_check(caps.size() == 1 and "quick_eject" in caps, "[15] 'quick_eject' capability is present in instance")


func _test_old_frame_data_fallback() -> void:
	print("\n-- [16] Old Frame Data Fallback --")
	# 16. Old frame data without new fields
	var old_frame := {
		"id": "frame_legacy_01",
		"name": "Legacy Rusty Core",
		"hp": 45.0,
		"weight": 5.0,
		"carry_bonus": 4.0,
	}
	_check(not old_frame.has("generator_compatibility"), "Old frame data has no generator_compatibility")
	_check(not old_frame.has("backpack_compatibility"), "Old frame data has no backpack_compatibility")
	_check(not old_frame.has("base_frame_id"), "Old frame data has no base_frame_id")

	# Querying through FrameSystem shouldn't crash and provides safe defaults
	_check(FrameSys.get_frame_hp(old_frame) == 45.0, "[16a] Old frame HP resolves")
	_check(FrameSys.get_frame_weight(old_frame) == 5.0, "[16b] Old frame weight resolves")
	_check(FrameSys.get_frame_carry_capacity(old_frame) == 4.0, "[16c] Old frame carry capacity resolves")
	_check(FrameSys.can_equip_generator(old_frame, "combustion"), "[16d] Old frame defaults to accepting generators")
	_check(FrameSys.can_equip_backpack(old_frame, "booster"), "[16e] Old frame defaults to accepting backpacks")

	var schematized := FrameSys.ensure_frame_instance_schema(old_frame, "body")
	_check(schematized.get("base_frame_id") == "frame_legacy_01", "[16f] Old frame schematized base_frame_id defaults to id")
	_check(schematized.get("generator_compatibility") == ["all"], "[16g] Old frame schematized generator_compatibility == ['all']")
	_check(schematized.get("backpack_compatibility") == ["all"], "[16h] Old frame schematized backpack_compatibility == ['all']")


func _test_arm_frame_heavy_weapon_gating() -> void:
	print("\n-- [17] Existing Arm-Frame Heavy Weapon Gating --")
	GlobalData.reset_run_data()
	GlobalData.weapons.chassis_id = "standard" # chassis power = 12

	# Standard arm frame (carry_bonus 3) -> 12 + 3 = 15 power
	var left_power := FrameSys.get_arm_power("left")
	_check(left_power == 15.0, "[17a] Standard left arm power is 15.0 (chassis 12 + arm frame 3)")

	var railgun = load("res://resources/mech/stock/weapon_railgun.tres")
	_check(railgun.requires_two_hand(left_power), "[17b] 15.0 power cannot one-hand railgun (needs 18)")

	# Equip heavy siege arm (carry_bonus 9) -> 12 + 9 = 21 power
	var frames := GlobalData.weapons.equipped_frames.duplicate(true)
	frames["arm_right"] = FrameSys.get_frame_definition("frame_arm_right_04")
	GlobalData.weapons.equipped_frames = frames

	var right_power := FrameSys.get_arm_power("right")
	_check(right_power == 21.0, "[17c] Heavy arm frame right power is 21.0 (chassis 12 + arm frame 9)")
	_check(not railgun.requires_two_hand(right_power), "[17d] 21.0 power can one-hand railgun")
	_check(FrameSys.get_arm_power("left") == 15.0, "[17e] Left arm power remains independent")


func _test_total_weight_consistency_and_breakdown() -> void:
	print("\n-- [18-22] Total Weight Consistency & Breakdown --")
	GlobalData.reset_run_data()
	ArmorSystem.ensure_default_equipped_parts()

	# 18. Total weight consistency
	var loadout_weight := LoadoutSystem.get_total_mecha_weight()
	_check(loadout_weight > 0.0, "[18a] Authoritative total mecha weight is positive")

	var dummy_ctrl := MechaControllerScript.new()
	add_child(dummy_ctrl)
	dummy_ctrl._recalculate_weight()
	_check(is_equal_approx(dummy_ctrl.total_weight, loadout_weight), "[18b] MechaController total_weight matches LoadoutSystem")
	dummy_ctrl.queue_free()

	# Component breakdown tests:
	# Calculate baseline
	var base_total := LoadoutSystem.get_total_mecha_weight()

	# 19. Backpack weight included once
	BackpackSystem.equip("cargo") # cargo weight is 8.0 kg
	var weight_with_cargo := LoadoutSystem.get_total_mecha_weight()
	BackpackSystem.unequip() # 0 kg
	var weight_no_bp := LoadoutSystem.get_total_mecha_weight()
	_check(is_equal_approx(weight_with_cargo - weight_no_bp, 8.0), "[19] Backpack weight (8.0 kg) included exactly once")

	# 20. Generator weight included once
	GlobalData.weapons.power_core_id = "combustion" # weight = 12.0 kg
	var weight_combustion := LoadoutSystem.get_total_mecha_weight()
	GlobalData.weapons.power_core_id = "ancient" # weight = 4.0 kg
	var weight_ancient := LoadoutSystem.get_total_mecha_weight()
	_check(is_equal_approx(weight_combustion - weight_ancient, 8.0), "[20] Generator weight difference (12 - 4 = 8.0 kg) reflected exactly once")
	GlobalData.weapons.power_core_id = "combustion"

	# 21. Armor weight included once
	var head_part = GlobalData.weapons.equipped_parts.get("head")
	var head_weight: float = float(head_part.get("weight", 0.0)) if head_part is Dictionary else float(head_part.weight)
	GlobalData.weapons.equipped_parts.erase("head")
	var weight_without_head_armor := LoadoutSystem.get_total_mecha_weight()
	_check(is_equal_approx(weight_combustion - weight_without_head_armor, head_weight), "[21] Armor weight included exactly once")
	GlobalData.weapons.equipped_parts["head"] = head_part

	# 22. Weapon weight included once
	var weapon_wt := LoadoutSystem.get_loadout_weapon_weight()
	var prev_w = GlobalData.weapons.weapon_loadout.duplicate(true)
	GlobalData.weapons.weapon_loadout["left"] = ""
	GlobalData.weapons.weapon_loadout["right"] = ""
	GlobalData.weapons.weapon_loadout["shoulder_left"] = ""
	GlobalData.weapons.weapon_loadout["shoulder_right"] = ""
	GlobalData.weapons.weapon_loadout["carry"] = []
	var weight_unarmed := LoadoutSystem.get_total_mecha_weight()
	_check(is_equal_approx(weight_combustion - weight_unarmed, weapon_wt), "[22] Weapon weight included exactly once")
	GlobalData.weapons.weapon_loadout = prev_w
