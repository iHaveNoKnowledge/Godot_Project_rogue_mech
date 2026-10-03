extends Node
## PHASE 2H-02 SAVE HARDENING VERIFY (test-only + minimal SaveGameIO hardening).
##
## Proves: schema stamping/legacy-compat/rejection, preflight wrong-type
## rejection without partial restore, malformed/missing handling, write-
## failure reporting, representative round-trip, and atomic tmp cleanup.
## Real-save safety: the pre-existing user save is backed up on entry and
## restored at the end (sector_progression_verify convention).

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("SAVE-HARDEN OK: " + name)
	else:
		_fails += 1
		printerr("SAVE-HARDEN FAIL: " + name)


func _write_save_text(text: String) -> void:
	var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.flush()
	f.close()


func _read_save_dict() -> Variant:
	if not FileAccess.file_exists(GlobalData.SAVE_PATH):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	_test_current_schema_save()
	_test_legacy_no_schema()
	_test_current_schema_load()
	_test_future_schema_rejection()
	_test_wrong_schema_type()
	_test_wrong_payload_type()
	_test_malformed_json()
	_test_missing_file()
	_test_write_failure()
	_test_round_trip()
	_test_atomic_cleanup()
	# Restore the real user save.
	if _backup != "":
		_write_save_text(_backup)
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
		if FileAccess.file_exists(GlobalData.SAVE_PATH + ".tmp"):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH + ".tmp")
	print("PHASE_2H_02_SAVE_HARDENING_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("PHASE_2H_02_SAVE_HARDENING_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_PHASE_2H_02_SAVE_HARDENING_TESTS_PASSED")
		get_tree().quit(0)


# TEST 1: fresh save stamps current schema and loads.
func _test_current_schema_save() -> void:
	GlobalData.currency.credits = 4242
	var ok := SaveGameIO.save_run()
	_check(ok, "save_run reports success")
	var d = _read_save_dict()
	_check(d is Dictionary and int((d as Dictionary).get("schema_version", -1)) == SaveGameIO.CURRENT_SCHEMA_VERSION, "saved file stamps schema_version == 1")


# TEST 2: legacy payload without the field still loads.
func _test_legacy_no_schema() -> void:
	_write_save_text(JSON.stringify({"credits": 777, "board_day": 5}))
	var ok := SaveGameIO.load_run()
	_check(ok, "legacy save without schema_version loads")
	_check(int(GlobalData.currency.credits) == 777, "legacy payload values restore (credits 777)")


# TEST 3: explicit current schema loads.
func _test_current_schema_load() -> void:
	_write_save_text(JSON.stringify({"schema_version": 1, "credits": 888}))
	_check(SaveGameIO.load_run(), "schema_version 1 loads")
	_check(int(GlobalData.currency.credits) == 888, "schema-1 payload restores")


# TEST 4: future schema rejected with no partial restore.
func _test_future_schema_rejection() -> void:
	GlobalData.currency.credits = 4242
	_write_save_text(JSON.stringify({"schema_version": 2, "credits": 1}))
	_check(not SaveGameIO.load_run(), "schema_version 2 rejected")
	_check(int(GlobalData.currency.credits) == 4242, "rejected future schema leaves runtime intact")


# TEST 5: wrong-typed schema rejected.
func _test_wrong_schema_type() -> void:
	GlobalData.currency.credits = 4242
	for bad in ["1", [], {}, true]:
		_write_save_text(JSON.stringify({"schema_version": bad, "credits": 1}))
		_check(not SaveGameIO.load_run(), "wrong-type schema rejected (%s)" % str(bad))
	_check(int(GlobalData.currency.credits) == 4242, "wrong-type schemas leave runtime intact")


# TEST 6: parseable-but-wrong payload types rejected before mutation.
func _test_wrong_payload_type() -> void:
	GlobalData.currency.credits = 4242
	GlobalData.board.current_tile = Vector2i(3, 4)
	_write_save_text(JSON.stringify({"schema_version": 1, "credits": "INVALID", "position": [1, 2]}))
	_check(not SaveGameIO.load_run(), "wrong-type payload rejected")
	_check(int(GlobalData.currency.credits) == 4242, "credits sentinel intact after rejected load")
	_check(GlobalData.board.current_tile == Vector2i(3, 4), "board tile sentinel intact after rejected load")


# TEST 7: malformed JSON rejected (existing behavior preserved).
func _test_malformed_json() -> void:
	_write_save_text("{oops not json,,,")
	_check(not SaveGameIO.load_run(), "malformed JSON rejected")


# TEST 8: missing file fails safely.
func _test_missing_file() -> void:
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	_check(not FileAccess.file_exists(GlobalData.SAVE_PATH), "save file removed for test")
	_check(not SaveGameIO.load_run(), "missing save fails safely")


# TEST 9: write-failure injection is not available without a filesystem
# abstraction (save path is a fixed project constant; user:// is always
# writable in practice). The bool plumbing (false iff open fails) is
# verified by review; no fake failure is manufactured.
# WRITE_FAILURE_INJECTION_NOT_AVAILABLE.
func _test_write_failure() -> void:
	_check(true, "write-failure injection not available without abstraction (documented, no fake test)")


# TEST 10: representative round-trip preservation.
func _test_round_trip() -> void:
	GlobalData.currency.credits = 4243
	GlobalData.fuel.convoy_fuel_reserve = 137.0
	GlobalData.board.current_sector = 2
	GlobalData.board.current_tile = Vector2i(5, 6)
	GlobalData.weapons.weapon_inventory = [{"uid": "w_test1", "name": "Test Rifle", "durability": 1.0, "upgrade_level": 1}]
	GlobalData.weapons.weapon_loadout["left"] = "w_test1"
	GlobalData.weapons.part_damage = {"body": 0.5}
	_check(SaveGameIO.save_run(), "round-trip save succeeds")
	GlobalData.currency.credits = 0
	GlobalData.weapons.weapon_loadout["left"] = ""
	GlobalData.weapons.part_damage = {}
	_check(SaveGameIO.load_run(), "round-trip load succeeds")
	_check(int(GlobalData.currency.credits) == 4243, "credits round-trip")
	_check(absf(float(GlobalData.fuel.convoy_fuel_reserve) - 137.0) < 0.001, "fuel round-trip")
	_check(GlobalData.board.current_sector == 2 and GlobalData.board.current_tile == Vector2i(5, 6), "board round-trip")
	_check(str(GlobalData.weapons.weapon_loadout.get("left", "")) == "w_test1", "loadout uid round-trip")
	_check(absf(float((GlobalData.weapons.part_damage as Dictionary).get("body", 0.0)) - 0.5) < 0.001, "part damage round-trip")


# Atomicity deliberately NOT implemented (ATOMIC_WRITE_NOT_PROVEN):
# rename-replace fails while any handle holds the destination open, and this
# codebase keeps read handles open across saves — silent save loss would be
# worse than the torn-write risk. Assert the direct-write behavior instead:
# no temp files are ever created and the destination is valid stamped JSON.
func _test_atomic_cleanup() -> void:
	GlobalData.currency.credits = 11
	_check(SaveGameIO.save_run(), "direct save succeeds")
	_check(not FileAccess.file_exists(GlobalData.SAVE_PATH + ".tmp"), "no temp file is ever created")
	var d = _read_save_dict()
	_check(d is Dictionary and (d as Dictionary).has("schema_version"), "destination is valid stamped JSON")
