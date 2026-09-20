class_name SpecialWeaponSystem
extends RefCounted

## =============================================================================
## SPECIAL WEAPON SYSTEM — Generic Advanced Technology Integration Contract (Phase 2E-5)
##
## Defines generic capability contracts, targeting models, area geometries,
## validation gates, effect payload structures, and observation hooks for special weapons
## without introducing weapon-specific ID branching or violating authority boundaries.
##
## CAPABILITIES SUPPORTED (Data-Driven):
## 1. Disruption: Electronic & movement inhibition (e.g. Jammer, EMP, dampener)
## 2. Strategic Strike: Large-scale beam, sweep, or orbital bombardment (e.g. Satellite Cannon)
## 3. Area Denial: Persistent zone hazard / interference
## 4. Custom: Extensible generic data contracts
##
## AUTHORITY BOUNDARIES:
## - TechnologySystem: Technology lifecycle & usability authorization authority.
## - FrameSystem: Physical hardware compatibility authority.
## - LoadoutSystem / ArmorSystem: Equipment state mutation authority.
## - WeaponCore / WeaponManager: Combat firing execution authority.
## - SpecialWeaponSystem: Special capability contract & validation resolution.
## - StuntWeaponSystem: Authoritative effect / status application & state mutation.
## - EventBus: Asynchronous signal broker.
## =============================================================================

# Preloaded Systems
const ActivationTimingSys = preload("res://scripts/systems/activation_timing_system.gd")

# Canonical Capability Types
const CAPABILITY_DISRUPTION := "disruption"
const CAPABILITY_STRATEGIC_STRIKE := "strategic_strike"
const CAPABILITY_AREA_DENIAL := "area_denial"
const CAPABILITY_CUSTOM := "custom"

# Canonical Targeting Modes
const TARGETING_POINT := "point"
const TARGETING_AREA_RADIUS := "area_radius"
const TARGETING_BEAM_LINE := "beam_line"
const TARGETING_SWEEP_CONE := "sweep_cone"
const TARGETING_MAP_SECTOR := "map_sector"

# Canonical Area Geometry Shapes
const SHAPE_SPHERE := "sphere"
const SHAPE_CYLINDER := "cylinder"
const SHAPE_BOX := "box"
const SHAPE_CONE := "cone"
const SHAPE_LINE := "line"


# =============================================================================
# CAPABILITY RESOLUTION & NORMALIZATION
# =============================================================================

## Resolves and normalizes special capability data from a weapon resource or dictionary.
static func resolve_special_capability(weapon_or_data: Variant) -> Dictionary:
	var raw_cap: Dictionary = {}
	var tech_id := ""

	if weapon_or_data is Dictionary:
		if weapon_or_data.has("special_capability") and weapon_or_data["special_capability"] is Dictionary:
			raw_cap = weapon_or_data["special_capability"]
		elif weapon_or_data.has("capability_type"):
			raw_cap = weapon_or_data
		tech_id = str(weapon_or_data.get("tech_id", weapon_or_data.get("technology_id", "")))
	elif weapon_or_data is Resource:
		if "special_capability" in weapon_or_data and weapon_or_data.special_capability is Dictionary:
			raw_cap = weapon_or_data.special_capability
		if "tech_id" in weapon_or_data:
			tech_id = str(weapon_or_data.tech_id)

	if raw_cap.is_empty():
		return {
			"has_capability": false,
			"capability_type": "",
			"targeting_mode": TARGETING_POINT,
			"area_shape": SHAPE_SPHERE,
			"area_parameters": {},
			"duration": 0.0,
			"charge_time": 0.0,
			"cooldown": 0.0,
			"energy_cost": 0.0,
			"effect_payload": {},
			"tech_id": tech_id
		}

	var cap_type := str(raw_cap.get("capability_type", CAPABILITY_CUSTOM)).to_lower()
	if cap_type == "temporary_disruption":
		cap_type = CAPABILITY_DISRUPTION
	var targeting_mode := str(raw_cap.get("targeting_mode", TARGETING_POINT)).to_lower()
	var area_shape := str(raw_cap.get("area_shape", SHAPE_SPHERE)).to_lower()
	var area_params: Dictionary = raw_cap.get("area_parameters", {}) if raw_cap.get("area_parameters") is Dictionary else {}
	var duration := float(raw_cap.get("duration", 0.0))
	var charge_time := maxf(float(raw_cap.get("charge_time", raw_cap.get("activation_delay", 0.0))), 0.0)
	var cooldown := float(raw_cap.get("cooldown", 0.0))
	var energy_cost := float(raw_cap.get("energy_cost", 0.0))
	var effect_payload: Dictionary = raw_cap.get("effect_payload", {}) if raw_cap.get("effect_payload") is Dictionary else {}
	if not effect_payload.has("damage"):
		if weapon_or_data is Resource and "damage" in weapon_or_data and float(weapon_or_data.damage) > 0.0:
			effect_payload["damage"] = float(weapon_or_data.damage)
		elif weapon_or_data is Dictionary and weapon_or_data.has("damage") and float(weapon_or_data["damage"]) > 0.0:
			effect_payload["damage"] = float(weapon_or_data["damage"])

	if not effect_payload.has("damage_type"):
		if weapon_or_data is Resource and weapon_or_data.has_method("get_damage_type") and str(weapon_or_data.get_damage_type()) != "":
			effect_payload["damage_type"] = weapon_or_data.get_damage_type()
		elif weapon_or_data is Resource and "damage_type" in weapon_or_data and str(weapon_or_data.damage_type) != "":
			effect_payload["damage_type"] = str(weapon_or_data.damage_type)
		elif weapon_or_data is Dictionary and weapon_or_data.has("damage_type"):
			effect_payload["damage_type"] = str(weapon_or_data["damage_type"])

	# Infer standard defaults based on capability type if omitted
	if not raw_cap.has("targeting_mode"):
		if cap_type == CAPABILITY_DISRUPTION:
			targeting_mode = TARGETING_AREA_RADIUS
		elif cap_type == CAPABILITY_STRATEGIC_STRIKE:
			targeting_mode = TARGETING_BEAM_LINE

	if not raw_cap.has("area_shape"):
		if targeting_mode == TARGETING_AREA_RADIUS:
			area_shape = SHAPE_SPHERE
		elif targeting_mode == TARGETING_BEAM_LINE:
			area_shape = SHAPE_LINE
		elif targeting_mode == TARGETING_SWEEP_CONE:
			area_shape = SHAPE_CONE

	return {
		"has_capability": true,
		"capability_type": cap_type,
		"targeting_mode": targeting_mode,
		"area_shape": area_shape,
		"area_parameters": area_params.duplicate(true),
		"duration": duration,
		"charge_time": charge_time,
		"cooldown": cooldown,
		"energy_cost": energy_cost,
		"effect_payload": effect_payload.duplicate(true),
		"tech_id": tech_id
	}


# =============================================================================
# AUTHORITATIVE ACTIVATION VALIDATION
# =============================================================================

## Authoritatively validates if a special weapon capability can be activated.
## Checks:
## 1. Capability contract validity
## 2. Technology authorization (via TechnologySystem)
## 3. Physical frame compatibility (via FrameSystem if frame context provided)
## 4. Resource / cooldown readiness (if context provided)
## Does NOT mutate any gameplay or equipment state.
static func validate_special_activation(weapon_or_data: Variant, user_context: Dictionary = {}) -> Dictionary:
	var cap := resolve_special_capability(weapon_or_data)
	if not bool(cap.get("has_capability", false)):
		return {
			"can_activate": false,
			"reason": "no_special_capability",
			"message": "Weapon does not possess a special capability contract.",
			"capability": cap,
			"tech_id": ""
		}

	var tech_id := str(cap.get("tech_id", ""))

	# 1. Technology Authorization Gate (Delegated to TechnologySystem authority)
	var tech_sys = load("res://scripts/systems/technology_system.gd")
	if tech_sys and tech_id != "":
		var is_usable: bool = tech_sys.is_technology_usable(tech_id)
		if not is_usable:
			return {
				"can_activate": false,
				"reason": "technology_locked",
				"message": "Special technology '%s' is not authorized for combat use." % tech_id,
				"capability": cap,
				"tech_id": tech_id
			}

	# 2. Physical Frame Compatibility Gate (Delegated to FrameSystem authority)
	var frame_sys = load("res://scripts/systems/frame_system.gd")
	if frame_sys and user_context.has("frame_data") and tech_id != "":
		var frame_data = user_context["frame_data"]
		if (frame_data is Dictionary and not frame_data.is_empty()) or (frame_data != null and not (frame_data is Dictionary)):
			var installed_bridges: Array = user_context.get("installed_bridges", [])
			var is_compat: bool = frame_sys.can_support_technology(frame_data, tech_id, installed_bridges)
			if not is_compat:
				return {
					"can_activate": false,
					"reason": "physically_incompatible",
					"message": "Frame cannot physically support technology '%s'." % tech_id,
					"capability": cap,
					"tech_id": tech_id
				}

	# 3. Energy / Resource Requirements
	var req_energy: float = float(cap.get("energy_cost", 0.0))
	if req_energy > 0.0 and user_context.has("current_energy"):
		var cur_energy: float = float(user_context["current_energy"])
		if cur_energy < req_energy:
			return {
				"can_activate": false,
				"reason": "insufficient_energy",
				"message": "Insufficient energy (%.1f required, %.1f available)." % [req_energy, cur_energy],
				"capability": cap,
				"tech_id": tech_id
			}

	# 4. Cooldown Validation
	if user_context.has("cooldown_remaining"):
		var cd: float = float(user_context["cooldown_remaining"])
		if cd > 0.0:
			return {
				"can_activate": false,
				"reason": "on_cooldown",
				"message": "Special capability on cooldown (%.1fs remaining)." % cd,
				"capability": cap,
				"tech_id": tech_id
			}

	return {
		"can_activate": true,
		"reason": "ok",
		"message": "Special capability is ready for activation.",
		"capability": cap,
		"tech_id": tech_id
	}


# =============================================================================
# TARGETING & AREA RESOLUTION
# =============================================================================

## Geometrically evaluates and returns all targets affected by a special capability volume.
## Uses pure vector geometry independent of weapon identity.
static func resolve_affected_targets(targeting_mode: String, origin: Vector3, direction: Vector3, area_params: Dictionary, potential_targets: Array) -> Array:
	var affected: Array = []
	var norm_dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD

	for target in potential_targets:
		var target_pos := _extract_target_position(target)
		if target_pos == Vector3.INF:
			continue

		var is_inside := false
		match targeting_mode:
			TARGETING_AREA_RADIUS:
				var radius := float(area_params.get("radius", area_params.get("range", 10.0)))
				is_inside = origin.distance_to(target_pos) <= radius

			TARGETING_BEAM_LINE:
				var length := float(area_params.get("length", area_params.get("range", 100.0)))
				var width := float(area_params.get("width", area_params.get("beam_radius", 4.0)))
				var half_width := width / 2.0 if width > 0.0 else 2.0
				var to_target := target_pos - origin
				var proj := to_target.dot(norm_dir)
				if proj >= 0.0 and proj <= length:
					var perp_dist := (to_target - norm_dir * proj).length()
					is_inside = perp_dist <= half_width

			TARGETING_SWEEP_CONE:
				var range_dist := float(area_params.get("range", area_params.get("length", 50.0)))
				var cone_angle := float(area_params.get("angle", area_params.get("spread", 45.0)))
				var half_angle := cone_angle / 2.0
				var dist := origin.distance_to(target_pos)
				if dist <= range_dist:
					if dist < 0.001:
						is_inside = true
					else:
						var to_target_dir := (target_pos - origin).normalized()
						var dot_val := clampf(norm_dir.dot(to_target_dir), -1.0, 1.0)
						var angle_deg := rad_to_deg(acos(dot_val))
						is_inside = angle_deg <= half_angle

			TARGETING_MAP_SECTOR:
				if area_params.has("min") and area_params.has("max"):
					var b_min: Vector3 = area_params["min"]
					var b_max: Vector3 = area_params["max"]
					is_inside = (target_pos.x >= b_min.x and target_pos.x <= b_max.x and
								 target_pos.y >= b_min.y and target_pos.y <= b_max.y and
								 target_pos.z >= b_min.z and target_pos.z <= b_max.z)
				else:
					var sec_radius := float(area_params.get("radius", 500.0))
					is_inside = origin.distance_to(target_pos) <= sec_radius

			TARGETING_POINT, _:
				var point_radius := float(area_params.get("radius", 2.0))
				var target_point := origin + norm_dir * float(area_params.get("range", 50.0))
				is_inside = target_pos.distance_to(target_point) <= point_radius

		if is_inside:
			affected.append(target)

	return affected


static func _extract_target_position(target: Variant) -> Vector3:
	if target is Node3D and is_instance_valid(target) and target.is_inside_tree():
		return target.global_position
	elif target is Dictionary:
		if target.has("global_position"):
			return target["global_position"]
		elif target.has("position"):
			return target["position"]
	elif target is Vector3:
		return target
	return Vector3.INF


## Validates whether a candidate target entity can receive electronic / disruption effects.
## Excludes source node, destroyed nodes, dead nodes, and static terrain/cover props.
static func is_valid_disruption_target(target: Variant, source_node: Node = null) -> bool:
	if target == null:
		return false
	if target == source_node:
		return false
	if target is Node:
		if not is_instance_valid(target) or target.is_queued_for_deletion():
			return false
		if target.has_method("_is_downed") and target._is_downed():
			return false
		if target.has_meta("is_destroyed") and bool(target.get_meta("is_destroyed")):
			return false
		var hs = target.get_node_or_null("HealthSystem")
		if hs and bool(hs.get("is_destroyed")):
			return false
		if target.is_in_group("terrain") or target.is_in_group("cover") or target.is_in_group("debris"):
			return false
		return true
	elif target is Dictionary:
		if bool(target.get("destroyed", false)) or bool(target.get("is_dead", false)):
			return false
		if str(target.get("type", "")) in ["terrain", "cover", "static_prop", "building"]:
			return false
		return true
	return false


## Validates whether a candidate target entity can receive damage / strategic strike effects.
## Excludes source node, destroyed nodes, dead nodes, and non-targetable entities.
static func is_valid_damage_target(target: Variant, source_node: Node = null) -> bool:
	if target == null:
		return false
	if target == source_node:
		return false
	if target is Node:
		if not is_instance_valid(target) or target.is_queued_for_deletion():
			return false
		if target.has_method("_is_downed") and target._is_downed():
			return false
		if target.has_meta("is_destroyed") and bool(target.get_meta("is_destroyed")):
			return false
		var hs = target.get_node_or_null("HealthSystem")
		if hs and bool(hs.get("is_destroyed")):
			return false
		return true
	elif target is Dictionary:
		if bool(target.get("destroyed", false)) or bool(target.get("is_dead", false)):
			return false
		return true
	return false


## Filters a candidate target array according to capability-specific rules.
static func filter_valid_targets(candidate_targets: Array, capability_type: String, source_node: Node = null) -> Array:
	var valid: Array = []
	for target in candidate_targets:
		match capability_type:
			CAPABILITY_DISRUPTION:
				if is_valid_disruption_target(target, source_node):
					valid.append(target)
			CAPABILITY_STRATEGIC_STRIKE:
				if is_valid_damage_target(target, source_node):
					valid.append(target)
			_:
				if target != source_node:
					valid.append(target)
	return valid



# =============================================================================
# EFFECT REQUEST BUILDER & DISPATCHER
# =============================================================================

## Builds a standardized, structured effect request payload for special capabilities.
## This function is a pure factory that does NOT perform state mutation.
static func create_effect_request(capability_type: String, capability_data: Dictionary, origin: Vector3, targets: Array = [], extra_context: Dictionary = {}) -> Dictionary:
	return {
		"capability_type": capability_type,
		"origin": origin,
		"targets": targets.duplicate(true),
		"target_positions": targets.duplicate(true), # Backward compatibility with positional array queries
		"duration": float(capability_data.get("duration", 0.0)),
		"intensity": float(capability_data.get("intensity", 1.0)),
		"area_parameters": capability_data.get("area_parameters", {}).duplicate(true) if capability_data.get("area_parameters") is Dictionary else {},
		"effect_payload": capability_data.get("effect_payload", {}).duplicate(true) if capability_data.get("effect_payload") is Dictionary else {},
		"timestamp": Time.get_ticks_msec(),
		"extra": extra_context.duplicate(true)
	}


## Legacy alias for create_effect_request. Constructs pure effect data without mutating target state.
static func build_effect_payload(capability_type: String, capability_data: Dictionary, origin: Vector3, target_positions: Array = [], extra_context: Dictionary = {}) -> Dictionary:
	return create_effect_request(capability_type, capability_data, origin, target_positions, extra_context)


## Dispatches an effect request to the authoritative effect/status system.
## SpecialWeaponSystem itself NEVER owns node status or gameplay state mutation.
static func dispatch_effect_request(effect_request: Dictionary, effect_authority: Variant = null) -> int:
	if effect_request.is_empty():
		return 0

	var auth = effect_authority
	if auth == null:
		auth = load("res://scripts/war/stunt_weapon_system.gd")

	if auth:
		if auth.has_method("apply_effect_request"):
			return auth.apply_effect_request(effect_request)
		elif auth.has_method("apply_disruption") and effect_request.has("targets"):
			var duration: float = float(effect_request.get("duration", 0.0))
			var eff_data: Dictionary = effect_request.get("effect_payload", {}) if effect_request.get("effect_payload") is Dictionary else {}
			var count := 0
			for t in effect_request.get("targets", []):
				if t is Node and auth.apply_disruption(t, duration, eff_data):
					count += 1
			return count

	return 0


## Applies a generic disruption effect by delegating to the authoritative StuntWeaponSystem.
## SpecialWeaponSystem does NOT directly mutate target metadata or create status timers.
static func apply_disruption_effect(target: Node, duration: float, disruption_data: Dictionary = {}) -> bool:
	var stunt_sys = load("res://scripts/war/stunt_weapon_system.gd")
	if stunt_sys and stunt_sys.has_method("apply_disruption"):
		return stunt_sys.apply_disruption(target, duration, disruption_data)
	return false


# =============================================================================
# TECHNOLOGY OBSERVATION INTEGRATION
# =============================================================================

## Dispatches a generic technology observation event through EventBus when a special capability is executed.
static func report_special_weapon_observed(tech_id: String, source_node: Node, capability_type: String, extra_data: Dictionary = {}) -> void:
	if tech_id == "":
		return

	var obs_payload: Dictionary = {
		"source": "special_weapon",
		"source_type": capability_type,
		"source_node": source_node.name if source_node else "unknown",
		"timestamp": Time.get_ticks_msec()
	}
	for k in extra_data:
		obs_payload[k] = extra_data[k]

	var tree: SceneTree = null
	if source_node and source_node.is_inside_tree():
		tree = source_node.get_tree()
	elif Engine.get_main_loop() is SceneTree:
		tree = Engine.get_main_loop() as SceneTree

	if tree and tree.root and tree.root.has_node("EventBus"):
		var bus = tree.root.get_node("EventBus")
		if bus and bus.has_signal("technology_observed"):
			bus.technology_observed.emit(tech_id, obs_payload)
	else:
		var tech_sys = load("res://scripts/systems/technology_system.gd")
		if tech_sys:
			tech_sys.record_technology_encountered(tech_id, obs_payload)


# =============================================================================
# AUTHORITATIVE ACTIVATION PIPELINE
# =============================================================================

## High-level authoritative activation pipeline for special weapon capabilities.
## Connects validation, capability resolution, target resolution, effect request construction,
## effect dispatch to StuntWeaponSystem, resource/cooldown consumption, and technology observation.
## Does NOT directly mutate target node movement or gameplay state.
static func activate_special_weapon(weapon_or_data: Variant, source_node: Node, user_context: Dictionary = {}, potential_targets: Array = []) -> Dictionary:
	# 1. Validation Gate (Technology Usability + Frame Compatibility + Resources + Cooldown)
	var val := validate_special_activation(weapon_or_data, user_context)
	if not bool(val.get("can_activate", false)):
		return {
			"success": false,
			"reason": str(val.get("reason", "validation_failed")),
			"validation": val,
			"capability": val.get("capability", {}),
			"targets_affected": 0,
			"affected_targets": []
		}

	# 2. Capability Resolution
	var cap := resolve_special_capability(weapon_or_data)
	if not bool(cap.get("has_capability", false)):
		return {
			"success": false,
			"reason": "no_special_capability",
			"validation": val,
			"capability": cap,
			"targets_affected": 0,
			"affected_targets": []
		}

	# 3. Spatial Origin & Direction
	var origin: Vector3 = Vector3.ZERO
	var direction: Vector3 = Vector3.FORWARD
	if user_context.has("origin") and user_context["origin"] is Vector3:
		origin = user_context["origin"]
	elif source_node is Node3D and is_instance_valid(source_node) and source_node.is_inside_tree():
		origin = source_node.global_position

	if user_context.has("direction") and user_context["direction"] is Vector3:
		direction = user_context["direction"]
	elif source_node is Node3D and is_instance_valid(source_node) and source_node.is_inside_tree():
		direction = -source_node.global_transform.basis.z

	# 4. Candidate Target Collection & Filtering
	var candidates: Array = []
	if not potential_targets.is_empty():
		candidates = potential_targets
	elif user_context.has("potential_targets") and user_context["potential_targets"] is Array:
		candidates = user_context["potential_targets"]
	else:
		if source_node and source_node.is_inside_tree():
			var tree := source_node.get_tree()
			if tree:
				var pool: Array = []
				for grp in ["enemies", "mecha", "target"]:
					for n in tree.get_nodes_in_group(grp):
						if not pool.has(n):
							pool.append(n)
				candidates = pool

	var cap_type: String = str(cap.get("capability_type", CAPABILITY_CUSTOM))
	var filtered_candidates := filter_valid_targets(candidates, cap_type, source_node)

	# 5. Geometric Target Resolution
	var targeting_mode: String = str(cap.get("targeting_mode", TARGETING_AREA_RADIUS))
	var area_params: Dictionary = cap.get("area_parameters", {})
	var affected := resolve_affected_targets(targeting_mode, origin, direction, area_params, filtered_candidates)

	# Helper closure to execute effect dispatch, resource consumption, and observation at completion
	var execute_effect = func(_session = null) -> Dictionary:
		# 6. Generic Effect Request Construction (Pure Data Payload)
		var effect_request := create_effect_request(cap_type, cap, origin, affected, {
			"source_node": source_node,
			"weapon": weapon_or_data
		})

		# 7. Authoritative Effect Dispatch to StuntWeaponSystem
		var affected_count := dispatch_effect_request(effect_request)

		# 8. Resource & Cooldown Consumption on User Context
		if user_context.has("core") and user_context["core"] != null:
			var core = user_context["core"]
			if "cooldown" in core:
				core.cooldown = float(cap.get("cooldown", 0.0))
			if "ammo" in core and not bool(core.get("unlimited_ammo")):
				if core.ammo > 0:
					core.ammo -= 1
					if core.has_signal("ammo_changed"):
						core.ammo_changed.emit(core.ammo, core.max_ammo)
		if user_context.has("energy_system") and user_context["energy_system"] != null:
			var es = user_context["energy_system"]
			var req_energy := float(cap.get("energy_cost", 0.0))
			if req_energy > 0.0 and "energy" in es:
				es.energy = maxf(es.energy - req_energy, 0.0)

		# 9. Generic Technology Observation Dispatch
		var tech_id := str(cap.get("tech_id", ""))
		if tech_id != "":
			report_special_weapon_observed(tech_id, source_node, cap_type, {"weapon_data": weapon_or_data})

		return {
			"effect_request": effect_request,
			"affected_count": affected_count
		}

	# 10. Activation Timing Evaluation
	var charge_time := float(cap.get("charge_time", 0.0))
	if charge_time <= 0.0:
		# Instantaneous execution (Zero-duration activation)
		var res: Dictionary = execute_effect.call(null)
		return {
			"success": true,
			"reason": "ok",
			"capability": cap,
			"effect_request": res.get("effect_request", {}),
			"targets_affected": int(res.get("affected_count", 0)),
			"affected_targets": affected,
			"is_charging": false,
			"timing_session": null
		}

	# Deferred execution via Generic ActivationTimingSystem
	var session_ctx := user_context.duplicate(true)
	session_ctx["origin"] = origin
	session_ctx["direction"] = direction
	session_ctx["affected_targets"] = affected
	session_ctx["targets"] = affected

	var final_res: Dictionary = {
		"effect_request": {},
		"affected_count": 0
	}

	var on_complete = func(s):
		var exec_res: Dictionary = execute_effect.call(s)
		final_res["effect_request"] = exec_res.get("effect_request", {})
		final_res["affected_count"] = exec_res.get("affected_count", 0)
		if user_context.has("on_complete") and user_context["on_complete"] is Callable:
			user_context["on_complete"].call(s, exec_res)

	var on_cancel = func(s, reason: String):
		if user_context.has("on_cancel") and user_context["on_cancel"] is Callable:
			user_context["on_cancel"].call(s, reason)

	var timing_session = ActivationTimingSys.create_session(cap, session_ctx, on_complete, on_cancel)
	timing_session.start()

	return {
		"success": true,
		"reason": "charging",
		"capability": cap,
		"effect_request": final_res.get("effect_request", {}),
		"targets_affected": int(final_res.get("affected_count", 0)),
		"affected_targets": affected,
		"is_charging": true,
		"timing_session": timing_session
	}


## Creates an activation timing session for a capability.
static func create_activation_session(weapon_or_data: Variant, user_context: Dictionary = {}, on_complete: Callable = Callable(), on_cancel: Callable = Callable()) -> RefCounted:
	var cap := resolve_special_capability(weapon_or_data)
	return ActivationTimingSys.create_session(cap, user_context, on_complete, on_cancel)


## Helper to query the charge / activation delay time for a weapon or capability.
static func get_charge_time(weapon_or_data: Variant) -> float:
	var cap := resolve_special_capability(weapon_or_data)
	return float(cap.get("charge_time", 0.0))


