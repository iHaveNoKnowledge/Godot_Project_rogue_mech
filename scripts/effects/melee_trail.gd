extends Node3D

@export var trail_length: float = 1.5
@export var trail_width: float = 0.3
@export var trail_color: Color = Color(0.8, 0.9, 1.0, 0.8)

var mesh_instance: MeshInstance3D
var material: StandardMaterial3D
var timer: float = 0.0


func _ready() -> void:
	mesh_instance = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(trail_width, trail_length, 0.05)
	mesh_instance.mesh = box

	material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = trail_color
	material.emission_enabled = true
	material.emission = trail_color
	material.emission_energy_multiplier = 2.0
	material.no_depth_test = true
	mesh_instance.material_override = material

	add_child(mesh_instance)


func _process(delta: float) -> void:
	timer += delta
	var alpha = 1.0 - (timer / 0.3)
	if alpha <= 0.0:
		queue_free()
		return
	material.albedo_color.a = alpha
	material.emission_energy_multiplier = alpha * 2.0


func setup(direction: Vector3) -> void:
	look_at(global_position + direction, Vector3.UP)
	rotate_object_local(Vector3.FORWARD, deg_to_rad(90))
