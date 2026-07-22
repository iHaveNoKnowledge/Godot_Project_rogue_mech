extends Node

@export var team_mode: String = "solo"


func spawn_backup_mech() -> void:
	var spawn_pos: Vector3
	if team_mode == "team":
		spawn_pos = Vector3(randf_range(-10, 10), 5, randf_range(-10, 10))
	else:
		spawn_pos = Vector3(randf_range(40, 60), 20, randf_range(40, 60))

	var backup = CharacterBody3D.new()
	backup.name = "BackupMech"
	backup.add_to_group("backup_mech")

	var collision = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.height = 3.5
	shape.radius = 0.8
	collision.shape = shape
	collision.position.y = 1.75
	backup.add_child(collision)

	var mesh = MeshInstance3D.new()
	var capsule_mesh = CapsuleMesh.new()
	capsule_mesh.height = 3.5
	capsule_mesh.radius = 0.8
	mesh.mesh = capsule_mesh
	mesh.position.y = 1.75
	backup.add_child(mesh)

	get_parent().add_child(backup)
	backup.global_position = spawn_pos
