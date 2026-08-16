extends Node

## Verifies the FOREST arena terrain features (gentle rolling banks + open flat
## meadows):
##   1. The terrain height function is flat on the river strip, the spawn
##      pocket, and inside every open field, and rolls into gentle hills
##      (max ~3m, never cliffs) elsewhere.
##   2. Open-field blobs exist and the floor texture tints them as lighter
##      meadow green than the surrounding woods.
##   3. Ground tiles are displaced ArrayMesh banks + a flat river strip, not a
##      tile grid.
##   4. Forest collision is two HeightMapShape3D banks (no flat box), so mechs
##      can actually walk the hills.
## Run: godot --headless --path . res://tests/arena_forest_terrain_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("TERRAIN_OK: " + name)
	else:
		_fails += 1
		printerr("TERRAIN_FAIL: " + name)


func _ready() -> void:
	GlobalData.reset_run_data()
	GlobalData.board_seed = 7  # deterministic field layout + hills
	var arena_script = preload("res://scripts/arena/arena_generator.gd")
	var arena := arena_script.new()
	arena.current_theme = arena_script.BiomeTheme.FOREST
	arena.arena_size = 240.0
	arena.generate_arena()

	# --- 1. Height function: flat pockets, rolling hills elsewhere ---
	var strip_y: float = arena_script.FOREST_RIVER_STRIP_Y
	# The shallow river crosses the whole map (including the center spawn
	# pocket), so the strip stays flat at the wading surface everywhere.
	_check(absf(arena._forest_terrain_height(0.0, 0.0) - strip_y) < 0.01, "spawn center is flat at river level")
	_check(absf(arena._forest_terrain_height(12.0, -12.0) - strip_y) < 0.01, "spawn pocket stays flat")
	_check(absf(arena._forest_terrain_height(60.0, 0.0) - strip_y) < 0.01, "river strip is the flat wading surface")
	# The bank right at the water's edge must not turn into a cliff.
	var bank_near_river := arena._forest_terrain_height(60.0, 30.0)
	_check(bank_near_river > strip_y - 3.5 and bank_near_river < 4.5, "bank near the river stays gentle (h=%.2f)" % bank_near_river)

	# Open-field blobs exist, are flat, and are recognized as fields.
	var fields: Array = arena._forest_fields
	_check(fields.size() >= 2, "forest arena has open-field blobs (got %d)" % fields.size())
	for f in fields:
		var c: Vector2 = f["center"]
		_check(arena._is_open_field(c.x, c.y), "field center (%d,%d) is open" % [int(c.x), int(c.y)])
		_check(absf(arena._forest_terrain_height(c.x, c.y)) < 0.01, "field center is flat")

	# Hills exist somewhere outside the flat pockets.
	var hills := 0
	for i in range(300):
		var sx := randf_range(-110.0, 110.0)
		var sz := randf_range(30.0, 110.0)
		if absf(arena._forest_terrain_height(sx, sz)) > 0.4:
			hills += 1
	_check(hills > 5, "bank terrain rolls into gentle hills (samples=%d)" % hills)

	# Hills stay gentle: |height| never exceeds ~4m anywhere in the arena.
	var max_h := 0.0
	for i in range(300):
		var sx := randf_range(-110.0, 110.0)
		var sz := randf_range(-110.0, 110.0)
		max_h = maxf(max_h, absf(arena._forest_terrain_height(sx, sz)))
	_check(max_h < 4.5, "hills stay gentle (max |h|=%.2f)" % max_h)

	# --- 2. Floor texture tints open fields lighter than dense woods ---
	var tiles := arena.get_node_or_null("GroundTiles")
	var bank_mesh: MeshInstance3D = null
	var mesh_count := 0
	var array_mesh := 0
	if tiles:
		for child in tiles.get_children():
			var m := child as MeshInstance3D
			if m == null or m.mesh == null:
				continue
			mesh_count += 1
			if m.mesh is ArrayMesh:
				array_mesh += 1
				if bank_mesh == null:
					bank_mesh = m
	_check(array_mesh >= 1, "forest banks use a displaced ArrayMesh terrain")
	_check(mesh_count <= 4, "forest ground is a few big meshes, not a tile grid (got %d)" % mesh_count)

	if bank_mesh and fields.size() > 0:
		var mat := bank_mesh.material_override as StandardMaterial3D
		var tex := mat.albedo_texture as ImageTexture
		var img := tex.get_image()
		var half := 120.0
		var f: Dictionary = fields[0]
		var c: Vector2 = f["center"]
		var pu := int(((c.x + half) / 240.0) * float(img.get_width() - 1))
		var pv := int(((c.y + half) / 240.0) * float(img.get_height() - 1))
		var field_color := img.get_pixel(clampi(pu, 0, img.get_width() - 1), clampi(pv, 0, img.get_height() - 1))
		# A dense-forest pixel far from any field (dense scan + palette fallback).
		var wood_color := Color(0.14, 0.30, 0.14)  # dense-forest base palette
		var found_wood := false
		for i in range(160):
			var wx := -110.0 + float(i % 16) * 14.6
			var wz := 30.0 + float(i / 16) * 11.4
			if not arena._is_open_field(wx, wz):
				var u2 := int(((wx + half) / 240.0) * float(img.get_width() - 1))
				var v2 := int(((wz + half) / 240.0) * float(img.get_height() - 1))
				wood_color = img.get_pixel(clampi(u2, 0, img.get_width() - 1), clampi(v2, 0, img.get_height() - 1))
				found_wood = true
				break
		_check(found_wood, "found a dense-forest pixel to compare against")
		_check(field_color.g > wood_color.g + 0.05, "open fields tint lighter than the woods (%.2f vs %.2f)" % [field_color.g, wood_color.g])

	# --- 3. Field decorations: flowers + fallen leaves dot the meadows ---
	var structures := arena.get_node_or_null("ThemeStructures")
	var flower_patches := 0
	var leaf_patches := 0
	if structures:
		for child in structures.get_children():
			if child.name.begins_with("FlowerPatch"):
				flower_patches += 1
			elif child.name.begins_with("FallenLeaves"):
				leaf_patches += 1
	_check(flower_patches >= 3, "open fields have scattered flower patches (got %d)" % flower_patches)
	_check(leaf_patches >= 3, "open fields have fallen-leaf patches (got %d)" % leaf_patches)
	# Flower patches are decorative (no collision) and sit on the field surface.
	if structures:
		for child in structures.get_children():
			if child.name.begins_with("FlowerPatch"):
				_check(absf(child.position.y - arena._forest_terrain_height(child.position.x, child.position.z)) < 0.01, "flower patch rests on the field surface")
				_check(absf(child.position.y) < 0.01, "flower patch sits on flat field ground")
				break

	# --- 4. Collision: two HeightMapShape3D banks, no flat box ---
	var heightmap_bodies := 0
	var flat_box := false
	if structures:
		for child in structures.get_children():
			for sub in child.get_children():
				if sub is CollisionShape3D and sub.shape != null:
					if sub.shape is HeightMapShape3D:
						heightmap_bodies += 1
					elif sub.shape is BoxShape3D and child.name == "GroundCollision":
						flat_box = true
	_check(heightmap_bodies == 2, "forest terrain collision = 2 heightmap banks (got %d)" % heightmap_bodies)
	_check(not flat_box, "forest arena has no flat box ground collision")

	# --- 5. River strip mesh faces UP (winding not inverted) ---
	# The strip is an ArrayMesh quad; its front face must point at the sky so
	# the ground never renders see-through from above / inside-out from below.
	var strip_faces_up := true
	if tiles:
		for child in tiles.get_children():
			var m := child as MeshInstance3D
			if m == null or not (m.mesh is ArrayMesh) or m.name != "ForestRiverStrip":
				continue
			var mesh: ArrayMesh = m.mesh
			var arrays := mesh.surface_get_arrays(0)
			var verts_arr: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx_arr: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			# First triangle's geometric normal must point up (+Y) — a downward
			# winding would cross to -Y and flip the visible side of the ground.
			for t in range(0, min(idx_arr.size(), 6), 3):
				var a := verts_arr[idx_arr[t]]
				var b := verts_arr[idx_arr[t + 1]]
				var c := verts_arr[idx_arr[t + 2]]
				var n := (b - a).cross(c - a)
				if n.y <= 0.0:
					strip_faces_up = false
	_check(strip_faces_up, "river strip mesh winding faces up (+Y), not inverted")

	# --- 6. River strip still has full-width walkable collision (no gap between
	# the band and the bank heightmaps at |z| = 24) ---
	var has_wide_riverband := false
	if structures:
		for child in structures.get_children():
			if child.name == "Riverband":
				for sub in child.get_children():
					if sub is CollisionShape3D and sub.shape is BoxShape3D:
						if absf((sub.shape as BoxShape3D).size.z - 48.0) < 0.01:
							has_wide_riverband = true
	_check(has_wide_riverband, "riverband collision meets the bank heightmaps (|z| < 24)")

	print("ARENA_FOREST_TERRAIN_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
