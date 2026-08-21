class_name AiPilotTraits
extends RefCounted

## Pilot personality profiles and combat parameters for Beehave Behavior Tree.
## Translates narrative pilot traits (from pilot_generator.gd) into concrete
## tactical thresholds: flee HP, engagement range, melee aggression, and scavenging.

enum PersonalityType {
	AGGRESSIVE,
	CAUTIOUS,
	SCAVENGER,
	TACTICAL,
	BALANCED
}

# Mapping from text trait to enum type
static func get_personality_type(trait_name: String) -> PersonalityType:
	var t := trait_name.to_lower().strip_edges()
	match t:
		"reckless daredevil", "hot-headed", "fearless", "adrenaline junkie", "aggressive":
			return PersonalityType.AGGRESSIVE
		"cold & calculating", "cynical", "pragmatic", "cautious", "mercenary":
			return PersonalityType.CAUTIOUS
		"scavenger", "greedy", "scrapper", "opportunist":
			return PersonalityType.SCAVENGER
		"quiet professional", "vigilant", "battle-hardened", "fiercely loyal", "methodical", "tactical":
			return PersonalityType.TACTICAL
		_:
			return PersonalityType.BALANCED


## Returns personality configuration parameters for Blackboard
static func get_personality_profile(trait_name: String) -> Dictionary:
	var type := get_personality_type(trait_name)
	match type:
		PersonalityType.AGGRESSIVE:
			return {
				"type": PersonalityType.AGGRESSIVE,
				"name": "Aggressive",
				"flee_hp_threshold": 0.10,          # Only flees when nearly destroyed (10% HP)
				"prefer_melee": true,               # Prefers switching to melee blade
				"melee_dash_chance": 0.75,          # Frequently dashes into enemy face
				"scavenge_ammo_threshold": 0.15,    # Only grabs ammo when almost completely dry
				"scavenge_scan_radius": 20.0,
				"optimal_range_factor": 0.50,       # Pushes closer than weapon max range
				"seek_cover_when_shot": false,      # Ignores incoming fire and charges
				"target_priority": "lowest_hp"
			}
		PersonalityType.CAUTIOUS:
			return {
				"type": PersonalityType.CAUTIOUS,
				"name": "Cautious",
				"flee_hp_threshold": 0.45,          # Retreats to cover when HP drops below 45%
				"prefer_melee": false,              # Avoids melee unless forced
				"melee_dash_chance": 0.15,
				"scavenge_ammo_threshold": 0.50,    # Grabs ammo as soon as half-empty if safe
				"scavenge_scan_radius": 35.0,
				"optimal_range_factor": 0.90,       # Kites near maximum effective range
				"seek_cover_when_shot": true,       # Proactively seeks cover when taking hits
				"target_priority": "isolated"
			}
		PersonalityType.SCAVENGER:
			return {
				"type": PersonalityType.SCAVENGER,
				"name": "Scavenger",
				"flee_hp_threshold": 0.30,          # Flees at 30% HP
				"prefer_melee": false,
				"melee_dash_chance": 0.30,
				"scavenge_ammo_threshold": 0.60,    # High priority to scavenge ammo & scrap
				"scavenge_scan_radius": 50.0,       # Long-distance loot radar
				"optimal_range_factor": 0.75,
				"seek_cover_when_shot": true,
				"target_priority": "nearest"
			}
		PersonalityType.TACTICAL:
			return {
				"type": PersonalityType.TACTICAL,
				"name": "Tactical",
				"flee_hp_threshold": 0.25,          # Standard tactical retreat at 25% HP
				"prefer_melee": false,
				"melee_dash_chance": 0.40,
				"scavenge_ammo_threshold": 0.35,
				"scavenge_scan_radius": 30.0,
				"optimal_range_factor": 0.75,
				"seek_cover_when_shot": true,
				"target_priority": "protect_allies" # Targets enemies attacking the player/squad
			}
		_:
			return {
				"type": PersonalityType.BALANCED,
				"name": "Balanced",
				"flee_hp_threshold": 0.25,
				"prefer_melee": false,
				"melee_dash_chance": 0.40,
				"scavenge_ammo_threshold": 0.30,
				"scavenge_scan_radius": 25.0,
				"optimal_range_factor": 0.75,
				"seek_cover_when_shot": false,
				"target_priority": "nearest"
			}
