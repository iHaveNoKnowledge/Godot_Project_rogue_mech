class_name ScenarioSchemaValidator
extends RefCounted

## ---------------------------------------------------------------------------
## SCENARIO SCHEMA VALIDATOR — Phase 5AC (Canonical Scenario Schema Validator).
##
## Architectural Responsibility:
##   Pure, read-only inspection layer that determines whether a ScenarioDefinition
##   contains structurally valid authored scenario data BEFORE CampaignScenarioInitializer
##   converts it into runtime campaign state.
##
## Strict Scope:
##   - NEVER mutates ScenarioDefinition.
##   - NEVER mutates runtime campaign state (CampaignForce, CampaignNodeRegistry,
##     CampaignTerritory, CampaignBase, FactionSystem, GlobalData).
##   - Pure function: validate_scenario(scenario, catalog_context) -> Dictionary
## ---------------------------------------------------------------------------

const DATA_CLASSIFICATION := "CANONICAL"

## Whitelist of supported strategic rule keys.
## Prevents strategic_rules Dictionary from becoming an untyped escape hatch.
const SUPPORTED_STRATEGIC_RULES: Array[String] = [
	"turn_limit",
	"victory_condition",
	"defeat_condition",
]

## Forbidden runtime fields that must NEVER appear in authored specs.
const FORBIDDEN_FORCE_RUNTIME_FIELDS: Array[String] = [
	"state", "orders", "order", "battles", "battle_id", "combat",
	"position", "path", "route", "health", "hp", "cooldown",
	"inventory", "supplies", "supply", "fuel", "ammo", "casualties",
	"allegiance", "object", "resource"
]

const FORBIDDEN_NODE_RUNTIME_FIELDS: Array[String] = [
	"forces", "units", "occupants", "controller", "owner", "faction",
	"state", "health", "destroyed", "object", "resource", "node"
]

const FORBIDDEN_TERRITORY_RUNTIME_FIELDS: Array[String] = [
	"forces", "units", "occupants", "contesting_forces", "events",
	"active_events", "object", "resource"
]

const FORBIDDEN_BASE_RUNTIME_FIELDS: Array[String] = [
	"supply", "supplies", "fuel", "ammo", "inventory",
	"reinforcements", "reinforcement_queue", "queue",
	"garrison", "forces", "units", "roster",
	"under_siege", "siege_turns", "siege",
	"object", "resource"
]


static func get_data_classification() -> String:
	return DATA_CLASSIFICATION


static func is_canonical_authority() -> bool:
	return true


## Convenience predicate.
static func is_valid(scenario: Resource, catalog_context: Resource = null) -> bool:
	var result := validate_scenario(scenario, catalog_context)
	return bool(result.get("valid", false))


## Validates an authored ScenarioDefinition resource.
## Returns a structured validation result Dictionary:
## {
##   "valid": bool,
##   "errors": Array[Dictionary], # [{ "code": String, "field": String, "reason": String }, ...]
##   "warnings": Array[Dictionary]
## }
static func validate_scenario(scenario: Resource, catalog_context: Resource = null) -> Dictionary:
	var errors: Array[Dictionary] = []
	var warnings: Array[Dictionary] = []

	# 0. Null check
	if scenario == null:
		_add_error(errors, "NULL_SCENARIO", "", "ScenarioDefinition resource cannot be null.")
		return _build_result(errors, warnings)

	# Type contract check
	if not ("scenario_id" in scenario) or not scenario.has_method("get_initial_force_specs"):
		_add_error(errors, "INVALID_RESOURCE_TYPE", "", "Resource is not an instance of ScenarioDefinition.")
		return _build_result(errors, warnings)

	# 1. Top-Level Fields Contract
	_validate_top_level(scenario, catalog_context, errors, warnings)

	# 2. Factions Setup
	_validate_faction_setup(scenario, errors, warnings)

	# 3. Initial Nodes
	var authored_node_ids := _validate_initial_nodes(scenario, errors, warnings)

	# 4. Initial Territories
	var authored_territory_ids := _validate_initial_territories(scenario, authored_node_ids, errors, warnings)

	# 5. Initial Bases
	var authored_base_ids := _validate_initial_bases(scenario, authored_node_ids, authored_territory_ids, errors, warnings)

	# 6. Initial Forces & Cross-References
	_validate_initial_forces(scenario, authored_node_ids, authored_base_ids, errors, warnings)

	# 7. Initial Relationships
	_validate_initial_relationships(scenario, errors, warnings)

	# 8. Strategic Rules (Strict Whitelist & Scalar Enforcement)
	_validate_strategic_rules(scenario, errors, warnings)

	return _build_result(errors, warnings)


## Validates a ScenarioCatalogData resource.
## An empty catalog is canonically valid.
static func validate_catalog(catalog: Resource) -> Dictionary:
	var errors: Array[Dictionary] = []
	var warnings: Array[Dictionary] = []

	if catalog == null:
		_add_error(errors, "NULL_CATALOG", "", "Scenario catalog cannot be null.")
		return _build_result(errors, warnings)

	if not ("scenarios" in catalog) or not (catalog.get("scenarios") is Array):
		_add_error(errors, "INVALID_CATALOG_STRUCTURE", "scenarios", "Catalog must contain a 'scenarios' Array.")
		return _build_result(errors, warnings)

	var scenarios_array: Array = catalog.get("scenarios")
	if scenarios_array.is_empty():
		# Empty catalog is explicitly valid and safe
		return _build_result(errors, warnings)

	var seen_ids: Dictionary = {}
	for i in range(scenarios_array.size()):
		var item = scenarios_array[i]
		if not (item is Resource):
			_add_error(errors, "INVALID_CATALOG_ENTRY", "scenarios[%d]" % i, "Catalog entry must be a Resource.")
			continue

		var s_id: String = str(item.get("scenario_id", "")).strip_edges()
		if s_id != "":
			if seen_ids.has(s_id):
				_add_error(errors, "DUPLICATE_SCENARIO_ID", "scenarios[%d].scenario_id" % i,
					"Duplicate scenario_id '%s' in scenario catalog." % s_id)
			else:
				seen_ids[s_id] = true

		var sub_result := validate_scenario(item, catalog)
		if not sub_result.get("valid", false):
			for err in sub_result.get("errors", []):
				errors.append(err)
			for warn in sub_result.get("warnings", []):
				warnings.append(warn)

	return _build_result(errors, warnings)


# --- Internal Validation Helpers ---------------------------------------------

static func _build_result(errors: Array[Dictionary], warnings: Array[Dictionary]) -> Dictionary:
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
	}


static func _add_error(errors: Array[Dictionary], code: String, field: String, reason: String) -> void:
	errors.append({
		"code": code,
		"field": field,
		"reason": reason,
	})


static func _add_warning(warnings: Array[Dictionary], code: String, field: String, reason: String) -> void:
	warnings.append({
		"code": code,
		"field": field,
		"reason": reason,
	})


static func _validate_top_level(scenario: Resource, catalog_context: Resource, errors: Array[Dictionary], _warnings: Array[Dictionary]) -> void:
	# scenario_id
	var raw_id = scenario.get("scenario_id")
	if not (raw_id is String):
		_add_error(errors, "INVALID_FIELD_TYPE", "scenario_id", "scenario_id must be a String.")
	else:
		var sc_id: String = str(raw_id).strip_edges()
		if sc_id.is_empty():
			_add_error(errors, "MISSING_SCENARIO_ID", "scenario_id", "scenario_id cannot be empty.")
		else:
			# Verify stable identifier suitable for save identity
			var valid_chars := true
			for ch in sc_id:
				var c := ch.to_lower()
				if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "-"):
					valid_chars = false
					break
			if not valid_chars:
				_add_error(errors, "INVALID_SCENARIO_ID", "scenario_id",
					"scenario_id must contain only alphanumeric characters, underscores, or hyphens.")

			if catalog_context != null and catalog_context.has_method("get_all_scenarios"):
				var all_sc: Array = catalog_context.call("get_all_scenarios")
				var duplicate_count := 0
				for s in all_sc:
					if s is Resource and s.get("scenario_id") == sc_id:
						duplicate_count += 1
				if duplicate_count > 1:
					_add_error(errors, "DUPLICATE_SCENARIO_ID", "scenario_id",
						"scenario_id '%s' is duplicated in the catalog." % sc_id)

	# display_name
	var raw_name = scenario.get("display_name")
	if not (raw_name is String):
		_add_error(errors, "INVALID_FIELD_TYPE", "display_name", "display_name must be a String.")
	else:
		if str(raw_name).strip_edges().is_empty():
			_add_error(errors, "MISSING_DISPLAY_NAME", "display_name", "display_name must be a non-empty String.")

	# description
	var raw_desc = scenario.get("description")
	if not (raw_desc is String):
		_add_error(errors, "INVALID_FIELD_TYPE", "description", "description must be a String.")

	# Container types
	if not (scenario.get("faction_setup") is Array):
		_add_error(errors, "INVALID_FIELD_TYPE", "faction_setup", "faction_setup must be an Array.")
	if not (scenario.get("initial_force_specs") is Array):
		_add_error(errors, "INVALID_FIELD_TYPE", "initial_force_specs", "initial_force_specs must be an Array.")
	if not (scenario.get("initial_node_specs") is Array):
		_add_error(errors, "INVALID_FIELD_TYPE", "initial_node_specs", "initial_node_specs must be an Array.")
	if not (scenario.get("initial_territory_specs") is Array):
		_add_error(errors, "INVALID_FIELD_TYPE", "initial_territory_specs", "initial_territory_specs must be an Array.")
	if not (scenario.get("initial_base_specs") is Array):
		_add_error(errors, "INVALID_FIELD_TYPE", "initial_base_specs", "initial_base_specs must be an Array.")
	if not (scenario.get("initial_relationships") is Dictionary):
		_add_error(errors, "INVALID_FIELD_TYPE", "initial_relationships", "initial_relationships must be a Dictionary.")
	if not (scenario.get("strategic_rules") is Dictionary):
		_add_error(errors, "INVALID_FIELD_TYPE", "strategic_rules", "strategic_rules must be a Dictionary.")


static func _validate_faction_setup(scenario: Resource, errors: Array[Dictionary], _warnings: Array[Dictionary]) -> void:
	var factions_val = scenario.get("faction_setup")
	if not (factions_val is Array):
		return

	var seen_factions: Dictionary = {}
	var index := 0
	for entry in factions_val:
		var fac_id := ""
		if entry is String:
			fac_id = str(entry).strip_edges()
		elif entry is Dictionary:
			fac_id = str(entry.get("id", entry.get("faction_id", ""))).strip_edges()
		else:
			_add_error(errors, "INVALID_FACTION_SPEC", "faction_setup[%d]" % index,
				"Faction entry must be a String ID or Dictionary.")
			index += 1
			continue

		if fac_id.is_empty():
			_add_error(errors, "INVALID_FACTION_ID", "faction_setup[%d]" % index,
				"Faction ID cannot be empty.")
		elif not FactionSystem.has_faction(fac_id):
			_add_error(errors, "INVALID_FACTION_ID", "faction_setup[%d]" % index,
				"Faction '%s' does not exist in FactionSystem." % fac_id)
		elif seen_factions.has(fac_id):
			_add_error(errors, "DUPLICATE_FACTION_ID", "faction_setup[%d]" % index,
				"Faction '%s' is duplicated in faction_setup." % fac_id)
		else:
			seen_factions[fac_id] = true

		index += 1


static func _validate_initial_nodes(scenario: Resource, errors: Array[Dictionary], _warnings: Array[Dictionary]) -> Dictionary:
	var nodes_val = scenario.get("initial_node_specs")
	var authored_node_ids: Dictionary = {}
	if not (nodes_val is Array):
		return authored_node_ids

	for i in range(nodes_val.size()):
		var spec = nodes_val[i]
		if not (spec is Dictionary):
			_add_error(errors, "INVALID_NODE_SPEC", "initial_node_specs[%d]" % i,
				"Node specification must be a Dictionary.")
			continue

		# Forbidden runtime fields
		for k in FORBIDDEN_NODE_RUNTIME_FIELDS:
			if spec.has(k):
				_add_error(errors, "FORBIDDEN_RUNTIME_FIELD", "initial_node_specs[%d].%s" % [i, k],
					"Node specification must not contain runtime field '%s'." % k)

		# Node ID
		var nid: String = str(spec.get("id", spec.get("node_id", ""))).strip_edges()
		if nid.is_empty():
			_add_error(errors, "MISSING_NODE_ID", "initial_node_specs[%d].id" % i,
				"Node id cannot be empty.")
		elif authored_node_ids.has(nid):
			_add_error(errors, "DUPLICATE_NODE_ID", "initial_node_specs[%d].id" % i,
				"Duplicate node id '%s'." % nid)
		else:
			authored_node_ids[nid] = true

		# Node Type
		var ntype: String = str(spec.get("node_type", "safehouse")).strip_edges()
		var is_known_type := (CampaignNodeRegistry.is_strategic_tile(ntype.to_lower())
			or CampaignNodeRegistry.STRATEGIC_TILE_TYPES.values().has(ntype.to_upper()))
		if not is_known_type:
			_add_error(errors, "INVALID_NODE_TYPE", "initial_node_specs[%d].node_type" % i,
				"Node type '%s' is not recognized by CampaignNodeRegistry." % ntype)

		# Strategic Importance (optional scalar number)
		if spec.has("strategic_importance"):
			var imp = spec["strategic_importance"]
			if not ((imp is int) or (imp is float)) or imp < 0:
				_add_error(errors, "INVALID_STRATEGIC_IMPORTANCE", "initial_node_specs[%d].strategic_importance" % i,
					"strategic_importance must be a non-negative scalar number.")

	return authored_node_ids


static func _validate_initial_territories(scenario: Resource, authored_node_ids: Dictionary, errors: Array[Dictionary], _warnings: Array[Dictionary]) -> Dictionary:
	var terr_val = scenario.get("initial_territory_specs")
	var authored_territory_ids: Dictionary = {}
	if not (terr_val is Array):
		return authored_territory_ids

	for i in range(terr_val.size()):
		var spec = terr_val[i]
		if not (spec is Dictionary):
			_add_error(errors, "INVALID_TERRITORY_SPEC", "initial_territory_specs[%d]" % i,
				"Territory specification must be a Dictionary.")
			continue

		# Forbidden runtime fields
		for k in FORBIDDEN_TERRITORY_RUNTIME_FIELDS:
			if spec.has(k):
				_add_error(errors, "FORBIDDEN_RUNTIME_FIELD", "initial_territory_specs[%d].%s" % [i, k],
					"Territory specification must not contain runtime field '%s'." % k)

		# Territory ID
		var tid: String = str(spec.get("id", "")).strip_edges()
		if tid.is_empty():
			_add_error(errors, "MISSING_TERRITORY_ID", "initial_territory_specs[%d].id" % i,
				"Territory id cannot be empty.")
		elif authored_territory_ids.has(tid):
			_add_error(errors, "DUPLICATE_TERRITORY_ID", "initial_territory_specs[%d].id" % i,
				"Duplicate territory id '%s'." % tid)
		else:
			authored_territory_ids[tid] = true

		# Members / Nodes
		var members = spec.get("members", spec.get("nodes", []))
		if not (members is Array):
			_add_error(errors, "INVALID_TERRITORY_MEMBERS", "initial_territory_specs[%d].members" % i,
				"Territory members must be an Array.")
		else:
			for m in members:
				if not (m is String) or str(m).strip_edges().is_empty():
					_add_error(errors, "INVALID_TERRITORY_MEMBERS", "initial_territory_specs[%d].members" % i,
						"Territory member node must be a non-empty String.")
				else:
					var m_str := str(m).strip_edges()
					# Cross reference: if authored nodes exist and member is not board pattern or registered node
					if authored_node_ids.size() > 0 and not authored_node_ids.has(m_str) and not CampaignNodeRegistry.has_node(m_str) and not _is_board_node_pattern(m_str):
						_add_error(errors, "DANGLING_NODE_REFERENCE", "initial_territory_specs[%d].members" % i,
							"Member node '%s' does not exist in authored or registered nodes." % m_str)

		# Controller
		var ctrl: String = str(spec.get("controller", "")).strip_edges()
		if ctrl != "" and not FactionSystem.has_faction(ctrl):
			_add_error(errors, "INVALID_TERRITORY_CONTROLLER", "initial_territory_specs[%d].controller" % i,
				"Territory controller '%s' does not exist in FactionSystem." % ctrl)

		# State
		if spec.has("state"):
			var st = spec["state"]
			var valid_state := false
			if st is int:
				valid_state = (st >= 0 and st <= 2)
			elif st is String:
				valid_state = (st.to_lower() in ["uncontrolled", "controlled", "contested"])
			if not valid_state:
				_add_error(errors, "INVALID_TERRITORY_STATE", "initial_territory_specs[%d].state" % i,
					"Territory state '%s' is not recognized." % str(st))

	return authored_territory_ids


static func _validate_initial_bases(scenario: Resource, authored_node_ids: Dictionary, authored_territory_ids: Dictionary, errors: Array[Dictionary], _warnings: Array[Dictionary]) -> Dictionary:
	var bases_val = scenario.get("initial_base_specs")
	var authored_base_ids: Dictionary = {}
	if not (bases_val is Array):
		return authored_base_ids

	for i in range(bases_val.size()):
		var spec = bases_val[i]
		if not (spec is Dictionary):
			_add_error(errors, "INVALID_BASE_SPEC", "initial_base_specs[%d]" % i,
				"Base specification must be a Dictionary.")
			continue

		# Forbidden runtime fields
		for k in FORBIDDEN_BASE_RUNTIME_FIELDS:
			if spec.has(k):
				_add_error(errors, "FORBIDDEN_RUNTIME_FIELD", "initial_base_specs[%d].%s" % [i, k],
					"Base specification must not contain runtime field '%s'." % k)

		# Base ID
		var bid: String = str(spec.get("id", spec.get("base_id", ""))).strip_edges()
		if bid.is_empty():
			_add_error(errors, "MISSING_BASE_ID", "initial_base_specs[%d].id" % i,
				"Base id cannot be empty.")
		elif authored_base_ids.has(bid):
			_add_error(errors, "DUPLICATE_BASE_ID", "initial_base_specs[%d].id" % i,
				"Duplicate base id '%s'." % bid)
		else:
			authored_base_ids[bid] = true

		# Node ID
		var nid: String = str(spec.get("node_id", "")).strip_edges()
		if nid.is_empty():
			_add_error(errors, "INVALID_NODE_ID", "initial_base_specs[%d].node_id" % i,
				"Base node_id cannot be empty.")
		elif authored_node_ids.size() > 0 and not authored_node_ids.has(nid) and not CampaignNodeRegistry.has_node(nid) and not _is_board_node_pattern(nid):
			_add_error(errors, "DANGLING_NODE_REFERENCE", "initial_base_specs[%d].node_id" % i,
				"Base node_id '%s' does not exist in authored or registered nodes." % nid)

		# Base Type
		var btype: String = str(spec.get("base_type", "")).strip_edges()
		if btype.is_empty() or not (CampaignBase.is_valid_type(btype.to_upper()) or CampaignBase.BASE_TYPES.has(btype.to_upper())):
			_add_error(errors, "INVALID_BASE_TYPE", "initial_base_specs[%d].base_type" % i,
				"Base type '%s' is not recognized by CampaignBase." % btype)

		# Controller
		var ctrl: String = str(spec.get("controller", spec.get("faction", ""))).strip_edges()
		if ctrl != "" and not FactionSystem.has_faction(ctrl):
			_add_error(errors, "INVALID_BASE_CONTROLLER", "initial_base_specs[%d].controller" % i,
				"Base controller '%s' does not exist in FactionSystem." % ctrl)

		# State
		if spec.has("state"):
			var st = spec["state"]
			var valid_state := false
			if st is int:
				valid_state = (st >= 0 and st <= 2)
			elif st is String:
				valid_state = (st.to_lower() in ["active", "disabled", "destroyed"])
			if not valid_state:
				_add_error(errors, "INVALID_BASE_STATE", "initial_base_specs[%d].state" % i,
					"Base state '%s' is not recognized." % str(st))

		# Territory reference (optional)
		if spec.has("territory_id"):
			var tid: String = str(spec["territory_id"]).strip_edges()
			if tid != "":
				if authored_territory_ids.size() > 0 and not authored_territory_ids.has(tid) and not CampaignTerritory.has_territory(tid):
					_add_error(errors, "DANGLING_TERRITORY_REFERENCE", "initial_base_specs[%d].territory_id" % i,
						"Territory '%s' referenced by base does not exist in scenario territories." % tid)

	return authored_base_ids


static func _validate_initial_forces(scenario: Resource, authored_node_ids: Dictionary, authored_base_ids: Dictionary, errors: Array[Dictionary], _warnings: Array[Dictionary]) -> void:
	var forces_val = scenario.get("initial_force_specs")
	if not (forces_val is Array):
		return

	var seen_slugs: Dictionary = {}
	for i in range(forces_val.size()):
		var spec = forces_val[i]
		if not (spec is Dictionary):
			_add_error(errors, "INVALID_FORCE_SPEC", "initial_force_specs[%d]" % i,
				"Force specification must be a Dictionary.")
			continue

		# Forbidden runtime fields
		for k in FORBIDDEN_FORCE_RUNTIME_FIELDS:
			if spec.has(k):
				_add_error(errors, "FORBIDDEN_RUNTIME_FIELD", "initial_force_specs[%d].%s" % [i, k],
					"Force specification must not contain runtime field '%s'." % k)

		# Slug
		var slug: String = str(spec.get("slug", "")).strip_edges()
		if slug.is_empty():
			_add_error(errors, "MISSING_FORCE_SLUG", "initial_force_specs[%d].slug" % i,
				"Force slug cannot be empty.")
		elif seen_slugs.has(slug):
			_add_error(errors, "DUPLICATE_FORCE_SLUG", "initial_force_specs[%d].slug" % i,
				"Duplicate force slug '%s'." % slug)
		else:
			seen_slugs[slug] = true

		# Force Type
		var ftype: String = str(spec.get("force_type", "")).strip_edges()
		if ftype.is_empty() or not (CampaignForce.is_valid_type(ftype.to_upper()) or CampaignForce.FORCE_TYPES.has(ftype.to_upper())):
			_add_error(errors, "INVALID_FORCE_TYPE", "initial_force_specs[%d].force_type" % i,
				"Force type '%s' is not recognized by CampaignForce." % ftype)

		# Faction
		var faction: String = str(spec.get("faction", "")).strip_edges()
		if faction.is_empty() or not FactionSystem.has_faction(faction):
			_add_error(errors, "INVALID_FACTION_ID", "initial_force_specs[%d].faction" % i,
				"Faction '%s' does not exist in FactionSystem." % faction)

		# Node ID
		var nid: String = str(spec.get("node_id", "")).strip_edges()
		if nid.is_empty():
			_add_error(errors, "INVALID_NODE_ID", "initial_force_specs[%d].node_id" % i,
				"Force node_id cannot be empty.")
		elif authored_node_ids.size() > 0 and not authored_node_ids.has(nid) and not CampaignNodeRegistry.has_node(nid) and not _is_board_node_pattern(nid):
			_add_error(errors, "DANGLING_NODE_REFERENCE", "initial_force_specs[%d].node_id" % i,
				"Force node_id '%s' does not exist in authored or registered nodes." % nid)

		# Unit Count
		if not spec.has("unit_count"):
			_add_error(errors, "MISSING_FIELD", "initial_force_specs[%d].unit_count" % i,
				"Force unit_count is required.")
		else:
			var uc = spec["unit_count"]
			if not ((uc is int) or (uc is float and uc == floor(uc))) or int(uc) <= 0:
				_add_error(errors, "INVALID_FORCE_UNIT_COUNT", "initial_force_specs[%d].unit_count" % i,
					"unit_count must be an integer greater than 0.")

		# Strength
		if not spec.has("strength"):
			_add_error(errors, "MISSING_FIELD", "initial_force_specs[%d].strength" % i,
				"Force strength is required.")
		else:
			var st = spec["strength"]
			if not ((st is int) or (st is float and st == floor(st))) or int(st) < 0:
				_add_error(errors, "INVALID_FORCE_STRENGTH", "initial_force_specs[%d].strength" % i,
					"strength must be a non-negative integer.")

		# Base ID (optional cross-reference)
		if spec.has("base_id"):
			var bid: String = str(spec["base_id"]).strip_edges()
			if bid != "":
				if authored_base_ids.size() > 0 and not authored_base_ids.has(bid) and not CampaignBase.has_base(bid):
					_add_error(errors, "DANGLING_BASE_REFERENCE", "initial_force_specs[%d].base_id" % i,
						"Base '%s' referenced by force does not exist in scenario bases." % bid)


static func _validate_initial_relationships(scenario: Resource, errors: Array[Dictionary], _warnings: Array[Dictionary]) -> void:
	var rels_val = scenario.get("initial_relationships")
	if not (rels_val is Dictionary):
		return

	for key in rels_val:
		if not (key is String):
			_add_error(errors, "INVALID_RELATIONSHIP_KEY", "initial_relationships",
				"Relationship key must be a String.")
			continue

		var key_str: String = str(key)
		var parts: PackedStringArray = []
		if ":" in key_str:
			parts = key_str.split(":")
		elif "|" in key_str:
			parts = key_str.split("|")
		else:
			_add_error(errors, "INVALID_RELATIONSHIP_KEY", "initial_relationships.%s" % key_str,
				"Relationship key must be delimited by ':' or '|'.")
			continue

		if parts.size() != 2:
			_add_error(errors, "INVALID_RELATIONSHIP_KEY", "initial_relationships.%s" % key_str,
				"Relationship key must contain exactly two faction IDs.")
			continue

		var fa: String = parts[0].strip_edges()
		var fb: String = parts[1].strip_edges()

		if not FactionSystem.has_faction(fa):
			_add_error(errors, "INVALID_FACTION_ID", "initial_relationships.%s" % key_str,
				"Faction '%s' does not exist in FactionSystem." % fa)
		if not FactionSystem.has_faction(fb):
			_add_error(errors, "INVALID_FACTION_ID", "initial_relationships.%s" % key_str,
				"Faction '%s' does not exist in FactionSystem." % fb)

		if fa == fb and FactionSystem.has_faction(fa):
			_add_error(errors, "SELF_RELATIONSHIP_PROHIBITED", "initial_relationships.%s" % key_str,
				"Self-relationships are prohibited in FactionSystem.")

		# Value check
		var val = rels_val[key]
		var valid_val := false
		if val is int:
			valid_val = (val >= 0 and val <= 3)
		elif val is String:
			valid_val = (val.to_lower() in ["hostile", "neutral", "cooperative", "allied"])
		if not valid_val:
			_add_error(errors, "INVALID_RELATIONSHIP_VALUE", "initial_relationships.%s" % key_str,
				"Relationship value '%s' is not recognized by FactionSystem." % str(val))


static func _validate_strategic_rules(scenario: Resource, errors: Array[Dictionary], _warnings: Array[Dictionary]) -> void:
	var rules_val = scenario.get("strategic_rules")
	if not (rules_val is Dictionary):
		return

	for key in rules_val:
		if not (key is String):
			_add_error(errors, "INVALID_RULE_KEY", "strategic_rules",
				"Strategic rule key must be a String.")
			continue

		var k_str: String = str(key)
		if not SUPPORTED_STRATEGIC_RULES.has(k_str):
			_add_error(errors, "UNSUPPORTED_SCENARIO_RULE", "strategic_rules.%s" % k_str,
				"Rule '%s' is unsupported. Allowed rule keys: %s." % [k_str, str(SUPPORTED_STRATEGIC_RULES)])
			continue

		var val = rules_val[key]
		var is_scalar := ((val is int) or (val is float) or (val is bool) or (val is String))
		if not is_scalar:
			_add_error(errors, "INVALID_RULE_VALUE", "strategic_rules.%s" % k_str,
				"Rule value for '%s' must be a scalar (int, float, bool, String). Objects/Containers are forbidden." % k_str)


static func _is_board_node_pattern(nid: String) -> bool:
	# Hybrid model: board-projected nodes follow node_s<sec>_<type>_<x>_<y> or node_<x>_<y> or test_node_...
	if nid.begins_with("node_") or nid.begins_with("test_node"):
		return true
	return false
