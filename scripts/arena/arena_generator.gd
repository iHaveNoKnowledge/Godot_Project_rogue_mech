extends Node3D

## Generates procedural combat maps: Desert, Skyscraper City, Urban Crossroads, and River Bridge.

@export var arena_size: float = 240.0
@export var tile_count: int = 24

enum BiomeTheme { DESERT, CITY_HIGHRISE, CROSSROADS, RIVER_BRIDGE, FOREST, FOREST_ROAD }

# Arena footprint per combat node type — bigger fights need bigger fields so the
# spawn ring / AI search radius / nav floor all breathe instead of hugging walls.
const ARENA_SIZES: Dictionary = {
	"grunt": 240.0,
	"ace": 320.0,
	"duel": 300.0,
	"boss": 400.0,
	"enemy_base": 400.0,
}

# How far the walkable ground extends past the arena edge, so the player can
# walk THROUGH the retreat light wall and stand behind it (the retreat hold
# keeps charging out there). The void barrier sits just past this apron.
const ESCAPE_APRON_DEPTH := 5.0

var current_theme: BiomeTheme = BiomeTheme.DESERT
var tile_container: Node3D
var escape_zone_container: Node3D
var structures_container: Node3D

# Natural ground-variation noise used to tint the seamless floor texture so it
# reads organic instead of a flat plastic slab.
var ground_noise: FastNoiseLite = FastNoiseLite.new()

# Low-frequency noise that rolls the FOREST banks into gentle hills. Seeded
# from the board seed so the same map always fights on the same terrain while
# different boards get different contours.
var terrain_noise: FastNoiseLite = FastNoiseLite.new()

# Open-field blobs (meadow clearings) for the FOREST biome, computed once per
# arena so the heightmap, floor texture, and prop scatter all agree on where
# the clearings are.
var _forest_fields: Array = []
var _forest_fields_ready: bool = false

# Counter for unique decor-patch names (Godot auto-renames duplicate sibling
# names, which would hide all but the first flower/leaf patch from lookups).
var _forest_decor_seq: int = 0

# Walkable surface height of the forest river strip (matches the riverband
# collision top) so the bank terrain meets the wading band flush instead of
# leaving a step that could trap mechs against the water.
const FOREST_RIVER_STRIP_Y := -0.35


func _ready() -> void:
	current_theme = _theme_from_board()
	arena_size = _arena_size_for_combat()
	GlobalData.current_arena_size = arena_size
	generate_arena()
	_place_player_at_arena_edge()


# Moves the player mech to a random EDGE spawn instead of the center of the
# field, so each battle starts from a different side. The spot is chosen away
# from cover objects (trees, buildings, dunes) so the player never spawns
# inside a rock or tree trunk. Falls back to leaving the mech where it is if no
# clear edge spot exists.
func _place_player_at_arena_edge() -> void:
	var host := get_parent()
	if host == null:
		return
	var mecha := host.get_node_or_null("Mecha")
	if mecha == null:
		return
	# Cover objects spawn one frame later (obstacle_spawner awaits a frame), but
	# their positions are deterministic via the shared seed system — query them
	# up front so the player never spawns on top of a tree/rock/barricade.
	var cover_positions: Array = []
	var seed_sys = host.get_node_or_null("ArenaSeedSystem")
	if seed_sys and seed_sys.has_method("set_seed") and seed_sys.has_method("get_obstacle_positions"):
		seed_sys.set_seed(GlobalData.current_sector, GlobalData.current_tile)
		cover_positions = seed_sys.get_obstacle_positions(current_theme, arena_size)
	var attempts := 0
	while attempts < 24:
		attempts += 1
		# Pick a point on the outer ring (between 30% and 46% of the arena size
		# away from center) — clearly off-center, still inside the escape walls.
		# A random angle every roll so spawns vary per battle.
		var angle := randf_range(0.0, TAU)
		var dist := arena_size * randf_range(0.30, 0.46)
		var candidate := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		# Keep clear of every solid obstacle + upcoming cover spawn.
		if _spawn_point_clear(candidate, 8.0, cover_positions):
			mecha.position = candidate
			mecha.position.y = 5.0  # Drop-pod height; combat_intro waits for landing.
			return
	# No clear ring spot (dense dune/buildings) — fall back to the arena center,
	# which every theme keeps clear of structures (center pockets stay empty).
	mecha.position = Vector3.ZERO
	mecha.position.y = 5.0


# True when no solid obstacle (dune, rock, building, tree, log, cover) occupies
# the point or sits within `min_dist` meters of it, the point is not on top of a
# future cover spawn, and it is not inside the void/escape frame. Clearance is
# measured against each obstacle's WORLD AABB (its true footprint) rather than
# its center — a 24m building or 45m dune blocks its full extent + margin, so
# the drop-pod never lands embedded inside a wall.
func _spawn_point_clear(point: Vector3, min_dist: float, cover_positions: Array = []) -> bool:
	var half := arena_size * 0.5
	if absf(point.x) > half - 6.0 or absf(point.z) > half - 6.0:
		return false
	for node in get_tree().get_nodes_in_group("solid_obstacle"):
		if node is Node3D:
			var aabb := _obstacle_world_aabb(node)
			if aabb.size != Vector3.ZERO and _point_near_aabb(point, aabb, min_dist):
				return false
	for cp in cover_positions:
		if cp is Dictionary:
			var cpos: Vector3 = cp.get("pos", Vector3.ZERO)
			if Vector2(point.x, point.z).distance_to(Vector2(cpos.x, cpos.z)) < min_dist:
				return false
	return true


# World-space AABB of a solid obstacle body (from its collision shape, so
# rotated dunes/buildings still report their true footprint). Returns a
# zero-sized AABB when the body has no usable collision shape.
func _obstacle_world_aabb(body: Node3D) -> AABB:
	for child in body.get_children():
		if child is CollisionShape3D and child.shape != null:
			var s: Shape3D = child.shape
			var half: Vector3
			if s is BoxShape3D:
				half = (s as BoxShape3D).size * 0.5
			elif s is CylinderShape3D:
				var cyl := s as CylinderShape3D
				half = Vector3(cyl.radius, cyl.height * 0.5, cyl.radius)
			else:
				continue
			var t: Transform3D = (child as CollisionShape3D).global_transform
			var half_world: Vector3 = (t.basis * half).abs()
			return AABB(t.origin - half_world, half_world * 2.0)
	return AABB()


# True when the point's XZ position is within `margin` of the AABB's footprint
# (expanded box), so a mech standing at `point` would collide with the body.
func _point_near_aabb(point: Vector3, aabb: AABB, margin: float) -> bool:
	var min_x := aabb.position.x - margin
	var max_x := aabb.end.x + margin
	var min_z := aabb.position.z - margin
	var max_z := aabb.end.z + margin
	return point.x >= min_x and point.x <= max_x \
		and point.z >= min_z and point.z <= max_z


# Picks the field size for the current battle. Defaults to the export value when
# no recognized combat node type is present (e.g. standalone test scenes).
func _arena_size_for_combat() -> float:
	var node_type := GameManager.combat_node_type
	if ARENA_SIZES.has(node_type):
		return float(ARENA_SIZES[node_type])
	return arena_size


# The open-grid board theme drives the combat arena biome, so the battle scene
# always matches the map the player is exploring (desert dune fights on the
# desert board, urban skyscraper fights in the city, etc.). The board theme is
# read from GlobalData directly (not GameManager.current_state) because
# enter_combat() flips the state to COMBAT before the deferred scene swap runs,
# so arena_generator._ready() would otherwise never see State.BOARD.
func _theme_from_board() -> BiomeTheme:
	# A forest board fought on a ROAD tile gets the road-through-forest arena:
	# the enemy was caught on the forest road, so the battle map is a road
	# cutting through the woods instead of the plain river forest.
	if GlobalData.board_theme_id == "forest" and GlobalData.combat_tile_terrain == "road":
		return BiomeTheme.FOREST_ROAD
	var arena_name: String = BoardConfig.THEME_ARENA.get(GlobalData.board_theme_id, "")
	# Never fall back to a RANDOM biome: a random pick can drop a forest board
	# into a street fight (and vice versa). Unknown/empty themes default to the
	# suburb crossroads, matching the default board theme.
	if arena_name == "":
		return BiomeTheme.CROSSROADS
	for i in range(BiomeTheme.size()):
		if BiomeTheme.keys()[i] == arena_name:
			return i as BiomeTheme
	return BiomeTheme.CROSSROADS


func generate_arena() -> void:
	_create_containers()
	_add_ground_tiles()
	_add_ground_collision()
	_create_escape_zones()
	_add_escape_apron()
	_create_void_barrier()
	_create_theme_structures()
	EventBus.arena_generated.emit({
		"size": arena_size,
		"theme": current_theme
	})


func _create_containers() -> void:
	escape_zone_container = Node3D.new()
	escape_zone_container.name = "EscapeZones"
	add_child(escape_zone_container)

	tile_container = Node3D.new()
	tile_container.name = "GroundTiles"
	add_child(tile_container)

	structures_container = Node3D.new()
	structures_container.name = "ThemeStructures"
	add_child(structures_container)


# Builds the battlefield floor as ONE seamless textured plane per theme instead
# of a grid of 24x24 box tiles (which showed visible seams + hard color
# patchwork). A 1024px image is generated per theme and stretched across the
# whole field, so roads/lanes/trails blend naturally with no tile lines.
func _add_ground_tiles() -> void:
	var texture := _build_ground_texture()

	match current_theme:
		BiomeTheme.RIVER_BRIDGE:
			# Raised banks on each side of the water trench (|z| < 22 is the
			# sunken riverbed handled by the river structures).
			_add_ground_plane(texture, 0.45, -22.0, arena_size / 2.0)
			_add_ground_plane(texture, 0.45, 22.0, arena_size / 2.0)
		BiomeTheme.FOREST, BiomeTheme.FOREST_ROAD:
			# Rolling banks + a flat central band: the river strip stays a plain
			# quad (the water sheet sits under it) while the banks are displaced
			# into gentle hills and open meadow clearings. FOREST_ROAD reuses the
			# same geometry but the central band is a level road (see
			# _forest_terrain_height / _get_theme_ground_color), so the battle
			# reads as a road cutting through the woods.
			_add_forest_terrain_banks(texture)
			_add_forest_strip_plane(texture)
		_:
			_add_ground_plane(texture, -0.39, -arena_size / 2.0, arena_size / 2.0)


func _add_ground_plane(texture: Texture2D, y: float, z0: float, z1: float) -> void:
	var size_z := z1 - z0
	var center_z := (z0 + z1) * 0.5
	var plane = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(arena_size, 0.1, size_z)
	plane.mesh = box

	var mat = StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.roughness = 0.85
	# Stretch UVs so the generated texture spans the full field once (no tiling
	# seams, roads keep their true metre-scale spacing).
	mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
	plane.material_override = mat

	plane.position = Vector3(0, y, center_z)
	tile_container.add_child(plane)


# The flat river band (|z| < 24) between the two banks. Built as an explicit
# quad with position-mapped UVs so it shows only the texture's middle band
# (z -24..24 of the full field) and lines up seamlessly with the bank meshes.
func _add_forest_strip_plane(texture: Texture2D) -> void:
	var half := arena_size / 2.0
	var z0 := -24.0
	var z1 := 24.0
	var strip_y := _forest_strip_y()
	# Keep the same height as the old full-field plane (top ~ -0.34) so the
	# sunken water sheet and the riverbank look are unchanged. FOREST_ROAD
	# raises the strip to a level road surface instead.
	var verts := PackedVector3Array([
		Vector3(-half, strip_y - 0.04, z0),
		Vector3(half, strip_y - 0.04, z0),
		Vector3(-half, strip_y - 0.04, z1),
		Vector3(half, strip_y - 0.04, z1),
	])
	var uvs := PackedVector2Array([
		Vector2(0.0, (z0 + half) / arena_size),
		Vector2(1.0, (z0 + half) / arena_size),
		Vector2(0.0, (z1 + half) / arena_size),
		Vector2(1.0, (z1 + half) / arena_size),
	])
	var normals := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var indices := PackedInt32Array([0, 1, 2, 2, 1, 3])

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.roughness = 0.85
	var surface := MeshInstance3D.new()
	surface.name = "ForestRiverStrip"
	surface.mesh = mesh
	surface.material_override = mat
	tile_container.add_child(surface)


# Builds the two forest bank surfaces (north + south of the river strip) as a
# displaced ArrayMesh so the terrain rolls into gentle hills and flat meadow
# clearings instead of being a flat slab. The vertex heights come from the same
# _forest_terrain_height() the collision uses, so what you see is what you walk.
func _add_forest_terrain_banks(texture: Texture2D) -> void:
	var half := arena_size / 2.0
	_add_forest_bank_mesh(texture, 24.0, half)
	_add_forest_bank_mesh(texture, -half, -24.0)


func _add_forest_bank_mesh(texture: Texture2D, z0: float, z1: float) -> void:
	var half := arena_size / 2.0
	var step := 4.0
	var cols := int(ceil(arena_size / step))
	var rows := int(ceil((z1 - z0) / step))

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	for row in range(rows + 1):
		var wz := z0 + float(row) * (z1 - z0) / float(rows)
		for col in range(cols + 1):
			var wx := -half + float(col) * arena_size / float(cols)
			verts.append(Vector3(wx, _forest_terrain_height(wx, wz), wz))
			# UVs map back to world coords so the position-based floor texture
			# (roads/trails/moss) stays continuous across banks and river strip.
			uvs.append(Vector2((wx + half) / arena_size, (wz + half) / arena_size))
			normals.append(Vector3.ZERO)

	var indices := PackedInt32Array()
	for row in range(rows):
		for col in range(cols):
			var i00 := row * (cols + 1) + col
			var i10 := i00 + 1
			var i01 := i00 + (cols + 1)
			var i11 := i01 + 1
			indices.append(i00)
			indices.append(i01)
			indices.append(i10)
			indices.append(i10)
			indices.append(i01)
			indices.append(i11)

	# Smooth vertex normals averaged from face normals so the gentle hills
	# shade soft instead of showing faceted triangles.
	for i in range(0, indices.size(), 3):
		var a := verts[indices[i]]
		var b := verts[indices[i + 1]]
		var c := verts[indices[i + 2]]
		var n := (b - a).cross(c - a)
		normals[indices[i]] = normals[indices[i]] + n
		normals[indices[i + 1]] = normals[indices[i + 1]] + n
		normals[indices[i + 2]] = normals[indices[i + 2]] + n
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.roughness = 0.85
	var surface := MeshInstance3D.new()
	surface.name = "ForestTerrain"
	surface.mesh = mesh
	surface.material_override = mat
	tile_container.add_child(surface)


# Generates a seamless 1024px ground texture for the current theme. Each pixel
# maps to a world coordinate and gets the theme's palette (roads, sidewalks,
# lanes, trails) blended with organic noise so it never looks tiled.
func _build_ground_texture() -> ImageTexture:
	var res := 1024
	var img := Image.create(res, res, false, Image.FORMAT_RGB8)
	var half := arena_size / 2.0
	for py in range(res):
		var wz := lerpf(-half, half, float(py) / float(res - 1))
		for px in range(res):
			var wx := lerpf(-half, half, float(px) / float(res - 1))
			img.set_pixel(px, py, _get_theme_ground_color(wx, wz))
	return ImageTexture.create_from_image(img)


func _get_theme_ground_color(pos_x: float, pos_z: float) -> Color:
	var v := ground_noise.get_noise_2d(pos_x * 0.03, pos_z * 0.03) * 0.05
	match current_theme:
		BiomeTheme.DESERT:
			return Color(0.62 + v, 0.50 + v, 0.32 + v)

		BiomeTheme.CITY_HIGHRISE:
			if int(abs(pos_x)) % 40 < 12 or int(abs(pos_z)) % 40 < 12:
				return Color(0.18 + v, 0.19 + v, 0.22 + v)
			return Color(0.40 + v, 0.42 + v, 0.45 + v)

		BiomeTheme.CROSSROADS:
			if absf(pos_x) < 18.0 or absf(pos_z) < 18.0:
				if absf(pos_x) < 1.0 or absf(pos_z) < 1.0:
					return Color(0.85 + v, 0.75 + v, 0.20 + v)
				return Color(0.15 + v, 0.16 + v, 0.18 + v)
			return Color(0.45 + v, 0.45 + v, 0.48 + v)

		BiomeTheme.RIVER_BRIDGE:
			if absf(pos_z) < 32.0:
				return Color(0.35 + v, 0.32 + v, 0.28 + v)
			return Color(0.22 + v, 0.24 + v, 0.26 + v)

		BiomeTheme.FOREST:
			# Open fields read as sunlit meadow clearings (lighter green); the
			# rest of the forest floor stays dark mossy undergrowth.
			if _is_open_field(pos_x, pos_z):
				return Color(0.32 + v, 0.56 + v, 0.24 + v)
			if int(abs(pos_x)) % 22 < 3 or int(abs(pos_z)) % 22 < 3:
				return Color(0.24 + v, 0.20 + v, 0.14 + v)
			return Color(0.14 + v, 0.30 + v, 0.14 + v)

		BiomeTheme.FOREST_ROAD:
			# A packed-dirt / light-asphalt road cuts through the woods along
			# the central band (|z| < 24); the forest floor around it keeps the
			# FOREST palette (meadows + mossy undergrowth).
			if absf(pos_z) < 24.0:
				if absf(pos_z) < 2.0:
					return Color(0.30 + v, 0.28 + v, 0.22 + v)
				return Color(0.26 + v, 0.24 + v, 0.19 + v)
			if _is_open_field(pos_x, pos_z):
				return Color(0.32 + v, 0.56 + v, 0.24 + v)
			if int(abs(pos_x)) % 22 < 3 or int(abs(pos_z)) % 22 < 3:
				return Color(0.24 + v, 0.20 + v, 0.14 + v)
			return Color(0.14 + v, 0.30 + v, 0.14 + v)

	return Color(0.5, 0.5, 0.5)


# The main walkable ground per theme. The global Ground in game_world.tscn is
# only a deep safety net now (top ~ -2.5), so each theme must build its own
# collision surface: a flat plane for most themes, and raised riverbanks for
# RIVER_BRIDGE so the water trench reads as a real sunken channel.
func _add_ground_collision() -> void:
	if current_theme == BiomeTheme.RIVER_BRIDGE:
		_add_riverbank_collision()
		return
	if current_theme == BiomeTheme.FOREST or current_theme == BiomeTheme.FOREST_ROAD:
		_add_forest_terrain_collision()
		return

	var ground = StaticBody3D.new()
	ground.name = "GroundCollision"
	ground.collision_layer = 2
	ground.collision_mask = 1

	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(arena_size, 0.8, arena_size)
	col.shape = shape
	ground.add_child(col)

	ground.position = Vector3(0, -0.8, 0)
	structures_container.add_child(ground)


func _add_riverbank_collision() -> void:
	var half := arena_size / 2.0
	var trench_half := 22.0
	var bank_depth := half - trench_half

	for sign_z in [1.0, -1.0]:
		var bank = StaticBody3D.new()
		bank.name = "RiverbankCollision"
		bank.collision_layer = 2
		bank.collision_mask = 1

		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(arena_size, 1.0, bank_depth)
		col.shape = shape
		bank.add_child(col)

		var z_center = sign_z * (trench_half + bank_depth * 0.5)
		bank.position = Vector3(0, 0.0, z_center)
		structures_container.add_child(bank)


# Walkable collision for the forest banks: one HeightMapShape3D per bank that
# matches the visual terrain mesh exactly (1m grid, heights in world units).
# The river strip keeps its own flat collision + riverbed, so the two surfaces
# meet flush at |z| = 24 (both sit at FOREST_RIVER_STRIP_Y there).
func _add_forest_terrain_collision() -> void:
	var half := arena_size / 2.0
	_add_forest_bank_collision(24.0, half)
	_add_forest_bank_collision(-half, -24.0)


func _add_forest_bank_collision(z0: float, z1: float) -> void:
	var half := arena_size / 2.0
	# HeightMapShape3D grid points sit 1 unit apart, so arena_size samples span
	# exactly the field width (and (z1 - z0) samples the bank depth).
	var x_samples := int(round(arena_size)) + 1
	var z_samples := int(round(z1 - z0)) + 1
	var data := PackedFloat32Array()
	data.resize(x_samples * z_samples)
	for row in range(z_samples):
		var wz := z0 + float(row) * (z1 - z0) / float(z_samples - 1)
		for col in range(x_samples):
			var wx := -half + float(col) * arena_size / float(x_samples - 1)
			data[row * x_samples + col] = _forest_terrain_height(wx, wz)

	var shape := HeightMapShape3D.new()
	shape.map_width = x_samples
	shape.map_depth = z_samples
	shape.map_data = data

	var body := StaticBody3D.new()
	body.name = "ForestTerrainCollision%s" % ("North" if z0 > 0.0 else "South")
	body.collision_layer = 2
	body.collision_mask = 1
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	# The heightmap grid is centered on the node origin; shift it to the bank's
	# z-center so the grid covers exactly [z0, z1] with heights in world units.
	body.position = Vector3(0, 0, (z0 + z1) * 0.5)
	structures_container.add_child(body)


func _create_escape_zones() -> void:
	var half := arena_size / 2.0
	# Zone frame spans the full square INCLUDING the apron corners so the
	# retreat hold keeps charging anywhere behind the wall, even out at the
	# corners of the outside strip.
	var len := arena_size + ESCAPE_APRON_DEPTH * 2.0

	# Escape zones form a square frame of tall light walls around the arena's
	# outer edge — OUTSIDE the combat field (beyond the spawn ring and dunes,
	# just inside the void barrier) — so retreating never happens mid-fight.
	# The trigger box extends WELL PAST the visible wall into the outside
	# strip, all the way to the void barrier's inner face: the wall itself is
	# a slim, purely-visual light wall the player walks straight through, and
	# the retreat hold keeps charging even out in the dead zone behind it.
	var wall_height := 8.0
	# Trigger spans from 4m inside the field (the hold starts charging as the
	# player approaches the wall) through the whole apron to the barrier's
	# inner face (half + apron depth + 0.5), so standing anywhere behind the
	# wall still counts toward the escape.
	var trigger_inner := half - 4.0
	var trigger_outer := half + ESCAPE_APRON_DEPTH + 0.5
	var trigger_thickness := trigger_outer - trigger_inner
	var trigger_center := (trigger_inner + trigger_outer) * 0.5
	var zone_defs = [
		{"pos": Vector3(0, wall_height * 0.5, -trigger_center), "size": Vector3(len, wall_height, trigger_thickness)},
		{"pos": Vector3(0, wall_height * 0.5, trigger_center), "size": Vector3(len, wall_height, trigger_thickness)},
		{"pos": Vector3(-trigger_center, wall_height * 0.5, 0), "size": Vector3(trigger_thickness, wall_height, len)},
		{"pos": Vector3(trigger_center, wall_height * 0.5, 0), "size": Vector3(trigger_thickness, wall_height, len)},
	]

	var zone_script := preload("res://scripts/arena/escape_zone.gd")

	for def in zone_defs:
		var zone := Area3D.new()
		zone.name = "EscapeZone"
		zone.add_to_group("escape_zone")
		zone.set_script(zone_script)
		zone.position = def["pos"]

		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = def["size"]
		collision.shape = shape
		zone.add_child(collision)

		# Physical barrier for ENEMIES only: the glow wall itself is a purely
		# visual slab the player walks straight through (so the retreat hold is
		# reachable), but chasing enemies must not be able to follow the player
		# out of the arena through it. The barrier sits exactly where the glow
		# wall is drawn (the zone's center) on layer 32 — the player's mask
		# (1+2) ignores it, while enemies (mask 3|32) are stopped by it.
		var barrier := StaticBody3D.new()
		barrier.name = "RetreatWallBarrier"
		barrier.collision_layer = 32
		barrier.collision_mask = 0
		barrier.position = def["pos"]

		var bcol := CollisionShape3D.new()
		var bshape := BoxShape3D.new()
		var dsize: Vector3 = def["size"]
		# Slim slab matching the visible glow wall (thin axis capped at 1.5m).
		if dsize.z < dsize.x:
			bshape.size = Vector3(dsize.x, dsize.y, 1.5)
		else:
			bshape.size = Vector3(1.5, dsize.y, dsize.z)
		bcol.shape = bshape
		barrier.add_child(bcol)
		escape_zone_container.add_child(barrier)

		escape_zone_container.add_child(zone)


# Invisible safety frame just past the escape apron so the player (and enemies)
# can't walk off the edge of the ground and fall into the void. It sits BEYOND
# the apron (inner face = half + apron depth + 0.5), leaving a real strip of
# solid ground behind the retreat wall to stand on.
func _create_void_barrier() -> void:
	var half := arena_size / 2.0
	var len := arena_size + (ESCAPE_APRON_DEPTH + 2.0) * 2.0
	var barrier_pos := half + ESCAPE_APRON_DEPTH + 1.5
	var thickness := 2.0
	var height := 6.0

	var barrier_defs = [
		{"pos": Vector3(0, height * 0.5, -barrier_pos), "size": Vector3(len, height, thickness)},
		{"pos": Vector3(0, height * 0.5, barrier_pos), "size": Vector3(len, height, thickness)},
		{"pos": Vector3(-barrier_pos, height * 0.5, 0), "size": Vector3(thickness, height, len)},
		{"pos": Vector3(barrier_pos, height * 0.5, 0), "size": Vector3(thickness, height, len)},
	]

	for def in barrier_defs:
		var barrier := StaticBody3D.new()
		barrier.name = "VoidBarrier"
		barrier.collision_layer = 2
		barrier.collision_mask = 0

		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = def["size"]
		collision.shape = shape
		barrier.add_child(collision)

		barrier.position = def["pos"]
		escape_zone_container.add_child(barrier)


# Walkable ground OUTSIDE the arena edge — the strip between the battlefield
# and the void barrier. Without it the retreat light wall sat at the edge of
# the floor: the player's feet ran out of ground right at the wall and the
# void barrier (only ~1m behind it) blocked the rest, so walking into the
# retreat behaved exactly like hitting a solid wall. Now the ground continues
# past the wall, so the player walks straight through it and stands behind it
# while the escape hold charges.
func _add_escape_apron() -> void:
	var half := arena_size / 2.0
	var depth := ESCAPE_APRON_DEPTH
	var top_y := _apron_top_y()

	var body := StaticBody3D.new()
	body.name = "EscapeApron"
	body.collision_layer = 2
	body.collision_mask = 1

	# Dark packed-dirt look: reads as "outside the battlefield", distinct
	# from the themed ground inside the walls.
	var apron_mat := StandardMaterial3D.new()
	apron_mat.albedo_color = Color(0.16, 0.15, 0.13)
	apron_mat.roughness = 0.95

	# North/south slabs run the FULL width (covering the corners); east/west
	# slabs cover the edge strips between the corners.
	var defs = [
		{"pos": Vector3(0, 0, half + depth * 0.5), "size": Vector3(arena_size + depth * 2.0, 0.8, depth)},
		{"pos": Vector3(0, 0, -half - depth * 0.5), "size": Vector3(arena_size + depth * 2.0, 0.8, depth)},
		{"pos": Vector3(half + depth * 0.5, 0, 0), "size": Vector3(depth, 0.8, arena_size)},
		{"pos": Vector3(-half - depth * 0.5, 0, 0), "size": Vector3(depth, 0.8, arena_size)},
	]
	for def in defs:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = def["size"]
		col.shape = shape
		col.position = def["pos"] + Vector3(0, top_y - 0.4, 0)
		body.add_child(col)

		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = def["size"]
		mesh.mesh = box
		mesh.material_override = apron_mat
		mesh.position = def["pos"] + Vector3(0, top_y - 0.4, 0)
		body.add_child(mesh)

	structures_container.add_child(body)


# Height of the walkable apron beyond the arena edge, matched to each theme's
# ground surface so stepping out of the field is flush (no invisible step).
func _apron_top_y() -> float:
	match current_theme:
		BiomeTheme.RIVER_BRIDGE:
			return 0.35
		BiomeTheme.FOREST, BiomeTheme.FOREST_ROAD:
			return 0.0
		_:
			return -0.39


# ====================================================================
# MAP STRUCTURAL THEMES
# ====================================================================

func _create_theme_structures() -> void:
	match current_theme:
		BiomeTheme.DESERT:
			_generate_randomized_desert_dunes()
		BiomeTheme.CITY_HIGHRISE:
			_build_city_highrise_structures()
		BiomeTheme.CROSSROADS:
			_build_crossroads_structures()
		BiomeTheme.RIVER_BRIDGE:
			_build_river_bridge_structures()
		BiomeTheme.FOREST, BiomeTheme.FOREST_ROAD:
			_build_forest_structures()


func _build_desert_structures() -> void:
	_generate_randomized_desert_dunes()


func _generate_randomized_desert_dunes() -> void:
	var half = arena_size / 2.0 - 25.0
	var dune_count = randi_range(12, 20)
	
	var sand_mat = StandardMaterial3D.new()
	sand_mat.albedo_color = Color(0.82, 0.65, 0.38)
	sand_mat.roughness = 0.85
	
	var rock_mat = StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.45, 0.38, 0.30)
	rock_mat.roughness = 0.9
	
	for i in range(dune_count):
		# Random position away from center (keep central area 60% flat & open)
		var angle = randf_range(0, TAU)
		var dist = randf_range(35.0, half)
		var pos_x = cos(angle) * dist
		var pos_z = sin(angle) * dist
		
		var dune = StaticBody3D.new()
		dune.collision_layer = 2
		dune.collision_mask = 1
		
		var width = randf_range(20.0, 45.0)
		var length = randf_range(14.0, 32.0)
		var height = randf_range(2.5, 5.5)
		
		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(width, height, length)
		collision.shape = shape
		dune.add_child(collision)
		
		var mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(width, height, length)
		mesh_inst.mesh = box
		mesh_inst.material_override = sand_mat
		dune.add_child(mesh_inst)
		
		dune.rotation.y = randf_range(0, TAU)
		dune.rotation.x = deg_to_rad(randf_range(-5.0, 5.0))
		dune.position = Vector3(pos_x, height / 2.0 - 0.2, pos_z)
		
		# Solid obstacle: the player must never spawn inside its footprint.
		dune.add_to_group("solid_obstacle")
		structures_container.add_child(dune)
		
		# 35% chance to spawn a rock outcrop / ancient desert structure on the dune
		if randf() < 0.35:
			_spawn_desert_outcrop(dune.position + Vector3(randf_range(-4, 4), height / 2.0, randf_range(-4, 4)), rock_mat)

func _spawn_desert_outcrop(pos: Vector3, rock_mat: StandardMaterial3D) -> void:
	var rock = StaticBody3D.new()
	rock.collision_layer = 2
	rock.collision_mask = 1
	
	var r_size = Vector3(randf_range(4.0, 9.0), randf_range(3.0, 8.0), randf_range(4.0, 9.0))
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = r_size
	rock.add_child(collision)
	
	var mesh_inst = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = r_size
	mesh_inst.mesh = box
	mesh_inst.material_override = rock_mat
	rock.add_child(mesh_inst)
	
	rock.rotation.y = randf_range(0, TAU)
	rock.rotation.z = deg_to_rad(randf_range(-12, 12))
	rock.position = pos
	rock.add_to_group("solid_obstacle")
	structures_container.add_child(rock)


func _build_city_highrise_structures() -> void:
	# Grid of skyscraper building blocks, but never the same city twice: a
	# seeded roll decides which cells actually rise (and how tall), so two
	# battles in the highrise never look identical.
	var b_coords = [-70.0, -35.0, 35.0, 70.0]
	for bx in b_coords:
		for bz in b_coords:
			if absf(bx) < 20.0 and absf(bz) < 20.0:
				continue # Clear spawn area
			# ~78% fill: some cells stay as empty lots/parks.
			if randf() < 0.22:
				continue
			var b_height = randf_range(25.0, 45.0)
			var building = StaticBody3D.new()
			building.collision_layer = 2
			building.collision_mask = 1

			var footprint = randf_range(15.0, 24.0)
			var collision = CollisionShape3D.new()
			var shape = BoxShape3D.new()
			shape.size = Vector3(footprint, b_height, footprint)
			collision.shape = shape
			collision.position.y = b_height / 2.0
			building.add_child(collision)

			var mesh = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(footprint, b_height, footprint)
			mesh.mesh = box
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(randf_range(0.12, 0.18), randf_range(0.15, 0.22), randf_range(0.20, 0.28))
			mat.metallic = 0.3
			mat.roughness = 0.5
			mesh.material_override = mat
			building.add_child(mesh)

			# Slight random offset so blocks don't sit in a rigid grid.
			building.position = Vector3(bx + randf_range(-4, 4), 0, bz + randf_range(-4, 4))
			building.add_to_group("concealment")
			building.add_to_group("solid_obstacle")
			structures_container.add_child(building)


func _build_crossroads_structures() -> void:
	# 4-way urban intersection with corner building blocks — but never the same
	# crossroads twice. A random pick decides whether the intersection is framed
	# by 2, 3, or all 4 corner blocks, and each block varies in size/position.
	var corners = [
		Vector3(-55, 0, -55), Vector3(55, 0, -55),
		Vector3(-55, 0, 55), Vector3(55, 0, 55)
	]
	corners.shuffle()
	var block_count := randi_range(2, 4)
	for i in range(block_count):
		var pos = corners[i]
		var b_height = randf_range(28.0, 52.0)
		var footprint = randf_range(38.0, 54.0)
		var block = StaticBody3D.new()
		block.collision_layer = 2
		block.collision_mask = 1

		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(footprint, b_height, footprint)
		collision.shape = shape
		collision.position.y = b_height / 2.0
		block.add_child(collision)

		var mesh = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(footprint, b_height, footprint)
		mesh.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(randf_range(0.10, 0.15), randf_range(0.12, 0.17), randf_range(0.18, 0.24))
		mat.metallic = 0.4
		mat.roughness = 0.4
		mesh.material_override = mat
		block.add_child(mesh)

		block.position = pos + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
		block.add_to_group("concealment")
		block.add_to_group("solid_obstacle")
		structures_container.add_child(block)


func _build_river_bridge_structures() -> void:
	# 1. Submerged riverbed floor so mechs can wade through the water trench
	_spawn_riverbed_floor()

	# 2. Water trench as TALL passable volumes (Z = -20 to 20), split around the
	#    bridge strips so standing on a bridge never counts as "in water".
	#    Center bridge spans X in [-15, 15]; flanking bridges at X = +-75 (width 15).
	var water_mat = _create_water_material()
	var center_bridge_half = 15.0
	var flank_center_x = 75.0
	var flank_bridge_half = 7.5
	var half = arena_size / 2.0
	var water_x_ranges = [
		[-half, -flank_center_x - flank_bridge_half],
		[-flank_center_x + flank_bridge_half, -center_bridge_half],
		[center_bridge_half, flank_center_x - flank_bridge_half],
		[flank_center_x + flank_bridge_half, half],
	]
	for x_range in water_x_ranges:
		var x0: float = x_range[0]
		var x1: float = x_range[1]
		var width: float = x1 - x0
		if width <= 0.0:
			continue
		_spawn_water_volume((x0 + x1) * 0.5, width, water_mat)

	# 3. Main Center Steel Bridge Crossing (X = -20 to 20, Z = -25 to 25)
	var bridge = StaticBody3D.new()
	bridge.collision_layer = 2
	bridge.collision_mask = 1

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(30, 1.0, 52)
	collision.shape = shape
	collision.position.y = 0.0
	bridge.add_child(collision)

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(30, 1.0, 52)
	mesh.mesh = box
	var bridge_mat = StandardMaterial3D.new()
	bridge_mat.albedo_color = Color(0.35, 0.38, 0.42)
	bridge_mat.metallic = 0.7
	bridge_mat.roughness = 0.4
	mesh.material_override = bridge_mat
	bridge.add_child(mesh)

	# Steel Bridge Side Girders
	for side in [-15.0, 15.0]:
		var girder = MeshInstance3D.new()
		var g_mesh = BoxMesh.new()
		g_mesh.size = Vector3(1.2, 8.0, 52.0)
		girder.mesh = g_mesh
		var g_mat = StandardMaterial3D.new()
		g_mat.albedo_color = Color(0.7, 0.25, 0.15) # Rusted Red Truss Steel
		g_mat.metallic = 0.6
		girder.material_override = g_mat
		girder.position = Vector3(side, 4.0, 0)
		bridge.add_child(girder)

	bridge.position = Vector3(0, 0, 0)
	structures_container.add_child(bridge)

	# 4. Flanking Side Bridges (East and West)
	for flank_x in [-75.0, 75.0]:
		var f_bridge = StaticBody3D.new()
		f_bridge.collision_layer = 2
		f_bridge.collision_mask = 1

		var f_collision = CollisionShape3D.new()
		var f_shape = BoxShape3D.new()
		f_shape.size = Vector3(15, 1.0, 52)
		f_collision.shape = f_shape
		f_collision.position.y = 0.0
		f_bridge.add_child(f_collision)

		var f_mesh = MeshInstance3D.new()
		var f_box = BoxMesh.new()
		f_box.size = Vector3(15, 1.0, 52)
		f_mesh.mesh = f_box
		f_mesh.material_override = bridge_mat
		f_bridge.add_child(f_mesh)

		f_bridge.position = Vector3(flank_x, 0, 0)
		structures_container.add_child(f_bridge)


func _spawn_riverbed_floor() -> void:
	var floor_body = StaticBody3D.new()
	floor_body.collision_layer = 2
	floor_body.collision_mask = 1

	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(arena_size, 0.6, 40)
	col.shape = shape
	floor_body.add_child(col)

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.25, 0.30)
	mat.roughness = 0.9
	mesh.material_override = mat
	floor_body.add_child(mesh)

	floor_body.position = Vector3(0, -1.5, 0)
	structures_container.add_child(floor_body)


func _create_water_material() -> ShaderMaterial:
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 water_color : source_color = vec4(0.15, 0.6, 1.0, 0.62);
uniform float wave_speed : hint_range(0, 10) = 2.5;
uniform float wave_strength : hint_range(0, 0.5) = 0.06;
uniform float emission_energy = 1.6;

void vertex() {
	UV *= 8.0;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 uv = UV;
	uv.y += t;
	uv.y += sin(uv.x * 6.0 + t) * wave_strength;
	ALBEDO = water_color.rgb;
	ALPHA = water_color.a;
	EMISSION = vec3(0.1, 0.4, 0.9) * emission_energy;
	ROUGHNESS = 0.1;
	METALLIC = 0.3;
}
"""
	mat.shader = shader
	return mat


# Spawns a passable water volume tagged as a water volume.
# The DETECTION box is a tall, invisible volume so a wading mech (feet down in
# the trench) is counted as "in water". The VISUAL is a thin, flat sheet sunk
# below the riverbanks and bridge deck — water must sit lower than the ground
# and lower than the bridge, never as a tall cube rising above them.
func _spawn_water_volume(center_x: float, width: float, mat: Material) -> void:
	var area = Area3D.new()
	area.name = "WaterVolume"
	area.collision_layer = 4
	area.collision_mask = 0
	area.monitoring = true
	area.add_to_group("water_volume")

	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(width, 2.6, 40)
	col.shape = shape
	area.add_child(col)

	# Visual: thin low sheet so the water reads as a sunken surface, well below
	# the riverbank ground (top ~ +0.5) and the bridge deck (top ~ +0.5), but
	# high enough above the riverbed (top ~ -1.2) to read as flowing water.
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(width, 0.3, 40)
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position.y = -0.55
	area.add_child(mesh)

	area.position = Vector3(center_x, -0.9, 0)
	structures_container.add_child(area)


# ====================================================================
# FOREST BIOME (ป่า: trees, streams, waterfall, rocks, grassland)
# ====================================================================

# Height of the forest terrain at a world position. Returns
# FOREST_RIVER_STRIP_Y on the river strip (which includes the center spawn
# pocket — the shallow stream runs straight through the map), 0 inside open
# fields, and gentle noise-driven hills (max ~3m) on the banks. Hills ramp in
# smoothly off the flat pockets and flatten back down near the arena walls so
# the spawn ring and the escape frame both sit on level ground.
# Y of the flat central band. FOREST keeps the sunken river strip;
# FOREST_ROAD raises it to a level dirt/asphalt road surface.
func _forest_strip_y() -> float:
	return 0.0 if current_theme == BiomeTheme.FOREST_ROAD else FOREST_RIVER_STRIP_Y


func _forest_terrain_height(wx: float, wz: float) -> float:
	_ensure_forest_fields()
	var nx := absf(wx)
	var nz := absf(wz)
	var half := arena_size / 2.0
	var strip_y := _forest_strip_y()
	# River strip (|z| < 24) is the flat surface — the player and the spawn
	# ring start on it, so it never rolls.
	if nz <= 24.0:
		return strip_y
	# Smoothly lift off the river bank and out of the spawn pocket...
	var river_ramp := clampf((nz - 24.0) / 10.0, 0.0, 1.0)
	var pocket_ramp := clampf((maxf(nx, nz) - 18.0) / 22.0, 0.0, 1.0)
	var rise := minf(river_ramp, pocket_ramp)
	var base := lerpf(strip_y, 0.0, river_ramp)
	# ...and flatten back down near the arena walls (escape frame sits flush).
	var rim := clampf((half - maxf(nx, nz)) / 26.0, 0.0, 1.0)
	if rise <= 0.0 or rim <= 0.0:
		return base
	# Open fields are flat meadows: blend the base up to 0 and fade the hills
	# out across the field edge so clearings never end in a cliff.
	var field_mask := _forest_field_mask(wx, wz)
	var field_flat := 1.0 - field_mask
	if field_flat >= 1.0:
		return 0.0
	var h := terrain_noise.get_noise_2d(wx, wz) * 0.72
	h += terrain_noise.get_noise_2d(wx * 2.3 + 31.7, wz * 2.3 - 12.4) * 0.28
	return lerpf(base, 0.0, field_flat) + h * 4.0 * rise * rim * field_mask


# 0 inside an open field, 1 outside. The ring is ramped over 8m so meadow
# edges blend into the surrounding forest instead of forming a step.
func _forest_field_mask(wx: float, wz: float) -> float:
	_ensure_forest_fields()
	var mask := 1.0
	for f in _forest_fields:
		var center: Vector2 = f["center"]
		var radius := float(f["radius"])
		var dist := Vector2(wx, wz).distance_to(center)
		mask = minf(mask, clampf((dist - radius) / 8.0, 0.0, 1.0))
	return mask


func _is_open_field(wx: float, wz: float) -> bool:
	return _forest_field_mask(wx, wz) < 0.5


# Builds the open-field blobs once per arena. Seeded from the board seed so the
# same map always clears the same meadows, while different boards (and thus
# different combat encounters) get different field layouts.
func _ensure_forest_fields() -> void:
	if _forest_fields_ready:
		return
	_forest_fields_ready = true
	var seed_base := 20260814 + maxi(int(GlobalData.board_seed), 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_base
	# ~33m wavelength so the hills actually roll across the field (the default
	# 0.01 frequency at unscaled coords would take ~6km per feature).
	terrain_noise.seed = seed_base + 7
	terrain_noise.frequency = 0.03
	var half := arena_size / 2.0
	for i in range(3):
		var angle := (i / 3.0) * TAU + rng.randf_range(-0.45, 0.45)
		var radius := rng.randf_range(0.42, 0.72) * half
		var cx := cos(angle) * radius
		var cz := sin(angle) * radius
		# Keep fields on dry land, clear of the river strip and the center pocket.
		if absf(cz) < 34.0:
			cz = 34.0 * (1.0 if cz >= 0.0 else -1.0)
		if absf(cx) < 22.0 and absf(cz) < 22.0:
			cx = 22.0 * (1.0 if cx >= 0.0 else -1.0)
		var field_radius := rng.randf_range(0.26, 0.40) * half
		_forest_fields.append({"center": Vector2(cx, cz), "radius": field_radius})


func _build_forest_structures() -> void:
	# 1. A wide river cut across the map (Z band) with banks of mossy ground;
	#    the road-through-forest variant lays a packed-dirt road there instead.
	if current_theme == BiomeTheme.FOREST_ROAD:
		_spawn_forest_road()
	else:
		_spawn_forest_river()

	# 2. Scattered trees of varied size (tall/short, thick/thin) + rocks + logs.
	#    Open fields stay clear of cover so they read as meadows, and every
	#    prop is planted on the terrain surface so slopes never bury them.
	var half = arena_size / 2.0 - 15.0
	var tree_count := randi_range(60, 80)
	for i in range(tree_count):
		var x = randf_range(-half, half)
		var z = randf_range(-half, half)
		if absf(x) < 15.0 and absf(z) < 15.0:
			continue # Keep spawn area clear
		if absf(z) < 24.0:
			continue # Keep the central road/river clear
		var ground_y := _forest_terrain_height(x, z)
		# Only a truly flat meadow (field interior) counts as an open field — the
		# 8m fade ramp around each field still rolls, so a flower/grass tuft there
		# would sit on a slope instead of the flat clearing.
		if _is_open_field(x, z) and absf(ground_y) < 0.05:
			# Meadows keep sightlines open; only a few tufts of tall grass
			# and the odd flower patch.
			var field_roll := randf()
			if field_roll < 0.3:
				_spawn_grass_patch(Vector3(x, ground_y, z))
			elif field_roll < 0.42:
				_spawn_flower_patch(Vector3(x, ground_y, z))
			continue
		var roll := randf()
		if roll < 0.68:
			_spawn_forest_tree(Vector3(x, ground_y, z))
		elif roll < 0.82:
			_spawn_fallen_log(Vector3(x, ground_y, z))
		elif roll < 0.94:
			_spawn_forest_rock(Vector3(x, ground_y, z))
		else:
			_spawn_grass_patch(Vector3(x, ground_y, z))

	# 3. Dot the open fields with meadow grass, flower patches, and fallen
	#    leaves so they read as lived-in clearings instead of bare dirt.
	_ensure_forest_fields()
	for f in _forest_fields:
		var center: Vector2 = f["center"]
		var radius := float(f["radius"])
		for i in range(12):
			var gx := center.x + randf_range(-radius * 0.75, radius * 0.75)
			var gz := center.y + randf_range(-radius * 0.75, radius * 0.75)
			if absf(gz) < 26.0:
				continue
			var ground_pos := Vector3(gx, _forest_terrain_height(gx, gz), gz)
			var roll := randf()
			if roll < 0.45:
				_spawn_grass_patch(ground_pos)
			elif roll < 0.70:
				_spawn_flower_patch(ground_pos)
			else:
				_spawn_fallen_leaves(ground_pos)


func _spawn_forest_road() -> void:
	# Packed-dirt road band cutting across the forest (|z| < 24): a passable
	# flat surface at y=0 (the strip plane + heightmap already sit there), with
	# a slightly darker worn lane and edge shoulders so it reads as a road
	# cutting through the woods rather than a bare strip of dirt.
	var half := arena_size / 2.0

	var road := StaticBody3D.new()
	road.name = "ForestRoad"
	road.collision_layer = 2
	road.collision_mask = 1

	# Passable floor across the whole band (meets the bank heightmap at |z|=24).
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(arena_size, 0.5, 48)
	col.shape = shape
	road.add_child(col)

	# Visual: a thin worn-dirt slab slightly above the collision top so the
	# strip reads as a raised packed road.
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(arena_size, 0.25, 46)
	mesh.mesh = box
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.28, 0.25, 0.18)
	road_mat.roughness = 0.95
	mesh.material_override = road_mat
	mesh.position.y = 0.02
	road.add_child(mesh)

	# Wheel-rut lanes: two darker parallel strips.
	for lane_x in [-6.0, 6.0]:
		var lane := MeshInstance3D.new()
		var lane_box := BoxMesh.new()
		lane_box.size = Vector3(0.6, 0.26, 46)
		lane.mesh = lane_box
		var lane_mat := StandardMaterial3D.new()
		lane_mat.albedo_color = Color(0.18, 0.16, 0.12)
		lane_mat.roughness = 1.0
		lane.material_override = lane_mat
		lane.position = Vector3(lane_x, 0.03, 0)
		road.add_child(lane)

	road.position = Vector3(0, -0.25, 0)
	structures_container.add_child(road)


func _spawn_forest_river() -> void:
	# Wide river trench (Z from -22 to 22) with the same passable water-volume
	# technique as the river bridge map: mechs can wade, water stays sunken.
	_spawn_forest_riverbed_floor()

	var water_mat := _create_water_material()
	var half := arena_size / 2.0

	var river_band := StaticBody3D.new()
	river_band.name = "Riverband"
	river_band.collision_layer = 2
	river_band.collision_mask = 1

	# Shallow water floor (passable) across the whole band. Spans |z| < 24 so it
	# meets the bank heightmap collision (which starts at |z| = 24) flush — a
	# narrower band would leave a collision gap mechs fall through at the edge.
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(arena_size, 0.5, 48)
	col.shape = shape
	river_band.add_child(col)

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(arena_size, 0.3, 44)
	mesh.mesh = box
	mesh.material_override = water_mat
	mesh.position.y = -0.5
	river_band.add_child(mesh)

	river_band.position = Vector3(0, -0.6, 0)
	structures_container.add_child(river_band)

	# 2. Waterfall on the west edge feeding the river.
	_spawn_waterfall(water_mat, -half + 8.0)


func _spawn_forest_riverbed_floor() -> void:
	var floor_body = StaticBody3D.new()
	floor_body.collision_layer = 2
	floor_body.collision_mask = 1

	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(arena_size, 0.6, 42)
	col.shape = shape
	floor_body.add_child(col)

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(arena_size, 0.6, 42)
	mesh.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.20, 0.16)
	mat.roughness = 0.9
	mesh.material_override = mat
	floor_body.add_child(mesh)

	floor_body.position = Vector3(0, -1.4, 0)
	structures_container.add_child(floor_body)


func _spawn_waterfall(water_mat: Material, pos_x: float) -> void:
	var falls = Area3D.new()
	falls.name = "Waterfall"
	falls.collision_layer = 4
	falls.collision_mask = 0
	falls.add_to_group("water_volume")

	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(10, 14, 10)
	col.shape = shape
	falls.add_child(col)

	var sheet = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(10, 14, 0.8)
	sheet.mesh = box
	var sheet_mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
uniform vec4 water_color : source_color = vec4(0.55, 0.85, 1.0, 0.85);
uniform float wave_speed : hint_range(0, 10) = 4.0;
uniform float wave_strength : hint_range(0, 0.5) = 0.1;
void vertex() {
	UV *= 4.0;
}
void fragment() {
	float t = TIME * wave_speed;
	vec2 uv = UV;
	uv.y += t;
	uv.y += sin(uv.x * 8.0 + t) * wave_strength;
	ALBEDO = water_color.rgb;
	ALPHA = water_color.a;
	EMISSION = vec3(0.4, 0.7, 1.0) * 0.6;
	ROUGHNESS = 0.1;
	METALLIC = 0.3;
}
"""
	sheet_mat.shader = shader
	sheet.material_override = sheet_mat
	sheet.position = Vector3(pos_x, 5.0, 0)
	falls.add_child(sheet)

	# Spray mist at the base of the falls.
	var mist = MeshInstance3D.new()
	var mist_mesh = BoxMesh.new()
	mist_mesh.size = Vector3(8, 1.2, 8)
	mist.mesh = mist_mesh
	var mist_mat = StandardMaterial3D.new()
	mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist_mat.albedo_color = Color(0.9, 0.95, 1.0, 0.35)
	mist.material_override = mist_mat
	mist.position = Vector3(pos_x, 0.6, 0)
	falls.add_child(mist)

	falls.position = Vector3(0, 0, 0)
	structures_container.add_child(falls)


func _spawn_forest_tree(pos: Vector3) -> void:
	var trunk_h = randf_range(4.0, 10.0)   # tall / short
	var trunk_r = randf_range(0.5, 1.1)    # thick / thin
	var tree = StaticBody3D.new()
	tree.collision_layer = 2
	tree.collision_mask = 1

	var collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = trunk_r
	shape.height = trunk_h
	collision.shape = shape
	collision.position.y = trunk_h * 0.5
	tree.add_child(collision)

	var trunk = MeshInstance3D.new()
	var trunk_mesh = CylinderMesh.new()
	trunk_mesh.top_radius = trunk_r * 0.7
	trunk_mesh.bottom_radius = trunk_r
	trunk_mesh.height = trunk_h
	trunk.mesh = trunk_mesh
	var trunk_mat = StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.34, 0.22, 0.12)
	trunk_mat.roughness = 0.9
	trunk.material_override = trunk_mat
	trunk.position.y = trunk_h * 0.5
	tree.add_child(trunk)

	# 2-3 layered canopies.
	var leaf_mat = StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(randf_range(0.10, 0.18), randf_range(0.32, 0.46), randf_range(0.10, 0.16))
	leaf_mat.roughness = 1.0
	var layers = randi_range(2, 3)
	for l in range(layers):
		var layer = MeshInstance3D.new()
		var layer_mesh = CylinderMesh.new()
		var lr = trunk_r * (2.6 + l * 0.6)
		var lh = trunk_r * (2.0 + l * 0.5)
		layer_mesh.top_radius = lr * 0.4
		layer_mesh.bottom_radius = lr
		layer_mesh.height = lh
		layer.mesh = layer_mesh
		layer.material_override = leaf_mat
		layer.position.y = trunk_h - lh * 0.5 + l * lh * 0.55
		tree.add_child(layer)

	tree.position = pos
	tree.add_to_group("concealment")
	tree.add_to_group("solid_obstacle")
	structures_container.add_child(tree)


func _spawn_fallen_log(pos: Vector3) -> void:
	var log = StaticBody3D.new()
	log.collision_layer = 2
	log.collision_mask = 1

	var len = randf_range(5.0, 10.0)
	var r = randf_range(0.6, 1.2)

	var collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = r
	shape.height = len
	collision.shape = shape
	collision.rotation_degrees.x = 90.0
	log.add_child(collision)

	var body = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r * 1.1
	mesh.height = len
	body.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.20, 0.10)
	mat.roughness = 1.0
	body.material_override = mat
	body.rotation_degrees.x = 90.0
	log.add_child(body)

	log.position = pos + Vector3(0, r * 0.5, 0)
	log.rotation.y = randf_range(0, TAU)
	log.add_to_group("solid_obstacle")
	structures_container.add_child(log)


func _spawn_forest_rock(pos: Vector3) -> void:
	var rock = StaticBody3D.new()
	rock.collision_layer = 2
	rock.collision_mask = 1

	var size = Vector3(randf_range(1.5, 3.5), randf_range(1.2, 2.8), randf_range(1.5, 3.5))
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position.y = size.y * 0.5
	rock.add_child(collision)

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.34, 0.36)
	mat.roughness = 1.0
	mesh.material_override = mat
	mesh.position.y = size.y * 0.5
	rock.add_child(mesh)

	rock.position = pos
	rock.rotation.y = randf_range(0, TAU)
	rock.add_to_group("solid_obstacle")
	structures_container.add_child(rock)


func _spawn_grass_patch(pos: Vector3) -> void:
	var patch = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	var r = randf_range(0.8, 1.6)
	mesh.radius = r
	mesh.height = r * 1.4
	patch.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.40, 0.16)
	mat.roughness = 1.0
	patch.material_override = mat
	patch.position = pos + Vector3(0, r * 0.5, 0)
	structures_container.add_child(patch)


# A small cluster of tall meadow flowers (green stems + pastel heads) for the
# open fields. Purely decorative — no collision, like the grass patches.
func _spawn_flower_patch(pos: Vector3) -> void:
	var patch := Node3D.new()
	patch.name = "FlowerPatch%d" % _forest_decor_seq
	_forest_decor_seq += 1
	var head_colors := [
		Color(0.95, 0.55, 0.75),  # pink
		Color(0.95, 0.95, 0.90),  # white
		Color(0.95, 0.85, 0.30),  # yellow
		Color(0.70, 0.50, 0.85),  # violet
		Color(0.85, 0.30, 0.30),  # red
	]
	var count := randi_range(4, 7)
	for i in range(count):
		var ox := randf_range(-1.4, 1.4)
		var oz := randf_range(-1.4, 1.4)
		var stem_h := randf_range(0.7, 1.3)

		var stem := MeshInstance3D.new()
		var stem_mesh := CylinderMesh.new()
		stem_mesh.top_radius = 0.05
		stem_mesh.bottom_radius = 0.06
		stem_mesh.height = stem_h
		stem.mesh = stem_mesh
		var stem_mat := StandardMaterial3D.new()
		stem_mat.albedo_color = Color(0.22, 0.45, 0.18)
		stem_mat.roughness = 1.0
		stem.material_override = stem_mat
		stem.position = Vector3(ox, stem_h * 0.5, oz)
		patch.add_child(stem)

		var head := MeshInstance3D.new()
		var head_mesh := SphereMesh.new()
		var hr := randf_range(0.16, 0.34)
		head_mesh.radius = hr
		head_mesh.height = hr * 1.3
		head.mesh = head_mesh
		var head_mat := StandardMaterial3D.new()
		head_mat.albedo_color = head_colors[randi() % head_colors.size()]
		head_mat.roughness = 0.9
		head.material_override = head_mat
		head.position = Vector3(ox, stem_h + hr * 0.45, oz)
		patch.add_child(head)
	patch.position = pos
	structures_container.add_child(patch)


# A scatter of fallen autumn leaves (thin flat discs) for the open fields.
func _spawn_fallen_leaves(pos: Vector3) -> void:
	var patch := Node3D.new()
	patch.name = "FallenLeaves%d" % _forest_decor_seq
	_forest_decor_seq += 1
	var leaf_colors := [
		Color(0.85, 0.45, 0.15),  # orange
		Color(0.75, 0.25, 0.20),  # red
		Color(0.80, 0.70, 0.25),  # yellow
		Color(0.50, 0.35, 0.15),  # brown
	]
	var count := randi_range(6, 10)
	for i in range(count):
		var leaf := MeshInstance3D.new()
		var leaf_mesh := CylinderMesh.new()
		var lr := randf_range(0.14, 0.30)
		leaf_mesh.top_radius = lr
		leaf_mesh.bottom_radius = lr
		leaf_mesh.height = 0.02
		leaf.mesh = leaf_mesh
		var leaf_mat := StandardMaterial3D.new()
		leaf_mat.albedo_color = leaf_colors[randi() % leaf_colors.size()]
		leaf_mat.roughness = 1.0
		leaf.material_override = leaf_mat
		leaf.position = Vector3(randf_range(-1.8, 1.8), 0.01, randf_range(-1.8, 1.8))
		leaf.rotation.x = deg_to_rad(randf_range(-10.0, 10.0))
		leaf.rotation.z = deg_to_rad(randf_range(-10.0, 10.0))
		leaf.rotation.y = randf_range(0, TAU)
		patch.add_child(leaf)
	patch.position = pos
	structures_container.add_child(patch)
