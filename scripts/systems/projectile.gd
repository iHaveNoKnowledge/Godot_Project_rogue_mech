extends CharacterBody3D

var speed: float = 50.0
var damage: float = 25.0
var damage_type: String = "kinetic"
var lifetime: float = 3.0
var timer: float = 0.0
var trail_timer: float = 0.0
var direction: Vector3 = Vector3.FORWARD
var last_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("projectile")
	velocity = Vector3.ZERO
	last_pos = global_position


func _physics_process(delta: float) -> void:
	timer += delta
	if timer >= lifetime:
		queue_free()
		return

	last_pos = global_position
	move_and_slide()

	_check_enemy_hit()

	trail_timer += delta
	if trail_timer >= 0.02:
		trail_timer = 0.0
		_spawn_trail_segment()

	if is_on_floor() or is_on_wall() or is_on_ceiling():
		EffectManager.spawn_impact(global_position, Vector3.UP)
		queue_free()


func _check_enemy_hit() -> void:
	var space_state = get_viewport().get_world_3d().direct_space_state
	var from = last_pos
	var to = global_position
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 9
	var result = space_state.intersect_ray(query)

	if result:
		var collider = result["collider"]
		var hit_pos = result["position"]
		var hit_part = result.get("collider_shape_name", "")

		if collider.is_in_group("enemy"):
			_hit_enemy(collider, hit_pos, hit_part)
		else:
			EffectManager.spawn_impact(hit_pos, result["normal"])
			queue_free()
	else:
		var enemies = get_tree().get_nodes_in_group("enemy")
		for enemy in enemies:
			if not is_instance_valid(enemy):
				continue
			var enemy_center = enemy.global_position + Vector3(0, 1.5, 0)
			var closest = Geometry3D.get_closest_point_to_segment(enemy_center, from, to)
			var dist = closest.distance_to(enemy_center)
			if dist < 1.2:
				_hit_enemy(enemy, closest, "")
				return


func _hit_enemy(enemy: Node3D, hit_pos: Vector3, _hit_part: String) -> void:
	EffectManager.spawn_impact(hit_pos, Vector3.UP)

	if enemy.has_method("take_damage_at_point"):
		enemy.take_damage_at_point(damage, hit_pos, damage_type)
	elif enemy.has_method("take_damage"):
		enemy.take_damage(damage, damage_type)

	EffectManager.spawn_damage_number(hit_pos + Vector3(0, 1, 0), damage, Color.WHITE)
	queue_free()


func setup(dir: Vector3, spd: float, dmg: float = 25.0, dmg_type: String = "kinetic") -> void:
	speed = spd
	damage = dmg
	damage_type = dmg_type
	direction = dir.normalized()
	velocity = direction * speed


func get_damage() -> float:
	return damage


func _spawn_trail_segment() -> void:
	var trail = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.08, 0.08, 0.4)
	trail.mesh = box

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 0.9, 0.5, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.8, 0.3)
	mat.emission_energy_multiplier = 2.0
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail.material_override = mat

	get_tree().current_scene.add_child(trail)
	trail.global_position = global_position
	trail.look_at(global_position + direction, Vector3.UP)

	var tween = get_tree().create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.15)
	tween.tween_callback(trail.queue_free)
