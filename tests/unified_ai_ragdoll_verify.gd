extends Node

const MechaAIController = preload("res://scripts/mecha/ai/mecha_ai_controller.gd")
const WarPilotAgent = preload("res://scripts/war/war_pilot_agent.gd")
const MechaRagdoll = preload("res://scripts/mecha/mecha_ragdoll.gd")

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	print("=== Starting Unified AI, Ragdoll & Combat Verification ===")
	_test_mecha_ai_controller()
	_test_mecha_ragdoll_spawn()
	_test_war_pilot_ejection()
	_test_enemy_dummy_ragdoll()

	print("=== Unified AI & Ragdoll Finished: %d passed, %d failed ===" % [_passed, _failed])
	if _failed == 0:
		print("ALL_UNIFIED_AI_RAGDOLL_TESTS_PASSED")
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("UNIFIED_OK: %s" % label)
	else:
		_failed += 1
		push_error("UNIFIED_FAIL: %s" % label)


func _test_mecha_ai_controller() -> void:
	var mecha_scene = load("res://scenes/mecha/mecha_base.tscn")
	_assert(mecha_scene != null, "Loaded mecha_base.tscn")
	var mecha = mecha_scene.instantiate() as CharacterBody3D
	add_child(mecha)
	mecha.global_position = Vector3(0, 0, 0)

	var ai = MechaAIController.new()
	ai.name = "TestAIController"
	ai.actor = mecha
	ai.faction_team = "friendly"
	ai.preferred_range = 20.0
	ai.min_retreat_range = 10.0
	mecha.add_child(ai)

	# 1. Target acquisition
	var enemy_dummy = CharacterBody3D.new()
	enemy_dummy.name = "TargetEnemy"
	enemy_dummy.add_to_group("enemy")
	add_child(enemy_dummy)
	enemy_dummy.global_position = Vector3(0, 0, 50.0)

	var found = ai.acquire_target(100.0)
	_assert(found == enemy_dummy, "MechaAIController acquired enemy in 'enemy' group")

	# 2. Advance decision when far (> preferred_range)
	var cmds = ai.update_ai_decisions(0.016)
	_assert(cmds["move_direction"].z > 0.5, "MechaAIController advances toward distant target (move_dir.z = %.2f)" % cmds["move_direction"].z)
	_assert(cmds["aim_point"].z > 40.0, "MechaAIController aims toward target (aim_point.z = %.2f)" % cmds["aim_point"].z)

	# 3. Strafe decision when in sweet spot
	enemy_dummy.global_position = Vector3(0, 0, 18.0)
	cmds = ai.update_ai_decisions(0.016)
	_assert(absf(cmds["move_direction"].x) > 0.5, "MechaAIController performs lateral circle-strafe in combat range (move_dir.x = %.2f)" % cmds["move_direction"].x)

	# 4. Weapon firing check when facing target
	mecha.rotation.y = deg_to_rad(180.0) # Face towards +Z
	cmds = ai.update_ai_decisions(0.016)
	_assert(cmds["fire_left"] == true, "MechaAIController triggers primary weapon within effective range")

	# Clean up
	enemy_dummy.queue_free()
	mecha.queue_free()


func _test_mecha_ragdoll_spawn() -> void:
	var mecha_scene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha = mecha_scene.instantiate() as CharacterBody3D
	add_child(mecha)
	mecha.global_position = Vector3(0, 5, 0)

	var ragdoll_res = MechaRagdoll.spawn_ragdoll(mecha)
	_assert(ragdoll_res.has("bodies"), "MechaRagdoll.spawn_ragdoll returns 'bodies'")
	_assert(ragdoll_res.has("joints"), "MechaRagdoll.spawn_ragdoll returns 'joints'")
	var bodies: Array = ragdoll_res.get("bodies", [])
	var joints: Array = ragdoll_res.get("joints", [])
	_assert(bodies.size() == 10, "Ragdoll created exactly 10 segment RigidBody3D pieces (got %d)" % bodies.size())
	_assert(joints.size() >= 8, "Ragdoll created PinJoint3D constraints between limbs (got %d)" % joints.size())

	# Verify physics pieces are added to tree
	for b in bodies:
		_assert(b.is_inside_tree(), "Ragdoll piece '%s' is active in SceneTree" % b.name)
		_assert(b is RigidBody3D, "Ragdoll piece is a RigidBody3D")

	# Cleanup ragdoll pieces
	for j in joints:
		if is_instance_valid(j):
			j.queue_free()
	for b in bodies:
		if is_instance_valid(b):
			b.queue_free()
	mecha.queue_free()


func _test_war_pilot_ejection() -> void:
	var mecha_scene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha = mecha_scene.instantiate() as CharacterBody3D
	add_child(mecha)
	mecha.global_position = Vector3(0, 2, 0)

	var pilot = WarPilotAgent.new()
	pilot.team = "friendly"
	pilot.pilot_name = "TestPilot"
	add_child(pilot)

	# Board vehicle
	pilot._board_existing_vehicle(mecha)
	_assert(pilot.state == WarPilotAgent.PilotState.PILOTING_COMBAT, "Pilot is in PILOTING_COMBAT state")
	_assert(pilot.current_vehicle == mecha, "Pilot is seated inside mecha")
	_assert(pilot.ai_controller != null, "Pilot created MechaAIController to drive vehicle")

	# Trigger destruction / collapse
	mecha._eject_pilot()
	_assert(pilot.state == WarPilotAgent.PilotState.EJECTED_SURVIVAL, "Pilot entered EJECTED_SURVIVAL state after mech destruction")
	_assert(pilot.visible == true, "On-foot pilot mesh became visible")
	_assert(pilot.current_vehicle == null, "Pilot decoupled from destroyed vehicle")
	_assert(pilot.velocity.y > 4.0, "Pilot was launched upward on ejection (velocity.y = %.2f)" % pilot.velocity.y)

	pilot.queue_free()
	mecha.queue_free()


func _test_enemy_dummy_ragdoll() -> void:
	var enemy_scene = load("res://scenes/mecha/enemy_dummy.tscn")
	if enemy_scene == null:
		print("UNIFIED_OK: enemy_dummy.tscn skipped (not present)")
		return
	var enemy = enemy_scene.instantiate() as CharacterBody3D
	add_child(enemy)
	enemy.global_position = Vector3(0, 5, 0)

	_assert(enemy.has_method("set_drive_commands"), "EnemyDummy has unified set_drive_commands method")

	# Call _tilt_over directly and verify ragdoll bodies
	enemy._tilt_over()
	_assert(enemy.has_meta("ragdoll_bodies"), "EnemyDummy _tilt_over creates physics ragdoll bodies")
	var bodies = enemy.get_meta("ragdoll_bodies")
	_assert(bodies is Array and (bodies as Array).size() == 10, "EnemyDummy spawned 10 ragdoll pieces")

	# Cleanup ragdoll pieces
	if enemy.has_meta("ragdoll_joints"):
		for j in enemy.get_meta("ragdoll_joints"):
			if is_instance_valid(j):
				j.queue_free()
	if bodies is Array:
		for b in bodies:
			if is_instance_valid(b):
				b.queue_free()
	enemy.queue_free()
