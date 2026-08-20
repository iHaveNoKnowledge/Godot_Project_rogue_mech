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
# No cooldown — the dash is gated purely by energy. Spamming burns the tank
# fast; precise, well-timed dashes conserve fuel. Works mid-air too: the mech
# shifts its arms/legs and body mass to steer its center of gravity.
var dash_timer: float = 0.0
var is_dashing: bool = false
var dash_direction: Vector3 = Vector3.ZERO
var current_dash_speed: float = 25.0

# --- Flash Burn & Spam Dash Dynamics (GDD §5.1) -----------------------------
# Spamming dash bursts in rapid succession causes Flash Burn: short-pulse
# ignition cannot maintain momentum, reactor heat spikes, and fuel burns +50% faster.
var _dash_spam_window: float = 0.0
var _dash_spam_count: int = 0
const SPAM_DASH_WINDOW := 0.75
const SPAM_DASH_ENERGY_PENALTY_MULT := 0.5
const SPAM_DASH_MOMENTUM_PENALTY := 0.25

# --- Energy system ----------------------------------------------------------
# The mech runs on a finite energy pool. Normal walking is nearly free, but
# every dash costs a chunk of energy and sustained roller dashing drains the
# pool at an ever-increasing rate — so spamming dashes or holding the roller
# burns through it fast. Releasing the throttle lets the pool recharge.
var max_energy: float = 200.0
var energy: float = 200.0
const DASH_ENERGY_COST := 6.0         # energy per dash burst (cheap =鼓励 precise dashes)
const ENERGY_REGEN_RATE := 10.0       # per second while not boosting
# --- Precision Dash (GDD §3.2) ---------------------------------------------
# Dashing at the right moment — just before an enemy attack lands — refunds
# energy and plays a visual/audio cue. The window is short: 0.4s after dash
# start, the system scans for enemy projectiles within 2.0 m of the dash start
# position (meaning the attack would have hit if the player hadn't moved).
var _dash_start_pos: Vector3 = Vector3.ZERO
var _precision_window: float = 0.0    # counts down from PRECISION_WINDOW after dash start
var _precision_armed: bool = false    # true while scanning for near-misses
var _precision_dodged: bool = false   # true if a precision dodge was detected this dash
var _precision_cooldown: float = 0.0  # prevents double-triggering on the same attack
const PRECISION_WINDOW := 0.4         # seconds after dash start to detect near-misses
const PRECISION_NEAR_MISS_DIST := 2.5 # meters: how close a projectile must pass to dash start
const PRECISION_ENERGY_REFUND := 4.0  # energy refunded on a precision dodge (net gain = refund - cost)
const PRECISION_COOLDOWN := 0.5       # seconds between precision dodge triggers
const ROLLER_BASE_DRAIN := 2.0        # per second the roller is held (gentle)
const ROLLER_RAMP_DRAIN := 3.0        # extra per second per second of continuous roller use
const ROLLER_MAX_DRAIN := 20.0        # ceiling so a full tank lasts ~10s at max burn
var roller_drain_ramp: float = 0.0    # grows while the roller is held, resets on release
# --- External Drop Tanks (GDD §2.4) ----------------------------------------
# Bolt-on fuel canisters that extend the mech's energy pool in combat. They
# are fragile — enemy fire can detonate them. The player can Purge (jettison)
# before they explode. Drop tank fuel is consumed FIRST from the pool.
var _drop_tank_active: bool = false   # true when drop tanks are mounted this fight
var _drop_tank_hp: float = 30.0       # HP before detonation (shared across all tanks)
var _drop_tank_detonating: bool = false  # countdown to explosion after HP reaches 0
var _drop_tank_timer: float = 0.0     # seconds until detonation
const DROP_TANK_DET_DELAY := 1.5      # seconds between HP=0 and explosion
const DROP_TANK_HP_PER_TANK := 30.0   # HP added per attached tank
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
	# Load persisted energy from GlobalData (survives combat/board transitions).
	max_energy = GlobalData.mech_max_energy
	energy = clampf(GlobalData.mech_energy, 0.0, max_energy)
	# Initialize external drop tanks from GlobalData.
	if GlobalData.drop_tanks_attached > 0 and GlobalData.drop_tank_fuel > 0.0:
		_drop_tank_active = true
		_drop_tank_hp = GlobalData.drop_tanks_attached * DROP_TANK_HP_PER_TANK
		max_energy += GlobalData.drop_tank_fuel
		energy += GlobalData.drop_tank_fuel
	var dtv = get_node_or_null("DropTankVisuals")
	if dtv and dtv.has_method("_refresh"):
		dtv._refresh()


func _exit_tree() -> void:
	# Persist current energy back to GlobalData so it survives scene transitions.
	GlobalData.mech_energy = energy
	GlobalData.mech_max_energy = max_energy
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
	var info = LoadoutSystem.get_chassis_stats()
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


# True while the mech is in its core-breach death window (body HP depleted, the
# machine is ragdolled and counting down to detonation). During that time every
# function is dead except the eject seat — movement, dash, roller, jump and the
# weapon inputs all refuse to respond so the mech reads as genuinely out.
func _is_downed() -> bool:
	var hs := _health_system()
	return hs != null and bool(hs.get("is_destroyed"))


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
	if _is_downed():
		# Core-breach window: the mech has ragdolled and no longer responds to
		# any input except eject. Cut the roller hum too (the loop would keep
		# playing on the autoload otherwise).
		if AudioManager:
			AudioManager.stop_roller_dash()
		return
	# Roller wheels need ground under them: leaving the floor (a jump) cuts the
	# roller out immediately, so it can never boost air speed.
	if is_roller_dashing and not is_on_floor():
		is_roller_dashing = false
		roller_drain_ramp = 0.0
	_process_energy(delta)
	_process_drop_tanks(delta)
	_process_jump(delta)

	if _dash_spam_window > 0.0:
		_dash_spam_window = maxf(_dash_spam_window - delta, 0.0)
		if _dash_spam_window <= 0.0:
			_dash_spam_count = 0

	if is_dashing:
		dash_timer -= delta
		velocity.x = dash_direction.x * current_dash_speed
		velocity.z = dash_direction.z * current_dash_speed
		if dash_timer <= 0.0:
			is_dashing = false
	else:
		_handle_movement_input()
		_apply_movement(delta)

	# Precision Dash detection: during the window after dash start, scan for
	# enemy projectiles that pass near the dash start position (near-miss).
	if _precision_armed and not _precision_dodged:
		_precision_window -= delta
		if _precision_window <= 0.0:
			_precision_armed = false
		else:
			_check_precision_dash_near_miss()
	if _precision_cooldown > 0.0:
		_precision_cooldown -= delta

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

	if Input.is_action_just_pressed("dash"):
		if energy >= DASH_ENERGY_COST:
			_start_dash()

	# Jump only starts on the ground; the launch itself is handled by
	# _start_jump/_process_jump (variable height + momentum + energy cost).
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		_start_jump()

	# Drop tank purge: jettison external fuel tanks to avoid detonation.
	if _drop_tank_active and Input.is_action_just_pressed("eject"):
		_purge_drop_tanks()


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
	var power := float(LoadoutSystem.get_chassis_stats().get("power", 12.0))
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
		# Dust Storm: roller drain x1.5 — sand clogs the wheels.
		var drain_mult := GlobalData.DUST_STORM_ROLLER_DRAIN_MULT if GlobalData.current_hazard == GlobalData.HAZARD_DUST_STORM else 1.0
		energy = maxf(energy - (ROLLER_BASE_DRAIN + roller_drain_ramp) * drain_mult * delta, 0.0)
		if energy <= 0.0:
			# Out of juice: the roller cuts out mid-run.
			is_roller_dashing = false
			roller_drain_ramp = 0.0
			if AudioManager:
				AudioManager.play_mecha_actuator(global_position)
	else:
		roller_drain_ramp = 0.0
		# Engine dirt slows energy regen — dirty fuel burns less efficiently.
		var dirt_penalty := lerpf(1.0, 1.0 / GlobalData.ENGINE_DIRT_HEAT_MULTIPLIER, GlobalData.engine_dirt)
		energy = minf(energy + ENERGY_REGEN_RATE * dirt_penalty * delta, max_energy)


# --- Precision Dash Detection (GDD §3.2) ------------------------------------
# Scans for enemy projectiles that pass within PRECISION_NEAR_MISS_DIST of the
# dash start position. If found, the player dodged an attack at the last moment
# and is rewarded with an energy refund + visual feedback.
func _check_precision_dash_near_miss() -> void:
	if _precision_cooldown > 0.0:
		return
	var projectiles = get_tree().get_nodes_in_group("projectile")
	for proj in projectiles:
		if not is_instance_valid(proj):
			continue
		# Only enemy projectiles count for precision dodge.
		if not proj.get("fired_by_enemy", false):
			continue
		var dist := proj.global_position.distance_to(_dash_start_pos)
		if dist < PRECISION_NEAR_MISS_DIST:
			_precision_dodged = true
			_precision_armed = false
			_precision_cooldown = PRECISION_COOLDOWN
			_trigger_precision_dodge(proj.global_position)
			return


func _trigger_precision_dodge(hit_pos: Vector3) -> void:
	# Refund energy — the dash cost 6.0, refund 4.0 = net cost only 2.0.
	energy = minf(energy + PRECISION_ENERGY_REFUND, max_energy)
	# Visual feedback: green flash + energy surge particles.
	_spawn_precision_flash(hit_pos)
	# Audio cue.
	if AudioManager:
		AudioManager.play_mecha_actuator(global_position)


func _spawn_precision_flash(from_pos: Vector3) -> void:
	EffectFactory.spawn_flash(get_tree(), from_pos, Color(0.3, 1.0, 0.5),
		0.5, 0.15, 5.0, true, 2.0)


# --- External Drop Tank Processing (GDD §2.4) --------------------------------
# Drop tanks add bonus energy capacity but are fragile. If their HP reaches
# zero, a short detonation countdown starts — the player must Purge before
# it expires or the explosion deals self-damage and destroys the tanks.
func _process_drop_tanks(delta: float) -> void:
	if not _drop_tank_active:
		return
	if _drop_tank_detonating:
		_drop_tank_timer -= delta
		if _drop_tank_timer <= 0.0:
			_drop_tank_explode()
		return
	# Drop tanks have HP; enemy fire can hit them via the health system's
	# part-damage routing. Once HP hits zero, the detonation countdown begins.
	# The HP is tracked here, set by apply_drop_tank_damage().


# Called by the health system when a projectile hits a drop tank hitbox.
func apply_drop_tank_damage(amount: float) -> void:
	if not _drop_tank_active or _drop_tank_detonating:
		return
	_drop_tank_hp -= amount
	# Notify the visual system to start sparking.
	var dtv = get_node_or_null("DropTankVisuals")
	if dtv and dtv.has_method("on_drop_tank_damaged"):
		dtv.on_drop_tank_damaged()
	if _drop_tank_hp <= 0.0:
		_drop_tank_detonating = true
		_drop_tank_timer = DROP_TANK_DET_DELAY
		if AudioManager:
			AudioManager.play_mecha_actuator(global_position)


# Purge: jettison the drop tanks to avoid detonation. Costs a small amount
# of energy (the explosive bolts firing) but prevents the self-damage.
func _purge_drop_tanks() -> void:
	if not _drop_tank_active:
		return
	# Expel the tanks: lose all drop-tank fuel and the extra capacity.
	var tank_fuel := GlobalData.drop_tank_fuel
	var fuel_in_tanks := minf(tank_fuel, energy - (max_energy - tank_fuel))
	energy = maxf(energy - tank_fuel, 0.0)
	max_energy -= tank_fuel
	# Reset drop tank state.
	_drop_tank_active = false
	_drop_tank_hp = 0.0
	_drop_tank_detonating = false
	_drop_tank_timer = 0.0
	GlobalData.drop_tanks_attached = 0
	GlobalData.drop_tank_fuel = 0.0
	# Visual: purge animation on the 3D model.
	var dtv = get_node_or_null("DropTankVisuals")
	if dtv and dtv.has_method("on_drop_tank_purged"):
		dtv.on_drop_tank_purged()
	# Additional scene-level VFX.
	_spawn_purge_effect()
	if AudioManager:
		AudioManager.play_mecha_actuator(global_position)


# Detonation: drop tanks explode, dealing self-damage and destroying the tanks.
func _drop_tank_explode() -> void:
	_drop_tank_active = false
	_drop_tank_detonating = false
	_drop_tank_timer = 0.0
	# Lose all drop tank fuel.
	var tank_fuel := GlobalData.drop_tank_fuel
	energy = maxf(energy - tank_fuel, 0.0)
	max_energy -= tank_fuel
	GlobalData.drop_tanks_attached = 0
	GlobalData.drop_tank_fuel = 0.0
	# Notify the visual system.
	var dtv = get_node_or_null("DropTankVisuals")
	if dtv and dtv.has_method("on_drop_tank_destroyed"):
		dtv.on_drop_tank_destroyed()
	if dtv and dtv.has_method("_clear_tanks"):
		dtv._clear_tanks()
	# Self-damage from the explosion.
	var hs := _health_system()
	if hs and hs.has_method("take_damage"):
		hs.take_damage(GlobalData.DROP_TANK_PURGE_DAMAGE, "explosive")
	if AudioManager:
		AudioManager.play_mecha_hit(global_position)
	# VFX.
	_spawn_detonation_effect()


func _spawn_purge_effect() -> void:
	EffectFactory.spawn_flash(get_tree(), global_position + Vector3(0, 1.0, 0),
		Color(0.4, 0.7, 1.0), 0.6, 0.3, 4.0, false, 3.0)


func _spawn_detonation_effect() -> void:
	for i in range(4):
		var offset := Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 1.5), randf_range(-1.0, 1.0))
		EffectFactory.spawn_box_spark(get_tree(), global_position + offset,
			Vector3(0.8, 0.3, 0.8), Color(1.0, 0.6, 0.1), 0.4, 6.0)


def _apply_movement(delta: float) -> void:
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
	# Dust Storm: movement speed x0.85 — sand resistance slows the mech.
	if GlobalData.current_hazard == GlobalData.HAZARD_DUST_STORM:
		move_speed *= GlobalData.DUST_STORM_SPEED_MULT

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
	EffectFactory.spawn_expanding_ring(get_tree(),
		global_position + Vector3(0, 0.05, 0),
		Color(1.0, 0.8, 0.4), Vector3(1, 1, 1), Vector3(5.5, 1.0, 5.5), 0.35, 2.5)
	EffectFactory.spawn_dust_puffs(get_tree(), global_position, 8)


func _spawn_roller_spark_effect() -> void:
	var spark_pos := global_position + Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3))
	EffectFactory.spawn_box_spark(get_tree(), spark_pos,
		Vector3(0.15, 0.05, 0.4), Color(1.0, 0.7, 0.2), 0.15, 4.0)


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

	var has_precog := GlobalData.has_pilot_perk("precognitive_flow")
	var is_flash_burn := false
	if not has_precog and _dash_spam_window > 0.0:
		_dash_spam_count += 1
		is_flash_burn = true
	else:
		_dash_spam_count = 1

	_dash_spam_window = SPAM_DASH_WINDOW

	var base_cost := DASH_ENERGY_COST * (0.5 if has_precog else 1.0)
	var actual_cost: float = base_cost * (1.0 + float(_dash_spam_count - 1) * SPAM_DASH_ENERGY_PENALTY_MULT)
	energy = maxf(energy - actual_cost, 0.0)
	current_dash_speed = dash_speed * (1.0 - (SPAM_DASH_MOMENTUM_PENALTY if is_flash_burn else 0.0))

	is_dashing = true
	dash_timer = dash_duration
	# Arm Precision Dash: record start position and open the detection window.
	_dash_start_pos = global_position
	_precision_window = PRECISION_WINDOW * (1.5 if has_precog else 1.0)
	_precision_armed = true
	_precision_dodged = false

	_spawn_dash_effect(is_flash_burn)
	if AudioManager:
		AudioManager.play_dash(global_position)


func _spawn_dash_effect(is_flash_burn: bool = false) -> void:
	for i in range(3):
		var trail_pos := global_position + Vector3(0, 1.5, 0) - dash_direction * (0.5 + i * 0.4)
		var color: Color
		var emission: Color
		if is_flash_burn:
			color = Color(1.0, 0.35, 0.15, 0.7 - i * 0.15)
			emission = Color(1.0, 0.25, 0.05)
		else:
			color = Color(0.5, 0.7, 1.0, 0.6 - i * 0.15)
			emission = Color(0.3, 0.5, 1.0)
		EffectFactory.spawn_trail(get_tree(), trail_pos, global_rotation,
			Vector3(0.8, 2.0, 1.5 - i * 0.3), color, emission, 0.2,
			4.0 - i if is_flash_burn else 3.0 - i)


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
	total_weight += LoadoutSystem.get_loadout_weapon_weight()

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
