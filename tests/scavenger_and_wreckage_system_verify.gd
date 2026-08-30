extends Node

func _ready() -> void:
	print("--- BEGIN SCAVENGER FACTION & WRECKAGE VERIFY TEST SUITE ---")
	test_camp_creation_and_manpower_growth()
	test_scavenger_fleet_spawning()
	test_multi_faction_auto_battle()
	test_tile_wreckage_registration_and_salvage()
	test_board_tile_visual_rendering()
	print("--- ALL TESTS PASSED SUCCESSFULLY! ---")
	get_tree().quit(0)


func assert_true(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERTION FAILED: " + msg)
		print("FAILED: " + msg)
		get_tree().quit(1)
	else:
		print("PASS: " + msg)


func test_camp_creation_and_manpower_growth() -> void:
	print("\n[TEST 1] Scavenger Camp Creation & Manpower Growth...")
	GlobalData.reset_all()

	var dummy_tiles := {}
	for x in range(10):
		for y in range(10):
			dummy_tiles[Vector2i(x, y)] = {"type": "plain"}

	ScavengerSystem.ensure_camps(dummy_tiles, 2)
	var camps: Array = ScavengerSystem.get_camps()
	assert_true(camps.size() == 2, "2 Scavenger camps created on board")

	var camp0 = camps[0]
	var initial_mp = int(camp0.get("manpower", 0))
	assert_true(initial_mp >= 6, "Initial manpower is at least 6 MP (actual: %d)" % initial_mp)

	# Advance turn
	ScavengerSystem.advance_turn(dummy_tiles)
	var updated_camps = ScavengerSystem.get_camps()
	var new_mp = int(updated_camps[0].get("manpower", 0))
	assert_true(new_mp >= initial_mp, "Manpower grew over turn: %d -> %d" % [initial_mp, new_mp])


func test_scavenger_fleet_spawning() -> void:
	print("\n[TEST 2] Scavenger Fleet Dispatch at Threshold...")
	GlobalData.reset_all()

	var dummy_tiles := {Vector2i(5, 5): {"type": "plain"}}
	var camps := [{
		"id": "camp_test",
		"pos_x": 5,
		"pos_y": 5,
		"name": "Test Den",
		"manpower": 18,
		"max_manpower": 20,
		"spawn_threshold": 16,
		"active_fleets": 0
	}]
	ScavengerSystem.set_camps(camps)

	var events = ScavengerSystem.advance_turn(dummy_tiles)
	assert_true(events.size() == 1, "Dispatched 1 Scavenger fleet event")
	assert_true(events[0]["type"] == "scavenger_fleet_spawned", "Event type is scavenger_fleet_spawned")

	var patrols = GlobalData.board.board_patrols
	assert_true(patrols.size() > 0, "Scavenger fleet added to GlobalData.board.board_patrols")
	var scav_patrol = patrols.back()
	assert_true(scav_patrol.get("faction") == "scavenger", "Patrol faction is scavenger")


func test_multi_faction_auto_battle() -> void:
	print("\n[TEST 3] Multi-Faction Auto-Battle Simulation...")
	var scav_fleet := {
		"name": "Scavenger Bandits",
		"faction": "scavenger",
		"grunts": 3,
		"aces": 1
	}
	var enemy_fleet := {
		"name": "Red Vanguard",
		"faction": "hostile",
		"grunts": 1,
		"aces": 0
	}

	var battle_res = ScavengerSystem.resolve_auto_battle(scav_fleet, enemy_fleet)
	assert_true(battle_res.has("winner"), "Battle result has winner: %s" % battle_res.get("winner"))
	assert_true(battle_res.get("scrap", 0) > 0, "Battle yields scrap: +%d" % battle_res.get("scrap"))
	assert_true(battle_res.get("log", "").contains("Clash"), "Battle log generated: %s" % battle_res.get("log"))


func test_tile_wreckage_registration_and_salvage() -> void:
	print("\n[TEST 4] Battlefield Tile Wreckage Registration and Salvage...")
	GlobalData.reset_all()

	var test_pos := Vector2i(3, 4)
	var test_w: WeaponPart = load("res://resources/mech/stock/weapon_machine_gun.tres")
	var drop_items = [{"type": "weapon", "weapon": test_w}]

	assert_true(not ScavengerSystem.has_wreckage_at(test_pos), "No initial wreckage at (3,4)")

	ScavengerSystem.register_tile_wreckage(test_pos, drop_items, 15)
	assert_true(ScavengerSystem.has_wreckage_at(test_pos), "Wreckage marker registered at (3,4)")

	var wr_data = ScavengerSystem.get_wreckage_at(test_pos)
	assert_true(wr_data.get("items", []).size() == 1, "Wreckage contains 1 weapon item")
	assert_true(int(wr_data.get("scrap", 0)) == 15, "Wreckage contains 15 scrap")

	# Claim salvage
	var claimed = ScavengerSystem.claim_tile_wreckage(test_pos)
	assert_true(claimed.get("items", []).size() == 1, "Claimed 1 weapon")
	assert_true(not ScavengerSystem.has_wreckage_at(test_pos), "Wreckage cleared from tile after claim")


func test_board_tile_visual_rendering() -> void:
	print("\n[TEST 5] BoardTile Visual Models for Scavenger Camp & Wreckage...")
	var tile_script = load("res://scripts/board/board_tile.gd")

	# Test Camp Tile Visual
	var camp_tile = Node3D.new()
	camp_tile.set_script(tile_script)
	add_child(camp_tile)
	camp_tile.board_pos = Vector2i(2, 2)
	camp_tile.tile_type = "scavenger_camp"
	camp_tile._update_poi_visual()
	assert_true(camp_tile._poi_node != null, "Camp POI node created")
	assert_true(camp_tile._poi_node.get_child_count() > 0, "Camp POI node has visual meshes")

	# Test Wreckage Tile Visual
	var wr_tile = Node3D.new()
	wr_tile.set_script(tile_script)
	add_child(wr_tile)
	wr_tile.board_pos = Vector2i(3, 3)
	wr_tile.tile_type = "tile_wreckage"
	wr_tile._update_poi_visual()
	assert_true(wr_tile._poi_node != null, "Wreckage POI node created")
	assert_true(wr_tile._poi_node.get_child_count() > 0, "Wreckage POI node has visual meshes")

	camp_tile.queue_free()
	wr_tile.queue_free()
