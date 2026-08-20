extends Node

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("MECHLESS OK: " + name)
	else:
		_fails += 1
		printerr("MECHLESS FAIL: " + name)


func _unit(tid: String, name: String) -> Dictionary:
	return {"template_id": tid, "name": name, "hp": 50.0, "max_hp": 50.0, "destroyed": false, "fielded": true}


func _ready() -> void:
	GlobalData.reset_run_data()
	GlobalData.fleet_roster = [_unit("grunt_squad", "Alpha"), _unit("ace_scout", "Bravo")]
	await get_tree().process_frame

	# --- Affiliation metadata ---
	var aff := ThemeSystem.get_affiliation()
	_check(aff.get("name", "") == "Fleet Soldier", "soldier affiliation name")
	_check(bool(aff.get("mechless_retreat", false)), "soldier convoy can retreat pilot-only")
	GlobalData.theme_id = "gundam_merc"
	_check(not bool(ThemeSystem.get_affiliation().get("mechless_retreat", true)), "gundam heir has no transport to retreat with")
	GlobalData.theme_id = "soldier"

	# --- Remove the seed mech -> pilot-only mode ---
	_check(GlobalData.hangar_mechs.size() == 1, "roster seeded with one mech")
	var destroyed_id := GlobalData.active_hangar_mech_id
	_check(HangarManager.remove_mech(destroyed_id), "remove the destroyed mech from the roster")
	_check(GlobalData.hangar_mechs.is_empty(), "roster is empty after removal")
	GlobalData.mech_less = GlobalData.hangar_mechs.is_empty()
	_check(GlobalData.mech_less, "mech_less flag set when roster empties")
	_check(HangarManager.can_mechless_retreat(), "squadmates left -> retreat, run continues")
	_check(GlobalData.active_hangar_mech_id == "", "no active mech while on foot")
	_check(HangarManager.get_mechs().is_empty(), "roster is NOT auto-reseeded while on foot")
	_check(HangarManager.build("").is_empty(), "cannot assemble a new mech while on foot")

	# --- Recovery pool only surfaces recovery events; normal pool never does ---
	var rec := ThemeSystem.get_weighted_recovery_event()
	_check(not rec.is_empty(), "recovery pool has an event")
	_check(bool(rec.get("params", {}).get("recovery", false)), "recovery event is flagged recovery")
	var normal := ThemeSystem.get_theme_event_pool()
	var has_recovery := false
	var has_garage := false
	for event in normal:
		if str(event.get("id", "")) == "abandoned_garage":
			has_recovery = true
		if str(event.get("id", "")) == "shady_garage":
			has_garage = true
	_check(not has_recovery, "recovery event excluded from the normal theme pool")
	_check(has_garage, "shady garage (trap) is a normal board event")

	# --- recover_mech choice rebuilds a chassis and ends pilot-only mode ---
	var recover_choice := {
		"effect": "recover_mech", "amount": 0,
		"params": {"heat": 1, "fallback_scrap": 30},
	}
	var forced := ThemeSystem.apply_event_effect(recover_choice)
	_check(not forced, "recover_mech does not force a scene transition")
	_check(GlobalData.hangar_mechs.size() == 1, "recovery rebuilt one mech")
	_check(not GlobalData.mech_less, "mech_less cleared after recovery mech granted")
	_check(GlobalData.active_hangar_mech_id == str(GlobalData.hangar_mechs[0].get("id", "")), "recovery mech is active")
	_check(GlobalData.run_notice != "", "recovery sets a convoy report")

	# --- Remove again; scrap choice on foot restores resources, stays on foot ---
	HangarManager.remove_mech(GlobalData.active_hangar_mech_id)
	GlobalData.mech_less = GlobalData.hangar_mechs.is_empty()
	var scrap_before := GlobalData.scrap
	GlobalData.part_damage["body"] = 0.8
	var scrap_choice := {
		"effect": "scrap", "amount": 30, "params": {"repair": 15},
	}
	ThemeSystem.apply_event_effect(scrap_choice)
	_check(GlobalData.scrap == scrap_before + 30, "scrap choice grants scrap")
	_check(GlobalData.part_damage["body"] < 0.8, "scrap choice also repairs parts")
	_check(GlobalData.mech_less, "scrap choice does not restore a mech")

	# --- recover_escort adds the first unowned ally ---
	var escort_before := GlobalData.fleet_roster.size()
	var escort := {"effect": "recover_escort", "amount": 0}
	ThemeSystem.apply_event_effect(escort)
	_check(GlobalData.fleet_roster.size() == escort_before + 1, "recover_escort adds an escort unit")
	_check(GlobalData.reputation == 1, "recover_escort grants reputation")

	# --- force_combat choice returns true (garage trap -> battle) ---
	var trap := {
		"effect": "force_combat", "amount": 0,
		"params": {"combat_type": "grunt"},
	}
	_check(ThemeSystem.apply_event_effect(trap), "force_combat choice forces a battle")

	# --- Save/load roundtrip preserves mech_less ---
	GlobalData.mech_less = true
	GlobalData.save_run()
	GlobalData.mech_less = false
	_check(GlobalData.load_run(), "save loads back")
	_check(GlobalData.mech_less, "mech_less flag survives save/load")

	# --- No squadmates left -> no retreat possible ---
	GlobalData.fleet_roster.clear()
	GlobalData.mech_less = true
	_check(not HangarManager.can_mechless_retreat(), "no squadmates -> pilot-only defeat ends the run")

	print("MECHLESS_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
