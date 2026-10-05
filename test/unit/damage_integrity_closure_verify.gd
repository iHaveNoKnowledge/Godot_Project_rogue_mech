extends Node
## DAMAGE INTEGRITY CLOSURE MASTER VERIFY
##
## Pins the complete modular-mecha damage integrity lifecycle across:
## 1. Armor -> Frame penetration and overflow preservation
## 2. Part operational penalties consistency (PartPenaltySystem)
## 3. Arm frame destruction -> canonical weapon detachment and pickup creation
## 4. End-to-end save -> emergency repair -> workshop repair -> load persistence
## 5. Unified cross-system authority consistency (MechaHealthBase -> PartPenaltySystem -> GlobalData -> SaveGameIO -> RepairSystem)

const MechaHealthScript = preload("res://scripts/mecha/mecha_health.gd")

var _fails := 0
var _checks := 0


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("[CLOSURE PASS] " + msg)
	else:
		_fails += 1
		printerr("[CLOSURE FAIL] " + msg)


func _ready() -> void:
	print("================================================================")
	print("   VALKREN — DAMAGE INTEGRITY LIFECYCLE CLOSURE VERIFICATION   ")
	print("================================================================")
	
	_verify_penetration_and_overflow()
	_verify_part_penalties_matrix()
	_verify_arm_destruction_weapon_lifecycle()
	_verify_full_persistence_and_repair_lifecycle()
	
	print("\n================================================================")
	print("   CLOSURE SUMMARY: %d checks, %d failures" % [_checks, _fails])
	print("================================================================")
	get_tree().quit(1 if _fails > 0 else 0)


func _verify_penetration_and_overflow() -> void:
	print("\n[PHASE 1] Verifying Armor -> Frame Penetration & Overflow")
	GlobalData.weapons.reset()
	var mecha := Node3D.new()
	var hs = MechaHealthScript.new()
	mecha.add_child(hs)
	add_child(mecha)
	
	hs.parts["body"]["armor_hp"] = 40.0
	hs.parts["body"]["max_armor"] = 40.0
	hs.parts["body"]["frame_hp"] = 100.0
	hs.parts["body"]["max_frame"] = 100.0
	hs.parts["body"]["armor_broken"] = false
	hs.parts["body"]["destroyed"] = false
	hs.parts["body"]["resistance"] = {"pierce": 1.0, "heat": 1.0, "impact": 1.0}
	
	# Apply 70 damage (40 breaks armor, 30 punches through to frame)
	hs.take_damage_to_part("body", 70.0, "pierce")
	_check(hs.parts["body"]["armor_hp"] == 0.0, "Body armor reduced to 0")
	_check(hs.parts["body"]["armor_broken"] == true, "Body armor_broken is true")
	_check(is_equal_approx(hs.parts["body"]["frame_hp"], 70.0), "Body frame HP reduced to 70 (30 overflow absorbed)")
	_check(hs.parts["body"]["destroyed"] == false, "Body not destroyed")
	
	mecha.queue_free()


func _verify_part_penalties_matrix() -> void:
	print("\n[PHASE 2] Verifying Part Penalty System Consistency Matrix")
	GlobalData.weapons.reset()
	
	# Healthy state
	_check(PartPenaltySystem.leg_speed_multiplier() == 1.0, "Healthy leg speed multiplier is 1.0")
	_check(PartPenaltySystem.arm_recoil_multiplier() == 1.0, "Healthy arm recoil multiplier is 1.0")
	_check(PartPenaltySystem.torso_energy_multiplier() == 1.0, "Healthy torso energy multiplier is 1.0")
	_check(not PartPenaltySystem.head_hud_glitching(), "Healthy head HUD is not glitching")
	
	# Severe head wear (0.80 wear -> 0.20 frame durability)
	GlobalData.weapons.equipped_frames["head"] = {"durability": 0.20}
	_check(PartPenaltySystem.head_hud_glitching(), "Head HUD glitching active at high wear")
	_check(is_equal_approx(PartPenaltySystem.head_spread_penalty(), PartPenaltySystem.HEAD_SPREAD_SEVERE), "Head spread penalty severe applied")
	_check(is_equal_approx(PartPenaltySystem.head_lock_on_multiplier(), PartPenaltySystem.HEAD_LOCK_ON_SEVERE), "Head lock-on multiplier severe applied")
	
	# Severe arm wear
	GlobalData.weapons.equipped_frames["arm_left"] = {"durability": 0.15}
	_check(is_equal_approx(PartPenaltySystem.arm_recoil_multiplier(), PartPenaltySystem.ARM_RECOIL_SEVERE), "Arm recoil multiplier severe applied")
	_check(PartPenaltySystem.arm_cannot_equip_heavy(), "Arm heavy weapon lockout active at severe damage")
	
	# Severe leg wear
	GlobalData.weapons.equipped_frames["leg_right"] = {"durability": 0.10}
	_check(is_equal_approx(PartPenaltySystem.leg_speed_multiplier(), PartPenaltySystem.LEG_SPEED_SEVERE), "Leg walk speed reduced to severe tier")
	_check(is_equal_approx(PartPenaltySystem.leg_dash_multiplier(), PartPenaltySystem.LEG_DASH_SEVERE), "Leg dash speed reduced to severe tier")


func _verify_arm_destruction_weapon_lifecycle() -> void:
	print("\n[PHASE 3] Verifying Arm Destruction & Weapon Ownership Lifecycle")
	GlobalData.weapons.reset()
	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha: Node3D = mecha_scene.instantiate()
	add_child(mecha)
	
	var wm = mecha.get_node("WeaponManager")
	var hs: MechaHealthBase = mecha.get_node("MechaHealth")
	var blade_res: WeaponPart = load("res://resources/mech/stock/weapon_heat_blade.tres")
	
	wm.right_hand = blade_res
	wm._update_weapon_visuals()
	wm.sync_loadout_to_global()
	
	var initial_pickups := get_tree().get_nodes_in_group("weapon_pickup").size()
	
	# Frame destruction
	hs.parts["arm_right"]["armor_hp"] = 0.0
	hs.parts["arm_right"]["armor_broken"] = true
	hs.take_damage_to_part("arm_right", 500.0, "pierce")
	
	_check(hs.parts["arm_right"]["destroyed"] == true, "Arm right frame destroyed")
	_check(wm.right_hand == null, "Right weapon cleanly unequipped from WeaponManager")
	_check(GlobalData.weapons.weapon_loadout.get("right", "") == "", "GlobalData loadout slot cleared")
	
	var pickups = get_tree().get_nodes_in_group("weapon_pickup")
	_check(pickups.size() == initial_pickups + 1, "WeaponPickup created on arm destruction")
	
	mecha.queue_free()


func _verify_full_persistence_and_repair_lifecycle() -> void:
	print("\n[PHASE 4] Verifying Full Persistence, Scrap Repair & Workshop Repair Lifecycle")
	GlobalData.weapons.reset()
	GlobalData.currency.credits = 10000
	GlobalData.currency.scrap = 200
	
	# Inflict damage on arm_left and leg_left
	GlobalData.weapons.part_damage["arm_left"] = 1.0
	GlobalData.weapons.part_damage["arm_left_frame"] = 0.60
	GlobalData.weapons.part_damage["leg_left"] = 0.85
	GlobalData.weapons.part_damage["leg_left_frame"] = 0.40
	
	# Emergency repair arm_left
	var patch := RepairSystem.apply_emergency_repair("arm_left")
	_check(not patch.is_empty(), "Emergency scrap patch applied to arm_left")
	_check(not GlobalData.weapons.part_damage.has("arm_left"), "arm_left damage cleared")
	
	# Professional repair leg_left
	var rep_ok := RepairSystem.apply_professional_repair("leg_left")
	_check(rep_ok, "Professional repair applied to leg_left")
	_check(not GlobalData.weapons.part_damage.has("leg_left"), "leg_left damage cleared")
	
	# Save run
	var save_ok := SaveGameIO.save_run()
	_check(save_ok, "SaveGameIO.save_run succeeded")
	
	# Reset working state
	GlobalData.weapons.reset()
	
	# Reload run
	var load_ok := SaveGameIO.load_run()
	_check(load_ok, "SaveGameIO.load_run succeeded")
	
	_check(GlobalData.weapons.scrap_patches.has("arm_left"), "arm_left scrap patch intact after reload")
	_check(not GlobalData.weapons.part_damage.has("arm_left"), "arm_left remains repaired after reload")
	_check(not GlobalData.weapons.part_damage.has("leg_left"), "leg_left remains fully restored after reload")
	_check(not GlobalData.weapons.scrap_patches.has("leg_left"), "leg_left has no scrap patches after reload")
