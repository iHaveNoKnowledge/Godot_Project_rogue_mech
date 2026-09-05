extends Node
class_name MechaAIController

## =============================================================================
## MECHA AI CONTROLLER — Unified Mecha AI Brain
## =============================================================================
## Drives any MechaBase / CharacterBody3D across Tabletop Arena and War Mode.
## Provides:
##   1. Dynamic Target Acquisition (by faction / opposing teams)
##   2. Tactical Range Management (Advance, Circle Strafe, Tactical Withdraw)
##   3. Dynamic Mobility (High-speed roller skating, dodge dash burst)
##   4. Aim Point & Lead Calculation
##   5. Weapon Trigger Handshake (Primary & Secondary firing arcs & range checks)
## =============================================================================

@export var actor: CharacterBody3D = null
@export var faction_team: String = "friendly"
@export var archetype: int = 1 # 0=Rusher, 1=Ranged, 2=Heavy, 3=Support, 4=ShieldMelee, 5=ShieldRanged
@export var pilot_trait: String = "Balanced"

# Combat distance thresholds (meters)
@export var preferred_range: float = 25.0
@export var min_retreat_range: float = 12.0
@export var max_detection_range: float = 180.0

# Strategic Objective (e.g. enemy main base coordinate or waypoint)
@export var objective_target_pos: Vector3 = Vector3.ZERO
@export var has_objective: bool = false

# Targets
var current_target: Node3D = null
var _decision_timer: float = 0.0
var _strafe_sign: float = 1.0
var _strafe_switch_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0

# Current calculated drive commands
var cmd_move_direction: Vector3 = Vector3.ZERO
var cmd_aim_point: Vector3 = Vector3.ZERO
var cmd_fire_left: bool = false
var cmd_fire_right: bool = false
var cmd_wants_dash: bool = false
var cmd_wants_jump: bool = false
var cmd_wants_roller: bool = false


func _ready() -> void:
	if actor == null and get_parent() is CharacterBody3D:
		actor = get_parent() as CharacterBody3D
	_apply_archetype_defaults()


## Configures combat ranges and behaviors based on archetype
func _apply_archetype_defaults() -> void:
	match archetype:
		0: # Rusher
			preferred_range = 6.0
			min_retreat_range = 2.0
		1: # Ranged
			preferred_range = 28.0
			min_retreat_range = 14.0
		2: # Heavy
			preferred_range = 18.0
			min_retreat_range = 8.0
		3: # Support
			preferred_range = 35.0
			min_retreat_range = 16.0
		4: # Shield Melee
			preferred_range = 5.0
			min_retreat_range = 1.5
		5: # Shield Ranged
			preferred_range = 22.0
			min_retreat_range = 10.0
		_:
			preferred_range = 22.0
			min_retreat_range = 10.0


## Periodic target scanning and threat assessment
func acquire_target(scan_radius: float = 180.0) -> Node3D:
	current_target = null
	if not is_inside_tree() or actor == null:
		return null

	var hostile_groups: Array[String] = []
	if faction_team == "friendly":
		hostile_groups.append("enemy")
	elif faction_team == "enemy":
		hostile_groups.append("friendly")
		hostile_groups.append("player")
	else:
		hostile_groups.append("enemy")

	var best_candidate: Node3D = null
	var best_dist: float = scan_radius
	var my_pos: Vector3 = actor.global_position

	for grp in hostile_groups:
		var nodes := get_tree().get_nodes_in_group(grp)
		for node in nodes:
			if node == actor or not (node is Node3D):
				continue
			var n3d := node as Node3D
			# Skip downed / destroyed entities
			if n3d.has_method("_is_downed") and n3d.call("_is_downed"):
				continue
			if n3d.has_meta("is_parked") and bool(n3d.get_meta("is_parked")):
				continue
			var hs = n3d.get_node_or_null("HealthSystem")
			if hs and hs.get("is_destroyed") == true:
				continue

			var d: float = my_pos.distance_to(n3d.global_position)
			if d < best_dist:
				best_dist = d
				best_candidate = n3d

	current_target = best_candidate
	return current_target


## Evaluates tactical AI decisions and generates drive commands
func update_ai_decisions(delta: float) -> Dictionary:
	if actor == null or not is_instance_valid(actor):
		return _empty_commands()

	_decision_timer -= delta
	_dash_cooldown_timer -= delta
	_strafe_switch_timer -= delta

	if _strafe_switch_timer <= 0.0:
		_strafe_switch_timer = randf_range(2.0, 4.5)
		_strafe_sign = -1.0 if randf() < 0.5 else 1.0

	# Periodically re-scan target
	if _decision_timer <= 0.0:
		_decision_timer = randf_range(0.8, 1.4)
		if current_target == null or not is_instance_valid(current_target) or (current_target.has_method("_is_downed") and current_target.call("_is_downed")):
			acquire_target(max_detection_range)

	var move_dir := Vector3.ZERO
	var aim_pt := Vector3.ZERO
	var fire_l := false
	var fire_r := false
	var wants_dash := false
	var wants_roller := false

	var is_skating: bool = actor.get("is_roller_dashing") == true
	var actor_pos: Vector3 = actor.global_position
	var fwd := -actor.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD

	if current_target != null and is_instance_valid(current_target):
		var target_pos := current_target.global_position
		aim_pt = target_pos + Vector3(0, 1.4, 0)
		var dist: float = actor_pos.distance_to(target_pos)
		var to_target: Vector3 = (target_pos - actor_pos)
		to_target.y = 0.0
		var to_target_norm: Vector3 = to_target.normalized() if to_target.length_squared() > 0.001 else Vector3.FORWARD

		# Tactical distance management
		if dist > preferred_range + 4.0:
			# Advance toward target
			move_dir = to_target_norm
			if dist > preferred_range + 20.0:
				if not is_skating:
					wants_roller = true
				if _dash_cooldown_timer <= 0.0 and randf() < 0.2:
					wants_dash = true
					_dash_cooldown_timer = 3.5
		elif dist < min_retreat_range:
			# Too close: tactical back-pedal
			move_dir = -to_target_norm
			if is_skating:
				wants_roller = true # Cut roller for tight footwork
		else:
			# In engagement sweet spot: circle strafe
			var lateral := Vector3(-to_target_norm.z, 0, to_target_norm.x) * _strafe_sign
			move_dir = (lateral + to_target_norm * 0.15).normalized()
			if is_skating:
				wants_roller = true

		# Weapon firing triggers & arc check
		# Check facing angle (target should be roughly within front 65 degrees)
		var angle_to_tgt: float = rad_to_deg(fwd.angle_to(to_target_norm))

		if dist <= preferred_range * 1.6 and angle_to_tgt <= 65.0:
			fire_l = true
			if dist <= preferred_range * 1.1:
				fire_r = true
	else:
		# No target: pursue objective target if available
		if has_objective and objective_target_pos != Vector3.ZERO:
			var to_obj := (objective_target_pos - actor_pos)
			to_obj.y = 0.0
			if to_obj.length() > 8.0:
				move_dir = to_obj.normalized()
				aim_pt = actor_pos + move_dir * 25.0
				if not is_skating:
					wants_roller = true
			else:
				move_dir = Vector3.ZERO
				aim_pt = actor_pos + fwd * 10.0
				if is_skating:
					wants_roller = true
		else:
			move_dir = Vector3.ZERO
			aim_pt = actor_pos - actor.global_transform.basis.z * 15.0
			if is_skating:
				wants_roller = true

	cmd_move_direction = move_dir
	cmd_aim_point = aim_pt
	cmd_fire_left = fire_l
	cmd_fire_right = fire_r
	cmd_wants_dash = wants_dash
	cmd_wants_jump = false
	cmd_wants_roller = wants_roller

	return {
		"move_direction": cmd_move_direction,
		"aim_point": cmd_aim_point,
		"fire_left": cmd_fire_left,
		"fire_right": cmd_fire_right,
		"wants_dash": cmd_wants_dash,
		"wants_jump": cmd_wants_jump,
		"wants_roller": cmd_wants_roller
	}


## Applies calculated commands into actor's driving interface
func apply_drive_to_actor(delta: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var cmds := update_ai_decisions(delta)
	if actor.has_method("set_drive_commands"):
		actor.set_drive_commands(
			cmds["move_direction"],
			cmds["aim_point"],
			cmds["fire_left"],
			cmds["fire_right"],
			cmds["wants_dash"],
			cmds["wants_jump"],
			cmds["wants_roller"]
		)


func _empty_commands() -> Dictionary:
	return {
		"move_direction": Vector3.ZERO,
		"aim_point": Vector3.ZERO,
		"fire_left": false,
		"fire_right": false,
		"wants_dash": false,
		"wants_jump": false,
		"wants_roller": false
	}
