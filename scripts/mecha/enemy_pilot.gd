extends CharacterBody3D

## A defeated enemy's pilot bailing out of a crippled mech: a small figure in
## the unit's colors that sprints away from the player and despawns once it
## reaches the arena boundary (or after a few seconds), so a mech that lost its
## legs still reads as "the enemy got out and ran".

var _target: Node3D = null
var _run_speed: float = 6.5
var _life: float = 8.0
var _color: Color = Color(0.75, 0.2, 0.2)


func setup(target: Node3D, color: Color) -> void:
	_target = target
	_color = color


func _ready() -> void:
	add_to_group("enemy_pilot")
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(60)

	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.22
	capsule.height = 0.9
	col.shape = capsule
	col.position.y = 0.45
	add_child(col)

	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.9
	body.mesh = mesh
	body.position.y = 0.45
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color
	mat.emission_enabled = true
	mat.emission = _color
	mat.emission_energy_multiplier = 0.6
	body.material_override = mat
	add_child(body)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0 or global_position.distance_to(Vector3.ZERO) > 60.0:
		queue_free()
		return

	var dir := Vector3.ZERO
	if _target != null and is_instance_valid(_target):
		dir = global_position - _target.global_position
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = Vector3(1, 0, 0)
	dir = dir.normalized()

	velocity = dir * _run_speed
	velocity.y -= 20.0 * delta
	move_and_slide()
	if dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 8.0 * delta)
