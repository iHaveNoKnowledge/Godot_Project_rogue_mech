extends Node
## MECHA EQUIPMENT PHASE 1 VERIFICATION
## Validates the Phase 1 architectural separation:
## 1. Existing armor still equips.
## 2. Existing frame still equips.
## 3. Existing modules still equip.
## 4. Existing backpack still equips.
## 5. Existing power core still works.
## 6. Existing weapon loadout still works.
## 7. Existing total weight calculation remains correct.
## 8. Old data without new fields does not crash.
## 9. Existing attachments data does not silently disappear.
## 10. Existing combat behavior remains unchanged.

var _fails: int = 0
var _checks: int = 0

const FrameModuleSys = preload("res://scripts/systems/frame_module_system.gd")
const PowerCoreSys = preload("res://scripts/systems/power_core_system.gd")

func _check(cond: bool, test_name: String) -> void:
	_checks += 1
	if cond:
		print("PHASE1 OK: " + test_name)
	else:
		_fails += 1
		printerr("PHASE1 FAIL: " + test_name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	print("\n=== STARTING MECHA EQUIPMENT PHASE 1 VERIFICATION ===")
	_test_armor_equips()
	_test_frame_equips()
	_test_modules_equip()
	_test_backpack_equips()
	_test_power_core_works()
	_test_weapon_loadout_works()
	_test_total_weight_calculation()
	_test_legacy_data_fallback_and_migration()
	_test_attachments_not_silently_lost()
	_test_combat_behavior_unchanged()

	print("\n=== PHASE 1 TEST SUMMARY ===")
	print("Checks: %d, Failures: %d" % [_checks, _fails])
	if _fails == 0:
		print("ALL_PHASE_1_TESTS_PASSED")
		get_tree().quit(0)
	else:
		printerr("PHASE_1_TESTS_FAILED")
		get_tree().quit(1)


func _test_armor_equips() -> void:
	print("\n-- [1] Existing Armor Still Equips --")
	GlobalData.weapons.reset()
	ArmorSystem.ensure_default_equipped_parts()

	for slot in GlobalData.MECHA_SLOTS:
		var part = GlobalData.weapons.equipped_parts.get(slot)
		_check(part != null and not part.is_empty(), "Slot '%s' has default armor equipped" % slot)
		if part is Dictionary:
			_check(part.has("name") and part.has("durability"), "Armor has name and durability")
			_check(part.has("defense_type"), "Armor has defense_type field")
			_check(part.has("resistance") and (part["resistance"] is Dictionary), "Armor has resistance dictionary")

	# Equip a specific catalog armor piece
	if GlobalData.armor_catalog.has("body") and not GlobalData.armor_catalog["body"].is_empty():
		var first_body_id = str(GlobalData.armor_catalog["body"][0].get("id", ""))
		var inst = ArmorSystem.make_armor_instance_from_catalog(first_body_id)
		_check(not inst.is_empty(), "Created armor instance from catalog")
		var equipped = ArmorSystem.equip_armor_instance(inst["uid"], "body")
		_check(equipped, "Equipped armor instance into body slot")
		var current = GlobalData.weapons.equipped_parts.get("body")
		_check(current is Dictionary and current.get("uid") == inst["uid"], "Equipped part matches new instance uid")


func _test_frame_equips() -> void:
	print("\n-- [2] Existing Frame Still Equips --")
	GlobalData.weapons._ensure_default_frames()

	for slot in GlobalData.MECHA_SLOTS:
		var frame = GlobalData.weapons.equipped_frames.get(slot)
		_check(frame is Dictionary and not frame.is_empty(), "Slot '%s' has default frame equipped" % slot)
		_check(frame.has("frame_set_id"), "Frame has frame_set_id: '%s'" % frame.get("frame_set_id", ""))
		_check(frame.has("recoil_resistance"), "Frame has recoil_resistance")
		_check(frame.has("max_armor_capacity"), "Frame has max_armor_capacity")
		_check(frame.has("generator_compatibility"), "Frame has generator_compatibility")
		_check(frame.has("backpack_compatibility"), "Frame has backpack_compatibility")
		_check(frame.has("frame_tags"), "Frame has frame_tags")


func _test_modules_equip() -> void:
	print("\n-- [3] Existing Modules Still Equip --")
	FrameModuleSys.init_slots_if_needed()

	# Test installing module into authoritative FrameModuleSystem
	var ok = FrameModuleSys.install_module("leg_left", 0, "v8_twin_turbo")
	_check(ok, "Installed v8_twin_turbo into leg_left:0")
	_check(FrameModuleSys.has_module("v8_twin_turbo"), "has_module recognizes installed module")

	# Test uninstall
	var uninstalled = FrameModuleSys.uninstall_module("leg_left", 0)
	_check(uninstalled == "v8_twin_turbo", "Uninstall returns correct module ID")
	_check(not FrameModuleSys.has_module("v8_twin_turbo"), "Module no longer active after uninstall")


func _test_backpack_equips() -> void:
	print("\n-- [4] Existing Backpack Still Equips --")
	BackpackSystem.unequip()
	_check(BackpackSystem.get_equipped_backpack().is_empty(), "Backpack empty after unequip")
	_check(BackpackSystem.get_backpack_weight() == 0.0, "Unequipped backpack weight is 0.0")
	_check(BackpackSystem.get_backpack_carry_bonus() == 0.0, "Unequipped backpack carry bonus is 0.0")

	# Equip cargo backpack
	var ok = BackpackSystem.equip("cargo")
	_check(ok, "Equipped cargo backpack")
	var bp = BackpackSystem.get_equipped_backpack()
	_check(bp.get("id") == "cargo", "Equipped backpack id is 'cargo'")
	_check(BackpackSystem.get_backpack_weight() == 8.0, "Cargo backpack weight is 8.0 kg")
	_check(BackpackSystem.get_backpack_carry_bonus() == 40.0, "Cargo backpack grants +40.0 kg capacity")

	# Field pack capacity reflects backpack bonus
	var cap = LoadoutSystem.get_field_pack_capacity()
	_check(cap >= GlobalData.FIELD_PACK_BASE_CAPACITY + 40.0, "Field pack capacity includes backpack bonus")

	# Switch to booster backpack
	BackpackSystem.equip("booster")
	_check(BackpackSystem.get_equipped_backpack().get("id") == "booster", "Switched to booster backpack")
	_check(BackpackSystem.get_backpack_weight() == 6.0, "Booster backpack weight is 6.0 kg")


func _test_power_core_works() -> void:
	print("\n-- [5] Existing Power Core Still Works --")
	GlobalData.weapons.power_core_id = "combustion"
	var cdef = PowerCoreSys.get_current_core_def()
	_check(cdef.get("id") == "combustion", "Combustion power core definition resolved")
	_check(PowerCoreSys.board_cost_multiplier() == 1.0, "Combustion board cost multiplier is 1.0")

	GlobalData.weapons.power_core_id = "hybrid"
	_check(PowerCoreSys.board_cost_multiplier() == 0.8, "Hybrid board cost multiplier is 0.8")
	_check(PowerCoreSys.dash_speed_multiplier() == 1.25, "Hybrid overclock speed multiplier is 1.25")

	GlobalData.weapons.power_core_id = "ancient"
	_check(PowerCoreSys.board_cost_multiplier() == 0.0, "Ancient board cost multiplier is 0.0 (GN Drive free movement)")

	# Restore default
	GlobalData.weapons.power_core_id = "combustion"


func _test_weapon_loadout_works() -> void:
	print("\n-- [6] Existing Weapon Loadout Still Works --")
	GlobalData.weapons.reset()
	var left_w = LoadoutSystem.get_equipped_weapon("left")
	var right_w = LoadoutSystem.get_equipped_weapon("right")
	_check(left_w != null, "Default left hand weapon equipped")
	_check(right_w != null, "Default right hand weapon equipped")
	var loadout_w_weight = LoadoutSystem.get_loadout_weapon_weight()
	_check(loadout_w_weight > 0.0, "Loadout weapon weight is positive")


func _test_total_weight_calculation() -> void:
	print("\n-- [7] Existing Total Weight Calculation Remains Correct --")
	BackpackSystem.unequip()
	var weight_no_bp = LoadoutSystem.get_total_mecha_weight()
	_check(weight_no_bp > 0.0, "Total mecha weight without backpack is positive")

	BackpackSystem.equip("combat")
	var weight_with_bp = LoadoutSystem.get_total_mecha_weight()
	_check(is_equal_approx(weight_with_bp, weight_no_bp + 10.0), "Total mecha weight increases by exactly combat backpack weight (+10.0kg)")


func _test_legacy_data_fallback_and_migration() -> void:
	print("\n-- [8] Old Data Without New Fields Does Not Crash & Migrates --")
	# Craft a legacy save dictionary where backpack and modules are in attachments
	var legacy_save: Dictionary = {
		"chassis": "standard",
		"power_core": "hybrid",
		"attachments": [
			{"id": "cargo", "type": "backpack", "slot": "backpack", "weight": 2.0},
			{"id": "mod_targeting_fcs", "slot": "head", "type": "sensor"},
			{"id": "cosmetic_antenna", "slot": "head", "type": "cosmetic", "position": {"x": 0, "y": 1, "z": 0}}
		],
		"parts": {},
		"frames": {},
		"weapon_loadout": {}
	}

	SaveGameIO.restore_from_dict(legacy_save)

	# Check that backpack was migrated to equipped_backpack
	_check(BackpackSystem.get_equipped_backpack().get("id") == "cargo", "Legacy backpack in attachments migrated to equipped_backpack")
	# Check that module was migrated to frame_modules
	_check(FrameModuleSys.get_installed_module_id("head", 0) == "mod_targeting_fcs", "Legacy module in attachments migrated to frame_modules")
	# Check that cosmetic attachment remained in attachments
	var has_cosmetic := false
	for att in GlobalData.weapons.attachments:
		if att is Dictionary and att.get("id") == "cosmetic_antenna":
			has_cosmetic = true
	_check(has_cosmetic, "Cosmetic antenna remains in attachments array")


func _test_attachments_not_silently_lost() -> void:
	print("\n-- [9] Existing Attachments Data Does Not Silently Disappear --")
	GlobalData.weapons.attachments.clear()
	GlobalData.weapons.attachments.append({
		"id": "scrap_plate_alpha",
		"type": "scrap",
		"weight": 1.5,
		"position": Vector3(0.1, 0.2, 0.3)
	})

	GlobalData.migrate_legacy_attachments()
	_check(GlobalData.weapons.attachments.size() == 1, "Scrap plate attachment preserved during migration")
	_check(GlobalData.weapons.attachments[0].get("id") == "scrap_plate_alpha", "Attachment ID preserved")


func _test_combat_behavior_unchanged() -> void:
	print("\n-- [10] Existing Combat Behavior Remains Unchanged --")
	var pen = DamageCalculator.calculate_weight_penalty(50.0, 75.0)
	_check(pen.has("turn_rate_mult"), "DamageCalculator calculate_weight_penalty returns valid dictionary")
	_check(pen["turn_rate_mult"] > 0.0, "Turn rate multiplier is positive")
