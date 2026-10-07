class_name ScenarioCatalogData
extends Resource

## ---------------------------------------------------------------------------
## SCENARIO CATALOG DATA — Database holding canonical ScenarioDefinition resources.
##
## Phase 5Z Status:
##   The repository currently contains ZERO canonical campaign scenarios.
##   Therefore, this catalog is explicitly empty (`scenarios = []`).
##   Empty catalog represents the valid state: NO CANONICAL SCENARIO CURRENTLY DEFINED.
## ---------------------------------------------------------------------------

const DATA_CLASSIFICATION := "CANONICAL"

@export var scenarios: Array = []


func get_data_classification() -> String:
	return DATA_CLASSIFICATION


func is_canonical() -> bool:
	return true


func get_scenario(id: String) -> Resource:
	for item in scenarios:
		if item is Resource and item.get("scenario_id") == id:
			return item
	return null


func get_all_scenarios() -> Array:
	return scenarios.duplicate()


func has_scenario(id: String) -> bool:
	return get_scenario(id) != null


func is_empty() -> bool:
	return scenarios.is_empty()


func get_scenario_count() -> int:
	return scenarios.size()
