class_name CampaignForceInitializer
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN FORCE INITIALIZER — Phase 5X (minimal deterministic initial population).
##
## Audit evidence:
##   - CampaignForce producer was NONE; initial population was ZERO.
##   - register_force() was explicit low-level authority only.
##   - Patrols (BoardState.board_patrols, PatrolSystem) have board-local identity,
##     churning IDs, encounter-stance labels ("hostile"/"unknown"), and tactical
##     rosters; DO NOT BRIDGE PATROL -> CAMPAIGNFORCE.
##   - Player hangar/fleet/pilot roster has separate ownership; DO NOT FABRICATE
##     PLAYER FORCE.
##   - Initial population must be deterministic, minimal (1-N NPC forces),
##     anchored to canonical FactionSystem and CampaignNodeRegistry nodes.
##
## Responsibilities:
##   - Register deterministic initial CampaignForce records during run
##     initialization (Option B).
##   - Idempotent: repeated initialization produces the same population without duplicates.
##   - Pure creator: does NOT move forces, advance turns, resolve battles,
##     mutate territory/base, simulate supply/detection/orders/AI.
## ---------------------------------------------------------------------------

const DEFAULT_FORCE_SPECS: Array[Dictionary] = [
	{
		"slug": "patrol_alpha",
		"force_type": "PATROL",
		"faction": "zeon",
		"preferred_node_type": "CITY",
		"fallback_node_type": "SAFEHOUSE",
		"unit_count": 2,
		"strength": 20,
	},
	{
		"slug": "convoy_beta",
		"force_type": "CONVOY",
		"faction": "federation",
		"preferred_node_type": "FUEL_DEPOT",
		"fallback_node_type": "START",
		"unit_count": 3,
		"strength": 30,
	},
	{
		"slug": "scavenger_gamma",
		"force_type": "SCAVENGER",
		"faction": "scavenger",
		"preferred_node_type": "SAFEHOUSE",
		"fallback_node_type": "RESEARCH_LAB",
		"unit_count": 1,
		"strength": 10,
	},
]


## Returns the default deterministic initial force specifications.
static func get_default_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in DEFAULT_FORCE_SPECS:
		out.append(s.duplicate(true))
	return out


## Resolves a deterministic node_id for a spec from existing nodes in CampaignNodeRegistry.
## Returns "" if no nodes are registered.
static func resolve_node_for_spec(spec: Dictionary, index: int = 0) -> String:
	var nodes := CampaignNodeRegistry.get_nodes()
	if nodes.is_empty():
		return ""

	nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)

	var preferred := str(spec.get("preferred_node_type", ""))
	if preferred != "":
		var pref_matches: Array = []
		for n in nodes:
			if str(n.get("node_type", "")) == preferred:
				pref_matches.append(n)
		if not pref_matches.is_empty():
			var pick: Dictionary = pref_matches[index % pref_matches.size()]
			return str(pick.get("id", ""))

	var fallback := str(spec.get("fallback_node_type", ""))
	if fallback != "":
		var fb_matches: Array = []
		for n in nodes:
			if str(n.get("node_type", "")) == fallback:
				fb_matches.append(n)
		if not fb_matches.is_empty():
			var pick: Dictionary = fb_matches[index % fb_matches.size()]
			return str(pick.get("id", ""))

	var fallback_pick: Dictionary = nodes[index % nodes.size()]
	return str(fallback_pick.get("id", ""))


## Resolves base_id for a spec. If an explicit base_id exists and is registered,
## returns it. Otherwise, if the node hosts a registered live base, returns it.
## Returns "" if no base is found or registered.
static func resolve_base_for_spec(spec: Dictionary, node_id: String) -> String:
	var explicit_base := str(spec.get("base_id", ""))
	if explicit_base != "" and CampaignBase.has_base(explicit_base):
		return explicit_base
	if node_id != "":
		var base_rec := CampaignBase.get_base_at_node(node_id)
		if not base_rec.is_empty():
			return str(base_rec.get("id", ""))
	return ""


## Registers deterministic initial CampaignForce records for the given sector.
## Uses custom_specs if provided, otherwise DEFAULT_FORCE_SPECS.
## Returns Array of registered force IDs.
static func initialize_campaign_forces(sector: int = 1, custom_specs: Array = []) -> Array:
	var specs_to_use: Array = custom_specs if not custom_specs.is_empty() else DEFAULT_FORCE_SPECS
	var registered_ids: Array = []

	for i in range(specs_to_use.size()):
		var spec: Dictionary = specs_to_use[i]
		var slug := str(spec.get("slug", ""))
		if slug == "":
			slug = "force_%d" % i
		var fid := CampaignForce.make_force_id(sector, slug)
		if fid == "":
			continue

		# If already registered, preserve existing state without duplicating
		if CampaignForce.has_force(fid):
			var existing := CampaignForce.get_force(fid)
			if str(existing.get("node_id", "")) == "":
				var nid := resolve_node_for_spec(spec, i)
				if nid != "":
					CampaignForce.set_node(fid, nid)
					var bid := resolve_base_for_spec(spec, nid)
					if bid != "":
						CampaignForce.set_base(fid, bid)
			registered_ids.append(fid)
			continue

		var force_type := str(spec.get("force_type", "PATROL"))
		var faction_id := str(spec.get("faction", ""))
		if faction_id != "" and not FactionSystem.has_faction(faction_id):
			faction_id = ""

		var node_id := str(spec.get("node_id", ""))
		if node_id == "" or not CampaignNodeRegistry.has_node(node_id):
			node_id = resolve_node_for_spec(spec, i)

		var base_id := resolve_base_for_spec(spec, node_id)
		var unit_count := maxi(int(spec.get("unit_count", 1)), 0)
		var strength := maxi(int(spec.get("strength", 10)), 0)

		var res_id := CampaignForce.register_force(
			fid,
			force_type,
			faction_id,
			node_id,
			base_id,
			unit_count,
			strength
		)
		if res_id != "":
			registered_ids.append(res_id)

	return registered_ids
