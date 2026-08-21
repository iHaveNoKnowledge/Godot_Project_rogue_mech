extends CharacterBody3D

const EffectFactory = preload("res://scripts/effects/effect_factory.gd")

@export var chassis: ChassisData

var total_weight: float = 0.0
var current_speed: float = 0.0
var turn_rate: float = 0.0
var strafe_mode: bool = false
var input_dir: Vector2 = Vector2.ZERO

const GRAVITY := 20.0

# Subsystems (created in _ready, attached as child nodes).
var _jump: Node  # MechaJumpSystem
var _dash: Node  # MechaDashSystem
var _energy: Node  # MechaEnergySystem

var energy: float:
	get:
		return _energy.energy if _energy else 100.0
	set(v):
		if _energy:
			_energy.energy = v

var max_energy: float:
	get:
		return _energy.max_energy if _energy else 100.0
	set(v):
		if _energy:
			_energy.max_energy = v

var _precision_dodged: bool:
	get:
		return _dash._precision_dodged if _dash else false
	set(v):
		if _dash:
			_dash._precision_dodged = v

var is_jumping: bool:
	get:
		return _jump.is_jumping if _jump else false
	set(v):
		if _jump:
			_jump.is_jumping = v

var jump_charge: float:
	get:
		return _jump.jump_charge if _jump else 0.0
	set(v):
		if _jump:
			_jump.jump_charge = v

var is_charging_prejump: bool:
	get:
		return _jump.is_charging_prejump if _jump else false

var prejump_charge_time: float:
	get:
		return _jump.prejump_charge_time if _jump else 0.0

var is_dashing: bool:
	get:
		return _dash.is_dashing if _dash else false
	set(v):
		if _dash:
			_dash.is_dashing = v

var dash_cooldown: float:
	get:
		return 0.5

var dash_cooldown_timer: float:
	get:
		return _dash._precision_cooldown if _dash else 0.0
	set(v):
		if _dash:
			_dash._precision_cooldown = v

var _drop_tank_active: bool:
	get:
		return _energy._drop_tank_active if _energy else false

var _drop_tank_detonating: bool:
	get:
		return _energy._drop_tank_detonating if _energy else false

# Roller state (kept on controller — input + VFX are controller concerns).
var is_roller_dashing: bool = false
var roller_spark_timer: float = 0.0
var _emp_spark_timer: float = 0.0

# Recoil (weapon kick).
var recoil_vector: Vector3 = Vector3.ZERO
var _recoil_recovery: float = 0.0

# Weight / chassis.
var _recalculating: bool = false
var was_in_air: bool = false
var footstep_timer: float = 0.0
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

	# Create subsystems.
	_jump = preload("res://scripts/mecha/mecha_jump_system.gd").new()
	_jump.name = "JumpSystem"
	add_child(_jump)

	_dash = preload("res://scripts/mecha/mecha_dash_system.gd").new()
	_dash.name = "DashSystem"
	add_child(_dash)

	_energy = preload("res://scripts/mecha/mecha_energy_system.gd").new()
	_energy.name = "EnergySystem"
	add_child(_energy)
	_energy.initialize_from_global()


func _exit_tree() -> void:
	_energy.persist_to_global()
	if AudioManager:
		AudioManager.stop_roller_dash()


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

func _health_system() -> Node:
	return get_node_or_null("HealthSystem")


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


# --- Recoil ----------------------------------------------------------------

func apply_recoil_impulse(backward: Vector3) -> void:
	backward.y = 0.0
	if backward.length() < 0.001:
		return
	recoil_vector += backward.normalized() * minf(backward.length(), 12.0)


func apply_heavy_recoil_impulse(backward: Vector3) -> void:
	backward.y = 0.0
	if backward.length() < 0.001:
		return
	recoil_vector += backward.normalized() * minf(backward.length(), 20.0)
	_recoil_recovery = clampf(_recoil_recovery + 0.55, 0.0, 2.5)


# --- Main physics loop ------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _is_downed():
		if AudioManager:
			AudioManager.stop_roller_dash()
		return

	# Roller wheels need ground: leaving floor cuts roller immediately.
	if is_roller_dashing and not is_on_floor():
		is_roller_dashing = false
		_energy.roller_drain_ramp = 0.0

	# Sync subsystem state.
	_energy.is_roller_dashing = is_roller_dashing
	_energy.input_dir = input_dir
	_energy.is_on_floor = is_on_floor()
	_dash.input_dir = input_dir
	_jump.total_weight = total_weight
	_jump.chassis_weight_capacity = _chassis_weight_capacity_override
	_jump.velocity_ref = velocity

	_energy.process_energy(delta)
	_energy.process_drop_tanks(delta)
	_dash.tick(delta)

	if _jump and _jump.is_charging_prejump:
		_jump.tick_prejump_charge(delta, is_on_floor())

	if _dash.is_dashing:
		velocity = _dash.apply_velocity(velocity)
	else:
		_handle_movement_input()
		_apply_movement(delta)

	if _jump.is_jumping:
		velocity.y = _jump.process_jump(delta, is_on_floor(), velocity.y)
	elif is_on_floor():
		_jump.is_jumping = false
		_jump.jump_charge = 0.0

	# Landing detection — restore floor snap so the mech sticks to slopes.
	var currently_on_floor = is_on_floor()
	if currently_on_floor and was_in_air:
		floor_snap_length = 0.3
		_trigger_landing_impact()
	was_in_air = not currently_on_floor

	move_and_slide()

	# Roller audio.
	var h_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	if is_roller_dashing and is_on_floor() and h_speed > 0.5:
		var ratio := h_speed / maxf(current_speed * 2.0, 1.0)
		if AudioManager:
			AudioManager.update_roller_dash(global_position, ratio)
	elif AudioManager:
		AudioManager.stop_roller_dash()


# --- Jump / Dash helper bridges --------------------------------------------

func _start_jump() -> float:
	if _jump:
		_jump.total_weight = total_weight
		_jump.chassis_weight_capacity = _chassis_weight_capacity_override
		var cost: float = _jump.start_jump(_energy.energy, global_position, velocity)
		if cost > 0.0:
			_energy.energy = maxf(_energy.energy - cost, 0.0)
			velocity.y = _jump.velocity_ref.y
			floor_snap_length = 0.0
			if AudioManager:
				AudioManager.play_jump(global_position)
			return cost
	return 0.0


func _release_prejump() -> float:
	if _jump:
		_jump.total_weight = total_weight
		_jump.chassis_weight_capacity = _chassis_weight_capacity_override
		var cost: float = _jump.release_prejump(_energy.energy, global_position, velocity)
		if cost > 0.0:
			_energy.energy = maxf(_energy.energy - cost, 0.0)
			velocity.y = _jump.velocity_ref.y
			floor_snap_length = 0.0
			if AudioManager:
				AudioManager.play_jump(global_position)
			EffectFactory.spawn_dust_puffs(get_tree(), global_position, 6)
			return cost
	return 0.0


func _jump_velocity(charge_frac: float) -> float:
	if _jump:
		_jump.velocity_ref = velocity
		_jump.total_weight = total_weight
		_jump.chassis_weight_capacity = _chassis_weight_capacity_override
		return float(_jump._jump_velocity(charge_frac, Vector3.ZERO))
	return 6.0


func _start_dash() -> void:
	if _dash and _energy:
		if _dash.can_dash(_energy.energy):
			var cost: float = _dash.start_dash(_energy.energy, global_position, global_transform.basis)
			_energy.energy = maxf(_energy.energy - cost, 0.0)


# --- Movement input & application -------------------------------------------

func _handle_movement_input() -> void:
	input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	strafe_mode = Input.is_action_pressed("strafe")

	# Roller toggle.
	if Input.is_action_just_pressed("roller_dash"):
		if not is_on_floor():
			is_roller_dashing = false
			_energy.roller_drain_ramp = 0.0
		elif _energy.energy > 1.0:
			if not is_roller_dashing:
				_energy.roller_drain_ramp = 0.0
			is_roller_dashing = not is_roller_dashing
			if AudioManager:
				AudioManager.play_mecha_actuator(global_position)
		else:
			is_roller_dashing = false
			_energy.roller_drain_ramp = 0.0

	# Dash.
	if Input.is_action_just_pressed("dash"):
		_start_dash()

	# Jump handling: Dual-mode (Jetpack Thruster vs Base Pre-Jump Charge)
	if _jump:
		var active_mode = _jump.get_active_jump_mode()
		if active_mode == _jump.JumpMode.JETPACK_THRUSTER:
			if is_on_floor() and Input.is_action_just_pressed("jump"):
				_start_jump()
		else:
			# Base Pre-Jump mode:
			if is_on_floor() and Input.is_action_just_pressed("jump"):
				_jump.start_prejump_charge()
			elif Input.is_action_just_released("jump") and _jump.is_charging_prejump:
				if is_on_floor():
					_release_prejump()
				else:
					_jump.cancel_prejump_charge()

	# Drop tank purge.
	if _energy._drop_tank_active and Input.is_action_just_pressed("eject"):
		_energy.purge_drop_tanks()


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

	# Footstep / roller spark VFX.
	if is_on_floor() and desired_velocity.length() > 0.5:
		if is_roller_dashing:
			roller_spark_timer -= delta
			if roller_spark_timer <= 0.0:
				roller_spark_timer = 0.08
				var spark_pos := global_position + Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3))
				EffectFactory.spawn_box_spark(get_tree(), spark_pos,
					Vector3(0.15, 0.05, 0.4), Color(1.0, 0.7, 0.2), 0.15, 4.0)
		else:
			footstep_timer -= delta
			if footstep_timer <= 0.0:
				footstep_timer = 0.35
				if AudioManager:
					AudioManager.play_footstep(global_position)

	# Recoil decay.
	if recoil_vector.length() > 0.001:
		velocity.x += recoil_vector.x
		velocity.z += recoil_vector.z
		var decay_rate := _recoil_decay_rate()
		if _recoil_recovery > 0.0:
			_recoil_recovery -= delta
			decay_rate *= 0.35
		recoil_vector = recoil_vector.move_toward(Vector3.ZERO, decay_rate * delta)

	# EMP Hazard Zone: electric spark discharges crackling across the mech chassis
	if GlobalData.current_hazard == GlobalData.HAZARD_EMP_ZONE:
		_emp_spark_timer -= delta
		if _emp_spark_timer <= 0.0:
			_emp_spark_timer = randf_range(0.3, 0.65)
			var spark_offset := Vector3(randf_range(-0.8, 0.8), randf_range(0.4, 2.0), randf_range(-0.8, 0.8))
			EffectFactory.spawn_electric_spark(get_tree(), global_position + spark_offset, Color(0.4, 0.85, 1.0), randf_range(0.5, 0.9), 0.12, 5.5)

	velocity.y -= GRAVITY * delta


func _recoil_decay_rate() -> float:
	var leg_power := GlobalData.get_leg_power()
	var rate := 30.0 + leg_power * 1.2 - clampf(total_weight * 0.12, 0.0, 18.0)
	return maxf(rate, 14.0)


# --- Landing impact ---------------------------------------------------------

func _trigger_landing_impact() -> void:
	if AudioManager:
		AudioManager.play_land(global_position)
	var rigs = get_tree().get_nodes_in_group("camera_rig")
	if not rigs.is_empty() and rigs[0].has_method("add_shake"):
		rigs[0].add_shake(0.50)
	var anim = get_node_or_null("AnimationSystem")
	if anim and anim.has_method("play_landing_impact"):
		anim.play_landing_impact()
	EffectFactory.spawn_expanding_ring(get_tree(),
		global_position + Vector3(0, 0.05, 0),
		Color(1.0, 0.8, 0.4), Vector3(1, 1, 1), Vector3(5.5, 1.0, 5.5), 0.35, 2.5)
	EffectFactory.spawn_dust_puffs(get_tree(), global_position, 8)


# --- Water detection --------------------------------------------------------

func _is_in_water() -> bool:
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


# --- Weight -----------------------------------------------------------------

func _recalculate_weight() -> void:
	if _recalculating:
		return
	_recalculating = true
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
	total_weight += LoadoutSystem.get_loadout_weapon_weight()
	var base_speed: float = _chassis_speed_override
	var weight_cap: float = _chassis_weight_capacity_override
	var base_turn: float = chassis.base_turn_rate if chassis else 4.0
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
