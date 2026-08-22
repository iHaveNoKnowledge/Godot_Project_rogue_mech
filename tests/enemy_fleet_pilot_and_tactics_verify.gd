extends Node3D

## Headless Automated Verification for Procedural Enemy Fleet Pilots, Squad Formations & Tactical AI.

const EnemySquadCoordinatorScript = preload("res://scripts/mecha/ai/enemy_squad_coordinator.gd")

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("FLEET_AI_OK: %s" % msg)
	else:
		_fails += 1
		print("FLEET_AI_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Procedural Enemy Fleet & Tactical AI Verification ---")

	# 1. Test PilotGenerator.generate_enemy_fleet
	var fleet_4 := PilotGenerator.generate_enemy_fleet(4, "Steel Legion", 2)
	_check(fleet_4.has("commander") and fleet_4.has("pilots"), "Enemy fleet generated with commander and pilots array")
	_check(fleet_4["pilots"].size() == 4, "Fleet size is exactly 4 pilots")

	var cmdr: Dictionary = fleet_4["commander"]
	_check(cmdr.get("squad_role") == "commander", "Commander has squad_role 'commander'")
	_check(cmdr.get("rank_title") == "[CMDR]", "Commander has rank title '[CMDR]'")
	_check(cmdr.get("name") != "" and cmdr.get("callsign") != "", "Commander has procedural full name and callsign")

	var roles_found: Array = []
	for p in fleet_4["pilots"]:
		roles_found.append(p.get("tactical_role", ""))
	_check(roles_found.has("commander"), "Fleet roles contain 'commander'")
	_check(roles_found.size() == 4, "All 4 pilots have distinct tactical assignments")

	# 2. Test EnemySquadCoordinator formation and dynamic flanking
	var coordinator = EnemySquadCoordinatorScript.new()
	coordinator.setup_squad(fleet_4["squad_id"], fleet_4["squad_name"])
	add_child(coordinator)

	var dummy_cmdr := Node3D.new()
	dummy_cmdr.name = "CommanderMech"
	dummy_cmdr.position = Vector3(0, 0, 0)
	add_child(dummy_cmdr)

	var dummy_wingman1 := Node3D.new()
	dummy_wingman1.name = "Wingman1"
	dummy_wingman1.position = Vector3(2.0, 0, 0) # Close to commander to test separation
	add_child(dummy_wingman1)

	var dummy_wingman2 := Node3D.new()
	dummy_wingman2.name = "Wingman2"
	dummy_wingman2.position = Vector3(10.0, 0, 10.0)
	add_child(dummy_wingman2)

	coordinator.register_member(dummy_cmdr, fleet_4["pilots"][0])
	coordinator.register_member(dummy_wingman1, fleet_4["pilots"][1])
	coordinator.register_member(dummy_wingman2, fleet_4["pilots"][2])

	_check(coordinator.get_living_count() == 3, "Coordinator tracks 3 living members")
	_check(coordinator.commander_mech == dummy_cmdr, "Coordinator identifies commander mech")

	# Test formation offset (Wedge)
	var offset0 = coordinator.get_formation_offset(dummy_cmdr)
	var offset1 = coordinator.get_formation_offset(dummy_wingman1)
	_check(offset0 == Vector3.ZERO, "Commander formation offset is at the tip (0, 0, 0)")
	_check(offset1 != Vector3.ZERO, "Wingman formation offset is spaced laterally in wedge")

	# Test Boids mutual separation force
	var sep = coordinator.get_separation_vector(dummy_wingman1, 6.5)
	_check(sep.length() > 0.0, "Wingman close to commander receives repulsive separation force (length: %.2f)" % sep.length())

	# Test Tactical waypoint calculation around a player target
	var player_target := Node3D.new()
	player_target.position = Vector3(0, 0, 30.0)
	add_child(player_target)

	var waypoint_cmdr = coordinator.get_tactical_waypoint(dummy_cmdr, player_target, 20.0)
	var waypoint_wing1 = coordinator.get_tactical_waypoint(dummy_wingman1, player_target, 20.0)
	_check(waypoint_cmdr != waypoint_wing1, "Commander and Wingman have distinct tactical flanking waypoints")
	_check(waypoint_cmdr.distance_to(player_target.position) > 15.0, "Waypoint maintains tactical engagement distance from player")

	# Test Commander promotion when leader dies
	coordinator.unregister_member(dummy_cmdr)
	_check(coordinator.commander_mech == dummy_wingman1, "Surviving wingman is dynamically promoted to new squad commander")
	_check(coordinator.get_living_count() == 2, "Coordinator living count decremented to 2")

	print("--- Fleet AI Verification Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_FLEET_AI_TESTS_PASSED")
	get_tree().quit(0 if _fails == 0 else 1)
