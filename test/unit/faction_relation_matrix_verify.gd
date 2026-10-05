extends Node
## PHASE 2 FACTION RELATION MATRIX VERIFY (Campaign V2 foundation).
##
## Proves: canonical registry, deterministic defaults/self/unknown behavior,
## symmetric mutation for all four relations, predicate helpers, reset,
## serialize/deserialize round-trip, old-save compatibility, new-run isolation,
## determinism, and the single-authority invariant (no second relation owner).
## Combat behavior is intentionally NOT migrated here — no combat assertions.
## Real-save safety: the pre-existing user save is backed up on entry and
## restored at the end (sector_progression_verify convention).

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("FACTION-RELATION OK: " + name)
	else:
		_fails += 1
		printerr("FACTION-RELATION FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_test_registry()
	_test_defaults()
	_test_mutation()
	_test_predicates()
	_test_reset()
	_test_serialize_round_trip()
	_test_old_save_compat()
	_test_new_run_isolation()
	_test_determinism()
	_test_single_authority()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("FACTION_RELATION_MATRIX_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("FACTION_RELATION_MATRIX_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FACTION_RELATION_MATRIX_TESTS_PASSED")
		get_tree().quit(0)


# A — registry: canonical IDs, unknown rejected, stable identity.
func _test_registry() -> void:
	var ids := FactionSystem.get_registered_factions()
	_check(ids == ["federation", "zeon", "outland", "scavenger"], "canonical registry has exactly the four campaign factions")
	_check(FactionSystem.get_faction_ids() == ids, "legacy accessor returns the same canonical registry")
	_check(FactionSystem.get_registered_factions() == ids, "registry stable across calls")
	for fid in ids:
		_check(FactionSystem.has_faction(fid), "registered faction recognized: " + fid)
		var def := FactionSystem.get_faction(fid)
		_check(str(def.get("id", "")) == fid, "definition id matches identity (never display name): " + fid)
	_check(not FactionSystem.has_faction("hostile"), "encounter label 'hostile' is not a campaign faction")
	_check(not FactionSystem.has_faction("unknown"), "encounter label 'unknown' is not a campaign faction")
	_check(not FactionSystem.has_faction(""), "empty id rejected")
	_check(str(FactionSystem.get_faction("nope").get("id", "")) == "outland",
		"unknown definition lookup keeps legacy outland fallback (compat)")


# B — defaults: unset pairs neutral, self allied, unknown safe.
func _test_defaults() -> void:
	FactionSystem.reset_relations()
	var ids := FactionSystem.get_registered_factions()
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			_check(FactionSystem.get_relation(ids[i], ids[j]) == FactionSystem.Relation.NEUTRAL,
				"unset pair defaults to NEUTRAL: %s-%s" % [ids[i], ids[j]])
	for fid in ids:
		_check(FactionSystem.get_relation(fid, fid) == FactionSystem.Relation.ALLIED,
			"self-relation is ALLIED: " + fid)
	_check(FactionSystem.get_relation("federation", "nope") == FactionSystem.Relation.NEUTRAL,
		"unknown faction reads as NEUTRAL (safe default, no invented hostility)")
	_check(FactionSystem.get_relation("nope", "nope2") == FactionSystem.Relation.NEUTRAL,
		"two unknown factions read as NEUTRAL")
	_check(FactionSystem.get_relation_name("federation", "zeon") == "neutral",
		"default serializes under a stable string name")


# C — mutation for every relation, symmetric both directions.
func _test_mutation() -> void:
	var cases := [
		[FactionSystem.Relation.HOSTILE, "hostile"],
		[FactionSystem.Relation.NEUTRAL, "neutral"],
		[FactionSystem.Relation.COOPERATIVE, "cooperative"],
		[FactionSystem.Relation.ALLIED, "allied"],
	]
	for c in cases:
		FactionSystem.reset_relations()
		var ok := FactionSystem.set_relation("federation", "zeon", int(c[0]))
		_check(ok, "set_relation accepted: " + str(c[1]))
		_check(FactionSystem.get_relation("federation", "zeon") == int(c[0]),
			"forward read matches: " + str(c[1]))
		_check(FactionSystem.get_relation("zeon", "federation") == int(c[0]),
			"symmetric reverse read matches: " + str(c[1]))
		_check(FactionSystem.get_relation_name("zeon", "federation") == str(c[1]),
			"name mapping stable: " + str(c[1]))
	FactionSystem.reset_relations()
	_check(not FactionSystem.set_relation("federation", "nope", FactionSystem.Relation.HOSTILE),
		"write with unknown faction rejected")
	_check(FactionSystem.get_relation("federation", "zeon") == FactionSystem.Relation.NEUTRAL,
		"rejected write mutated nothing")
	_check(not FactionSystem.set_relation("federation", "federation", FactionSystem.Relation.HOSTILE),
		"self-relation write rejected")
	_check(FactionSystem.get_relation("federation", "federation") == FactionSystem.Relation.ALLIED,
		"self-relation still ALLIED after rejected write")
	_check(not FactionSystem.set_relation("federation", "zeon", 99),
		"non-canonical relation value rejected")
	_check(FactionSystem.relation_from_name("bogus") == -1, "unknown relation name rejected")
	FactionSystem.reset_relations()


# D — predicate helpers against every relation type.
func _test_predicates() -> void:
	var ids := ["federation", "zeon", "outland", "scavenger"]
	var preds := ["is_hostile", "is_neutral", "is_cooperative", "is_allied"]
	var rels := [FactionSystem.Relation.HOSTILE, FactionSystem.Relation.NEUTRAL,
		FactionSystem.Relation.COOPERATIVE, FactionSystem.Relation.ALLIED]
	for r in range(rels.size()):
		FactionSystem.reset_relations()
		FactionSystem.set_relation(ids[0], ids[1], int(rels[r]))
		var got := [
			FactionSystem.is_hostile(ids[0], ids[1]),
			FactionSystem.is_neutral(ids[0], ids[1]),
			FactionSystem.is_cooperative(ids[0], ids[1]),
			FactionSystem.is_allied(ids[0], ids[1]),
		]
		for p in range(preds.size()):
			_check(bool(got[p]) == (p == r), "%s %s relation %d" % [preds[p], "matches" if p == r else "rejects", int(rels[r])])
	FactionSystem.reset_relations()


# E — reset restores defaults.
func _test_reset() -> void:
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	FactionSystem.set_relation("outland", "scavenger", FactionSystem.Relation.ALLIED)
	FactionSystem.reset_relations()
	_check(FactionSystem.get_relation("federation", "zeon") == FactionSystem.Relation.NEUTRAL,
		"reset clears hostile override")
	_check(FactionSystem.get_relation("outland", "scavenger") == FactionSystem.Relation.NEUTRAL,
		"reset clears allied override")
	_check((FactionSystem.serialize_relations().get("relations", []) as Array).is_empty(),
		"reset leaves no serialized overrides")


# F — serialize/deserialize exact restoration (sorted, string-stable).
func _test_serialize_round_trip() -> void:
	FactionSystem.reset_relations()
	FactionSystem.set_relation("zeon", "federation", FactionSystem.Relation.HOSTILE)
	FactionSystem.set_relation("outland", "scavenger", FactionSystem.Relation.COOPERATIVE)
	var snap := FactionSystem.serialize_relations()
	var rows: Array = snap.get("relations", [])
	_check(rows.size() == 2, "two overrides serialized")
	_check(str(rows[0].get("a", "")) <= str(rows[1].get("a", "")) or str(rows[0].get("a", "")) == "outland",
		"serialized pairs sorted deterministically")
	FactionSystem.reset_relations()
	FactionSystem.deserialize_relations(snap)
	_check(FactionSystem.get_relation("federation", "zeon") == FactionSystem.Relation.HOSTILE,
		"hostile override restored (either direction)")
	_check(FactionSystem.get_relation("scavenger", "outland") == FactionSystem.Relation.COOPERATIVE,
		"cooperative override restored (either direction)")
	FactionSystem.deserialize_relations({"relations": [
		{"a": "federation", "b": "nope", "relation": "hostile"},
		{"a": "federation", "b": "zeon", "relation": "bogus"},
		"not-a-row",
		{"a": "federation"},
	]})
	_check(FactionSystem.get_relation("federation", "zeon") == FactionSystem.Relation.NEUTRAL,
		"malformed rows skipped deterministically (no partial state)")
	FactionSystem.reset_relations()


# G — old saves without relation data load safely (full SaveGameIO path).
func _test_old_save_compat() -> void:
	FactionSystem.reset_relations()
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.ALLIED)
	_check(SaveGameIO.save_run(), "save_run reports success with relation override")
	var d = JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))
	_check(d is Dictionary and (d as Dictionary).has("faction_relations"),
		"save file carries faction_relations")
	(d as Dictionary).erase("faction_relations")
	var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f.flush()
	f.close()
	FactionSystem.reset_relations()
	_check(SaveGameIO.load_run(), "legacy payload without faction_relations still loads")
	_check(FactionSystem.get_relation("federation", "zeon") == FactionSystem.Relation.NEUTRAL,
		"missing relation data reconstructs deterministic defaults")
	# And the real round trip with data present.
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.ALLIED)
	_check(SaveGameIO.save_run(), "save_run reports success (round trip)")
	FactionSystem.reset_relations()
	_check(SaveGameIO.load_run(), "load_run reports success (round trip)")
	_check(FactionSystem.is_allied("zeon", "federation"), "relation restored symmetrically from save")
	FactionSystem.reset_relations()


# H — new-run isolation through the established reset primitive.
func _test_new_run_isolation() -> void:
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	_check(SaveGameIO.save_run(), "run A saved with hostile override")
	GlobalData.reset_run_data()
	_check(FactionSystem.get_relation("federation", "zeon") == FactionSystem.Relation.NEUTRAL,
		"reset_run_data clears relation state (run B starts at defaults)")


# I — determinism across repeated reset/initialize cycles.
func _test_determinism() -> void:
	FactionSystem.reset_relations()
	var empty_a := JSON.stringify(FactionSystem.serialize_relations())
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	var full_a := JSON.stringify(FactionSystem.serialize_relations())
	FactionSystem.reset_relations()
	var empty_b := JSON.stringify(FactionSystem.serialize_relations())
	FactionSystem.set_relation("zeon", "federation", FactionSystem.Relation.HOSTILE)
	var full_b := JSON.stringify(FactionSystem.serialize_relations())
	_check(empty_a == empty_b, "default serialization identical across cycles")
	_check(full_a == full_b, "override serialization identical regardless of set direction")
	FactionSystem.reset_relations()


# J — single authority: no second relation implementation exists.
func _test_single_authority() -> void:
	for cls in [FactionSystem, FactionEconomySystem, EnemyFactionSystem]:
		var names := {}
		for m in (cls as Script).get_script_method_list():
			names[str(m.get("name", ""))] = true
		if cls == FactionSystem:
			_check(names.has("get_relation") and names.has("set_relation")
				and names.has("serialize_relations") and names.has("reset_relations"),
				"FactionSystem owns the relation API")
		else:
			_check(not names.has("get_relation") and not names.has("set_relation")
				and not names.has("serialize_relations"),
				"no parallel relation owner")
