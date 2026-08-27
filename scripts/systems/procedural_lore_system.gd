class_name ProceduralLoreSystem
extends RefCounted

## ---------------------------------------------------------------------------
## PROCEDURAL LORE & RUN ORIGIN SYSTEM
##
## Generates unique procedural origins for secret beam/relic technologies and
## manages faction alignments (Federation vs Resistance vs 3rd-party Scavenger).
## Also initializes enemy commander rosters with procedural pilots.
## ---------------------------------------------------------------------------

enum TechOrigin {
	SECRET_LAB_EXPERIMENT,
	ANCIENT_BUNKER_RELIC,
	CELESTIAL_INTERVENTION
}

enum PlayerRole {
	FEDERATION_SOLDIER,
	RESISTANCE_REBEL,
	THIRD_PARTY_SCAVENGER
}

static var current_origin: TechOrigin = TechOrigin.SECRET_LAB_EXPERIMENT
static var current_role: PlayerRole = PlayerRole.FEDERATION_SOLDIER

# Active enemy commander pilot profile for the run
static var rival_commander_pilot: Dictionary = {}
static var rival_ace_squad: Array[Dictionary] = []


static func initialize_run_lore(role: PlayerRole = PlayerRole.FEDERATION_SOLDIER) -> Dictionary:
	current_role = role
	current_origin = TechOrigin.values()[randi() % TechOrigin.values().size()]
	
	# Generate rival commander and ace pilots from Day 1
	rival_commander_pilot = PilotGenerator.generate_pilot({"allow_legendary": true, "callsign_prob": 1.0})
	rival_commander_pilot["callsign"] = "Commander " + rival_commander_pilot.get("callsign", "Vanguard")
	
	rival_ace_squad.clear()
	for i in range(2):
		rival_ace_squad.append(PilotGenerator.generate_pilot({"callsign_prob": 0.85}))

	return {
		"role": get_role_name(),
		"origin": get_origin_name(),
		"origin_description": get_origin_description(),
		"rival_commander": rival_commander_pilot.get("name", "Unknown Commander"),
		"rival_callsign": rival_commander_pilot.get("callsign", "Nemesis")
	}


static func get_role_name() -> String:
	match current_role:
		PlayerRole.FEDERATION_SOLDIER:
			return "Federation Vanguard Soldier"
		PlayerRole.RESISTANCE_REBEL:
			return "Resistance Freedom Fighter"
		PlayerRole.THIRD_PARTY_SCAVENGER:
			return "Third-Party Scavenger (Neutral Mercenary)"
	return "Soldier"


static func get_origin_name() -> String:
	match current_origin:
		TechOrigin.SECRET_LAB_EXPERIMENT:
			return "Black-Ops Directorate Lab"
		TechOrigin.ANCIENT_BUNKER_RELIC:
			return "Ancient Pre-Calamity Relic Vault"
		TechOrigin.CELESTIAL_INTERVENTION:
			return "Celestial Shadow Intervention"
	return "Secret Tech"


static func get_origin_description() -> String:
	match current_origin:
		TechOrigin.SECRET_LAB_EXPERIMENT:
			return "Deep subterranean laboratories are reverse-engineering illicit energy prototypes behind closed doors."
		TechOrigin.ANCIENT_BUNKER_RELIC:
			return "Heavy excavators unearthed sealed pre-war bunkers buried beneath the desert ruins, uncovering Singularity schematics."
		TechOrigin.CELESTIAL_INTERVENTION:
			return "An autonomous orbital syndicate has secretly intervened in the planetary conflict, seeding experimental frames to disrupt the war's balance."
	return ""


## Returns role-specific gameplay perks and resource multipliers.
static func get_role_perks() -> Dictionary:
	match current_role:
		PlayerRole.FEDERATION_SOLDIER:
			return {
				"starting_ammo_mult": 1.5,
				"repair_discount": 0.20,
				"scrap_bonus": 1.0,
				"federation_standing": 80,
				"resistance_standing": -50
			}
		PlayerRole.RESISTANCE_REBEL:
			return {
				"starting_ammo_mult": 0.9,
				"repair_discount": 0.0,
				"scrap_bonus": 1.40,
				"speed_bonus": 0.10,
				"federation_standing": -60,
				"resistance_standing": 80
			}
		PlayerRole.THIRD_PARTY_SCAVENGER:
			return {
				"starting_ammo_mult": 1.1,
				"repair_discount": 0.10,
				"scrap_bonus": 1.25,
				"black_market_discount": 0.25,
				"federation_standing": 10,
				"resistance_standing": 10
			}
	return {}
