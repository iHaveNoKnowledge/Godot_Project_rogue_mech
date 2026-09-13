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
	"urban": 2,
	"bridge": 1,
	"rock": 3,
	"water": -1,
}

# Energy cost per terrain cell (GDD §3.1).
# Road = 10, Off-road/Mud/Sand = 25, Roller on Road = 5.
const TERRAIN_ENERGY: Dictionary = {
	"road": 10.0,
	"bridge": 10.0,
	"plain": 20.0,
	"urban": 20.0,
	"sand": 25.0,
	"forest": 25.0,
	"rock": 35.0,
	"water": 0.0,
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

# Default grid dimensions for a sector's open board (expanded for strategic extraction runs).
const GRID_SIZE: int = 35

# -----------------------------------------------------------------------------
# EXTRACTION CONTRACTS
# Procedural contracts offered at the start of a sector run. Each contract defines
# a Primary Objective, optional Secondaries, Min/Max Heat stars, and extraction rewards.
# -----------------------------------------------------------------------------
const EXTRACTION_CONTRACTS: Dictionary = {
	"destroy_comms": {
		"id": "destroy_comms",
		"name": "Operation: Blackout Relay",
		"theme": "suburb",
		"desc": "Infiltrate deep behind enemy lines and demolish the regional Comms Relay Array. Once communications are severed, reach the extraction LZ before airborne hunter squads locate your signal.",
		"primary": {
			"id": "destroy_relay",
			"name": "Demolish Comms Array",
			"target_tile_type": "comms_relay",
			"desc": "Locate and neutralize the fortified Comms Relay Array facility."
		},
		"secondaries": [
			{"id": "hack_intel", "name": "Extract Encryption Core", "target_tile_type": "data_node", "desc": "Hack an auxiliary data terminal (+150 cr, +2 Cores).", "reward_credits": 150, "reward_scrap": 20},
			{"id": "destroy_patrol", "name": "Silence Patrol Vanguard", "desc": "Eliminate at least 2 hostile patrol fleets (+100 cr).", "target_count": 2, "reward_credits": 100, "reward_scrap": 30}
		],
		"min_heat": 2,
		"max_heat": 5,
		"reward_credits": 600,
		"reward_scrap": 80,
	},
	"prototype_heist": {
		"id": "prototype_heist",
		"name": "Operation: Stolen Core",
		"theme": "desert",
		"desc": "A convoy transporting a prototype energy reactor has broken down in the desert wastes. Recover the prototype reactor core and bring it safely to the extraction LZ.",
		"primary": {
			"id": "secure_core",
			"name": "Recover Prototype Core",
			"target_tile_type": "prototype_vault",
			"desc": "Breach the secure vault and secure the prototype core."
		},
		"secondaries": [
			{"id": "scav_cache", "name": "Raid Scavenger Stash", "target_tile_type": "salvage_cache", "desc": "Loot an abandoned military supply cache (+120 cr, +40 scrap).", "reward_credits": 120, "reward_scrap": 40},
			{"id": "survey_dunes", "name": "Reconnaissance Survey", "desc": "Map at least 8 unknown sectors (+80 cr).", "target_count": 8, "reward_credits": 80, "reward_scrap": 15}
		],
		"min_heat": 1,
		"max_heat": 4,
		"reward_credits": 500,
		"reward_scrap": 100,
	},
	"assassinate_warlord": {
		"id": "assassinate_warlord",
		"name": "Operation: Apex Hunt",
		"theme": "urban",
		"desc": "A notorious enemy ace warlord is coordinating sector defense from an urban stronghold. Eliminate the target and break through the subsequent high-alert blockade to extract.",
		"primary": {
			"id": "kill_warlord",
			"name": "Assassinate Ace Warlord",
			"target_tile_type": "enemy_base",
			"desc": "Engage and destroy the warlord's elite command detachment."
		},
		"secondaries": [
			{"id": "rescue_operative", "name": "Extract Captured Informant", "target_tile_type": "safehouse", "desc": "Rescue the trapped syndicate spy (+200 cr).", "reward_credits": 200, "reward_scrap": 25},
			{"id": "demolish_depot", "name": "Burn Ammo Stockpile", "target_tile_type": "supply_depot", "desc": "Detonate the weapons stockpile to weaken reinforcements (+100 cr).", "reward_credits": 100, "reward_scrap": 50}
		],
		"min_heat": 3,
		"max_heat": 5,
		"reward_credits": 850,
		"reward_scrap": 120,
	}
}

static func get_contracts_for_sector(sector: int) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for k in EXTRACTION_CONTRACTS:
		var c: Dictionary = EXTRACTION_CONTRACTS[k].duplicate(true)
		# Scale payout slightly by sector tier
		var mult: float = 1.0 + float(sector - 1) * 0.35
		c["reward_credits"] = int(float(c.get("reward_credits", 500)) * mult)
		c["reward_scrap"] = int(float(c.get("reward_scrap", 50)) * mult)
		list.append(c)
	return list

# -----------------------------------------------------------------------------
# SUB-ZONES (Micro-Biomes)
# Each sector theme is partitioned into organic sub-zones (districts/micro-biomes)
# that provide varied terrain generation on the board and drive matching 3D combat arenas.
# -----------------------------------------------------------------------------
const SUB_ZONES: Dictionary = {
	# --- Suburb Sub-Zones ---
	"suburb_village": {
		"id": "suburb_village",
		"theme": "suburb",
		"name": "Residential Village",
		"name_th": "หมู่บ้านชานเมือง",
		"desc": "Dense suburban neighborhoods with paved street grids, housing estates, and alley cover.",
		"terrain_weights": [["road", 5], ["rock", 4], ["plain", 3], ["forest", 1]],
		"arena_preset": "SUBURB_VILLAGE",
	},
	"suburb_meadow": {
		"id": "suburb_meadow",
		"theme": "suburb",
		"name": "Open Meadow",
		"name_th": "ทุ่งหญ้าชานเมือง",
		"desc": "Expansive green grasslands with gentle rolling knolls and wide sightlines.",
		"terrain_weights": [["plain", 7], ["forest", 2], ["rock", 1], ["road", 1]],
		"arena_preset": "SUBURB_MEADOW",
	},
	"suburb_water": {
		"id": "suburb_water",
		"theme": "suburb",
		"name": "Wetland & Lakefront",
		"name_th": "ริมน้ำและหนองน้ำชานเมือง",
		"desc": "Waterside lowlands with streams, drainage basins, reed banks, and crossing bridges.",
		"terrain_weights": [["water", 4], ["plain", 4], ["bridge", 2], ["sand", 1]],
		"arena_preset": "SUBURB_WETLAND",
	},

	# --- Urban Sub-Zones ---
	"urban_downtown": {
		"id": "urban_downtown",
		"theme": "urban",
		"name": "Downtown Highrise",
		"name_th": "ใจกลางเมืองตึกระฟ้า",
		"desc": "Towering skyscrapers, high urban density, and tight concrete street canyons.",
		"terrain_weights": [["road", 5], ["rock", 5], ["plain", 2]],
		"arena_preset": "URBAN_DOWNTOWN",
	},
	"urban_industrial": {
		"id": "urban_industrial",
		"theme": "urban",
		"name": "Industrial Logistics Zone",
		"name_th": "เขตอุตสาหกรรมและคลังสินค้า",
		"desc": "Heavy warehouses, storage silos, container stacks, and cargo truck routes.",
		"terrain_weights": [["road", 4], ["rock", 4], ["plain", 2], ["sand", 1]],
		"arena_preset": "URBAN_INDUSTRIAL",
	},
	"urban_park": {
		"id": "urban_park",
		"theme": "urban",
		"name": "Central Metro Park",
		"name_th": "สวนสาธารณะเมืองหลวง",
		"desc": "Open public plazas, manicured lawns, decorative ponds, and memorial statues.",
		"terrain_weights": [["plain", 6], ["forest", 2], ["road", 2], ["water", 1]],
		"arena_preset": "URBAN_PARK",
	},

	# --- Desert Sub-Zones ---
	"desert_dunes": {
		"id": "desert_dunes",
		"theme": "desert",
		"name": "Endless Sand Dunes",
		"name_th": "ทะเลทรายลึก",
		"desc": "Vast ocean of shifting sand dunes with steep crests and low vehicle traction.",
		"terrain_weights": [["sand", 8], ["rock", 2], ["plain", 1]],
		"arena_preset": "DESERT_DUNES",
	},
	"desert_canyon": {
		"id": "desert_canyon",
		"theme": "desert",
		"name": "Rocky Canyon & Badlands",
		"name_th": "หุบเขาหินผา",
		"desc": "Precipitous sandstone bluffs, natural choke points, and rocky ambush terraces.",
		"terrain_weights": [["rock", 6], ["sand", 4], ["road", 1]],
		"arena_preset": "DESERT_CANYON",
	},
	"desert_oasis": {
		"id": "desert_oasis",
		"theme": "desert",
		"name": "Oasis Outpost",
		"name_th": "โอเอซิสและแคมป์เหมือง",
		"desc": "Natural water basin surrounded by date palms, salvaged outposts, and trade tracks.",
		"terrain_weights": [["plain", 4], ["sand", 3], ["water", 2], ["road", 2]],
		"arena_preset": "DESERT_OASIS",
	},

	# --- Forest Sub-Zones ---
	"forest_deep": {
		"id": "forest_deep",
		"theme": "forest",
		"name": "Dense Canopy Forest",
		"name_th": "ป่าทึบ",
		"desc": "Ancient towering trees, thick foliage cover, and restricted long-range ballistic lines.",
		"terrain_weights": [["forest", 7], ["plain", 2], ["rock", 1]],
		"arena_preset": "FOREST_DEEP",
	},
	"forest_river": {
		"id": "forest_river",
		"theme": "forest",
		"name": "River Crossing",
		"name_th": "ลำน้ำแบ่งฟาก",
		"desc": "Wide river dividing the forest banks with vital bridge bottlenecks.",
		"terrain_weights": [["water", 4], ["forest", 3], ["bridge", 2], ["plain", 2]],
		"arena_preset": "FOREST_RIVER",
	},
	"forest_ruins": {
		"id": "forest_ruins",
		"theme": "forest",
		"name": "Logging Camp & Ruins",
		"name_th": "ค่ายตัดไม้และซากปรักหักพัง",
		"desc": "Forested clearings with lumber mills, log yards, and mossy stone ruins.",
		"terrain_weights": [["plain", 4], ["forest", 3], ["rock", 3], ["road", 2]],
		"arena_preset": "FOREST_RUINS",
	},
}

# Per-theme fallback weighted terrain pools used when no sub-zone is active.
const THEME_TERRAIN: Dictionary = {
	"suburb": [
		["plain", 5], ["road", 4], ["rock", 2], ["forest", 1],
	],
	"desert": [
		["sand", 7], ["rock", 2], ["plain", 2],
	],
	"forest": [
		["forest", 5], ["plain", 3], ["sand", 1],
	],
	"urban": [
		["plain", 3], ["road", 4], ["rock", 3],
	],
}

# Returns all sub-zone IDs available for a given theme.
static func sub_zones_for_theme(theme_id: String) -> Array[String]:
	var list: Array[String] = []
	for sz_id in SUB_ZONES:
		if SUB_ZONES[sz_id].get("theme", "") == theme_id:
			list.append(sz_id)
	if list.is_empty():
		list.append(theme_id + "_default")
	return list

# Returns sub-zone data dict or a default fallback.
static func get_sub_zone_info(sub_zone_id: String) -> Dictionary:
	if SUB_ZONES.has(sub_zone_id):
		return SUB_ZONES[sub_zone_id]
	return {
		"id": sub_zone_id,
		"theme": "suburb",
		"name": sub_zone_id.capitalize(),
		"name_th": sub_zone_id,
		"desc": "Standard sector terrain.",
		"terrain_weights": THEME_TERRAIN.get("suburb", []),
		"arena_preset": "CROSSROADS",
	}

# Returns weighted terrain array for a specific sub-zone and theme.
static func terrain_pool_for_sub_zone(sub_zone_id: String, theme_id: String) -> Array:
	if SUB_ZONES.has(sub_zone_id):
		return SUB_ZONES[sub_zone_id].get("terrain_weights", THEME_TERRAIN.get(theme_id, [["plain", 1]]))
	return THEME_TERRAIN.get(theme_id, [["plain", 1]])

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
			var b_seed: int = 0
			if Engine.has_singleton("GlobalData") or is_instance_valid(Engine.get_main_loop()) and Engine.get_main_loop().root and Engine.get_main_loop().root.has_node("GlobalData"):
				var gd = Engine.get_main_loop().root.get_node("GlobalData")
				b_seed = int(gd.board.board_seed)
			return "desert" if (b_seed % 2 == 0) else "forest"
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

