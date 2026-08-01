extends CharacterBody3D

@export var chassis: ChassisData

var total_weight: float = 0.0
var current_speed: float = 0.0
var turn_rate: float = 0.0
var strafe_mode: bool = false
var input_dir: Vector2 = Vector2.ZERO

const GRAVITY := 20.0
const JUMP_FORCE := 12.0

var dash_speed: float = 25.0
var dash_duration: float = 0.2
var dash_cooldown: float = 1.0
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var is_dashing: bool = false
var dash_direction: Vector3 = Vector3.ZERO
var _recalculating: bool = false
var was_in_air: bool = false
var footstep_timer: float = 0.0
var roller_skate_timer: float = 0.0

# Override values used when no ChassisData resource is assigned in the scene.
# Populated by _apply_chassis_from_global_data() from GlobalData.chassis_id.
var _chassis_speed_override: float = 14.0
var _chassis_weight_capacity_override: float = 75.0


func _ready() -> void:
	add_to_group("mecha")
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(60)
	_apply_chassis_from_global_data()
	_recalculate_weight()
	_initialize_mesh_from_global_data()
	EventBus.weight_changed.connect(_on_weight_changed)


# Apply chassis speed/weight from GlobalData.chassis_id.
# Always writes to override vars — never mutates the shared @export ChassisData Resource.
# _recalculate_weight() reads the override vars first, falling back to ChassisData only
# for base_turn_rate (which is not stored in chassis_catalog).
func _apply_chassis_from_global_data() -> void:
	var info = GlobalData.get_chassis_stats()
	_chassis_speed_override = info.get("speed", 7.0)
	_chassis_weight_capacity_override = info.get("max_weight", 75.0)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("eject"):
		var eject = get_node_or_null("MechaEject")
		if eject:
			eject.initiate_eject()


func _physics_process(delta: float) -> void:
	dash_cooldown_timer -= delta

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
		if has_node("/root/AudioManager"):
			AudioManager.play_land(global_position)
	was_in_air = not currently_on_floor

	move_and_slide()


var is_roller_dashing: bool = false
var roller_spark_timer: float = 0.0


func _handle_movement_input() -> void:
	input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	strafe_mode = Input.is_action_pressed("strafe")

	if Input.is_action_just_pressed("roller_dash"):
		is_roller_dashing = not is_roller_dashing
		if has_node("/root/AudioManager"):
			AudioManager.play_ui_click()

	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0.0:
		_start_dash()


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
			roller_skate_timer -= delta
			if roller_skate_timer <= 0.0:
				roller_skate_timer = 0.12
				if has_node("/root/AudioManager"):
					AudioManager.play_roller_skate(global_position)
		else:
			footstep_timer -= delta
			if footstep_timer <= 0.0:
				footstep_timer = 0.35
				if has_node("/root/AudioManager"):
					AudioManager.play_footstep(global_position)

	if not is_on_floor():
		was_in_air = true
	elif was_in_air and is_on_floor():
		was_in_air = false
		if has_node("/root/AudioManager"):
			AudioManager.play_land(global_position)

	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = 15.0
		if has_node("/root/AudioManager"):
			AudioManager.play_jump(global_position)

	velocity.y -= GRAVITY * delta


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

	_spawn_dash_effect()
	if has_node("/root/AudioManager"):
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
	var slots = ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]
	for slot in slots:
		var part_obj: ArmorPart = null
		if GlobalData.equipped_parts.has(slot):
			var equipped = GlobalData.equipped_parts[slot]
			if equipped is ArmorPart:
				part_obj = equipped
			elif equipped is Dictionary and not equipped.is_empty():
				part_obj = ArmorPart.new()
				part_obj.part_name = equipped.get("name", "Custom Armor")
				part_obj.max_hp = equipped.get("max_hp", equipped.get("durability", 100.0))
				if equipped.has("color"):
					part_obj.part_color = equipped.get("color")
		if part_obj == null:
			part_obj = ArmorPart.new()
			part_obj.part_name = "Tactical Armor"
			part_obj.max_hp = 100.0
			part_obj.part_color = Color(0.25, 0.40, 0.60)
		pmm.initialize_slot(slot, part_obj)


func _on_weight_changed(_w: float) -> void:
	_recalculate_weight()
