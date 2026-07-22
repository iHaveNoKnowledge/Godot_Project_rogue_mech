extends Node
class_name DamageCalculator


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
