class_name EnemyAttackTemplates
extends RefCounted

## Static attack pattern definitions per archetype.

enum Archetype { RUSHER, RANGED, HEAVY, SUPPORT }


static func get_stats(archetype: int, is_full: bool = false) -> Dictionary:
	match archetype:
		Archetype.RUSHER:
			if is_full:
				return {
					"move_speed": 3.0,
					"attack_range": 15.0,
					"attack_damage": 20.0,
					"attack_cooldown": 2.0,
				}
			else:
				return {
					"move_speed": 3.0,
					"attack_range": 15.0,
					"attack_damage": 15.0,
					"attack_cooldown": 2.0,
				}
		Archetype.RANGED:
			if is_full:
				return {
					"move_speed": 4.0,
					"attack_range": 60.0,
					"attack_damage": 15.0,
					"attack_cooldown": 0.5,
				}
			else:
				return {
					"move_speed": 4.0,
					"attack_range": 60.0,
					"attack_damage": 12.0,
					"attack_cooldown": 0.6,
				}
		Archetype.HEAVY:
			return {
				"move_speed": 1.5,
				"attack_range": 10.0,
				"attack_damage": 50.0,
				"attack_cooldown": 4.0,
			}
		Archetype.SUPPORT:
			if is_full:
				return {
					"move_speed": 5.0,
					"attack_range": 40.0,
					"attack_damage": 0.0,
					"attack_cooldown": 1.0,
				}
			else:
				return {
					"move_speed": 5.0,
					"attack_range": 40.0,
					"attack_damage": 0.0,
					"attack_cooldown": 1.0,
				}
	return {}


static func get_hp(archetype: int, is_full: bool = false) -> Dictionary:
	match archetype:
		Archetype.RUSHER:
			if is_full:
				return {"armor": 80.0, "frame": 100.0}
			else:
				return {"armor": 40.0, "frame": 60.0}
		Archetype.RANGED:
			if is_full:
				return {"armor": 50.0, "frame": 70.0}
			else:
				return {"armor": 30.0, "frame": 40.0}
		Archetype.HEAVY:
			return {"armor": 150.0, "frame": 200.0}
		Archetype.SUPPORT:
			if is_full:
				return {"armor": 40.0, "frame": 50.0}
			else:
				return {"armor": 20.0, "frame": 30.0}
	return {}
