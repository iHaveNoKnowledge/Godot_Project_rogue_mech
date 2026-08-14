extends Node

@export var team_mode: String = "solo"


func spawn_backup_mech() -> void:
	var mecha = GameManager.get_player_mecha()
	var backup_id := GlobalData.get_backup_hangar_mech_id()
	if backup_id == "":
		push_warning("No second built mech is stored in the hangar.")
		return
	GlobalData.switch_hangar_mech(backup_id)
	var base_pos = mecha.global_position if mecha else Vector3.ZERO
	var spawn_pos: Vector3
	if team_mode == "team":
		spawn_pos = base_pos + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
	else:
		spawn_pos = base_pos + Vector3(randf_range(8, 15), 0, randf_range(8, 15))
	spawn_pos.y = 0.0

	var backup = preload("res://scenes/mecha/mecha_base.tscn").instantiate()
	backup.name = "BackupMech"
	backup.add_to_group("backup_mech")
	backup.set_meta("hangar_mech_id", backup_id)
	# The parked machine is a real built mech, but it does not consume player
	# input while the pilot is walking toward it.
	backup.set_physics_process(false)
	for child in backup.get_children():
		child.set_process(false)
		child.set_physics_process(false)

	get_parent().add_child(backup)
	var pmm = backup.get_node_or_null("PartMeshManager")
	if pmm and pmm.has_method("refresh_slots"):
		pmm.refresh_slots()
	# An empty machine waits kneeling for its pilot — same occupancy rule as
	# the main mech after an eject. The generic child disable above stopped the
	# animation too, so wake just the AnimationSystem and seed the pose.
	var anim = backup.get_node_or_null("AnimationSystem")
	if anim:
		anim.set_process(true)
		anim.set_physics_process(true)
		if anim.has_method("set_kneeling"):
			anim.set_kneeling(true)
	backup.global_position = spawn_pos
