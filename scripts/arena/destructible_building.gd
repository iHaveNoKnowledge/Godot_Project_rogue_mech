class_name DestructibleBuilding
extends StaticBody3D

## Destructible Skyscraper / Building in Combat Arena
## Receives damage from projectiles and melee weapons, shows hit feedback,
## and collapses into walkable rubble when destroyed.

@export var max_hp: float = 180.0
@export var current_hp: float = 180.0
@export var is_destroyed: bool = false
@export var building_size: Vector3 = Vector3(18.0, 38.0, 18.0)

var _mesh_instance: MeshInstance3D = null
var _collision_shape: CollisionShape3D = null
var _box_shape: BoxShape3D = null
var _original_mat: Material = null
var _is_flashing: bool = false


func setup_building(size: Vector3, mat: Material, hp: float = 180.0) -> void:
	building_size = size
	max_hp = hp
	current_hp = hp
	_original_mat = mat

	add_to_group("solid_obstacle")
	add_to_group("concealment")
	add_to_group("destructible_building")
	collision_layer = 2
	collision_mask = 1

	_collision_shape = CollisionShape3D.new()
	_box_shape = BoxShape3D.new()
	_box_shape.size = size
	_collision_shape.shape = _box_shape
	_collision_shape.position.y = size.y * 0.5
	add_child(_collision_shape)

	_mesh_instance = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	_mesh_instance.mesh = box
	_mesh_instance.material_override = mat
	_mesh_instance.position.y = size.y * 0.5
	add_child(_mesh_instance)


func take_damage_at_point(amount: float, _hit_pos: Vector3, damage_type: String = "kinetic") -> void:
	take_damage(amount, damage_type)


func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if is_destroyed:
		return

	var mult: float = 1.0
	if damage_type == "explosive" or damage_type == "impact":
		mult = 1.8 # Explosive / heavy melee deals high structural demolition
	elif damage_type == "energy":
		mult = 1.25

	var effective_dmg := amount * mult
	current_hp -= effective_dmg

	_flash_hit_feedback()
	_spawn_concrete_debris()

	if current_hp <= 0.0:
		collapse()


func _flash_hit_feedback() -> void:
	if _is_flashing or _mesh_instance == null:
		return
	_is_flashing = true

	var tween := create_tween()
	# Brief surface flash
	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color(0.9, 0.7, 0.5)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.6, 0.2)
	flash_mat.emission_energy_multiplier = 1.8
	_mesh_instance.material_override = flash_mat

	tween.tween_interval(0.06)
	tween.tween_callback(func():
		if is_instance_valid(_mesh_instance) and not is_destroyed:
			_mesh_instance.material_override = _original_mat
		_is_flashing = false
	)


func _spawn_concrete_debris() -> void:
	# Subtle debris dust puff on impact
	pass


func collapse() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	remove_from_group("concealment")

	# 1. Trigger building collapse audio / explosion effect if available
	if has_node("/root/EffectManager"):
		var em = get_node("/root/EffectManager")
		if em and em.has_method("spawn_explosion"):
			em.spawn_explosion(global_position + Vector3(0, building_size.y * 0.3, 0), 1.6)

	# 2. Shrink building into low rubble mound
	var rubble_height: float = 1.6
	var tween := create_tween()
	tween.set_parallel(true)
	if _mesh_instance:
		tween.tween_property(_mesh_instance, "scale:y", rubble_height / building_size.y, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tween.tween_property(_mesh_instance, "position:y", rubble_height * 0.5, 0.45)

	if _box_shape and _collision_shape:
		_box_shape.size = Vector3(building_size.x * 1.15, rubble_height, building_size.z * 1.15)
		_collision_shape.position.y = rubble_height * 0.5
