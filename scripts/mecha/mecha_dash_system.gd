extends Node

## ---------------------------------------------------------------------------
## MECHA DASH SYSTEM — short-pulse dash, Flash Burn (spam penalty), and
## Precision Dash (near-miss energy refund).  Extracted from mecha_controller.gd.
##
## The dash is gated purely by energy — no cooldown.  Spamming burns the tank
## fast (Flash Burn: momentum penalty + energy cost multiplier).  A well-timed
## dash that narrowly avoids an enemy projectile triggers Precision Dodge and
## refunds energy.
## ---------------------------------------------------------------------------

var dash_speed: float = 25.0
var dash_duration: float = 0.2
var dash_timer: float = 0.0
var is_dashing: bool = false
var dash_direction: Vector3 = Vector3.ZERO
var current_dash_speed: float = 25.0

# Flash Burn (spam dash dynamics).
var _dash_spam_window: float = 0.0
var _dash_spam_count: int = 0
const SPAM_DASH_WINDOW := 0.75
const SPAM_DASH_ENERGY_PENALTY_MULT := 0.5
const SPAM_DASH_MOMENTUM_PENALTY := 0.25
const DASH_ENERGY_COST := 6.0

# Precision Dash (GDD §3.2).
var _dash_start_pos: Vector3 = Vector3.ZERO
var _precision_window: float = 0.0
var _precision_armed: bool = false
var _precision_dodged: bool = false
var _precision_cooldown: float = 0.0
const PRECISION_WINDOW := 0.4
const PRECISION_NEAR_MISS_DIST := 2.5
const PRECISION_ENERGY_REFUND := 4.0
const PRECISION_COOLDOWN := 0.5

## Set by the parent controller before calling start_dash().
var input_dir: Vector2 = Vector2.ZERO


func tick(delta: float) -> void:
	## Call every physics frame to tick spam window and precision cooldown.
	if _dash_spam_window > 0.0:
		_dash_spam_window = maxf(_dash_spam_window - delta, 0.0)
		if _dash_spam_window <= 0.0:
			_dash_spam_count = 0

	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0.0:
			is_dashing = false

	if _precision_armed and not _precision_dodged:
		_precision_window -= delta
		if _precision_window <= 0.0:
			_precision_armed = false
		else:
			_check_precision_dash_near_miss()
	if _precision_cooldown > 0.0:
		_precision_cooldown -= delta


func can_dash(energy: float) -> bool:
	return energy >= DASH_ENERGY_COST


## Starts a dash. Returns the energy cost (caller subtracts from its pool).
## Mutates dash_direction and current_dash_speed.
func start_dash(energy: float, global_pos: Vector3, global_rot: Basis) -> float:
	var cam: Camera3D = null
	if is_inside_tree() and get_viewport():
		cam = get_viewport().get_camera_3d()
	if cam == null:
		var loop = Engine.get_main_loop() as SceneTree
		if loop and loop.root:
			cam = loop.root.get_camera_3d()

	if cam != null:
		var cam_basis = cam.global_transform.basis
		var forward = -cam_basis.z
		var right = cam_basis.x
		forward.y = 0.0
		forward = forward.normalized()
		right.y = 0.0
		right = right.normalized()
		dash_direction = (forward * -input_dir.y + right * input_dir.x).normalized()
	else:
		dash_direction = Vector3.ZERO

	if dash_direction.length() < 0.1:
		dash_direction = -Transform3D(Basis(Vector3.UP, global_rot.get_euler().y), Vector3.ZERO).basis.z

	var has_precog := GlobalData.narrative.has_pilot_perk("precognitive_flow")
	var is_flash_burn := false
	if not has_precog and _dash_spam_window > 0.0:
		_dash_spam_count += 1
		is_flash_burn = true
	else:
		_dash_spam_count = 1

	_dash_spam_window = SPAM_DASH_WINDOW

	var base_cost := DASH_ENERGY_COST * (0.5 if has_precog else 1.0)
	var actual_cost: float = base_cost * (1.0 + float(_dash_spam_count - 1) * SPAM_DASH_ENERGY_PENALTY_MULT)
	current_dash_speed = dash_speed * (1.0 - (SPAM_DASH_MOMENTUM_PENALTY if is_flash_burn else 0.0))

	is_dashing = true
	dash_timer = dash_duration

	_dash_start_pos = global_pos
	_precision_window = PRECISION_WINDOW * (1.5 if has_precog else 1.0)
	_precision_armed = true
	_precision_dodged = false

	# VFX
	for i in range(3):
		var trail_pos := global_pos + Vector3(0, 1.5, 0) - dash_direction * (0.5 + i * 0.4)
		var color: Color
		var emission: Color
		if is_flash_burn:
			color = Color(1.0, 0.35, 0.15, 0.7 - i * 0.15)
			emission = Color(1.0, 0.25, 0.05)
		else:
			color = Color(0.5, 0.7, 1.0, 0.6 - i * 0.15)
			emission = Color(0.3, 0.5, 1.0)
		EffectFactory.spawn_trail(Engine.get_main_loop(), trail_pos, global_rot,
			Vector3(0.8, 2.0, 1.5 - i * 0.3), color, emission, 0.2,
			4.0 - i if is_flash_burn else 3.0 - i)

	if AudioManager:
		AudioManager.play_dash(global_pos)

	return actual_cost


func apply_velocity(velocity_ref: Vector3) -> Vector3:
	## Overwrites horizontal velocity with dash vector while dashing.
	if is_dashing:
		velocity_ref.x = dash_direction.x * current_dash_speed
		velocity_ref.z = dash_direction.z * current_dash_speed
	return velocity_ref


func _check_precision_dash_near_miss() -> void:
	if _precision_cooldown > 0.0:
		return
	var projectiles = get_tree().get_nodes_in_group("projectile")
	for proj in projectiles:
		if not is_instance_valid(proj):
			continue
		if not bool(proj.get("fired_by_enemy")):
			continue
		if not proj is Node3D:
			continue
		var dist: float = (proj as Node3D).global_position.distance_to(_dash_start_pos)
		if dist < PRECISION_NEAR_MISS_DIST:
			_precision_dodged = true
			_precision_armed = false
			_precision_cooldown = PRECISION_COOLDOWN
			_trigger_precision_dodge((proj as Node3D).global_position)
			return


func _trigger_precision_dodge(hit_pos: Vector3) -> void:
	# Refund energy — the dash cost 6.0, refund 4.0 = net cost only 2.0.
	var parent = get_parent()
	if parent and "energy" in parent:
		parent.energy = minf(parent.energy + PRECISION_ENERGY_REFUND, parent.max_energy)
	EffectFactory.spawn_flash(get_tree(), hit_pos, Color(0.3, 1.0, 0.5),
		0.5, 0.15, 5.0, true, 2.0)
	if AudioManager:
		var pos := (parent as Node3D).global_position if parent is Node3D else Vector3.ZERO
		AudioManager.play_mecha_actuator(pos)
