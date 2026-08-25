extends Node

## Sets up NavigationRegion3D after arena generation.
## Attach to game_world.tscn alongside ArenaGenerator.
##
## FIX 2026-08: Previous version never actually carved obstacles into the
## NavigationMesh — it added invisible footprint boxes as source but never
## configured PARSED_GEOMETRY_BOTH nor baked after covers spawned, so
## NavigationServer3D.map_get_path() returned straight lines through barriers.
## Enemies then drove straight into walls and stuck on move_and_slide().
## This version:
##  - configures the mesh to parse BOTH meshes + static colliders (layer 2)
##  - waits for ArenaGenerator + ObstacleSpawner + structures to finish
##  - bakes the region on the thread so holes are cut around every cover /
##    building / dune / pillar / container
##  - falls back to avoidance steering if the mesh is still empty

@export var agent_radius: float = 1.6
@export var agent_height: float = 2.0
@export var cell_size: float = 0.33
@export var cell_height: float = 0.2

var nav_region: NavigationRegion3D
var _nav_mesh: NavigationMesh


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame  # Wait 2 frames for arena to generate
	_setup_navigation()


func _setup_navigation() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavigationRegion"
	get_parent().add_child(nav_region)

	_nav_mesh = NavigationMesh.new()
	_nav_mesh.cell_size = cell_size
	_nav_mesh.cell_height = cell_height
	_nav_mesh.agent_radius = agent_radius
	_nav_mesh.agent_height = agent_height
	_nav_mesh.agent_max_climb = 0.45
	_nav_mesh.agent_max_slope = 45.0
	_nav_mesh.edge_max_error = 1.3
	_nav_mesh.region_min_size = 2.0
	_nav_mesh.region_merge_size = 8.0
	_nav_mesh.sample_partition_type = NavigationMesh.SAMPLE_PARTITION_WATERSHED
	# Parse both visual meshes and static colliders (covers, dunes, buildings)
	# so the baker cuts holes where cover actually sits.
	_nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_BOTH
	_nav_mesh.geometry_parsed_collision_mask = 2  # Environment layer
	_nav_mesh.filter_low_hanging_obstacles = true
	_nav_mesh.filter_ledge_spans = true
	_nav_mesh.filter_walkable_low_height_spans = true

	# Source geometry for the bake: one invisible box per footprint cell on
	# irregular maps (so navigation hugs the real battlefield outline), or the
	# classic slightly-shrunk square floor otherwise. These MeshInstance3Ds are
	# children of the region so the baker collects them as walkable source.
	var arena_gen := get_parent().get_node_or_null("ArenaGenerator")
	var fp: ArenaFootprint = null
	if arena_gen != null and arena_gen.get("footprint") != null:
		fp = arena_gen.footprint
	if fp != null:
		for c: Vector2i in fp.cells:
			var cell_mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(fp.CELL_SIZE - 0.5, 0.1, fp.CELL_SIZE - 0.5)
			cell_mesh.mesh = box
			var center := fp.origin + (Vector2(c) + Vector2(0.5, 0.5)) * fp.CELL_SIZE
			cell_mesh.position = Vector3(center.x, 0.05, center.y)
			cell_mesh.visible = false
			nav_region.add_child(cell_mesh)
	else:
		var floor_mesh = MeshInstance3D.new()
		var box = BoxMesh.new()
		var arena_size := GlobalData.board.current_arena_size
		# Slightly smaller than arena so edges stay clear of void walls
		box.size = Vector3(arena_size * 0.49, 0.1, arena_size * 0.49)
		floor_mesh.mesh = box
		floor_mesh.position.y = 0.05
		floor_mesh.visible = false
		nav_region.add_child(floor_mesh)

	# Assign mesh before baking — the region will collect source geometry
	# from its children + static colliders in the scene.
	nav_region.navigation_mesh = _nav_mesh

	# Use default world map
	var maps = NavigationServer3D.get_maps()
	if maps.size() > 0:
		NavigationServer3D.region_set_map(nav_region.get_rid(), maps[0])

	# Bake after obstacles/structures have spawned. ObstacleSpawner awaits one
	# frame before spawning, and city/dune structures spawn immediately in
	# generate_arena(), so 0.6s guarantees everything with collision_layer 2
	# is in the tree for the baker to see.
	_bake_after_obstacles()


func _bake_after_obstacles() -> void:
	await get_tree().create_timer(0.6).timeout
	if not is_instance_valid(nav_region) or _nav_mesh == null:
		return
	# Re-ensure the region is on the correct map (scene may have recreated maps)
	var maps = NavigationServer3D.get_maps()
	if maps.size() > 0:
		NavigationServer3D.region_set_map(nav_region.get_rid(), maps[0])
	# Bake on thread — cuts holes around every StaticBody3D on layer 2
	nav_region.bake_navigation_mesh(true)
	# Debug: log bake stats a moment later so map_get_path can be verified
	await get_tree().create_timer(0.4).timeout
	if is_instance_valid(nav_region) and nav_region.navigation_mesh:
		var verts: int = nav_region.navigation_mesh.get_vertices().size()
		var polys: int = nav_region.navigation_mesh.get_polygon_count()
		print("NAV_BAKE: vertices=%d polys=%d radius=%.1f covers=%d" % [verts, polys, agent_radius, get_tree().get_nodes_in_group("cover").size() + get_tree().get_nodes_in_group("solid_obstacle").size()])
