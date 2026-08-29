class_name RepairSystem
extends RefCounted

# -----------------------------------------------------------------------------
# REPAIR / SCRAP PATCHES
# Repair costing and emergency scrap-patch logic extracted from GlobalData so
# the run-state autoload stays focused on state. Every function reads/writes
# state through the GlobalData singleton, and GlobalData keeps thin
# get_repair_cost()/apply_emergency_repair()/... facades for its callers.
#
# A patched slot uses WEAKER scrap stats derived from the driver's repair-skill
# tier and stays patched until a professional mechanic rebuilds the real armor.
#   key: slot name
#   value: {
#     "tier": 1..5, "stat_scale": 0.40..0.80,
#     "scrap_armor_hp": float, "scrap_frame_hp": float,
#     "armor_class": float, "scrap_spent": int,
#     "primitives": [ {shape, pos, rot, scale, color} ]
#   }
# -----------------------------------------------------------------------------


# Credit cost to fully repair a slot (armor + inner frame). One formula, used by
# every repair UI so the same damage always costs the same credits.
static func get_repair_cost(slot: String) -> int:
	var dmg := clampf(float(GlobalData.weapons.part_damage.get(slot, 0.0)), 0.0, 1.0)
	var frame_dmg := clampf(float(GlobalData.weapons.part_damage.get(slot + "_frame", 0.0)), 0.0, 1.0)
	if dmg <= 0.0 and frame_dmg <= 0.0:
		return 0
	var armor_max_hp: float = float(GlobalData.weapons.part_stat(GlobalData.weapons.equipped_parts.get(slot), "max_hp", 50.0))
	var frame_max_hp: float = float(GlobalData.weapons.part_stat(GlobalData.weapons.equipped_frames.get(slot), "max_hp", 50.0))
	var cost: float = dmg * armor_max_hp * GlobalData.REPAIR_COST_PER_HP
	cost += frame_dmg * frame_max_hp * GlobalData.REPAIR_COST_PER_HP
	return maxi(1, int(ceil(cost)))


# Scrap cost to emergency-patch a slot, based on how much of it is damaged.
static func get_emergency_repair_scrap_cost(slot: String) -> int:
	var dmg := clampf(float(GlobalData.weapons.part_damage.get(slot, 0.0)), 0.0, 1.0)
	var frame_dmg := clampf(float(GlobalData.weapons.part_damage.get(slot + "_frame", 0.0)), 0.0, 1.0)
	if dmg <= 0.0 and frame_dmg <= 0.0:
		return 0
	var armor_max_hp: float = float(GlobalData.weapons.part_stat(GlobalData.weapons.equipped_parts.get(slot), "max_hp", 50.0))
	var frame_max_hp: float = float(GlobalData.weapons.part_stat(GlobalData.weapons.equipped_frames.get(slot), "max_hp", 50.0))
	var cost: int = int(GlobalData.EMERGENCY_REPAIR_BASE_SCRAP)
	cost += int(ceil(dmg * armor_max_hp * GlobalData.EMERGENCY_REPAIR_SCRAP_PER_ARMOR_HP))
	cost += int(ceil(frame_dmg * frame_max_hp * GlobalData.EMERGENCY_REPAIR_SCRAP_PER_FRAME_HP))
	return maxi(1, cost)


# Builds and records a scrap patch on a slot: spends scrap, restores the slot to
# a partial weaker state (stats scaled by the driver's repair-skill tier) and
# clears its damage. Returns the patch, or {} when the slot is fine / unaffordable.
static func apply_emergency_repair(slot: String, primitives: Array = []) -> Dictionary:
	if slot not in GlobalData.MECHA_SLOTS:
		return {}
	var cost := get_emergency_repair_scrap_cost(slot)
	if cost <= 0 or GlobalData.currency.scrap < cost:
		return {}
	GlobalData.currency.scrap -= cost

	var tier := FleetSystem.get_scrap_armor_tier()
	var scale := FleetSystem.get_scrap_armor_stat_scale()
	var armor_max_hp: float = float(GlobalData.weapons.part_stat(GlobalData.weapons.equipped_parts.get(slot), "max_hp", 50.0))
	var frame_max_hp: float = float(GlobalData.weapons.part_stat(GlobalData.weapons.equipped_frames.get(slot), "max_hp", 50.0))

	var armor_class := 1.0
	var p = GlobalData.weapons.equipped_parts.get(slot)
	if p:
		if p.get("armor_class") != null:
			armor_class = float(p.armor_class)
		elif p.get("armor") != null:
			armor_class = maxf(float(p.get("armor", 10.0)) / 10.0, 0.1)

	# Primitives are stored JSON-safe (arrays for vec3/color) so the patch
	# survives save_run()/load_run() round-trips.
	var safe_primitives: Array = []
	for primitive in primitives:
		if primitive is Dictionary:
			safe_primitives.append(_scrap_primitive_to_json_safe(primitive))

	var patch := {
		"tier": tier,
		"stat_scale": scale,
		"scrap_armor_hp": maxf(armor_max_hp * scale, 1.0),
		"scrap_frame_hp": maxf(frame_max_hp * scale, 1.0),
		"armor_class": maxf(armor_class * scale, 0.1),
		"scrap_spent": cost,
		"primitives": safe_primitives,
	}
	GlobalData.weapons.scrap_patches[slot] = patch
	# GDD §6.2: If the frame was damaged, spawn composite cloth binding visual.
	var had_frame_damage := float(GlobalData.weapons.part_damage.get(slot + "_frame", 0.0)) > 0.0
	GlobalData.weapons.part_damage.erase(slot)
	GlobalData.weapons.part_damage.erase(slot + "_frame")
	GlobalData.weapons.part_hit_meta.erase(slot)
	if had_frame_damage:
		GlobalData.weapons.frame_bindings[slot] = true

	# Quick scrap repair taxes max durability by 2% (wear and tear on crude patching)
	ArmorSystem.degrade_equipped_armor(slot, 0.02)

	# Practice makes perfect — patching is how the driver's repair skill grows.
	FleetSystem.gain_repair_xp(10 + cost)
	return patch


# Converts a scrap primitive's Vector3/Color fields into JSON-safe arrays.
static func _scrap_primitive_to_json_safe(primitive: Dictionary) -> Dictionary:
	var out := primitive.duplicate(true)
	var pos = primitive.get("pos")
	if pos is Vector3:
		out["pos"] = [pos.x, pos.y, pos.z]
	var rot = primitive.get("rot")
	if rot is Vector3:
		out["rot"] = [rot.x, rot.y, rot.z]
	var scale = primitive.get("scale")
	if scale is Vector3:
		out["scale"] = [scale.x, scale.y, scale.z]
	elif scale is float or scale is int:
		var f := float(scale)
		out["scale"] = [f, f, f]
	var color = primitive.get("color")
	if color is Color:
		out["color"] = [color.r, color.g, color.b, color.a]
	return out


static func scrap_primitive_pos(primitive: Dictionary) -> Vector3:
	var raw = primitive.get("pos")
	if raw is Vector3:
		return raw
	if raw is Array and raw.size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.ZERO


static func scrap_primitive_rot(primitive: Dictionary) -> Vector3:
	var raw = primitive.get("rot")
	if raw is Vector3:
		return raw
	if raw is Array and raw.size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.ZERO


static func scrap_primitive_scale(primitive: Dictionary) -> Vector3:
	var raw = primitive.get("scale")
	if raw is Vector3:
		return raw
	if raw is Array and raw.size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	var flat = primitive.get("scale")
	if flat is float or flat is int:
		var f := float(flat)
		return Vector3(f, f, f)
	return Vector3.ONE


static func scrap_primitive_color(primitive: Dictionary) -> Color:
	var raw = primitive.get("color")
	if raw is Color:
		return raw
	if raw is Array and raw.size() >= 4:
		return Color(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
	return Color(0.55, 0.55, 0.6, 1.0)


static func has_scrap_patch(slot: String) -> bool:
	return GlobalData.weapons.scrap_patches.has(slot)


static func remove_scrap_patch(slot: String) -> void:
	GlobalData.weapons.scrap_patches.erase(slot)


# -----------------------------------------------------------------------------
# PROFESSIONAL REPAIR — a fleet mechanic / village workshop rebuilds a scrap-
# patched (or damaged) slot into fresh catalog armor. Costs credits and consumes
# the node you're standing on. Returns the credit price for the slot.
# -----------------------------------------------------------------------------


static func get_professional_repair_cost(slot: String) -> int:
	if slot not in GlobalData.MECHA_SLOTS:
		return 0
	var armor_max_hp: float = float(GlobalData.weapons.part_stat(GlobalData.weapons.equipped_parts.get(slot), "max_hp", 50.0))
	var frame_max_hp: float = float(GlobalData.weapons.part_stat(GlobalData.weapons.equipped_frames.get(slot), "max_hp", 50.0))
	var cost: float = float(armor_max_hp * GlobalData.PROFESSIONAL_REPAIR_CREDITS_PER_ARMOR_HP)
	cost += float(frame_max_hp * GlobalData.PROFESSIONAL_REPAIR_CREDITS_PER_FRAME_HP)
	return maxi(1, int(ceil(cost)))


# The mechanic rebuilds the slot: removes any scrap patch, clears all damage and
# restores the real catalog armor at full HP. Returns false if unaffordable.
static func apply_professional_repair(slot: String) -> bool:
	if slot not in GlobalData.MECHA_SLOTS:
		return false
	var cost := get_professional_repair_cost(slot)
	if GlobalData.currency.credits < cost:
		return false
	GlobalData.currency.credits -= cost
	GlobalData.weapons.scrap_patches.erase(slot)
	GlobalData.weapons.part_damage.erase(slot)
	GlobalData.weapons.part_damage.erase(slot + "_frame")
	GlobalData.weapons.part_hit_meta.erase(slot)
	# GDD §6.2: Professional repair removes frame bindings (real armor restored)
	GlobalData.weapons.frame_bindings.erase(slot)
	return true
