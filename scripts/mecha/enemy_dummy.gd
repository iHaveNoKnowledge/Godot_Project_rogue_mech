extends CharacterBody3D

@export var move_speed: float = 3.0
@export var attack_range: float = 15.0
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 2.0

var target: Node3D = null
var attack_timer: float = 0.0

@onready var health_system: Node = $HealthSystem
@onready var body_mesh: MeshInstance3D = $BodyMesh


func _ready() -> void:
	add_to_group("enemy")
	_setup_enemy_status()


func _setup_enemy_status() -> void:
	var status = get_node_or_null("EnemyStatus")
	if status:
		status.setup_target(self)


func _physics_process(delta: float) -> void:
	if health_system.is_destroyed:
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
	if health_system:
		health_system.take_damage(amount, damage_type)
