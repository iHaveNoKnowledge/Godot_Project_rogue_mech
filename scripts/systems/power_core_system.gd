extends RefCounted

## ---------------------------------------------------------------------------
## POWER CORE SYSTEM — GDD §4.3 Torso Power Core Classes
##
## Three engine archetypes that modify board movement cost, combat heat
## accumulation, roller-dash speed, and frame durability risk.
##
## Core class is stored in GlobalData.weapons.power_core_id (String).
## ---------------------------------------------------------------------------

# ---- Core Class IDs ----
const COMBUSTION := "combustion"       # Direct Combustion Core
const HYBRID := "hybrid"               # Overclocked Hybrid Core
const ANCIENT := "ancient"             # Ancient / Legendary Core (GN Drive)

const DEFAULT_CORE := COMBUSTION

# ---- Per-tile board energy cost multipliers (GDD §4.3) ----
const BOARD_COST_MULT := { "combustion": 1.0, "hybrid": 0.8, "ancient": 0.0 }

# ---- Combat heat accumulation multipliers (GDD §4.3) ----
const HEAT_ACCUM_MULT := { "combustion": 1.0, "hybrid": 1.5, "ancient": 0.3 }

# ---- Roller-dash speed multipliers (GDD §4.3) ----
const DASH_SPEED_MULT := { "combustion": 0.9, "hybrid": 1.25, "ancient": 1.15 }

# ---- Passive heat accumulation per second in combat (GDD §4.3) ----
const PASSIVE_HEAT_PER_SEC := { "combustion": 0.8, "hybrid": 0.0, "ancient": 0.0 }

# ---- Heat → Frame Durability penalty (GDD §4.3 Hybrid only) ----
const HYBRID_FRAME_HEAT_THRESHOLD := 0.75
const HYBRID_FRAME_DURABILITY_DRAIN := 0.02

# ---- Fuel type compatibility (GDD §4.2) ----
# FuelType: CRUDE_OIL=0, REFINED_CELL=1, BIO_FUEL=2
const COMPATIBLE_FUEL := {
	"combustion": [0, 2],
	"hybrid": [1, 2],
	"ancient": [1],
}

const BIO_FUEL_HEAT_PENALTY := 1.3

# ---- Loot drop behavior (GDD §4.3) ----
const DROPS_LOOT := { "combustion": true, "hybrid": true, "ancient": false }

# ---- Hunter-Killer attraction (GDD §4.3) ----
const HK_ATTRACTION_MULT := { "combustion": 1.0, "hybrid": 1.0, "ancient": 2.0 }

# ---- Display / Description ----
const DISPLAY_NAMES := {
	"combustion": "Direct Combustion Core",
	"hybrid": "Overclocked Hybrid Core",
	"ancient": "Ancient Legendary Core",
}

const DESCRIPTIONS := {
	"combustion": "Heavy diesel engine. Uses Crude Oil, high torque for heavy weapons, but medium heat buildup and slower dash.",
	"hybrid": "Overclocked turbine. Saves 20% fuel, powerful roller-dash, but runs dangerously hot — high heat drains Frame Durability.",
	"ancient": "GN-Drive relic. Zero fuel cost on board, sustains beam fire, but cannot drop parts and attracts Hunter-Killer fleets.",
}


# ==========================================================================
# STATIC HELPERS
# ==========================================================================

static func _dict_val(dict: Dictionary, key: String, default) -> Variant:
	return dict[key] if dict.has(key) else default


static func get_current_core() -> String:
	return str(GlobalData.weapons.get("power_core_id")) if GlobalData.weapons.get("power_core_id") != null else COMBUSTION


static func set_core(core_id: String) -> void:
	if core_id in BOARD_COST_MULT:
		GlobalData.weapons.power_core_id = core_id


static func board_cost_multiplier(core_id: String = "") -> float:
	if core_id == "":
		core_id = get_current_core()
	return float(_dict_val(BOARD_COST_MULT, core_id, 1.0))


static func heat_accumulation_multiplier(core_id: String = "", using_bio_fuel: bool = false) -> float:
	if core_id == "":
		core_id = get_current_core()
	var mult = float(_dict_val(HEAT_ACCUM_MULT, core_id, 1.0))
	if using_bio_fuel and core_id == HYBRID:
		mult *= BIO_FUEL_HEAT_PENALTY
	return mult


static func passive_heat_rate(core_id: String = "") -> float:
	if core_id == "":
		core_id = get_current_core()
	return float(_dict_val(PASSIVE_HEAT_PER_SEC, core_id, 0.0))


static func dash_speed_multiplier(core_id: String = "") -> float:
	if core_id == "":
		core_id = get_current_core()
	return float(_dict_val(DASH_SPEED_MULT, core_id, 1.0))


static func has_frame_heat_risk(core_id: String = "") -> bool:
	if core_id == "":
		core_id = get_current_core()
	return core_id == HYBRID


static func frame_heat_drain_rate(heat_ratio: float, core_id: String = "") -> float:
	if core_id == "":
		core_id = get_current_core()
	if core_id != HYBRID:
		return 0.0
	if heat_ratio < HYBRID_FRAME_HEAT_THRESHOLD:
		return 0.0
	return HYBRID_FRAME_DURABILITY_DRAIN


static func drops_loot(core_id: String = "") -> bool:
	if core_id == "":
		core_id = get_current_core()
	return bool(_dict_val(DROPS_LOOT, core_id, true))


static func hk_attraction_multiplier(core_id: String = "") -> float:
	if core_id == "":
		core_id = get_current_core()
	return float(_dict_val(HK_ATTRACTION_MULT, core_id, 1.0))


static func display_name(core_id: String) -> String:
	return str(_dict_val(DISPLAY_NAMES, core_id, core_id))


static func description(core_id: String) -> String:
	return str(_dict_val(DESCRIPTIONS, core_id, ""))


static func is_fuel_compatible(core_id: String, fuel_type: int) -> bool:
	if core_id == "":
		core_id = get_current_core()
	var compat = COMPATIBLE_FUEL[core_id] if COMPATIBLE_FUEL.has(core_id) else []
	return fuel_type in compat


static func stats_summary(core_id: String) -> Dictionary:
	var s: Dictionary = {}
	s["id"] = core_id
	s["name"] = display_name(core_id)
	s["board_cost_mult"] = board_cost_multiplier(core_id)
	s["heat_accum_mult"] = heat_accumulation_multiplier(core_id)
	s["passive_heat"] = passive_heat_rate(core_id)
	s["dash_speed_mult"] = dash_speed_multiplier(core_id)
	s["frame_heat_risk"] = has_frame_heat_risk(core_id)
	s["drops_loot"] = drops_loot(core_id)
	s["hk_attraction"] = hk_attraction_multiplier(core_id)
	return s
