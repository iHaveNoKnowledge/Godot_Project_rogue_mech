extends CharacterBody3D

var speed: float = 50.0
var damage: float = 25.0
var damage_type: String = "kinetic"
var lifetime: float = 5.0
var timer: float = 0.0
var trail_timer: float = 0.0
var direction: Vector3 = Vector3.FORWARD


func _ready() -> void:
	add_to_group("projectile")


func _physics_process(delta: float) -> void:
	timer += delta
	if timer >= lifetime:
		queue_free()
		return

	var collision = move_and_collide(velocity * delta)
	if collision:
		var collider = collision.get_collider()
		if collider.is_in_group("enemy"):
			_hit_enemy(collider, collision.get_position())
		else:
			EffectManager.spawn_impact(collision.get_position(), collision.get_normal())
			queue_free()
		return

	_check_enemy_proximity()

	trail_timer += delta
	if trail_timer >= 0.03:
		trail_timer = 0.0
		_spawn_trail()


func _check_enemy_proximity() -> void:
	var enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var dist = global_position.distance_to(enemy.global_position + Vector3(0, 1.5, 0))
		if dist < 1.5:
			_hit_enemy(enemy, global_position)
			return


func _hit_enemy(enemy: Node3D, hit_pos: Vector3) -> void:
	EffectManager.spawn_impact(hit_pos, Vector3.UP)

	if enemy.has_method("take_damage_at_point"):
		enemy.take_damage_at_point(damage, hit_pos, damage_type)
	elif enemy.has_method("take_damage"):
		enemy.take_damage(damage, damage_type)

	EffectManager.spawn_damage_number(hit_pos + Vector3(0, 1.5, 0), damage, Color.WHITE)
	queue_free()


func _spawn_trail() -> void:
	var trail = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.06, 0.06, 0.3)
	trail.mesh = box

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 0.8, 0.3, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.7, 0.2)
	mat.emission_energy_multiplier = 3.0
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail.material_override = mat

	get_tree().current_scene.add_child(trail)
	trail.global_position = global_position
	trail.look_at(global_position + direction, Vector3.UP)

	var tween = get_tree().create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tween.tween_callback(trail.queue_free)
