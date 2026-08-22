extends Node3D

## Automated Verification for Directional Escapes (Breakthrough & Retreat) and Board Map Integration.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("ESCAPE_VERIFY_OK: %s" % msg)
	else:
		_fails += 1
		print("ESCAPE_VERIFY_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Directional Escape & Board Map Verification ---")

	# 1. Test Grid Boundary Logic at (0, 0) - Corner of World Map
	GlobalData.board.current_tile = Vector2i(0, 0)
	GlobalData.board.player_last_dir = Vector2i(1, 0) # Entered moving East

	var arena_gen_scene = preload("res://scripts/arena/arena_generator.gd")
	var generator = Node3D.new()
	generator.set_script(arena_gen_scene)
	add_child(generator)
	generator.generate_arena()

	var zones = get_tree().get_nodes_in_group("escape_zone")
	_check(zones.size() >= 4, "Generated at least 4 directional escape zones (North, South, East, West)")

	var north_zone: Area3D = null
	var south_zone: Area3D = null
	var west_zone: Area3D = null
	var east_zone: Area3D = null

	for z in zones:
		var d_name: String = str(z.get("direction_name"))
		if d_name == "NORTH":
			north_zone = z
		elif d_name == "SOUTH":
			south_zone = z
		elif d_name == "WEST":
			west_zone = z
		elif d_name == "EAST":
			east_zone = z

	_check(north_zone != null and south_zone != null and west_zone != null and east_zone != null, "Found all 4 cardinal escape zones")

	# At (0, 0): North (y=-1) and West (x=-1) are outside map [0..14] -> must be LOCKED
	_check(north_zone.get("is_locked") == true, "North zone (y=-1) is locked at map upper edge")
	_check(west_zone.get("is_locked") == true, "West zone (x=-1) is locked at map left edge")

	# South (y=1) and East (x=1) are inside map -> must be ACTIVE / UNLOCKED
	_check(south_zone.get("is_locked") == false, "South zone (y=1) is active")
	_check(east_zone.get("is_locked") == false, "East zone (x=1) is active")

	# East is the forward moving direction -> Breakthrough
	_check(east_zone.get("escape_type") == "breakthrough", "East zone is marked as 'breakthrough'")
	_check(east_zone.get("delta_tile") == Vector2i(1, 0), "East breakthrough yields +1 tile advance")

	# 2. Test Directional Escape Completion in CombatRewardsUI
	var rewards_ui = preload("res://scripts/ui/combat_rewards_ui.gd").new()
	add_child(rewards_ui)

	# Simulate Breakthrough escape
	EventBus.combat_escaped_directional.emit("breakthrough", Vector2i(1, 0))
	EventBus.combat_escaped.emit()

	_check(rewards_ui.visible == true, "Escape UI is shown upon escape")
	_check(rewards_ui._last_escape_type == "breakthrough", "Rewards UI records breakthrough escape type")
	_check(rewards_ui._last_delta_tile == Vector2i(1, 0), "Rewards UI records +1 tile delta")

	# Simulate pressing continue to return to board
	rewards_ui._on_continue_pressed()
	_check(GlobalData.board.current_tile == Vector2i(1, 0), "Board current_tile advanced from (0,0) to (1,0) via breakthrough")

	# Simulate Tactical Retreat escape from (1, 0)
	EventBus.combat_escaped_directional.emit("retreat", Vector2i(-1, 0))
	EventBus.combat_escaped.emit()
	rewards_ui._on_continue_pressed()
	_check(GlobalData.board.current_tile == Vector2i(0, 0), "Board current_tile fell back from (1,0) to (0,0) via tactical retreat")

	print("--- Directional Escape Verification Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_ESCAPE_TESTS_PASSED")
	get_tree().quit(0 if _fails == 0 else 1)
