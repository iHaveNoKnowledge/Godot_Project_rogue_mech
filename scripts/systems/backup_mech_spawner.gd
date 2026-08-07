extends Node

@export var team_mode: String = "solo"


func spawn_backup_mech() -> void:
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	var base_pos = mecha.global_position if mecha else Vector3.ZERO
	var spawn_pos: Vector3
	if team_mode == "team":
		spawn_pos = base_pos + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
	else:
		spawn_pos = base_pos + Vector3(randf_range(8, 15), 0, randf_range(8, 15))
	spawn_pos.y = 0.0

	var backup = CharacterBody3D.new()
	backup.name = "BackupMech"
	backup.add_to_group("backup_mech")

	var collision = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.height = 4.5
	shape.radius = 1.0
	collision.shape = shape
	collision.position.y = 2.25
	backup.add_child(collision)

	var mesh = MeshInstance3D.new()
	var capsule_mesh = CapsuleMesh.new()
	capsule_mesh.height = 4.5
	capsule_mesh.radius = 1.0
	mesh.mesh = capsule_mesh
	mesh.position.y = 2.25
	backup.add_child(mesh)

	get_parent().add_child(backup)
	backup.global_position = spawn_pos
