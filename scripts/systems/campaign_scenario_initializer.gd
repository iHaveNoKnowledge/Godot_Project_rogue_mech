class_name CampaignScenarioInitializer
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN SCENARIO INITIALIZER — Phase 5Z (Canonical Scenario Initialization Authority).
##
## Architectural Contract:
##   ScenarioDefinition
##           ↓
##   CampaignScenarioInitializer
##           ↓
##   Campaign Runtime State (CampaignForce, CampaignNodeRegistry, CampaignTerritory, CampaignBase)
##
## Zero-Data Contract:
##   When scenario is null, invalid, or has no authored initial force specs:
##     - Live campaign start registers ZERO forces.
##     - NEVER invokes or falls back to CampaignForceInitializer (which remains
##       strictly a SPECULATIVE_DEVELOPMENT_FIXTURE).
##     - Does not consume RunTheme or BoardGenerator as fake scenario authorities.
##     - ScenarioDefinition remains unmutated (read-only authoring data).
## ---------------------------------------------------------------------------

const ScenarioDef = preload("res://resources/data/scenario_definition.gd")

const DATA_CLASSIFICATION := "CANONICAL"


static func get_data_classification() -> String:
	return DATA_CLASSIFICATION


static func is_canonical_authority() -> bool:
	return true


## Checks whether the given scenario can be applied.
static func can_apply(scenario: Resource) -> bool:
	if scenario == null:
		return false
	if scenario.has_method("is_valid"):
		return scenario.call("is_valid")
	return false


## Applies an authored ScenarioDefinition to initialize the campaign runtime state.
## If scenario is null or invalid, cleanly does nothing and returns empty result.
## Under NO circumstances does this fall back to speculative fixtures.
static func apply_scenario(scenario: Resource, sector: int = 1) -> Dictionary:
	if not can_apply(scenario):
		return {
			"ok": true,
			"applied": false,
			"reason": "no_scenario",
			"scenario_id": "",
			"forces_created": [],
			"nodes_created": [],
			"territories_created": [],
			"bases_created": [],
		}

	var forces_created: Array[String] = []
	var nodes_created: Array[String] = []
	var territories_created: Array[String] = []
	var bases_created: Array[String] = []

	# 1. Apply authored initial nodes (if any explicitly specified)
	var node_specs: Array = scenario.get_initial_node_specs() if scenario.has_method("get_initial_node_specs") else []
	for node_spec in node_specs:
		if node_spec is Dictionary:
			var nid: String = str(node_spec.get("id", ""))
			var tile: Vector2i = node_spec.get("tile", Vector2i(-1, -1))
			var node_type: String = str(node_spec.get("node_type", "safehouse")).to_lower()
			var sec: int = int(node_spec.get("sector", sector))
			if nid != "" and not CampaignNodeRegistry.has_node(nid):
				var reg_id := CampaignNodeRegistry.register_node(sec, tile, node_type, nid)
				if reg_id != "":
					nodes_created.append(reg_id)

	# 2. Apply authored initial territories (if any explicitly specified)
	var terr_specs: Array = scenario.get_initial_territory_specs() if scenario.has_method("get_initial_territory_specs") else []
	for terr_spec in terr_specs:
		if terr_spec is Dictionary:
			var tid: String = str(terr_spec.get("id", ""))
			var node_ids: Array = terr_spec.get("nodes", [])
			if tid != "" and not CampaignTerritory.has_territory(tid):
				CampaignTerritory.register_territory(tid, node_ids)
				var ctrl_name: String = str(terr_spec.get("controller", ""))
				if ctrl_name != "":
					CampaignTerritory.set_controlled(tid, ctrl_name)
				territories_created.append(tid)

	# 3. Apply authored initial bases (if any explicitly specified)
	var base_specs: Array = scenario.get_initial_base_specs() if scenario.has_method("get_initial_base_specs") else []
	for base_spec in base_specs:
		if base_spec is Dictionary:
			var bid: String = str(base_spec.get("id", ""))
			var nid: String = str(base_spec.get("node_id", ""))
			var faction: String = str(base_spec.get("faction", ""))
			var base_type: String = str(base_spec.get("base_type", "OUTPOST"))
			var terr_id: String = str(base_spec.get("territory_id", ""))
			if bid != "" and not CampaignBase.has_base(bid):
				var reg_base := CampaignBase.register_base(bid, nid, base_type, faction, terr_id)
				if reg_base != "":
					bases_created.append(reg_base)

	# 4. Apply authored initial forces (strictly from scenario.get_initial_force_specs())
	# NO FALLBACK TO CampaignForceInitializer.DEFAULT_FORCE_SPECS!
	var force_specs: Array = scenario.get_initial_force_specs() if scenario.has_method("get_initial_force_specs") else []
	for i in range(force_specs.size()):
		var spec = force_specs[i]
		if not (spec is Dictionary):
			continue
		var slug: String = str(spec.get("slug", ""))
		if slug == "":
			slug = "force_%d" % i
		var fid: String = CampaignForce.make_force_id(sector, slug)
		if fid == "" or CampaignForce.has_force(fid):
			continue

		var force_type: String = str(spec.get("force_type", "PATROL"))
		var faction_id: String = str(spec.get("faction", ""))
		if faction_id != "" and not FactionSystem.has_faction(faction_id):
			faction_id = ""

		var node_id: String = str(spec.get("node_id", ""))
		var base_id: String = str(spec.get("base_id", ""))
		var unit_count: int = maxi(int(spec.get("unit_count", 1)), 0)
		var strength: int = maxi(int(spec.get("strength", 10)), 0)

		var res_id: String = CampaignForce.register_force(
			fid,
			force_type,
			faction_id,
			node_id,
			base_id,
			unit_count,
			strength
		)
		if res_id != "":
			forces_created.append(res_id)

	var sc_id: String = str(scenario.get("scenario_id")) if "scenario_id" in scenario else ""

	return {
		"ok": true,
		"applied": true,
		"reason": "success",
		"scenario_id": sc_id,
		"forces_created": forces_created,
		"nodes_created": nodes_created,
		"territories_created": territories_created,
		"bases_created": bases_created,
	}
