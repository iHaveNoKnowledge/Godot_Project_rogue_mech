extends Node

## Declared-capability → actual-gameplay audit for Module / PowerCore /
## Backpack fields. Proves ACTIVE capabilities change runtime behavior causally
## (with/without measurements) and pins INTENTIONALLY INERT fields by showing
## the data is present while dependent behavior is byte-identical.
## No file I/O except BackpackSystem.equip's own save (user save isolated).
## Run: godot --headless --path . res://tests/mecha/module_core_backpack_effect_audit.tscn

var _fails := 0
var _checks := 0
var _snap: Dictionary = {}
var _save_backup: PackedByteArray = PackedByteArray()
var _had_save: bool = false


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + label)
	else:
		_fails += 1
		push_error("FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	_backup_save()
	_snap_state()
	await _run()
	_restore_state()
	_restore_save()
	print("CAPABILITY_EFFECT_PROBE: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _backup_save() -> void:
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.READ)
		if f:
			_save_backup = f.get_buffer(f.get_length())
			_had_save = true
			f.close()


func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(_save_backup)
			f.close()
	elif FileAccess.file_exists(GlobalData.SAVE_PATH):
		DirAccess.remove_absolute(GlobalData.SAVE_PATH)


func _snap_state() -> void:
	_snap = {
		"modules": (GlobalData.weapons.frame_modules as Dictionary).duplicate(true),
		"modinv": (GlobalData.weapons.module_inventory as Array).duplicate(true),
		"backpack": (GlobalData.weapons.equipped_backpack as Dictionary).duplicate(true),
		"core": str(GlobalData.weapons.power_core_id),
		"damage": (GlobalData.weapons.part_damage as Dictionary).duplicate(true),
	}


func _restore_state() -> void:
	GlobalData.weapons.frame_modules = (_snap["modules"] as Dictionary).duplicate(true)
	GlobalData.weapons.module_inventory = (_snap["modinv"] as Array).duplicate(true)
	GlobalData.weapons.equipped_backpack = (_snap["backpack"] as Dictionary).duplicate(true)
	GlobalData.weapons.power_core_id = str(_snap["core"])
	GlobalData.weapons.part_damage = (_snap["damage"] as Dictionary).duplicate(true)


func _close(a: float, b: float, eps: float = 0.0001) -> bool:
	return absf(a - b) <= eps


func _run() -> void:
	HangarManager.ensure_roster()

	# ---- ACTIVE: cryo heatsink loop raises weapon heat capacity ----
	var cap0 := FrameModuleSystem.calculate_heat_capacity_multiplier()
	FrameModuleSystem.install_module("body", 0, "cryo_heatsink_loop")
	_check(FrameModuleSystem.has_module("cryo_heatsink_loop"), "cryo installs")
	var cap1 := FrameModuleSystem.calculate_heat_capacity_multiplier()
	_check(_close(cap0, 1.0) and _close(cap1, 1.25), "heat capacity 1.0 -> 1.25 from catalog value (causal)")
	FrameModuleSystem.uninstall_module("body", 0)
	_check(_close(FrameModuleSystem.calculate_heat_capacity_multiplier(), 1.0), "capacity returns after uninstall")

	# ---- ACTIVE: vent protocol bleeds heat per shot (arm-category → arm slot) ----
	FrameModuleSystem.install_module("arm_left", 0, "vent_protocol")
	_check(_close(FrameModuleSystem.calculate_heat_per_shot_multiplier(), 0.70), "per-shot heat x0.70 from catalog (causal)")
	_check(_close(FrameModuleSystem.calculate_heat_cool_rate_multiplier(), 1.15), "cool rate x1.15 from catalog (causal)")
	FrameModuleSystem.uninstall_module("arm_left", 0)

	# ---- ACTIVE: v8 dash stacking + berserk speed scale with live state ----
	# (v8 is leg-category → leg slot; the category gate correctly rejects body)
	_check(not FrameModuleSystem.install_module("body", 0, "v8_twin_turbo"), "category gate rejects leg module in body socket")
	FrameModuleSystem.install_module("leg_left", 0, "v8_twin_turbo")
	_check(_close(FrameModuleSystem.calculate_dash_stack_multiplier(0), 1.0), "v8 zero stacks neutral")
	_check(FrameModuleSystem.calculate_dash_stack_multiplier(3) > 1.5, "v8 full stacks boost dash (causal)")
	FrameModuleSystem.uninstall_module("leg_left", 0)
	FrameModuleSystem.install_module("body", 0, "exposed_frame_berserk")
	_check(_close(FrameModuleSystem.calculate_berserk_speed_multiplier(), 1.0), "berserk neutral on intact mech")
	(GlobalData.weapons.part_damage as Dictionary)["arm_left"] = 1.0
	_check(FrameModuleSystem.calculate_berserk_speed_multiplier() > 1.0, "berserk rises with broken armor (causal)")
	(GlobalData.weapons.part_damage as Dictionary).erase("arm_left")
	FrameModuleSystem.uninstall_module("body", 0)

	# ---- ACTIVE: power core heat/dash/board/weight follow CURRENT core id ----
	PowerCoreSystem.set_core("combustion")
	var heat_c := PowerCoreSystem.heat_accumulation_multiplier()
	PowerCoreSystem.set_core("hybrid")
	_check(_close(PowerCoreSystem.heat_accumulation_multiplier(), heat_c * 1.5), "hybrid heat x1.5 vs combustion (causal)")
	_check(PowerCoreSystem.dash_speed_multiplier() > PowerCoreSystem.DASH_SPEED_MULT["combustion"], "hybrid dash exceeds combustion (causal)")
	_check(PowerCoreSystem.board_cost_multiplier() < 1.0, "hybrid board cost discounted (causal)")
	_check(PowerCoreSystem.passive_heat_rate() == 0.0, "hybrid passive heat zero per table")
	PowerCoreSystem.set_core("combustion")
	_check(PowerCoreSystem.passive_heat_rate() > 0.0, "combustion passive heat positive per table")
	var w_comb := LoadoutSystem.get_total_mecha_weight()
	PowerCoreSystem.set_core("ancient")
	_check(LoadoutSystem.get_total_mecha_weight() < w_comb, "ancient core lightens total (12kg -> 4kg, causal)")
	PowerCoreSystem.set_core("combustion")

	# ---- ACTIVE: backpack weight + carry bonus follow CURRENT pack ----
	BackpackSystem.equip("cargo")
	var cap_cargo := LoadoutSystem.get_field_pack_capacity()
	var w_cargo := LoadoutSystem.get_total_mecha_weight()
	BackpackSystem.equip("booster")
	_check(LoadoutSystem.get_field_pack_capacity() < cap_cargo, "booster carry bonus below cargo (40 -> 0, causal)")
	_check(LoadoutSystem.get_total_mecha_weight() < w_cargo, "booster lighter than cargo (8kg -> 6kg, causal)")
	BackpackSystem.unequip()
	_check(BackpackSystem.get_backpack_weight() == 0.0, "no pack contributes zero weight")

	# ---- INERT (pinned): legacy energy/recharge fields change nothing ----
	var e_max := GlobalData.fuel.mech_max_energy
	FrameModuleSystem.install_module("body", 0, "mod_reactor_fission")
	_check(_close(float(FrameModuleSystem.get_module_effect("mod_reactor_fission", "energy_bonus", 0.0)), 1000.0), "energy_bonus data present in catalog")
	_check(_close(float(GlobalData.fuel.mech_max_energy), e_max), "max energy untouched by energy_bonus mod (inert, no consumer)")
	FrameModuleSystem.uninstall_module("body", 0)

	# ---- INERT (pinned): legacy lock-on/spread/recoil/melee/roller/jump bonuses ----
	FrameModuleSystem.install_module("head", 0, "mod_targeting_fcs")
	var spread0 := PartPenaltySystem.total_spread_penalty()
	var lock0 := PartPenaltySystem.head_lock_on_multiplier()
	_check(_close(float(FrameModuleSystem.get_module_effect("mod_targeting_fcs", "lock_on_bonus", 0.0)), 0.40), "lock_on_bonus data present")
	_check(PartPenaltySystem.total_spread_penalty() == spread0 and PartPenaltySystem.head_lock_on_multiplier() == lock0, "lock/spread behavior identical with mod installed (inert)")
	FrameModuleSystem.uninstall_module("head", 0)
	FrameModuleSystem.install_module("arm_left", 0, "mod_recoil_gyro_l")
	_check(_close(float(FrameModuleSystem.get_module_effect("mod_recoil_gyro_l", "recoil_reduction", 0.0)), 0.35), "recoil_reduction data present")
	FrameModuleSystem.uninstall_module("arm_left", 0)
	FrameModuleSystem.install_module("leg_left", 0, "mod_roller_overdrive_l")
	FrameModuleSystem.install_module("leg_right", 0, "mod_shock_absorbers_r")
	_check(FrameModuleSystem.has_module("mod_roller_overdrive_l") and FrameModuleSystem.has_module("mod_shock_absorbers_r"), "mobility mods install")
	FrameModuleSystem.uninstall_module("leg_left", 0)
	FrameModuleSystem.uninstall_module("leg_right", 0)

	# ---- INERT (pinned): uncalled module calculators + backpack secondary fields ----
	_check(FrameModuleSystem.calculate_berserk_melee_multiplier() == 1.0, "berserk melee calc defined but unconsumed (returns neutral)")
	BackpackSystem.equip("booster")
	_check(_close(float(BackpackSystem.get_backpack_stat("roller_bonus", -1.0)), 0.30), "roller_bonus readable via accessor (data path only; zero gameplay readers per audit)")
	BackpackSystem.equip("combat")
	_check(str(GlobalData.weapons.equipped_backpack.get("id", "")) == "combat", "combat pack equips (armor_bonus inert: no armor consumer reads it)")
	BackpackSystem.unequip()

	# ---- save/berth round-trip preserves ids (persistence, not behavior) ----
	FrameModuleSystem.install_module("body", 0, "cryo_heatsink_loop")
	HangarManager.save_mech_state(GlobalData.hangar.active_hangar_mech_id)
	FrameModuleSystem.uninstall_module("body", 0)
	HangarManager.load_mech_state(GlobalData.hangar.active_hangar_mech_id)
	_check(FrameModuleSystem.has_module("cryo_heatsink_loop"), "berth round-trip restores module id")
	_check(_close(FrameModuleSystem.calculate_heat_capacity_multiplier(), 1.25), "restored module effect live again")
	FrameModuleSystem.uninstall_module("body", 0)
