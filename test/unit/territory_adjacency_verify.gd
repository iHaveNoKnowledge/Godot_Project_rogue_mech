extends Node
## TERRITORY ADJACENCY VERIFY (Phase C5-A1).
##
## Proves:
## 1. Registering two valid Territories and establishing symmetric adjacency.
## 2. Rejecting self-adjacency.
## 3. Rejecting unknown Territory IDs.
## 4. Idempotent duplicate registration.
## 5. Returned neighbor arrays cannot mutate internal state (defensive copy).
## 6. Detecting duplicate, dangling, self-referencing, and asymmetric data in validate().
## 7. Scenario validation of valid and invalid neighbor declarations.
## 8. Initialization with all Territory identities registered before adjacency application.
## 9. Serialization round-trip preservation.
## 10. Legacy Territory data without neighbors loading as an empty neighbor list.
## 11. Existing ownership and Node membership behavior remaining unchanged.

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("ADJACENCY OK: " + name)
	else:
		_fails += 1
		printerr("ADJACENCY FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()

	_test_basic_symmetric_adjacency()
	_test_rejection_rules()
	_test_idempotency()
	_test_defensive_copies()
	_test_mutual_adjacency_query()
	_test_validation_detection()
	_test_deserialization_malformed_preservation()
	_test_scenario_validation()
	_test_scenario_initialization_ordering()
	_test_serialization_round_trip()
	_test_legacy_save_loading()
	_test_ownership_and_members_untouched()

	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)

	print("TERRITORY_ADJACENCY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("TERRITORY_ADJACENCY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_TERRITORY_ADJACENCY_TESTS_PASSED")
		get_tree().quit(0)


func _seed_sample_nodes() -> void:
	CampaignNodeRegistry.clear()
	CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "city", "node_city_1")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "safehouse", "node_safe_1")
	CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "fuel_depot", "node_depot_1")


## 1. Registering two valid Territories and establishing symmetric adjacency.
func _test_basic_symmetric_adjacency() -> void:
	CampaignTerritory.clear()
	_seed_sample_nodes()
	CampaignTerritory.register_territory("terr_a", ["node_city_1"])
	CampaignTerritory.register_territory("terr_b", ["node_safe_1"])

	_check(not CampaignTerritory.are_adjacent("terr_a", "terr_b"), "initially not adjacent")
	_check(CampaignTerritory.get_neighbors("terr_a").is_empty(), "terr_a has no neighbors initially")
	_check(CampaignTerritory.get_neighbors("terr_b").is_empty(), "terr_b has no neighbors initially")

	var ok: bool = CampaignTerritory.register_adjacency("terr_a", "terr_b")
	_check(ok, "register_adjacency returns true")
	_check(CampaignTerritory.are_adjacent("terr_a", "terr_b"), "terr_a is adjacent to terr_b")
	_check(CampaignTerritory.are_adjacent("terr_b", "terr_a"), "terr_b is adjacent to terr_a (symmetric)")
	_check(CampaignTerritory.get_neighbors("terr_a") == ["terr_b"], "terr_a neighbor list has terr_b")
	_check(CampaignTerritory.get_neighbors("terr_b") == ["terr_a"], "terr_b neighbor list has terr_a")
	_check(CampaignTerritory.validate().is_empty(), "healthy symmetric adjacency validates cleanly")


## 2 & 3. Rejecting self-adjacency and unknown Territory IDs.
func _test_rejection_rules() -> void:
	CampaignTerritory.clear()
	_seed_sample_nodes()
	CampaignTerritory.register_territory("terr_a", ["node_city_1"])
	CampaignTerritory.register_territory("terr_b", ["node_safe_1"])

	_check(not CampaignTerritory.register_adjacency("terr_a", "terr_a"), "self-adjacency rejected")
	_check(not CampaignTerritory.are_adjacent("terr_a", "terr_a"), "self is not adjacent")
	_check(CampaignTerritory.get_neighbors("terr_a").is_empty(), "self-adjacency changed nothing")

	_check(not CampaignTerritory.register_adjacency("terr_a", "terr_unknown"), "unknown territory_b rejected")
	_check(not CampaignTerritory.register_adjacency("terr_unknown", "terr_a"), "unknown territory_a rejected")
	_check(not CampaignTerritory.register_adjacency("terr_unknown_1", "terr_unknown_2"), "both unknown rejected")
	_check(not CampaignTerritory.register_adjacency("", "terr_a"), "empty territory_a rejected")
	_check(not CampaignTerritory.register_adjacency("terr_a", ""), "empty territory_b rejected")
	_check(CampaignTerritory.get_neighbors("terr_a").is_empty(), "rejected calls changed nothing")


## 4. Idempotent duplicate registration.
func _test_idempotency() -> void:
	CampaignTerritory.clear()
	_seed_sample_nodes()
	CampaignTerritory.register_territory("terr_a", ["node_city_1"])
	CampaignTerritory.register_territory("terr_b", ["node_safe_1"])

	_check(CampaignTerritory.register_adjacency("terr_a", "terr_b"), "first call succeeds")
	_check(CampaignTerritory.register_adjacency("terr_a", "terr_b"), "repeat call is idempotent (returns true)")
	_check(CampaignTerritory.register_adjacency("terr_b", "terr_a"), "reverse call is idempotent (returns true)")
	_check(CampaignTerritory.get_neighbors("terr_a") == ["terr_b"], "no duplicates in terr_a")
	_check(CampaignTerritory.get_neighbors("terr_b") == ["terr_a"], "no duplicates in terr_b")


## 5. Returned neighbor arrays cannot mutate internal state.
func _test_defensive_copies() -> void:
	CampaignTerritory.clear()
	_seed_sample_nodes()
	CampaignTerritory.register_territory("terr_a", ["node_city_1"])
	CampaignTerritory.register_territory("terr_b", ["node_safe_1"])
	CampaignTerritory.register_adjacency("terr_a", "terr_b")

	var n := CampaignTerritory.get_neighbors("terr_a")
	n.append("terr_injected_evil")
	_check(CampaignTerritory.get_neighbors("terr_a") == ["terr_b"], "external mutation does not affect internal state")
	_check(not CampaignTerritory.are_adjacent("terr_a", "terr_injected_evil"), "injected id is not adjacent")


## Required Fix A: Mutual Adjacency Query checks
func _test_mutual_adjacency_query() -> void:
	CampaignTerritory.clear()
	_seed_sample_nodes()
	CampaignTerritory.register_territory("terr_a", ["node_city_1"])
	CampaignTerritory.register_territory("terr_b", ["node_safe_1"])
	CampaignTerritory.register_territory("terr_c", ["node_depot_1"])

	# Symmetric valid adjacency -> true in both argument orders
	CampaignTerritory.register_adjacency("terr_a", "terr_b")
	_check(CampaignTerritory.are_adjacent("terr_a", "terr_b"), "valid adjacency true (a, b)")
	_check(CampaignTerritory.are_adjacent("terr_b", "terr_a"), "valid adjacency true (b, a)")

	# One-sided relationship -> false in both argument orders
	CampaignTerritory.deserialize({"territories": [
		{"id": "terr_a", "control": "uncontrolled", "controller": "", "contesting": [], "members": ["node_city_1"], "neighbors": ["terr_b"]},
		{"id": "terr_b", "control": "uncontrolled", "controller": "", "contesting": [], "members": ["node_safe_1"], "neighbors": []}
	]})
	_check(not CampaignTerritory.are_adjacent("terr_a", "terr_b"), "one-sided relationship false (a, b)")
	_check(not CampaignTerritory.are_adjacent("terr_b", "terr_a"), "one-sided relationship false (b, a)")

	# Missing territory, empty IDs, self-adjacency -> false
	_check(not CampaignTerritory.are_adjacent("", "terr_a"), "empty ID a is false")
	_check(not CampaignTerritory.are_adjacent("terr_a", ""), "empty ID b is false")
	_check(not CampaignTerritory.are_adjacent("terr_a", "terr_a"), "self-adjacency is false")
	_check(not CampaignTerritory.are_adjacent("terr_a", "terr_unknown"), "unknown territory b is false")
	_check(not CampaignTerritory.are_adjacent("terr_unknown", "terr_a"), "unknown territory a is false")

	# Missing/malformed neighbor fields -> no runtime error and no false positive
	CampaignTerritory.deserialize({"territories": [
		{"id": "terr_a", "control": "uncontrolled", "controller": "", "contesting": [], "members": ["node_city_1"], "neighbors": 12345},
		{"id": "terr_b", "control": "uncontrolled", "controller": "", "contesting": [], "members": ["node_safe_1"]}
	]})
	_check(not CampaignTerritory.are_adjacent("terr_a", "terr_b"), "malformed neighbor field is false (a, b)")
	_check(not CampaignTerritory.are_adjacent("terr_b", "terr_a"), "malformed neighbor field is false (b, a)")
	_check(CampaignTerritory.get_neighbors("terr_a").is_empty(), "get_neighbors returns empty array on malformed non-array neighbor")


## Required Fix B: Preserve Serialized Neighbor Data During Deserialization
func _test_deserialization_malformed_preservation() -> void:
	CampaignTerritory.clear()
	_seed_sample_nodes()

	# 1. Asymmetric known adjacency: A lists B, B is empty
	CampaignTerritory.deserialize({"territories": [
		{"id": "terr_a", "control": "uncontrolled", "controller": "", "contesting": [], "members": ["node_city_1"], "neighbors": ["terr_b"]},
		{"id": "terr_b", "control": "uncontrolled", "controller": "", "contesting": [], "members": ["node_safe_1"], "neighbors": []}
	]})
	_check(CampaignTerritory.get_neighbors("terr_a") == ["terr_b"], "deserialization preserves terr_a neighbor B")
	_check(CampaignTerritory.get_neighbors("terr_b").is_empty(), "deserialization does NOT synthesize reverse link on B")
	_check(not CampaignTerritory.are_adjacent("terr_a", "terr_b"), "are_adjacent false on asymmetric deserialized state (a, b)")
	_check(not CampaignTerritory.are_adjacent("terr_b", "terr_a"), "are_adjacent false on asymmetric deserialized state (b, a)")
	var probs := CampaignTerritory.validate()
	_check(probs.any(func(p: String): return p.contains("asymmetric territory adjacency between terr_a and terr_b")), "validate detects asymmetric adjacency")

	# 2. Duplicate known neighbor: A lists B twice
	CampaignTerritory.deserialize({"territories": [
		{"id": "terr_a", "control": "uncontrolled", "controller": "", "contesting": [], "members": ["node_city_1"], "neighbors": ["terr_b", "terr_b"]},
		{"id": "terr_b", "control": "uncontrolled", "controller": "", "contesting": [], "members": ["node_safe_1"], "neighbors": ["terr_a"]}
	]})
	_check(CampaignTerritory.get_neighbors("terr_a") == ["terr_b", "terr_b"], "deserialization preserves duplicate known neighbors")
	probs = CampaignTerritory.validate()
	_check(probs.any(func(p: String): return p.contains("duplicate neighbor terr_b")), "validate detects duplicate known neighbor")

	# 3. Non-String neighbor: A has number and Dictionary
	CampaignTerritory.deserialize({"territories": [
		{"id": "terr_a", "control": "uncontrolled", "controller": "", "contesting": [], "members": ["node_city_1"], "neighbors": [123, {"bad": true}]}
	]})
	_check(CampaignTerritory.get_neighbors("terr_a").size() == 2, "deserialization preserves non-string neighbor items")
	probs = CampaignTerritory.validate()
	_check(probs.any(func(p: String): return p.contains("non-string neighbor")), "validate detects non-string neighbor without crash")

	# 4. Non-Array neighbor: A has integer neighbor field
	CampaignTerritory.deserialize({"territories": [
		{"id": "terr_a", "control": "uncontrolled", "controller": "", "contesting": [], "members": ["node_city_1"], "neighbors": 999}
	]})
	probs = CampaignTerritory.validate()
	_check(probs.any(func(p: String): return p.contains("non-array neighbors")), "validate detects non-array neighbors")


## 6. Detecting duplicate, dangling, self-referencing, and asymmetric data in validate().
func _test_validation_detection() -> void:
	CampaignTerritory.clear()
	_seed_sample_nodes()
	CampaignTerritory.register_territory("terr_a", ["node_city_1"])
	CampaignTerritory.register_territory("terr_b", ["node_safe_1"])

	# Self-referencing error
	CampaignTerritory.deserialize({"territories": [
		{"id": "terr_a", "control": "uncontrolled", "controller": "", "contesting": [], "members": ["node_city_1"], "neighbors": ["terr_a"]}
	]})
	var probs := CampaignTerritory.validate()
	_check(probs.any(func(p: String): return p.contains("lists itself as neighbor")), "detects self-referencing neighbor")

	# Unknown / dangling neighbor
	CampaignTerritory.deserialize({"territories": [
		{"id": "terr_a", "control": "uncontrolled", "controller": "", "contesting": [], "members": ["node_city_1"], "neighbors": ["terr_nonexistent"]}
	]})
	probs = CampaignTerritory.validate()
	_check(probs.any(func(p: String): return p.contains("references unknown neighbor")), "detects unknown neighbor")

	# Duplicate neighbor
	CampaignTerritory.deserialize({"territories": [
		{"id": "terr_a", "control": "uncontrolled", "controller": "", "contesting": [], "members": ["node_city_1"], "neighbors": ["terr_nonexistent", "terr_nonexistent"]}
	]})
	probs = CampaignTerritory.validate()
	_check(probs.any(func(p: String): return p.contains("duplicate neighbor")), "detects duplicate neighbor")

	# Clean state validation
	CampaignTerritory.clear()
	CampaignTerritory.register_territory("terr_a", ["node_city_1"])
	CampaignTerritory.register_territory("terr_b", ["node_safe_1"])
	CampaignTerritory.register_adjacency("terr_a", "terr_b")
	probs = CampaignTerritory.validate()
	_check(probs.is_empty(), "healthy adjacency has no problems")


## 7. Scenario validation of valid and invalid neighbor declarations.
func _test_scenario_validation() -> void:
	var scn: Resource = ScenarioDefinition.new()
	scn.set("scenario_id", "test_adj_scn")
	scn.set("display_name", "Test Adjacency Scenario")
	scn.set("description", "Valid test scenario description.")
	scn.set("faction_setup", ["federation", "zeon"])
	scn.set("initial_node_specs", [
		{"id": "n1", "tile": Vector2i(1, 1), "node_type": "city", "sector": 1},
		{"id": "n2", "tile": Vector2i(2, 2), "node_type": "safehouse", "sector": 1}
	])

	# Valid symmetric neighbors
	scn.set("initial_territory_specs", [
		{"id": "t1", "members": ["n1"], "controller": "federation", "neighbors": ["t2"]},
		{"id": "t2", "members": ["n2"], "controller": "zeon", "neighbors": ["t1"]}
	])
	var res := ScenarioSchemaValidator.validate_scenario(scn)
	_check(res.valid, "valid scenario with symmetric neighbors passes")

	# Self-adjacency error
	scn.set("initial_territory_specs", [
		{"id": "t1", "members": ["n1"], "controller": "federation", "neighbors": ["t1"]}
	])
	res = ScenarioSchemaValidator.validate_scenario(scn)
	_check(not res.valid, "scenario with self-adjacency rejected")
	_check((res.errors as Array).any(func(e): return e.get("code") == "SELF_ADJACENT_TERRITORY"), "reports SELF_ADJACENT_TERRITORY")

	# Unknown neighbor error
	scn.set("initial_territory_specs", [
		{"id": "t1", "members": ["n1"], "controller": "federation", "neighbors": ["t_ghost"]}
	])
	res = ScenarioSchemaValidator.validate_scenario(scn)
	_check(not res.valid, "scenario with unknown neighbor rejected")
	_check((res.errors as Array).any(func(e): return e.get("code") == "UNKNOWN_NEIGHBOR_TERRITORY"), "reports UNKNOWN_NEIGHBOR_TERRITORY")

	# Duplicate neighbor error
	scn.set("initial_territory_specs", [
		{"id": "t1", "members": ["n1"], "controller": "federation", "neighbors": ["t2", "t2"]},
		{"id": "t2", "members": ["n2"], "controller": "zeon", "neighbors": ["t1"]}
	])
	res = ScenarioSchemaValidator.validate_scenario(scn)
	_check(not res.valid, "scenario with duplicate neighbor rejected")
	_check((res.errors as Array).any(func(e): return e.get("code") == "DUPLICATE_TERRITORY_NEIGHBOR"), "reports DUPLICATE_TERRITORY_NEIGHBOR")

	# Asymmetric neighbor error
	scn.set("initial_territory_specs", [
		{"id": "t1", "members": ["n1"], "controller": "federation", "neighbors": ["t2"]},
		{"id": "t2", "members": ["n2"], "controller": "zeon", "neighbors": []}
	])
	res = ScenarioSchemaValidator.validate_scenario(scn)
	_check(not res.valid, "scenario with asymmetric neighbors rejected")
	_check((res.errors as Array).any(func(e): return e.get("code") == "ASYMMETRIC_TERRITORY_ADJACENCY"), "reports ASYMMETRIC_TERRITORY_ADJACENCY")


## 8. Initialization with all Territory identities registered before adjacency application.
func _test_scenario_initialization_ordering() -> void:
	CampaignTerritory.clear()
	CampaignNodeRegistry.clear()
	var scn: Resource = ScenarioDefinition.new()
	scn.set("scenario_id", "test_order_scn")
	scn.set("display_name", "Test Order Scenario")
	scn.set("description", "Valid order scenario description.")
	scn.set("faction_setup", ["federation", "zeon"])
	scn.set("initial_node_specs", [
		{"id": "n1", "tile": Vector2i(1, 1), "node_type": "city", "sector": 1},
		{"id": "n2", "tile": Vector2i(2, 2), "node_type": "safehouse", "sector": 1}
	])
	# t1 references t2 (which appears second in the list): forward reference!
	scn.set("initial_territory_specs", [
		{"id": "t1", "members": ["n1"], "controller": "federation", "neighbors": ["t2"]},
		{"id": "t2", "members": ["n2"], "controller": "zeon", "neighbors": ["t1"]}
	])
	var init_res := CampaignScenarioInitializer.apply_scenario(scn)
	_check(init_res.ok and init_res.applied, "apply_scenario succeeded")
	_check(CampaignTerritory.has_territory("t1") and CampaignTerritory.has_territory("t2"), "both territories registered")
	_check(CampaignTerritory.are_adjacent("t1", "t2"), "forward-referenced adjacency applied successfully")
	_check(CampaignTerritory.are_adjacent("t2", "t1"), "reverse adjacency confirmed")


## 9. Serialization round-trip preservation.
func _test_serialization_round_trip() -> void:
	CampaignTerritory.clear()
	_seed_sample_nodes()
	CampaignTerritory.register_territory("terr_a", ["node_city_1"])
	CampaignTerritory.register_territory("terr_b", ["node_safe_1"])
	CampaignTerritory.register_territory("terr_c", ["node_depot_1"])
	CampaignTerritory.set_controlled("terr_a", "federation")
	CampaignTerritory.set_controlled("terr_b", "zeon")
	CampaignTerritory.register_adjacency("terr_a", "terr_b")
	CampaignTerritory.register_adjacency("terr_b", "terr_c")

	var snap_1 := JSON.stringify(CampaignTerritory.serialize())
	CampaignTerritory.clear()
	CampaignTerritory.deserialize(JSON.parse_string(snap_1))
	var snap_2 := JSON.stringify(CampaignTerritory.serialize())

	_check(snap_1 == snap_2, "serialization round-trip matches bit-for-bit")
	_check(CampaignTerritory.are_adjacent("terr_a", "terr_b"), "adjacency a-b restored")
	_check(CampaignTerritory.are_adjacent("terr_b", "terr_c"), "adjacency b-c restored")
	_check(not CampaignTerritory.are_adjacent("terr_a", "terr_c"), "non-adjacent a-c preserved")
	_check(CampaignTerritory.get_neighbors("terr_b") == ["terr_a", "terr_c"], "sorted neighbors restored")


## 10. Legacy Territory data without neighbors loading as an empty neighbor list.
func _test_legacy_save_loading() -> void:
	CampaignTerritory.clear()
	_seed_sample_nodes()
	var legacy_payload = {
		"territories": [
			{
				"id": "terr_legacy_1",
				"control": "controlled",
				"controller": "federation",
				"contesting": [],
				"members": ["node_city_1"]
				# Notice: "neighbors" key completely missing!
			},
			{
				"id": "terr_legacy_2",
				"control": "controlled",
				"controller": "zeon",
				"contesting": [],
				"members": ["node_safe_1"]
				# Missing "neighbors"
			}
		]
	}
	CampaignTerritory.deserialize(legacy_payload)
	_check(CampaignTerritory.has_territory("terr_legacy_1"), "legacy territory 1 loaded")
	_check(CampaignTerritory.has_territory("terr_legacy_2"), "legacy territory 2 loaded")
	_check(CampaignTerritory.get_neighbors("terr_legacy_1") == [], "legacy territory 1 defaults to empty neighbors")
	_check(CampaignTerritory.get_neighbors("terr_legacy_2") == [], "legacy territory 2 defaults to empty neighbors")
	_check(not CampaignTerritory.are_adjacent("terr_legacy_1", "terr_legacy_2"), "legacy territories not adjacent")
	_check(CampaignTerritory.validate().is_empty(), "legacy territories validate cleanly")


## 11. Existing ownership and Node membership behavior remaining unchanged.
func _test_ownership_and_members_untouched() -> void:
	CampaignTerritory.clear()
	_seed_sample_nodes()
	CampaignTerritory.register_territory("terr_a", ["node_city_1", "node_safe_1"])
	CampaignTerritory.register_territory("terr_b", ["node_depot_1"])
	CampaignTerritory.set_controlled("terr_a", "federation")
	CampaignTerritory.set_contested("terr_b", ["zeon", "outland"])

	CampaignTerritory.register_adjacency("terr_a", "terr_b")

	_check(CampaignTerritory.is_controlled("terr_a"), "terr_a is controlled")
	_check(CampaignTerritory.get_controller("terr_a") == "federation", "controller federation preserved")
	_check(CampaignTerritory.is_contested("terr_b"), "terr_b is contested")
	_check(CampaignTerritory.get_contesting("terr_b") == ["outland", "zeon"], "contest list preserved")
	_check(CampaignTerritory.get_members("terr_a") == ["node_city_1", "node_safe_1"], "members preserved")
	_check(CampaignTerritory.get_territories_for_node("node_city_1").size() == 1, "get_territories_for_node works unchanged")
