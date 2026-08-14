extends Node

@onready var mecha: CharacterBody3D = get_parent()

var pilot_scene: PackedScene = preload("res://scenes/pilot/pilot.tscn")


func _ready() -> void:
	pass


func initiate_eject() -> void:
	# One pilot per cockpit: an already-parked mech has its pilot out on the
	# field, so a repeat eject (e.g. pressing the key again) must not spawn a
	# second pilot. Boarding clears the parked state, re-arming the eject.
	if mecha.has_meta("is_parked"):
		return
	EventBus.eject_initiated.emit()
	# The cockpit is now empty: the mech kneels until its pilot boards again.
	EventBus.mecha_occupancy_changed.emit(false)
	var pilot = pilot_scene.instantiate()
	var parent_node = mecha.get_parent()
	if parent_node == null:
		parent_node = get_tree().current_scene
	parent_node.add_child(pilot)

	var eject_point = mecha.get_node_or_null("EjectPoint")
	if eject_point:
		pilot.global_position = eject_point.global_position
	else:
		pilot.global_position = mecha.global_position + Vector3(0, 1.5, -2.0)

	# Park the mech in place — keep it visible and solid, but suspend active movement.
	mecha.set_meta("is_parked", true)
	mecha.set_physics_process(false)
	mecha.visible = true
	# The parked mech becomes the boarding target: the pilot's interact area
	# only tracks bodies in the "backup_mech" group, so without this the pilot
	# could never climb back in (boarding was unreachable after eject).
	mecha.add_to_group("backup_mech")

	EventBus.camera_mode_changed.emit("eject")
	EventBus.pilot_spawned.emit(pilot)
	GameManager.enter_eject()


func board_parked_mecha(parked_mecha: CharacterBody3D) -> void:
	var pilot = get_tree().current_scene.get_node_or_null("Pilot")
	if pilot == null:
		var pilots = get_tree().get_nodes_in_group("pilot")
		if not pilots.is_empty():
			pilot = pilots[0]
	if pilot:
		pilot.queue_free()

	if parked_mecha and parked_mecha.has_meta("is_parked"):
		parked_mecha.remove_meta("is_parked")

	# No longer a boarding target now that the pilot is seated again.
	mecha.remove_from_group("backup_mech")

	mecha.set_physics_process(true)
	mecha.visible = true
	var col = mecha.get_node_or_null("CollisionShape3D")
	if col:
		col.set_deferred("disabled", false)

	EventBus.camera_mode_changed.emit("combat")
	# A pilot is seated again: the mech stands back up.
	EventBus.mecha_occupancy_changed.emit(true)
	# Resume the SAME battle — never enter_combat(), which would reload the
	# combat scene and restart the fight (new arena, respawned enemies).
	GameManager.resume_combat()


func board_backup_mech(backup_mech: CharacterBody3D) -> void:
	board_parked_mecha(mecha)
	if backup_mech and is_instance_valid(backup_mech) and backup_mech != mecha:
		backup_mech.queue_free()
