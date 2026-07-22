extends CharacterBody3D

var speed: float = 50.0
var damage: float = 25.0
var damage_type: String = "kinetic"
var lifetime: float = 3.0
var timer: float = 0.0


func _ready() -> void:
	add_to_group("projectile")
	velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	timer += delta
	if timer >= lifetime:
		queue_free()
		return

	move_and_slide()

	if is_on_floor() or is_on_wall() or is_on_ceiling():
		_spawn_impact()
		queue_free()


func setup(dir: Vector3, spd: float, dmg: float = 25.0, dmg_type: String = "kinetic") -> void:
	speed = spd
	damage = dmg
	damage_type = dmg_type
	velocity = dir * speed


func get_damage() -> float:
	return damage


func _spawn_impact() -> void:
	var normal = Vector3.UP
	if is_on_floor():
		normal = Vector3.UP
	elif is_on_wall():
		normal = get_wall_normal()
	EffectManager.spawn_impact(global_position, normal)
