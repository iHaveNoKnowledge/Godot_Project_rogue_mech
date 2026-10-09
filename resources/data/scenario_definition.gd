class_name ScenarioDefinition
extends Resource

## ---------------------------------------------------------------------------
## SCENARIO DEFINITION — Phase 5Z (Canonical Campaign World Authority).
##
## Architectural Contract:
##   SCENARIO             = Authoritative game-design definition of how the campaign world starts.
##   RUN THEME            = Player-facing starting loadout, allies, and run flow modifiers.
##   RUNTIME STATE        = Mutable state produced by gameplay actions and turns.
##   PLAYER STATE         = Pilot, mecha frame/parts, hangar, equipment, player resources.
##   SEED / BOARD GEN     = Deterministic procedural variation and physical grid topology.
##
## Design Rule:
##   If a field is not authoritatively authored by game design, it must remain
##   empty / undefined. NO speculative fallback values are injected.
## ---------------------------------------------------------------------------

const DATA_CLASSIFICATION := "CANONICAL"

## Stable, unique scenario identifier (e.g. "frontier_skirmish").
@export var scenario_id: String = ""

## Display name and narrative overview.
@export var display_name: String = ""
@export_multiline var description: String = ""

## World starting state specifications:
## Factions participating in the scenario: Array of faction IDs or setup dictionaries.
@export var faction_setup: Array = []

## Starting strategic forces: Array of force spec dictionaries authored for this scenario.
## Shape per force spec:
##   { "slug": String, "force_type": String, "faction": String, "node_id": String, "strength": int, ... }
@export var initial_force_specs: Array = []

## Starting strategic nodes authored specifically for this scenario (if overriding procedural nodes).
@export var initial_node_specs: Array = []

## Starting strategic routes connecting authored nodes explicitly.
## Shape per route spec: { "a": String, "b": String }
@export var initial_route_specs: Array = []

## Initial territory ownership/claims: Array of territory spec dictionaries.
@export var initial_territory_specs: Array = []

## Initial bases: Array of base spec dictionaries.
@export var initial_base_specs: Array = []

## Initial faction-to-faction relationships / standing: Dictionary of { "facA:facB": score }
@export var initial_relationships: Dictionary = {}

## Scenario-specific strategic rules or conditions.
@export var strategic_rules: Dictionary = {}


## Returns whether this scenario definition has an authoritative identity.
func is_valid() -> bool:
	return not scenario_id.strip_edges().is_empty()


## Returns the data classification for this authority.
func get_data_classification() -> String:
	return DATA_CLASSIFICATION


## Returns whether this scenario definition represents canonical data.
func is_canonical() -> bool:
	return true


## Returns a deep copy of initial force specs to prevent external mutation of authoring data.
func get_initial_force_specs() -> Array:
	var out: Array = []
	for spec in initial_force_specs:
		if spec is Dictionary:
			out.append((spec as Dictionary).duplicate(true))
		else:
			out.append(spec)
	return out


## Returns a deep copy of faction setup.
func get_faction_setup() -> Array:
	return faction_setup.duplicate(true)


## Returns a deep copy of initial node specs.
func get_initial_node_specs() -> Array:
	return initial_node_specs.duplicate(true)


## Returns a deep copy of initial route specs.
func get_initial_route_specs() -> Array:
	return initial_route_specs.duplicate(true)


## Returns a deep copy of territory specs.
func get_initial_territory_specs() -> Array:
	return initial_territory_specs.duplicate(true)


## Returns a deep copy of base specs.
func get_initial_base_specs() -> Array:
	return initial_base_specs.duplicate(true)


## Returns a deep copy of relationships.
func get_initial_relationships() -> Dictionary:
	return initial_relationships.duplicate(true)


## Returns a deep copy of strategic rules.
func get_strategic_rules() -> Dictionary:
	return strategic_rules.duplicate(true)
