extends Node
## PART DAMAGE LAYER PENETRATION VERIFY
##
## Verifies:
## 1. Armor absorbs incoming damage first.
## 2. When armor reaches 0, unabsorbed overflow damage punches through to frame.
## 3. If armor is already broken, damage routes directly to frame.
## 4. No duplicate damage or lost overflow occurs.
## 5. armor_broken signal fires on break, and part_destroyed only fires when frame HP reaches 0.
## 6. GlobalData.weapons.part_damage correctly caches both armor and frame damage ratios.

const MechaHealthScript = preload("res://scripts/mecha/mecha_health.gd")

var _fails := 0
var _checks := 0


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("[PENETRATION PASS] " + msg)
	else:
		_fails += 1
		printerr("[PENETRATION FAIL] " + msg)


func _ready() -> void:
	print("=== RUNNING PART DAMAGE LAYER PENETRATION VERIFY ===")
	_test_armor_overflow_penetration()
	_test_sub_break_damage()
	_test_direct_frame_damage_when_armor_broken()
	_test_lethal_overflow_frame_destruction()
	
	print("\n--- RESULTS: %d checks, %d failures ---" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _create_test_mecha() -> Node3D:
	var mecha := Node3D.new()
	mecha.name = "TestMecha"
	var hs = MechaHealthScript.new()
	hs.name = "MechaHealth"
	mecha.add_child(hs)
	add_child(mecha)
	return mecha


func _test_armor_overflow_penetration() -> void:
	print("\n-- Test 1: Armor Overflow into Frame --")
	GlobalData.weapons.reset()
	var mecha := _create_test_mecha()
	var hs: MechaHealthBase = mecha.get_node("MechaHealth")
	
	# Setup slot with Armor HP = 20, Frame HP = 100, resistance = 1.0
	hs.parts["arm_left"]["armor_hp"] = 20.0
	hs.parts["arm_left"]["max_armor"] = 20.0
	hs.parts["arm_left"]["frame_hp"] = 100.0
	hs.parts["arm_left"]["max_frame"] = 100.0
	hs.parts["arm_left"]["armor_broken"] = false
	hs.parts["arm_left"]["destroyed"] = false
	hs.parts["arm_left"]["resistance"] = {"pierce": 1.0, "heat": 1.0, "impact": 1.0}
	
	var armor_broken_fired := false
	var part_destroyed_fired := false
	hs.armor_broken.connect(func(slot): if slot == "arm_left": armor_broken_fired = true)
	hs.part_destroyed.connect(func(slot): if slot == "arm_left": part_destroyed_fired = true)
	
	# Apply 35 damage (20 should break armor, 15 should reach frame)
	hs.take_damage_to_part("arm_left", 35.0, "pierce")
	
	_check(hs.parts["arm_left"]["armor_hp"] == 0.0, "Armor HP reduced to 0")
	_check(hs.parts["arm_left"]["armor_broken"] == true, "Armor broken flag set to true")
	_check(armor_broken_fired, "armor_broken signal emitted")
	_check(is_equal_approx(hs.parts["arm_left"]["frame_hp"], 85.0), "Frame HP reduced from 100 to 85 (15 overflow absorbed, actual: %f)" % hs.parts["arm_left"]["frame_hp"])
	_check(not part_destroyed_fired, "part_destroyed signal NOT emitted since frame is alive (85 HP)")
	_check(hs.parts["arm_left"]["destroyed"] == false, "arm_left destroyed flag is false")
	
	# Verify persistent damage cache
	_check(is_equal_approx(float(GlobalData.weapons.part_damage.get("arm_left", 0.0)), 1.0), "Persistent armor damage ratio is 1.0")
	_check(is_equal_approx(float(GlobalData.weapons.part_damage.get("arm_left_frame", 0.0)), 0.15), "Persistent frame damage ratio is 0.15 (15/100, actual: %f)" % float(GlobalData.weapons.part_damage.get("arm_left_frame", 0.0)))
	
	mecha.queue_free()


func _test_sub_break_damage() -> void:
	print("\n-- Test 2: Damage below Armor HP (no overflow) --")
	GlobalData.weapons.reset()
	var mecha := _create_test_mecha()
	var hs: MechaHealthBase = mecha.get_node("MechaHealth")
	
	hs.parts["arm_right"]["armor_hp"] = 30.0
	hs.parts["arm_right"]["max_armor"] = 30.0
	hs.parts["arm_right"]["frame_hp"] = 50.0
	hs.parts["arm_right"]["max_frame"] = 50.0
	hs.parts["arm_right"]["armor_broken"] = false
	hs.parts["arm_right"]["destroyed"] = false
	hs.parts["arm_right"]["resistance"] = {"pierce": 1.0, "heat": 1.0, "impact": 1.0}
	
	var armor_broken_fired := false
	hs.armor_broken.connect(func(slot): if slot == "arm_right": armor_broken_fired = true)
	
	# Apply 12 damage (armor absorbs all 12, frame takes 0)
	hs.take_damage_to_part("arm_right", 12.0, "pierce")
	
	_check(is_equal_approx(hs.parts["arm_right"]["armor_hp"], 18.0), "Armor HP reduced from 30 to 18")
	_check(hs.parts["arm_right"]["armor_broken"] == false, "Armor remains unbroken")
	_check(not armor_broken_fired, "armor_broken signal not fired")
	_check(is_equal_approx(hs.parts["arm_right"]["frame_hp"], 50.0), "Frame HP untouched at 50")
	_check(is_equal_approx(float(GlobalData.weapons.part_damage.get("arm_right", 0.0)), 12.0 / 30.0), "Persistent armor damage ratio is 0.4")
	_check(float(GlobalData.weapons.part_damage.get("arm_right_frame", 0.0)) == 0.0, "Persistent frame damage ratio is 0.0")
	
	mecha.queue_free()


func _test_direct_frame_damage_when_armor_broken() -> void:
	print("\n-- Test 3: Direct Frame Damage when Armor already broken --")
	GlobalData.weapons.reset()
	var mecha := _create_test_mecha()
	var hs: MechaHealthBase = mecha.get_node("MechaHealth")
	
	hs.parts["leg_left"]["armor_hp"] = 0.0
	hs.parts["leg_left"]["max_armor"] = 25.0
	hs.parts["leg_left"]["frame_hp"] = 40.0
	hs.parts["leg_left"]["max_frame"] = 40.0
	hs.parts["leg_left"]["armor_broken"] = true
	hs.parts["leg_left"]["destroyed"] = false
	
	# Apply 15 damage directly to broken armor slot
	hs.take_damage_to_part("leg_left", 15.0, "pierce")
	
	_check(hs.parts["leg_left"]["armor_hp"] == 0.0, "Armor HP stays 0")
	_check(is_equal_approx(hs.parts["leg_left"]["frame_hp"], 25.0), "Frame HP reduced from 40 to 25")
	_check(is_equal_approx(float(GlobalData.weapons.part_damage.get("leg_left_frame", 0.0)), 15.0 / 40.0), "Persistent frame damage ratio is 0.375")
	
	mecha.queue_free()


func _test_lethal_overflow_frame_destruction() -> void:
	print("\n-- Test 4: Lethal Overflow Destroying Frame --")
	GlobalData.weapons.reset()
	var mecha := _create_test_mecha()
	var hs: MechaHealthBase = mecha.get_node("MechaHealth")
	
	hs.parts["head"]["armor_hp"] = 10.0
	hs.parts["head"]["max_armor"] = 10.0
	hs.parts["head"]["frame_hp"] = 20.0
	hs.parts["head"]["max_frame"] = 20.0
	hs.parts["head"]["armor_broken"] = false
	hs.parts["head"]["destroyed"] = false
	hs.parts["head"]["resistance"] = {"pierce": 1.0, "heat": 1.0, "impact": 1.0}
	
	var part_destroyed_fired := false
	hs.part_destroyed.connect(func(slot): if slot == "head": part_destroyed_fired = true)
	
	# Apply 50 damage (10 breaks armor, 40 destroys frame of 20 HP)
	hs.take_damage_to_part("head", 50.0, "pierce")
	
	_check(hs.parts["head"]["armor_hp"] == 0.0, "Armor HP is 0")
	_check(hs.parts["head"]["frame_hp"] == 0.0, "Frame HP is 0")
	_check(hs.parts["head"]["armor_broken"] == true, "Armor broken is true")
	_check(hs.parts["head"]["destroyed"] == true, "Head destroyed is true")
	_check(part_destroyed_fired, "part_destroyed signal fired on lethal penetration")
	_check(is_equal_approx(float(GlobalData.weapons.part_damage.get("head_frame", 0.0)), 1.0), "Persistent frame damage ratio is 1.0 (destroyed)")
	
	mecha.queue_free()
