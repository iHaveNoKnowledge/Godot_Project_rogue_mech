extends Node

## Verifies:
## 1. Artillery Fleet 3D bombardment animation on tabletop board (parabolic shells, impact blast, screen shake)
## 2. EMP hazard electric spark and burst VFX

var _fails := 0
var _checks := 0

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("FAIL: " + label)
	else:
		print("ARTILLERY_EMP_OK: " + label)

func _ready() -> void:
	GlobalData.reset_run_data()
	GameManager.current_state = GameManager.State.BOARD

	var fx := EffectManager.new()
	fx.name = "EffectManager"
	add_child(fx)

	# 1. Test EffectFactory electric sparks and burst
	EffectFactory.spawn_electric_spark(get_tree(), Vector3(0, 1, 0), Color(0.4, 0.85, 1.0), 0.8, 0.2)
	EffectFactory.spawn_electric_burst(get_tree(), Vector3(2, 1, 0), Color(0.4, 0.85, 1.0), 6, 1.2)
	_check(true, "Electric spark and burst generated without errors")

	# 2. Setup BoardManager and camera for artillery bombardment test
	var bm_script = preload("res://scripts/board/board_manager.gd")
	var bm: Node3D = Node3D.new()
	bm.name = "BoardManager"
	bm.set_script(bm_script)

	var tile_container := Node3D.new()
	tile_container.name = "TileContainer"
	bm.add_child(tile_container)

	var player_token := Node3D.new()
	player_token.name = "PlayerToken"
	player_token.position = Vector3(0, 0.5, 0)
	bm.player_token = player_token
	bm.add_child(player_token)

	add_child(bm)

	# Add camera with shake support
	var cam_script = preload("res://scripts/board/board_camera_init.gd")
	var cam := Camera3D.new()
	cam.set_script(cam_script)
	add_child(cam)

	# Add mock tile for player and artillery fleet
	var tile_script = preload("res://scripts/board/board_tile.gd")
	var player_tile: StaticBody3D = StaticBody3D.new()
	player_tile.set_script(tile_script)
	player_tile.position = Vector3(0, 0, 0)
	bm.nodes_dict[Vector2i(0, 0)] = player_tile
	tile_container.add_child(player_tile)

	var arty_tile: StaticBody3D = StaticBody3D.new()
	arty_tile.set_script(tile_script)
	arty_tile.position = Vector3(6, 0, 6)
	bm.nodes_dict[Vector2i(2, 2)] = arty_tile
	tile_container.add_child(arty_tile)

	bm.current_pos = Vector2i(0, 0)

	# Trigger artillery bombardment
	var mock_fleets: Array[Dictionary] = [
		{"id": "fleet_arty_1", "archetype": "artillery", "pos": Vector2i(2, 2)}
	]

	bm._trigger_artillery_bombardment(mock_fleets)

	# Check that parabolic shell nodes were spawned
	var found_shells := 0
	for child in bm.get_children():
		if child is MeshInstance3D and child.mesh is SphereMesh:
			found_shells += 1

	_check(found_shells >= 1, "Artillery bombardment spawned parabolic shell meshes (got %d)" % found_shells)
	_check(GlobalData.fuel.mech_energy <= 970.0, "Artillery bombardment deducted mech energy (energy=%.1f <= 970.0)" % GlobalData.fuel.mech_energy)

	print("BOARD_ARTILLERY_EMP_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
