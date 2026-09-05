extends Node

var _fails := 0
var _checks := 0

func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("[PASS] " + name)
	else:
		_fails += 1
		printerr("[FAIL] " + name)

func _ready() -> void:
	print("=== Running Weapon and Ammo Persistence Verification Suite ===")

	# 1. Test Ally Recruitment Isolation
	GlobalData.reset_run_data()
	GlobalData.hangar.fleet_roster = [
		{"template_id": "grunt_squad", "name": "Alpha", "hp": 50.0, "max_hp": 50.0, "destroyed": false, "fielded": true},
		{"template_id": "ace_scout", "name": "Bravo", "hp": 50.0, "max_hp": 50.0, "destroyed": false, "fielded": true}
	]
	
	# Set player active mech with distinct weapons
	var p_left = LoadoutSystem.register_weapon("res://resources/mech/stock/weapon_assault_cannon.tres")
	var p_right = LoadoutSystem.register_weapon("res://resources/mech/stock/weapon_heat_blade.tres")
	GlobalData.weapons.weapon_loadout["left"] = p_left
	GlobalData.weapons.weapon_loadout["right"] = p_right
	HangarManager.save_active()

	var player_before_berth = HangarManager.get_active_mech()
	var p_left_before = player_before_berth.get("weapon_loadout", {}).get("left", "")
	var p_right_before = player_before_berth.get("weapon_loadout", {}).get("right", "")

	# Recruit Serra
	var recruit_ok = RecruitSystem.recruit("serra")
	_check(recruit_ok, "Recruit Serra succeeded")

	# Check that player weapons are unchanged
	var player_after_berth = HangarManager.get_active_mech()
	var p_left_after = player_after_berth.get("weapon_loadout", {}).get("left", "")
	var p_right_after = player_after_berth.get("weapon_loadout", {}).get("right", "")
	_check(p_left_after == p_left_before and p_left_after == p_left, "Player left weapon unchanged after recruiting ally")
	_check(p_right_after == p_right_before and p_right_after == p_right, "Player right weapon unchanged after recruiting ally")

	# Check ally berth weapons are completely distinct
	var ally_berth: Dictionary = {}
	for b in HangarManager.get_mechs():
		if str(b.get("pilot", "")) == "fleet_ally_serra":
			ally_berth = b
			break
	_check(not ally_berth.is_empty(), "Ally Serra mech berth found")
	var ally_w_loadout = ally_berth.get("weapon_loadout", {})
	_check(ally_w_loadout.get("left", "") != p_left, "Ally left weapon UID is distinct from player's")
	_check(ally_w_loadout.get("right", "") != p_right, "Ally right weapon UID is distinct from player's")

	# 2. Test Ammo Looting & Inventory Transfer
	var dummy_mecha = CharacterBody3D.new()
	dummy_mecha.add_to_group("mecha")
	var wm = Node3D.new()
	wm.name = "WeaponManager"
	wm.set_script(load("res://scripts/mecha/weapon_manager.gd"))
	dummy_mecha.add_child(wm)
	add_child(dummy_mecha)

	var starting_kinetic_reserve = wm.get_battle_reserve("kinetic")
	var starting_kinetic_stash = LoadoutSystem.get_reserve_ammo("kinetic")

	var dummy_pickup_node = Area3D.new()
	dummy_pickup_node.set_script(load("res://scripts/mecha/weapon_pickup.gd"))
	var dropped_weapon = WeaponPart.new()
	dropped_weapon.weapon_name = "Test Kinetic Cannon"
	dropped_weapon.weapon_type = WeaponPart.WeaponType.MACHINE_GUN
	dropped_weapon.ammo_type = "kinetic"
	dropped_weapon.max_ammo = 100
	dummy_pickup_node.weapon_resource = dropped_weapon
	dummy_pickup_node.current_ammo = 60
	add_child(dummy_pickup_node)

	var drained = dummy_pickup_node.unload_ammo_to_player(dummy_mecha)
	_check(drained == 60, "WeaponPickup unloaded full ammo (60 rounds)")
	_check(dummy_pickup_node.current_ammo == 0, "Dropped weapon pickup ammo reduced to 0")
	_check(wm.get_battle_reserve("kinetic") == starting_kinetic_reserve + 60, "Player WeaponManager battle reserve increased by 60")
	_check(LoadoutSystem.get_reserve_ammo("kinetic") == starting_kinetic_stash + 60, "LoadoutSystem ammo inventory persisted +60")

	# 3. Test Carry Weapon Selection List (1-3) Excludes Ammo
	_check(wm.carry is Array, "WeaponManager carry is an Array of WeaponPart")
	for item in wm.carry:
		_check(item is WeaponPart, "Carry item is purely WeaponPart, never raw ammo")

	print("TEST SUMMARY: checks=%d fails=%d" % [_checks, _fails])
	dummy_mecha.queue_free()
	dummy_pickup_node.queue_free()
	get_tree().quit(1 if _fails > 0 else 0)
