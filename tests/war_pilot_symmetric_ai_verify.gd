extends Node

const WarPilotAgent = preload("res://scripts/war/war_pilot_agent.gd")

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	print("=== Starting War Mode Pilot-Centric Symmetric AI Verification ===")
	_test_faction_archetypes_gm_vs_zaku()
	_test_decoupled_vehicle_interface()
	_test_pilot_spawning_and_lifecycle()
	_test_emergency_eject_and_survival()

	print("=== Pilot-Centric Symmetric AI Finished: %d passed, %d failed ===" % [_passed, _failed])
	if _failed == 0:
		print("ALL_PILOT_SYMMETRIC_TESTS_PASSED")
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("PILOT_AI_OK: %s" % label)
	else:
		_failed += 1
		push_error("PILOT_AI_FAIL: %s" % label)


func _test_faction_archetypes_gm_vs_zaku() -> void:
	var friendly_arch = WarFactionVisual.get_faction_archetype("friendly")
	_assert(friendly_arch.get("style") == "gm_federation", "Friendly archetype is GM / Federation style")
	_assert(friendly_arch.get("slots", {}).get("head") == "head_001", "Friendly equips GM-style Visor head (head_001)")
	_assert(friendly_arch.get("slots", {}).get("body") == "body_line", "Friendly equips angular Line-Issue plating (body_line)")

	var enemy_arch = WarFactionVisual.get_faction_archetype("enemy")
	_assert(enemy_arch.get("style") == "zaku_outlaw", "Enemy archetype is Zaku / Outlaw style")
	_assert(enemy_arch.get("slots", {}).get("head") == "head_002", "Enemy equips Zaku-style Mono-Eye head (head_002)")
	_assert(enemy_arch.get("slots", {}).get("body") == "body_iron", "Enemy equips heavy industrial Iron plating (body_iron)")


func _test_decoupled_vehicle_interface() -> void:
	var mecha_scene = load("res://scenes/mecha/mecha_base.tscn")
	_assert(mecha_scene != null, "mecha_base.tscn loaded successfully")

	var mecha = mecha_scene.instantiate() as CharacterBody3D
	add_child(mecha)
	mecha.position = Vector3(0, 5, 0)

	# Verify decoupled drive interface variables exist
	_assert("is_player_driven" in mecha, "mecha_controller has is_player_driven property")
	_assert(mecha.has_method("set_drive_commands"), "mecha_controller has set_drive_commands method")
	_assert(mecha.has_method("board_pilot"), "mecha_controller has board_pilot method")
	_assert(mecha.has_method("eject_pilot"), "mecha_controller has eject_pilot method")

	# Test AI Boarding
	var dummy_pilot = Node3D.new()
	dummy_pilot.name = "AIPilot"
	add_child(dummy_pilot)

	mecha.board_pilot(dummy_pilot)
	_assert(mecha.seated_pilot == dummy_pilot, "Pilot successfully boarded vehicle")
	_assert(not mecha.is_player_driven, "Vehicle driven by AI is NOT player driven (is_player_driven = false)")
	_assert(not mecha.is_in_group("player"), "AI-driven vehicle is not in 'player' group (no input mirroring)")

	# Test AI Drive Commands (simulate movement input)
	mecha.set_drive_commands(Vector3(1, 0, 0), Vector3(50, 0, 0), false, false, false)
	# Process one movement step manually
	mecha._apply_movement(0.016)
	_assert(mecha.velocity.x > 0.0, "AI drive command applied forward movement velocity (velocity.x = %.2f)" % mecha.velocity.x)

	# Test Pilot Eject
	var ejected = mecha.eject_pilot()
	_assert(ejected == dummy_pilot, "eject_pilot cleanly returned seated pilot")
	_assert(mecha.seated_pilot == null, "Mecha has no seated pilot after eject")
	_assert(bool(mecha.get_meta("is_unoccupied")), "Mecha is marked unoccupied after eject")

	dummy_pilot.queue_free()
	mecha.queue_free()


func _test_pilot_spawning_and_lifecycle() -> void:
	var world_scene = load("res://scenes/war/war_world.tscn")
	_assert(world_scene != null, "war_world.tscn loaded")
	var world = world_scene.instantiate()
	add_child(world)

	var pilots := get_tree().get_nodes_in_group("pilot")
	_assert(pilots.size() >= 5, "World spawned pilots on foot across factions (got %d)" % pilots.size())

	var friendly_pilots: Array = []
	var enemy_pilots: Array = []
	for p in pilots:
		if p is WarPilotAgent:
			if (p as WarPilotAgent).team == "friendly":
				friendly_pilots.append(p)
			elif (p as WarPilotAgent).team == "enemy":
				enemy_pilots.append(p)

	_assert(friendly_pilots.size() >= 3, "Found %d friendly pilots on foot at Friendly Barracks" % friendly_pilots.size())
	_assert(enemy_pilots.size() >= 3, "Found %d enemy pilots on foot at Enemy Barracks" % enemy_pilots.size())

	# Verify Barracks spawn coordinates
	var fp0 = friendly_pilots[0] as WarPilotAgent
	_assert(fp0.global_position.z < -750.0, "Friendly pilot spawned at Friendly Barracks (Z = %.1f)" % fp0.global_position.z)

	var ep0 = enemy_pilots[0] as WarPilotAgent
	_assert(ep0.global_position.z > 750.0, "Enemy pilot spawned at Enemy Barracks (Z = %.1f)" % ep0.global_position.z)

	# Verify Pilot State Machine
	_assert(fp0.state == WarPilotAgent.PilotState.ON_FOOT_SEEKING_VEHICLE, "Pilot starts in ON_FOOT_SEEKING_VEHICLE state")

	world.queue_free()


func _test_emergency_eject_and_survival() -> void:
	var pilot = WarPilotAgent.new()
	pilot.name = "TestPilotEject"
	pilot.team = "friendly"
	add_child(pilot)

	var mecha_scene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha = mecha_scene.instantiate() as CharacterBody3D
	add_child(mecha)
	mecha.position = Vector3(10, 0, 10)

	# Board pilot into mecha
	pilot._board_existing_vehicle(mecha)
	_assert(pilot.state == WarPilotAgent.PilotState.PILOTING_COMBAT, "Pilot entered PILOTING_COMBAT state after boarding")
	_assert(not pilot.visible, "Pilot on-foot mesh hidden while inside cockpit")

	# Trigger emergency eject
	pilot._emergency_eject()
	_assert(pilot.state == WarPilotAgent.PilotState.EJECTED_SURVIVAL, "Pilot entered EJECTED_SURVIVAL state after emergency eject")
	_assert(pilot.visible, "Pilot on-foot mesh became visible after ejecting")
	_assert(pilot.current_vehicle == null, "Pilot is decoupled from vehicle after eject")

	pilot.queue_free()
	mecha.queue_free()
