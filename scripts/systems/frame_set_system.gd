class_name FrameSetSystem
extends RefCounted

## ---------------------------------------------------------------------------
## FRAME SET SYSTEM — Data-Driven Frame Set Bonuses (Phase 2B-2)
##
## Evaluates relationships between the six anatomical Frame segments:
##   - head
##   - body (or torso)
##   - arm_left
##   - arm_right
##   - leg_left
##   - leg_right
##
## Each equipped Frame segment provides a `frame_set_id`. This system:
##   - Identifies frame sets and counts equipped pieces across the 6 segments.
##   - Evaluates active set tiers against data-driven arbitrary thresholds.
##   - Aggregates active set bonuses (stat modifiers & special capabilities).
##   - Computes derived stats without mutating base frame definitions or instances.
##   - Supports multiple simultaneous active sets and clean safe fallbacks.
## ---------------------------------------------------------------------------

const SLOTS: Array[String] = [
	"head",
	"body",
	"arm_left",
	"arm_right",
	"leg_left",
	"leg_right"
]

# Built-in Default Set Definitions registry
static var _registry: Dictionary = {}
static var _registry_initialized: bool = false


# ===========================================================================
# REGISTRY MANAGEMENT & DEFINITIONS
# ===========================================================================

static func _ensure_registry() -> void:
	if _registry_initialized:
		return
	_registry_initialized = true
	_registry.clear()

	# 1. Standard Mass-Production Frame Set
	register_set_definition({
		"id": "standard",
		"name": "Standard Frame",
		"description": "Reliable mass-production structural frame. Balanced durability and maintenance efficiency.",
		"bonuses": {
			2: {
				"description": "+10 Frame HP",
				"stats": {"hp_flat": 10.0}
			},
			4: {
				"description": "+5 kg Carry Capacity",
				"stats": {"carry_capacity_flat": 5.0}
			},
			6: {
				"description": "Standard Maintenance Protocol (+15 Frame HP, +5 kg Carry Capacity)",
				"stats": {"hp_flat": 15.0, "carry_capacity_flat": 5.0},
				"capabilities": ["standard_field_maintenance"]
			}
		}
	})

	# 2. Valkyrion Neural-Link Frame Set
	register_set_definition({
		"id": "valkyrion",
		"name": "Valkyrion Frame",
		"description": "Alaya-Vijnana neural-link chassis. High agility, recoil dampening, and reactive overdrive.",
		"bonuses": {
			2: {
				"description": "+15% Recoil Resistance",
				"stats": {"recoil_resistance_add": 0.15}
			},
			4: {
				"description": "+10% Movement Speed",
				"stats": {"movement_speed_mult": 1.10}
			},
			6: {
				"description": "Neural-Link Overdrive Capability",
				"capabilities": ["valkyrion_overdrive"]
			}
		}
	})

	# 3. Scrap Pilgrim (Vagrant) Pre-Cog Frame Set
	register_set_definition({
		"id": "vagrant",
		"name": "Scrap Pilgrim Frame",
		"description": "Resonant wasteland frame kitbashed from high-yield relics. Extreme scrap efficiency.",
		"bonuses": {
			2: {
				"description": "+5 kg Carry Capacity",
				"stats": {"carry_capacity_flat": 5.0}
			},
			4: {
				"description": "+20% Scrap Salvage Yield",
				"stats": {"scrap_yield_mult": 1.20}
			},
			6: {
				"description": "Pre-Cog Hazard Instinct",
				"capabilities": ["vagrant_hazard_sense"]
			}
		}
	})

	# 4. Heavy / Titan Siege Frame Set
	register_set_definition({
		"id": "heavy",
		"name": "Titan Heavy Frame",
		"description": "Reinforced siege chassis designed for heavy weapon platforms and sustained impact.",
		"bonuses": {
			2: {
				"description": "+20 Frame HP",
				"stats": {"hp_flat": 20.0}
			},
			4: {
				"description": "+25% Recoil Resistance",
				"stats": {"recoil_resistance_add": 0.25}
			},
			6: {
				"description": "Siege Fortress Anchorage",
				"capabilities": ["heavy_siege_lock"]
			}
		}
	})


## Registers or updates a data-driven frame set definition.
static func register_set_definition(def: Dictionary) -> void:
	_ensure_registry()
	var set_id := str(def.get("id", "")).to_lower().strip_edges()
	if set_id == "":
		return
	_registry[set_id] = def.duplicate(true)


## Resets the registry back to built-in default definitions.
static func reset_set_definitions() -> void:
	_registry_initialized = false
	_registry.clear()
	_ensure_registry()


## Retrieves a registered frame set definition by ID.
static func get_set_definition(set_id: String) -> Dictionary:
	_ensure_registry()
	var sid := set_id.to_lower().strip_edges()
	return _registry.get(sid, {}).duplicate(true)


## Returns all registered set definitions.
static func get_all_set_definitions() -> Dictionary:
	_ensure_registry()
	return _registry.duplicate(true)


# ===========================================================================
# PIECE COUNTING & SLOT EVALUATION
# ===========================================================================

## Scans the 6 anatomical frame slots and returns a count of equipped pieces
## per set_id: { "valkyrion": 4, "vagrant": 2 }.
## Strictly ignores armor, backpacks, generators, weapons, modules, and attachments.
static func get_equipped_set_counts() -> Dictionary:
	var counts: Dictionary = {}
	if GlobalData == null or GlobalData.weapons == null or not ("equipped_frames" in GlobalData.weapons):
		return counts

	var equipped_frames = GlobalData.weapons.equipped_frames
	if not (equipped_frames is Dictionary):
		return counts

	for slot in SLOTS:
		var frame = equipped_frames.get(slot, null)
		if frame == null or not (frame is Dictionary) or frame.is_empty():
			continue

		var set_id: String = str(frame.get("frame_set_id", "")).to_lower().strip_edges()
		if set_id == "":
			# Fallback: if frame has no set_id, infer from schema
			var schematized := GlobalData.ensure_frame_data_schema(frame, slot)
			set_id = str(schematized.get("frame_set_id", "")).to_lower().strip_edges()

		if set_id != "":
			counts[set_id] = counts.get(set_id, 0) + 1

	return counts


## Returns the number of pieces equipped for a specific frame set (0 to 6).
static func get_set_piece_count(set_id: String) -> int:
	var counts := get_equipped_set_counts()
	return int(counts.get(set_id.to_lower().strip_edges(), 0))


# ===========================================================================
# TIER EVALUATION & ACTIVE BONUSES
# ===========================================================================

## Returns a sorted Array of active tier threshold integers for the given set (e.g. [2, 4]).
## Thresholds are data-driven and can be non-standard (e.g. [3, 5, 6]).
static func get_active_set_tiers(set_id: String) -> Array[int]:
	var active_tiers: Array[int] = []
	var def := get_set_definition(set_id)
	if def.is_empty() or not def.has("bonuses"):
		return active_tiers

	var count := get_set_piece_count(set_id)
	if count <= 0:
		return active_tiers

	var bonuses: Dictionary = def.get("bonuses", {})
	var thresholds: Array[int] = []
	for key in bonuses:
		var t := int(key)
		if t > 0:
			thresholds.append(t)
	thresholds.sort()

	for t in thresholds:
		if count >= t:
			active_tiers.append(t)

	return active_tiers


## Checks if a specific threshold bonus is active for the given set.
static func is_set_bonus_active(set_id: String, threshold: int) -> bool:
	var active_tiers := get_active_set_tiers(set_id)
	return threshold in active_tiers


## Collects all active bonus descriptors across all equipped frame sets.
## Evaluates multiple simultaneous sets independently.
static func get_active_set_bonuses() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var counts := get_equipped_set_counts()

	for set_id in counts:
		var count: int = counts[set_id]
		var def := get_set_definition(set_id)
		if def.is_empty() or not def.has("bonuses"):
			continue

		var set_name: String = str(def.get("name", set_id.capitalize()))
		var bonuses: Dictionary = def.get("bonuses", {})

		var thresholds: Array[int] = []
		for key in bonuses:
			var t := int(key)
			if t > 0:
				thresholds.append(t)
		thresholds.sort()

		for t in thresholds:
			if count >= t:
				var bonus_info = bonuses.get(t, bonuses.get(str(t), {}))
				if bonus_info is Dictionary:
					var item: Dictionary = (bonus_info as Dictionary).duplicate(true)
					item["set_id"] = set_id
					item["set_name"] = set_name
					item["threshold"] = t
					result.append(item)

	return result


# ===========================================================================
# BONUS STAT AGGREGATION & DERIVATION (Non-Mutating)
# ===========================================================================

## Aggregates all currently active set bonuses into a combined modifier structure.
## Never mutates base frame stats.
static func aggregate_active_stats() -> Dictionary:
	var agg: Dictionary = {
		"hp_flat": 0.0,
		"carry_capacity_flat": 0.0,
		"recoil_resistance_add": 0.0,
		"movement_speed_mult": 1.0,
		"scrap_yield_mult": 1.0,
		"capabilities": []
	}

	var active_bonuses := get_active_set_bonuses()
	for bonus in active_bonuses:
		var stats = bonus.get("stats", {})
		if stats is Dictionary:
			if stats.has("hp_flat"):
				agg["hp_flat"] += float(stats["hp_flat"])
			if stats.has("carry_capacity_flat"):
				agg["carry_capacity_flat"] += float(stats["carry_capacity_flat"])
			if stats.has("recoil_resistance_add"):
				agg["recoil_resistance_add"] += float(stats["recoil_resistance_add"])
			if stats.has("movement_speed_mult"):
				agg["movement_speed_mult"] *= float(stats["movement_speed_mult"])
			if stats.has("scrap_yield_mult"):
				agg["scrap_yield_mult"] *= float(stats["scrap_yield_mult"])

		var caps = bonus.get("capabilities", [])
		if caps is Array:
			for cap in caps:
				var scap := str(cap)
				if not scap in agg["capabilities"]:
					agg["capabilities"].append(scap)

	return agg


## Returns a list of all active special capabilities unlocked by full/partial sets.
static func get_active_capabilities() -> Array[String]:
	var agg := aggregate_active_stats()
	var caps: Array = agg.get("capabilities", [])
	var out: Array[String] = []
	for c in caps:
		out.append(str(c))
	return out


## Computes final derived stats from base frame stats without mutating input.
## Example base_stats: {"hp": 100.0, "carry_capacity": 50.0, "recoil_resistance": 0.2}
static func apply_set_bonuses_to_stats(base_stats: Dictionary) -> Dictionary:
	var derived := base_stats.duplicate(true)
	var agg := aggregate_active_stats()

	if derived.has("hp"):
		derived["hp"] = float(derived["hp"]) + float(agg.get("hp_flat", 0.0))
	if derived.has("carry_capacity"):
		derived["carry_capacity"] = float(derived["carry_capacity"]) + float(agg.get("carry_capacity_flat", 0.0))
	if derived.has("carry_bonus"):
		derived["carry_bonus"] = float(derived["carry_bonus"]) + float(agg.get("carry_capacity_flat", 0.0))
	if derived.has("recoil_resistance"):
		derived["recoil_resistance"] = float(derived["recoil_resistance"]) + float(agg.get("recoil_resistance_add", 0.0))
	if derived.has("speed"):
		derived["speed"] = float(derived["speed"]) * float(agg.get("movement_speed_mult", 1.0))
	if derived.has("movement_speed"):
		derived["movement_speed"] = float(derived["movement_speed"]) * float(agg.get("movement_speed_mult", 1.0))

	derived["unlocked_capabilities"] = get_active_capabilities()
	return derived


# ===========================================================================
# UI & FORMATTING HELPERS
# ===========================================================================

## Formats active frame sets and tier bonuses into a BBCode string for UI display.
static func format_set_summary_bbcode() -> String:
	var counts := get_equipped_set_counts()
	if counts.is_empty():
		return ""

	var lines: Array[String] = []
	for set_id in counts:
		var count: int = counts[set_id]
		var def := get_set_definition(set_id)
		var set_name: String = str(def.get("name", set_id.capitalize()))
		lines.append("[b][color=#00e5ff]%s Set[/color][/b] (%d/6)" % [set_name, count])

		var bonuses: Dictionary = def.get("bonuses", {})
		var thresholds: Array[int] = []
		for key in bonuses:
			var t := int(key)
			if t > 0:
				thresholds.append(t)
		thresholds.sort()

		for t in thresholds:
			var b = bonuses.get(t, bonuses.get(str(t), {}))
			var desc: String = str(b.get("description", "Tier bonus"))
			if count >= t:
				lines.append("  [color=#44ff77]✓ %d-Piece:[/color] %s" % [t, desc])
			else:
				lines.append("  [color=#888888]○ %d-Piece:[/color] %s" % [t, desc])

	return "\n".join(lines)
