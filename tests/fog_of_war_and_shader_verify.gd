extends Node3D

## Automated Verification for 3D Mesh Fog of War, Organic Terrain Shader, and HUD Currency Display.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("FOW_SHADER_OK: %s" % msg)
	else:
		_fails += 1
		print("FOW_SHADER_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Fog of War, Terrain Shader & HUD Currency Verification ---")

	# 1. Test 3D Mesh Fog of War and Shroud
	var tile_scene = preload("res://scenes/board/board_tile.tscn")
	var tile = tile_scene.instantiate()
	tile.set_meta("tile_type", "event")
	tile.set_meta("grid_pos", Vector2i(5, 5))
	tile.set_meta("terrain", "desert")
	add_child(tile)

	_check(not tile.is_revealed, "Unvisited tile initializes with is_revealed = false")
	_check(tile._fog_mesh != null, "3D Volumetric FogOfWarMesh is present on unrevealed tile")
	_check(tile._fog_mesh.visible == true, "FogOfWarMesh is visible, obscuring unexplored tile")

	# Test Reveal and Dissolve
	tile.reveal(false) # instant reveal for test
	_check(tile.is_revealed == true, "tile.reveal() marked is_revealed = true")
	_check(tile._fog_mesh == null, "FogOfWarMesh dissolved/freed upon tile reveal")

	# 2. Test Organic Terrain Blending Shader
	var mesh_inst: MeshInstance3D = tile.get_node_or_null("MeshInstance3D")
	_check(mesh_inst != null, "Found MeshInstance3D on tile")
	var mat = mesh_inst.get_surface_override_material(0)
	_check(mat is ShaderMaterial, "Tile uses custom ShaderMaterial for organic terrain blending")
	if mat is ShaderMaterial:
		var smat := mat as ShaderMaterial
		var feather: float = float(smat.get_shader_parameter("edge_feather"))
		var noise_blend: float = float(smat.get_shader_parameter("noise_blend_strength"))
		_check(feather > 0.1, "Terrain shader has active edge_feather (%.2f)" % feather)
		_check(noise_blend > 0.2, "Terrain shader has active noise_blend_strength (%.2f) to break square seams" % noise_blend)

	# 3. Test Board HUD Currency and Safe Layout
	GlobalData.currency.credits = 1450
	GlobalData.currency.scrap = 85
	GlobalData.currency.data_cores = 3

	var hud_scene = preload("res://scripts/ui/board_hud.gd")
	var hud = CanvasLayer.new()
	hud.set_script(hud_scene)
	add_child(hud)

	hud._refresh()
	_check(hud._credits_label != null and hud._credits_label.text.contains("1450"), "HUD displays Credits accurately in TopBar (found: %s)" % hud._credits_label.text)
	_check(hud._scrap_label != null and hud._scrap_label.text.contains("85"), "HUD displays Scrap accurately in TopBar (found: %s)" % hud._scrap_label.text)
	_check(hud._cores_label != null and hud._cores_label.text.contains("3"), "HUD displays Data Cores accurately in TopBar (found: %s)" % hud._cores_label.text)

	print("--- Fog of War, Terrain Shader & HUD Currency Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_FOW_SHADER_CURRENCY_TESTS_PASSED")
	get_tree().quit(0 if _fails == 0 else 1)
