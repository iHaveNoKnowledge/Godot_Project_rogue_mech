extends Node
class_name DamageCalculator


## Normalizes raw damage type string down to the canonical channels:
## - "heat" (from heat, beam, energy, thermal, plasma, fire, explosive)
## - "pierce" (from pierce, piercing, kinetic, rail, bullet, shell)
## - "impact" (from impact, blunt, crush, melee, force, ram)
static func normalize_damage_type(damage_type: String) -> String:
	match str(damage_type).to_lower():
		"heat", "beam", "energy", "thermal", "plasma", "fire", "explosive":
			return "heat"
		"pierce", "piercing", "kinetic", "rail", "bullet", "shell":
			return "pierce"
		"impact", "blunt", "crush", "melee", "force", "ram":
			return "impact"
		_:
			return str(damage_type).to_lower()


## Retrieves the damage resistance multiplier for a specific damage type on the given armor data.
## Semantics:
## 1.0 = normal damage (100%)
## 0.5 = 50% damage reduction
## 0.0 = immune (0 damage)
## 1.2 = 20% extra damage / vulnerability
static func get_armor_resistance(armor_data: Variant, damage_type: String) -> float:
	var channel := normalize_damage_type(damage_type)

	# 1. Primary path: check explicit resistance dictionary
	var res_dict: Dictionary = {}
	if armor_data is Dictionary:
		if armor_data.has("resistance") and armor_data["resistance"] is Dictionary and not armor_data["resistance"].is_empty():
			res_dict = armor_data["resistance"]
	elif armor_data is Resource:
		if "resistance" in armor_data and armor_data.resistance is Dictionary and not armor_data.resistance.is_empty():
			res_dict = armor_data.resistance

	if not res_dict.is_empty():
		if channel == "impact":
			if res_dict.has("impact"):
				return float(res_dict["impact"])
			elif res_dict.has("blunt"):
				return float(res_dict["blunt"])
		elif res_dict.has(channel):
			return float(res_dict[channel])
		return 1.0

	# 2. Legacy / fallback path: derive resistance from defense_type and armor_class
	var def_type := ""
	var armor_class := 1.0
	if armor_data is Dictionary:
		def_type = str(armor_data.get("defense_type", "")).to_lower()
		if armor_data.has("armor_class"):
			armor_class = float(armor_data["armor_class"])
		elif armor_data.has("armor"):
			armor_class = maxf(float(armor_data["armor"]) / 10.0, 0.1)
	elif armor_data is Resource:
		if "defense_type" in armor_data:
			def_type = str(armor_data.defense_type).to_lower()
		if "armor_class" in armor_data:
			armor_class = float(armor_data.armor_class)

	var matched_mult := 1.0 / maxf(armor_class, 0.1) if armor_class > 0.0 else 1.0
	var norm_def := normalize_damage_type(def_type)
	if def_type == "" or def_type == "balanced" or def_type == "standard":
		return matched_mult
	elif norm_def == channel:
		return matched_mult
	else:
		return 1.0


## Calculates the final mitigated damage dealt to an armor plate.
## raw_damage: incoming attack damage
## damage_type: attack type string (beam, kinetic, explosive, blunt, etc.)
## armor_data: Dictionary or ArmorPart resource
## durability_multiplier: optional durability multiplier (e.g. from ArmorSystem.get_durability_def_multiplier)
static func calculate_armor_damage(raw_damage: float, damage_type: String, armor_data: Variant, durability_multiplier: float = 1.0) -> float:
	var resistance := get_armor_resistance(armor_data, damage_type)
	var mitigated := raw_damage * resistance
	if durability_multiplier < 0.999 and durability_multiplier > 0.0:
		mitigated = mitigated / maxf(durability_multiplier, 0.10)
	return mitigated


static func calculate_damage(raw: float, armor_class: float, part_hp: float, is_broken: bool) -> Dictionary:
	if is_broken:
		return {"reduced": 0.0, "remaining": part_hp, "destroyed": false}
	var reduced = raw / maxf(armor_class, 0.1)
	var remaining = part_hp - reduced
	var destroyed = remaining <= 0.0
	return {"reduced": reduced, "remaining": maxf(remaining, 0.0), "destroyed": destroyed}


static func calculate_weight_penalty(total_weight: float, capacity: float) -> Dictionary:
	var ratio = clampf(total_weight / capacity, 0.0, 1.0)
	return {
		"speed_mult": 1.0 - ratio * 0.6,
		"turn_rate_mult": capacity / maxf(total_weight, 1.0),
	}
