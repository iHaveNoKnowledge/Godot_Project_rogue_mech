class_name FrameModuleSystem
extends RefCounted

## ---------------------------------------------------------------------------
## FRAME MODULE SYSTEM — "Sleeper Build Engine" (Roguelike Relic Architecture)
##
## Allows installing high-tech prototype and overclock modules directly into the
## Mecha's Inner Frame sockets. Outer armor can be rusty, scrap-patched, or
## scavenged, but the inner skeleton houses the roaring V8 engine and prototype
## chips that break game rules and create exponential combat synergies.
## ---------------------------------------------------------------------------

const DEFAULT_SOCKET_COUNTS: Dictionary = {
	"head": 1,
	"body": 3,
	"torso": 3,
	"arm_left": 1,
	"arm_right": 1,
	"leg_left": 1,
	"leg_right": 1,
}

# Legacy alias for backward compatibility with older tests/callers
const SOCKET_COUNTS: Dictionary = {
	"torso": 3,
	"arm_left": 1,
	"arm_right": 1,
	"leg_left": 1,
	"leg_right": 1,
}

static func normalize_slot_name(slot: String) -> String:
	var s := str(slot).to_lower().strip_edges()
	if s == "torso":
		return "body"
	return s

const MODULE_CATALOG: Dictionary = {
	"v8_twin_turbo": {
		"id": "v8_twin_turbo",
		"name": "Twin-Turbo Kinetic Pump",
		"category": "leg",
		"tier": "prototype",
		"desc": "V8 Supercharger: Consecutive dashes chain momentum, boosting speed by +20% per stack (max 3 stacks). High-velocity dashes stagger light foes.",
		"effects": {
			"dash_stack_boost": 0.20,
			"max_dash_stacks": 3,
			"dash_ram_stagger": true,
		},
		"rarity_color": Color(1.0, 0.45, 0.1), # High-octane Orange
	},
	"heat_kinetic_converter": {
		"id": "heat_kinetic_converter",
		"name": "Heat-to-Kinetic Converter",
		"category": "torso",
		"tier": "military",
		"desc": "Converts excess reactor thermal stress into kinetic acceleration: Fire rate and bullet speed scale up to +50% as heat builds up.",
		"effects": {
			"heat_fire_rate_scale": 0.50,
			"heat_proj_speed_scale": 0.35,
		},
		"rarity_color": Color(0.95, 0.25, 0.2), # Fiery Red
	},
	"cryo_heatsink_loop": {
		"id": "cryo_heatsink_loop",
		"name": "Cryo Heatsink Loop",
		"category": "torso",
		"tier": "military",
		"desc": "Liquid-cryo heatsink loop: +25% weapon heat capacity and +40% heat cool rate. Energy weapons stay in the fight longer.",
		"effects": {
			"heat_capacity_mult": 1.25,
			"heat_cool_rate_mult": 1.40,
		},
		"rarity_color": Color(0.35, 0.85, 1.0), # Cryo Cyan
	},
	"vent_protocol": {
		"id": "vent_protocol",
		"name": "Vent Protocol Actuator",
		"category": "arm",
		"tier": "scrap",
		"desc": "Scavenged barrel vents: each shot generates 30% less heat and residual heat sheds 15% faster.",
		"effects": {
			"heat_per_shot_mult": 0.70,
			"heat_cool_rate_mult": 1.15,
		},
		"rarity_color": Color(0.65, 0.85, 0.75), # Vent Sage
	},
	"nitrous_scorch": {
		"id": "nitrous_scorch",
		"name": "Nitrous Scorch Injector",
		"category": "leg",
		"tier": "prototype",
		"desc": "Injects unburned nitrous into exhaust manifolds during dash maneuvers, leaving a lingering incendiary scorch trail.",
		"effects": {
			"dash_fire_trail": true,
			"dash_fire_dps": 30.0,
		},
		"rarity_color": Color(1.0, 0.6, 0.0),
	},
	"synaptic_reflex": {
		"id": "synaptic_reflex",
		"name": "Synaptic Reflex Processor",
		"category": "torso",
		"tier": "prototype",
		"desc": "Direct neural link: Performing a Precision Dash triggers 1.5s localized Bullet-Time and instantly reloads all equipped weapons.",
		"effects": {
			"precision_bullet_time": 1.5,
			"precision_instant_reload": true,
		},
		"rarity_color": Color(0.3, 0.85, 1.0), # Cyber Cyan
	},
	"predictive_matrix": {
		"id": "predictive_matrix",
		"name": "Weakpoint Predictive Matrix",
		"category": "arm",
		"tier": "military",
		"desc": "Ballistic target predictor: Consecutive hits on the same enemy part ramp up critical hit damage by +15% per shot (max +45%).",
		"effects": {
			"weakpoint_crit_ramp": 0.15,
			"max_crit_ramp": 0.45,
		},
		"rarity_color": Color(0.4, 0.9, 0.4), # Tactical Green
	},
	"phantom_decoy": {
		"id": "phantom_decoy",
		"name": "Phantom Decoy Emitter",
		"category": "torso",
		"tier": "prototype",
		"desc": "When any armor part shatters (HP reaches 0), instantly deploys an electronic countermeasure smoke screen and a holographic decoy for 3.5s.",
		"effects": {
			"armor_break_decoy": true,
			"decoy_duration": 3.5,
		},
		"rarity_color": Color(0.75, 0.35, 1.0), # Holographic Violet
	},
	"exposed_frame_berserk": {
		"id": "exposed_frame_berserk",
		"name": "Exposed Frame Berserk Circuit",
		"category": "torso",
		"tier": "scrap",
		"desc": "Sleeper hotrod governor bypass: Every broken armor plate or scrap frame binding increases movement speed by +15% and melee damage by +25%.",
		"effects": {
			"broken_slot_speed": 0.15,
			"broken_slot_melee": 0.25,
		},
		"rarity_color": Color(0.85, 0.2, 0.2), # Rust Blood
	},
	"dynamo_siphon": {
		"id": "dynamo_siphon",
		"name": "Dynamo Impact Siphon",
		"category": "torso",
		"tier": "military",
		"desc": "Kinetic absorption dynamos: Converts 25% of all damage absorbed by shields or armor into instant energy cell replenishment.",
		"effects": {
			"damage_to_energy_ratio": 0.25,
		},
		"rarity_color": Color(0.2, 0.7, 0.9), # Electric Blue
	},
	"scrap_cannibalizer": {
		"id": "scrap_cannibalizer",
		"name": "Scrap Cannibalizer Overdrive",
		"category": "arm",
		"tier": "scrap",
		"desc": "Junk scavenge claw: Destroying an enemy at close range (<10m) restores 15% Frame HP and grants 3 seconds of zero-heat dashing.",
		"effects": {
			"kill_heal_frame": 0.15,
			"kill_infinite_dash_sec": 3.0,
		},
		"rarity_color": Color(0.8, 0.7, 0.3),
	},
	"seismic_piston": {
		"id": "seismic_piston",
		"name": "Seismic Piston Anchors",
		"category": "leg",
		"tier": "military",
		"desc": "Heavy reinforced hydraulic pistons: Jump landings and ground-pound dashes emit a radial seismic wave that staggers nearby light mechas.",
		"effects": {
			"landing_shockwave": true,
			"shockwave_radius": 7.0,
			"shockwave_stagger": 1.0,
		},
		"rarity_color": Color(0.7, 0.5, 0.3),
	},
	"gatling_governor": {
		"id": "gatling_governor",
		"name": "Gatling Over-Torque Governor",
		"category": "arm",
		"tier": "military",
		"desc": "Allows sustained automatic fire to overclock the feed motor, spinning up weapon fire rate by up to +75% over 2 seconds of continuous firing.",
		"effects": {
			"spool_max_fire_rate": 0.75,
			"spool_time": 2.0,
		},
		"rarity_color": Color(1.0, 0.7, 0.2),
	},
	"nanite_frame_mesh": {
		"id": "nanite_frame_mesh",
		"name": "Nanite Frame Mesh",
		"category": "torso",
		"tier": "prototype",
		"desc": "Self-repairing nanite matrix: Slowly repairs damaged Frame HP in combat (1 HP/sec) and nullifies permanent metal fatigue degradation.",
		"effects": {
			"passive_frame_regen": 1.0,
			"immune_fatigue": true,
		},
		"rarity_color": Color(0.2, 0.95, 0.7), # Nanite Emerald
	},
	# ---- Unified Legacy Frame Properties (Migrated from frame_property_catalog) ----
	"mod_reactor_fission": {
		"id": "mod_reactor_fission",
		"name": "Fission Power Core",
		"category": "body",
		"tier": "military",
		"weight": 18.0,
		"desc": "Primary power reactor. +1000 Energy, +80/s Recharge rate.",
		"effects": {
			"energy_bonus": 1000.0,
			"recharge_bonus": 80.0,
		},
		"rarity_color": Color(0.2, 0.7, 1.0),
	},
	"mod_flight_booster": {
		"id": "mod_flight_booster",
		"name": "High-Output Vector Thruster",
		"category": "body",
		"tier": "military",
		"weight": 14.0,
		"desc": "Aerial thruster glide system. +25% Dash Speed.",
		"effects": {
			"dash_speed_bonus": 0.25,
			"flight_glide": true,
		},
		"rarity_color": Color(1.0, 0.5, 0.1),
	},
	"mod_cryo_heatsink": {
		"id": "mod_cryo_heatsink",
		"name": "Cryogenic Heat Dissipator",
		"category": "body",
		"tier": "thermal",
		"weight": 8.0,
		"desc": "Liquid coolant circulation. -30% Heat accumulation.",
		"effects": {
			"heat_reduction": 0.30,
		},
		"rarity_color": Color(0.3, 0.85, 1.0),
	},
	"mod_targeting_fcs": {
		"id": "mod_targeting_fcs",
		"name": "Tactical FCS Sensor",
		"category": "head",
		"tier": "sensor",
		"weight": 4.0,
		"desc": "+40% Lock-On tracking speed, -15% weapon spread.",
		"effects": {
			"lock_on_bonus": 0.40,
			"spread_reduction": 0.15,
		},
		"rarity_color": Color(0.2, 1.0, 0.4),
	},
	"mod_threat_analyzer": {
		"id": "mod_threat_analyzer",
		"name": "Weakpoint Scanner",
		"category": "head",
		"tier": "sensor",
		"weight": 5.0,
		"desc": "Analyzes armor fault lines. +15% Critical hit chance.",
		"effects": {
			"crit_bonus": 0.15,
		},
		"rarity_color": Color(1.0, 0.3, 0.3),
	},
	"mod_recoil_gyro_l": {
		"id": "mod_recoil_gyro_l",
		"name": "Gyro Recoil Compensator (L)",
		"category": "arm",
		"tier": "actuator",
		"weight": 6.0,
		"desc": "Torque dampeners. -35% weapon recoil kick.",
		"effects": {
			"recoil_reduction": 0.35,
		},
		"rarity_color": Color(0.8, 0.8, 0.3),
	},
	"mod_recoil_gyro_r": {
		"id": "mod_recoil_gyro_r",
		"name": "Gyro Recoil Compensator (R)",
		"category": "arm",
		"tier": "actuator",
		"weight": 6.0,
		"desc": "Torque dampeners. -35% weapon recoil kick.",
		"effects": {
			"recoil_reduction": 0.35,
		},
		"rarity_color": Color(0.8, 0.8, 0.3),
	},
	"mod_melee_hydraulic_l": {
		"id": "mod_melee_hydraulic_l",
		"name": "High-Torque Melee Actuator (L)",
		"category": "arm",
		"tier": "actuator",
		"weight": 10.0,
		"desc": "Reinforced arm servos. +30% Melee attack speed & damage.",
		"effects": {
			"melee_speed_bonus": 0.30,
		},
		"rarity_color": Color(1.0, 0.4, 0.1),
	},
	"mod_melee_hydraulic_r": {
		"id": "mod_melee_hydraulic_r",
		"name": "High-Torque Melee Actuator (R)",
		"category": "arm",
		"tier": "actuator",
		"weight": 10.0,
		"desc": "Reinforced arm servos. +30% Melee attack speed & damage.",
		"effects": {
			"melee_speed_bonus": 0.30,
		},
		"rarity_color": Color(1.0, 0.4, 0.1),
	},
	"mod_roller_overdrive_l": {
		"id": "mod_roller_overdrive_l",
		"name": "Roller Overdrive Bearings (L)",
		"category": "leg",
		"tier": "mobility",
		"weight": 8.0,
		"desc": "+30% Roller Dash speed, -20% roller energy cost.",
		"effects": {
			"roller_speed_bonus": 0.30,
		},
		"rarity_color": Color(0.4, 0.9, 1.0),
	},
	"mod_roller_overdrive_r": {
		"id": "mod_roller_overdrive_r",
		"name": "Roller Overdrive Bearings (R)",
		"category": "leg",
		"tier": "mobility",
		"weight": 8.0,
		"desc": "+30% Roller Dash speed, -20% roller energy cost.",
		"effects": {
			"roller_speed_bonus": 0.30,
		},
		"rarity_color": Color(0.4, 0.9, 1.0),
	},
	"mod_shock_absorbers_l": {
		"id": "mod_shock_absorbers_l",
		"name": "Hydraulic Impact Dampeners (L)",
		"category": "leg",
		"tier": "mobility",
		"weight": 7.0,
		"desc": "Zero landing stun, +20% jump height.",
		"effects": {
			"jump_bonus": 0.20,
		},
		"rarity_color": Color(0.9, 0.7, 0.2),
	},
	"mod_shock_absorbers_r": {
		"id": "mod_shock_absorbers_r",
		"name": "Hydraulic Impact Dampeners (R)",
		"category": "leg",
		"tier": "mobility",
		"weight": 7.0,
		"desc": "Zero landing stun, +20% jump height.",
		"effects": {
			"jump_bonus": 0.20,
		},
		"rarity_color": Color(0.9, 0.7, 0.2),
	},
}


# -----------------------------------------------------------------------------
# INITIALIZATION & SOCKET ACCESS
# -----------------------------------------------------------------------------

static func init_slots_if_needed() -> void:
	if GlobalData == null or GlobalData.weapons == null:
		return
	var modules: Dictionary = GlobalData.weapons.frame_modules
	var all_slots := ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]
	for slot in all_slots:
		var target_count: int = get_socket_count(slot)
		if not modules.has(slot) or not (modules[slot] is Array):
			var arr: Array = []
			for i in range(target_count):
				arr.append("")
			modules[slot] = arr
		else:
			var arr: Array = modules[slot]
			while arr.size() < target_count:
				arr.append("")
			if arr.size() > target_count:
				arr.resize(target_count)
	# Also ensure legacy "torso" points to "body" for older callers
	if modules.has("body"):
		modules["torso"] = modules["body"]


static func get_socket_count(slot: String) -> int:
	var norm := normalize_slot_name(slot)
	if GlobalData and GlobalData.weapons and ("equipped_frames" in GlobalData.weapons):
		var frame = GlobalData.weapons.equipped_frames.get(norm, {})
		if frame is Dictionary:
			if frame.has("module_slots"):
				var ms = frame["module_slots"]
				if ms is int or ms is float:
					return int(ms)
				elif ms is Dictionary:
					return int(ms.get(norm, DEFAULT_SOCKET_COUNTS.get(norm, 1)))
			if frame.has("sockets"):
				return int(frame["sockets"])
	return int(DEFAULT_SOCKET_COUNTS.get(norm, 1))


static func get_module(module_id: String) -> Dictionary:
	return MODULE_CATALOG.get(module_id, {})


static func get_installed_module_id(slot: String, socket_index: int) -> String:
	init_slots_if_needed()
	var norm := normalize_slot_name(slot)
	var arr: Array = GlobalData.weapons.frame_modules.get(norm, [])
	if socket_index >= 0 and socket_index < arr.size():
		return str(arr[socket_index])
	return ""


static func get_installed_module(slot: String, socket_index: int) -> Dictionary:
	var id := get_installed_module_id(slot, socket_index)
	return get_module(id)


static func is_slot_compatible(module_category: String, target_slot: String) -> bool:
	var cat := module_category.to_lower().strip_edges()
	var slot := normalize_slot_name(target_slot)
	if cat == "universal":
		return true
	if cat == "head" and slot == "head":
		return true
	if (cat == "torso" or cat == "body") and (slot == "body" or slot == "torso"):
		return true
	if cat == "arm" and (slot == "arm_left" or slot == "arm_right"):
		return true
	if cat == "leg" and (slot == "leg_left" or slot == "leg_right"):
		return true
	return false


# -----------------------------------------------------------------------------
# INSTALL / UNINSTALL
# -----------------------------------------------------------------------------

static func install_module(slot: String, socket_index: int, module_id: String) -> bool:
	init_slots_if_needed()
	if not MODULE_CATALOG.has(module_id):
		return false
	var mod_data: Dictionary = MODULE_CATALOG[module_id]
	var cat: String = str(mod_data.get("category", "universal"))
	if not is_slot_compatible(cat, slot):
		return false
	
	var norm := normalize_slot_name(slot)
	var arr: Array = GlobalData.weapons.frame_modules.get(norm, [])
	if socket_index < 0 or socket_index >= arr.size():
		return false
	
	# If old module installed, return it to cargo inventory
	var old_id: String = str(arr[socket_index])
	if old_id != "":
		GlobalData.weapons.module_inventory.append(old_id)
	
	# Remove new module from cargo inventory if present
	var inv: Array = GlobalData.weapons.module_inventory
	var idx = inv.find(module_id)
	if idx != -1:
		inv.remove_at(idx)
	
	arr[socket_index] = module_id
	return true


static func uninstall_module(slot: String, socket_index: int) -> String:
	init_slots_if_needed()
	var norm := normalize_slot_name(slot)
	var arr: Array = GlobalData.weapons.frame_modules.get(norm, [])
	if socket_index < 0 or socket_index >= arr.size():
		return ""
	var old_id: String = str(arr[socket_index])
	if old_id != "":
		arr[socket_index] = ""
		GlobalData.weapons.module_inventory.append(old_id)
	return old_id


static func get_all_installed_modules() -> Array[Dictionary]:
	init_slots_if_needed()
	var list: Array[Dictionary] = []
	for slot in GlobalData.weapons.frame_modules:
		var arr: Array = GlobalData.weapons.frame_modules[slot]
		for mod_id in arr:
			if mod_id != "" and MODULE_CATALOG.has(mod_id):
				list.append(MODULE_CATALOG[mod_id])
	return list


static func has_module(module_id: String) -> bool:
	init_slots_if_needed()
	for slot in GlobalData.weapons.frame_modules:
		var arr: Array = GlobalData.weapons.frame_modules[slot]
		if arr.has(module_id):
			return true
	return false


static func get_module_effect(module_id: String, effect_key: String, default_val = null):
	if not has_module(module_id):
		return default_val
	var mod := get_module(module_id)
	var effs: Dictionary = mod.get("effects", {})
	return effs.get(effect_key, default_val)


# -----------------------------------------------------------------------------
# COMBAT STAT & SYNERGY CALCULATORS
# -----------------------------------------------------------------------------

## V8 Twin-Turbo dash stacking multiplier
static func calculate_dash_stack_multiplier(stacks: int) -> float:
	if not has_module("v8_twin_turbo"):
		return 1.0
	var boost: float = float(get_module_effect("v8_twin_turbo", "dash_stack_boost", 0.20))
	var max_stacks: int = int(get_module_effect("v8_twin_turbo", "max_dash_stacks", 3))
	var clamped_stacks := clampi(stacks, 0, max_stacks)
	return 1.0 + float(clamped_stacks) * boost


## Heat-to-Kinetic Converter fire-rate multiplier
static func calculate_heat_fire_rate_multiplier(heat_ratio: float) -> float:
	if not has_module("heat_kinetic_converter"):
		return 1.0
	var scale: float = float(get_module_effect("heat_kinetic_converter", "heat_fire_rate_scale", 0.50))
	# Scales from 0.50 heat to 1.0 heat
	var active_ratio = clampf((heat_ratio - 0.4) / 0.6, 0.0, 1.0)
	return 1.0 + active_ratio * scale


## Heat-to-Kinetic Converter projectile speed multiplier
static func calculate_heat_proj_speed_multiplier(heat_ratio: float) -> float:
	if not has_module("heat_kinetic_converter"):
		return 1.0
	var scale: float = float(get_module_effect("heat_kinetic_converter", "heat_proj_speed_scale", 0.35))
	var active_ratio = clampf((heat_ratio - 0.4) / 0.6, 0.0, 1.0)
	return 1.0 + active_ratio * scale


## Cryo/Vent heat-management multipliers. Each installed heat module
## contributes its own multiplier; multiple modules stack multiplicatively
## so a full cryo + vent build is strong but never free.
static func calculate_heat_capacity_multiplier() -> float:
	if GlobalData == null or GlobalData.weapons == null:
		return 1.0
	var mult := 1.0
	for mod in get_all_installed_modules():
		var effs: Dictionary = mod.get("effects", {})
		if effs.has("heat_capacity_mult"):
			mult *= float(effs["heat_capacity_mult"])
	return mult


static func calculate_heat_cool_rate_multiplier() -> float:
	if GlobalData == null or GlobalData.weapons == null:
		return 1.0
	var mult := 1.0
	for mod in get_all_installed_modules():
		var effs: Dictionary = mod.get("effects", {})
		if effs.has("heat_cool_rate_mult"):
			mult *= float(effs["heat_cool_rate_mult"])
	return mult


static func calculate_heat_per_shot_multiplier() -> float:
	if GlobalData == null or GlobalData.weapons == null:
		return 1.0
	var mult := 1.0
	for mod in get_all_installed_modules():
		var effs: Dictionary = mod.get("effects", {})
		if effs.has("heat_per_shot_mult"):
			mult *= float(effs["heat_per_shot_mult"])
	return mult


## Counts total damaged / broken / patched outer armor slots for Berserk synergy
static func get_total_broken_or_bound_slots() -> int:
	if GlobalData == null or GlobalData.weapons == null:
		return 0
	var count: int = 0
	for slot in GlobalData.MECHA_SLOTS:
		var is_broken := float(GlobalData.weapons.part_damage.get(slot, 0.0)) >= 1.0
		var is_bound := bool(GlobalData.weapons.frame_bindings.get(slot, false))
		var is_patched := bool(GlobalData.weapons.scrap_patches.has(slot))
		if is_broken or is_bound or is_patched:
			count += 1
	return count


## Exposed Frame Berserk speed multiplier
static func calculate_berserk_speed_multiplier() -> float:
	if not has_module("exposed_frame_berserk"):
		return 1.0
	var count := get_total_broken_or_bound_slots()
	var per_slot: float = float(get_module_effect("exposed_frame_berserk", "broken_slot_speed", 0.15))
	return 1.0 + float(count) * per_slot


## Exposed Frame Berserk melee damage multiplier
static func calculate_berserk_melee_multiplier() -> float:
	if not has_module("exposed_frame_berserk"):
		return 1.0
	var count := get_total_broken_or_bound_slots()
	var per_slot: float = float(get_module_effect("exposed_frame_berserk", "broken_slot_melee", 0.25))
	return 1.0 + float(count) * per_slot
