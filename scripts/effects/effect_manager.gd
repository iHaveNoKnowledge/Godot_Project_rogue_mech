class_name EffectManager
extends Node

static var instance: EffectManager = null


func _ready() -> void:
	instance = self


static func spawn_muzzle_flash(position: Vector3, direction: Vector3) -> void:
	if instance == null:
		return

	var flash = GPUParticles3D.new()
	var mat = ParticleProcessMaterial.new()
	mat.direction = direction
	mat.spread = 30.0
	mat.initial_velocity_min = 15.0
	mat.initial_velocity_max = 25.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.2
	mat.scale_max = 0.5

	flash.process_material = mat
	flash.amount = 6
	flash.lifetime = 0.15
	flash.one_shot = true
	flash.explosiveness = 1.0
	flash.emitting = true

	var mesh_instance = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.1
	mesh_instance.mesh = sphere
	var particle_mat = StandardMaterial3D.new()
	particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mat.albedo_color = Color(1, 0.9, 0.5, 0.8)
	mesh_instance.material_override = particle_mat
	flash.add_child(mesh_instance)

	instance.add_child(flash)
	flash.global_position = position
	flash.look_at(position + direction)

	await instance.get_tree().create_timer(0.3).timeout
	if is_instance_valid(flash):
		flash.queue_free()


static func spawn_impact(position: Vector3, normal: Vector3) -> void:
	if instance == null:
		return

	var impact = GPUParticles3D.new()
	var mat = ParticleProcessMaterial.new()
	mat.direction = normal
	mat.spread = 60.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 8.0
	mat.gravity = Vector3(0, -5, 0)
	mat.scale_min = 0.05
	mat.scale_max = 0.15

	impact.process_material = mat
	impact.amount = 10
	impact.lifetime = 0.4
	impact.one_shot = true
	impact.explosiveness = 0.8
	impact.emitting = true

	var mesh_instance = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.05
	mesh_instance.mesh = sphere
	var particle_mat = StandardMaterial3D.new()
	particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mat.albedo_color = Color(1, 0.7, 0.3, 0.9)
	mesh_instance.material_override = particle_mat
	impact.add_child(mesh_instance)

	instance.add_child(impact)
	impact.global_position = position

	await instance.get_tree().create_timer(0.5).timeout
	if is_instance_valid(impact):
		impact.queue_free()


static func spawn_damage_number(position: Vector3, damage: float, color: Color = Color.WHITE) -> void:
	if instance == null:
		return

	var label = Label3D.new()
	label.text = str(int(damage))
	label.font_size = 32
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = color

	instance.add_child(label)
	label.global_position = position + Vector3(randf_range(-0.5, 0.5), 1.0, 0)

	var tween = instance.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", position.y + 2.5, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


static func spawn_explosion(position: Vector3) -> void:
	if instance == null:
		return

	var explosion = GPUParticles3D.new()
	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 15.0
	mat.gravity = Vector3(0, -3, 0)
	mat.scale_min = 0.3
	mat.scale_max = 0.8

	explosion.process_material = mat
	explosion.amount = 30
	explosion.lifetime = 0.8
	explosion.one_shot = true
	explosion.explosiveness = 0.9
	explosion.emitting = true

	var mesh_instance = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.2
	mesh_instance.mesh = sphere
	var particle_mat = StandardMaterial3D.new()
	particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mat.albedo_color = Color(1, 0.5, 0.1, 1)
	mesh_instance.material_override = particle_mat
	explosion.add_child(mesh_instance)

	instance.add_child(explosion)
	explosion.global_position = position

	await instance.get_tree().create_timer(1.0).timeout
	if is_instance_valid(explosion):
		explosion.queue_free()
