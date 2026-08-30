extends StaticBody3D

var grid_pos: Vector2i = Vector2i.ZERO
var tile_type: String = "empty"
var terrain: String = "plain"
var sub_zone: String = ""
var is_highlighted: bool = false
var is_revealed: bool = false
var connections: Array = []

var _reachable_glow: MeshInstance3D = null
var _event_beacon: Node = null
var _enemy_base_model: Node = null
var _poi_node: Node3D = null
var _fog_mesh: MeshInstance3D = null

## Per-terrain ground texture packs (CC0 from ambientCG), keyed by terrain name.
const TEXTURE_ROOT := "res://resources/textures/"
static var _texture_cache: Dictionary = {}
static var _terrain_shader: Shader = preload("res://shaders/board_terrain_tile.gdshader")
static var _fog_shader: Shader = preload("res://shaders/board_fog_of_war.gdshader")


func _ready() -> void:
	add_to_group("board_tile")
	tile_type = get_meta("tile_type", "empty")
	grid_pos = get_meta("grid_pos", Vector2i.ZERO)
	terrain = get_meta("terrain", "plain")
	sub_zone = get_meta("sub_zone", "")
	connections = get_meta("connections", [])

	# Start and exit tiles are always revealed; all other tiles start shrouded in Fog of War.
	if tile_type in ["start", "exit"]:
		is_revealed = true
	else:
		is_revealed = false

	_add_terrain_props()
	_add_poi_visual()
	if tile_type in ["event", "data_node", "bait", "unknown_signal"]:
		_event_beacon = _make_beacon()

	if not is_revealed:
		_create_fog_mesh()

	_update_visual()


func create_path_visuals(_nodes_dict: Dictionary) -> void:
	# Free-movement grid: no bridges between nodes; adjacencies are implicit.
	pass


func reveal(animated: bool = true) -> void:
	if is_revealed:
		return
	is_revealed = true
	if _fog_mesh != null and is_instance_valid(_fog_mesh):
		if animated:
			var mat = _fog_mesh.get_surface_override_material(0)
			if mat is ShaderMaterial:
				var fog_id := _fog_mesh.get_instance_id() if _fog_mesh else 0
				var tween := create_tween()
				tween.tween_property(mat, "shader_parameter/dissolve_progress", 1.0, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tween.tween_callback(func():
					# Use id to avoid freed lambda capture if tile was freed/reused
					var fog = instance_from_id(fog_id) if fog_id != 0 else null
					if is_instance_valid(fog):
						fog.queue_free()
					if is_instance_valid(self) and _fog_mesh == fog:
						_fog_mesh = null
					elif fog_id != 0:
						var self_fog = _fog_mesh
						if is_instance_valid(self_fog) and self_fog.get_instance_id() == fog_id:
							_fog_mesh = null
				)
			else:
				_fog_mesh.queue_free()
				_fog_mesh = null
		else:
			_fog_mesh.queue_free()
			_fog_mesh = null

	_update_visual()

	# Pop-in revealed POI/beacons
	if animated:
		if _poi_node:
			_poi_node.scale = Vector3.ZERO
			_poi_node.visible = true
			var t := create_tween()
			t.tween_property(_poi_node, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if _event_beacon:
			_event_beacon.scale = Vector3.ZERO
			_event_beacon.visible = true
			var t := create_tween()
			t.tween_property(_event_beacon, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _create_fog_mesh() -> void:
	if _fog_mesh != null:
		return
	_fog_mesh = MeshInstance3D.new()
	_fog_mesh.name = "FogOfWarMesh"
	
	# Subdivided organic mist canopy that overlaps seamlessly with zero grid seams.
	# FIX 2026-08 desert: previous 7.6 plane with radial fade 1.8→3.8 left a soft
	# transparent gap at tile diagonals (2.83m from center → 0.49 alpha), which on
	# bright desert sand (0.80,0.70,0.46) read as “fog missing”. Enlarged to 8.4
	# (half 4.2) so even diagonal midpoint (2.83) stays inside the opaque core.
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.4, 8.4)
	plane.subdivide_width = 16
	plane.subdivide_depth = 16
	_fog_mesh.mesh = plane

	var smat := ShaderMaterial.new()
	smat.shader = _fog_shader
	smat.set_shader_parameter("fog_color", Color(0.07, 0.10, 0.15, 0.98))
	smat.set_shader_parameter("fog_edge_color", Color(0.20, 0.30, 0.44, 0.92))
	smat.set_shader_parameter("dissolve_burn_color", Color(0.30, 0.85, 1.0, 1.0))
	smat.set_shader_parameter("dissolve_progress", 0.0)
	smat.set_shader_parameter("animation_speed", 0.35)
	smat.set_shader_parameter("noise_scale", 3.8)
	_fog_mesh.set_surface_override_material(0, smat)
	_fog_mesh.position = Vector3(0, 0.92, 0)
	add_child(_fog_mesh)


func _update_visual() -> void:
	var mesh_instance = get_node_or_null("MeshInstance3D")
	if mesh_instance == null:
		return

	# Apply the custom organic terrain blending shader (no more sharp square cut lines)
	var smat := ShaderMaterial.new()
	smat.shader = _terrain_shader

	var color := _terrain_color(terrain)
	smat.set_shader_parameter("base_color", color)
	smat.set_shader_parameter("edge_feather", 0.38)
	smat.set_shader_parameter("noise_blend_strength", 0.72)
	smat.set_shader_parameter("highlight_intensity", 1.0 if is_highlighted else 0.0)
	smat.set_shader_parameter("highlight_color", Color(0.25, 0.75, 1.0, 1.0))

	var albedo_tex := _cached_texture(terrain, "albedo")
	var normal_tex := _cached_texture(terrain, "normal")
	var roughness_tex := _cached_texture(terrain, "roughness")

	smat.set_shader_parameter("has_albedo_tex", albedo_tex != null)
	if albedo_tex != null:
		smat.set_shader_parameter("albedo_tex", albedo_tex)

	smat.set_shader_parameter("has_normal_tex", normal_tex != null)
	if normal_tex != null:
		smat.set_shader_parameter("normal_tex", normal_tex)

	smat.set_shader_parameter("has_roughness_tex", roughness_tex != null)
	if roughness_tex != null:
		smat.set_shader_parameter("roughness_tex", roughness_tex)

	smat.set_shader_parameter("roughness_scale", 0.85)
	smat.set_shader_parameter("uv_scale", 2.0)

	# Outer table fade — make the 25×25 grid read as an irregular island, not a hard square.
	var grid_s: int = BoardConfig.GRID_SIZE
	var board_center := Vector3(grid_s * 2.0, 0.0, grid_s * 2.0)
	smat.set_shader_parameter("use_board_fade", true)
	smat.set_shader_parameter("board_center", board_center)
	smat.set_shader_parameter("board_half_size", grid_s * 2.0)
	smat.set_shader_parameter("board_fade_width", 6.0)

	mesh_instance.set_surface_override_material(0, smat)

	# Content POI models and beacons stay hidden under fog of war until revealed.
	if _poi_node != null:
		_poi_node.visible = is_revealed
	if _event_beacon != null:
		_event_beacon.visible = is_revealed
	if _enemy_base_model != null:
		_enemy_base_model.visible = is_revealed


func _terrain_color(t: String) -> Color:
	var theme_id := str(GlobalData.board.board_theme_id)
	return BoardConfig.terrain_color(t, theme_id)


static func _cached_texture(terrain_name: String, kind: String) -> Texture2D:
	var key := "%s/%s" % [terrain_name, kind]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var path := TEXTURE_ROOT + terrain_name + "/" + kind + ".jpg"
	var tex: Texture2D = null
	if ResourceLoader.exists(path, "Texture2D"):
		tex = load(path)
	_texture_cache[key] = tex
	return tex


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

	# --- Sub-Zone Special Prop Overrides ---
	if sub_zone == "suburb_village":
		if terrain == "rock" or (terrain == "plain" and rng.randf() < 0.45):
			_add_suburban_house(prop_node, rng)
			return
		elif terrain == "road" and rng.randf() < 0.3:
			_add_streetlight(prop_node, rng)
	elif sub_zone == "suburb_meadow":
		if terrain == "plain":
			if rng.randf() < 0.6:
				_add_flower_cluster(prop_node, rng)
			elif rng.randf() < 0.3:
				_add_bush(prop_node, rng)
			return
	elif sub_zone == "suburb_water":
		if terrain == "water" or terrain == "plain":
			if rng.randf() < 0.5:
				_add_reeds(prop_node, rng)
				return
	elif sub_zone == "urban_industrial":
		if terrain == "rock" or (terrain == "plain" and rng.randf() < 0.4):
			_add_industrial_silo(prop_node, rng)
			return
	elif sub_zone == "urban_park":
		if terrain == "plain":
			if rng.randf() < 0.5:
				_add_tree(prop_node, rng, 1.4, 2.0)
				return
	elif sub_zone == "desert_oasis":
		if terrain == "plain" or terrain == "water":
			if rng.randf() < 0.5:
				_add_palm_tree(prop_node, rng)
				return
	elif sub_zone == "desert_canyon":
		if terrain == "rock" or terrain == "sand":
			if rng.randf() < 0.5:
				_add_canyon_spire(prop_node, rng)
				return
	elif sub_zone == "forest_ruins":
		if terrain == "rock" or (terrain == "plain" and rng.randf() < 0.4):
			_add_ruin_pillar(prop_node, rng)
			return

	# --- Default Theme / Terrain Props ---
	match terrain:
		"forest":
			var is_woods := GlobalData.board.board_theme_id == "forest"
			var trunk_h := 1.8 if is_woods else 1.2
			var canopy_r := 2.8 if is_woods else 1.8
			_add_tree(prop_node, rng, trunk_h, canopy_r)
			if rng.randf() < (0.45 if is_woods else 0.22):
				_add_tree(prop_node, rng, 1.2 if is_woods else 0.9, 1.8 if is_woods else 1.3, Vector3(rng.randf_range(-1.3, 1.3), 0, rng.randf_range(-1.3, 1.3)))
		"rock":
			if GlobalData.board.board_theme_id in ["urban", "suburb"]:
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
	var b_root := Node3D.new()
	# Position near the corner edge so the tile center remains open for player token
	b_root.position = Vector3(1.1, 0, -1.1)

	var building := MeshInstance3D.new()
	var body := BoxMesh.new()
	var bw := rng.randf_range(1.2, 1.6)
	var bh := rng.randf_range(1.6, 2.6)
	body.size = Vector3(bw, bh, bw)
	building.mesh = body
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30 + rng.randf_range(-0.05, 0.05), 0.31, 0.36)
	mat.roughness = 0.8
	building.material_override = mat
	building.position = Vector3(0, bh * 0.5, 0)
	b_root.add_child(building)

	# Roof slab
	var roof := MeshInstance3D.new()
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(bw + 0.15, 0.1, bw + 0.15)
	roof.mesh = roof_mesh
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.42, 0.43, 0.48)
	roof_mat.roughness = 0.9
	roof.material_override = roof_mat
	roof.position = Vector3(0, bh + 0.05, 0)
	b_root.add_child(roof)

	parent.add_child(b_root)


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


func _add_suburban_house(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var house := Node3D.new()
	var hw := rng.randf_range(1.0, 1.3)
	var hh := rng.randf_range(0.8, 1.1)
	var hd := rng.randf_range(1.1, 1.4)

	var base_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(hw, hh, hd)
	base_mesh.mesh = box
	var b_mat := StandardMaterial3D.new()
	b_mat.albedo_color = Color(0.72 + rng.randf_range(-0.05, 0.05), 0.70, 0.64)
	b_mat.roughness = 0.8
	base_mesh.material_override = b_mat
	base_mesh.position = Vector3(0, hh * 0.5, 0)
	house.add_child(base_mesh)

	# Gabled roof
	var roof := MeshInstance3D.new()
	var r_mesh := PrismMesh.new()
	r_mesh.size = Vector3(hw + 0.2, 0.55, hd + 0.15)
	roof.mesh = r_mesh
	var r_mat := StandardMaterial3D.new()
	r_mat.albedo_color = Color(0.55 + rng.randf_range(-0.1, 0.1), 0.22, 0.18)
	r_mat.roughness = 0.7
	roof.material_override = r_mat
	roof.position = Vector3(0, hh + 0.28, 0)
	house.add_child(roof)

	# Position near the corner edge of tile
	house.position = Vector3(1.1, 0, -1.1)
	house.rotation.y = rng.randf_range(0.0, TAU)
	parent.add_child(house)


func _add_streetlight(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var pole := MeshInstance3D.new()
	var p_mesh := CylinderMesh.new()
	p_mesh.top_radius = 0.04
	p_mesh.bottom_radius = 0.05
	p_mesh.height = 1.8
	pole.mesh = p_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.22, 0.25)
	mat.metallic = 0.8
	mat.roughness = 0.3
	pole.material_override = mat
	pole.position = Vector3(rng.randf_range(-1.2, 1.2), 0.9, rng.randf_range(-1.2, 1.2))
	parent.add_child(pole)


func _add_flower_cluster(parent: Node3D, rng: RandomNumberGenerator) -> void:
	for i in range(rng.randi_range(2, 4)):
		var flower := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = rng.randf_range(0.12, 0.22)
		mesh.height = mesh.radius * 1.5
		flower.mesh = mesh
		var mat := StandardMaterial3D.new()
		var flower_colors := [Color(0.85, 0.75, 0.2), Color(0.8, 0.3, 0.3), Color(0.7, 0.4, 0.8), Color(0.9, 0.9, 0.95)]
		mat.albedo_color = flower_colors[rng.randi() % flower_colors.size()]
		mat.roughness = 0.8
		flower.material_override = mat
		flower.position = Vector3(rng.randf_range(-1.4, 1.4), mesh.height * 0.5, rng.randf_range(-1.4, 1.4))
		parent.add_child(flower)


func _add_reeds(parent: Node3D, rng: RandomNumberGenerator) -> void:
	for i in range(rng.randi_range(3, 5)):
		var reed := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.02
		mesh.bottom_radius = 0.04
		mesh.height = rng.randf_range(0.8, 1.4)
		reed.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.32, 0.45, 0.20)
		mat.roughness = 0.9
		reed.material_override = mat
		reed.position = Vector3(rng.randf_range(-1.4, 1.4), mesh.height * 0.5, rng.randf_range(-1.4, 1.4))
		reed.rotation.z = deg_to_rad(rng.randf_range(-8.0, 8.0))
		parent.add_child(reed)


func _add_industrial_silo(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var silo := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.6
	mesh.bottom_radius = 0.6
	mesh.height = rng.randf_range(1.8, 2.6)
	silo.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.52, 0.55)
	mat.metallic = 0.6
	mat.roughness = 0.4
	silo.material_override = mat
	silo.position = Vector3(rng.randf_range(-0.8, 0.8), mesh.height * 0.5, rng.randf_range(-0.8, 0.8))
	parent.add_child(silo)


func _add_palm_tree(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var palm := Node3D.new()
	var trunk := MeshInstance3D.new()
	var t_mesh := CylinderMesh.new()
	t_mesh.top_radius = 0.08
	t_mesh.bottom_radius = 0.14
	t_mesh.height = 1.6
	trunk.mesh = t_mesh
	var t_mat := StandardMaterial3D.new()
	t_mat.albedo_color = Color(0.42, 0.32, 0.20)
	t_mat.roughness = 0.9
	trunk.material_override = t_mat
	trunk.position = Vector3(0, 0.8, 0)
	palm.add_child(trunk)

	var fronds := MeshInstance3D.new()
	var f_mesh := SphereMesh.new()
	f_mesh.radius = 1.1
	f_mesh.height = 0.4
	fronds.mesh = f_mesh
	var f_mat := StandardMaterial3D.new()
	f_mat.albedo_color = Color(0.22, 0.48, 0.18)
	f_mat.roughness = 0.8
	fronds.material_override = f_mat
	fronds.position = Vector3(0, 1.6, 0)
	palm.add_child(fronds)

	palm.position = Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0))
	parent.add_child(palm)


func _add_canyon_spire(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var spire := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = rng.randf_range(0.2, 0.4)
	mesh.bottom_radius = rng.randf_range(0.6, 1.0)
	mesh.height = rng.randf_range(1.8, 3.2)
	spire.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.60, 0.42, 0.28)
	mat.roughness = 0.95
	spire.material_override = mat
	spire.position = Vector3(rng.randf_range(-0.8, 0.8), mesh.height * 0.5, rng.randf_range(-0.8, 0.8))
	spire.rotation.y = rng.randf_range(0.0, TAU)
	parent.add_child(spire)


func _add_ruin_pillar(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var pillar := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.6, rng.randf_range(1.4, 2.2), 0.6)
	pillar.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.40, 0.36)
	mat.roughness = 0.9
	pillar.material_override = mat
	pillar.position = Vector3(rng.randf_range(-1.0, 1.0), mesh.size.y * 0.5, rng.randf_range(-1.0, 1.0))
	pillar.rotation.z = deg_to_rad(rng.randf_range(-12.0, 12.0))
	parent.add_child(pillar)


# ---------------------------------------------------------------------------
# PROCEDURAL 3D POI MODELS & FLOATING TACTICAL BADGES
# Replaces floor tile coloring with distinctive 3D landmarks and readable
# floating billboard badges so players can instantly identify landmarks easily.
# ---------------------------------------------------------------------------

func _poi_mat(color: Color, roughness: float = 0.7, emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	return mat


func _add_floating_badge(parent: Node3D, text: String, color: Color, height: float = 2.4, offset_xz: Vector2 = Vector2.ZERO) -> void:
	var lbl := Label3D.new()
	lbl.name = "TacticalBadge"
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.pixel_size = 0.01
	lbl.font_size = 32
	lbl.outline_size = 10
	lbl.outline_modulate = Color(0.02, 0.03, 0.06, 0.98)
	lbl.modulate = color
	lbl.position = Vector3(offset_xz.x, height, offset_xz.y)
	parent.add_child(lbl)


func _add_poi_visual() -> void:
	if tile_type in ["empty", "road", "plain", "forest", "sand", "water", "bridge", "rock"]:
		return
	if tile_type in ["event", "data_node", "bait"]:
		# These are handled by _make_beacon().
		return
	if tile_type == "enemy_base":
		# Managed via set_enemy_base_model() by BoardManager / EnemyFactionSystem.
		return

	_poi_node = Node3D.new()
	_poi_node.name = "POIVisual"
	add_child(_poi_node)

	match tile_type:
		"start":
			_build_start_model(_poi_node)
		"exit":
			_build_exit_model(_poi_node)
		"safehouse":
			_build_safehouse_model(_poi_node)
		"city":
			_build_city_model(_poi_node)
		"fuel_depot":
			_build_fuel_depot_model(_poi_node)
		"supply_truck":
			_build_supply_truck_model(_poi_node)
		"wreckage":
			_build_wreckage_model(_poi_node)
		"research_lab":
			_build_research_lab_model(_poi_node)
		"dust_storm":
			_build_dust_storm_model(_poi_node)
		"tactical_smog":
			_build_smog_model(_poi_node)
		"emp_zone":
			_build_emp_model(_poi_node)
		"rain":
			_build_rain_model(_poi_node)
		"sandstorm":
			_build_sandstorm_model(_poi_node)
		"fog":
			_build_fog_model(_poi_node)
		"distress_signal":
			_build_distress_model(_poi_node)
		"scavenge_site":
			_build_scavenge_model(_poi_node)
		"convoy_ambush":
			_build_ambush_model(_poi_node)
		"convoy_breakdown":
			_build_breakdown_model(_poi_node)
		"unknown_signal":
			_build_unknown_signal_model(_poi_node)


# Start Hangar / Forward Command Launchpad
func _build_start_model(root: Node3D) -> void:
	var pad := MeshInstance3D.new()
	var pad_m := BoxMesh.new()
	pad_m.size = Vector3(2.6, 0.08, 2.6)
	pad.mesh = pad_m
	pad.material_override = _poi_mat(Color(0.24, 0.26, 0.30), 0.8)
	pad.position = Vector3(0, 0.04, 0)
	root.add_child(pad)

	# Antenna Mast
	var mast := MeshInstance3D.new()
	var mast_m := CylinderMesh.new()
	mast_m.top_radius = 0.04
	mast_m.bottom_radius = 0.06
	mast_m.height = 1.6
	mast.mesh = mast_m
	mast.material_override = _poi_mat(Color(0.4, 0.45, 0.5), 0.6)
	mast.position = Vector3(-1.0, 0.8, -1.0)
	root.add_child(mast)

	# 4 Corner Blue Beacons
	var corner_offsets = [Vector3(-1.1, 0.1, -1.1), Vector3(1.1, 0.1, -1.1), Vector3(-1.1, 0.1, 1.1), Vector3(1.1, 0.1, 1.1)]
	for off in corner_offsets:
		var b := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.08
		bm.height = 0.16
		b.mesh = bm
		b.material_override = _poi_mat(Color(0.3, 0.8, 1.0), 0.3, Color(0.3, 0.8, 1.0), 3.0)
		b.position = off
		root.add_child(b)

	_add_floating_badge(root, "🚩 BASE", Color(0.4, 0.85, 1.0), 2.2)


# Exit / Evacuation Helipad Zone
func _build_exit_model(root: Node3D) -> void:
	var pad := MeshInstance3D.new()
	var pad_m := CylinderMesh.new()
	pad_m.top_radius = 1.3
	pad_m.bottom_radius = 1.35
	pad_m.height = 0.08
	pad.mesh = pad_m
	pad.material_override = _poi_mat(Color(0.22, 0.22, 0.26), 0.8)
	pad.position = Vector3(0, 0.04, 0)
	root.add_child(pad)

	# Yellow cross marker
	var cross := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.8, 0.09, 0.35)
	cross.mesh = cm
	cross.material_override = _poi_mat(Color(0.9, 0.75, 0.2), 0.5)
	cross.position = Vector3(0, 0.045, 0)
	root.add_child(cross)

	var cross2 := MeshInstance3D.new()
	var cm2 := BoxMesh.new()
	cm2.size = Vector3(0.35, 0.09, 1.8)
	cross2.mesh = cm2
	cross2.material_override = _poi_mat(Color(0.9, 0.75, 0.2), 0.5)
	cross2.position = Vector3(0, 0.045, 0)
	root.add_child(cross2)

	# Magenta strobe beacons
	for i in range(4):
		var angle := float(i) * (PI / 2.0) + PI / 4.0
		var pos := Vector3(cos(angle) * 1.1, 0.1, sin(angle) * 1.1)
		var b := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.09
		bm.height = 0.18
		b.mesh = bm
		b.material_override = _poi_mat(Color(0.95, 0.35, 0.95), 0.2, Color(0.95, 0.35, 0.95), 3.5)
		b.position = pos
		root.add_child(b)

	_add_floating_badge(root, "🚁 EVAC", Color(0.95, 0.45, 0.95), 2.2)


# Safehouse / Field Repair Bunker
func _build_safehouse_model(root: Node3D) -> void:
	var s_node := Node3D.new()
	s_node.position = Vector3(1.0, 0, -1.0)
	s_node.scale = Vector3(0.8, 0.8, 0.8)

	var bunker := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 1.0
	bm.height = 1.1
	bunker.mesh = bm
	bunker.material_override = _poi_mat(Color(0.28, 0.34, 0.30), 0.7)
	bunker.position = Vector3(0, 0.3, 0)
	s_node.add_child(bunker)

	# Blast door entrance vestibule
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.7, 0.8, 0.5)
	door.mesh = dm
	door.material_override = _poi_mat(Color(0.18, 0.22, 0.20), 0.8)
	door.position = Vector3(0, 0.4, 0.85)
	s_node.add_child(door)

	# Green status light
	var light := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.08
	lm.height = 0.16
	light.mesh = lm
	light.material_override = _poi_mat(Color(0.3, 0.95, 0.4), 0.2, Color(0.3, 0.95, 0.4), 3.0)
	light.position = Vector3(0, 0.85, 0.88)
	s_node.add_child(light)

	root.add_child(s_node)
	_add_floating_badge(root, "🏠 SAFEHOUSE", Color(0.4, 0.95, 0.4), 2.2, Vector2(1.0, -1.0))


# Trading City / Settlement Cluster
func _build_city_model(root: Node3D) -> void:
	var c_node := Node3D.new()
	c_node.position = Vector3(1.1, 0, -1.1)

	var b1 := MeshInstance3D.new()
	var b1m := BoxMesh.new()
	b1m.size = Vector3(0.8, 1.8, 0.8)
	b1.mesh = b1m
	b1.material_override = _poi_mat(Color(0.38, 0.40, 0.44), 0.8)
	b1.position = Vector3(-0.25, 0.9, -0.25)
	c_node.add_child(b1)

	var b2 := MeshInstance3D.new()
	var b2m := BoxMesh.new()
	b2m.size = Vector3(0.65, 1.2, 0.65)
	b2.mesh = b2m
	b2.material_override = _poi_mat(Color(0.44, 0.42, 0.38), 0.8)
	b2.position = Vector3(0.35, 0.6, -0.2)
	c_node.add_child(b2)

	var b3 := MeshInstance3D.new()
	var b3m := BoxMesh.new()
	b3m.size = Vector3(0.6, 0.85, 0.6)
	b3.mesh = b3m
	b3.material_override = _poi_mat(Color(0.35, 0.38, 0.42), 0.8)
	b3.position = Vector3(0.1, 0.42, 0.35)
	c_node.add_child(b3)

	root.add_child(c_node)
	_add_floating_badge(root, "🏙️ CITY", Color(1.0, 0.75, 0.3), 2.5, Vector2(1.1, -1.1))


# Fuel Depot Storage Silos
func _build_fuel_depot_model(root: Node3D) -> void:
	var f_node := Node3D.new()
	f_node.position = Vector3(1.0, 0, -1.0)
	f_node.scale = Vector3(0.75, 0.75, 0.75)

	for x_off in [-0.5, 0.5]:
		var silo := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.4
		sm.bottom_radius = 0.4
		sm.height = 1.3
		silo.mesh = sm
		silo.material_override = _poi_mat(Color(0.55, 0.58, 0.62), 0.6)
		silo.position = Vector3(x_off, 0.65, 0)
		f_node.add_child(silo)

		# Amber hazard stripe ring
		var stripe := MeshInstance3D.new()
		var stm := CylinderMesh.new()
		stm.top_radius = 0.41
		stm.bottom_radius = 0.41
		stm.height = 0.18
		stripe.mesh = stm
		stripe.material_override = _poi_mat(Color(0.95, 0.65, 0.1), 0.5, Color(0.95, 0.65, 0.1), 1.0)
		stripe.position = Vector3(x_off, 1.0, 0)
		f_node.add_child(stripe)

	# Fuel manifold pipe
	var pipe := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(1.1, 0.1, 0.1)
	pipe.mesh = pm
	pipe.material_override = _poi_mat(Color(0.25, 0.28, 0.32), 0.8)
	pipe.position = Vector3(0, 0.75, 0)
	f_node.add_child(pipe)

	root.add_child(f_node)
	_add_floating_badge(root, "⛽ FUEL DEPOT", Color(1.0, 0.8, 0.2), 2.2, Vector2(1.0, -1.0))


# Supply Truck Carrier
func _build_supply_truck_model(root: Node3D) -> void:
	# Truck Cab
	var cab := MeshInstance3D.new()
	var cab_m := BoxMesh.new()
	cab_m.size = Vector3(0.9, 0.75, 0.9)
	cab.mesh = cab_m
	cab.material_override = _poi_mat(Color(0.30, 0.42, 0.40), 0.7)
	cab.position = Vector3(0, 0.5, 0.65)
	root.add_child(cab)

	# Cargo Container
	var bed := MeshInstance3D.new()
	var bed_m := BoxMesh.new()
	bed_m.size = Vector3(1.1, 0.9, 1.4)
	bed.mesh = bed_m
	bed.material_override = _poi_mat(Color(0.42, 0.46, 0.38), 0.8)
	bed.position = Vector3(0, 0.6, -0.4)
	root.add_child(bed)

	# 6 Wheels
	var wheel_offsets = [
		Vector3(-0.55, 0.2, 0.6), Vector3(0.55, 0.2, 0.6),
		Vector3(-0.55, 0.2, -0.2), Vector3(0.55, 0.2, -0.2),
		Vector3(-0.55, 0.2, -0.8), Vector3(0.55, 0.2, -0.8),
	]
	for wpos in wheel_offsets:
		var w := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(0.18, 0.35, 0.35)
		w.mesh = wm
		w.material_override = _poi_mat(Color(0.12, 0.12, 0.14), 0.9)
		w.position = wpos
		root.add_child(w)

	_add_floating_badge(root, "📦 SUPPLY TRUCK", Color(0.4, 0.9, 0.9), 2.0)


# Fallen Mecha Wreckage
func _build_wreckage_model(root: Node3D) -> void:
	var torso := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(1.4, 0.75, 1.1)
	torso.mesh = tm
	torso.material_override = _poi_mat(Color(0.28, 0.22, 0.20), 0.9)
	torso.position = Vector3(0, 0.38, 0)
	torso.rotation = Vector3(0.2, 0.3, -0.25)
	root.add_child(torso)

	# Scattered limb / arm scrap
	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.4, 0.35, 1.2)
	arm.mesh = am
	arm.material_override = _poi_mat(Color(0.32, 0.26, 0.22), 0.9)
	arm.position = Vector3(0.8, 0.18, -0.3)
	arm.rotation = Vector3(-0.1, 0.6, 0.1)
	root.add_child(arm)

	# Smoldering ember spark
	var ember := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 0.08
	em.height = 0.16
	ember.mesh = em
	ember.material_override = _poi_mat(Color(1.0, 0.45, 0.1), 0.2, Color(1.0, 0.45, 0.1), 3.0)
	ember.position = Vector3(0.1, 0.7, 0.1)
	root.add_child(ember)

	_add_floating_badge(root, "🔧 WRECKAGE", Color(0.95, 0.55, 0.3), 1.8)


# Science & Research Laboratory
func _build_research_lab_model(root: Node3D) -> void:
	var r_node := Node3D.new()
	r_node.position = Vector3(1.0, 0, -1.0)
	r_node.scale = Vector3(0.75, 0.75, 0.75)

	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.9
	bm.bottom_radius = 1.0
	bm.height = 0.85
	base.mesh = bm
	base.material_override = _poi_mat(Color(0.35, 0.42, 0.50), 0.7)
	base.position = Vector3(0, 0.42, 0)
	r_node.add_child(base)

	# Satellite Dish
	var dish := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.6
	dm.bottom_radius = 0.08
	dm.height = 0.22
	dish.mesh = dm
	dish.material_override = _poi_mat(Color(0.75, 0.80, 0.88), 0.5)
	dish.position = Vector3(0.2, 1.15, 0)
	dish.rotation = Vector3(0.5, 0.4, 0)
	r_node.add_child(dish)

	root.add_child(r_node)
	_add_floating_badge(root, "🔬 RESEARCH LAB", Color(0.5, 0.75, 1.0), 2.2, Vector2(1.0, -1.0))


# Dust Storm Vortex Ring
func _build_dust_storm_model(root: Node3D) -> void:
	for h in [0.4, 1.0]:
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 1.2 + h * 0.3
		rm.bottom_radius = 0.9 + h * 0.2
		rm.height = 0.35
		ring.mesh = rm
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.85, 0.70, 0.40, 0.45)
		mat.roughness = 1.0
		ring.material_override = mat
		ring.position = Vector3(0, h, 0)
		root.add_child(ring)

	_add_floating_badge(root, "🌪️ DUST STORM", Color(0.9, 0.8, 0.5), 2.0)


# Rain Zone — translucent blue columns with ripple rings
func _build_rain_model(root: Node3D) -> void:
	# Rain curtain pillars
	for i in range(5):
		var pillar := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.02
		pm.bottom_radius = 0.02
		pm.height = 2.5
		pillar.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.45, 0.6, 0.9, 0.3)
		mat.roughness = 1.0
		pillar.material_override = mat
		pillar.position = Vector3(randf_range(-1.0, 1.0), 1.2, randf_range(-1.0, 1.0))
		root.add_child(pillar)
	# Ripple rings on ground
	for j in range(3):
		var ripple := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = 0.3 + j * 0.2
		rm.outer_radius = 0.35 + j * 0.2
		ripple.mesh = rm
		var rmat := StandardMaterial3D.new()
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.albedo_color = Color(0.5, 0.7, 1.0, 0.25)
		ripple.material_override = rmat
		ripple.position = Vector3(randf_range(-0.8, 0.8), 0.05, randf_range(-0.8, 0.8))
		root.add_child(ripple)
	_add_floating_badge(root, "🌧️ RAIN", Color(0.5, 0.7, 1.0), 2.0)


# Sandstorm — swirling amber particles with low-lying sand cloud
func _build_sandstorm_model(root: Node3D) -> void:
	# Sand cloud spheres
	for i in range(4):
		var cloud := MeshInstance3D.new()
		var cm := SphereMesh.new()
		cm.radius = 0.6 + randf() * 0.4
		cm.height = 0.8
		cloud.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.85, 0.70, 0.35, 0.45)
		mat.roughness = 1.0
		cloud.material_override = mat
		cloud.position = Vector3(randf_range(-1.0, 1.0), 0.3 + randf() * 0.4, randf_range(-1.0, 1.0))
		root.add_child(cloud)
	# Swirl ring
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.8
	rm.outer_radius = 1.1
	ring.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(0.9, 0.75, 0.4, 0.35)
	ring.material_override = rmat
	ring.position = Vector3(0, 0.8, 0)
	ring.rotation_degrees.x = 15.0
	root.add_child(ring)
	_add_floating_badge(root, "🏜️ SANDSTORM", Color(0.9, 0.8, 0.4), 2.0)


# Fog Zone — low-lying translucent white blanket
func _build_fog_model(root: Node3D) -> void:
	# Fog blanket panels
	for i in range(6):
		var fog := MeshInstance3D.new()
		var fm := QuadMesh.new()
		fm.size = Vector2(1.2, 0.6)
		fog.mesh = fm
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.8, 0.82, 0.85, 0.35)
		mat.roughness = 1.0
		fog.material_override = mat
		fog.position = Vector3(randf_range(-1.2, 1.2), 0.3, randf_range(-1.2, 1.2))
		fog.rotation_degrees.y = randf() * 360.0
		root.add_child(fog)
	_add_floating_badge(root, "🌫️ FOG", Color(0.8, 0.82, 0.85), 2.0)


# Tactical Toxic Smog
func _build_smog_model(root: Node3D) -> void:
	for off in [Vector3(-0.4, 0.4, -0.3), Vector3(0.4, 0.5, 0.3), Vector3(0.1, 0.35, -0.2)]:
		var cloud := MeshInstance3D.new()
		var cm := SphereMesh.new()
		cm.radius = 0.7
		cm.height = 0.8
		cloud.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.45, 0.65, 0.35, 0.40)
		mat.roughness = 1.0
		cloud.material_override = mat
		cloud.position = off
		root.add_child(cloud)

	_add_floating_badge(root, "☣️ TOXIC SMOG", Color(0.65, 0.9, 0.4), 1.8)


# EMP Discharge Hazard Field
func _build_emp_model(root: Node3D) -> void:
	var spire := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.08
	sm.bottom_radius = 0.16
	sm.height = 1.6
	spire.mesh = sm
	spire.material_override = _poi_mat(Color(0.28, 0.28, 0.35), 0.6)
	spire.position = Vector3(0, 0.8, 0)
	root.add_child(spire)

	for yh in [0.5, 0.9, 1.3]:
		var coil := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.35
		cm.bottom_radius = 0.35
		cm.height = 0.1
		coil.mesh = cm
		coil.material_override = _poi_mat(Color(0.7, 0.35, 0.95), 0.2, Color(0.4, 0.85, 1.0), 4.5)
		coil.position = Vector3(0, yh, 0)
		root.add_child(coil)

	# Electric pulsing light at the spire top
	var emp_light := OmniLight3D.new()
	emp_light.light_color = Color(0.4, 0.85, 1.0)
	emp_light.light_energy = 2.5
	emp_light.omni_range = 3.5
	emp_light.position = Vector3(0, 1.7, 0)
	root.add_child(emp_light)

	# Pulsing animation on the light
	var lt := root.create_tween().set_loops()
	lt.tween_property(emp_light, "light_energy", 0.6, 0.4).set_trans(Tween.TRANS_SINE)
	lt.tween_property(emp_light, "light_energy", 3.2, 0.2).set_trans(Tween.TRANS_BOUNCE)

	_add_floating_badge(root, "⚡ EMP FIELD", Color(0.85, 0.5, 1.0), 2.2)


# Distress Signal Antenna Tower
func _build_distress_model(root: Node3D) -> void:
	var tower := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.06
	tm.bottom_radius = 0.2
	tm.height = 2.0
	tower.mesh = tm
	tower.material_override = _poi_mat(Color(0.35, 0.38, 0.42), 0.7)
	tower.position = Vector3(0, 1.0, 0)
	root.add_child(tower)

	var beacon := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.14
	bm.height = 0.28
	beacon.mesh = bm
	beacon.material_override = _poi_mat(Color(1.0, 0.25, 0.25), 0.2, Color(1.0, 0.25, 0.25), 4.0)
	beacon.position = Vector3(0, 2.05, 0)
	root.add_child(beacon)

	_add_floating_badge(root, "📡 DISTRESS SOS", Color(1.0, 0.4, 0.4), 2.6)


# Scavenge & Salvage Pod Site
func _build_scavenge_model(root: Node3D) -> void:
	var c1 := MeshInstance3D.new()
	var c1m := BoxMesh.new()
	c1m.size = Vector3(1.1, 0.6, 0.8)
	c1.mesh = c1m
	c1.material_override = _poi_mat(Color(0.48, 0.38, 0.28), 0.85)
	c1.position = Vector3(-0.3, 0.3, 0)
	root.add_child(c1)

	var c2 := MeshInstance3D.new()
	var c2m := BoxMesh.new()
	c2m.size = Vector3(0.7, 0.5, 0.7)
	c2.mesh = c2m
	c2.material_override = _poi_mat(Color(0.38, 0.42, 0.45), 0.85)
	c2.position = Vector3(0.45, 0.25, 0.1)
	root.add_child(c2)

	_add_floating_badge(root, "⛏️ SALVAGE SITE", Color(0.85, 0.75, 0.5), 1.9)


# Convoy Ambush Checkpoint Barricade
func _build_ambush_model(root: Node3D) -> void:
	for x_off in [-0.6, 0.6]:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 0.6, 0.3)
		bar.mesh = bm
		bar.material_override = _poi_mat(Color(0.65, 0.25, 0.20), 0.8)
		bar.position = Vector3(x_off, 0.3, 0)
		bar.rotation.y = 0.2 if x_off < 0 else -0.2
		root.add_child(bar)

	_add_floating_badge(root, "⚠️ AMBUSH", Color(1.0, 0.3, 0.3), 1.8)


# Convoy Breakdown Site
func _build_breakdown_model(root: Node3D) -> void:
	var truck := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(1.0, 0.75, 1.6)
	truck.mesh = tm
	truck.material_override = _poi_mat(Color(0.45, 0.38, 0.30), 0.8)
	truck.position = Vector3(0, 0.4, 0)
	truck.rotation.y = 0.35
	root.add_child(truck)

	# Warning cone
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.15
	cm.height = 0.45
	cone.mesh = cm
	cone.material_override = _poi_mat(Color(0.95, 0.5, 0.1), 0.4, Color(0.95, 0.5, 0.1), 1.5)
	cone.position = Vector3(0.85, 0.22, 0.6)
	root.add_child(cone)

	_add_floating_badge(root, "🔧 BREAKDOWN", Color(1.0, 0.6, 0.2), 1.9)


# Unknown Signal / Emergency Beacon
func _build_unknown_signal_model(root: Node3D) -> void:
	# Base radar dish mast
	var mast := MeshInstance3D.new()
	var mm := CylinderMesh.new()
	mm.top_radius = 0.08
	mm.bottom_radius = 0.22
	mm.height = 1.0
	mast.mesh = mm
	mast.material_override = _poi_mat(Color(0.25, 0.28, 0.35), 0.7)
	mast.position = Vector3(0, 0.5, 0)
	root.add_child(mast)

	# Glowing antenna emitter
	var emitter := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 0.22
	em.height = 0.44
	emitter.mesh = em
	emitter.material_override = _poi_mat(Color(0.25, 0.85, 1.0), 0.3, Color(0.2, 0.85, 1.0), 3.0)
	emitter.position = Vector3(0, 1.1, 0)
	root.add_child(emitter)

	# Scanner ring
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.35
	rm.outer_radius = 0.45
	ring.mesh = rm
	ring.material_override = _poi_mat(Color(0.25, 0.85, 1.0), 0.4, Color(0.2, 0.85, 1.0), 2.0)
	ring.position = Vector3(0, 0.75, 0)
	ring.rotation.x = 0.3
	root.add_child(ring)

	_add_floating_badge(root, "❓ UNKNOWN SIGNAL", Color(0.25, 0.85, 1.0), 1.9)


# ---------------------------------------------------------------------------
# HIGHLIGHTS & BEACONS
# ---------------------------------------------------------------------------

func highlight(active: bool) -> void:
	is_highlighted = active
	if active:
		_ensure_reachable_glow()
		if _reachable_glow != null:
			_reachable_glow.visible = true
		reveal()
	else:
		if _reachable_glow != null:
			_reachable_glow.visible = false


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


func _make_beacon() -> Node:
	var beacon := Node3D.new()
	beacon.set_script(preload("res://scripts/board/tile_glow.gd"))
	if tile_type == "event":
		beacon.setup(Color(0.35, 0.85, 1.0))
		_add_floating_badge(beacon, "❓ EVENT", Color(0.4, 0.85, 1.0), 2.2)
	elif tile_type == "bait":
		beacon.setup(Color(1.0, 0.45, 0.15))
		_add_floating_badge(beacon, "❓ CACHE", Color(1.0, 0.6, 0.2), 2.2)
	else:
		beacon.setup(Color(1.0, 0.75, 0.2))
		_add_floating_badge(beacon, "💎 DATA NODE", Color(1.0, 0.85, 0.3), 2.2)
	add_child(beacon)
	return beacon


# ---------------------------------------------------------------------------
# ENEMY BASE 3D MODEL
# ---------------------------------------------------------------------------

func set_enemy_base_model(kind: String) -> void:
	_clear_enemy_base_model()
	_enemy_base_model = Node3D.new()
	_enemy_base_model.name = "EnemyBaseModel"
	add_child(_enemy_base_model)
	if kind == "camp":
		_build_camp_model(_enemy_base_model)
		_add_floating_badge(_enemy_base_model, "⚡ ENEMY CAMP", Color(1.0, 0.35, 0.3), 2.2)
	else:
		_build_rooted_model(_enemy_base_model)
		_add_floating_badge(_enemy_base_model, "⚡ ENEMY BASE", Color(1.0, 0.35, 0.3), 5.8)
	_enemy_base_model.visible = is_revealed


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
		if not is_inside_tree():
			return
		var bm = get_tree().current_scene
		if bm and bm.has_node("BoardHUD"):
			var hud = bm.get_node("BoardHUD")
			if hud and hud.has_method("update_tile_inspector"):
				var e_cost := GlobalData.fuel.get_tile_energy_cost(terrain)
				var mp_cost := BoardConfig.move_cost(terrain)
				var is_zoc := PatrolSystem.is_in_zone_of_control(grid_pos)
				var is_artillery := not PatrolSystem.check_artillery_bombardment(grid_pos).is_empty()
				hud.update_tile_inspector(terrain, mp_cost, e_cost, is_zoc, is_artillery)
	else:
		mesh_instance.position.y = 0.02 if is_highlighted else 0.0


func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not is_inside_tree():
			return
		var board_manager = get_tree().current_scene
		if board_manager and board_manager.has_method("move_to_tile"):
			board_manager.move_to_tile(grid_pos)