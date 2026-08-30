class_name ScavengerSystem
extends RefCounted

## ---------------------------------------------------------------------------
## SCAVENGER FACTION & BATTLEFIELD WRECKAGE SYSTEM
##
## Features:
##   1. Wreckage Tile Tracking:
##      - When a battle leaves unrecovered loot/weapons on a board tile, a
##        Wreckage Marker is placed at that tile coordinate (Vector2i).
##      - Visiting the tile allows the player to salvage their left-behind gear.
##
##   2. Scavenger Camps (POIs):
##      - Camps accumulate Manpower (MP) over turns and by looting wrecks.
##      - When manpower reaches threshold (e.g. 15-20 MP), the camp dispatches
##        a roaming Scavenger Fleet Token onto the map.
##
##   3. Roaming Scavenger Fleets (🏴‍☠️ Yellow/Orange Faction):
##      - Move across the board hunting for wreckage tiles, convoys, and scrap.
##      - Collision with AI Factions (Red Hostiles / Blue Allies) triggers
##        an auto-resolved battle calculation with casualty logs.
##      - Collision with Player triggers real-time combat in arena.
##      - Defeating a Scavenger fleet/camp reclaims all accumulated stolen loot!
## ---------------------------------------------------------------------------

const SCAV_ARCHETYPES := ["scav_raider", "scav_scrapper", "scav_warlord"]

# Camp data structure: { id, pos: Vector2i, name, manpower: int, max_manpower: int, stolen_loot: Array, active_fleets: int }
# Wreckage data structure: { pos: Vector2i, items: Array, scrap: int }


static func get_camps() -> Array:
	if not GlobalData.board.has_meta("scavenger_camps"):
		GlobalData.board.set_meta("scavenger_camps", [])
	return GlobalData.board.get_meta("scavenger_camps")


static func set_camps(camps: Array) -> void:
	GlobalData.board.set_meta("scavenger_camps", camps)


static func get_tile_wreckages() -> Dictionary:
	if not GlobalData.board.has_meta("tile_wreckages"):
		GlobalData.board.set_meta("tile_wreckages", {})
	return GlobalData.board.get_meta("tile_wreckages")


static func set_tile_wreckages(dict: Dictionary) -> void:
	GlobalData.board.set_meta("tile_wreckages", dict)


## Registers dropped / unrecovered items on a board tile as a Wreckage Marker
static func register_tile_wreckage(tile_pos: Vector2i, items: Array, scrap: int = 0) -> void:
	if items.is_empty() and scrap <= 0:
		return
	var wreckages := get_tile_wreckages()
	var key := "%d,%d" % [tile_pos.x, tile_pos.y]
	if not wreckages.has(key):
		wreckages[key] = {"pos_x": tile_pos.x, "pos_y": tile_pos.y, "items": [], "scrap": 0}

	for item in items:
		wreckages[key]["items"].append(item)
	wreckages[key]["scrap"] = int(wreckages[key].get("scrap", 0)) + scrap
	set_tile_wreckages(wreckages)


## Clears wreckage at a tile after the player (or scavengers) loot it
static func claim_tile_wreckage(tile_pos: Vector2i) -> Dictionary:
	var wreckages := get_tile_wreckages()
	var key := "%d,%d" % [tile_pos.x, tile_pos.y]
	if wreckages.has(key):
		var data = wreckages[key]
		wreckages.erase(key)
		set_tile_wreckages(wreckages)
		return data
	return {}


static func has_wreckage_at(tile_pos: Vector2i) -> bool:
	var wreckages := get_tile_wreckages()
	var key := "%d,%d" % [tile_pos.x, tile_pos.y]
	return wreckages.has(key) and (!wreckages[key].get("items", []).is_empty() or int(wreckages[key].get("scrap", 0)) > 0)


static func get_wreckage_at(tile_pos: Vector2i) -> Dictionary:
	var wreckages := get_tile_wreckages()
	var key := "%d,%d" % [tile_pos.x, tile_pos.y]
	return wreckages.get(key, {})


static func _get_tile_terrain(tile: Variant) -> String:
	if tile is Dictionary:
		return str((tile as Dictionary).get("terrain", (tile as Dictionary).get("type", "plain")))
	if tile is Object and is_instance_valid(tile):
		if "terrain" in tile:
			return str(tile.terrain)
		if tile.has_meta("terrain"):
			return str(tile.get_meta("terrain"))
		if "tile_type" in tile:
			return str(tile.tile_type)
	return "plain"


## Spawns initial Scavenger Camps on the board
static func ensure_camps(board_tiles: Dictionary, count: int = 2) -> void:
	var camps: Array = get_camps()
	if not camps.is_empty():
		return

	var candidates: Array[Vector2i] = []
	for pos in board_tiles:
		var tile = board_tiles[pos]
		var t_type := _get_tile_terrain(tile)
		# Place camps away from player start (0, 0) in wilderness / ruins
		if pos != Vector2i.ZERO and pos.length() >= 5.0 and t_type in ["plain", "sand", "forest", "rock"]:
			candidates.append(pos)

	candidates.shuffle()
	var names := ["Rustfang Outpost", "Scrap-Den Alpha", "Junk Maw Stronghold", "Iron Vulture Nest"]

	for i in range(mini(count, candidates.size())):
		var pos = candidates[i]
		var camp := {
			"id": "scav_camp_%d" % i,
			"pos_x": pos.x,
			"pos_y": pos.y,
			"name": names[i % names.size()],
			"manpower": randi_range(6, 12),
			"max_manpower": 20,
			"spawn_threshold": 16,
			"stolen_loot": [],
			"active_fleets": 0
		}
		camps.append(camp)

	set_camps(camps)


## Called each turn/day: increases camp manpower and dispatches fleets when ready
static func advance_turn(board_tiles: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var camps: Array = get_camps()

	for camp in camps:
		var mp: int = int(camp.get("manpower", 10))
		var max_mp: int = int(camp.get("max_manpower", 20))
		var threshold: int = int(camp.get("spawn_threshold", 16))

		# Natural growth (+1 to +2 MP per turn)
		mp = mini(mp + randi_range(1, 2), max_mp)
		camp["manpower"] = mp

		# If threshold reached and not exceeding max fleets, dispatch a fleet
		if mp >= threshold and int(camp.get("active_fleets", 0)) < 2:
			var dispatch_cost := 10
			camp["manpower"] = mp - dispatch_cost
			camp["active_fleets"] = int(camp.get("active_fleets", 0)) + 1
			var fleet = _spawn_scavenger_fleet(camp, board_tiles)
			if not fleet.is_empty():
				events.append({
					"type": "scavenger_fleet_spawned",
					"camp_name": camp.get("name", "Scavenger Camp"),
					"pos": Vector2i(camp.get("pos_x", 0), camp.get("pos_y", 0)),
					"fleet": fleet
				})

	set_camps(camps)
	return events


static func _spawn_scavenger_fleet(camp: Dictionary, board_tiles: Dictionary) -> Dictionary:
	var home_pos := Vector2i(camp.get("pos_x", 0), camp.get("pos_y", 0))
	var fleet_id := "scav_fleet_%d" % Time.get_ticks_msec()
	var fleet := {
		"id": fleet_id,
		"pos": home_pos,
		"home": home_pos,
		"name": "Scavenger Raiders (%s)" % camp.get("name", "Clan"),
		"faction": "scavenger",
		"grunts": randi_range(2, 3),
		"aces": 1 if randf() < 0.3 else 0,
		"archetype": "scav_raider",
		"aggro": true,
		"camp_id": camp.get("id", ""),
		"carried_scrap": randi_range(10, 25),
		"carried_loot": []
	}

	# Add to GlobalData.board.board_patrols
	if not (GlobalData.board.board_patrols is Array):
		GlobalData.board.board_patrols = []
	GlobalData.board.board_patrols.append(fleet)
	return fleet


## Resolves an auto-battle when a Scavenger Fleet collides with an AI Enemy or Ally token
static func resolve_auto_battle(fleet_a: Dictionary, fleet_b: Dictionary) -> Dictionary:
	var name_a := str(fleet_a.get("name", "Faction A"))
	var name_b := str(fleet_b.get("name", "Faction B"))
	var grunts_a := int(fleet_a.get("grunts", 1))
	var aces_a := int(fleet_a.get("aces", 0))
	var power_a := grunts_a * 10 + aces_a * 25 + randi_range(-5, 5)

	var grunts_b := int(fleet_b.get("grunts", 1))
	var aces_b := int(fleet_b.get("aces", 0))
	var power_b := grunts_b * 10 + aces_b * 25 + randi_range(-5, 5)

	var winner := ""
	var loser := ""
	var victory_a := power_a >= power_b

	if victory_a:
		winner = name_a
		loser = name_b
		fleet_a["grunts"] = maxi(1, grunts_a - randi_range(0, 1))
		fleet_b["destroyed"] = true
	else:
		winner = name_b
		loser = name_a
		fleet_b["grunts"] = maxi(1, grunts_b - randi_range(0, 1))
		fleet_a["destroyed"] = true

	var scrap_yield := randi_range(8, 20)
	return {
		"winner": winner,
		"loser": loser,
		"victory_a": victory_a,
		"power_a": power_a,
		"power_b": power_b,
		"scrap": scrap_yield,
		"log": "💥 Multi-Faction Clash: %s defeated %s! (+%d Scrap left at site)" % [winner, loser, scrap_yield]
	}
