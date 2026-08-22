class_name MechaFootIK
extends Node3D

## ---------------------------------------------------------------------------
## MECHA FOOT IK & GROUND PLACEMENT SYSTEM
##
## Automatically aligns the mecha's feet to ground slope normals and adjusts
## leg/hip heights to prevent feet floating in the air or sinking into terrain.
##
## Designed for Godot 4.6.2. Works seamlessly across Walking, Sprinting,
## Roller Dashing, and Idle combat postures.
## ---------------------------------------------------------------------------

@export var enabled: bool = true
@export var ray_height: float = 1.6
@export var ray_length: float = 2.5
@export var foot_spacing_x: float = 0.38
@export var max_step_height: float = 0.6
@export var ik_blend_speed: float = 12.0
@export var ankle_rotation_speed: float = 14.0
@export var hip_adjustment_speed: float = 10.0

var mecha: CharacterBody3D = null
var leg_left: Node3D = null
var leg_right: Node3D = null
var shin_left: Node3D = null
var shin_right: Node3D = null
var foot_left: Node3D = null
var foot_right: Node3D = null

var ray_left: RayCast3D = null
var ray_right: RayCast3D = null

var ik_weight: float = 0.0
var _current_hip_offset: float = 0.0
var _current_left_foot_offset: float = 0.0
var _current_right_foot_offset: float = 0.0

var _left_ankle_quat: Quaternion = Quaternion.IDENTITY
var _right_ankle_quat: Quaternion = Quaternion.IDENTITY

var _orig_leg_left_pos: Vector3 = Vector3.ZERO
var _orig_leg_right_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	mecha = get_parent() as CharacterBody3D
	_setup_raycasts()
	_resolve_nodes()


func _setup_raycasts() -> void:
	if ray_left == null:
		ray_left = RayCast3D.new()
		ray_left.name = "FootRayLeft"
		ray_left.position = Vector3(-foot_spacing_x, ray_height, 0.0)
		ray_left.target_position = Vector3(0, -ray_length, 0)
		ray_left.collision_mask = 1 # Environment / Terrain
		ray_left.hit_from_inside = true
		add_child(ray_left)

	if ray_right == null:
		ray_right = RayCast3D.new()
		ray_right.name = "FootRayRight"
		ray_right.position = Vector3(foot_spacing_x, ray_height, 0.0)
		ray_right.target_position = Vector3(0, -ray_length, 0)
		ray_right.collision_mask = 1
		ray_right.hit_from_inside = true
		add_child(ray_right)


func _resolve_nodes() -> void:
	if mecha == null:
		return
	leg_left = mecha.get_node_or_null("LegLeft")
	leg_right = mecha.get_node_or_null("LegRight")
	shin_left = mecha.get_node_or_null("LegLeft/ShinLeft")
	shin_right = mecha.get_node_or_null("LegRight/ShinRight")
	foot_left = mecha.get_node_or_null("LegLeft/ShinLeft/FootLeft")
	foot_right = mecha.get_node_or_null("LegRight/ShinRight/FootRight")

	if leg_left and _orig_leg_left_pos == Vector3.ZERO:
		_orig_leg_left_pos = leg_left.position
	if leg_right and _orig_leg_right_pos == Vector3.ZERO:
		_orig_leg_right_pos = leg_right.position

	# Make sure raycasts ignore the mecha itself
	if ray_left:
		ray_left.add_exception(mecha)
	if ray_right:
		ray_right.add_exception(mecha)


func update_ik(delta: float) -> void:
	if not enabled or mecha == null:
		return

	_resolve_nodes()
	if leg_left == null or leg_right == null:
		return

	var is_grounded := mecha.is_on_floor()
	var target_weight := 1.0 if is_grounded else 0.0
	ik_weight = lerpf(ik_weight, target_weight, ik_blend_speed * delta)

	if ik_weight < 0.001:
		_reset_pose(delta)
		return

	_process_foot_placement(delta)


func _process_foot_placement(delta: float) -> void:
	# 1. Query raycasts
	var left_hit := ray_left.is_colliding()
	var right_hit := ray_right.is_colliding()

	var left_offset := 0.0
	var right_offset := 0.0
	var left_normal := Vector3.UP
	var right_normal := Vector3.UP

	var m_scale_y := maxf(mecha.scale.y, 0.001)

	if left_hit:
		var pt := ray_left.get_collision_point()
		var rel_y := (pt.y - mecha.global_position.y) / m_scale_y
		left_offset = clampf(rel_y, -max_step_height, max_step_height)
		left_normal = ray_left.get_collision_normal()

	if right_hit:
		var pt := ray_right.get_collision_point()
		var rel_y := (pt.y - mecha.global_position.y) / m_scale_y
		right_offset = clampf(rel_y, -max_step_height, max_step_height)
		right_normal = ray_right.get_collision_normal()

	# 2. Smooth targets
	_current_left_foot_offset = lerpf(_current_left_foot_offset, left_offset * ik_weight, hip_adjustment_speed * delta)
	_current_right_foot_offset = lerpf(_current_right_foot_offset, right_offset * ik_weight, hip_adjustment_speed * delta)

	# 3. Leg vertical height adaptation
	if leg_left:
		leg_left.position.y = _orig_leg_left_pos.y + _current_left_foot_offset
	if leg_right:
		leg_right.position.y = _orig_leg_right_pos.y + _current_right_foot_offset

	# 4. Ankle rotation alignment (match terrain normal)
	_apply_ankle_alignment(foot_left, left_normal, delta, true)
	_apply_ankle_alignment(foot_right, right_normal, delta, false)


func _apply_ankle_alignment(foot_node: Node3D, world_normal: Vector3, delta: float, is_left: bool) -> void:
	if foot_node == null:
		return

	# Transform world normal into mecha local orientation
	var local_normal := mecha.global_transform.basis.inverse() * world_normal
	local_normal = local_normal.normalized()

	# Compute pitch (forward/back tilt) and roll (left/right tilt)
	var pitch := atan2(local_normal.z, local_normal.y)
	var roll := -atan2(local_normal.x, local_normal.y)

	# Clamp to reasonable mecha ankle ranges (-45 deg to +45 deg)
	pitch = clampf(pitch, -deg_to_rad(45.0), deg_to_rad(45.0))
	roll = clampf(roll, -deg_to_rad(30.0), deg_to_rad(30.0))

	var target_basis := Basis.from_euler(Vector3(pitch * ik_weight, 0.0, roll * ik_weight))
	var target_quat := target_basis.get_rotation_quaternion()

	if is_left:
		_left_ankle_quat = _left_ankle_quat.slerp(target_quat, ankle_rotation_speed * delta)
		foot_node.quaternion = _left_ankle_quat
	else:
		_right_ankle_quat = _right_ankle_quat.slerp(target_quat, ankle_rotation_speed * delta)
		foot_node.quaternion = _right_ankle_quat


func _reset_pose(delta: float) -> void:
	_current_left_foot_offset = lerpf(_current_left_foot_offset, 0.0, hip_adjustment_speed * delta)
	_current_right_foot_offset = lerpf(_current_right_foot_offset, 0.0, hip_adjustment_speed * delta)

	if leg_left:
		leg_left.position.y = lerpf(leg_left.position.y, _orig_leg_left_pos.y, hip_adjustment_speed * delta)
	if leg_right:
		leg_right.position.y = lerpf(leg_right.position.y, _orig_leg_right_pos.y, hip_adjustment_speed * delta)

	_left_ankle_quat = _left_ankle_quat.slerp(Quaternion.IDENTITY, ankle_rotation_speed * delta)
	_right_ankle_quat = _right_ankle_quat.slerp(Quaternion.IDENTITY, ankle_rotation_speed * delta)

	if foot_left:
		foot_left.quaternion = _left_ankle_quat
	if foot_right:
		foot_right.quaternion = _right_ankle_quat
