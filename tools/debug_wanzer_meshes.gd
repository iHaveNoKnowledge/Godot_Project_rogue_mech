extends SceneTree

func _init() -> void:
	var packed: PackedScene = load("res://scenes/test_wanzer.tscn")
	var root_node: Node = packed.instantiate()
	get_root().add_child(root_node)
	await process_frame
	await process_frame
	var mecha = root_node.get_node_or_null("MechaBase")
	if mecha == null:
		print("[DBG] no MechaBase")
		quit(1)
		return
	print("[DBG] MechaBase global pos: ", (mecha as Node3D).global_position)
	var total := 0
	_dump(mecha, 0, total)
	quit(0)

func _dump(n: Node, depth: int, total: int) -> void:
	var pad := ""
	for i in depth:
		pad += "  "
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		var info := "nil-mesh"
		if mesh != null:
			info = "surfaces=%d aabb=%s" % [mesh.get_surface_count(), str(mesh.get_aabb())]
		print("[DBG] ", pad, mi.name, " vis=", mi.visible, " gpos=", mi.global_position, " ", info)
		total += 1
	for c in n.get_children():
		_dump(c, depth + 1, total)
