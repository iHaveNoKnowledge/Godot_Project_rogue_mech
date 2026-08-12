extends Node

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("ROSTER OK: " + name)
	else:
		_fails += 1
		printerr("ROSTER FAIL: " + name)


func _pilot_of(mech_id: String) -> String:
	for mech in GlobalData.get_hangar_mechs():
		if str(mech.get("id", "")) == mech_id:
			return str(mech.get("pilot", ""))
	return ""


func _unit(tid: String, name: String) -> Dictionary:
	return {"template_id": tid, "name": name, "hp": 50.0, "max_hp": 50.0, "destroyed": false, "fielded": true}


func _ready() -> void:
	# One clean reset at the top; reset_run_data() re-seeds the roster AND clears
	# the fleet, so the fleet is configured once right after.
	GlobalData.reset_run_data()
	GlobalData.fleet_roster = [_unit("grunt_squad", "Alpha"), _unit("ace_scout", "Bravo")]
	await get_tree().process_frame

	# --- Fleet-driven capacity ---
	GlobalData.fleet_roster.clear()
	_check(GlobalData.get_hangar_capacity() == 2, "solo convoy parks 2 mechs")
	GlobalData.fleet_roster = [_unit("grunt_squad", "Alpha"), _unit("ace_scout", "Bravo")]
	_check(GlobalData.get_hangar_capacity() == 8, "fleet of 3 pilots -> 2 trucks -> 8 berths")

	# --- Seed / roster basics ---
	GlobalData.ensure_hangar_roster()
	var mechs := GlobalData.get_hangar_mechs()
	_check(mechs.size() == 1, "roster seeded with one mech")
	_check(int(mechs[0].get("slot", 0)) == 1, "seed mech parked in slot 1")
	_check(str(mechs[0].get("pilot", "")) == "player", "player pilot drives the seed mech")

	var pilots := GlobalData.get_hangar_pilots()
	_check(pilots.size() == 3, "pilot list = YOU + 2 fleet units")
	_check(GlobalData.get_hangar_pilot_name("player") == "YOU (driver)", "player pilot display name")

	# --- Build into a requested empty slot ---
	var built := GlobalData.build_hangar_mech("", 4)
	_check(not built.is_empty(), "can build a mech")
	_check(int(built.get("slot", 0)) == 4, "built mech parked in requested slot 4")
	_check(str(built.get("name", "")) == "Mech 04", "built mech auto-named by slot number")
	_check(str(built.get("pilot", "")) == "", "newly built mech has no pilot until assigned")
	mechs = GlobalData.get_hangar_mechs()
	_check(mechs.size() == 2, "two mechs parked after build")
	_check(GlobalData.build_hangar_mech("", 1).is_empty(), "cannot build into an occupied slot")

	# --- Pilot assignment: moving the player out of mech01 into mech04 ---
	var id01 := str(mechs[0].get("id", ""))
	var id04 := str(mechs[1].get("id", ""))
	_check(GlobalData.assign_hangar_pilot(id04, "player"), "assign player to mech04")
	_check(_pilot_of(id04) == "player", "player now drives mech04")
	_check(_pilot_of(id01) == "", "mech01 seat is empty after the player moved out")

	# --- Pilot swap: player into an occupied berth trades seats ---
	var npc_id := "fleet_grunt_squad"
	_check(GlobalData.assign_hangar_pilot(id01, npc_id), "assign squadmate to mech01")
	_check(_pilot_of(id01) == npc_id, "squadmate drives mech01")
	_check(GlobalData.assign_hangar_pilot(id01, "player"), "move player into occupied mech01")
	_check(_pilot_of(id01) == "player", "player sits in mech01 after the move")
	_check(_pilot_of(id04) == npc_id, "squadmate swapped into mech04")

	# --- Capacity gating: fill all 8 berths then reject more ---
	for slot in [2, 3, 5, 6, 7, 8]:
		_check(not GlobalData.build_hangar_mech("", slot).is_empty(), "build fills empty slot %d" % slot)
	_check(GlobalData.get_hangar_mechs().size() == 8, "convoy is full at 8/8")
	_check(GlobalData.build_hangar_mech("").is_empty(), "convoy full - cannot build another mech")
	_check(GlobalData.build_hangar_mech("", 9).is_empty(), "cannot build beyond capacity (slot 9)")

	# --- Backup + switch by id ---
	var backup := GlobalData.get_backup_hangar_mech_id()
	_check(backup != "" and backup != GlobalData.active_hangar_mech_id, "backup mech id differs from active")
	_check(GlobalData.switch_hangar_mech(id04), "switch to mech04")
	_check(GlobalData.active_hangar_mech_id == id04, "active id updated after switch")
	_check(GlobalData.get_hangar_slot_of(id04) == 4, "slot lookup returns 4")

	# --- Old-save migration: entries without slot/pilot get both ---
	GlobalData.hangar_mechs = [
		{"id": "old_1", "name": "Old One", "chassis_id": "standard", "frames": {}, "parts": {}, "damage": {}, "attachments": [], "weapon_loadout": {}, "scrap_patches": {}},
		{"id": "old_2", "name": "Old Two", "chassis_id": "standard", "frames": {}, "parts": {}, "damage": {}, "attachments": [], "weapon_loadout": {}, "scrap_patches": {}},
	]
	GlobalData.active_hangar_mech_id = "old_1"
	GlobalData.ensure_hangar_roster()
	mechs = GlobalData.get_hangar_mechs()
	_check(int(mechs[0].get("slot", 0)) == 1 and int(mechs[1].get("slot", 0)) == 2, "old saves get stable slots")
	_check(str(mechs[0].get("pilot", "")) == "player", "old saves assign the player to the first mech")

	# --- Archetype (ROLE): defaults, set, clamp, persist through save/load ---
	_check(GlobalData.get_hangar_archetype("old_1") == HangarManager.ARCHETYPE_RANGED, "old saves default to Ranged archetype")
	_check(GlobalData.get_hangar_archetype("missing") == HangarManager.ARCHETYPE_RANGED, "unknown mech falls back to Ranged")
	_check(GlobalData.set_hangar_archetype("old_1", HangarManager.ARCHETYPE_RUSHER), "can set Rusher role")
	_check(GlobalData.get_hangar_archetype("old_1") == HangarManager.ARCHETYPE_RUSHER, "role reads back as Rusher")
	_check(not GlobalData.set_hangar_archetype("missing", HangarManager.ARCHETYPE_HEAVY), "unknown mech rejects role change")
	_check(GlobalData.set_hangar_archetype("old_1", 99), "role set clamps out-of-range")
	_check(GlobalData.get_hangar_archetype("old_1") == HangarManager.ARCHETYPE_SUPPORT, "role clamped to Support max")

	print("ROSTER_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
