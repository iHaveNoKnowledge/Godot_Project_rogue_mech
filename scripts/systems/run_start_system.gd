class_name RunStartSystem
extends RefCounted

# -----------------------------------------------------------------------------
# RANDOM RUN START
# Rolls and installs the starting loadout for a new run from the current theme's
# start config. Extracted from GlobalData so the run-state autoload stays
# focused on state; GlobalData keeps a thin roll_random_start() facade.
# -----------------------------------------------------------------------------


# Picks a weighted-random chassis key from a theme's chassis_weights.
static func roll_weighted_chassis(theme: Dictionary) -> String:
	var weights: Dictionary = theme.get("start", {}).get("chassis_weights", {})
	var total := 0
	for key in weights:
		total += int(weights[key])
	if total <= 0:
		return "standard"
	var roll := randi() % total
	for key in weights:
		roll -= int(weights[key])
		if roll < 0:
			return key
	return "standard"


# Picks a random catalog part id for an armor slot (lowest tier always exists).
static func roll_armor_part(slot: String) -> String:
	if GlobalData.armor_catalog.has(slot) and GlobalData.armor_catalog[slot].size() > 0:
		return str(GlobalData.armor_catalog[slot][0].get("id", ""))
	return ""


# Picks a frame id for a slot weighted by part_tier_weights.
# frame_catalog[slot] is ordered: [standard, valkyrion, medium, heavy] per slot.
static func roll_frame(slot: String, tier_weights: Dictionary) -> String:
	var entries: Array = GlobalData.frame_catalog.get(slot, [])
	if entries.is_empty():
		return ""
	var tier_order := ["standard", "valkyrion", "medium", "heavy"]
	var total := 0
	for tier in tier_order:
		total += int(tier_weights.get(tier, 0))
	if total <= 0:
		return str(entries[0].get("id", ""))
	var roll := randi() % total
	var index := 0
	for tier in tier_order:
		var w := int(tier_weights.get(tier, 0))
		if roll < w:
			index = tier_order.find(tier)
			break
		roll -= w
	index = clampi(index, 0, entries.size() - 1)
	return str(entries[index].get("id", ""))


# Rolls and installs a random starting loadout for the current theme.
static func roll_random_start() -> void:
	var theme = ThemeSystem.get_run_theme()
	if theme.is_empty():
		return
	var start: Dictionary = theme.get("start", {})

	# Chassis.
	GlobalData.weapons.chassis_id = roll_weighted_chassis(theme)

	# Armor + frames per slot.
	GlobalData.weapons.equipped_parts.clear()
	GlobalData.weapons.part_damage.clear()
	GlobalData.weapons.part_hit_meta.clear()
	GlobalData.weapons.armor_inventory.clear()
	GlobalData.weapons.equipped_frames.clear()
	var tier_weights: Dictionary = start.get("part_tier_weights", {})
	for slot in GlobalData.MECHA_SLOTS:
		var armor_id := roll_armor_part(slot)
		if armor_id != "":
			var inst := ArmorSystem.make_armor_instance_from_catalog(armor_id)
			if not inst.is_empty():
				ArmorSystem.equip_armor_instance(inst["uid"], slot)
		var frame_id := roll_frame(slot, tier_weights)
		if frame_id != "":
			GlobalData.weapons.equipped_frames[slot] = ArmorSystem.get_frame_catalog_entry(frame_id)
	GlobalData.weapons._ensure_default_frames()

	# Weapons.
	var pool: Array = start.get("weapon_pool", [])
	if pool.is_empty():
		pool = [GlobalData.DEFAULT_LEFT_WEAPON_PATH, GlobalData.DEFAULT_RIGHT_WEAPON_PATH, GlobalData.DEFAULT_CARRY_WEAPON_PATH]
	var valid: Array = []
	for p in pool:
		if p is String and ResourceLoader.exists(p):
			valid.append(p)
	# A weapon model may only be equipped once (left hand, right hand, back
	# carry), so the rolled left-hand pick must stay distinct from the fixed
	# right-hand and back-carry defaults.
	var right_path: String = GlobalData.DEFAULT_RIGHT_WEAPON_PATH
	var carry_path: String = GlobalData.DEFAULT_CARRY_WEAPON_PATH
	var left_pool: Array = []
	for p in valid:
		if str(p) != right_path and str(p) != carry_path:
			left_pool.append(p)
	if left_pool.is_empty():
		left_pool = valid
	var left_path: String = left_pool[randi() % left_pool.size()] if not left_pool.is_empty() else GlobalData.DEFAULT_LEFT_WEAPON_PATH
	# Each copy is a stash INSTANCE; the loadout references the copies by uid so
	# equipping one copy never marks its same-model siblings as equipped.
	GlobalData.weapons.weapon_inventory.clear()
	var left_uid := ""
	var right_uid := ""
	var carry_uid := ""
	for path in [left_path, right_path, carry_path]:
		if path is String and path != "":
			var uid := LoadoutSystem.register_weapon(path, "Starter")
			if left_uid == "" and str(path) == left_path:
				left_uid = uid
			elif right_uid == "" and str(path) == right_path:
				right_uid = uid
			elif carry_uid == "" and str(path) == carry_path:
				carry_uid = uid
	GlobalData.weapons.weapon_loadout["left"] = left_uid
	GlobalData.weapons.weapon_loadout["right"] = right_uid
	GlobalData.weapons.weapon_loadout["carry"] = [carry_uid]

	# Allies.
	GlobalData.hangar.fleet_roster.clear()
	var allies: Dictionary = start.get("allies", {})
	var templates: Array = allies.get("templates", [])
	var min_a := int(allies.get("min", 0))
	var max_a := int(allies.get("max", min_a))
	if not templates.is_empty():
		var count := randi_range(min_a, max_a)
		var shuffled := templates.duplicate()
		shuffled.shuffle()
		for tpl in shuffled.slice(0, count):
			FleetSystem.add_ally_unit(str(tpl))

	# Resources.
	var credits_range: Array = start.get("credits", [100, 150])
	var scrap_range: Array = start.get("scrap", [0, 10])
	var cores_range: Array = start.get("data_cores", [0, 0])
	GlobalData.currency.credits = randi_range(int(credits_range[0]), int(credits_range[1]))
	GlobalData.currency.scrap = randi_range(int(scrap_range[0]), int(scrap_range[1]))
	GlobalData.currency.data_cores = randi_range(int(cores_range[0]), int(cores_range[1]))
	HangarManager.ensure_roster()
	HangarManager.save_active()

	# Procedural Lore, Rival Behind-The-Scenes Progression & Era Progression
	ProceduralLoreSystem.initialize_run_lore()
	RivalProgressionSystem.reset()
	EraProgressionSystem.reset()
	CampaignTurnExecutive.reset()
	FactionSystem.reset_relations()
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	GlobalData.current_campaign_scenario_id = ""


# -----------------------------------------------------------------------------
# CAMPAIGN SCENARIO START CONTRACT (Phase 5AE)
# -----------------------------------------------------------------------------

const CANONICAL_SCENARIO_CATALOG_PATH := "res://resources/data/scenario_definition_catalog.tres"
const ScenarioCatalogScript = preload("res://resources/data/scenario_catalog_data.gd")
const ScenarioDefScript = preload("res://resources/data/scenario_definition.gd")
const ScenarioSchemaValidatorScript = preload("res://scripts/systems/scenario_schema_validator.gd")
const CampaignScenarioInitializerScript = preload("res://scripts/systems/campaign_scenario_initializer.gd")


## Returns the active campaign scenario ID from the authoritative run state.
static func get_current_campaign_scenario_id() -> String:
	return GlobalData.current_campaign_scenario_id


## Starts a Campaign V2 run from a selected scenario ID.
## Contract:
##   selected_scenario_id
##           ↓
##   ScenarioCatalog lookup
##           ↓
##   ScenarioDefinition
##           ↓
##   ScenarioSchemaValidator.validate(...)
##           ↓
##   CampaignScenarioInitializer.apply_scenario(...)
##           ↓
##   campaign runtime publication
##
## Invariants:
##   - Rejects empty, unknown, or schema-invalid scenario selections safely.
##   - Never falls back to arbitrary defaults or speculative fixtures.
##   - Atomic: failures leave zero partial campaign runtime state.
##   - Never mutates or replaces RunTheme.
##   - Never embeds board_seed into ScenarioDefinition.
##   - Never creates Player CampaignForce.
##   - ScenarioDefinition remains unmutated (read-only authoring data).
static func start_campaign_scenario(
	scenario_id: String,
	catalog: ScenarioCatalogData = null,
	sector: int = 1
) -> Dictionary:
	var clean_id := scenario_id.strip_edges()
	if clean_id.is_empty():
		return {
			"ok": false,
			"started": false,
			"reason": "missing_scenario_id",
			"scenario_id": "",
			"errors": ["Scenario ID cannot be empty."],
		}

	var active_catalog: ScenarioCatalogData = catalog
	if active_catalog == null:
		if ResourceLoader.exists(CANONICAL_SCENARIO_CATALOG_PATH):
			active_catalog = load(CANONICAL_SCENARIO_CATALOG_PATH) as ScenarioCatalogData
	if active_catalog == null:
		return {
			"ok": false,
			"started": false,
			"reason": "catalog_not_found",
			"scenario_id": clean_id,
			"errors": ["Scenario catalog could not be loaded."],
		}

	var scenario: Resource = active_catalog.get_scenario(clean_id)
	if scenario == null:
		return {
			"ok": false,
			"started": false,
			"reason": "unknown_scenario",
			"scenario_id": clean_id,
			"errors": ["Scenario '%s' not found in catalog." % clean_id],
		}

	var validation: Dictionary = ScenarioSchemaValidatorScript.validate_scenario(scenario, active_catalog)
	if not validation.get("valid", false):
		return {
			"ok": false,
			"started": false,
			"reason": "validation_failed",
			"scenario_id": clean_id,
			"errors": validation.get("errors", []),
		}

	# Prepare clean state before applying scenario to ensure atomicity
	_clear_campaign_runtime_state()

	# Apply initial faction relationships from authored scenario
	var rels: Dictionary = {}
	if scenario.has_method("get_initial_relationships"):
		rels = scenario.get_initial_relationships()
	elif "initial_relationships" in scenario:
		var raw_rels = scenario.get("initial_relationships")
		if raw_rels is Dictionary:
			rels = raw_rels
	for pair_key in rels:
		var pair_str := str(pair_key)
		var colon_idx := pair_str.find(":")
		if colon_idx != -1:
			var fac_a := pair_str.substr(0, colon_idx).strip_edges()
			var fac_b := pair_str.substr(colon_idx + 1).strip_edges()
			var val := int(rels[pair_key])
			if FactionSystem.has_faction(fac_a) and FactionSystem.has_faction(fac_b):
				FactionSystem.set_relation(fac_a, fac_b, val)

	# Initialize runtime state via CampaignScenarioInitializer
	var init_res: Dictionary = CampaignScenarioInitializerScript.apply_scenario(scenario, sector)
	if not init_res.get("ok", false) or not init_res.get("applied", false):
		# Rollback on failure to guarantee atomicity: no partial runtime state remains
		_clear_campaign_runtime_state()
		return {
			"ok": false,
			"started": false,
			"reason": "initialization_failed",
			"scenario_id": clean_id,
			"errors": init_res.get("errors", []),
		}

	# Publish active scenario ID to authoritative run identity
	GlobalData.current_campaign_scenario_id = clean_id

	return {
		"ok": true,
		"started": true,
		"reason": "success",
		"scenario_id": clean_id,
		"scenario": scenario,
		"forces_created": init_res.get("forces_created", []),
		"nodes_created": init_res.get("nodes_created", []),
		"territories_created": init_res.get("territories_created", []),
		"bases_created": init_res.get("bases_created", []),
	}


static func _clear_campaign_runtime_state() -> void:
	CampaignTurnExecutive.reset()
	FactionSystem.reset_relations()
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	GlobalData.current_campaign_scenario_id = ""
