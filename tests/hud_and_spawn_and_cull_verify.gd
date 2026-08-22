extends Node3D

## Automated Verification for Tabletop Mode HUD, Battle Player Ground Snapping, and Ground Culling.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("HUD_SPAWN_OK: %s" % msg)
	else:
		_fails += 1
		print("HUD_SPAWN_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting HUD, Spawn Height & Ground Cull Verification ---")

	# 1. Test Ground Material Culling Mode
	var mat := MaterialFactory.get_ground_material(0) # Desert
	_check(mat.cull_mode == BaseMaterial3D.CULL_DISABLED, "Ground material has CULL_DISABLED (double-sided rendering)")

	# 2. Test Player Spawn Ground Snapping
	var arena = preload("res://scripts/arena/arena_generator.gd").new()
	arena.current_theme = 0 # Desert
	add_child(arena)

	# Mock host tree structure with Mecha node
	var mecha = CharacterBody3D.new()
	mecha.name = "Mecha"
	add_child(mecha)

	arena._place_player_at_arena_edge()
	var ground_y: float = arena._get_terrain_height(mecha.position.x, mecha.position.z)
	_check(is_equal_approx(mecha.position.y, ground_y + 1.2), "Player mecha position.y is directly snapped to terrain ground level (y=%.2f, ground=%.2f)" % [mecha.position.y, ground_y])

	# 3. Test Board HUD Mode Labels and Toggle Button
	var hud_scene = preload("res://scripts/ui/board_hud.gd")
	var hud = CanvasLayer.new()
	hud.set_script(hud_scene)
	add_child(hud)

	# Case A: Convoy mode
	GlobalData.fuel.reset()
	GlobalData.fuel.traversal_mode = "convoy"
	hud._refresh()
	var e_label: Label = hud._energy_label
	var btn: Button = hud._roller_toggle_btn
	_check(e_label != null and e_label.text.contains("CONVOY FUEL"), "HUD displays 'CONVOY FUEL' in convoy mode (found: %s)" % e_label.text)
	_check(btn != null and btn.text.contains("DEPLOY MECHA"), "HUD toggle button shows '[DEPLOY MECHA]' in convoy mode")

	# Case B: Click toggle -> deploys Mecha
	hud._on_roller_toggle_pressed()
	_check(GlobalData.fuel.traversal_mode == "mecha", "Toggle button deployed Mecha mode")
	_check(e_label.text.contains("MECHA BATTERY"), "HUD displays 'MECHA BATTERY' in mecha mode (found: %s)" % e_label.text)
	_check(btn.text.contains("DEPLOY PILOT"), "HUD toggle button shows '[DEPLOY PILOT]' in mecha mode")

	# 4. Test BoardManager Hotkey Actions
	var board_mgr = preload("res://scripts/board/board_manager.gd").new()
	add_child(board_mgr)

	# Hotkey 2: deploy mecha
	GlobalData.fuel.traversal_mode = "convoy"
	board_mgr._cycle_traversal_mode()
	_check(GlobalData.fuel.traversal_mode == "mecha", "BoardManager._cycle_traversal_mode() deployed Mecha")

	# Hotkey 3: deploy pilot
	board_mgr._cycle_traversal_mode()
	_check(GlobalData.fuel.traversal_mode == "pilot", "BoardManager._cycle_traversal_mode() deployed Pilot")

	print("--- HUD, Spawn Height & Ground Cull Verification Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_HUD_SPAWN_CULL_TESTS_PASSED")
	get_tree().quit(0 if _fails == 0 else 1)
