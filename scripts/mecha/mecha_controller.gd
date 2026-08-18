extends CharacterBody3D

@export var chassis: ChassisData

var total_weight: float = 0.0
var current_speed: float = 0.0
var turn_rate: float = 0.0
var strafe_mode: bool = false
var input_dir: Vector2 = Vector2.ZERO

const GRAVITY := 20.0

# --- Bounded variable-height jump ---
# A tap is a low hop; HOLDING space charges the launch up to the frame's full
# jump power over JUMP_CHARGE_TIME. The launch is a single impulse — once the
# charge is spent the mech arcs under gravity, so holding forever never floats.
# Full power = chassis base + leg-frame power (a special gundam-class frame can
# declare its own `jump_power` to leap beyond the standard curve; normal frames
# fall back to their carry_bonus strength) + current momentum, minus a weight
# penalty: heavy mechs don't launch as high. Launching also costs energy scaled
# by carried mass.
const JUMP_CHARGE_TIME := 0.32        # seconds of holding for full power
const JUMP_RAMP_RATE := 50.0          # how fast the ascent builds while held
const JUMP_MIN_VELOCITY := 6.0        # tap velocity (low hop)
const JUMP_MAX_BASE := 6.0            # full-power velocity before leg/speed scaling
const LEG_POWER_JUMP_BONUS := 0.5     # per leg-power point added to full velocity
const SPEED_JUMP_BONUS := 0.12        # current horizontal speed feeds the launch
const WEIGHT_JUMP_PENALTY := 4.0      # a fully-loaded mech loses up to 4 m/s of launch
const JUMP_BASE_ENERGY_COST := 6.0
const JUMP_WEIGHT_ENERGY := 0.06      # extra energy per kg of carried mass

var is_jumping: bool = false
var jump_charge: float = 0.0

var dash_speed: float = 25.0
var dash_duration: float = 0.2
# Dash recharges fast (half the old cooldown) and works mid-air too: the mech
# shifts its arms/legs and body mass to steer its center of gravity, so it can
# redirect momentum even with no ground underfoot.
var dash_cooldown: float = 0.5
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var is_dashing: bool = false
var dash_direction: Vector3 = Vector3.ZERO

# --- Energy system ----------------------------------------------------------
# The mech runs on a finite energy pool. Normal walking is nearly free, but
# every dash costs a chunk of energy and sustained roller dashing drains the
# pool at an ever-increasing rate — so spamming dashes or holding the roller
# burns through it fast. Releasing the throttle lets the pool recharge.
var max_energy: float = 100.0
var energy: float = 100.0
const DASH_ENERGY_COST := 12.0        # energy per dash burst
const ENERGY_REGEN_RATE := 10.0       # per second while not boosting
const ROLLER_BASE_DRAIN := 4.0        # per second the roller is held
const ROLLER_RAMP_DRAIN := 7.0        # extra per second per second of continuous roller use
const ROLLER_MAX_DRAIN := 40.0        # ceiling so a full tank lasts ~2.5s at max burn
var roller_drain_ramp: float = 0.0    # grows while the roller is held, resets on release
# Recoil kick applied by heavy weapons (see apply_recoil_impulse). Decays over
# a short window so the mech staggers backwards instead of teleporting.
var recoil_vector: Vector3 = Vector3.ZERO
# Stance-recovery timer after a heavy shot: while > 0 the mech's recoil decay
# is slowed (the railgun's kick takes a beat to re-balance) instead of snapping
# back instantly. Leg power + total weight tune the decay below.
var _recoil_recovery: float = 0.0
var _recalculating: bool = false
var was_in_air: bool = false
var footstep_timer: float = 0.0
var roller_skate_timer: float = 0.0

# Override values used when no ChassisData resource is assigned in the scene.
# Populated by _apply_chassis_from_global_data() from GlobalData.chassis_id.
var _chassis_speed_override: float = 14.0
var _chassis_weight_capacity_override: float = 75.0
var can_traverse_water: bool = false


func _ready() -> void:
	add_to_group("mecha")
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(60)
	_apply_chassis_from_global_data()
	_recalculate_weight()
	_initialize_mesh_from_global_data()
	var attachment_manager = get_node_or_null("AttachmentManager")
	if attachment_manager:
		attachment_manager.rebuild_from_global_data()
	EventBus.weight_changed.connect(_on_weight_changed)


func _exit_tree() -> void:
	# The roller loop lives on the AudioManager autoload (which outlives this
	# mech): cut it when the mech is freed by a scene change, or the hum would
	# keep looping after the battle/board is gone.
	if AudioManager:
		AudioManager.stop_roller_dash()


# Apply chassis speed/weight from GlobalData.chassis_id.
# Always writes to override vars — never mutates the shared @export ChassisData Resource.
# _recalculate_weight() reads the override vars first, falling back to ChassisData only
# for base_turn_rate (which is not stored in chassis_catalog).
func _apply_chassis_from_global_data() -> void:
	var info = GlobalData.get_chassis_stats()
	_chassis_speed_override = info.get("speed", 7.0)
	_chassis_weight_capacity_override = info.get("max_weight", 75.0)
	can_traverse_water = info.get("water_traversal", false)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("eject"):
		var eject = get_node_or_null("MechaEject")
		if eject:
			eject.initiate_eject()


# --- Damage routing ---------------------------------------------------------
# Enemies/projectiles hit the mecha root (group "mecha"). The actual health
# lives on the child HealthSystem, so forward every damage entry point here so
# incoming fire actually reduces the pilot's HP instead of passing through.
func _health_system() -> Node:
	return get_node_or_null("HealthSystem")


func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	var hs := _health_system()
	if hs and hs.has_method("take_damage"):
		hs.take_damage(amount, damage_type)


func take_damage_at_point(amount: float, world_pos: Vector3, damage_type: String = "kinetic") -> void:
	var hs := _health_system()
	if hs and hs.has_method("take_damage_at_point"):
		hs.take_damage_at_point(amount, world_pos, damage_type)


func take_damage_to_part(slot_name: String, amount: float, damage_type: String = "kinetic", layer: String = "") -> void:
	var hs := _health_system()
	if hs and hs.has_method("take_damage_to_part"):
		hs.take_damage_to_part(slot_name, amount, damage_type, layer)


func take_damage_to_part_at(slot_name: String, amount: float, world_pos: Vector3, damage_type: String = "kinetic") -> void:
	var hs := _health_system()
	if hs and hs.has_method("take_damage_to_part_at"):
		hs.take_damage_to_part_at(slot_name, amount, world_pos, damage_type)


# Called by WeaponManager when a weapon with recoil fires: shoves the mech along
# a horizontal world direction (unit vector already * recoil force).
func apply_recoil_impulse(backward: Vector3) -> void:
	backward.y = 0.0
	if backward.length() < 0.001:
		return
	recoil_vector += backward.normalized() * minf(backward.length(), 12.0)


# Heavy kick (railgun): a big push that also extends the stance-recovery time.
# The push is capped higher than normal recoil and decays slower, so the mech
# visibly staggers backwards and takes a beat to re-balance — exactly how a
# railgun should feel.
func apply_heavy_recoil_impulse(backward: Vector3) -> void:
	backward.y = 0.0
	if backward.length() < 0.001:
		return
	recoil_vector += backward.normalized() * minf(backward.length(), 20.0)
	# Extend the recovery window so the stance takes a moment to settle.
	_recoil_recovery = clampf(_recoil_recovery + 0.55, 0.0, 2.5)


func _physics_process(delta: float) -> void:
	dash_cooldown_timer -= delta
	# Roller wheels need ground under them: leaving the floor (a jump) cuts the
	# roller out immediately, so it can never boost air speed.
	if is_roller_dashing and not is_on_floor():
		is_roller_dashing = false
		roller_drain_ramp = 0.0
	_process_energy(delta)
	_process_jump(delta)

	if is_dashing:
		dash_timer -= delta
		velocity.x = dash_direction.x * dash_speed
		velocity.z = dash_direction.z * dash_speed
		if dash_timer <= 0.0:
			is_dashing = false
	else:
		_handle_movement_input()
		_apply_movement(delta)

	var currently_on_floor = is_on_floor()
	if currently_on_floor and was_in_air:
		_trigger_landing_impact()
	was_in_air = not currently_on_floor

	move_and_slide()

	# Roller-dash audio: a continuous loop whose pitch BENDS with actual speed —
	# faster rolls whine higher, standing still stays quiet (the loop only whines
	# while the wheels are really rolling on the ground).
	var h_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	if is_roller_dashing and is_on_floor() and h_speed > 0.5:
		var ratio := h_speed / maxf(current_speed * 2.0, 1.0)
		if AudioManager:
			AudioManager.update_roller_dash(global_position, ratio)
	elif AudioManager:
		AudioManager.stop_roller_dash()


var is_roller_dashing: bool = false
var roller_spark_timer: float = 0.0


func _handle_movement_input() -> void:
	input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	strafe_mode = Input.is_action_pressed("strafe")

	if Input.is_action_just_pressed("roller_dash"):
		if not is_on_floor():
			# Roller dash is a GROUND-wheel mode — pressing it mid-air does
			# nothing (it can't add or cut air speed).
			is_roller_dashing = false
			roller_drain_ramp = 0.0
		elif energy > 1.0:
			# Re-engaging the roller restarts the burn ramp from zero.
			if not is_roller_dashing:
				roller_drain_ramp = 0.0
			is_roller_dashing = not is_roller_dashing
			# Engaging/disengaging the roller legs is the mech's joints moving —
			# a hydraulic actuator sound, never a UI click.
			if AudioManager:
				AudioManager.play_mecha_actuator(global_position)
		else:
			# Empty tank: the roller refuses to engage until it recharges.
			is_roller_dashing = false
			roller_drain_ramp = 0.0

	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0.0:
		if energy >= DASH_ENERGY_COST:
			_start_dash()

	# Jump only starts on the ground; the launch itself is handled by
	# _start_jump/_process_jump (variable height + momentum + energy cost).
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		_start_jump()


# --- Jump helpers -----------------------------------------------------------

# Kicks off a jump. The launch costs energy scaled by carried mass, and the
# initial hop is small — holding the button (see _process_jump) drives the mech
# up to its full jump power set by leg frames + current momentum.
func _start_jump() -> void:
	var cost := JUMP_BASE_ENERGY_COST + total_weight * JUMP_WEIGHT_ENERGY
	if energy < cost:
		return
	energy = maxf(energy - cost, 0.0)
	jump_charge = 0.0
	is_jumping = true
	velocity.y = _jump_velocity(0.0)
	if AudioManager:
		AudioManager.play_jump(global_position)


# While the button is held the ascent builds toward the full jump velocity;
# releasing early simply LOCKS IN whatever launch power was built up so far — a
# tap stays a low hop and holding longer buys a higher arc, monotonically up to
# the frame's max. The launch is a single impulse: once the charge window is
# spent (or the button is released) thrust stops and gravity arcs the mech back
# down — holding the button forever never lets the mech float or climb without
# limit. The state also clears the moment the mech touches back down.
func _process_jump(delta: float) -> void:
	if is_jumping:
		if Input.is_action_pressed("jump") and jump_charge < JUMP_CHARGE_TIME:
			jump_charge = minf(jump_charge + delta, JUMP_CHARGE_TIME)
			var target := _jump_velocity(jump_charge / JUMP_CHARGE_TIME)
			if velocity.y < target:
				velocity.y = move_toward(velocity.y, target, JUMP_RAMP_RATE * delta)
		else:
			# Charge complete or released: the launch is set, no more thrust.
			is_jumping = false
	if is_on_floor():
		is_jumping = false
		jump_charge = 0.0


# Full jump power = base + leg-frame power + current horizontal momentum, minus
# a weight penalty (heavy mechs launch lower). The charge fraction lerps between
# a low tap hop and that full power, so holding space longer (up to
# JUMP_CHARGE_TIME) buys a higher jump — but never higher than the frame's max.
func _jump_velocity(charge_frac: float) -> float:
	var leg_power := _leg_jump_power()
	var speed_bonus := Vector3(velocity.x, 0.0, velocity.z).length() * SPEED_JUMP_BONUS
	var weight_ratio := clampf(total_weight / maxf(_chassis_weight_capacity_override, 1.0), 0.0, 1.0)
	var full := JUMP_MAX_BASE + leg_power * LEG_POWER_JUMP_BONUS \
			- weight_ratio * WEIGHT_JUMP_PENALTY + speed_bonus
	return lerp(JUMP_MIN_VELOCITY, full, charge_frac)


# Leg thrust for jumping: chassis base + both leg frames. A special gundam-class
# leg frame can declare its own `jump_power` stat to leap beyond the standard
# curve; normal frames fall back to their carry_bonus strength.
func _leg_jump_power() -> float:
	var power := float(GlobalData.get_chassis_stats().get("power", 12.0))
	for leg in ["leg_left", "leg_right"]:
		var f = GlobalData.equipped_frames.get(leg, {})
		if f is Dictionary:
			power += float(f.get("jump_power", f.get("carry_bonus", 0.0)))
	return power


# Regenerates or burns the energy pool every frame. The roller's drain ramps up
# the longer it is held, so marathon roller dashing exhausts the tank quickly
# while short bursts stay cheap; releasing it restarts regen immediately.
func _process_energy(delta: float) -> void:
	# The roller only burns fuel while the mech is actually ROLLING (moving on
	# the ground) — engaging it and standing still costs nothing, and the burn
	# ramp only grows while rolling.
	if is_roller_dashing and is_on_floor() and input_dir.length() > 0.0:
		roller_drain_ramp = minf(roller_drain_ramp + ROLLER_RAMP_DRAIN * delta, ROLLER_MAX_DRAIN)
		energy = maxf(energy - (ROLLER_BASE_DRAIN + roller_drain_ramp) * delta, 0.0)
		if energy <= 0.0:
			# Out of juice: the roller cuts out mid-run.
			is_roller_dashing = false
			roller_drain_ramp = 0.0
			if AudioManager:
				AudioManager.play_mecha_actuator(global_position)
	else:
		roller_drain_ramp = 0.0
		energy = minf(energy + ENERGY_REGEN_RATE * delta, max_energy)


func _apply_movement(delta: float) -> void:
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var cam_basis = cam.global_transform.basis
	var forward = -cam_basis.z
	var right = cam_basis.x
	forward.y = 0.0
	forward = forward.normalized()
	right.y = 0.0
	right = right.normalized()

	var move_speed = current_speed
	if is_roller_dashing:
		move_speed *= 2.0
	if _is_in_water() and not can_traverse_water:
		move_speed *= 0.45

	var desired_velocity := Vector3.ZERO
	desired_velocity = (forward * -input_dir.y + right * input_dir.x) * move_speed

	if not strafe_mode and desired_velocity.length() > 0.1:
		var target_angle = atan2(-desired_velocity.x, -desired_velocity.z)
		var effective_turn = turn_rate * (1.5 if is_roller_dashing else 1.0)
		var lerp_weight = clampf(effective_turn * delta, 0.0, 1.0)
		rotation.y = lerp_angle(rotation.y, target_angle, lerp_weight)

	velocity.x = desired_velocity.x
	velocity.z = desired_velocity.z

	if is_on_floor() and desired_velocity.length() > 0.5:
		if is_roller_dashing:
			roller_spark_timer -= delta
			if roller_spark_timer <= 0.0:
				roller_spark_timer = 0.08
				_spawn_roller_spark_effect()
		else:
			footstep_timer -= delta
			if footstep_timer <= 0.0:
				footstep_timer = 0.35
				if AudioManager:
					AudioManager.play_footstep(global_position)

	if not is_on_floor():
		was_in_air = true
	elif was_in_air and is_on_floor():
		was_in_air = false
		_trigger_landing_impact()

	# Blend in any weapon recoil push then decay it. The railgun's heavy kick
	# decays slower while the stance recovers; strong legs and a light mech
	# re-balance faster, heavy mechs take longer.
	if recoil_vector.length() > 0.001:
		velocity.x += recoil_vector.x
		velocity.z += recoil_vector.z
		var decay_rate := _recoil_decay_rate()
		if _recoil_recovery > 0.0:
			_recoil_recovery -= delta
			decay_rate *= 0.35
		recoil_vector = recoil_vector.move_toward(Vector3.ZERO, decay_rate * delta)

	velocity.y -= GRAVITY * delta


# How fast weapon recoil decays each second. Strong legs brace harder (faster
# recovery) while heavier mechs take longer to re-stabilize — so a light mech
# with heavy leg frames snaps back from the railgun kick quickly, and a heavy
# mech staggers longer.
func _recoil_decay_rate() -> float:
	var leg_power := GlobalData.get_leg_power()
	# Base 30 (the old constant) tuned by bracing strength vs carried mass.
	var rate := 30.0 + leg_power * 1.2 - clampf(total_weight * 0.12, 0.0, 18.0)
	return maxf(rate, 14.0)


func _trigger_landing_impact() -> void:
	if AudioManager:
		AudioManager.play_land(global_position)

	# 1. Screen Shake
	var rigs = get_tree().get_nodes_in_group("camera_rig")
	if not rigs.is_empty() and rigs[0].has_method("add_shake"):
		rigs[0].add_shake(0.50)

	# 2. Animation impact recoil / compression
	var anim = get_node_or_null("AnimationSystem")
	if anim and anim.has_method("play_landing_impact"):
		anim.play_landing_impact()

	# 3. Ground Shockwave Ring & Dust VFX
	_spawn_landing_impact_effect()


func _is_in_water() -> bool:
	# Only true while inside an actual water volume placed by the arena (Area3D
	# tagged "water_volume", collision layer 4). Bridges are separate geometry,
	# so crossing a bridge never counts as being in water.
	var space = get_world_3d().direct_space_state
	for sample in [global_position, global_position + Vector3(0, 1.0, 0), global_position + Vector3(0, 2.0, 0)]:
		var query = PhysicsPointQueryParameters3D.new()
		query.position = sample
		query.collision_mask = 4
		var results = space.intersect_point(query)
		for hit in results:
			var collider = hit.get("collider")
			if collider is Area3D and collider.collision_layer & 4 != 0:
				return true
	return false


func _spawn_landing_impact_effect() -> void:
	# Expanding Shockwave Ring
	var shockwave = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.4
	cylinder.bottom_radius = 0.5
	cylinder.height = 0.04
	shockwave.mesh = cylinder

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.9, 0.85, 0.75, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.4)
	mat.emission_energy_multiplier = 2.5
	shockwave.material_override = mat

	get_tree().current_scene.add_child(shockwave)
	shockwave.global_position = global_position + Vector3(0, 0.05, 0)

	var tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property(shockwave, "scale", Vector3(5.5, 1.0, 5.5), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tween.chain().tween_callback(shockwave.queue_free)

	# Dust Puffs Expanding Outward
	for i in range(8):
		var dust = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = randf_range(0.2, 0.4)
		sphere.height = sphere.radius * 2.0
		dust.mesh = sphere

		var d_mat = StandardMaterial3D.new()
		d_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		d_mat.albedo_color = Color(0.75, 0.70, 0.65, 0.7)
		dust.material_override = d_mat

		get_tree().current_scene.add_child(dust)
		var angle = (i / 8.0) * TAU
		var dir = Vector3(cos(angle), 0.1, sin(angle))
		dust.global_position = global_position + dir * 0.3

		var dtween = get_tree().create_tween().set_parallel(true)
		dtween.tween_property(dust, "global_position", global_position + dir * randf_range(2.0, 3.5) + Vector3(0, randf_range(0.3, 0.7), 0), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		dtween.tween_property(d_mat, "albedo_color:a", 0.0, 0.4)
		dtween.chain().tween_callback(dust.queue_free)


func _spawn_roller_spark_effect() -> void:
	var spark = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.15, 0.05, 0.4)
	spark.mesh = box

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.7, 0.2, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.3)
	mat.emission_energy_multiplier = 4.0
	spark.material_override = mat

	get_tree().current_scene.add_child(spark)
	spark.global_position = global_position + Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3))
	spark.global_rotation = global_rotation

	var tween = get_tree().create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.15)
	tween.tween_callback(spark.queue_free)


func _start_dash() -> void:
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var cam_basis = cam.global_transform.basis
	var forward = -cam_basis.z
	var right = cam_basis.x
	forward.y = 0.0
	forward = forward.normalized()
	right.y = 0.0
	right = right.normalized()

	dash_direction = (forward * -input_dir.y + right * input_dir.x).normalized()
	if dash_direction.length() < 0.1:
		dash_direction = -transform.basis.z

	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	energy = maxf(energy - DASH_ENERGY_COST, 0.0)

	_spawn_dash_effect()
	if AudioManager:
		AudioManager.play_dash(global_position)


func _spawn_dash_effect() -> void:
	for i in range(3):
		var trail = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.8, 2.0, 1.5 - i * 0.3)
		trail.mesh = box

		var mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.5, 0.7, 1.0, 0.6 - i * 0.15)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.5, 1.0)
		mat.emission_energy_multiplier = 3.0 - i
		mat.no_depth_test = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		trail.material_override = mat

		get_tree().current_scene.add_child(trail)
		trail.global_position = global_position + Vector3(0, 1.5, 0) - dash_direction * (0.5 + i * 0.4)
		trail.global_rotation = global_rotation

		var tween = get_tree().create_tween()
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.2)
		tween.tween_callback(trail.queue_free)


func _recalculate_weight() -> void:
	if _recalculating:
		return
	_recalculating = true

	# Start with base frame weight (inner frame skeleton ~22.0 kg)
	var base_frame_weight: float = 22.0
	for slot in GlobalData.equipped_frames:
		var f = GlobalData.equipped_frames[slot]
		if f is Dictionary:
			base_frame_weight += f.get("weight", 3.0)

	total_weight = base_frame_weight
	for slot in GlobalData.equipped_parts:
		var part = GlobalData.equipped_parts[slot]
		if part:
			var break_thresh = part.break_threshold if "break_threshold" in part else 999.0
			if not GlobalData.part_damage.get(slot, 0.0) >= break_thresh:
				if part is ArmorPart:
					total_weight += part.weight
				elif part is Dictionary:
					total_weight += part.get("weight", 0.0)
	for attachment in GlobalData.attachments:
		total_weight += float(attachment.get("weight", 0.0))
	# Weapons (hands + back-carry) are real carried mass: count them exactly like
	# the Hangar TOTAL WEIGHT does, so mid-battle pickups/drops affect the mech.
	total_weight += GlobalData.get_loadout_weapon_weight()

	# Override vars are set from GlobalData.chassis_id by _apply_chassis_from_global_data().
	# ChassisData resource is used for base_turn_rate if assigned.
	var base_speed: float = _chassis_speed_override
	var weight_cap: float = _chassis_weight_capacity_override
	var base_turn: float = chassis.base_turn_rate if chassis else 4.0

	# Clamp turn rate to [3.0, 15.0] rad/s so low weight doesn't cause infinite rotation speed
	var calculated_turn = base_turn * (weight_cap / maxf(total_weight, 20.0))
	turn_rate = clampf(calculated_turn, 3.0, 15.0)
	current_speed = base_speed * (1.0 - clampf(total_weight / weight_cap, 0.0, 0.25))

	_recalculating = false


func _initialize_mesh_from_global_data() -> void:
	var pmm = get_node_or_null("PartMeshManager")
	if not pmm:
		return
	pmm.refresh_slots()


func _on_weight_changed(_w: float) -> void:
	_recalculate_weight()
