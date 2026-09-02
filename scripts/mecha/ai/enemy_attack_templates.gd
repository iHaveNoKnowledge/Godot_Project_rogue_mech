class_name EnemyAttackTemplates
extends RefCounted

## Static attack pattern definitions per archetype.
## 4 = SHIELD_MELEE (โล่ + ดาบ), 5 = SHIELD_RANGED (โล่ + ปืน).
## Updated speeds to parity with player mecha speeds (~11.0 - 14.5 m/s).

enum Archetype { RUSHER, RANGED, HEAVY, SUPPORT, SHIELD_MELEE, SHIELD_RANGED }


static func get_stats(archetype: int, is_full: bool = false) -> Dictionary:
	match archetype:
		Archetype.SHIELD_MELEE:
			if is_full:
				return {
					"move_speed": 13.0,
					"attack_range": 5.2,
					"attack_damage": 24.0,
					"attack_cooldown": 2.2,
				}
			else:
				return {
					"move_speed": 12.5,
					"attack_range": 5.2,
					"attack_damage": 18.0,
					"attack_cooldown": 2.2,
				}
		Archetype.SHIELD_RANGED:
			if is_full:
				return {
					"move_speed": 13.8,
					"attack_range": 50.0,
					"attack_damage": 22.0,
					"attack_cooldown": 1.2,
				}
			else:
				return {
					"move_speed": 13.5,
					"attack_range": 50.0,
					"attack_damage": 16.0,
					"attack_cooldown": 1.2,
				}
		Archetype.RUSHER:
			if is_full:
				return {
					"move_speed": 14.5,
					"attack_range": 5.0,
					"attack_damage": 20.0,
					"attack_cooldown": 2.0,
				}
			else:
				return {
					"move_speed": 14.0,
					"attack_range": 5.0,
					"attack_damage": 15.0,
					"attack_cooldown": 2.0,
				}
		Archetype.RANGED:
			if is_full:
				return {
					"move_speed": 14.0,
					"attack_range": 60.0,
					"attack_damage": 15.0,
					"attack_cooldown": 0.5,
				}
			else:
				return {
					"move_speed": 13.5,
					"attack_range": 60.0,
					"attack_damage": 12.0,
					"attack_cooldown": 0.6,
				}
		Archetype.HEAVY:
			return {
				"move_speed": 11.0,
				"attack_range": 10.0,
				"attack_damage": 50.0,
				"attack_cooldown": 4.0,
			}
		Archetype.SUPPORT:
			if is_full:
				return {
					"move_speed": 14.5,
					"attack_range": 40.0,
					"attack_damage": 0.0,
					"attack_cooldown": 1.0,
				}
			else:
				return {
					"move_speed": 14.0,
					"attack_range": 40.0,
					"attack_damage": 0.0,
					"attack_cooldown": 1.0,
				}
	return {}


static func get_hp(archetype: int, is_full: bool = false) -> Dictionary:
	match archetype:
		Archetype.SHIELD_MELEE:
			if is_full:
				return {"armor": 90.0, "frame": 110.0}
			else:
				return {"armor": 45.0, "frame": 65.0}
		Archetype.SHIELD_RANGED:
			if is_full:
				return {"armor": 70.0, "frame": 90.0}
			else:
				return {"armor": 40.0, "frame": 55.0}
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
