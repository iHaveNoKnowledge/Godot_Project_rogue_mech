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
	var allow_legendary: bool = opts.get("allow_legendary", false) or (randf() < 0.01 and GlobalData.board.current_sector >= 3)
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
