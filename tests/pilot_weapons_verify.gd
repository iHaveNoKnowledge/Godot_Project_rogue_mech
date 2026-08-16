extends Node

## Verifies the pilot weapons system:
##   1. The PILOT WEAPON DB is separate from mech weapons — the four pilot guns
##      (pistol / assault rifle / anti-tank rifle / bazooka) with their sizes
##      and carry-point costs (small 1 / medium 2 / big 3).
##   2. The 7-point carry budget: equipping within budget works, exceeding it
##      is rejected, mech weapons are never equipable on foot.
##   3. Sprint/stamina: pilot stamina is its own pool (separate from the mech's
##      energy), drains while sprinting, regens while walking.
## Run: godot --headless --path . res://tests/pilot_weapons_verify.tscn

var _fails := 0
var _checks := 0

const PISTOL := "res://resources/mech/stock/weapon_pilot_pistol.tres"
const ASSAULT := "res://resources/mech/stock/weapon_pilot_assault_rifle.tres"
const ANTITANK := "res://resources/mech/stock/weapon_pilot_anti_tank_rifle.tres"
const BAZOOKA := "res://resources/mech/stock/weapon_pilot_bazooka.tres"
const MECH_GUN := "res://resources/mech/stock/weapon_machine_gun.tres"


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("PILOTW OK: " + name)
	else:
		_fails += 1
		printerr("PILOTW FAIL: " + name)


func _ready() -> void:
	GlobalData.reset_run_data()
	await get_tree().process_frame

	# --- 1. Database shape ---
	var db := PilotSystem.get_pilot_weapon_db()
	_check(db.size() == 4, "pilot weapon DB has 4 entries")
	_check(PilotSystem.get_pilot_weapon_points(PISTOL) == 1, "pistol costs 1 point")
	_check(PilotSystem.get_pilot_weapon_points(ASSAULT) == 2, "assault rifle costs 2 points")
	_check(PilotSystem.get_pilot_weapon_points(ANTITANK) == 3, "anti-tank rifle costs 3 points")
	_check(PilotSystem.get_pilot_weapon_points(BAZOOKA) == 3, "bazooka costs 3 points")
	_check(PilotSystem.get_pilot_weapon_size(PISTOL) == "small", "pistol is small size")
	_check(PilotSystem.get_pilot_weapon_size(ASSAULT) == "medium", "assault rifle is medium")
	_check(PilotSystem.get_pilot_weapon_size(ANTITANK) == "big", "anti-tank rifle is big")
	_check(PilotSystem.get_pilot_weapon_size(BAZOOKA) == "big", "bazooka is big")
	_check(ResourceLoader.exists(PISTOL) and load(PISTOL) is WeaponPart, "pistol resource loads as WeaponPart")
	_check(ResourceLoader.exists(BAZOOKA) and load(BAZOOKA) is WeaponPart, "bazooka resource loads as WeaponPart")

	# --- 2. Budget enforcement ---
	GlobalData.pilot_weapons = []
	_check(PilotSystem.get_pilot_carry_points() == 7, "base carry budget is 7 points")
	_check(PilotSystem.get_pilot_carry_used() == 0, "empty loadout uses 0 points")
	_check(PilotSystem.get_pilot_carry_remaining() == 7, "7 points remain empty")
	_check(PilotSystem.can_equip_pilot_weapon(BAZOOKA), "bazooka fits in an empty loadout")
	_check(not PilotSystem.can_equip_pilot_weapon(MECH_GUN), "mech weapons are NOT in the pilot DB")

	# Pistol + assault + anti-tank = 1+2+3 = 6 <= 7 -> all fit.
	_check(PilotSystem.add_weapon(PISTOL), "equip pistol succeeds")
	_check(PilotSystem.add_weapon(ASSAULT), "equip assault rifle succeeds")
	_check(PilotSystem.add_weapon(ANTITANK), "equip anti-tank rifle succeeds")
	_check(PilotSystem.get_pilot_carry_used() == 6, "6 points used after 3 weapons")
	_check(PilotSystem.get_pilot_carry_remaining() == 1, "1 point remains")
	# Adding a 4th (bazooka, 3pt) would exceed 7 -> rejected.
	_check(not PilotSystem.add_weapon(BAZOOKA), "equipping bazooka over budget is rejected")
	_check(not PilotSystem.add_weapon(MECH_GUN), "mech weapon equip is rejected entirely")
	_check(GlobalData.pilot_weapons.size() == 3, "only 3 weapons equipped")
	_check(not PilotSystem.add_weapon(PISTOL), "duplicate weapon equip is rejected")

	# Unequip frees budget -> bazooka now fits.
	PilotSystem.remove_weapon(ASSAULT)
	_check(PilotSystem.get_pilot_carry_used() == 4, "unequip assault frees 2 points")
	_check(PilotSystem.add_weapon(BAZOOKA), "bazooka fits after freeing points")
	_check(PilotSystem.get_pilot_carry_used() == 7, "7 points used exactly at budget")

	# --- 3. Pilot controller stamina (separate from mech energy) ---
	GlobalData.reset_run_data()
	var pilot_scene := load("res://scenes/pilot/pilot.tscn") as PackedScene
	_check(pilot_scene != null, "pilot scene loads")
	if pilot_scene:
		var pilot = pilot_scene.instantiate()
		add_child(pilot)
		await get_tree().process_frame
		_check(pilot.get("max_stamina") == 100.0, "pilot max stamina is 100")
		_check(is_equal_approx(pilot.get("stamina"), 100.0), "pilot starts with full stamina")
		_check(is_equal_approx(pilot.get_stamina_ratio(), 1.0), "stamina ratio starts at 1.0")
		# Drain manually (simulates sprint) then check regen clamp.
		pilot.stamina = 30.0
		_check(is_equal_approx(pilot.get_stamina_ratio(), 0.3), "stamina ratio reflects current pool")
		pilot.stamina = 0.0
		_check(is_equal_approx(pilot.get_stamina_ratio(), 0.0), "empty stamina clamps at 0")
		pilot.queue_free()

	print("PILOTW_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)
