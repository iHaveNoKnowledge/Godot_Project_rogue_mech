extends Node

@export var bob_amount: float = 0.15
@export var bob_speed: float = 8.0
@export var recoil_amount: float = 0.3
@export var recoil_recovery: float = 10.0

var mecha: CharacterBody3D = null
var head_mesh: Node3D = null
var body_mesh: Node3D = null
var arm_left: Node3D = null
var arm_right: Node3D = null

var bob_timer: float = 0.0
var is_moving: bool = false
var current_recoil: float = 0.0

var _original_head_pos: Vector3
var _original_body_pos: Vector3
var _original_arm_left_pos: Vector3
var _original_arm_right_pos: Vector3


func _ready() -> void:
	mecha = get_parent()
	head_mesh = get_node_or_null("../Head")
	body_mesh = get_node_or_null("../Body")
	arm_left = get_node_or_null("../ArmLeft")
	arm_right = get_node_or_null("../ArmRight")

	if head_mesh:
		_original_head_pos = head_mesh.position
	if body_mesh:
		_original_body_pos = body_mesh.position
	if arm_left:
		_original_arm_left_pos = arm_left.position
	if arm_right:
		_original_arm_right_pos = arm_right.position


func _physics_process(delta: float) -> void:
	if mecha == null:
		return

	is_moving = mecha.velocity.length() > 1.0

	_update_bob(delta)
	_update_recoil(delta)
	_update_legs(delta)


func _update_bob(delta: float) -> void:
	if is_moving:
		bob_timer += delta * bob_speed
		var bob = sin(bob_timer) * bob_amount

		if body_mesh:
			body_mesh.position.y = _original_body_pos.y + bob * 0.5
		if head_mesh:
			head_mesh.position.y = _original_head_pos.y + bob
		if arm_left:
			arm_left.position.y = _original_arm_left_pos.y + bob * 0.3
			arm_left.position.x = _original_arm_left_pos.x + sin(bob_timer * 0.5) * 0.1
		if arm_right:
			arm_right.position.y = _original_arm_right_pos.y + bob * 0.3
			arm_right.position.x = _original_arm_right_pos.x - sin(bob_timer * 0.5) * 0.1
	else:
		bob_timer = 0.0
		_lerp_to_original(delta)


func _update_recoil(delta: float) -> void:
	if current_recoil > 0.0:
		current_recoil = move_toward(current_recoil, 0.0, recoil_recovery * delta)
		if head_mesh:
			head_mesh.rotation.x = -current_recoil * 0.5


func _update_legs(delta: float) -> void:
	var leg_left = get_node_or_null("../LegLeft")
	var leg_right = get_node_or_null("../LegRight")

	if is_moving and leg_left and leg_right:
		var leg_swing = sin(bob_timer * 2.0) * 0.3
		leg_left.rotation.x = leg_swing
		leg_right.rotation.x = -leg_swing
	else:
		if leg_left:
			leg_left.rotation.x = lerp(leg_left.rotation.x, 0.0, 5.0 * delta)
		if leg_right:
			leg_right.rotation.x = lerp(leg_right.rotation.x, 0.0, 5.0 * delta)


func _lerp_to_original(delta: float) -> void:
	var speed = 5.0 * delta
	if body_mesh:
		body_mesh.position.y = lerp(body_mesh.position.y, _original_body_pos.y, speed)
	if head_mesh:
		head_mesh.position.y = lerp(head_mesh.position.y, _original_head_pos.y, speed)
		head_mesh.rotation.x = lerp(head_mesh.rotation.x, 0.0, speed)
	if arm_left:
		arm_left.position = arm_left.position.lerp(_original_arm_left_pos, speed)
	if arm_right:
		arm_right.position = arm_right.position.lerp(_original_arm_right_pos, speed)


func play_recoil() -> void:
	current_recoil = recoil_amount
