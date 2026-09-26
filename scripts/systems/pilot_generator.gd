class_name PilotGenerator
extends RefCounted

# -----------------------------------------------------------------------------
# PROCEDURAL PILOT GENERATOR & MASSIVE NAME DATABASE
# Generates randomized pilots with unique names, backgrounds, traits, and perks
# for pilot permadeath replacement, mercenary recruitment, and convoy fleet crews.
# Combinations: > 4,000,000 unique full name permutations.
# -----------------------------------------------------------------------------

const FIRST_NAMES: Array[String] = [
	# Western & Classic
	"Leo", "Marcus", "Lucas", "Victor", "Alexander", "Gideon", "Arthur", "Dominic", "Vincent", "Gabriel",
	"Raymond", "Julian", "Damian", "Felix", "Adrian", "Cyrus", "Silas", "Derrick", "Tristan", "Roland",
	"Sarah", "Chloe", "Elena", "Valerie", "Clara", "Nadia", "Diana", "Iris", "Helena", "Morgan",
	"Lydia", "Astrid", "Gwen", "Sienna", "Vera", "Rowan", "Tessa", "Naomi", "Cora", "Maeve",
	# Slavic & Eastern European
	"Dmitri", "Nikolai", "Alexei", "Sergei", "Mikhail", "Ilya", "Yuri", "Boris", "Stanislav", "Vassily",
	"Katya", "Svetlana", "Natasha", "Oksana", "Tatiana", "Yelena", "Daria", "Mila", "Irina", "Polina",
	"Karel", "Marek", "Jiri", "Pavel", "Luka", "Bojan", "Milan", "Goran", "Zoran", "Dragan",
	# Asian (East / South-East / South)
	"Jin", "Kenji", "Ren", "Tatsuya", "Ryoma", "Kazuki", "Shin", "Hayato", "Daiki", "Souta",
	"Kaito", "Haruto", "Yuto", "Akira", "Minato", "Hajime", "Katsuro", "Taiki", "Jun", "Hideki",
	"Mei", "Lin", "Yuki", "Hana", "Aoi", "Kaede", "Rin", "Sakura", "Chiyo", "Ayumi",
	"Wei", "Chen", "Bo", "Feng", "Jian", "Jun", "Tao", "Zhen", "Xiao", "Haoran",
	"Arjun", "Rohan", "Vikram", "Kiran", "Dev", "Siddharth", "Tara", "Ananya", "Priya", "Sunita",
	# Nordic & Germanic
	"Bjorn", "Erik", "Torvald", "Sven", "Magnus", "Frederik", "Ragnar", "Olaf", "Leif", "Henrik",
	"Freja", "Ingrid", "Sigrid", "Solveig", "Karin", "Klara", "Britta", "Greta", "Ilse", "Hannelore",
	"Klaus", "Dieter", "Wolfgang", "Gunther", "Jonas", "Lukas", "Otto", "Franz", "Axel", "Kurt",
	# Latin & Mediterranean
	"Mateo", "Carlos", "Rafael", "Santiago", "Diego", "Javier", "Alvaro", "Gonzalo", "Ignacio", "Emilio",
	"Lucia", "Camila", "Sofia", "Valentina", "Esperanza", "Marisol", "Catalina", "Adriana", "Paloma", "Rocio",
	"Dante", "Enzo", "Marco", "Matteo", "Lorenzo", "Giovanni", "Luigi", "Rocco", "Giulio", "Fabio",
	# Middle-Eastern & African
	"Tariq", "Zayn", "Malik", "Rashid", "Farhan", "Kareem", "Samir", "Amir", "Omar", "Hassan",
	"Layla", "Soraya", "Yasmin", "Zahra", "Farida", "Nour", "Rania", "Amina", "Khadija", "Salma",
	"Kofi", "Jabari", "Kwame", "Sekou", "Malick", "Zuri", "Asha", "Makena", "Amara", "Tendai",
	# Sci-Fi / Cyberpunk Monikers & Modern Edge
	"Kael", "Valen", "Orion", "Zephyr", "Rix", "Balthazar", "Darek", "Corvus", "Vance", "Kroll",
	"Nyx", "Vesper", "Scylla", "Aura", "Nova", "Lyra", "Echo", "Kallisto", "Juno", "Astra",
	"Deckard", "Miller", "Taggart", "Gage", "Raze", "Brant", "Flint", "Colt", "Jett", "Jax"
]

const CALLSIGNS: Array[String] = [
	"Apex", "Anvil", "Banshee", "Blackjack", "Blitz", "Bloodhound", "Bonecrusher", "Bullseye",
	"Cannonball", "Centurion", "Cipher", "Cinder", "Cobalt", "Comet", "Crag", "Cutter",
	"Deadbolt", "Deadeye", "Demolisher", "Dustdevil", "Echo", "Eclipse", "Fang", "Firebrand",
	"Flash", "Foxhound", "Frost", "Gargoyle", "Ghost", "Goliath", "Grave", "Grim",
	"Hacksaw", "Hammer", "Havoc", "Hellhound", "Hex", "Hornet", "Hound", "Hurricane",
	"Igniter", "Imp", "Ironclad", "Jackal", "Jester", "Jinx", "Juggernaut", "Kestrel",
	"Killjoy", "Knight", "Kraken", "Lockdown", "Longshot", "Madcat", "Mammoth", "Mantis",
	"Maverick", "Misfit", "Monarch", "Nailgun", "Nemesis", "Nightfall", "Nightshade", "Null",
	"Omen", "Outlaw", "Overcharge", "Overload", "Phantom", "Pitbull", "Pyro", "Quake",
	"Rancor", "Raptor", "Razor", "Reaper", "Redline", "Riptide", "Ronin", "Rust",
	"Sabre", "Scrapdog", "Scythe", "Shadow", "Shrapnel", "Siege", "Sledge", "Specter",
	"Spitfire", "Steelhead", "Stinger", "Storm", "Strider", "Striker", "Tempest", "Thunder",
	"Titan", "Trigger", "Undertaker", "Valkyrie", "Vandal", "Viper", "Vortex", "Vulcan",
	"Warlock", "Warthog", "Watchdog", "Wildcard", "Wraith", "Wyvern", "Zero", "Zeus"
]

const LAST_NAMES: Array[String] = [
	# Western & Anglo
	"Sterling", "Vance", "Mercer", "Blackwood", "Gallagher", "Thorne", "Cross", "Fletcher", "Barrett", "Hawthorne",
	"Winter", "Sinclair", "Crawford", "Garrison", "Montgomery", "Carrington", "Prescott", "Shepherd", "Vaughn", "Clayton",
	"Holloway", "Browning", "Stafford", "Redfield", "Kingsley", "Lockwood", "Pemberton", "Fairfax", "Harding", "Monroe",
	# Eastern European & Slavic
	"Kovacs", "Volkov", "Ivanov", "Petrov", "Morozov", "Sokolov", "Popov", "Lebedev", "Kozlov", "Novak",
	"Zaytsev", "Belov", "Chernov", "Romanov", "Vasiliev", "Grigoriev", "Orlov", "Turgenev", "Kasparov", "Babin",
	"Kowalski", "Wisniewski", "Kaminski", "Lewandowski", "Dabrowski", "Zieliński", "Szymanski", "Wozniak", "Kozlowski", "Jankowski",
	# Asian (Japanese, Chinese, Korean, Indian)
	"Tanaka", "Ishikawa", "Takahashi", "Watanabe", "Sato", "Suzuki", "Kobayashi", "Kato", "Yoshida", "Yamamoto",
	"Nakamura", "Matsuda", "Fujita", "Okada", "Hasegawa", "Kuroda", "Shimizu", "Ogawa", "Tsukamoto", "Nomura",
	"Chen", "Zhang", "Wang", "Li", "Liu", "Yang", "Huang", "Zhao", "Wu", "Zhou",
	"Lin", "Xu", "Sun", "Ma", "Zhu", "Hu", "Guo", "He", "Gao", "Luo",
	"Patel", "Sharma", "Bose", "Menon", "Mukherjee", "Kapoor", "Chatterjee", "Deshmukh", "Chowdhury", "Rathore",
	# Germanic & Nordic
	"Richter", "Lindqvist", "Althaus", "Kruger", "Faust", "Eisenhardt", "Vogel", "Hoffmann", "Schulz", "Zimmermann",
	"Bergman", "Dahl", "Holm", "Lund", "Nyqvist", "Strom", "Aasland", "Engstrom", "Nordqvist", "Westermark",
	"Jaeger", "Baumann", "Fischer", "Hartmann", "Keller", "Kaiser", "Schmidt", "Weiss", "Schreiber", "Brandt",
	# Latin & Hispanic
	"Morales", "Reyes", "Salazar", "Castillo", "Guerrero", "Navarro", "Delgado", "Cabrera", "Mendoza", "Ortega",
	"Santana", "Figueroa", "Cordero", "Valdez", "Peralta", "Solano", "Cardoso", "Miranda", "Carrasco", "Montoya",
	"Rossi", "Ferrari", "Esposito", "Bianchi", "Romano", "Colombo", "Ricci", "Marino", "Greco", "Conti",
	# Middle-Eastern & Global
	"Khoury", "Mansour", "Haddad", "Najjar", "Qasim", "Darwish", "Fakhoury", "Boulos", "Sarkis", "Tahan",
	"Okafor", "Adeyemi", "Mensah", "Diallo", "Traore", "Ndiaye", "Touré", "Kamara", "Sow", "Ba",
	# Industrial / Outland / Frontier Surnames
	"Ironclad", "Rust", "Grit", "Forge", "Cinder", "Hardy", "Ashford", "Stone", "Crag", "Overholt",
	"Brant", "Hazen", "Rook", "Vane", "Stryker", "Kroll", "Gant", "Drayton", "Harker", "Sloan"
]

const BACKGROUNDS: Array[Dictionary] = [
	{
		"id": "ex_military",
		"name": "Ex-Military Vanguard",
		"desc": "A disciplined soldier discharged following the Border Wars.",
		"default_archetype": 2, # Heavy
	},
	{
		"id": "scavenger",
		"name": "Wasteland Scavenger",
		"desc": "Survived years scavenging scrap and parts in contested dead zones.",
		"default_archetype": 1, # Ranged
	},
	{
		"id": "merc_veteran",
		"name": "Mercenary Veteran",
		"desc": "Has fought under a dozen banners and survived every bloodbath.",
		"default_archetype": 0, # Rusher
	},
	{
		"id": "corp_deserter",
		"name": "Corporate Deserter",
		"desc": "Stole high-grade pilot gear and fled the mega-corporations.",
		"default_archetype": 3, # Support
	},
	{
		"id": "arena_fighter",
		"name": "Underground Gladiator",
		"desc": "Trained in no-rules death matches in the underground mech coliseums.",
		"default_archetype": 0, # Rusher
	},
	{
		"id": "convoy_smuggler",
		"name": "Convoy Smuggler",
		"desc": "Knows how to push engines to their absolute limit to escape patrols.",
		"default_archetype": 0, # Rusher
	},
	{
		"id": "gearhead_mechanic",
		"name": "Field Grease-Monkey",
		"desc": "Can patch up a shattered cooling manifold with spit and scrap wiring.",
		"default_archetype": 3, # Support
	},
	{
		"id": "frontier_scout",
		"name": "Frontier Outland Scout",
		"desc": "Patient, quiet, and deadly at extreme engagement ranges.",
		"default_archetype": 1, # Ranged
	},
]

const PERSONALITY_TRAITS: Array[String] = [
	"Fearless", "Methodical", "Hot-headed", "Pragmatic", "Cold & Calculating",
	"Fiercely Loyal", "Reckless Daredevil", "Battle-Hardened", "Vigilant", "Cynical",
	"Quiet Professional", "Adrenaline Junkie"
]

const PILOT_PERKS: Array[Dictionary] = [
	{
		"id": "iron_lungs",
		"name": "Iron Lungs",
		"desc": "+30% on-foot pilot HP (Higher survival rate upon ejection).",
		"effect": "pilot_hp",
		"val": 1.30,
		"weight": 10,
	},
	{
		"id": "overdrive_reflexes",
		"name": "Overdrive Reflexes",
		"desc": "-15% Dash energy consumption and faster stamina recovery.",
		"effect": "dash_eff",
		"val": 0.85,
		"weight": 10,
	},
	{
		"id": "sharpshooter",
		"name": "Sharpshooter",
		"desc": "+15% Ballistic weapon precision and critical hit multiplier.",
		"effect": "crit_boost",
		"val": 1.15,
		"weight": 10,
	},
	{
		"id": "grease_monkey",
		"name": "Grease Monkey",
		"desc": "-20% Scrap and credit cost to repair mech parts at safehouses.",
		"effect": "repair_discount",
		"val": 0.80,
		"weight": 10,
	},
	{
		"id": "roller_maestro",
		"name": "Roller Maestro",
		"desc": "+15% Roller Dash top velocity on paved roads and in battle.",
		"effect": "roller_speed",
		"val": 1.15,
		"weight": 10,
	},
	{
		"id": "adrenaline_rush",
		"name": "Adrenaline Rush",
		"desc": "Grants 2.5s damage immunity window immediately after mech ejection.",
		"effect": "eject_shield",
		"val": 2.5,
		"weight": 10,
	},
	{
		"id": "heavy_metal",
		"name": "Heavy Metal",
		"desc": "+15% Armor kinetic and explosive damage resistance.",
		"effect": "armor_res",
		"val": 1.15,
		"weight": 10,
	},
	{
		"id": "ammo_hoarder",
		"name": "Ammo Hoarder",
		"desc": "+25% Personal pilot ammunition carrying capacity.",
		"effect": "ammo_cap",
		"val": 1.25,
		"weight": 10,
	},
	{
		"id": "precognitive_flow",
		"name": "Pre-Cognitive Flow",
		"desc": "Effortless movement reading: -50% Dash Energy Cost, +25% Evasion, Zero-Waste Momentum.",
		"effect": "precog_flow",
		"val": 0.50,
		"weight": 1,
		"is_legendary": true,
	},
]


# -----------------------------------------------------------------------------
# PUBLIC API: GENERATION FUNCTIONS
# -----------------------------------------------------------------------------

## Selects a perk respecting rarity weights and legendary gating
static func pick_random_perk(allow_legendary: bool = false) -> Dictionary:
	var pool: Array[Dictionary] = []
	for p in PILOT_PERKS:
		if p.get("is_legendary", false) and not allow_legendary:
			continue
		var w: int = int(p.get("weight", 10))
		for i in range(w):
			pool.append(p)
	if pool.is_empty():
		return PILOT_PERKS[0]
	return pool.pick_random()


## Generates a randomized full pilot name with optional callsign
static func generate_pilot_name(include_callsign_prob: float = 0.70) -> Dictionary:
	var first: String = FIRST_NAMES.pick_random()
	var last: String = LAST_NAMES.pick_random()
	var callsign: String = ""

	if randf() < include_callsign_prob:
		callsign = CALLSIGNS.pick_random()

	var full_name: String
	if callsign != "":
		full_name = "%s '%s' %s" % [first, callsign, last]
	else:
		full_name = "%s %s" % [first, last]

	return {
		"full_name": full_name,
		"first_name": first,
		"callsign": callsign,
		"last_name": last,
	}


## Generates a complete pilot record
static func generate_pilot(opts: Dictionary = {}) -> Dictionary:
	var name_info := generate_pilot_name(opts.get("callsign_prob", 0.75))
	var bg: Dictionary = BACKGROUNDS.pick_random()
	var cur_sec: int = 1
	if Engine.has_singleton("GlobalData") or (is_instance_valid(Engine.get_main_loop()) and Engine.get_main_loop().root and Engine.get_main_loop().root.has_node("GlobalData")):
		var gd = Engine.get_main_loop().root.get_node("GlobalData")
		cur_sec = int(gd.board.current_sector)
	var allow_legendary: bool = opts.get("allow_legendary", false) or (randf() < 0.01 and cur_sec >= 3)
	var perk: Dictionary = pick_random_perk(allow_legendary)
	var trait_str: String = PERSONALITY_TRAITS.pick_random()

	var archetype: int = int(opts.get("archetype", bg.get("default_archetype", 0)))
	var base_hp: int = int(100.0 * float(perk.get("val", 1.0))) if perk.get("effect") == "pilot_hp" else 100
	var hire_cost: int = int(randf_range(80.0, 160.0))

	var unique_id := "pilot_%d_%d" % [Time.get_ticks_msec(), randi() % 9999]

	return {
		"id": unique_id,
		"name": name_info["full_name"],
		"first_name": name_info["first_name"],
		"callsign": name_info["callsign"],
		"last_name": name_info["last_name"],
		"background": bg["name"],
		"background_desc": bg["desc"],
		"trait": trait_str,
		"perk_id": perk["id"],
		"perk_name": perk["name"],
		"perk_desc": perk["desc"],
		"perk_effect": perk["effect"],
		"perk_val": perk["val"],
		"archetype": archetype,
		"level": int(opts.get("level", 1)),
		"sorties": 0,
		"kills": 0,
		"hp": base_hp,
		"max_hp": base_hp,
		"is_alive": true,
		"hire_cost": hire_cost,
		"assigned_mech_slot": -1,
	}


## Generates a pool of recruitable pilots (e.g. for city mercenary hire or replacement)
static func generate_hire_pool(count: int = 3) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for i in range(count):
		pool.append(generate_pilot())
	return pool


## Generates an emergency replacement recruit when an existing pilot dies
static func generate_replacement_pilot(dead_pilot_name: String = "") -> Dictionary:
	var pilot := generate_pilot()
	if dead_pilot_name != "":
		pilot["recruit_reason"] = "Hired as replacement for fallen pilot %s." % dead_pilot_name
	return pilot


const SQUAD_NAME_PREFIXES: Array[String] = [
	"Iron", "Viper", "Ghost", "Shadow", "Steel", "Obsidian", "Blood", "Storm",
	"Apex", "Crimson", "Thunder", "Titan", "Night", "Wolf", "Dire", "Gargoyle"
]

const SQUAD_NAME_SUFFIXES: Array[String] = [
	"Squadron", "Fireteam", "Strike Fleet", "Vanguard", "Claw", "Lance",
	"Battalion", "Cohort", "Brigade", "Division", "Platoon"
]

const TACTICAL_ROLES: Array[String] = [
	"vanguard", "flanker_left", "flanker_right", "fire_support", "guardian"
]


# ---------------------------------------------------------------------------
# CATALOG MECH LOADOUT — each pilot's mech is assembled from the same
# armor_catalog / frame_catalog the player uses (GDD §2 WYSIWYG).
# ---------------------------------------------------------------------------

static func _is_blueprint_frame(entry: Dictionary) -> bool:
	return str(entry.get("type", "")).contains("Valkyrion")

static func _archetype_frame_index(archetype: int) -> int:
	match archetype:
		1: return 1  # Ranged: medium
		2: return 2  # Heavy: heaviest
		3: return 1  # Support: medium
		4, 5: return 1 # Shield: medium
		_: return 0  # Rusher: lightest

static func _pick_armor_by_tier(eligible: Array, heaviest: bool) -> Dictionary:
	var best := eligible[0] as Dictionary
	for entry in eligible:
		var hp: float = float(entry.get("hp", 0.0))
		var best_hp: float = float(best.get("hp", 0.0))
		if heaviest and hp > best_hp:
			best = entry
		elif not heaviest and hp < best_hp:
			best = entry
	return best

static func _pick_armor_by_faction_tier(eligible: Array, faction_tier: int) -> Dictionary:
	if eligible.is_empty():
		return {}
	# Sort by HP (light -> heavy)
	var sorted := eligible.duplicate()
	sorted.sort_custom(func(a, b): return float(a.get("hp", 0.0)) < float(b.get("hp", 0.0)))
	# Tier 1: lightest 33%, Tier 2: middle 33%, Tier 3: heaviest 33%
	var idx: int = 0
	if faction_tier == 1:
		idx = 0
	elif faction_tier == 2:
		idx = int(sorted.size() * 0.5)
	else:
		idx = sorted.size() - 1
	idx = clampi(idx, 0, sorted.size() - 1)
	return sorted[idx] as Dictionary

static func _archetype_palette_for(archetype: int, faction_paint: Dictionary = {}, squad_role: String = "") -> Dictionary:
	if not faction_paint.is_empty():
		var base: Color = faction_paint.get("base", Color(0.6, 0.6, 0.6))
		var accent: Color = faction_paint.get("accent", base)
		var trim: Color = faction_paint.get("trim", base)
		var is_commander := squad_role == "commander"
		return {
			"default": base,
			"head": accent if is_commander else trim,
			"arm_left": accent if is_commander else base,
			"arm_right": accent if is_commander else base,
		}
	match archetype:
		1: return {"default": Color(0.25, 0.55, 0.8), "head": Color(0.2, 0.5, 0.75)}
		2: return {"default": Color(0.65, 0.15, 0.2), "head": Color(0.75, 0.2, 0.15)}
		3: return {"default": Color(0.75, 0.65, 0.2), "head": Color(0.8, 0.7, 0.25)}
		4: return {"default": Color(0.25, 0.35, 0.55), "head": Color(0.3, 0.5, 0.8)}
		5: return {"default": Color(0.6, 0.4, 0.2), "head": Color(0.85, 0.6, 0.25)}
		_: return {"default": Color(0.75, 0.2, 0.2), "head": Color(0.85, 0.25, 0.25)}

static func _scene_type_for_archetype(archetype: int, is_commander: bool) -> String:
	# Map pilot archetype -> enemy scene type. Commanders field full-rig variant.
	match archetype:
		0: return "rusher_full" if is_commander else "rusher_simple"
		1: return "ranged_full" if is_commander else "ranged_simple"
		2: return "heavy_full" # always full
		3: return "support_full" if is_commander else "support_simple"
		4: return "shieldmelee_full"
		5: return "shieldranged_full"
		_: return "rusher_simple"

## Generates a per-pilot mech loadout from GlobalData catalogs.
## Returns { slot: {"frame":{}, "armor":{}} } mirroring enemy_dummy._enemy_loadout()
## If FactionSystem is available, picks armor by faction tier (1=light, 3=heavy) otherwise heaviest/lightest.
static func generate_mech_loadout(archetype: int, faction_paint: Dictionary = {}, squad_role: String = "", faction_id: String = "") -> Dictionary:
	var has_global := false
	var armor_cat: Dictionary = {}
	var frame_cat: Dictionary = {}
	var gd_inst = Engine.get_singleton("GlobalData") if Engine.has_singleton("GlobalData") else (Engine.get_main_loop().root.get_node_or_null("GlobalData") if is_instance_valid(Engine.get_main_loop()) and Engine.get_main_loop().root else null)
	if gd_inst and gd_inst.armor_catalog.size() > 0:
		armor_cat = gd_inst.armor_catalog
		frame_cat = gd_inst.frame_catalog
		has_global = true
	if not has_global:
		return {}
	var palette := _archetype_palette_for(archetype, faction_paint, squad_role)
	var wants_heavy := archetype == 2
	# Try faction tier pick first (real time + event driven), fallback to archetype heaviest
	var faction_tier: int = 0
	if faction_id != "" and ResourceLoader.exists("res://scripts/systems/faction_system.gd"):
		var FS = load("res://scripts/systems/faction_system.gd")
		faction_tier = FS.get_tier(faction_id) if faction_id != "outland" else FS.get_tier("federation") # outland mixed, use federation as base then randomize below
		if faction_id == "outland":
			# Outland wanderers use random tier outside both factions (scrap mix)
			faction_tier = randi_range(1, 3) if FS.get_time_days() >= 15 else randi_range(1, 2)
	var loadout: Dictionary = {}
	var slots: Array = ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]
	for slot in slots:
		var frame_entry: Dictionary = {}
		var frames = frame_cat.get(slot, [])
		var eligible_frames: Array = []
		if frames is Array:
			for entry in frames:
				if entry is Dictionary and not _is_blueprint_frame(entry):
					eligible_frames.append(entry)
		if eligible_frames.size() > 0:
			var f_idx: int = clampi(_archetype_frame_index(archetype), 0, eligible_frames.size() - 1)
			frame_entry = (eligible_frames[f_idx] as Dictionary).duplicate(true)
		var armor_entry: Dictionary = {}
		var eligible: Array = []
		var armors = armor_cat.get(slot, [])
		if armors is Array:
			for entry in armors:
				if not entry.get("blueprint_only", false):
					eligible.append(entry as Dictionary)
		if eligible.size() > 0:
			if faction_tier >= 1 and faction_tier <= 3:
				armor_entry = _pick_armor_by_faction_tier(eligible, faction_tier).duplicate(true)
			else:
				armor_entry = _pick_armor_by_tier(eligible, wants_heavy).duplicate(true)
		if not armor_entry.is_empty():
			armor_entry["equipped"] = true
			armor_entry["color"] = palette.get(slot, palette.get("default", Color(0.7, 0.15, 0.15)))
		loadout[slot] = {"frame": frame_entry, "armor": armor_entry}
	return loadout

## Generates a complete Enemy Fleet / Squad of procedural pilots with assigned tactical roles
## Each pilot now also carries a catalog-based mech_loadout and scene_type.
## faction_name is display name (Federation/Zeon), faction_id is federation/zeon/outland for tier
static func generate_enemy_fleet(squad_size: int = 3, faction_name: String = "", difficulty: int = 1, faction_paint: Dictionary = {}, faction_id: String = "", commander_archetype: int = -1) -> Dictionary:
	var squad_id := "fleet_%d_%d" % [Time.get_ticks_msec(), randi() % 99999]
	var prefix: String = SQUAD_NAME_PREFIXES.pick_random()
	var suffix: String = SQUAD_NAME_SUFFIXES.pick_random()
	var squad_name: String = "%s %s" % [prefix, suffix]
	if faction_name != "":
		squad_name = "%s - %s %s" % [faction_name, prefix, suffix]

	var pilots: Array[Dictionary] = []
	var count := maxi(1, squad_size)

	# 1. Generate Commander Pilot (Leader)
	var commander_opts := {
		"callsign_prob": 1.0,
		"allow_legendary": difficulty >= 3,
		"level": difficulty + 1,
	}
	if commander_archetype >= 0:
		commander_opts["archetype"] = commander_archetype
	var commander := generate_pilot(commander_opts)
	commander["squad_id"] = squad_id
	commander["squad_name"] = squad_name
	commander["squad_role"] = "commander"
	commander["tactical_role"] = "commander"
	commander["rank_title"] = "[CMDR]"
	commander["display_name"] = "%s %s" % [commander["rank_title"], commander["name"]]
	# Commander personality leans tactical/aggressive leadership
	if commander["trait"] not in ["Tactical", "Aggressive", "Cold & Calculating"]:
		commander["trait"] = ["Tactical", "Aggressive", "Cold & Calculating"].pick_random()
	commander["scene_type"] = _scene_type_for_archetype(int(commander.get("archetype", 0)), true)
	commander["mech_loadout"] = generate_mech_loadout(int(commander.get("archetype", 0)), faction_paint, "commander", faction_id)
	commander["faction_id"] = faction_id
	pilots.append(commander)

	# 2. Generate Wingmen Pilots with tactical distribution
	var role_pool := TACTICAL_ROLES.duplicate()
	role_pool.shuffle()

	for i in range(1, count):
		var role: String = role_pool[(i - 1) % role_pool.size()]
		var wingman_opts := {
			"callsign_prob": 0.85,
			"allow_legendary": false,
			"level": difficulty,
		}
		var wingman := generate_pilot(wingman_opts)
		wingman["squad_id"] = squad_id
		wingman["squad_name"] = squad_name
		wingman["squad_role"] = "member"
		wingman["tactical_role"] = role
		wingman["rank_title"] = "[SGT]" if i == 1 else "[PVT]"
		wingman["display_name"] = "%s %s" % [wingman["rank_title"], wingman["name"]]

		# Adjust personality trait according to role for natural tactical synergy
		match role:
			"vanguard":
				wingman["trait"] = "Aggressive"
				wingman["archetype"] = 0 # Rusher / Melee
			"flanker_left", "flanker_right":
				wingman["trait"] = "Tactical"
				wingman["archetype"] = 1 # Ranged / Rifle
			"fire_support":
				wingman["trait"] = "Cautious"
				wingman["archetype"] = 3 # Support / Sniper / Mortar
			"guardian":
				wingman["trait"] = "Balanced"
				wingman["archetype"] = 4 # Shield / Heavy
		wingman["scene_type"] = _scene_type_for_archetype(int(wingman.get("archetype", 0)), false)
		wingman["mech_loadout"] = generate_mech_loadout(int(wingman.get("archetype", 0)), faction_paint, "member", faction_id)
		wingman["faction_id"] = faction_id
		pilots.append(wingman)

	return {
		"squad_id": squad_id,
		"squad_name": squad_name,
		"commander": commander,
		"pilots": pilots,
		"squad_size": pilots.size(),
		"formation": "wedge" if count <= 4 else "line_abreast"
	}
