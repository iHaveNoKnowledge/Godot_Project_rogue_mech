extends Node
## CAMPAIGN C5-A TERRITORY SCHEMA VERIFY (Phase C5-A, yield/category slice).
##
## Proves:
## 1. New territories default to unclassified with zero income.
## 2. set_yield stores a valid category and non-negative incomes; get_yield returns them.
## 3. set_yield is atomic: unknown territory, unknown category, negative income,
##    and income on an unclassified territory are rejected without mutation.
## 4. validate() detects injected invalid yield data.
## 5. Scenario validation accepts valid yield declarations and reports bad ones.
## 6. Scenario initialization applies declared yields to the registry.

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("C5A_SCHEMA OK: " + name)
	else:
		_fails += 1
		printerr("C5A_SCHEMA FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()

	_test_defaults()
	_test_set_yield_valid()
	_test_set_yield_rejections_are_atomic()
	_test_validate_detects_injected_bad_yield()
	_test_scenario_validation()
	_test_scenario_initialization_applies_yield()

	CampaignTerritory.clear()
	CampaignNodeRegistry.clear()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)

	print("CAMPAIGN_C5_TERRITORY_SCHEMA_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_C5_TERRITORY_SCHEMA_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CAMPAIGN_C5_TERRITORY_SCHEMA_TESTS_PASSED")
		get_tree().quit(0)


func _seed_nodes() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "city", "node_c5_city")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "safehouse", "node_c5_safe")


func _test_defaults() -> void:
	_seed_nodes()
	CampaignTerritory.register_territory("terr_c5_default", ["node_c5_city"])
	var y := CampaignTerritory.get_yield("terr_c5_default")
	_check(y.get("category", "x") == "", "new territory defaults to unclassified category")
	_check(int(y.get("income_credits", -1)) == 0, "new territory defaults to zero credit income")
	_check(int(y.get("income_scrap", -1)) == 0, "new territory defaults to zero scrap income")
	_check(CampaignTerritory.get_yield("terr_c5_unknown").is_empty(), "get_yield on unknown id returns empty dictionary")
	_check(CampaignTerritory.validate().is_empty(), "default territory validates cleanly")


func _test_set_yield_valid() -> void:
	_seed_nodes()
	CampaignTerritory.register_territory("terr_c5_yield", ["node_c5_city"])
	_check(CampaignTerritory.set_yield("terr_c5_yield", "industrial", 40, 5), "valid set_yield accepted")
	var y := CampaignTerritory.get_yield("terr_c5_yield")
	_check(y.get("category") == "industrial", "category stored")
	_check(int(y.get("income_credits")) == 40, "credit income stored")
	_check(int(y.get("income_scrap")) == 5, "scrap income stored")
	_check(CampaignTerritory.set_yield("terr_c5_yield", "", 0, 0), "unclassified zero-income accepted")
	_check(CampaignTerritory.get_yield("terr_c5_yield").get("category") == "", "unclassified category stored")
	for cat in ["commercial", "residential", "wasteland"]:
		_check(CampaignTerritory.set_yield("terr_c5_yield", cat, 1, 0), "category %s accepted" % cat)
	_check(CampaignTerritory.validate().is_empty(), "valid yields validate cleanly")


func _test_set_yield_rejections_are_atomic() -> void:
	_seed_nodes()
	CampaignTerritory.register_territory("terr_c5_atomic", ["node_c5_city"])
	CampaignTerritory.set_yield("terr_c5_atomic", "commercial", 25, 3)
	var before := CampaignTerritory.get_yield("terr_c5_atomic")

	_check(not CampaignTerritory.set_yield("terr_c5_ghost", "industrial", 1, 1), "unknown territory rejected")
	_check(not CampaignTerritory.set_yield("terr_c5_atomic", "mystery", 1, 1), "unknown category rejected")
	_check(not CampaignTerritory.set_yield("terr_c5_atomic", "industrial", -1, 0), "negative credit income rejected")
	_check(not CampaignTerritory.set_yield("terr_c5_atomic", "industrial", 0, -1), "negative scrap income rejected")
	_check(not CampaignTerritory.set_yield("terr_c5_atomic", "", 10, 0), "income on unclassified territory rejected")
	_check(CampaignTerritory.get_yield("terr_c5_atomic") == before, "rejected calls leave yield unchanged")


func _test_validate_detects_injected_bad_yield() -> void:
	_seed_nodes()
	CampaignTerritory.register_territory("terr_c5_bad", ["node_c5_city"])
	CampaignTerritory._territories["terr_c5_bad"]["category"] = "mystery"
	var probs := CampaignTerritory.validate()
	_check(probs.any(func(p: String): return p.contains("unknown category mystery")), "validate detects unknown category")

	CampaignTerritory._territories["terr_c5_bad"]["category"] = "industrial"
	CampaignTerritory._territories["terr_c5_bad"]["income_credits"] = -5
	probs = CampaignTerritory.validate()
	_check(probs.any(func(p: String): return p.contains("negative income")), "validate detects negative income")

	CampaignTerritory._territories["terr_c5_bad"]["category"] = ""
	CampaignTerritory._territories["terr_c5_bad"]["income_credits"] = 7
	probs = CampaignTerritory.validate()
	_check(probs.any(func(p: String): return p.contains("income but no category")), "validate detects income without category")
	CampaignTerritory.clear()


func _test_scenario_validation() -> void:
	_seed_nodes()
	var scn: Resource = ScenarioDefinition.new()
	scn.set("scenario_id", "test_c5_yield_scn")
	scn.set("display_name", "Test C5 Yield Scenario")
	scn.set("description", "Valid C5 yield scenario description.")
	scn.set("faction_setup", ["federation", "zeon"])
	scn.set("initial_node_specs", [
		{"id": "n1", "tile": Vector2i(1, 1), "node_type": "city", "sector": 1},
		{"id": "n2", "tile": Vector2i(2, 2), "node_type": "safehouse", "sector": 1}
	])

	scn.set("initial_territory_specs", [
		{"id": "t1", "members": ["n1"], "controller": "federation", "category": "industrial", "income_credits": 30, "income_scrap": 2},
		{"id": "t2", "members": ["n2"], "controller": "zeon"}
	])
	var res := ScenarioSchemaValidator.validate_scenario(scn)
	_check(res.valid, "valid scenario with yield declarations passes")

	scn.set("initial_territory_specs", [
		{"id": "t1", "members": ["n1"], "controller": "federation", "category": "mystery"}
	])
	res = ScenarioSchemaValidator.validate_scenario(scn)
	_check(not res.valid, "scenario with unknown category rejected")
	_check((res.errors as Array).any(func(e): return e.get("code") == "INVALID_TERRITORY_CATEGORY"), "reports INVALID_TERRITORY_CATEGORY")

	scn.set("initial_territory_specs", [
		{"id": "t1", "members": ["n1"], "controller": "federation", "category": "commercial", "income_credits": -4}
	])
	res = ScenarioSchemaValidator.validate_scenario(scn)
	_check(not res.valid, "scenario with negative income rejected")
	_check((res.errors as Array).any(func(e): return e.get("code") == "INVALID_TERRITORY_INCOME"), "reports INVALID_TERRITORY_INCOME")

	scn.set("initial_territory_specs", [
		{"id": "t1", "members": ["n1"], "controller": "federation", "income_scrap": 3}
	])
	res = ScenarioSchemaValidator.validate_scenario(scn)
	_check(not res.valid, "scenario with income but no category rejected")
	_check((res.errors as Array).any(func(e): return e.get("code") == "INVALID_TERRITORY_INCOME"), "income without category reports INVALID_TERRITORY_INCOME")


func _test_scenario_initialization_applies_yield() -> void:
	CampaignTerritory.clear()
	CampaignNodeRegistry.clear()
	var scn: Resource = ScenarioDefinition.new()
	scn.set("scenario_id", "test_c5_yield_init_scn")
	scn.set("display_name", "Test C5 Yield Init Scenario")
	scn.set("description", "Valid C5 yield init scenario description.")
	scn.set("faction_setup", ["federation", "zeon"])
	scn.set("initial_node_specs", [
		{"id": "n1", "tile": Vector2i(1, 1), "node_type": "city", "sector": 1},
		{"id": "n2", "tile": Vector2i(2, 2), "node_type": "safehouse", "sector": 1}
	])
	scn.set("initial_territory_specs", [
		{"id": "t_init_1", "members": ["n1"], "controller": "federation", "category": "residential", "income_credits": 12, "income_scrap": 1},
		{"id": "t_init_2", "members": ["n2"], "controller": "zeon"}
	])
	var init_res := CampaignScenarioInitializer.apply_scenario(scn)
	_check(init_res.ok and init_res.applied, "apply_scenario with yields succeeded")
	var y1 := CampaignTerritory.get_yield("t_init_1")
	_check(y1.get("category") == "residential", "initializer applies declared category")
	_check(int(y1.get("income_credits", -1)) == 12, "initializer applies declared credit income")
	_check(int(y1.get("income_scrap", -1)) == 1, "initializer applies declared scrap income")
	var y2 := CampaignTerritory.get_yield("t_init_2")
	_check(y2.get("category", "x") == "" and int(y2.get("income_credits", -1)) == 0, "territory without yield declaration stays unclassified")
	_check(CampaignTerritory.validate().is_empty(), "initialized yields validate cleanly")
	CampaignTerritory.clear()
	CampaignNodeRegistry.clear()
