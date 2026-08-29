extends Node

var _fails: int = 0
var _checks: int = 0

func _check(condition: bool, name: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: " + name)
	else:
		_fails += 1
		printerr("  FAIL: " + name)

func _ready() -> void:
	print("--- Running durability_debuff_and_armor_shatter_verify ---")
	_test_armor_damage_has_no_operational_debuffs()
	_test_frame_durability_triggers_operational_debuffs()
	_test_armor_durability_def_scaling()
	_test_armor_permadeath_at_zero_durability()
	_test_repairs_do_not_degrade_durability()

	print("DURABILITY_DEBUFF_AND_ARMOR_SHATTER_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _test_armor_damage_has_no_operational_debuffs() -> void:
	print("Testing that in-combat armor damage causes NO operational debuffs...")
	# Ensure frames are 100% pristine durability
	for slot in GlobalData.MECHA_SLOTS:
		GlobalData.restore_frame_durability(slot, 1.0)
	
	# Simulate 100% broken combat armor damage on all slots
	for slot in GlobalData.MECHA_SLOTS:
		GlobalData.weapons.part_damage[slot] = 1.0
		GlobalData.weapons.part_damage[slot + "_frame"] = 0.0
	
	_check(PartPenaltySystem.head_spread_penalty() == 0.0, "100% armor damage has 0 weapon spread penalty")
	_check(PartPenaltySystem.head_lock_on_multiplier() == 1.0, "100% armor damage has 1.0 lock-on speed")
	_check(PartPenaltySystem.leg_speed_multiplier() == 1.0, "100% armor damage has 1.0 leg walk speed")
	_check(PartPenaltySystem.leg_dash_multiplier() == 1.0, "100% armor damage has 1.0 leg dash speed")
	_check(PartPenaltySystem.arm_recoil_multiplier() == 1.0, "100% armor damage has 1.0 arm recoil")
	_check(PartPenaltySystem.torso_energy_multiplier() == 1.0, "100% armor damage has 1.0 max energy")
	_check(PartPenaltySystem.torso_heat_multiplier() == 1.0, "100% armor damage has 1.0 heat multiplier")
	_check(PartPenaltySystem.active_penalties().is_empty(), "100% armor damage leaves active_penalties list empty")


func _test_frame_durability_triggers_operational_debuffs() -> void:
	print("Testing that Frame Durability wear triggers operational debuffs...")
	# Clean slate
	for slot in GlobalData.MECHA_SLOTS:
		GlobalData.restore_frame_durability(slot, 1.0)
		GlobalData.weapons.part_damage[slot] = 0.0
		GlobalData.weapons.part_damage[slot + "_frame"] = 0.0
	
	# Degrade Head frame durability to 0.50 (50% wear >= 40% threshold mild)
	GlobalData.degrade_frame_durability("head", 0.50)
	_check(PartPenaltySystem.head_spread_penalty() > 0.0, "Head frame at 50% durability causes weapon spread penalty")
	_check(PartPenaltySystem.head_lock_on_multiplier() < 1.0, "Head frame at 50% durability causes lock-on speed reduction")
	
	# Degrade Leg frame durability to 0.35 (65% wear >= 60% threshold moderate)
	GlobalData.degrade_frame_durability("leg_left", 0.65)
	_check(PartPenaltySystem.leg_speed_multiplier() <= 0.75, "Leg frame at 35% durability reduces walk speed to <= 75%")
	_check(PartPenaltySystem.leg_dash_multiplier() <= 0.65, "Leg frame at 35% durability reduces dash speed to <= 65%")
	
	# Degrade Torso frame durability to 0.15 (85% wear >= 80% threshold severe)
	GlobalData.degrade_frame_durability("body", 0.85)
	_check(PartPenaltySystem.torso_energy_multiplier() <= 0.55, "Torso frame at 15% durability reduces max energy to <= 55%")
	_check(PartPenaltySystem.torso_heat_multiplier() >= 1.60, "Torso frame at 15% durability increases heat accumulation to >= 160%")
	
	var active = PartPenaltySystem.active_penalties()
	_check(active.size() >= 3, "Active penalties list reflects all degraded frame components (%d penalties)" % active.size())

	# Reset frame durability
	for slot in GlobalData.MECHA_SLOTS:
		GlobalData.restore_frame_durability(slot, 1.0)


func _test_armor_durability_def_scaling() -> void:
	print("Testing Armor Durability DEF scaling (<50% reduces DEF by up to 20%)...")
	_check(ArmorSystem.get_durability_def_multiplier(1.0) == 1.0, "100% Durability gives 1.0 DEF multiplier")
	_check(ArmorSystem.get_durability_def_multiplier(0.75) == 1.0, "75% Durability gives 1.0 DEF multiplier")
	_check(ArmorSystem.get_durability_def_multiplier(0.50) == 1.0, "50% Durability gives 1.0 DEF multiplier (no reduction threshold)")
	
	var def_40 = ArmorSystem.get_durability_def_multiplier(0.40)
	_check(is_equal_approx(def_40, 0.96), "40% Durability gives 0.96 DEF multiplier (-4%%)")
	
	var def_25 = ArmorSystem.get_durability_def_multiplier(0.25)
	_check(is_equal_approx(def_25, 0.90), "25% Durability gives 0.90 DEF multiplier (-10%%)")
	
	var def_0 = ArmorSystem.get_durability_def_multiplier(0.0)
	_check(is_equal_approx(def_0, 0.80), "0% Durability gives 0.80 DEF multiplier (-20%% max reduction)")


func _test_armor_permadeath_at_zero_durability() -> void:
	print("Testing Armor Permadeath (0% durability destroys and deletes item permanently)...")
	# Create a test armor piece and equip to body
	var test_armor = {
		"uid": "test_plate_001",
		"name": "Test Heavy Plate",
		"slot": "body",
		"hp": 100.0,
		"max_hp": 100.0,
		"armor_class": 2.0,
		"durability": 0.10,
		"equipped": true
	}
	GlobalData.weapons.equipped_parts["body"] = test_armor
	GlobalData.weapons.armor_inventory.append(test_armor)
	
	_check(not GlobalData.weapons.equipped_parts["body"].is_empty(), "Test armor equipped to body initially")
	_check(GlobalData.get_part_durability("body") == 0.10, "Armor durability is 0.10 (10%)")
	
	var signal_results: Array = []
	var on_shatter = func(slot: String, _data: Dictionary) -> void:
		signal_results.append(slot)
	
	GlobalData.armor_destroyed_permanently.connect(on_shatter)
	
	# Degrade the remaining 10% durability to 0.0
	GlobalData.degrade_part_durability("body", 0.15)
	
	_check(signal_results.size() > 0, "armor_destroyed_permanently signal was emitted")
	_check(signal_results.size() > 0 and signal_results[0] == "body", "Signal reported body slot")
	_check(GlobalData.weapons.equipped_parts["body"].is_empty(), "Equipped slot 'body' is now empty (permanently unequipped)")
	
	var in_inv := false
	for item in GlobalData.weapons.armor_inventory:
		if item.get("uid", "") == "test_plate_001":
			in_inv = true
			break
	_check(not in_inv, "Test armor was completely deleted from armor_inventory")
	
	GlobalData.armor_destroyed_permanently.disconnect(on_shatter)


func _test_repairs_do_not_degrade_durability() -> void:
	print("Testing that repair operations only restore durability and never decrease it...")
	var test_armor = {
		"uid": "test_plate_002",
		"name": "Worn Plate",
		"slot": "head",
		"hp": 10.0,
		"max_hp": 100.0,
		"durability": 0.02,
		"equipped": true
	}
	GlobalData.weapons.equipped_parts["head"] = test_armor
	
	GlobalData.restore_part_durability("head", 0.50)
	_check(GlobalData.get_part_durability("head") >= 0.52, "Restoring durability increased value from 0.02 to >= 0.52")
	_check(not GlobalData.weapons.equipped_parts["head"].is_empty(), "Worn armor was NOT destroyed by repair operation")
