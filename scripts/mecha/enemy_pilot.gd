extends CharacterBody3D

## A defeated enemy's pilot bailing out of a crippled mech: a small figure in
## the unit's colors that sprints away from the player. The pilot is a real
## target — the player can shoot it down. Its HP pool mirrors the player's
## PilotSystem rule: HP reaching 0 is PERMANENT DEATH (the pilot is gone for
## good), instead of every enemy pilot always getting away.

var _target: Node3D = null
var _run_speed: float = 6.5
var _life: float = 8.0
var _color: Color = Color(0.75, 0.2, 0.2)
var _dead: bool = false

# Enemy pilot HP: a fleeing pilot is fragile but not a one-shot. Uses the same
# "HP 0 = dead forever" rule as the player pilot (PilotSystem), so both sides
# share one permanent-death system.
var hp: float = 40.0
var max_hp: float = 40.0


func setup(target: Node3D, color: Color) -> void:
	_target = target
	_color = color


func _ready() -> void:
	add_to_group("enemy_pilot")
	add_to_group("enemy")
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(60)

	# Hittable like the enemy mechs: layer 8 is the enemy hit layer the player's
	# weapons (ranged aim ray + melee) scan, so the pilot is a real target.
	collision_layer = 8
	collision_mask = 3

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


# Player fire hits the fleeing pilot: HP drops and, at 0, the pilot dies
# permanently (never comes back in the run) instead of always getting away.
func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if _dead or amount <= 0.0:
		return
	hp -= amount
	EffectManager.spawn_damage_number(global_position + Vector3(0, 1.6, 0), amount, Color(1.0, 0.5, 0.2))
	if AudioManager:
		AudioManager.play_impact_by_type(damage_type, global_position)
	if hp <= 0.0:
		_die()


# Permanent death: the pilot collapses (small hit-mark effect) and is gone.
func _die() -> void:
	if _dead:
		return
	_dead = true
	EffectManager.spawn_explosion(global_position + Vector3(0, 0.8, 0))
	queue_free()


func _physics_process(delta: float) -> void:
	if _dead:
		return
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
