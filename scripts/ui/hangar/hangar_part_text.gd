class_name HangarPartText
extends RefCounted

## Pure text-formatting helpers for part stat cards (weapons / armor / frames).
## Extracted from hangar_controller.gd so the selection + hover stat previews
## share one place for the formatting rules. No UI or controller state.


static func weapon_type_label(wtype) -> String:
	match int(wtype):
		0: return "Beam Weapon"
		1: return "Kinetic Weapon"
		2: return "Missile Launcher"
		3: return "Shotgun"
		4: return "Melee Weapon"
		5: return "Shield"
		6: return "Railgun"
		7: return "Minigun"
	return "Unknown"


# The three attack types. Every weapon deals one, every armor plate defends
# against one, every shield plate resists one best.
static func damage_type_label(dtype: String) -> String:
	match str(dtype).to_lower():
		"heat": return "HEAT 🔥"
		"pierce": return "PIERCE 🗡️"
		"blunt": return "BLUNT 🔨"
	return "BALANCED"


# Builds a combat-capability stat block for a weapon resource (damage, fire
# rate, mag size, range, heat, recoil, ...). Only lines with a meaningful value
# are shown. Used by the selection + hover stat cards on the customize page.
static func weapon_capability_text(res: Resource) -> String:
	if res == null:
		return ""
	var lines: Array[String] = []

	var wtype := weapon_type_label(res.weapon_type) if "weapon_type" in res else "Unknown"
	lines.append("TYPE: %s" % wtype)

	if int(res.weapon_type) == 5:
		# Shield plate: show its anti-type + HP instead of damage numbers.
		var stype := ""
		if res.has_method("get_shield_type"):
			stype = res.get_shield_type()
		lines.append("ANTI-TYPE: %s" % damage_type_label(stype))
	else:
		var dtype := ""
		if res.has_method("get_damage_type"):
			dtype = res.get_damage_type()
		lines.append("DAMAGE TYPE: %s" % damage_type_label(dtype))

	if "damage" in res and res.damage != null and float(res.damage) > 0.0 and int(res.weapon_type) != 5:
		lines.append("DAMAGE: %.1f" % float(res.damage))

	if "fire_rate" in res and res.fire_rate != null and float(res.fire_rate) > 0.0:
		var fr := float(res.fire_rate)
		lines.append("FIRE RATE: %.3fs / shot (%.1f /s)" % [fr, 1.0 / fr])

	var max_ammo := int(res.max_ammo) if "max_ammo" in res and res.max_ammo != null else 0
	var ammo_per_shot := int(res.ammo_per_shot) if "ammo_per_shot" in res and res.ammo_per_shot != null else 1
	var volley := int(res.projectiles_per_shot) if "projectiles_per_shot" in res and res.projectiles_per_shot != null else 1
	var is_melee_or_shield := int(res.weapon_type) in [4, 5]
	if max_ammo > 0 and not is_melee_or_shield:
		lines.append("MAG SIZE: %d rounds" % max_ammo)
		if ammo_per_shot > 1:
			lines.append("AMMO / SHOT: %d" % ammo_per_shot)
		if volley > 1:
			lines.append("VOLLEY: x%d projectiles / pull" % volley)
		var trig := int(res.trigger_mode) if "trigger_mode" in res and res.trigger_mode != null else 0
		var burst_n := int(res.burst_count) if "burst_count" in res and res.burst_count != null else 3
		if trig == 1:
			lines.append("TRIGGER: SEMI (press per shot)")
		elif trig == 2:
			lines.append("TRIGGER: BURST x%d (hold)" % maxi(burst_n, 1))
	elif is_melee_or_shield:
		lines.append("AMMO: NONE")

	if "range_distance" in res and res.range_distance != null and float(res.range_distance) > 0.0:
		lines.append("RANGE: %.1f m" % float(res.range_distance))

	if "projectile_speed" in res and res.projectile_speed != null and float(res.projectile_speed) > 0.0:
		lines.append("PROJECTILE SPEED: %.1f" % float(res.projectile_speed))

	if "spread" in res and res.spread != null and float(res.spread) > 0.0:
		lines.append("SPREAD: %.2f" % float(res.spread))

	if "ammo_regen_per_sec" in res and res.ammo_regen_per_sec != null and float(res.ammo_regen_per_sec) > 0.0:
		lines.append("FABRICATOR: forges +1 round / %.1fs into the mag" % (1.0 / float(res.ammo_regen_per_sec)))

	if "heat_capacity" in res and res.heat_capacity != null and float(res.heat_capacity) > 0.0:
		var hcap := float(res.heat_capacity)
		var hshot := float(res.heat_per_shot) if "heat_per_shot" in res and res.heat_per_shot != null else 0.0
		var hcool := float(res.heat_cool_rate) if "heat_cool_rate" in res and res.heat_cool_rate != null else 0.0
		lines.append("HEAT: %.1f cap | %.1f /shot | cool %.1f/s" % [hcap, hshot, hcool])

	if "impact" in res and res.impact != null and float(res.impact) > 0.0:
		lines.append("IMPACT (Stagger): %.1f" % float(res.impact))

	if "recoil_force" in res and res.recoil_force != null and float(res.recoil_force) > 0.0:
		lines.append("RECOIL: %.1f" % float(res.recoil_force))

	if int(res.weapon_type) == 5:
		var shp := float(res.shield_hp) if "shield_hp" in res and res.shield_hp != null else 0.0
		lines.append("SHIELD HP: %.1f" % shp)
		lines.append("NOTE: Physical plate — no regen. Drains 40% vs its anti-type, 100% vs others.")

	if "two_handed" in res and res.two_handed:
		var power_need := float(res.power_required) if "power_required" in res and res.power_required != null else 0.0
		lines.append("GRIP: TWO-HANDED (needs Power %.1f to one-hand)" % power_need)

	var desc := ""
	if "description" in res and res.description != null:
		desc = str(res.description).strip_edges()
	if not desc.is_empty():
		lines.append("")
		lines.append("DESC: %s" % desc)

	return "\n".join(lines)


# Builds a defensive stat block for an owned armor instance (type, armor class,
# HP, weight, durability, upgrade level). Only lines with a meaningful value
# are shown. Durability (0..1) is passed in because the caller already computed
# it (equipped parts read the live combat damage cache).
static func armor_capability_text(inst: Dictionary, durability: float) -> String:
	if inst.is_empty():
		return ""
	var lines: Array[String] = []

	lines.append("TYPE: %s" % inst.get("type", "Instance"))

	# Which attack type this plate defends against (empty = balanced plate).
	var ddef := str(inst.get("defense_type", "")).to_lower()
	if ddef != "":
		lines.append("DEFENSE TYPE: %s" % damage_type_label(ddef))
	else:
		lines.append("DEFENSE TYPE: BALANCED (all types at armor class)")

	if inst.has("resistance") and inst["resistance"] is Dictionary and not (inst["resistance"] as Dictionary).is_empty():
		var r: Dictionary = inst["resistance"]
		var heat_r: float = float(r.get("heat", 1.0))
		var pierce_r: float = float(r.get("pierce", 1.0))
		var impact_r: float = float(r.get("impact", r.get("blunt", 1.0)))
		lines.append("RESISTANCE: Heat x%.2f | Pierce x%.2f | Impact x%.2f" % [heat_r, pierce_r, impact_r])

	var full_hp := float(GlobalData.part_stat(inst, "max_hp", 30.0))
	var dur := clampf(durability, 0.0, 1.0)
	var armor_class := GlobalData.part_stat(inst, "armor", 0.0)
	
	lines.append("ARMOR HP: %.0f / %.0f" % [full_hp, full_hp])
	if dur < 0.999:
		var col_tag := "#ff4444" if dur <= 0.35 else "#ffaa33"
		lines.append("DURABILITY: [color=%s]%.0f%% (DEF Mitigation: %.0f%%)[/color]" % [col_tag, dur * 100.0, dur * 100.0])
	else:
		lines.append("DURABILITY: [color=#44ff77]100%% (Pristine DEF: 100%%)[/color]")

	if armor_class > 0.0:
		var eff_ac := armor_class * dur
		if dur < 0.999:
			lines.append("ARMOR CLASS: %.1f (Base: %.0f)" % [eff_ac, armor_class])
		else:
			lines.append("ARMOR CLASS: %.0f" % armor_class)

	var weight := GlobalData.part_stat(inst, "weight", 0.0)
	if weight > 0.0:
		lines.append("WEIGHT: %.1f kg" % weight)

	var upg := int(inst.get("upgrade_level", 1))
	lines.append("TIER: %s" % GlobalData.part_tier_text(upg))
	if upg > 1:
		lines.append("UPGRADES: %d (+%d HP)" % [upg - 1, (upg - 1) * 15])

	return "\n".join(lines)


# Builds a frame stat block for an inner frame catalog entry (type, frame HP,
# weight, field-pack carry bonus). Mirrors weapon_capability_text so frames
# get the same rich stat cards as weapons and armor.
static func frame_capability_text(info: Dictionary, durability: float = 1.0) -> String:
	if info.is_empty():
		return ""
	var lines: Array[String] = []

	lines.append("TYPE: %s" % info.get("type", "Inner Frame"))

	var fhp := float(info.get("hp", info.get("max_hp", 20.0)))
	var dur := clampf(durability, 0.0, 1.0)
	lines.append("FRAME HP: %.0f / %.0f" % [fhp, fhp])
	if dur < 0.999:
		var col_tag := "#ff4444" if dur <= 0.35 else "#ffaa33"
		lines.append("DURABILITY: [color=%s]%.0f%% (DEF Mitigation: %.0f%%)[/color]" % [col_tag, dur * 100.0, dur * 100.0])
	else:
		lines.append("DURABILITY: [color=#44ff77]100%% (Pristine DEF: 100%%)[/color]")

	var fwt := float(info.get("weight", 0.0))
	if fwt > 0.0:
		lines.append("WEIGHT: %.1f kg" % fwt)

	var bonus := float(info.get("carry_bonus", 0.0))
	if bonus > 0.0:
		lines.append("FIELD PACK BONUS: +%.1f kg" % bonus)

	return "\n".join(lines)


## Builds the Technology and Physical Compatibility status block for the Detail Panel.
## Formats authoritative validation results returned by LoadoutSystem.validate_equip_request.
static func technology_status_block(validation: Dictionary) -> String:
	if validation.is_empty():
		return ""
	var is_legacy: bool = bool(validation.get("is_legacy_neutral", false))
	var tid: String = str(validation.get("tech_id", ""))
	if is_legacy or tid == "":
		return "\n[color=#88aacc]TECHNOLOGY & COMPATIBILITY:[/color]\n  Technology: [color=#44ff77]CONVENTIONAL (Standard)[/color]\n  Frame Compatibility: [color=#44ff77]COMPATIBLE[/color]\n  Equip Status: [color=#44ff77]AVAILABLE[/color]"

	var tech_allowed: bool = bool(validation.get("technology_allowed", false))
	var phys_compat: bool = bool(validation.get("physically_compatible", false))
	var can_eq: bool = bool(validation.get("can_equip", false))
	var reason: String = str(validation.get("reason", ""))

	var tech_status_str := "[color=#44ff77]USABLE[/color]" if tech_allowed else "[color=#ff5555]NOT USABLE (Locked)[/color]"
	var frame_status_str := "[color=#44ff77]COMPATIBLE[/color]" if phys_compat else "[color=#ffaa33]INCOMPATIBLE[/color]"

	var equip_status_str := "[color=#44ff77]AVAILABLE[/color]"
	if not can_eq:
		if reason == "technology_locked":
			equip_status_str = "[color=#ff5555]LOCKED (Technology not authorized)[/color]"
		elif reason == "physically_incompatible":
			equip_status_str = "[color=#ffaa33]LOCKED (Current frame cannot support this hardware)[/color]"
		elif reason == "arm_destroyed":
			equip_status_str = "[color=#ff5555]LOCKED (Arm is destroyed)[/color]"
		else:
			equip_status_str = "[color=#ff5555]LOCKED[/color]"

	var lines: Array[String] = [
		"\n[color=#88aacc]TECHNOLOGY & COMPATIBILITY:[/color]",
		"  Technology (%s): %s" % [tid, tech_status_str],
		"  Frame Compatibility: %s" % frame_status_str,
		"  Equip Status: %s" % equip_status_str
	]
	return "\n".join(lines)

