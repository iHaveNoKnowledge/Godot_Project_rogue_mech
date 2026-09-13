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

# Tactical Postures: "aggressive" (normal), "gak" (conservative/starved), "retreat" (low HP / escape)
@export var posture: String = "aggressive"
@export var is_starved: bool = false

# AI Energy & Mobility Management
var ai_energy: float = 100.0
var ai_max_energy: float = 100.0
const AI_ROLLER_DRAIN_RATE := 15.0
const AI_REGEN_RATE := 16.0
const AI_LOW_ENERGY_CUTOFF := 18.0

var has_popped_retreat_smoke: bool = false
var last_known_target_pos: Vector3 = Vector3.ZERO
var _search_patrol_timer: float = 0.0
var _search_patrol_dir: Vector3 = Vector3.FORWARD

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
	_search_patrol_timer -= delta

	if _strafe_switch_timer <= 0.0:
		_strafe_switch_timer = randf_range(2.0, 4.5)
		_strafe_sign = -1.0 if randf() < 0.5 else 1.0

	# Periodically re-scan target
	if _decision_timer <= 0.0:
		_decision_timer = randf_range(0.8, 1.4)
		if current_target == null or not is_instance_valid(current_target) or (current_target.has_method("_is_downed") and current_target.call("_is_downed")):
			acquire_target(max_detection_range)

	# Update Posture dynamically based on HP & logistics supply
	var hs = actor.get_node_or_null("HealthSystem")
	if hs and hs.has_method("get_total_hp"):
		var cur_hp: float = float(hs.get("total_hp") if "total_hp" in hs else 100.0)
		var max_hp: float = float(hs.get("max_total_hp") if "max_total_hp" in hs else 100.0)
		if max_hp > 0.0 and (cur_hp / max_hp) < 0.30:
			posture = "retreat"
	elif is_starved:
		posture = "gak"

	var move_dir := Vector3.ZERO
	var aim_pt := Vector3.ZERO
	var fire_l := false
	var fire_r := false
	var wants_dash := false
	var wants_roller := false
	var wants_jump := false

	var is_skating: bool = actor.get("is_roller_dashing") == true
	var actor_pos: Vector3 = actor.global_position if actor.is_inside_tree() else actor.position
	var fwd := -actor.global_transform.basis.z if actor.is_inside_tree() else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD

	# Energy tracking: drain during roller-dash, recharge when walking/idle
	if is_skating:
		ai_energy = maxf(ai_energy - AI_ROLLER_DRAIN_RATE * delta, 0.0)
	else:
		ai_energy = minf(ai_energy + AI_REGEN_RATE * delta, ai_max_energy)
	var can_boost: bool = ai_energy >= AI_LOW_ENERGY_CUTOFF

	if current_target != null and is_instance_valid(current_target):
		last_known_target_pos = current_target.global_position
		var target_pos := current_target.global_position
		aim_pt = target_pos + Vector3(0, 1.4, 0)
		var dist: float = actor_pos.distance_to(target_pos)
		var to_target: Vector3 = (target_pos - actor_pos)
		to_target.y = 0.0
		var to_target_norm: Vector3 = to_target.normalized() if to_target.length_squared() > 0.001 else Vector3.FORWARD

		# Dynamic range modifier by posture
		var eff_preferred := preferred_range
		var eff_min_retreat := min_retreat_range
		if posture == "gak":
			eff_preferred += 12.0
			eff_min_retreat += 8.0

		if posture == "retreat":
			# Tactical Retreat: pop smoke and fall back to arena border
			if not has_popped_retreat_smoke:
				has_popped_retreat_smoke = true
				if is_inside_tree():
					var eff_fact = load("res://scripts/effects/effect_factory.gd")
					if eff_fact and eff_fact.has_method("spawn_smoke_plume"):
						eff_fact.spawn_smoke_plume(get_tree(), actor_pos, 7, 0.35, 1.2, 2.5)
			# Move in reverse away from target
			move_dir = -to_target_norm
			aim_pt = actor_pos + to_target_norm * 10.0
			if can_boost:
				wants_roller = true
			# Suppressive parting shots
			fire_l = randf() < 0.35
		elif dist > eff_preferred + 4.0:
			# Advance toward target
			move_dir = to_target_norm
			if dist > eff_preferred + 18.0 and can_boost:
				if not is_skating:
					wants_roller = true
				if _dash_cooldown_timer <= 0.0 and randf() < 0.2 and posture != "gak":
					wants_dash = true
					_dash_cooldown_timer = 3.5
		elif dist < eff_min_retreat:
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
		var angle_to_tgt: float = rad_to_deg(fwd.angle_to(to_target_norm))
		if posture != "retreat" and dist <= eff_preferred * 1.6 and angle_to_tgt <= 65.0:
			fire_l = true
			# Gak posture conserves secondary weapons unless opponent is pressed close
			if posture == "gak":
				fire_r = (dist <= 8.0)
			elif dist <= eff_preferred * 1.1:
				fire_r = true
	else:
		# Search / Hunt behavior when target is lost
		if last_known_target_pos != Vector3.ZERO and actor_pos.distance_to(last_known_target_pos) > 6.0:
			var to_last := (last_known_target_pos - actor_pos)
			to_last.y = 0.0
			move_dir = to_last.normalized()
			aim_pt = last_known_target_pos + Vector3(0, 1.4, 0)
			if is_skating:
				wants_roller = true # walk normally when hunting
		elif has_objective and objective_target_pos != Vector3.ZERO:
			var to_obj := (objective_target_pos - actor_pos)
			to_obj.y = 0.0
			if to_obj.length() > 8.0:
				move_dir = to_obj.normalized()
				aim_pt = actor_pos + move_dir * 25.0
				if not is_skating and can_boost:
					wants_roller = true
			else:
				move_dir = Vector3.ZERO
				aim_pt = actor_pos + fwd * 10.0
		else:
			# Gentle perimeter scanning patrol
			if _search_patrol_timer <= 0.0:
				_search_patrol_timer = randf_range(3.0, 6.0)
				var angle := randf_range(-PI, PI)
				_search_patrol_dir = Vector3(cos(angle), 0, sin(angle))
			move_dir = _search_patrol_dir * 0.4
			aim_pt = actor_pos + _search_patrol_dir * 12.0
			if is_skating:
				wants_roller = true

	# Obstacle avoidance and jump clearance
	if actor.is_on_wall() and move_dir.length_squared() > 0.05:
		wants_jump = true
		# Sidestep away from wall normal
		var wall_norm := actor.get_wall_normal()
		var side_slide := Vector3(-wall_norm.z, 0, wall_norm.x) * _strafe_sign
		move_dir = (move_dir * 0.4 + side_slide * 0.6).normalized()

	cmd_move_direction = move_dir
	cmd_aim_point = aim_pt
	cmd_fire_left = fire_l
	cmd_fire_right = fire_r
	cmd_wants_dash = wants_dash
	cmd_wants_jump = wants_jump
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
