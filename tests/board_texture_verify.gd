extends Node

## Verifies the board tile ground-texture system:
##   1. Every terrain with a texture pack under resources/textures/ loads all
##      three PBR maps (albedo / normal / roughness).
##   2. Terrains without a pack (e.g. water) return null so tiles fall back to
##      the flat palette color.
##   3. A live BoardTile applies a textured material (albedo_texture set) and
##      keeps fog-of-war dimming for unrevealed tiles.
## Run: godot --headless --path . res://tests/board_texture_verify.tscn

const BOARD_TILE_SCENE := preload("res://scenes/board/board_tile.tscn")

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("TEX_OK: " + name)
	else:
		_fails += 1
		printerr("TEX_FAIL: " + name)


func _spawn_tile(grid: Vector2i, terrain_name: String) -> Node:
	var tile := BOARD_TILE_SCENE.instantiate()
	tile.set_meta("tile_type", "empty")
	tile.set_meta("grid_pos", grid)
	tile.set_meta("terrain", terrain_name)
	add_child(tile)
	return tile


func _override_mat(tile: Node) -> StandardMaterial3D:
	var mesh := tile.get_node("MeshInstance3D") as MeshInstance3D
	return mesh.get_surface_override_material(0) as StandardMaterial3D


func _ready() -> void:
	var tile_script := load("res://scripts/board/board_tile.gd")

	for terrain in ["plain", "road", "rock", "forest", "sand", "bridge"]:
		for kind in ["albedo", "normal", "roughness"]:
			var tex = tile_script._cached_texture(terrain, kind)
			_check(tex != null, "%s/%s.jpg loads" % [terrain, kind])

	# Water has no texture pack -> flat color fallback.
	var water_tex = tile_script._cached_texture("water", "albedo")
	_check(water_tex == null, "water falls back to flat color")
	var unknown = tile_script._cached_texture("no_such_terrain", "albedo")
	_check(unknown == null, "unknown terrain falls back to flat color")

	# Live tile: revealed suburb plain tile must carry an albedo texture.
	GlobalData.board.board_theme_id = "suburb"
	var revealed := _spawn_tile(Vector2i.ZERO, "plain")
	revealed.reveal()
	var mat := _override_mat(revealed)
	_check(mat != null, "revealed tile has override material")
	if mat != null:
		_check(mat.albedo_texture != null, "revealed tile uses ground texture")
		_check(mat.albedo_color.is_equal_approx(Color.WHITE), "revealed tile untinted")

	# Fog of war: unrevealed tile dims via darkened palette color.
	var foggy := _spawn_tile(Vector2i(1, 1), "plain")
	var fmat := _override_mat(foggy)
	_check(fmat != null and fmat.albedo_color.v < 0.5, "unrevealed tile stays dimmed")

	if _fails == 0:
		print("TEX_ALL_OK: %d checks passed" % _checks)
	else:
		printerr("TEX_FAILURES: %d/%d checks failed" % [_fails, _checks])
	get_tree().quit(1 if _fails > 0 else 0)
