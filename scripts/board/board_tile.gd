extends StaticBody3D

var grid_pos: Vector2i = Vector2i.ZERO
var tile_type: String = "empty"
var terrain: String = "plain"
var is_highlighted: bool = false
var is_revealed: bool = false
var connections: Array = []

var _reachable_glow: MeshInstance3D = null
var _event_beacon: Node = null
var _enemy_base_model: Node = null


func _ready() -> void:
	add_to_group("board_tile")
	tile_type = get_meta("tile_type", "empty")
	grid_pos = get_meta("grid_pos", Vector2i.ZERO)
	terrain = get_meta("terrain", "plain")
	connections = get_meta("connections", [])

	if tile_type in ["start", "exit", "safehouse", "data_node", "enemy_base", "city", "bait", "fuel_depot", "supply_truck", "wreckage"]:
		is_revealed = true
	_add_terrain_props()
	# Event / data-node tiles are marked by a glowing 3D beacon (a transparent
	# cylinder), not by coloring the floor — the tile itself keeps its terrain
	# color and the beacon hides until the tile is revealed. Bait caches share
	# the beacon so they read as interactable loot (they are decoys).
	if tile_type in ["event", "data_node", "bait"]:
		_event_beacon = _make_beacon()
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
			"fuel_depot":
				color = Color(0.9, 0.55, 0.0) # Amber Fuel Depot
			"supply_truck":
				color = Color(0.3, 0.75, 0.85) # Teal Supply Truck
			"wreckage":
				color = Color(0.55, 0.25, 0.15) # Burnt Orange Wreckage
	else:
		color = color.darkened(0.35)
		color.a = 0.9

	material.albedo_color = color
	material.roughness = 0.85
	mesh_instance.set_surface_override_material(0, material)

	# Content beacons (event / data-node) stay hidden under fog of war and only
	# glow once their tile is explored.
	if _event_beacon != null:
		_event_beacon.visible = is_revealed


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


# ---------------------------------------------------------------------------
# TERRAIN PROPS (trees on forest tiles, buildings on rock tiles, etc.)
# Simple decorative meshes so the board reads as real terrain. Props are pure
# visual (no physics) so they never block movement, clicks, or the hover ray.
# ---------------------------------------------------------------------------

func _add_terrain_props() -> void:
	var prop_node := Node3D.new()
	prop_node.name = "TerrainProps"
	add_child(prop_node)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(grid_pos.x * 73856093) ^ int(grid_pos.y * 19349663)

	match terrain:
		"forest":
			# Deep woods (forest map) grow tall dense trees; a forest tile on a
			# suburb map is just a park cluster, so keep those sparse + short so
			# the suburb board never reads as a jungle.
			var is_woods := GlobalData.board_theme_id == "forest"
			var trunk_h := 1.8 if is_woods else 1.2
			var canopy_r := 2.8 if is_woods else 1.8
			_add_tree(prop_node, rng, trunk_h, canopy_r)
			if rng.randf() < (0.45 if is_woods else 0.22):
				_add_tree(prop_node, rng, 1.2 if is_woods else 0.9, 1.8 if is_woods else 1.3, Vector3(rng.randf_range(-1.3, 1.3), 0, rng.randf_range(-1.3, 1.3)))
		"rock":
			if GlobalData.board_theme_id in ["urban", "suburb"]:
				_add_building(prop_node, rng)
			else:
				_add_boulder(prop_node, rng)
		"plain":
			if rng.randf() < 0.35:
				_add_bush(prop_node, rng)
		"sand":
			if rng.randf() < 0.4:
				_add_boulder(prop_node, rng)
		_:
			pass


func _add_tree(parent: Node3D, rng: RandomNumberGenerator, trunk_h: float, canopy_r: float, offset: Vector3 = Vector3.ZERO) -> void:
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.12
	trunk_mesh.bottom_radius = 0.18
	trunk_mesh.height = trunk_h
	trunk.mesh = trunk_mesh
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.38, 0.26, 0.15)
	trunk_mat.roughness = 1.0
	trunk.material_override = trunk_mat
	trunk.position = offset + Vector3(0, trunk_h * 0.5, 0)
	parent.add_child(trunk)

	var canopy := MeshInstance3D.new()
	var canopy_mesh := CylinderMesh.new()
	canopy_mesh.top_radius = 0.05
	canopy_mesh.bottom_radius = canopy_r
	canopy_mesh.height = canopy_r * 1.6
	canopy.mesh = canopy_mesh
	var leaf_mat := StandardMaterial3D.new()
	var shade := rng.randf_range(-0.08, 0.06)
	leaf_mat.albedo_color = Color(0.14 + shade, 0.34 + shade, 0.15 + shade)
	leaf_mat.roughness = 1.0
	canopy.material_override = leaf_mat
	canopy.position = offset + Vector3(0, trunk_h + canopy_mesh.height * 0.45, 0)
	canopy.rotation.y = rng.randf_range(0.0, TAU)
	parent.add_child(canopy)


func _add_building(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var building := MeshInstance3D.new()
	var body := BoxMesh.new()
	var bw := rng.randf_range(1.8, 2.6)
	var bh := rng.randf_range(2.0, 3.6)
	body.size = Vector3(bw, bh, bw)
	building.mesh = body
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30 + rng.randf_range(-0.05, 0.05), 0.31, 0.36)
	mat.roughness = 0.8
	building.material_override = mat
	building.position = Vector3(0, bh * 0.5, 0)
	parent.add_child(building)

	# Roof slab
	var roof := MeshInstance3D.new()
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(bw + 0.2, 0.12, bw + 0.2)
	roof.mesh = roof_mesh
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.42, 0.43, 0.48)
	roof_mat.roughness = 0.9
	roof.material_override = roof_mat
	roof.position = Vector3(0, bh + 0.06, 0)
	parent.add_child(roof)


func _add_boulder(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var boulder := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var size := rng.randf_range(0.7, 1.4)
	mesh.size = Vector3(size, size * rng.randf_range(0.6, 0.8), size)
	boulder.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.40, 0.38, 0.34)
	mat.roughness = 1.0
	boulder.material_override = mat
	boulder.position = Vector3(rng.randf_range(-1.4, 1.4), mesh.size.y * 0.5, rng.randf_range(-1.4, 1.4))
	boulder.rotation.y = rng.randf_range(0.0, TAU)
	parent.add_child(boulder)


func _add_bush(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var bush := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	var size := rng.randf_range(0.35, 0.6)
	mesh.radius = size
	mesh.height = size * 1.3
	bush.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.40, 0.22)
	mat.roughness = 1.0
	bush.material_override = mat
	bush.position = Vector3(rng.randf_range(-1.5, 1.5), size * 0.55, rng.randf_range(-1.5, 1.5))
	parent.add_child(bush)


func highlight(active: bool) -> void:
	is_highlighted = active
	if active:
		# Reachable tiles get a faint light disc on the ground so the player can
		# see where they may step — dim on purpose, the scene must stay readable.
		_ensure_reachable_glow()
		if _reachable_glow != null:
			_reachable_glow.visible = true
		reveal()
	else:
		if _reachable_glow != null:
			_reachable_glow.visible = false


# Builds the reachable-tile glow disc once, lazily (only tiles that actually get
# highlighted ever allocate one).
func _ensure_reachable_glow() -> void:
	if _reachable_glow != null:
		return
	var glow := MeshInstance3D.new()
	glow.name = "ReachableGlow"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.5
	mesh.bottom_radius = 1.5
	mesh.height = 0.05
	glow.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.45, 0.8, 1.0, 0.16)
	mat.emission_enabled = true
	mat.emission = Color(0.45, 0.8, 1.0)
	mat.emission_energy_multiplier = 0.7
	glow.material_override = mat
	glow.position.y = 0.05
	glow.visible = false
	add_child(glow)
	_reachable_glow = glow


# Event / data-node tiles get a transparent glowing cylinder beacon (TileGlow)
# so interactable content reads as a 3D model on the board, not a floor color.
func _make_beacon() -> Node:
	var beacon := Node3D.new()
	beacon.set_script(preload("res://scripts/board/tile_glow.gd"))
	# Events glow cyan, data terminals glow gold, bait caches glow a warning
	# orange-red so a sprung decoy still reads as a (hostile) landmark.
	if tile_type == "event":
		beacon.setup(Color(0.35, 0.85, 1.0))
	elif tile_type == "bait":
		beacon.setup(Color(1.0, 0.45, 0.15))
	else:
		beacon.setup(Color(1.0, 0.75, 0.2))
	add_child(beacon)
	return beacon


# ---------------------------------------------------------------------------
# ENEMY BASE 3D MODEL — a red structure sitting on the research base tile. A
# freshly planted base is a temporary CAMP (triangular A-frame tent); once its
# research has rooted in (>= half done) it becomes a TALL fortified building.
# Both are built ONLY from angular primitives (prisms / boxes) — never
# cylinders, so the base reads as a solid man-made structure on the map.
# ---------------------------------------------------------------------------

# Replaces the current model with one for the given kind: "camp" (tent) or
# anything else = "rooted" (tall building).
func set_enemy_base_model(kind: String) -> void:
	_clear_enemy_base_model()
	_enemy_base_model = Node3D.new()
	_enemy_base_model.name = "EnemyBaseModel"
	add_child(_enemy_base_model)
	if kind == "camp":
		_build_camp_model(_enemy_base_model)
	else:
		_build_rooted_model(_enemy_base_model)


func clear_enemy_base_model() -> void:
	_clear_enemy_base_model()


func _clear_enemy_base_model() -> void:
	if _enemy_base_model != null:
		_enemy_base_model.queue_free()
		_enemy_base_model = null


func _enemy_base_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	return mat


# Triangular A-frame tent: a prism body + a dark entrance flap.
func _build_camp_model(root: Node3D) -> void:
	var body := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(2.6, 1.5, 2.2)
	prism.left_to_right = 1.0
	body.mesh = prism
	body.material_override = _enemy_base_mat(Color(0.72, 0.17, 0.10))
	body.position = Vector3(0, 0.75, 0)
	root.add_child(body)

	var entrance := MeshInstance3D.new()
	var flap := BoxMesh.new()
	flap.size = Vector3(0.8, 0.95, 0.12)
	entrance.mesh = flap
	entrance.material_override = _enemy_base_mat(Color(0.22, 0.05, 0.05))
	entrance.position = Vector3(0, 0.48, 1.08)
	root.add_child(entrance)


# Tall fortified tower: stacked box floors shrinking upward + roof + antenna.
func _build_rooted_model(root: Node3D) -> void:
	var red := Color(0.8, 0.18, 0.10)
	var dark := Color(0.45, 0.09, 0.07)
	var roof_c := Color(0.55, 0.11, 0.09)
	_add_box(root, Vector3(2.8, 1.5, 2.8), red, 0.75)
	_add_box(root, Vector3(2.2, 1.5, 2.2), red, 2.25)
	_add_box(root, Vector3(1.6, 1.6, 1.6), red, 3.8)
	_add_box(root, Vector3(1.9, 0.2, 1.9), roof_c, 4.65)
	_add_box(root, Vector3(0.12, 1.0, 0.12), dark, 5.25)


func _add_box(root: Node3D, size: Vector3, color: Color, y: float) -> void:
	var box := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	box.mesh = m
	box.material_override = _enemy_base_mat(color)
	box.position = Vector3(0, y, 0)
	root.add_child(box)


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