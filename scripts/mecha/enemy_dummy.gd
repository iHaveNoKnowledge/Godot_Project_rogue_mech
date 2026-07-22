extends CharacterBody3D

@export var max_hp: float = 200.0
@export var move_speed: float = 3.0
@export var attack_range: float = 15.0
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 2.0

var current_hp: float
var target: Node3D = null
var attack_timer: float = 0.0
var is_destroyed: bool = false

@onready var mesh: MeshInstance3D = $BodyMesh
var original_color: Color = Color(0.8, 0.2, 0.2, 1)


func _ready() -> void:
	add_to_group("enemy")
	current_hp = max_hp


func _physics_process(delta: float) -> void:
	if is_destroyed:
		return

	_find_target()
	if target:
		_move_toward_target(delta)
		_try_attack(delta)


func _find_target() -> void:
	if target and is_instance_valid(target):
		return
	var mechas = get_tree().get_nodes_in_group("mecha")
	if mechas.size() > 0:
		target = mechas[0]


func _move_toward_target(delta: float) -> void:
	var direction = (target.global_position - global_position).normalized()
	direction.y = 0.0
	velocity = direction * move_speed
	velocity.y = -10.0
	move_and_slide()

	if direction.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 5.0 * delta)


func _try_attack(delta: float) -> void:
	attack_timer -= delta
	if attack_timer > 0.0:
		return

	var distance = global_position.distance_to(target.global_position)
	if distance <= attack_range:
		attack_timer = attack_cooldown
		if target.has_method("take_damage"):
			target.take_damage(attack_damage, "melee")


func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if is_destroyed:
		return

	current_hp -= amount
	_update_visual()

	if current_hp <= 0.0:
		_on_destroyed()


func _update_visual() -> void:
	if mesh and mesh.material_override:
		var damage_ratio = 1.0 - (current_hp / max_hp)
		mesh.material_override.albedo_color = original_color.lerp(Color(0.3, 0.3, 0.3, 1), damage_ratio)


func _on_destroyed() -> void:
	is_destroyed = true
	velocity = Vector3.ZERO
	if mesh and mesh.material_override:
		mesh.material_override.albedo_color = Color(0.2, 0.2, 0.2, 1)
	set_physics_process(false)
	await get_tree().create_timer(2.0).timeout
	queue_free()
