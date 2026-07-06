extends Node

@onready var mecha: CharacterBody3D = get_parent()

var pilot_scene: PackedScene = preload("res://scenes/pilot/pilot.tscn")


func _ready() -> void:
	pass


func initiate_eject() -> void:
	EventBus.eject_initiated.emit()
	var pilot = pilot_scene.instantiate()
	mecha.get_parent().add_child(pilot)
	pilot.global_position = mecha.get_node("EjectPoint").global_position
	mecha.set_physics_process(false)
	mecha.get_node("CollisionShape3D").set_deferred("disabled", true)
	mecha.visible = false
	EventBus.camera_mode_changed.emit("eject")
	EventBus.pilot_spawned.emit(pilot)
	GameManager.enter_eject()


func board_backup_mech(backup_mech: CharacterBody3D) -> void:
	var pilot = mecha.get_parent().get_node_or_null("Pilot")
	if pilot:
		pilot.queue_free()
	mecha.global_position = backup_mech.global_position
	mecha.set_physics_process(true)
	mecha.get_node("CollisionShape3D").set_deferred("disabled", false)
	mecha.visible = true
	backup_mech.queue_free()
	EventBus.camera_mode_changed.emit("combat")
	GameManager.enter_combat()
