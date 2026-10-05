extends Node
## REPAIR PERSISTENCE CYCLE VERIFY
##
## Verifies:
## 1. Multi-part combat damage (armor & frame) persists accurately through SaveGameIO save & load.
## 2. Emergency scrap repair consumes scrap, creates scrap_patches, clears damage, and survives reload.
## 3. Professional workshop repair consumes credits, clears patches/bindings/damage, and survives reload.
## 4. Part destruction state (frame HP = 0) serializes and reconstructs correctly in MechaHealth on load.

const MechaHealthScript = preload("res://scripts/mecha/mecha_health.gd")

var _fails := 0
var _checks := 0


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("[PERSISTENCE PASS] " + msg)
	else:
		_fails += 1
		printerr("[PERSISTENCE FAIL] " + msg)


func _ready() -> void:
	print("=== RUNNING REPAIR PERSISTENCE CYCLE VERIFY ===")
	_test_damage_persistence_cycle()
	_test_emergency_repair_persistence_cycle()
	_test_professional_repair_persistence_cycle()
	_test_destruction_reconstruction_cycle()
	
	print("\n--- RESULTS: %d checks, %d failures ---" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_damage_persistence_cycle() -> void:
	print("\n-- Test 3A: Damage Persists through Save & Load --")
	GlobalData.weapons.reset()
	GlobalData.currency.credits = 1000
	GlobalData.currency.scrap = 50
	
	# Apply distinct damage ratios
	GlobalData.weapons.part_damage["head"] = 0.45
	GlobalData.weapons.part_damage["head_frame"] = 0.20
	GlobalData.weapons.part_damage["arm_left"] = 1.0  # armor broken
	GlobalData.weapons.part_damage["arm_left_frame"] = 0.50
	GlobalData.weapons.part_damage["leg_left"] = 0.80
	GlobalData.weapons.part_damage["body"] = 0.30
	GlobalData.weapons.part_damage["body_frame"] = 0.10
	
	var save_ok := SaveGameIO.save_run()
	_check(save_ok, "SaveGameIO.save_run succeeded")
	
	# Clear runtime state completely
	GlobalData.weapons.reset()
	_check(GlobalData.weapons.part_damage.is_empty(), "Working state reset before load")
	
	var load_ok := SaveGameIO.load_run()
	_check(load_ok, "SaveGameIO.load_run succeeded")
	
	# Verify exact restored values
	_check(is_equal_approx(float(GlobalData.weapons.part_damage.get("head", 0.0)), 0.45), "Head armor damage restored to 0.45")
	_check(is_equal_approx(float(GlobalData.weapons.part_damage.get("head_frame", 0.0)), 0.20), "Head frame damage restored to 0.20")
	_check(is_equal_approx(float(GlobalData.weapons.part_damage.get("arm_left", 0.0)), 1.0), "ArmLeft armor damage restored to 1.0")
	_check(is_equal_approx(float(GlobalData.weapons.part_damage.get("arm_left_frame", 0.0)), 0.50), "ArmLeft frame damage restored to 0.50")
	_check(is_equal_approx(float(GlobalData.weapons.part_damage.get("leg_left", 0.0)), 0.80), "LegLeft armor damage restored to 0.80")
	_check(is_equal_approx(float(GlobalData.weapons.part_damage.get("body", 0.0)), 0.30), "Body armor damage restored to 0.30")
	_check(is_equal_approx(float(GlobalData.weapons.part_damage.get("body_frame", 0.0)), 0.10), "Body frame damage restored to 0.10")


func _test_emergency_repair_persistence_cycle() -> void:
	print("\n-- Test 3B: Emergency Repair Persists through Save & Load --")
	GlobalData.weapons.reset()
	GlobalData.currency.scrap = 100
	
	# Damage arm_right
	GlobalData.weapons.part_damage["arm_right"] = 0.70
	GlobalData.weapons.part_damage["arm_right_frame"] = 0.40
	
	var init_scrap: int = GlobalData.currency.scrap
	var cost := RepairSystem.get_emergency_repair_scrap_cost("arm_right")
	_check(cost > 0, "Emergency repair scrap cost is positive (%d scrap)" % cost)
	
	var patch := RepairSystem.apply_emergency_repair("arm_right")
	_check(not patch.is_empty(), "Emergency repair patch applied successfully")
	_check(GlobalData.currency.scrap == init_scrap - cost, "Scrap correctly deducted")
	_check(not GlobalData.weapons.part_damage.has("arm_right"), "Armor damage cleared after scrap patch")
	_check(not GlobalData.weapons.part_damage.has("arm_right_frame"), "Frame damage cleared after scrap patch")
	_check(GlobalData.weapons.scrap_patches.has("arm_right"), "Scrap patch recorded in GlobalData")
	
	# Save, reset, load
	var save_ok := SaveGameIO.save_run()
	_check(save_ok, "Save after emergency repair succeeded")
	
	GlobalData.weapons.reset()
	var load_ok := SaveGameIO.load_run()
	_check(load_ok, "Load after emergency repair succeeded")
	
	_check(GlobalData.weapons.scrap_patches.has("arm_right"), "Scrap patch restored on arm_right")
	_check(not GlobalData.weapons.part_damage.has("arm_right"), "arm_right damage remains cleared on load")
	_check(not GlobalData.weapons.part_damage.has("arm_right_frame"), "arm_right_frame damage remains cleared on load")


func _test_professional_repair_persistence_cycle() -> void:
	print("\n-- Test 3C: Professional Repair Persists through Save & Load --")
	GlobalData.weapons.reset()
	GlobalData.currency.credits = 5000
	
	# Setup damage and a scrap patch on leg_right
	GlobalData.weapons.part_damage["leg_right"] = 0.90
	GlobalData.weapons.part_damage["leg_right_frame"] = 0.50
	GlobalData.weapons.scrap_patches["leg_right"] = {"tier": 1, "stat_scale": 0.5}
	GlobalData.weapons.frame_bindings["leg_right"] = true
	
	var init_credits: int = GlobalData.currency.credits
	var cost := RepairSystem.get_professional_repair_cost("leg_right")
	_check(cost > 0, "Professional repair cost is positive (%d credits)" % cost)
	
	var success := RepairSystem.apply_professional_repair("leg_right")
	_check(success, "Professional repair succeeded")
	_check(GlobalData.currency.credits == init_credits - cost, "Credits correctly deducted")
	_check(not GlobalData.weapons.part_damage.has("leg_right"), "Damage cleared after professional repair")
	_check(not GlobalData.weapons.part_damage.has("leg_right_frame"), "Frame damage cleared after professional repair")
	_check(not GlobalData.weapons.scrap_patches.has("leg_right"), "Scrap patch removed after professional repair")
	_check(not GlobalData.weapons.frame_bindings.has("leg_right"), "Frame bindings removed after professional repair")
	
	# Save, reset, load
	SaveGameIO.save_run()
	GlobalData.weapons.reset()
	SaveGameIO.load_run()
	
	_check(not GlobalData.weapons.part_damage.has("leg_right"), "leg_right remains pristine after reload")
	_check(not GlobalData.weapons.scrap_patches.has("leg_right"), "scrap patch remains gone after reload")
	_check(not GlobalData.weapons.frame_bindings.has("leg_right"), "frame bindings remain gone after reload")


func _test_destruction_reconstruction_cycle() -> void:
	print("\n-- Test 3D: Destruction State Reconstruction on Load --")
	GlobalData.weapons.reset()
	
	# Destroy arm_left frame
	GlobalData.weapons.part_damage["arm_left"] = 1.0
	GlobalData.weapons.part_damage["arm_left_frame"] = 1.0
	
	SaveGameIO.save_run()
	GlobalData.weapons.reset()
	SaveGameIO.load_run()
	
	_check(is_equal_approx(float(GlobalData.weapons.part_damage.get("arm_left_frame", 0.0)), 1.0), "Persistent frame damage ratio is 1.0")
	
	# Instantiate MechaHealth and verify it initializes with destroyed=true
	var mecha := Node3D.new()
	var hs = MechaHealthScript.new()
	mecha.add_child(hs)
	add_child(mecha)
	
	_check(hs.parts["arm_left"]["armor_hp"] == 0.0, "MechaHealth initialized with 0 armor HP")
	_check(hs.parts["arm_left"]["frame_hp"] == 0.0, "MechaHealth initialized with 0 frame HP")
	_check(hs.parts["arm_left"]["armor_broken"] == true, "MechaHealth initialized with armor_broken = true")
	_check(hs.parts["arm_left"]["destroyed"] == true, "MechaHealth initialized with destroyed = true")
	
	mecha.queue_free()
