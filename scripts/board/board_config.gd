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

# Energy cost per terrain cell (GDD §3.1).
# Road = 10, Off-road/Mud/Sand = 25, Roller on Road = 5.
const TERRAIN_ENERGY: Dictionary = {
	"road": 10.0,
	"bridge": 10.0,
	"plain": 20.0,
	"sand": 25.0,
	"forest": 25.0,
	"water": 0.0,
	"rock": 0.0,
}

# Enemy Fleet Archetypes (GDD §3.3)
const FLEET_ARCHETYPES: Dictionary = {
	"recon": {
		"name": "Recon Fleet",
		"mp": 4,
		"aces": 0,
		"tags": ["Roller-Dash", "Light-Armor"],
		"bombard_range": 0,
		"desc": "High-mobility scout fleet. Patrols fast with roller-dash legs.",
	},
	"armored": {
		"name": "Armored Fleet",
		"mp": 1,
		"aces": 0,
		"tags": ["Heavy-Armor", "Shield"],
		"bombard_range": 0,
		"desc": "Heavy frontline battle group. High armor and defensive shields.",
	},
	"artillery": {
		"name": "Artillery Fleet",
		"mp": 1,
		"aces": 0,
		"tags": ["Missile-Pod", "Railgun"],
		"bombard_range": 2,
		"desc": "Long-range fire support unit. Bombards nearby convoy positions on the board.",
	},
	"hunter_killer": {
		"name": "Hunter-Killer Fleet",
		"mp": 3,
		"aces": 1,
		"tags": ["High-Tech", "Tier-2-3"],
		"bombard_range": 0,
		"desc": "Elite assassination unit deployed at high threat levels. Heavy synergy loadouts.",
	},
	"boss": {
		"name": "Sector Supreme Commander",
		"mp": 2,
		"aces": 2,
		"tags": ["Boss", "Prototype-Chassis", "Overclocked-Core"],
		"bombard_range": 3,
		"desc": "Apex Sector Commander. Roams inside the fog with prototype heavy ordnance and escorts.",
	},
}

static func energy_cost(terrain: String, is_roller: bool = false) -> float:
	if is_roller:
		if terrain in ["road", "bridge"]:
			return 5.0 # Roller Dash mode on paved road: -5 Energy
		else:
			return 35.0 # Roller Dash off-road penalty: -35 Energy
	return float(TERRAIN_ENERGY.get(terrain, 20.0))

# Default grid dimensions for a sector's open board (expanded for strategic breath and open spaces).
const GRID_SIZE: int = 25

# Per-theme weighted terrain pools used by the generator's seeded RNG.
const THEME_TERRAIN: Dictionary = {
	# Suburb (chánmeuang): paved streets + houses with patches of lawn, only a
	# FEW trees — kept visually distinct from the FOREST map so a suburb board
	# never reads as a jungle (its arena is the crossroads city, not the woods).
	"suburb": [
		["plain", 5], ["road", 4], ["rock", 2], ["forest", 1],
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
	"forest": "FOREST",
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
			return "desert" if (GlobalData.board.board_seed % 2 == 0) else "forest"
		_:
			return "urban"


# Per-theme harmonious color palettes for terrain tiles so the board displays
# a unified, eye-friendly landscape matching each sector biome.
const THEME_PALETTES: Dictionary = {
	"suburb": {
		"road": Color(0.30, 0.32, 0.35),
		"plain": Color(0.42, 0.54, 0.34),
		"sand": Color(0.68, 0.60, 0.44),
		"forest": Color(0.24, 0.42, 0.25),
		"water": Color(0.18, 0.45, 0.70),
		"bridge": Color(0.48, 0.40, 0.30),
		"rock": Color(0.36, 0.35, 0.33),
	},
	"desert": {
		"road": Color(0.45, 0.42, 0.38),
		"plain": Color(0.64, 0.56, 0.38),
		"sand": Color(0.80, 0.70, 0.46),
		"forest": Color(0.35, 0.50, 0.30),
		"water": Color(0.15, 0.52, 0.68),
		"bridge": Color(0.50, 0.38, 0.28),
		"rock": Color(0.55, 0.38, 0.30),
	},
	"forest": {
		"road": Color(0.32, 0.30, 0.26),
		"plain": Color(0.34, 0.52, 0.30),
		"sand": Color(0.65, 0.60, 0.45),
		"forest": Color(0.18, 0.38, 0.20),
		"water": Color(0.14, 0.42, 0.65),
		"bridge": Color(0.42, 0.32, 0.22),
		"rock": Color(0.32, 0.34, 0.30),
	},
	"urban": {
		"road": Color(0.25, 0.27, 0.30),
		"plain": Color(0.38, 0.48, 0.32),
		"sand": Color(0.62, 0.55, 0.42),
		"forest": Color(0.22, 0.40, 0.24),
		"water": Color(0.16, 0.40, 0.62),
		"bridge": Color(0.38, 0.39, 0.42),
		"rock": Color(0.30, 0.31, 0.33),
	},
}

static func terrain_color(terrain: String, theme_id: String = "suburb") -> Color:
	var palette: Dictionary = THEME_PALETTES.get(theme_id, THEME_PALETTES["suburb"])
	return palette.get(terrain, Color(0.45, 0.48, 0.40))


static func move_cost(terrain: String) -> int:
	return int(TERRAIN.get(terrain, 1))


static func is_passable(terrain: String) -> bool:
	return int(TERRAIN.get(terrain, 1)) > 0


static func get_objective(theme_id: String) -> Dictionary:
	var obj: Dictionary = OBJECTIVES.get(theme_id, OBJECTIVES["suburb"])
	return obj.duplicate()

