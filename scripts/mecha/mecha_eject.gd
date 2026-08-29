class_name MechaEject
extends Node

## -----------------------------------------------------------------------------
## MECHA EJECT & BOARDING SYSTEM — GTA-Style Decoupled Pilot-Mech Transitions
##
## Supports:
##   • Voluntary Dismount anytime via [F] key.
##   • Emergency Eject upon catastrophic chassis destruction.
##   • Dynamic Boarding into ANY unoccupied mech on the battlefield (original,
##     backup, fleet units, or captured mechas).
## -----------------------------------------------------------------------------

@onready var mecha: CharacterBody3D = get_parent()

var pilot_scene: PackedScene = preload("res://scenes/pilot/pilot.tscn")


func _ready() -> void:
	pass


## Voluntary or emergency pilot dismount from the mech cockpit
func dismount_pilot(is_emergency: bool = false) -> void:
	if mecha == null or not is_instance_valid(mecha):
		return
	if mecha.has_meta("is_parked") or mecha.has_meta("is_unoccupied"):
		return

	if is_emergency:
		EventBus.eject_initiated.emit()

	# Put current mecha into power-down / standby state
	if mecha.has_method("power_down"):
		mecha.power_down()
	else:
		mecha.set_meta("is_parked", true)
		mecha.set_meta("is_unoccupied", true)
		mecha.set_physics_process(false)
		mecha.add_to_group("boardable_mech")
		mecha.add_to_group("backup_mech")

	# Spawn pilot on foot
	var pilot: CharacterBody3D = pilot_scene.instantiate()
	var parent_node = mecha.get_parent()
	if parent_node == null:
		parent_node = get_tree().current_scene
	parent_node.add_child(pilot)

	var eject_point = mecha.get_node_or_null("EjectPoint")
	if eject_point:
		pilot.global_position = eject_point.global_position
	else:
		pilot.global_position = mecha.global_position + Vector3(0, 0.5, -2.5)

	EventBus.camera_mode_changed.emit("eject")
	EventBus.mecha_occupancy_changed.emit(false)
	EventBus.pilot_spawned.emit(pilot)
	GameManager.enter_eject()


## Emergency eject backwards compatibility alias
func initiate_eject() -> void:
	dismount_pilot(true)


## Boards any target mecha on the field, waking it up and transferring controls
static func board_mecha(target_mecha: CharacterBody3D) -> void:
	if target_mecha == null or not is_instance_valid(target_mecha):
		return

	# Remove active on-foot pilot
	var tree = target_mecha.get_tree()
	if tree:
		var pilots = tree.get_nodes_in_group("pilot")
		for p in pilots:
			if is_instance_valid(p):
				p.queue_free()

	# Wake up target mecha
	if target_mecha.has_method("power_up"):
		target_mecha.power_up()
	else:
		target_mecha.remove_meta("is_parked")
		target_mecha.remove_meta("is_unoccupied")
		target_mecha.remove_from_group("boardable_mech")
		target_mecha.set_physics_process(true)
		target_mecha.visible = true
		var col = target_mecha.get_node_or_null("CollisionShape3D")
		if col:
			col.set_deferred("disabled", false)

	EventBus.camera_mode_changed.emit("combat")
	EventBus.mecha_occupancy_changed.emit(true)
	GameManager.resume_combat()


## Legacy alias for compatibility with existing callers
func board_parked_mecha(parked_mecha: CharacterBody3D) -> void:
	board_mecha(parked_mecha if parked_mecha else mecha)


## Legacy alias for backup mech boarding
func board_backup_mech(backup_mech: CharacterBody3D) -> void:
	board_mecha(backup_mech if backup_mech else mecha)
