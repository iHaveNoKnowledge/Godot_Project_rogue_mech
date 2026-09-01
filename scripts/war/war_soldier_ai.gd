extends Node
## Simple wander guard for barracks personnel — patrols around barracks

var soldier: CharacterBody3D = null
var center: Vector3 = Vector3.ZERO
var target: Vector3 = Vector3.ZERO
var speed: float = 1.8
var _timer: float = 0.0
var _pick_interval: float = 3.5

func _ready() -> void:
	soldier = get_parent() as CharacterBody3D
	if soldier:
		center = soldier.global_position
		_pick_new_target()
	set_physics_process(true)

func _pick_new_target() -> void:
	var ang := randf_range(0, TAU)
	var dist := randf_range(2.0, 6.0)
	target = center + Vector3(cos(ang) * dist, 0, sin(ang) * dist)
	target.y = soldier.global_position.y if soldier else target.y
	_timer = 0.0
	_pick_interval = randf_range(2.5, 5.0)

func _physics_process(delta: float) -> void:
	if soldier == null or not is_instance_valid(soldier):
		queue_free()
		return
	_timer += delta
	if _timer > _pick_interval or soldier.global_position.distance_to(target) < 0.6:
		_pick_new_target()
	var dir := (target - soldier.global_position)
	dir.y = 0
	if dir.length() < 0.1:
		return
	dir = dir.normalized()
	soldier.velocity.x = dir.x * speed
	soldier.velocity.z = dir.z * speed
	soldier.velocity.y = -1.0
	soldier.move_and_slide()
	if dir.length() > 0.01:
		soldier.rotation.y = lerp_angle(soldier.rotation.y, atan2(dir.x, dir.z), 5.0 * delta)
