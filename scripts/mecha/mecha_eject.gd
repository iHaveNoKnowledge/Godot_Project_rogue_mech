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
	var backup_spawner = get_tree().current_scene.get_node_or_null("BackupSpawner")
	if backup_spawner and backup_spawner.has_method("spawn_backup_mech"):
		backup_spawner.spawn_backup_mech()
	EventBus.camera_mode_changed.emit("eject")
	EventBus.pilot_spawned.emit(pilot)
	GameManager.enter_eject()


func board_backup_mech(backup_mech: CharacterBody3D) -> void:
	var pilot = get_tree().current_scene.get_node_or_null("Pilot")
	if pilot:
		pilot.queue_free()
	var hangar_mech_id := str(backup_mech.get_meta("hangar_mech_id", ""))
	if hangar_mech_id != "":
		GlobalData.switch_hangar_mech(hangar_mech_id)
	mecha.global_position = backup_mech.global_position
	var health = mecha.get_node_or_null("HealthSystem")
	if health and health.has_method("_init_parts"):
		health._init_parts()
	var pmm = mecha.get_node_or_null("PartMeshManager")
	if pmm and pmm.has_method("refresh_slots"):
		pmm.refresh_slots()
	mecha.set_physics_process(true)
	mecha.get_node("CollisionShape3D").set_deferred("disabled", false)
	mecha.visible = true
	backup_mech.queue_free()
	EventBus.camera_mode_changed.emit("combat")
	GameManager.enter_combat()
