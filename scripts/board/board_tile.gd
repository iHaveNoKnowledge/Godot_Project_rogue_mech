extends StaticBody3D

var grid_pos: Vector2i = Vector2i.ZERO
var tile_type: String = "empty"
var is_highlighted: bool = false


func _ready() -> void:
	add_to_group("board_tile")
	tile_type = get_meta("tile_type", "empty")
	grid_pos = get_meta("grid_pos", Vector2i.ZERO)
	_update_visual()


func _update_visual() -> void:
	var mesh_instance = get_node_or_null("MeshInstance3D")
	if mesh_instance == null:
		return
	var material = StandardMaterial3D.new()
	match tile_type:
		"combat":
			material.albedo_color = Color(0.8, 0.2, 0.2)
		"event":
			material.albedo_color = Color(0.2, 0.6, 0.8)
		"safehouse":
			material.albedo_color = Color(0.2, 0.8, 0.2)
		_:
			material.albedo_color = Color(0.5, 0.5, 0.5)
	mesh_instance.set_surface_override_material(0, material)


func highlight(active: bool) -> void:
	is_highlighted = active
	var mesh_instance = get_node_or_null("MeshInstance3D")
	if mesh_instance == null:
		return
	if active:
		mesh_instance.position.y = 0.1
	else:
		mesh_instance.position.y = 0.0


func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var board_manager = get_tree().current_scene
		if board_manager and board_manager.has_method("move_to_tile"):
			board_manager.move_to_tile(grid_pos)
