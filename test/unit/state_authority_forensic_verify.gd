extends Node

## STATE AUTHORITY FORENSIC AUDIT — identity/state contract verification.
##
## Proves ACTIVE ID == STATE OWNER == WORKING SET OWNER == RUNTIME SOURCE
## across switch / destroy-handover / recovery / sacrifice / save-load paths.
##
## Run: godot --headless res://test/unit/state_authority_forensic_verify.tscn

var _pass_count: int = 0
var _fail_count: int = 0
var _failed_messages: Array[String] = []
var _save_backup: PackedByteArray = PackedByteArray()
var _had_save: bool = false


func _ready() -> void:
	print("\n=== STARTING STATE AUTHORITY FORENSIC AUDIT ===\n")
	GameManager.suppress_scene_change = true
	_backup_save()
	await _run_all()
	_restore_save()
	GameManager.suppress_scene_change = false
	print("\n==================================================")
	print("STATE AUTHORITY FORENSIC SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failed_messages.is_empty():
		print("FAILED ASSERTIONS:")
		for msg in _failed_messages:
			print("  - " + msg)
	print("==================================================")
	if _fail_count == 0:
		print("STATE_AUTHORITY_FORENSIC_SUCCESS\n")
	else:
		push_error("STATE_AUTHORITY_FORENSIC_FAILURE: %d assertions failed" % _fail_count)
	get_tree().quit(0 if _fail_count == 0 else 1)


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("  [PASS] %s" % msg)
	else:
		_fail_count += 1
		_failed_messages.append(msg)
		push_error("Assertion failed: %s" % msg)
		print("  [FAIL] %s" % msg)


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


func _run_all() -> void:
	GlobalData.reset_run_data()
	GlobalData.hangar.hangar_mechs.clear()
	GlobalData.narrative.mech_less = false
	HangarManager.ensure_roster()
	await _case_a_switch()
	await _case_b_destroy_handover()
	await _case_c_repeated_swap()
	await _case_d1_sacrifice_grand_entry()
	await _case_d2_recovery_clone()
	await _case_e_save_load_roundtrip()


func _snapshot_working() -> Dictionary:
	return {
		"chassis": str(GlobalData.weapons.chassis_id),
		"damage": (GlobalData.weapons.part_damage as Dictionary).duplicate(true),
		"loadout": (GlobalData.weapons.weapon_loadout as Dictionary).duplicate(true),
	}


func _berth_state(mech_id: String) -> Dictionary:
	for m in GlobalData.hangar.hangar_mechs:
		if m is Dictionary and str(m.get("id", "")) == mech_id:
			return {
				"chassis": str(m.get("chassis_id", "")),
				"damage": (m.get("damage", {}) as Dictionary).duplicate(true),
				"loadout": (m.get("weapon_loadout", {}) as Dictionary).duplicate(true),
			}
	return {}


# Case A: A damaged, B pristine, A -> B verifies full identity handoff.
func _case_a_switch() -> void:
	print("\n--- Case A: identity swap A(damaged) -> B(pristine) ---\n")
	GlobalData.reset_run_data()
	GlobalData.hangar.hangar_mechs.clear()
	GlobalData.narrative.mech_less = false
	HangarManager.ensure_roster()
	var id_a: String = GlobalData.hangar.active_hangar_mech_id
	# Distinct A state.
	GlobalData.weapons.chassis_id = "standard"
	GlobalData.weapons.part_damage = {"arm_left": 0.6, "leg_left": 0.3}
	GlobalData.weapons.weapon_loadout = {"left": "w_A_left", "right": "w_A_right", "carry": [], "ammo": {}}
	HangarManager.save_active()
	# Park B then give it pristine distinct state.
	var built: Dictionary = HangarManager.build("MechB")
	var id_b: String = str(built.get("id", ""))
	_assert(id_b != "" and id_b != id_a, "A: reserve berth B parked")
	HangarManager.load_mech_state(id_b)
	GlobalData.weapons.chassis_id = "aegis"
	GlobalData.weapons.part_damage = {}
	GlobalData.weapons.weapon_loadout = {"left": "w_B_left", "right": "w_B_right", "carry": [], "ammo": {}}
	HangarManager.save_mech_state(id_b)
	HangarManager.load_mech_state(id_a)
	_assert(str(GlobalData.weapons.chassis_id) == "standard", "A: working set back on A before switch")
	# Switch A -> B via production path.
	var ok: bool = HangarManager.switch_mech(id_b)
	_assert(ok, "A: switch_mech(B) returns true")
	_assert(GlobalData.hangar.active_hangar_mech_id == id_b, "A: active ID = B")
	_assert(str(GlobalData.weapons.chassis_id) == "aegis", "A: working chassis = B")
	_assert((GlobalData.weapons.part_damage as Dictionary).is_empty(), "A: working damage = B (pristine)")
	_assert(str(GlobalData.weapons.weapon_loadout.get("left", "")) == "w_B_left", "A: working loadout = B")
	var berth_b: Dictionary = _berth_state(id_b)
	_assert(str(berth_b.get("chassis", "")) == "aegis", "A: berth B chassis intact")
	# And back B -> A.
	var ok2: bool = HangarManager.switch_mech(id_a)
	_assert(ok2, "A: switch_mech(A) returns true")
	_assert(GlobalData.hangar.active_hangar_mech_id == id_a, "A: active ID = A again")
	_assert(str(GlobalData.weapons.chassis_id) == "standard", "A: working chassis = A")
	_assert(absf(float((GlobalData.weapons.part_damage as Dictionary).get("arm_left", 0.0)) - 0.6) < 0.0001, "A: working damage = A")
	_assert(str(GlobalData.weapons.weapon_loadout.get("left", "")) == "w_A_left", "A: working loadout = A")


# Case B: A destroyed, handover to B, board, combat again — B pristine, no leak.
func _case_b_destroy_handover() -> void:
	print("\n--- Case B: destroyed handover A(wreck) -> B(reserve) ---\n")
	var id_a: String = GlobalData.hangar.active_hangar_mech_id
	HangarManager.save_active()
	var ids: Array = []
	for m in HangarManager.get_mechs():
		ids.append(str(m.get("id", "")))
	var id_b: String = ""
	for mid in ids:
		if mid != id_a:
			id_b = mid
	if id_b == "":
		var built: Dictionary = HangarManager.build("ReserveB")
		id_b = str(built.get("id", ""))
	# Seed reserve B to a known distinct pristine-ish state regardless of prior cases.
	HangarManager.load_mech_state(id_b)
	GlobalData.weapons.chassis_id = "aegis"
	GlobalData.weapons.part_damage = {"body": 0.4}
	GlobalData.weapons.weapon_loadout = {"left": "w_B_left", "right": "w_B_right", "carry": [], "ammo": {}}
	HangarManager.save_mech_state(id_b)
	HangarManager.load_mech_state(id_a)
	# Doom A.
	GlobalData.weapons.part_damage = {"body": 1.0, "body_frame": 1.0, "arm_left": 1.0}
	HangarManager.save_active()
	GameManager.enter_combat("grunt")
	EventBus.combat_ended.emit(false)
	var removed: bool = HangarManager.remove_mech(GlobalData.hangar.active_hangar_mech_id)
	GlobalData.narrative.mech_less = GlobalData.hangar.hangar_mechs.is_empty()
	_assert(removed, "B: wreck removed")
	_assert(GlobalData.hangar.active_hangar_mech_id == id_b, "B: active = reserve")
	GameManager.return_to_board()
	var b_after: Dictionary = _berth_state(id_b)
	_assert(str(b_after.get("chassis", "")) == "aegis", "B: reserve chassis not clobbered")
	_assert(absf(float((b_after.get("damage", {}) as Dictionary).get("body", -1.0)) - 0.4) < 0.0001, "B: reserve damage not clobbered")
	GameManager.enter_combat("grunt")
	_assert(str(GlobalData.weapons.chassis_id) == "aegis", "B: combat reconstructs reserve")
	_assert(float((GlobalData.weapons.part_damage as Dictionary).get("body_frame", 0.0)) < 1.0, "B: wreck body_frame does not leak")
	GameManager.return_to_board()


# Case C: A/B partially damaged differently, repeated swaps preserve exactly.
func _case_c_repeated_swap() -> void:
	print("\n--- Case C: repeated A<->B swaps preserve exact state ---\n")
	# Case B removed the wreck, leaving a single reserve berth. Re-park a second
	# berth so the repeated-swap stress has two identities to alternate.
	if HangarManager.get_mechs().size() < 2:
		var rebuilt: Dictionary = HangarManager.build("SwapA")
		_assert(not rebuilt.is_empty(), "C: second berth re-parked after handover")
	var ids: Array = []
	for m in HangarManager.get_mechs():
		ids.append(str(m.get("id", "")))
	if ids.size() < 2:
		_assert(false, "C: need two berths (setup)")
		return
	var id_a: String = GlobalData.hangar.active_hangar_mech_id
	var id_b: String = ""
	for mid in ids:
		if mid != id_a:
			id_b = mid
	# Seed distinct partial damage.
	HangarManager.load_mech_state(id_a)
	GlobalData.weapons.chassis_id = "standard"
	GlobalData.weapons.part_damage = {"leg_left": 0.5, "head": 0.2}
	GlobalData.weapons.weapon_loadout = {"left": "w_A_left", "right": "w_A_right", "carry": [], "ammo": {}}
	HangarManager.save_mech_state(id_a)
	HangarManager.load_mech_state(id_b)
	GlobalData.weapons.chassis_id = "aegis"
	GlobalData.weapons.part_damage = {"leg_right": 0.7, "arm_right": 0.1}
	GlobalData.weapons.weapon_loadout = {"left": "w_B_left", "right": "w_B_right", "carry": [], "ammo": {}}
	HangarManager.save_mech_state(id_b)
	var expect_a: Dictionary = _berth_state(id_a)
	var expect_b: Dictionary = _berth_state(id_b)
	HangarManager.load_mech_state(id_a)
	HangarManager.switch_mech(id_a)  # ensure active A (no-op if already)
	GlobalData.hangar.active_hangar_mech_id = id_a
	HangarManager.load_mech_state(id_a)
	var seq: Array = [id_b, id_a, id_b, id_a, id_b, id_a]
	for i in range(seq.size()):
		HangarManager.switch_mech(str(seq[i]))
		var wid: String = GlobalData.hangar.active_hangar_mech_id
		var w: Dictionary = _snapshot_working()
		var exp: Dictionary = expect_a if wid == id_a else expect_b
		_assert(str(w.get("chassis", "")) == str(exp.get("chassis", "")), "C%d: chassis matches berth %s" % [i + 1, wid])
		_assert((w.get("damage", {}) as Dictionary) == (exp.get("damage", {}) as Dictionary), "C%d: damage matches berth %s" % [i + 1, wid])
		_assert(str((w.get("loadout", {}) as Dictionary).get("left", "")) == str((exp.get("loadout", {}) as Dictionary).get("left", "")), "C%d: loadout matches berth %s" % [i + 1, wid])
	# Final berths unchanged.
	_assert(_berth_state(id_a).get("damage", {}) == (expect_a.get("damage", {}) as Dictionary), "C: berth A damage stable")
	_assert(_berth_state(id_b).get("damage", {}) == (expect_b.get("damage", {}) as Dictionary), "C: berth B damage stable")


# D1: sacrifice grand entry must handover identity+state (same contract as switch/remove).
func _case_d1_sacrifice_grand_entry() -> void:
	print("\n--- Case D1: sacrifice grand entry handover ---\n")
	GlobalData.reset_run_data()
	GlobalData.hangar.hangar_mechs.clear()
	GlobalData.narrative.mech_less = false
	HangarManager.ensure_roster()
	# Old mech heavily damaged (sacrifice trigger condition).
	GlobalData.weapons.chassis_id = "standard"
	GlobalData.weapons.part_damage = {"body": 1.0, "body_frame": 1.0, "arm_left": 1.0, "leg_left": 0.5}
	GlobalData.weapons.weapon_loadout = {"left": "w_old_left", "right": "w_old_right", "carry": [], "ammo": {}}
	HangarManager.save_active()
	var old_id: String = GlobalData.hangar.active_hangar_mech_id
	# Production path: build Hero Unit then set active (sacrifice_event.complete_grand_entry).
	var SacScript = load("res://scripts/systems/sacrifice_event.gd")
	var node: Node = SacScript.new()
	add_child(node)
	GlobalData.narrative.grand_entry_mech_id = "gm_custom"
	GlobalData.narrative.grand_entry_pending = true
	node.complete_grand_entry()
	var new_id: String = GlobalData.hangar.active_hangar_mech_id
	_assert(new_id != "" and new_id != old_id, "D1: grand entry re-points active to Hero Unit")
	var berth: Dictionary = _berth_state(new_id)
	var working: Dictionary = _snapshot_working()
	_assert(str(berth.get("chassis", "")) == str(working.get("chassis", "")), "D1: working chassis == Hero berth chassis (no old-chassis leak)")
	_assert((berth.get("damage", {}) as Dictionary) == (working.get("damage", {}) as Dictionary), "D1: working damage == Hero berth damage (no wreck leak)")
	_assert(float((working.get("damage", {}) as Dictionary).get("body_frame", 0.0)) < 1.0, "D1: wreck body_frame does not leak into Hero working set")
	# Save must not clobber Hero berth with wreck state.
	HangarManager.save_active()
	var berth2: Dictionary = _berth_state(new_id)
	_assert(str(berth2.get("chassis", "")) == str(berth.get("chassis", "")), "D1: save_active preserves Hero chassis")
	_assert((berth2.get("damage", {}) as Dictionary) == (berth.get("damage", {}) as Dictionary), "D1: save_active preserves Hero damage")
	node.queue_free()
	await get_tree().process_frame


# D2: mech-less recovery grant must not clone the wreck's damage.
func _case_d2_recovery_clone() -> void:
	print("\n--- Case D2: mech-less recovery grant ---\n")
	GlobalData.reset_run_data()
	GlobalData.hangar.hangar_mechs.clear()
	GlobalData.narrative.mech_less = false
	HangarManager.ensure_roster()
	var id_a: String = GlobalData.hangar.active_hangar_mech_id
	GlobalData.weapons.chassis_id = "standard"
	GlobalData.weapons.part_damage = {"body": 1.0, "body_frame": 1.0, "arm_left": 1.0, "arm_right": 1.0}
	GlobalData.weapons.weapon_loadout = {"left": "w_wreck_left", "right": "w_wreck_right", "carry": [], "ammo": {}}
	HangarManager.save_active()
	# Destroy last mech -> empty roster, working set still holds wreck.
	var removed: bool = HangarManager.remove_mech(id_a)
	_assert(removed, "D2: last mech removed")
	_assert(GlobalData.hangar.hangar_mechs.is_empty(), "D2: roster empty")
	GlobalData.narrative.mech_less = true
	var wreck_damage: Dictionary = (GlobalData.weapons.part_damage as Dictionary).duplicate(true)
	_assert(float(wreck_damage.get("body_frame", 0.0)) >= 1.0, "D2: working set still holds wreck (precondition)")
	var granted: Dictionary = HangarManager.grant_recovery_mech()
	var gid: String = str(granted.get("id", ""))
	_assert(gid != "", "D2: recovery granted")
	_assert(GlobalData.hangar.active_hangar_mech_id == gid, "D2: recovery is active")
	var berth: Dictionary = _berth_state(gid)
	var working: Dictionary = _snapshot_working()
	_assert(str(berth.get("chassis", "")) == str(working.get("chassis", "")), "D2: working chassis == granted berth")
	_assert((berth.get("damage", {}) as Dictionary) == (working.get("damage", {}) as Dictionary), "D2: working damage == granted berth")
	_assert(float((working.get("damage", {}) as Dictionary).get("body_frame", 0.0)) < 1.0, "D2: wreck body_frame does not leak into recovery")
	_assert(float((working.get("damage", {}) as Dictionary).get("body", 0.0)) < 1.0, "D2: wreck body damage does not leak into recovery")
	_assert((working.get("damage", {}) as Dictionary).is_empty(), "D2: fresh recovery chassis is pristine")


# E: save/load round trip preserves identity==state.
func _case_e_save_load_roundtrip() -> void:
	print("\n--- Case E: save/load round trip ---\n")
	GlobalData.reset_run_data()
	GlobalData.hangar.hangar_mechs.clear()
	GlobalData.narrative.mech_less = false
	HangarManager.ensure_roster()
	var id_a: String = GlobalData.hangar.active_hangar_mech_id
	GlobalData.weapons.chassis_id = "standard"
	GlobalData.weapons.part_damage = {"leg_left": 0.5}
	GlobalData.weapons.weapon_loadout = {"left": "w_A_left", "right": "w_A_right", "carry": [], "ammo": {}}
	HangarManager.save_active()
	var built: Dictionary = HangarManager.build("MechB")
	var id_b: String = str(built.get("id", ""))
	HangarManager.load_mech_state(id_b)
	GlobalData.weapons.chassis_id = "aegis"
	GlobalData.weapons.part_damage = {"leg_right": 0.25}
	GlobalData.weapons.weapon_loadout = {"left": "w_B_left", "right": "w_B_right", "carry": [], "ammo": {}}
	HangarManager.save_mech_state(id_b)
	HangarManager.switch_mech(id_b)
	GlobalData.save_run()
	var before_active: String = GlobalData.hangar.active_hangar_mech_id
	var before_working: Dictionary = _snapshot_working()
	var before_berth: Dictionary = _berth_state(before_active)
	# Simulate fresh boot: wipe runtime then restore.
	GlobalData.weapons.part_damage = {"body": 1.0}
	GlobalData.weapons.chassis_id = "corrupt"
	SaveGameIO.restore_from_dict(_read_save_dict())
	_assert(GlobalData.hangar.active_hangar_mech_id == before_active, "E: active ID survives reload")
	_assert(str(GlobalData.weapons.chassis_id) == str(before_working.get("chassis", "")), "E: working chassis survives reload")
	_assert((GlobalData.weapons.part_damage as Dictionary) == (before_working.get("damage", {}) as Dictionary), "E: working damage survives reload")
	var after_berth: Dictionary = _berth_state(GlobalData.hangar.active_hangar_mech_id)
	_assert((after_berth.get("damage", {}) as Dictionary) == (before_berth.get("damage", {}) as Dictionary), "E: active berth survives reload")
	_assert(str(GlobalData.weapons.chassis_id) == str(after_berth.get("chassis", "")), "E: working chassis == active berth after reload")
	_assert((GlobalData.weapons.part_damage as Dictionary) == (after_berth.get("damage", {}) as Dictionary), "E: working damage == active berth after reload")


func _read_save_dict() -> Dictionary:
	var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	return data if data is Dictionary else {}
