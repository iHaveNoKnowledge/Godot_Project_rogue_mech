extends StaticBody3D

var grid_pos: Vector2i = Vector2i.ZERO
var tile_type: String = "empty"
var is_highlighted: bool = false
var is_revealed: bool = false
var connections: Array = []


func _ready() -> void:
	add_to_group("board_tile")
	tile_type = get_meta("tile_type", "empty")
	grid_pos = get_meta("grid_pos", Vector2i.ZERO)
	connections = get_meta("connections", [])
	
	if tile_type in ["start", "exit", "safehouse", "data_node", "enemy_base"]:
		is_revealed = true
	_update_visual()


func create_path_visuals(nodes_dict: Dictionary) -> void:
	for target_key in connections:
		if not nodes_dict.has(target_key):
			continue
		var target_tile: Node3D = nodes_dict[target_key]
		var start_pos = global_position
		var end_pos = target_tile.global_position
		
		_spawn_path_bridge(start_pos, end_pos)


func _spawn_path_bridge(from_pos: Vector3, to_pos: Vector3) -> void:
	var mid_pos = (from_pos + to_pos) / 2.0
	var distance = from_pos.distance_to(to_pos)
	
	var path_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.15, 0.05, distance)
	path_mesh.mesh = box

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 0.9, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.4, 0.8)
	mat.emission_energy_multiplier = 1.0
	path_mesh.material_override = mat

	get_parent().add_child(path_mesh)
	path_mesh.global_position = mid_pos
	path_mesh.look_at(to_pos, Vector3.UP)


func reveal() -> void:
	is_revealed = true
	_update_visual()


func _update_visual() -> void:
	var mesh_instance = get_node_or_null("MeshInstance3D")
	if mesh_instance == null:
		return
	var material = StandardMaterial3D.new()

	if tile_type == "dead_end" and not is_revealed:
		material.albedo_color = Color(0.4, 0.4, 0.45)
		mesh_instance.set_surface_override_material(0, material)
		return

	match tile_type:
		"start":
			material.albedo_color = Color(0.2, 0.7, 0.9) # Cyan Practice Hangar
		"exit":
			material.albedo_color = Color(0.8, 0.2, 0.8) # Magenta Boss Extraction
		"combat":
			material.albedo_color = Color(0.8, 0.2, 0.2) # Red Combat
		"event":
			material.albedo_color = Color(0.2, 0.6, 0.8) # Blue Narrative Event
		"safehouse":
			material.albedo_color = Color(0.2, 0.8, 0.2) # Green Safehouse
		"data_node":
			material.albedo_color = Color(0.9, 0.8, 0.1) # Gold Data Terminal
		"enemy_base":
			material.albedo_color = Color(0.9, 0.2, 0.1) # Burning Red Research Base
		"dead_end":
			material.albedo_color = Color(0.15, 0.15, 0.2) # Dark Obstacle Wall
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
		reveal()
	else:
		mesh_instance.position.y = 0.0


func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var board_manager = get_tree().current_scene
		if board_manager and board_manager.has_method("move_to_tile"):
			board_manager.move_to_tile(grid_pos)
