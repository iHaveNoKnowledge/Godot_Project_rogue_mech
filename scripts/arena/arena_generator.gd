extends Node3D

## Generates procedural combat maps: Desert, Skyscraper City, Urban Crossroads, and River Bridge.

@export var arena_size: float = 240.0
@export var tile_count: int = 24

enum BiomeTheme { DESERT, CITY_HIGHRISE, CROSSROADS, RIVER_BRIDGE }

var current_theme: BiomeTheme = BiomeTheme.DESERT
var tile_container: Node3D
var escape_zone_container: Node3D
var structures_container: Node3D


func _ready() -> void:
	current_theme = randi() % BiomeTheme.size() as BiomeTheme
	generate_arena()


func generate_arena() -> void:
	_create_containers()
	_add_ground_tiles()
	_add_ground_collision()
	_create_escape_zones()
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


func _add_ground_tiles() -> void:
	var tile_size = arena_size / tile_count

	for x in range(tile_count):
		for z in range(tile_count):
			var pos_x = (x - tile_count / 2.0) * tile_size + tile_size / 2.0
			var pos_z = (z - tile_count / 2.0) * tile_size + tile_size / 2.0

			# Skip ground mesh inside river trench for RIVER_BRIDGE theme
			if current_theme == BiomeTheme.RIVER_BRIDGE and absf(pos_z) < 22.0:
				continue

			var tile = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(tile_size * 0.98, 0.1, tile_size * 0.98)
			tile.mesh = box

			var mat = StandardMaterial3D.new()
			var col = _get_theme_tile_color(x, z, pos_x, pos_z)
			mat.albedo_color = col
			mat.roughness = 0.8
			tile.material_override = mat

			var tile_y := -0.39
			if current_theme == BiomeTheme.RIVER_BRIDGE:
				tile_y = 0.45
			tile.position = Vector3(pos_x, tile_y, pos_z)
			tile_container.add_child(tile)


# The main walkable ground per theme. The global Ground in game_world.tscn is
# only a deep safety net now (top ~ -2.5), so each theme must build its own
# collision surface: a flat plane for most themes, and raised riverbanks for
# RIVER_BRIDGE so the water trench reads as a real sunken channel.
func _add_ground_collision() -> void:
	if current_theme == BiomeTheme.RIVER_BRIDGE:
		_add_riverbank_collision()
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


func _get_theme_tile_color(x: int, z: int, pos_x: float, pos_z: float) -> Color:
	var v = randf_range(-0.04, 0.04)
	match current_theme:
		BiomeTheme.DESERT:
			# Sand dunes yellow/amber
			return Color(0.62 + v, 0.50 + v, 0.32 + v)

		BiomeTheme.CITY_HIGHRISE:
			# Asphalt roads and concrete sidewalks
			if int(abs(pos_x)) % 40 < 12 or int(abs(pos_z)) % 40 < 12:
				return Color(0.18 + v, 0.19 + v, 0.22 + v) # Asphalt street
			return Color(0.40 + v, 0.42 + v, 0.45 + v) # Sidewalk

		BiomeTheme.CROSSROADS:
			# 4-way Urban Intersection
			if absf(pos_x) < 18.0 or absf(pos_z) < 18.0:
				if (absf(pos_x) < 1.0 or absf(pos_z) < 1.0):
					return Color(0.85 + v, 0.75 + v, 0.20 + v) # Yellow center lane lines
				return Color(0.15 + v, 0.16 + v, 0.18 + v) # Road asphalt
			return Color(0.45 + v, 0.45 + v, 0.48 + v) # Corner building sidewalk

		BiomeTheme.RIVER_BRIDGE:
			# Riverbanks and bridge access roads
			if absf(pos_z) < 32.0:
				return Color(0.35 + v, 0.32 + v, 0.28 + v) # Riverbank dirt
			return Color(0.22 + v, 0.24 + v, 0.26 + v) # Access road

	return Color(0.5, 0.5, 0.5)



func _create_escape_zones() -> void:
	var half := arena_size / 2.0
	var len := arena_size

	# Escape walls form a square frame of tall light walls around the arena's
	# outer edge — OUTSIDE the combat field (beyond the spawn ring and dunes,
	# just inside the void barrier) — so retreating never happens mid-fight.
	# They are tall walls, not flat floor strips.
	var wall_gap := 1.5
	var wall_thickness := 2.0
	var wall_height := 8.0
	var zone_defs = [
		{"pos": Vector3(0, wall_height * 0.5, -(half - wall_gap)), "size": Vector3(len, wall_height, wall_thickness)},
		{"pos": Vector3(0, wall_height * 0.5, (half - wall_gap)), "size": Vector3(len, wall_height, wall_thickness)},
		{"pos": Vector3(-(half - wall_gap), wall_height * 0.5, 0), "size": Vector3(wall_thickness, wall_height, len)},
		{"pos": Vector3((half - wall_gap), wall_height * 0.5, 0), "size": Vector3(wall_thickness, wall_height, len)},
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

		escape_zone_container.add_child(zone)


# Invisible safety frame just past the escape zones so the player (and enemies)
# can't walk off the edge of the ground plane and fall into the void.
func _create_void_barrier() -> void:
	var half := arena_size / 2.0
	var barrier_pos := half + 2.0
	var thickness := 2.0
	var height := 6.0

	var barrier_defs = [
		{"pos": Vector3(0, height * 0.5, -barrier_pos), "size": Vector3(arena_size + thickness * 2, height, thickness)},
		{"pos": Vector3(0, height * 0.5, barrier_pos), "size": Vector3(arena_size + thickness * 2, height, thickness)},
		{"pos": Vector3(-barrier_pos, height * 0.5, 0), "size": Vector3(thickness, height, arena_size + thickness * 2)},
		{"pos": Vector3(barrier_pos, height * 0.5, 0), "size": Vector3(thickness, height, arena_size + thickness * 2)},
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
	structures_container.add_child(rock)


func _build_city_highrise_structures() -> void:
	# Grid of skyscraper building blocks
	var b_coords = [-70.0, -35.0, 35.0, 70.0]
	for bx in b_coords:
		for bz in b_coords:
			if absf(bx) < 20.0 and absf(bz) < 20.0:
				continue # Clear spawn area
			var b_height = randf_range(25.0, 45.0)
			var building = StaticBody3D.new()
			building.collision_layer = 2
			building.collision_mask = 1

			var collision = CollisionShape3D.new()
			var shape = BoxShape3D.new()
			shape.size = Vector3(20, b_height, 20)
			collision.shape = shape
			collision.position.y = b_height / 2.0
			building.add_child(collision)

			var mesh = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(20, b_height, 20)
			mesh.mesh = box
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.15, 0.18, 0.24)
			mat.metallic = 0.3
			mat.roughness = 0.5
			mesh.material_override = mat
			building.add_child(mesh)

			building.position = Vector3(bx, 0, bz)
			structures_container.add_child(building)


func _build_crossroads_structures() -> void:
	# 4 Major corner skyscraper blocks surrounding 4-way intersection
	var corners = [
		Vector3(-55, 0, -55), Vector3(55, 0, -55),
		Vector3(-55, 0, 55), Vector3(55, 0, 55)
	]
	for pos in corners:
		var b_height = randf_range(30.0, 50.0)
		var block = StaticBody3D.new()
		block.collision_layer = 2
		block.collision_mask = 1

		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(50, b_height, 50)
		collision.shape = shape
		collision.position.y = b_height / 2.0
		block.add_child(collision)

		var mesh = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(50, b_height, 50)
		mesh.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.12, 0.14, 0.20)
		mat.metallic = 0.4
		mat.roughness = 0.4
		mesh.material_override = mat
		block.add_child(mesh)

		block.position = pos
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
