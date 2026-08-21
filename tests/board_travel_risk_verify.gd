extends Node

## Verifies:
## 1. Board generator rolls unknown_signal and removes static convoy_breakdown/ambush
## 2. unknown_signal POI model and badge creation
## 3. Mystery transmission choice effects (investigate_signal / ignore_signal)
## 4. Dynamic travel risk breakdown calculations across terrains & convoy HP states

var _checks := 0
var _fails := 0

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("TRAVEL_RISK_OK: " + label)
	else:
		_fails += 1
		printerr("TRAVEL_RISK_FAIL: " + label)

func _ready() -> void:
	print("--- 1. Testing Board Generator POI Distribution ---")
	var bg = preload("res://scripts/board/board_generator.gd").new()
	var rng = RandomNumberGenerator.new()
	rng.seed = 42

	var generated_types: Dictionary = {}
	for i in range(1000):
		var t = bg._roll_content(rng)
		generated_types[t] = generated_types.get(t, 0) + 1

	_check(generated_types.has("unknown_signal"), "generator rolls unknown_signal POI")
	_check(not generated_types.has("convoy_breakdown"), "generator no longer rolls static convoy_breakdown")
	_check(not generated_types.has("convoy_ambush"), "generator no longer rolls static convoy_ambush")

	print("--- 2. Testing Unknown Signal Tile Visuals ---")
	var tile_script = preload("res://scripts/board/board_tile.gd")
	var tile_node = StaticBody3D.new()
	tile_node.set_script(tile_script)
	tile_node.set_meta("tile_type", "unknown_signal")
	tile_node.set_meta("terrain", "plain")
	tile_node.set_meta("grid_pos", Vector2i(2, 2))
	add_child(tile_node)

	_check(tile_node.is_revealed, "unknown_signal tile is revealed by default")
	_check(tile_node._poi_node != null and tile_node._poi_node.get_child_count() > 0, "unknown_signal creates 3D beacon model")

	print("--- 3. Testing ThemeSystem Mystery Signal Choices ---")
	var initial_scrap = GlobalData.currency.scrap
	var forced_count := 0
	var reward_count := 0

	# Test 50 iterations of investigate_signal to verify both reward and trap outcomes
	for i in range(50):
		var choice = {"effect": "investigate_signal", "label": "Investigate Signal"}
		var is_trap = ThemeSystem.apply_event_effect(choice)
		if is_trap:
			forced_count += 1
			_check(GlobalData.board.convoy_defense_active == true, "trap sets convoy_defense_active")
			_check(GlobalData.board.convoy_defense_waves == 3, "trap configures 3-wave defense")
		else:
			reward_count += 1

	_check(forced_count > 0, "investigate_signal produced trap defense outcomes (got %d)" % forced_count)
	_check(reward_count > 0, "investigate_signal produced reward outcomes (got %d)" % reward_count)

	var ignore_choice = {"effect": "ignore_signal", "label": "Ignore & Move On"}
	var ignore_result = ThemeSystem.apply_event_effect(ignore_choice)
	_check(ignore_result == false, "ignore_signal is safe with no combat")

	print("--- 4. Testing Board Manager Dynamic Travel Risk ---")
	var bm_script = preload("res://scripts/board/board_manager.gd")
	var bm = Node3D.new()
	var tc = Node3D.new()
	tc.name = "TileContainer"
	bm.add_child(tc)
	var pt = Node3D.new()
	pt.name = "PlayerToken"
	bm.add_child(pt)
	bm.set_script(bm_script)
	add_child(bm)

	# Road should be completely safe (0% chance)
	GlobalData.board.convoy_destroyed = false
	GlobalData.narrative.mech_less = false
	GlobalData.narrative.ceasefire_turns = 0
	GlobalData.board.convoy_hp = 100.0
	GlobalData.board.convoy_hp_max = 100.0

	var road_breakdown := false
	for i in range(100):
		if bm._roll_travel_breakdown("road"):
			road_breakdown = true
			break
	_check(not road_breakdown, "road travel never causes breakdown (0% risk)")

	# Destroyed convoy never triggers breakdown
	GlobalData.board.convoy_destroyed = true
	_check(not bm._roll_travel_breakdown("mountain"), "destroyed convoy skips travel breakdown")
	GlobalData.board.convoy_destroyed = false

	# Pilot mechless skips travel breakdown
	GlobalData.narrative.mech_less = true
	_check(not bm._roll_travel_breakdown("mountain"), "mechless mode skips travel breakdown")
	GlobalData.narrative.mech_less = false

	print("==================================================")
	print("BOARD_TRAVEL_RISK_VERIFY COMPLETED:")
	print("Checks: %d | Fails: %d" % [_checks, _fails])
	print("==================================================")

	get_tree().quit(1 if _fails > 0 else 0)
