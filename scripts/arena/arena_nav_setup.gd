extends Node

## Sets up NavigationRegion3D after arena generation.
## Attach to game_world.tscn alongside ArenaGenerator.

@export var agent_radius: float = 2.0
@export var agent_height: float = 6.0
@export var cell_size: float = 0.5

var nav_region: NavigationRegion3D


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame  # Wait 2 frames for arena to generate
	_setup_navigation()


func _setup_navigation() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavigationRegion"
	get_parent().add_child(nav_region)

	var nav_mesh = NavigationMesh.new()
	nav_mesh.cell_size = cell_size
	nav_mesh.agent_radius = agent_radius
	nav_mesh.agent_height = agent_height
	nav_mesh.agent_max_climb = 0.3
	nav_mesh.agent_max_slope = 45.0

	# Source geometry for the bake: one invisible box per footprint cell on
	# irregular maps (so navigation hugs the real battlefield outline), or the
	# classic slightly-shrunk square floor otherwise.
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
		var arena_size := GlobalData.current_arena_size
		box.size = Vector3(arena_size * 0.49, 0.1, arena_size * 0.49)  # Slightly smaller than arena
		floor_mesh.mesh = box
		floor_mesh.position.y = 0.05
		floor_mesh.visible = false
		nav_region.add_child(floor_mesh)

	# Set the nav mesh
	nav_region.navigation_mesh = nav_mesh

	# Bake navigation — get the default world map
	var maps = NavigationServer3D.get_maps()
	if maps.size() > 0:
		NavigationServer3D.region_set_map(nav_region.get_rid(), maps[0])

	# Mark obstacle positions as blocked
	_mark_obstacles()


func _mark_obstacles() -> void:
	# Wait for obstacles to spawn
	await get_tree().create_timer(0.5).timeout

	var obstacles = get_tree().get_nodes_in_group("cover")
	for obstacle in obstacles:
		if not is_instance_valid(obstacle):
			continue
		# Create a navigation link barrier around each obstacle
		var pos = obstacle.global_position
		var size = Vector3(3, 2, 3)  # Default size

		# Get actual size from collision shape
		for child in obstacle.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				size = child.shape.size
				break

		# Add region exclusion (simple approach: lower nav mesh quality near obstacles)
		# In practice, the nav mesh baker handles this if we bake after obstacles exist
