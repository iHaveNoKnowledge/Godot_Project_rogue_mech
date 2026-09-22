class_name ActivationTimingSystem
extends RefCounted

## =============================================================================
## ACTIVATION TIMING SYSTEM — Generic Capability Activation Timing Contract (Phase 2E-9)
##
## Defines generic activation timing, charging, and telegraph state tracking for
## special weapon capabilities and actions without weapon-ID branching.
##
## PHASES:
## - READY (IDLE): No active timing session or reset.
## - PREPARING (CHARGING / WINDUP): Timing window active (0.0 <= elapsed < duration).
## - COMPLETED: Timing window reached completion (elapsed >= duration).
## - CANCELLED: Timing window was aborted prior to completion.
##
## AUTHORITY BOUNDARIES:
## - Owns: Activation phase, elapsed time, remaining time, progress [0.0..1.0],
##   cancellation state, completion callback execution, generic telegraph descriptor.
## - MUST NOT OWN: HP, armor, damage calculations, movement inhibition,
##   status application, technology progression, cooldown timers, or energy pools.
## =============================================================================

enum Phase {
	READY = 0,
	PREPARING = 1,
	COMPLETED = 2,
	CANCELLED = 3,
}

static var _session_counter: int = 0

var session_id: String = ""
var phase: Phase = Phase.READY
var duration: float = 0.0
var elapsed: float = 0.0
var capability_data: Dictionary = {}
var context: Dictionary = {}
var completion_callback: Callable = Callable()
var cancellation_callback: Callable = Callable()
var cancellation_reason: String = ""
var started_at: int = 0


## Factory to create and configure a new generic activation timing session.
static func create_session(cap_data: Dictionary = {}, user_ctx: Dictionary = {}, on_complete: Callable = Callable(), on_cancel: Callable = Callable()) -> RefCounted:
	var session = (load("res://scripts/systems/activation_timing_system.gd") as GDScript).new()
	_session_counter += 1
	session.session_id = "timing_session_%d" % _session_counter
	session.capability_data = cap_data.duplicate(true)
	session.context = user_ctx.duplicate(true)
	session.completion_callback = on_complete
	session.cancellation_callback = on_cancel
	session.duration = maxf(float(cap_data.get("charge_time", cap_data.get("activation_delay", 0.0))), 0.0)
	return session


## Starts the timing session.
## If duration <= 0.0, completes immediately in a synchronous pass.
## Otherwise enters PREPARING phase.
func start() -> void:
	elapsed = 0.0
	cancellation_reason = ""
	started_at = Time.get_ticks_msec()
	if duration <= 0.0:
		phase = Phase.COMPLETED
		if completion_callback.is_valid():
			completion_callback.call(self)
	else:
		phase = Phase.PREPARING


## Advances the timing session by delta seconds.
## Transitions to COMPLETED when elapsed >= duration and triggers completion callback.
func tick(delta: float) -> void:
	if phase != Phase.PREPARING:
		return

	elapsed = minf(elapsed + maxf(delta, 0.0), duration)
	if elapsed >= duration or is_equal_approx(elapsed, duration):
		elapsed = duration
		phase = Phase.COMPLETED
		if completion_callback.is_valid():
			completion_callback.call(self)


## Aborts an in-progress activation session.
## Transitions to CANCELLED and prevents completion from executing.
func cancel(reason: String = "manual_cancel") -> bool:
	if phase == Phase.PREPARING:
		phase = Phase.CANCELLED
		cancellation_reason = reason
		if cancellation_callback.is_valid():
			cancellation_callback.call(self, reason)
		return true
	return false


## Resets the session back to READY.
func reset() -> void:
	phase = Phase.READY
	elapsed = 0.0
	cancellation_reason = ""
	started_at = 0


## Returns the normalized progress from 0.0 (started) to 1.0 (completed).
func get_progress() -> float:
	if duration <= 0.0:
		return 1.0
	return clampf(elapsed / duration, 0.0, 1.0)


## Returns remaining duration in seconds.
func get_remaining_time() -> float:
	return maxf(duration - elapsed, 0.0)


## Phase query helpers.
func is_ready() -> bool:
	return phase == Phase.READY


func is_preparing() -> bool:
	return phase == Phase.PREPARING


func is_completed() -> bool:
	return phase == Phase.COMPLETED


func is_cancelled() -> bool:
	return phase == Phase.CANCELLED


## Generates a pure, generic telegraph descriptor dictionary suitable for
## visual/HUD rendering (danger zones, charge reticle, warning indicator)
## without polluting combat logic.
func get_telegraph_descriptor() -> Dictionary:
	var area_params: Dictionary = {}
	if capability_data.has("area_parameters") and capability_data["area_parameters"] is Dictionary:
		area_params = capability_data["area_parameters"].duplicate(true)

	var origin: Vector3 = Vector3.ZERO
	if context.has("origin") and context["origin"] is Vector3:
		origin = context["origin"]

	var direction: Vector3 = Vector3.FORWARD
	if context.has("direction") and context["direction"] is Vector3:
		direction = context["direction"]

	var targeting_mode: String = str(capability_data.get("targeting_mode", "point"))
	var area_shape: String = str(capability_data.get("area_shape", "sphere"))
	var is_act: bool = (phase == Phase.PREPARING)

	# Deterministic strike endpoint / target position calculation
	var target_pos: Vector3 = origin
	if context.has("target_position") and context["target_position"] is Vector3:
		target_pos = context["target_position"]
	elif targeting_mode == "beam_line" or area_shape == "line":
		var beam_len: float = float(area_params.get("length", area_params.get("range", 100.0)))
		var norm_dir: Vector3 = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
		target_pos = origin + norm_dir * beam_len
	elif targeting_mode == "point":
		var range_dist: float = float(area_params.get("range", 50.0))
		var norm_dir: Vector3 = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
		target_pos = origin + norm_dir * range_dist
	elif targeting_mode == "area_radius" or area_shape in ["sphere", "circle", "cylinder"]:
		target_pos = origin
	elif context.has("targets") and context["targets"] is Array and not context["targets"].is_empty():
		var first_target = context["targets"][0]
		if first_target is Node3D and is_instance_valid(first_target) and first_target.is_inside_tree():
			target_pos = first_target.global_position
		elif first_target is Dictionary and first_target.has("global_position"):
			target_pos = first_target["global_position"]

	var effect_id: String = str(capability_data.get("capability_type", capability_data.get("tech_id", "special_weapon")))
	var geom_type: String = area_shape if area_shape != "" else targeting_mode

	return {
		# Status & Lifecycle
		"session_id": session_id if session_id != "" else ("timing_session_%d" % get_instance_id()),
		"active": is_act,
		"is_active": is_act,
		"phase": phase,
		"progress": get_progress(),
		"elapsed": elapsed,
		"duration": duration,
		"remaining": get_remaining_time(),
		"started_at": started_at,

		# Identity
		"effect_id": effect_id,
		"capability_type": str(capability_data.get("capability_type", "")),
		"tech_id": str(capability_data.get("tech_id", "")),

		# Spatial & Strike Geometry
		"source": origin,
		"source_position": origin,
		"origin": origin,
		"target": target_pos,
		"target_position": target_pos,
		"direction": direction,
		"geometry_type": geom_type,
		"targeting_mode": targeting_mode,
		"area_shape": area_shape,
		"area_parameters": area_params,
		"targets": context.get("affected_targets", context.get("targets", []))
	}
