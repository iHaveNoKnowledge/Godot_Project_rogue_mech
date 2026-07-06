extends CharacterBody3D

var speed: float = 50.0
var lifetime: float = 3.0
var timer: float = 0.0


func _ready() -> void:
	add_to_group("projectile")
	# Disable gravity-like behavior, just go straight
	velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	timer += delta
	if timer >= lifetime:
		queue_free()
		return
	move_and_slide()


func setup(dir: Vector3, spd: float) -> void:
	speed = spd
	velocity = dir * speed
