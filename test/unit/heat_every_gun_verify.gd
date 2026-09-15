extends Node
## HEAT-EVERY-GUN VERIFY (roguelike heat pass)
## 1. beam_rifle is an ENERGY weapon (energy_cell / heat), not a bullet gun.
## 2. Every ranged gun has heat stats so fire discipline matters; melee/shields stay heat-free.
## 3. Heat-management frame modules exist and actually scale WeaponCore behaviour.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("HEAT OK: " + name)
	else:
		_fails += 1
		printerr("HEAT FAIL: " + name)


const GUN_PATHS: Array[String] = [
	"res://resources/mech/stock/weapon_beam_rifle.tres",
	"res://resources/mech/stock/weapon_beam_rifle_mk2.tres",
	"res://resources/mech/stock/weapon_beam_carbine.tres",
	"res://resources/mech/stock/weapon_beam_sniper.tres",
	"res://resources/mech/stock/weapon_assault_cannon.tres",
	"res://resources/mech/stock/weapon_machine_gun.tres",
	"res://resources/mech/stock/weapon_light_machine_gun.tres",
	"res://resources/mech/stock/weapon_heavy_machine_gun.tres",
	"res://resources/mech/stock/weapon_gatling_gun.tres",
	"res://resources/mech/stock/weapon_minigun.tres",
	"res://resources/mech/stock/weapon_railgun.tres",
	"res://resources/mech/stock/weapon_combat_shotgun.tres",
	"res://resources/mech/stock/weapon_shotgun.tres",
	"res://resources/mech/stock/weapon_sawed_off.tres",
	"res://resources/mech/stock/weapon_missile.tres",
	"res://resources/mech/stock/weapon_heavy_missile.tres",
	"res://resources/mech/stock/weapon_micro_missile.tres",
	"res://resources/mech/stock/weapon_swarm_missile.tres",
	"res://resources/mech/stock/weapon_pilot_pistol.tres",
	"res://resources/mech/stock/weapon_pilot_assault_rifle.tres",
	"res://resources/mech/stock/weapon_pilot_anti_tank_rifle.tres",
	"res://resources/mech/stock/weapon_pilot_bazooka.tres",
]

const HEAT_FREE_PATHS: Array[String] = [
	"res://resources/mech/stock/weapon_combat_knife.tres",
	"res://resources/mech/stock/weapon_heat_blade.tres",
	"res://resources/mech/stock/weapon_mace.tres",
	"res://resources/mech/stock/weapon_shield.tres",
	"res://resources/mech/stock/weapon_heavy_shield.tres",
]


func _ready() -> void:
	await get_tree().process_frame

	# --- 1. beam_rifle identity: energy, not bullet ---
	var beam: WeaponPart = load("res://resources/mech/stock/weapon_beam_rifle.tres")
	_check(beam.weapon_type == WeaponPart.WeaponType.BEAM_RIFLE, "beam rifle category is BEAM_RIFLE")
	_check(beam.get_damage_type() == "heat", "beam rifle damage type is heat")
	_check(beam.get_ammo_type() == "energy_cell", "beam rifle ammo is energy_cell (not bullet)")
	_check(beam.uses_heat(), "beam rifle uses heat")

	# --- 2. every gun runs hot, with sane tuning ---
	for path in GUN_PATHS:
		var w: WeaponPart = load(path)
		var tag: String = path.get_file()
		_check(w.uses_heat(), tag + " uses heat")
		_check(w.heat_per_shot > 0.0, tag + " has heat_per_shot > 0")
		_check(w.heat_cool_rate > 0.0, tag + " has heat_cool_rate > 0")
		_check(w.heat_release_ratio > 0.0 and w.heat_release_ratio < 1.0, tag + " has release ratio in (0, 1)")
		var shots_to_overheat: float = w.heat_capacity / maxf(w.heat_per_shot, 0.001)
		_check(shots_to_overheat >= 2.0, tag + " needs >= 2 shots to overheat (no insta-lock)")

	# --- 3. melee / shields stay heat-free ---
	for path in HEAT_FREE_PATHS:
		var w: WeaponPart = load(path)
		_check(not w.uses_heat(), path.get_file() + " stays heat-free")

	# --- 4. heat-management modules exist in the catalog ---
	var cryo: Dictionary = FrameModuleSystem.get_module("cryo_heatsink_loop")
	_check(not cryo.is_empty(), "cryo_heatsink_loop is in the module catalog")
	_check(float(cryo.get("effects", {}).get("heat_capacity_mult", 0.0)) > 1.0, "cryo raises heat capacity")
	_check(float(cryo.get("effects", {}).get("heat_cool_rate_mult", 0.0)) > 1.0, "cryo raises cool rate")
	var vent: Dictionary = FrameModuleSystem.get_module("vent_protocol")
	_check(not vent.is_empty(), "vent_protocol is in the module catalog")
	_check(float(vent.get("effects", {}).get("heat_per_shot_mult", 1.0)) < 1.0, "vent lowers heat per shot")
	_check(float(vent.get("effects", {}).get("heat_cool_rate_mult", 0.0)) > 1.0, "vent raises cool rate")

	# --- 5. WeaponCore wiring: capacity multiplier applies at build ---
	var core := WeaponCore.from_weapon(beam)
	core.unlimited_ammo = true # isolate heat from the magazine for this test
	var expected_cap: float = beam.heat_capacity * FrameModuleSystem.calculate_heat_capacity_multiplier()
	_check(core.heat_capacity > 0.0, "beam core has heat capacity")
	_check(is_equal_approx(core.heat_capacity, expected_cap), "core applies frame capacity multiplier")

	# --- 6. fire discipline: overheat locks, cooling unlocks ---
	var shots := 0
	while not core.is_overheated() and shots < 200:
		core.cooldown = 0.0
		if not core.consume_shot():
			break
		shots += 1
	_check(core.is_overheated(), "sustained beam fire overheats (locked after %d shots)" % shots)
	_check(not core.can_fire(), "overheated weapon cannot fire")
	core.tick(60.0)
	_check(not core.is_overheated(), "cooling clears overheat")
	_check(core.can_fire(), "weapon unlocks after cooling")

	# --- 7. cryo install widens the tank without rebuilding call sites ---
	if GlobalData != null and GlobalData.weapons != null:
		FrameModuleSystem.init_slots_if_needed()
		var arr: Array = GlobalData.weapons.frame_modules.get("torso", [])
		var inv: Array = GlobalData.weapons.module_inventory
		var old_id := str(arr[0]) if arr.size() > 0 else ""
		var had_cryo := inv.has("cryo_heatsink_loop")
		if not had_cryo:
			inv.append("cryo_heatsink_loop")
		var cap_before: float = WeaponCore.from_weapon(beam).heat_capacity
		var ok := FrameModuleSystem.install_module("torso", 0, "cryo_heatsink_loop")
		_check(ok, "cryo installs into torso socket 0")
		if ok:
			var cap_after: float = WeaponCore.from_weapon(beam).heat_capacity
			_check(cap_after > cap_before, "cryo install widens fresh core heat tank")
			_check(is_equal_approx(cap_after, cap_before * 1.25), "cryo capacity bonus is +25%")
			# restore prior state exactly (undo install's return-to-cargo)
			if arr.size() > 0:
				arr[0] = old_id
			if old_id != "":
				inv.erase(old_id)
		if not had_cryo:
			inv.erase("cryo_heatsink_loop")

	print("HEAT_EVERY_GUN_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
