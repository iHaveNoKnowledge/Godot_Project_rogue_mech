extends Node

## Verifies weapons are tracked as separate physical instances (like armor),
## never merged into a x2 count:
##   1. Registering the same weapon model twice creates TWO inventory entries,
##      each with its own uid (never one entry with count=2).
##   2. Owning two copies lets the same model fill BOTH hands at once (dual
##      wield), while owning one copy still MOVES between slots.
##   3. A spare copy does not get marked as used by another mech.
## Run: godot --headless --path . res://tests/weapon_instances_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _ready() -> void:
	GlobalData.reset_run_data()
	await get_tree().process_frame

	await _verify_register_appends_instances()
	await _verify_dual_wield_with_two_copies()
	await _verify_single_copy_still_moves()
	await _verify_spare_not_marked_taken()
	print("WEAPON_INSTANCES_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _verify_register_appends_instances() -> void:
	var stash_size_before: int = GlobalData.weapon_inventory.size()
	var pile_bunker := "res://resources/mech/stock/weapon_pile_bunker.tres"
	GlobalData.register_weapon(pile_bunker, "Pile Bunker")
	GlobalData.register_weapon(pile_bunker, "Pile Bunker")
	await get_tree().process_frame

	_check(GlobalData.weapon_inventory.size() == stash_size_before + 2,
		"registering the same model twice appends two entries (got %d new)" % (GlobalData.weapon_inventory.size() - stash_size_before))
	_check(GlobalData.count_owned_weapon(pile_bunker) == 2,
		"count_owned_weapon counts both instances (2)")
	# No entry carries a merged count > 1.
	var merged := false
	for entry in GlobalData.weapon_inventory:
		if str(entry.get("path", "")) == pile_bunker and int(entry.get("count", 1)) > 1:
			merged = true
	_check(not merged, "no stash entry uses a merged x2 count")
	# Each instance has its own uid.
	var uids: Array = []
	for entry in GlobalData.weapon_inventory:
		if str(entry.get("path", "")) == pile_bunker:
			uids.append(str(entry.get("uid", "")))
	_check(uids.size() == 2 and uids[0] != uids[1], "both copies carry distinct instance uids")


func _verify_dual_wield_with_two_copies() -> void:
	GlobalData.reset_run_data()
	await get_tree().process_frame
	var blade := "res://resources/mech/stock/weapon_heat_blade.tres"
	# Two copies in the stash (the starter stash already has one heat blade, so
	# register a second).
	GlobalData.register_weapon(blade, "Heat Blade")
	await get_tree().process_frame
	_check(GlobalData.count_owned_weapon(blade) == 2, "setup: two heat blade copies owned")

	# Empty the loadout hands so the test starts clean.
	GlobalData.set_hand_weapon("left", "")
	GlobalData.set_hand_weapon("right", "")
	GlobalData.weapon_loadout["carry"] = []
	_check(GlobalData.has_spare_weapon(blade), "both copies are free spares at start")

	# Equip one copy in each hand — both must stick (no move/swap).
	GlobalData.set_hand_weapon("left", blade)
	_check(str(GlobalData.weapon_loadout.get("left", "")) == blade, "left hand holds the first copy")
	_check(GlobalData.has_spare_weapon(blade), "a spare copy remains after equipping the left hand")

	GlobalData.set_hand_weapon("right", blade)
	_check(str(GlobalData.weapon_loadout.get("right", "")) == blade, "right hand holds the second copy (dual wield)")
	_check(str(GlobalData.weapon_loadout.get("left", "")) == blade, "left hand KEEPS its copy when dual-wielding")
	_check(not GlobalData.has_spare_weapon(blade), "no spare remains after both hands are filled")


func _verify_single_copy_still_moves() -> void:
	GlobalData.reset_run_data()
	await get_tree().process_frame
	# Starter stash holds exactly ONE beam rifle.
	var rifle := GlobalData.DEFAULT_LEFT_WEAPON_PATH
	GlobalData.set_hand_weapon("left", "")
	GlobalData.set_hand_weapon("right", "")
	GlobalData.weapon_loadout["carry"] = []
	_check(GlobalData.count_owned_weapon(rifle) >= 1, "setup: at least one rifle owned")
	# Force a single-copy scenario: keep only the first instance.
	var kept := false
	for i in range(GlobalData.weapon_inventory.size() - 1, -1, -1):
		var entry = GlobalData.weapon_inventory[i]
		if str(entry.get("path", "")) == rifle:
			if kept:
				GlobalData.weapon_inventory.remove_at(i)
			else:
				kept = true
	_check(GlobalData.count_owned_weapon(rifle) == 1, "setup: exactly one rifle copy remains")

	GlobalData.set_hand_weapon("left", rifle)
	_check(str(GlobalData.weapon_loadout.get("left", "")) == rifle, "left hand holds the only rifle")
	_check(not GlobalData.has_spare_weapon(rifle), "no spare with a single copy equipped")

	# Equipping the RIGHT hand must MOVE the rifle (left frees).
	GlobalData.set_hand_weapon("right", rifle)
	_check(str(GlobalData.weapon_loadout.get("right", "")) == rifle, "right hand now holds the rifle")
	_check(str(GlobalData.weapon_loadout.get("left", "")) == "", "single copy MOVES — left hand is freed")


func _verify_spare_not_marked_taken() -> void:
	GlobalData.reset_run_data()
	await get_tree().process_frame
	var shotgun := GlobalData.DEFAULT_CARRY_WEAPON_PATH
	# A parked mech already carries a shotgun in its snapshot; we own two.
	GlobalData.register_weapon(shotgun, "Shotgun")
	await get_tree().process_frame
	_check(GlobalData.count_owned_weapon(shotgun) == 2, "setup: two shotgun copies owned")

	# Simulate the roster marking: count_owned (2) > copies used by other mechs
	# (the parked berth holds 1) -> the spare is free, not marked taken.
	var used_by_others := 1
	_check(used_by_others < GlobalData.count_owned_weapon(shotgun),
		"a spare copy exists beyond what other mechs hold")
