extends Node3D

## Automated Verification for Fleet Merging, Splitting, Tabletop Billboard "xN" Badge, and 1-Fleet = 1-Wave Combat Scaling.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("FLEET_WAVE_OK: %s" % msg)
	else:
		_fails += 1
		print("FLEET_WAVE_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Fleet Stack & Wave Scaling Verification ---")

	# 1. Setup Mock Patrol Fleets
	GlobalData.board.board_patrols.clear()
	var fleet_a := {
		"id": 1,
		"pos": Vector2i(2, 2),
		"home": Vector2i(2, 2),
		"name": "Alpha Squad",
		"grunts": 3,
		"aces": 0,
		"aggro": false,
		"faction": "hostile",
		"archetype": "armored",
		"fleet_count": 1,
		"merged_fleets": [],
	}
	var fleet_b := {
		"id": 2,
		"pos": Vector2i(2, 2),
		"home": Vector2i(2, 2),
		"name": "Bravo Squad",
		"grunts": 2,
		"aces": 0,
		"aggro": false,
		"faction": "hostile",
		"archetype": "recon",
		"fleet_count": 1,
		"merged_fleets": [],
	}
	GlobalData.board.board_patrols.append(fleet_a)
	GlobalData.board.board_patrols.append(fleet_b)

	_check(GlobalData.board.board_patrols.size() == 2, "Initialized 2 separate patrol fleets on the board")

	# 2. Test Fleet Merging into 1 Token
	var merged := PatrolSystem.merge_fleets(1, 2)
	_check(merged == true, "PatrolSystem.merge_fleets successfully merged Fleet 2 into Fleet 1")
	_check(GlobalData.board.board_patrols.size() == 1, "Only 1 combined token remains in board_patrols")

	var combined_fleet := PatrolSystem.get_patrol_by_id(1)
	_check(int(combined_fleet.get("fleet_count", 0)) == 2, "Combined fleet has fleet_count == 2")
	_check(combined_fleet.get("merged_fleets", []).size() == 1, "Combined fleet preserves merged sub-fleet data")

	# 3. Test Tabletop Billboard "x2" Badge on PatrolMarker
	var marker_scene = preload("res://scripts/board/patrol_marker.gd")
	var marker = Node3D.new()
	marker.set_script(marker_scene)
	add_child(marker)
	marker.setup(combined_fleet)

	var badge: Label3D = marker.get_node_or_null("FleetCountBadge")
	_check(badge != null, "PatrolMarker creates camera-facing FleetCountBadge for fleet_count > 1")
	_check(badge.text == "x2", "Badge displays 'x2' text matching combined fleet count")
	_check(badge.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "Badge has billboard mode enabled to always face camera")

	# Test Single Fleet has NO badge
	var single_marker = Node3D.new()
	single_marker.set_script(marker_scene)
	add_child(single_marker)
	single_marker.setup({"id": 3, "pos": Vector2i(4, 4), "fleet_count": 1})
	var single_badge = single_marker.get_node_or_null("FleetCountBadge")
	_check(single_badge == null, "Single fleet (fleet_count == 1) does NOT display extra badge")

	# 4. Test 1-Fleet = 1-Wave Combat Scaling in SpawnManager
	var spawn_mgr = preload("res://scripts/systems/spawn_manager.gd").new()
	add_child(spawn_mgr)

	# Case A: 1 Token with 1 Fleet -> Exactly 1 Wave
	GameManager.combat_fleet_count = 1
	GlobalData.board.board_patrol_engagement = -1
	var waves_1 = spawn_mgr._get_active_defs()
	_check(waves_1.size() == 1, "1 Fleet generates exactly 1 combat wave (found %d waves)" % waves_1.size())

	# Case B: 1 Token with 2 Fleets (x2) -> Exactly 2 Waves
	GameManager.combat_fleet_count = 2
	var waves_2 = spawn_mgr._get_active_defs()
	_check(waves_2.size() == 2, "2 Merged Fleets (x2) generate exactly 2 combat waves (found %d waves)" % waves_2.size())

	# Case C: 1 Token with 3 Fleets (x3) -> Exactly 3 Waves
	GameManager.combat_fleet_count = 3
	var waves_3 = spawn_mgr._get_active_defs()
	_check(waves_3.size() == 3, "3 Merged Fleets (x3) generate exactly 3 combat waves (found %d waves)" % waves_3.size())

	# 5. Test Fleet Splitting
	var split_result := PatrolSystem.split_fleet(1, Vector2i(2, 3))
	_check(not split_result.is_empty(), "PatrolSystem.split_fleet successfully split 1 fleet off")
	_check(int(combined_fleet.get("fleet_count", 0)) == 1, "Parent fleet_count decremented to 1")
	_check(GlobalData.board.board_patrols.size() == 2, "Board now contains 2 separate tokens again after split")
	_check(split_result.get("pos") == Vector2i(2, 3), "Detached fleet placed at tactical flank position (2, 3)")

	print("--- Fleet Stack & Wave Scaling Verification Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_FLEET_WAVE_TESTS_PASSED")
	get_tree().quit(0 if _fails == 0 else 1)
