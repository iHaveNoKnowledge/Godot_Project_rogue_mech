extends StaticBody3D

## Destructible cover object with HP and visual damage states.

@export var max_hp: float = 200.0
@export var armor_class: float = 1.0
@export var cover_type: String = "barrier"

var current_hp: float
var mesh_ref: MeshInstance3D
var mat_ref: StandardMaterial3D
var _original_color: Color


func _ready() -> void:
	add_to_group("cover")
	collision_layer = 2  # Environment
	collision_mask = 1   # Mecha
	current_hp = max_hp
	_find_mesh()


func _find_mesh() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			mesh_ref = child
			mat_ref = mesh_ref.material_override
			if mat_ref:
				_original_color = mat_ref.albedo_color
			return


func ram_by_mecha(speed: float) -> void:
	var ram_dmg: float = maxf(speed * 12.0, 120.0)
	take_damage(ram_dmg, "ram")


func take_damage(amount: float, _damage_type: String = "kinetic") -> void:
	var reduced = amount / maxf(armor_class, 0.1)
	current_hp -= reduced

	_update_visual()

	if current_hp <= 0.0:
		_destroy()


func _update_visual() -> void:
	if mat_ref == null:
		return

	var hp_ratio = current_hp / max_hp

	if hp_ratio > 0.5:
		# Intact — no visual change
		return
	elif hp_ratio > 0.25:
		# Damaged — darken
		var t = (0.5 - hp_ratio) / 0.25
		mat_ref.albedo_color = _original_color.lerp(Color(0.2, 0.2, 0.2, 1), t)
	else:
		# Critical — very dark + slight red tint
		var t = (0.25 - hp_ratio) / 0.25
		mat_ref.albedo_color = Color(0.15, 0.1, 0.1, 1).lerp(Color(0.4, 0.1, 0.1, 1), t)
		# Emit particles if we have them
		var particles = get_node_or_null("DamageParticles")
		if particles and particles is GPUParticles3D:
			particles.emitting = true


func _destroy() -> void:
	# Spawn debris
	_spawn_debris()

	# Sound
	if AudioManager:
		AudioManager.play_explosion(global_position)

	EventBus.cover_destroyed.emit(global_position, cover_type)
	queue_free()


func _spawn_debris() -> void:
	for i in range(4):
		var debris = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.3, 0.3, 0.3) * randf_range(0.5, 1.5)
		debris.mesh = box

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.3, 0.3, 1)
		debris.material_override = mat

		get_tree().current_scene.add_child(debris)
		debris.global_position = global_position + Vector3(randf_range(-0.5, 0.5), 1.0, randf_range(-0.5, 0.5))

		var velocity = Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-3, 3))
		# Sequential tweens: fly outward first, then drop — parallel mode made both
		# write `position` every frame, so the debris ended up fighting itself.
		var tween = get_tree().create_tween()
		tween.tween_property(debris, "position", debris.position + velocity * 0.5, 0.5).set_ease(Tween.EASE_OUT)
		tween.tween_property(debris, "position:y", debris.position.y - 3.0, 0.5).set_delay(0.2).set_ease(Tween.EASE_IN)
		tween.tween_callback(debris.queue_free).set_delay(0.3)
