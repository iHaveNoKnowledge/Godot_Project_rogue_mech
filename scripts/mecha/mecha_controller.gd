extends CharacterBody3D

@export var chassis: ChassisData

var total_weight: float = 0.0
var current_speed: float = 0.0
var turn_rate: float = 0.0
var strafe_mode: bool = false
var input_dir: Vector2 = Vector2.ZERO

const GRAVITY := 20.0

# Subsystems — public references so callers access state directly
# (e.g. mecha.jump_system.is_jumping instead of mecha.is_jumping).
var jump_system: Node = null
var dash_system: Node = null
var energy_system: Node = null

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

var energy: float:
	get:
		return energy_system.energy if energy_system else (GlobalData.fuel.mech_energy if GlobalData.fuel else 100.0)
	set(val):
		if energy_system:
			energy_system.energy = val
		elif GlobalData.fuel:
			GlobalData.fuel.mech_energy = val

var max_energy: float:
	get:
		return energy_system.max_energy if energy_system else (GlobalData.fuel.mech_max_energy if GlobalData.fuel else 100.0)
	set(val):
		if energy_system:
			energy_system.max_energy = val
		elif GlobalData.fuel:
			GlobalData.fuel.mech_max_energy = val


func _init() -> void:
	jump_system = preload("res://scripts/mecha/mecha_jump_system.gd").new()
	dash_system = preload("res://scripts/mecha/mecha_dash_system.gd").new()
	energy_system = preload("res://scripts/mecha/mecha_energy_system.gd").new()


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

	# Register subsystems in tree if not already added.
	if jump_system.get_parent() == null:
		jump_system.name = "JumpSystem"
		add_child(jump_system)

	if dash_system.get_parent() == null:
		dash_system.name = "DashSystem"
		add_child(dash_system)

	if energy_system.get_parent() == null:
		energy_system.name = "EnergySystem"
		add_child(energy_system)
		energy_system.initialize_from_global()


func _exit_tree() -> void:
	energy_system.persist_to_global()
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
		energy_system.roller_drain_ramp = 0.0

	# Sync subsystem state.
	energy_system.is_roller_dashing = is_roller_dashing
	energy_system.input_dir = input_dir
	energy_system.is_on_floor = is_on_floor()
	dash_system.input_dir = input_dir
	jump_system.total_weight = total_weight
	jump_system.chassis_weight_capacity = _chassis_weight_capacity_override
	jump_system.velocity_ref = velocity

	energy_system.process_energy(delta)
	energy_system.process_drop_tanks(delta)
	dash_system.tick(delta)

	if dash_system.is_dashing:
		velocity = dash_system.apply_velocity(velocity)
	else:
		_handle_movement_input()
		_apply_movement(delta)

	if not is_on_floor():
		if jump_system and jump_system.is_gliding and energy_system.energy > 0.0:
			# Apply thruster slow-fall glide and drain energy
			var drain: float = float(jump_system.GLIDE_ENERGY_DRAIN) * delta
			energy_system.energy = maxf(energy_system.energy - drain, 0.0)
			if energy_system.energy <= 0.0:
				jump_system.is_gliding = false
			velocity.y = jump_system.process_glide(delta, velocity.y)
			jump_system.tick_glide_vfx(delta, get_tree(), global_position)
		else:
			velocity.y -= GRAVITY * delta
	else:
		if jump_system:
			jump_system.is_gliding = false
			jump_system.is_jumping = false

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
	if jump_system:
		jump_system.total_weight = total_weight
		jump_system.chassis_weight_capacity = _chassis_weight_capacity_override
		var cost: float = jump_system.start_jump(energy_system.energy, global_position, velocity)
		if cost > 0.0:
			energy_system.energy = maxf(energy_system.energy - cost, 0.0)
			velocity.y = jump_system.velocity_ref.y
			floor_snap_length = 0.0
			if AudioManager:
				AudioManager.play_jump(global_position)
			EffectFactory.spawn_dust_puffs(get_tree(), global_position, 8)
			return cost
	return 0.0


func _start_dash() -> void:
	if dash_system and energy_system:
		if dash_system.can_dash(energy_system.energy):
			var cost: float = dash_system.start_dash(energy_system.energy, global_position, global_transform.basis)
			energy_system.energy = maxf(energy_system.energy - cost, 0.0)


# --- Movement input & application -------------------------------------------

func _handle_movement_input() -> void:
	input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	strafe_mode = Input.is_action_pressed("strafe")

	# Roller toggle.
	if Input.is_action_just_pressed("roller_dash"):
		if not is_on_floor():
			is_roller_dashing = false
			energy_system.roller_drain_ramp = 0.0
		elif energy_system.energy > 1.0:
			if not is_roller_dashing:
				energy_system.roller_drain_ramp = 0.0
			is_roller_dashing = not is_roller_dashing
			if AudioManager:
				AudioManager.play_mecha_actuator(global_position)
		else:
			is_roller_dashing = false
			energy_system.roller_drain_ramp = 0.0

	# Dash.
	if Input.is_action_just_pressed("dash"):
		_start_dash()

	# Jump & Mid-Air Thruster Glide
	if jump_system:
		if is_on_floor():
			if Input.is_action_just_pressed("jump"):
				_start_jump()
		else:
			# While mid-air, holding or pressing jump engages thruster slow-fall glide
			if Input.is_action_pressed("jump") and energy_system.energy > 0.5:
				jump_system.is_gliding = true
			else:
				jump_system.is_gliding = false

	# Drop tank purge.
	if energy_system._drop_tank_active and Input.is_action_just_pressed("eject"):
		energy_system.purge_drop_tanks()


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
	if GlobalData.board.current_hazard == GlobalData.HAZARD_DUST_STORM:
		move_speed *= GlobalData.DUST_STORM_SPEED_MULT

	var desired_velocity := Vector3.ZERO
	desired_velocity = (forward * -input_dir.y + right * input_dir.x) * move_speed

	var is_attacking: bool = Input.is_action_pressed("fire_left") or Input.is_action_pressed("fire_right")
	var wm = get_node_or_null("WeaponManager")
	if wm:
		if wm.get("fire_left_holding") or wm.get("fire_right_holding") or (wm.get("_pending_fire") != null and str(wm.get("_pending_fire")) != ""):
			is_attacking = true

	if is_attacking or strafe_mode:
		var target_angle = atan2(-forward.x, -forward.z)
		var effective_turn = maxf(turn_rate * 2.5, 16.0)
		var lerp_weight = clampf(effective_turn * delta, 0.0, 1.0)
		rotation.y = lerp_angle(rotation.y, target_angle, lerp_weight)
	elif desired_velocity.length() > 0.1:
		var target_angle = atan2(-desired_velocity.x, -desired_velocity.z)
		var effective_turn = turn_rate * (1.5 if is_roller_dashing else 1.0)
		var lerp_weight = clampf(effective_turn * delta, 0.0, 1.0)
		rotation.y = lerp_angle(rotation.y, target_angle, lerp_weight)

	velocity.x = desired_velocity.x
	velocity.z = desired_velocity.z

	# Roller spark VFX while grounded and skating.
	if is_on_floor() and is_roller_dashing and desired_velocity.length() > 0.5:
		roller_spark_timer -= delta
		if roller_spark_timer <= 0.0:
			roller_spark_timer = 0.08
			var spark_pos := global_position + Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3))
			EffectFactory.spawn_box_spark(get_tree(), spark_pos,
				Vector3(0.15, 0.05, 0.4), Color(1.0, 0.7, 0.2), 0.15, 4.0)

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
	if GlobalData.board.current_hazard == GlobalData.HAZARD_EMP_ZONE:
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
	for slot in GlobalData.weapons.equipped_frames:
		var f = GlobalData.weapons.equipped_frames[slot]
		if f is Dictionary:
			base_frame_weight += f.get("weight", 3.0)
	total_weight = base_frame_weight
	for slot in GlobalData.weapons.equipped_parts:
		var part = GlobalData.weapons.equipped_parts[slot]
		if part:
			var break_thresh = part.break_threshold if "break_threshold" in part else 999.0
			if not GlobalData.weapons.part_damage.get(slot, 0.0) >= break_thresh:
				if part is ArmorPart:
					total_weight += part.weight
				elif part is Dictionary:
					total_weight += part.get("weight", 0.0)
	for attachment in GlobalData.weapons.attachments:
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
