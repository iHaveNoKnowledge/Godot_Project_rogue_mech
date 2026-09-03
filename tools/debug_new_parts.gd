extends Node3D
# Debug: equip NEW clean HY parts (001) instead of old split parts, then dump AABBs.

func _ready() -> void:
	var base_res: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha = base_res.instantiate()
	add_child(mecha)
	await get_tree().process_frame
	await get_tree().process_frame
	var pm = mecha.get_node_or_null("PartMeshManager")
	if pm == null:
		print("[DBG2] no PartMeshManager")
		get_tree().quit(1)
		return
	var loadout := {
		"head": {"frame": {"id": "frame_head_01", "equipped": true}, "armor": {"id": "wanzer_head_001", "equipped": true, "path": "res://resources/mech/parts/head/wanzer_head_001.tres", "slot": "head"}},
		"body": {"frame": {"id": "frame_body_01", "equipped": true}, "armor": {"id": "wanzer_body_001", "equipped": true, "path": "res://resources/mech/parts/body/wanzer_body_001.tres", "slot": "body"}},
		"arm_left": {"frame": {"id": "frame_arm_left_01", "equipped": true}, "armor": {"id": "wanzer_arm_left_001", "equipped": true, "path": "res://resources/mech/parts/arm_left/wanzer_arm_left_001.tres", "slot": "arm_left"}},
		"arm_right": {"frame": {"id": "frame_arm_right_01", "equipped": true}, "armor": {"id": "wanzer_arm_right", "equipped": true, "path": "res://resources/mech/parts/arm_right/wanzer_arm_right.tres", "slot": "arm_right"}},
		"leg_left": {"frame": {"id": "frame_leg_left_01", "equipped": true}, "armor": {"id": "wanzer_leg_left_001", "equipped": true, "path": "res://resources/mech/parts/leg_left/wanzer_leg_left_001.tres", "slot": "leg_left"}},
		"leg_right": {"frame": {"id": "frame_leg_right_01", "equipped": true}, "armor": {"id": "wanzer_leg_right", "equipped": true, "path": "res://resources/mech/parts/leg_right/wanzer_leg_right.tres", "slot": "leg_right"}},
	}
	pm.refresh_from_loadout(loadout)
	await get_tree().process_frame
	print("[DBG2] new-part AABBs (world):")
	_dump_armor(mecha)
	get_tree().quit(0)

func _dump_armor(n: Node) -> void:
	if n.name == "ArmorMesh":
		for c in n.get_children():
			_walk(c)
	for c in n.get_children():
		_dump_armor(c)

func _walk(n: Node) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		var aabb: AABB = (mi as Node3D).global_transform * mi.mesh.get_aabb()
		print("[DBG2] slot-mesh name=", mi.name, " parent=", (mi.get_parent() as Node).name, " gscale=", (mi as Node3D).global_scale, " gpos=", (mi as Node3D).global_position, " world_aabb=P", aabb.position, " S=", aabb.size)
	for c in n.get_children():
		_walk(c)
