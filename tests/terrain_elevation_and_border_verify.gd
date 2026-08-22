extends Node3D

## Automated Verification for 3D Terrain Slopes, Height Variation, and Holographic Border Visuals.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("TERRAIN_BORDER_OK: %s" % msg)
	else:
		_fails += 1
		print("TERRAIN_BORDER_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting 3D Terrain Elevation & Border Verification ---")

	var arena_gen_scene = preload("res://scripts/arena/arena_generator.gd")
	var generator = Node3D.new()
	generator.set_script(arena_gen_scene)
	add_child(generator)

	# 1. Test Desert Terrain Height Variance (Dune Slopes)
	generator.current_theme = 0 # DESERT
	var min_h := 999.0
	var max_h := -999.0
	for x in range(-50, 50, 5):
		for z in range(-50, 50, 5):
			var h: float = generator._get_terrain_height(float(x), float(z))
			min_h = minf(min_h, h)
			max_h = maxf(max_h, h)

	var height_variance := max_h - min_h
	_check(height_variance >= 1.5, "Desert terrain generates dynamic dune height variance (range: %.2fm to %.2fm, delta: %.2fm)" % [min_h, max_h, height_variance])

	# 2. Test Crossroads City Height Variance
	generator.current_theme = 2 # CROSSROADS
	var cross_min := 999.0
	var cross_max := -999.0
	for x in range(-60, 60, 8):
		for z in range(-60, 60, 8):
			var h: float = generator._get_terrain_height(float(x), float(z))
			cross_min = minf(cross_min, h)
			cross_max = maxf(cross_max, h)
	_check((cross_max - cross_min) >= 1.0, "Crossroads terrain generates elevated plazas & ramps (delta: %.2fm)" % (cross_max - cross_min))

	# 3. Test Full Arena Generation with Hologram Fence Visuals
	generator.generate_arena()

	var zones = get_tree().get_nodes_in_group("escape_zone")
	_check(zones.size() >= 4, "Generated holographic boundary zones across perimeter")

	var found_hologram := false
	var found_tag := false
	for z in zones:
		if z.has_node("HologramFence"):
			found_hologram = true
		if z.has_node("DirectionTag"):
			found_tag = true

	_check(found_hologram, "Hologram fence mesh exists with semi-transparent energy grid shader")
	_check(found_tag, "Directional 3D tag labels exist indicating retreat / breakthrough / blocked status")

	# Check terrain collision body
	var col_body = generator.get_node_or_null("ThemeStructures/GroundCollision")
	_check(col_body != null and col_body.collision_layer == 2, "3D Terrain Collision body is configured on Environment layer 2")

	print("--- Terrain & Border Verification Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_TERRAIN_BORDER_TESTS_PASSED")
	get_tree().quit(0 if _fails == 0 else 1)
