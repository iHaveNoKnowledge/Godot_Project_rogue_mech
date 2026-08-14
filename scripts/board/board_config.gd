class_name BoardConfig
extends RefCounted

# -----------------------------------------------------------------------------
# OPEN-GRID BOARD CONFIG
# Shared static data for the free-movement board: terrain costs, per-theme
# terrain palettes, per-sector map themes, and per-map objectives. Kept out of
# the autoload so GlobalData stays state-only; board scripts read these tables.
# -----------------------------------------------------------------------------

# Movement cost per terrain cell. Impassable cells return -1.
const TERRAIN: Dictionary = {
	"road": 1,
	"plain": 1,
	"sand": 2,
	"forest": 2,
	"bridge": 1,
	"water": -1,
	"rock": -1,
}

# Default grid dimensions for a sector's open board.
const GRID_SIZE: int = 15

# Per-theme weighted terrain pools used by the generator's seeded RNG.
const THEME_TERRAIN: Dictionary = {
	# Suburb (chánmeuang): grass + roads, light forest, a creek, some houses.
	"suburb": [
		["plain", 6], ["road", 3], ["forest", 2], ["rock", 1],
	],
	# Desert: sand everywhere, rocks, oasis plains.
	"desert": [
		["sand", 7], ["rock", 2], ["plain", 2],
	],
	# Forest: heavy trees, river crossing with bridges.
	"forest": [
		["forest", 5], ["plain", 3], ["sand", 1],
	],
	# Urban: asphalt grid of roads + building blocks, some parks.
	"urban": [
		["plain", 3], ["road", 4], ["rock", 3],
	],
}

# Which arena BiomeTheme (see arena_generator.gd) matches each board map theme.
const THEME_ARENA: Dictionary = {
	"suburb": "CROSSROADS",
	"desert": "DESERT",
	"forest": "RIVER_BRIDGE",
	"urban": "CITY_HIGHRISE",
}

# Objective per map theme. `progress` advances when the board's trigger fires.
const OBJECTIVES: Dictionary = {
	# Suburb: wipe out patrol fleets until the crossroads are secure.
	"suburb": {"id": "patrol_hunt", "name": "Patrol Hunt", "required": 3,
		"desc": "The crossroads are crawling with patrols. Destroy %d patrol fleets to secure the route."},
	# Desert: reveal the wasteland by exploring new ground.
	"desert": {"id": "survey", "name": "Survey the Wastes", "required": 6,
		"desc": "Map the dunes to find the extraction route. Explore %d new tiles."},
	# Forest: cross the river via the bridges to reach the far side.
	"forest": {"id": "cross_river", "name": "Cross the River", "required": 1,
		"desc": "Reach the far riverbank. Use the bridge tiles to cross the water."},
	# Urban: the enemy research base sits in the city heart — destroy it.
	"urban": {"id": "hq_strike", "name": "HQ Strike", "required": 1,
		"desc": "Destroy the enemy research base in the city to break their counter-unit."},
}

# Sector -> map theme. Sector 2 alternates desert/forest by board seed.
static func theme_for_sector(sector: int) -> String:
	match sector:
		1:
			return "suburb"
		2:
			return "desert" if (GlobalData.board_seed % 2 == 0) else "forest"
		_:
			return "urban"


static func move_cost(terrain: String) -> int:
	return int(TERRAIN.get(terrain, 1))


static func is_passable(terrain: String) -> bool:
	return int(TERRAIN.get(terrain, 1)) > 0


static func get_objective(theme_id: String) -> Dictionary:
	var obj: Dictionary = OBJECTIVES.get(theme_id, OBJECTIVES["suburb"])
	return obj.duplicate()
