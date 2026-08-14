extends StaticBody3D

var grid_pos: Vector2i = Vector2i.ZERO
var tile_type: String = "empty"
var terrain: String = "plain"
var is_highlighted: bool = false
var is_revealed: bool = false
var connections: Array = []


func _ready() -> void:
	add_to_group("board_tile")
	tile_type = get_meta("tile_type", "empty")
	grid_pos = get_meta("grid_pos", Vector2i.ZERO)
	terrain = get_meta("terrain", "plain")
	connections = get_meta("connections", [])

	if tile_type in ["start", "exit", "safehouse", "data_node", "enemy_base", "city"]:
		is_revealed = true
	_update_visual()


func create_path_visuals(_nodes_dict: Dictionary) -> void:
	# Free-movement grid: no bridges between nodes; adjacencies are implicit.
	pass


func reveal() -> void:
	is_revealed = true
	_update_visual()


func _update_visual() -> void:
	var mesh_instance = get_node_or_null("MeshInstance3D")
	if mesh_instance == null:
		return
	var material = StandardMaterial3D.new()

	# Fog of war: unexplored tiles still show their TERRAIN dimmed so the map
	# reads as the theme/area it is (suburb, desert, forest...) — only the
	# content markers (start/exit/hubs/combat) stay hidden until explored.
	var color := _terrain_color(terrain)
	if is_revealed:
		# Explored tiles trade visual priority with terrain: the objective/hub
		# tiles keep their signature colors; ordinary tiles show their terrain.
		match tile_type:
			"start":
				color = Color(0.2, 0.7, 0.9) # Cyan Practice Hangar
			"exit":
				color = Color(0.8, 0.2, 0.8) # Magenta Boss Extraction
			"enemy_base":
				color = Color(0.9, 0.2, 0.1) # Burning Red Research Base
			"safehouse":
				color = Color(0.2, 0.8, 0.2) # Green Safehouse
			"city":
				color = Color(0.95, 0.6, 0.2) # Orange Trading City
			"data_node":
				color = Color(0.9, 0.8, 0.1) # Gold Data Terminal
		if tile_type == "combat":
			material.emission_enabled = true
			material.emission = Color(0.8, 0.1, 0.1)
			material.emission_energy_multiplier = 0.7
	else:
		color = color.darkened(0.35)
		color.a = 0.9

	material.albedo_color = color
	material.roughness = 0.85
	mesh_instance.set_surface_override_material(0, material)


func _terrain_color(t: String) -> Color:
	match t:
		"road":
			return Color(0.28, 0.29, 0.31) # Asphalt
		"plain":
			return Color(0.45, 0.55, 0.35) # Suburban field / desert scrub
		"sand":
			return Color(0.78, 0.68, 0.42) # Sand dune
		"forest":
			return Color(0.22, 0.42, 0.24) # Dense woods
		"water":
			return Color(0.15, 0.45, 0.75) # River / water
		"bridge":
			return Color(0.45, 0.35, 0.25) # Wood / steel crossing
		"rock":
			return Color(0.35, 0.33, 0.30) # Building / boulder
	return Color(0.5, 0.5, 0.5)


func highlight(active: bool) -> void:
	is_highlighted = active
	var mesh_instance = get_node_or_null("MeshInstance3D")
	if mesh_instance == null:
		return
	if active:
		mesh_instance.position.y = 0.04
		reveal()
	else:
		mesh_instance.position.y = 0.0


func set_hover(hovered: bool) -> void:
	var mesh_instance = get_node_or_null("MeshInstance3D")
	if mesh_instance == null:
		return
	if hovered:
		mesh_instance.position.y = 0.08
	else:
		mesh_instance.position.y = 0.02 if is_highlighted else 0.0


func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var board_manager = get_tree().current_scene
		if board_manager and board_manager.has_method("move_to_tile"):
			board_manager.move_to_tile(grid_pos)