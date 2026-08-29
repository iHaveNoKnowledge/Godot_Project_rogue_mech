extends Node

const MechaEject = preload("res://scripts/mecha/mecha_eject.gd")

func _ready() -> void:
	print("--- Running pilot_mech_decoupling_verify ---")
	_test_mecha_dismount_flow()
	_test_pilot_proximity_and_boarding()
	_test_switching_between_multiple_mechas()
	print("All pilot_mech_decoupling_verify tests passed successfully!")
	get_tree().quit(0)

func _check(condition: bool, msg: String) -> void:
	if condition:
		print("  PASS: %s" % msg)
	else:
		push_error("  FAIL: %s" % msg)
		assert(condition, msg)

func _test_mecha_dismount_flow() -> void:
	print("Testing Mecha Voluntary Dismount Flow...")
	var mecha := CharacterBody3D.new()
	mecha.name = "Mecha_Alpha"
	var mecha_script = preload("res://scripts/mecha/mecha_controller.gd")
	mecha.set_script(mecha_script)
	add_child(mecha)
	mecha.global_position = Vector3(10, 0, 10)

	GameManager.current_state = GameManager.State.COMBAT

	# Trigger dismount
	mecha.dismount()

	_check(mecha.has_meta("is_parked"), "Mecha Alpha marked as parked")
	_check(mecha.has_meta("is_unoccupied"), "Mecha Alpha marked as unoccupied")
	_check(mecha.is_in_group("boardable_mech"), "Mecha Alpha added to boardable_mech group")
	_check(GameManager.current_state == GameManager.State.EJECT, "Game state transitioned to EJECT")

	var pilots = get_tree().get_nodes_in_group("pilot")
	_check(not pilots.is_empty(), "Pilot on-foot instance spawned in scene")

	# Clean up pilot
	for p in pilots:
		p.queue_free()
	mecha.queue_free()

func _test_pilot_proximity_and_boarding() -> void:
	print("Testing Pilot Proximity Detection and Boarding...")
	var mecha := CharacterBody3D.new()
	mecha.name = "Mecha_Beta"
	var mecha_script = preload("res://scripts/mecha/mecha_controller.gd")
	mecha.set_script(mecha_script)
	add_child(mecha)
	mecha.global_position = Vector3(0, 0, 0)
	mecha.power_down()

	var pilot := CharacterBody3D.new()
	var pilot_script = preload("res://scripts/pilot/pilot_controller.gd")
	pilot.set_script(pilot_script)
	add_child(pilot)
	pilot.global_position = Vector3(0, 0, 2.0) # 2 meters away (within 4.5m radius)

	var nearest = pilot.find_nearest_boardable_mech()
	_check(nearest == mecha, "Pilot successfully detected nearby Mecha Beta")

	# Execute Boarding
	MechaEject.board_mecha(mecha)

	_check(not mecha.has_meta("is_parked"), "Mecha Beta is no longer parked")
	_check(not mecha.has_meta("is_unoccupied"), "Mecha Beta is no longer unoccupied")
	_check(not mecha.is_in_group("boardable_mech"), "Mecha Beta removed from boardable_mech group")
	_check(GameManager.current_state == GameManager.State.COMBAT, "Combat resumed after boarding")

	mecha.queue_free()

func _test_switching_between_multiple_mechas() -> void:
	print("Testing Switching Between Multiple Independent Mechas...")
	# Spawn Mech 1
	var mech1 := CharacterBody3D.new()
	mech1.name = "Gundam_Unit_01"
	mech1.set_script(preload("res://scripts/mecha/mecha_controller.gd"))
	add_child(mech1)
	mech1.global_position = Vector3(0, 0, 0)

	# Spawn Mech 2
	var mech2 := CharacterBody3D.new()
	mech2.name = "Zaku_Unit_02"
	mech2.set_script(preload("res://scripts/mecha/mecha_controller.gd"))
	add_child(mech2)
	mech2.global_position = Vector3(15, 0, 0)
	mech2.power_down()

	GameManager.current_state = GameManager.State.COMBAT

	# Dismount from Mech 1
	mech1.dismount()
	_check(mech1.has_meta("is_parked"), "Mech 1 is parked")

	# Move pilot to Mech 2
	var pilots = get_tree().get_nodes_in_group("pilot")
	_check(not pilots.is_empty(), "Pilot is active on foot")
	var pilot: CharacterBody3D = pilots[0]
	pilot.global_position = Vector3(15, 0, 1.5)

	var target = pilot.find_nearest_boardable_mech()
	_check(target == mech2, "Pilot targets Mech 2 near position (15, 0, 0)")

	# Board Mech 2
	MechaEject.board_mecha(mech2)

	_check(not mech2.has_meta("is_parked"), "Mech 2 powered up and active")
	_check(mech1.has_meta("is_parked"), "Mech 1 remains parked and intact without getting deleted")
	_check(is_instance_valid(mech1), "Mech 1 is still a valid physical entity in world")

	mech1.queue_free()
	mech2.queue_free()
