class_name CampaignScenarioSelection
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN SCENARIO SELECTION — Phase 5AE (Scenario Selection Contract).
##
## Thin selection layer between scenario browsing and campaign start:
##   catalog enumeration (stable IDs + display metadata)
##           ↓
##   select_scenario(id): existence + schema validation, stores pending ID
##           ↓
##   confirm_selection(): re-resolves + re-validates, then delegates to the
##     existing entry contract RunStartSystem.start_campaign_scenario(...)
##
## Architectural Contract:
##   - Identity is always the stable scenario_id, never display_name.
##   - The catalog is the single source of selectable scenarios; no
##     selection-side copy or parallel registry is kept (only a transient
##     pending ID string, which is re-validated on confirm).
##   - Selection and preview are pure: listing, selecting, confirming a
##     FAILED start, or cancelling mutates no campaign runtime state.
##   - Runtime initialization belongs to 5AF/RunStartSystem; this layer
##     never executes turns, moves, battles, or state publication itself.
##   - Cancellation (clear_selection) and failed confirmation keep or drop
##     only the transient pending ID; successful confirmation clears it.
## ---------------------------------------------------------------------------

const CANONICAL_CATALOG_PATH := "res://resources/data/scenario_definition_catalog.tres"

const ScenarioCatalogScript = preload("res://resources/data/scenario_catalog_data.gd")
const ScenarioSchemaValidatorScript = preload("res://scripts/systems/scenario_schema_validator.gd")

static var _pending_scenario_id := ""


## Returns the pending selected scenario ID ("" when nothing is selected).
static func get_pending_scenario_id() -> String:
	return _pending_scenario_id


## Drops the pending selection without touching campaign runtime state.
static func clear_selection() -> void:
	_pending_scenario_id = ""


## Resolves the working catalog: explicit argument wins, otherwise the
## canonical on-disk catalog, otherwise null when unloadable.
static func resolve_catalog(catalog: Resource = null) -> Resource:
	if catalog != null:
		return catalog
	if ResourceLoader.exists(CANONICAL_CATALOG_PATH):
		return load(CANONICAL_CATALOG_PATH)
	return null


## Lists every catalog entry with display metadata and its validation
## result, in catalog order. Entries that fail validation are listed with
## valid=false (shown but never selectable) rather than hidden.
static func list_selectable_scenarios(catalog: Resource = null) -> Array:
	var active_catalog := resolve_catalog(catalog)
	var out: Array = []
	if active_catalog == null or not (active_catalog.get("scenarios") is Array):
		return out
	for item in active_catalog.get("scenarios"):
		if not (item is Resource):
			continue
		var sid := str(item.get("scenario_id") if "scenario_id" in item else "").strip_edges()
		var entry := {
			"scenario_id": sid,
			"display_name": str(item.get("display_name") if "display_name" in item else ""),
			"description": str(item.get("description") if "description" in item else ""),
			"valid": false if sid == "" else bool(
				ScenarioSchemaValidatorScript.validate_scenario(item, active_catalog).get("valid", false)),
		}
		out.append(entry)
	return out


## Returns display metadata for one catalog entry ({} when absent).
## Read-only: resolves and validates without storing any selection.
static func get_scenario_display(scenario_id: String, catalog: Resource = null) -> Dictionary:
	var clean_id := scenario_id.strip_edges()
	var active_catalog := resolve_catalog(catalog)
	if clean_id == "" or active_catalog == null:
		return {}
	var item = active_catalog.get_scenario(clean_id) if active_catalog.has_method("get_scenario") else null
	if not (item is Resource):
		return {}
	return {
		"scenario_id": clean_id,
		"display_name": str(item.get("display_name") if "display_name" in item else ""),
		"description": str(item.get("description") if "description" in item else ""),
		"valid": bool(ScenarioSchemaValidatorScript.validate_scenario(item, active_catalog).get("valid", false)),
	}


## Selects a scenario by stable ID after existence + schema validation.
## Stores only the transient pending ID; mutates no campaign state.
static func select_scenario(scenario_id: String, catalog: Resource = null) -> Dictionary:
	var clean_id := scenario_id.strip_edges()
	if clean_id == "":
		return {"ok": false, "reason": "missing_scenario_id", "scenario_id": ""}
	var active_catalog := resolve_catalog(catalog)
	if active_catalog == null:
		return {"ok": false, "reason": "catalog_not_found", "scenario_id": clean_id}
	var scenario = active_catalog.get_scenario(clean_id) if active_catalog.has_method("get_scenario") else null
	if not (scenario is Resource):
		return {"ok": false, "reason": "unknown_scenario", "scenario_id": clean_id}
	var validation: Dictionary = ScenarioSchemaValidatorScript.validate_scenario(scenario, active_catalog)
	if not bool(validation.get("valid", false)):
		return {"ok": false, "reason": "validation_failed", "scenario_id": clean_id,
			"errors": validation.get("errors", [])}
	_pending_scenario_id = clean_id
	return {"ok": true, "reason": "selected", "scenario_id": clean_id}


## Confirms the pending selection: re-resolves and re-validates, then
## delegates to the existing campaign-entry contract. A failed confirmation
## keeps the pending ID (retryable); success clears it. Returns the entry
## receipt unmodified on delegation.
static func confirm_selection(catalog: Resource = null, sector: int = 1) -> Dictionary:
	if _pending_scenario_id == "":
		return {"ok": false, "reason": "missing_selection", "scenario_id": "",
			"started": false}
	var clean_id := _pending_scenario_id
	var active_catalog := resolve_catalog(catalog)
	if active_catalog == null or not (active_catalog is ScenarioCatalogScript):
		return {"ok": false, "reason": "catalog_not_found", "scenario_id": clean_id,
			"started": false}
	var scenario = active_catalog.get_scenario(clean_id) if active_catalog.has_method("get_scenario") else null
	if not (scenario is Resource):
		return {"ok": false, "reason": "unknown_scenario", "scenario_id": clean_id,
			"started": false}
	var validation: Dictionary = ScenarioSchemaValidatorScript.validate_scenario(scenario, active_catalog)
	if not bool(validation.get("valid", false)):
		return {"ok": false, "reason": "validation_failed", "scenario_id": clean_id,
			"started": false, "errors": validation.get("errors", [])}
	var result: Dictionary = RunStartSystem.start_campaign_scenario(clean_id, active_catalog, sector)
	if bool(result.get("ok", false)) and bool(result.get("started", false)):
		_pending_scenario_id = ""
	return result
