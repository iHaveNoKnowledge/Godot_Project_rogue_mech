extends Node

## Headless verification of the 8-type ammo catalog (AmmoSystem):
##   1. Every stock weapon resolves to a catalog ammo type (no gun shares a
##      pool outside its own family, except the deliberate missile/rocket split).
##   2. Prices/weights stay in sync between AmmoSystem, PilotSystem, GlobalData.
##   3. Legacy 4-type save pools migrate without stranding any gun.
## Run: godot --headless --path . res://tests/ammo_system_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("AMMO_OK: " + name)
	else:
		_fails += 1
		printerr("AMMO_FAIL: " + name)


func _ready() -> void:
	_verify_weapon_mapping()
	_verify_catalog_sync()
	_verify_migration()
	await get_tree().process_frame

	print("AMMO_SYSTEM_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _weapon_ammo(path: String) -> String:
	var w: WeaponPart = load(path)
	return w.get_ammo_type()


func _verify_weapon_mapping() -> void:
	var cases := {
		# light guns share bullets (their own family pool)
		"res://resources/mech/stock/weapon_machine_gun.tres": "bullet",
		"res://resources/mech/stock/weapon_light_machine_gun.tres": "bullet",
		"res://resources/mech/stock/weapon_pilot_pistol.tres": "bullet",
		"res://resources/mech/stock/weapon_pilot_assault_rifle.tres": "bullet",
		# belt-fed heavies no longer eat sidearm bullets
		"res://resources/mech/stock/weapon_heavy_machine_gun.tres": "heavy_round",
		"res://resources/mech/stock/weapon_gatling_gun.tres": "heavy_round",
		"res://resources/mech/stock/weapon_minigun.tres": "heavy_round",
		# shotguns get their own shells
		"res://resources/mech/stock/weapon_shotgun.tres": "shell",
		"res://resources/mech/stock/weapon_combat_shotgun.tres": "shell",
		"res://resources/mech/stock/weapon_sawed_off.tres": "shell",
		# piercing rods share spikes, not rifle bullets
		"res://resources/mech/stock/weapon_railgun.tres": "spike",
		"res://resources/mech/stock/weapon_pilot_anti_tank_rifle.tres": "spike",
		"res://resources/mech/stock/weapon_pile_bunker.tres": "spike",
		# beam family on energy cells
		"res://resources/mech/stock/weapon_beam_rifle.tres": "energy_cell",
		"res://resources/mech/stock/weapon_beam_rifle_mk2.tres": "energy_cell",
		"res://resources/mech/stock/weapon_beam_carbine.tres": "energy_cell",
		"res://resources/mech/stock/weapon_beam_sniper.tres": "energy_cell",
		# small pods fire rockets, big launchers fire missiles
		"res://resources/mech/stock/weapon_micro_missile.tres": "rocket",
		"res://resources/mech/stock/weapon_swarm_missile.tres": "rocket",
		"res://resources/mech/stock/weapon_missile.tres": "missile",
		"res://resources/mech/stock/weapon_heavy_missile.tres": "missile",
		# HE slingers stay on explosives
		"res://resources/mech/stock/weapon_assault_cannon.tres": "explosive",
		"res://resources/mech/stock/weapon_pilot_bazooka.tres": "explosive",
		# melee / shields consume nothing
		"res://resources/mech/stock/weapon_combat_knife.tres": "none",
		"res://resources/mech/stock/weapon_heat_blade.tres": "none",
		"res://resources/mech/stock/weapon_shield.tres": "none",
	}
	for path in cases:
		_check(_weapon_ammo(path) == cases[path], "%s uses %s" % [path.get_file(), cases[path]])
	# Every non-none mapping must be a real catalog type.
	for path in cases:
		var t := _weapon_ammo(path)
		_check(t == "none" or AmmoSystem.NAMES.has(t), "%s maps into the catalog" % path.get_file())


func _verify_catalog_sync() -> void:
	for ammo_id in AmmoSystem.ORDER:
		_check(PilotSystem.get_ammo_price(ammo_id) == AmmoSystem.price(ammo_id), "shop price in sync for %s" % ammo_id)
		_check(float(GlobalData.AMMO_WEIGHT_PER_UNIT.get(ammo_id, -1.0)) == AmmoSystem.weight_per_unit(ammo_id), "pack weight in sync for %s" % ammo_id)
	_check(AmmoSystem.ORDER.size() == 8, "catalog holds 8 ammo types")


func _verify_migration() -> void:
	# Legacy 4-type pool: nothing lost, every successor funded.
	var legacy := {"kinetic": 100, "energy": 50, "missile": 20, "explosive": 10}
	AmmoSystem.migrate_dict(legacy)
	_check(not legacy.has("kinetic") and not legacy.has("energy"), "legacy keys are gone after migration")
	for t in ["bullet", "heavy_round", "shell", "spike"]:
		_check(int(legacy.get(t, 0)) == 100, "kinetic migrates into %s" % t)
	_check(int(legacy.get("energy_cell", 0)) == 50, "energy migrates into energy_cell")
	_check(int(legacy.get("missile", 0)) == 20 and int(legacy.get("rocket", 0)) == 20, "missile funds missile + rocket")
	_check(int(legacy.get("explosive", 0)) == 10, "explosive stays explosive")
	# Modern pools pass through untouched.
	var modern := {"bullet": 5, "spike": 7}
	AmmoSystem.migrate_dict(modern)
	_check(int(modern.get("bullet", 0)) == 5 and int(modern.get("spike", 0)) == 7, "modern pool is untouched")
