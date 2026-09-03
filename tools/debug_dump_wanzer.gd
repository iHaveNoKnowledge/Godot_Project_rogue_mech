extends Node3D

func _ready() -> void:
	var packed: PackedScene = load("res://scenes/test_wanzer.tscn")
	var inst: Node = packed.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	var mecha = inst.get_node_or_null("MechaBase")
	if mecha == null:
		print("[DBG] no MechaBase")
		get_tree().quit(1)
		return
	print("[DBG] MechaBase gpos=", (mecha as Node3D).global_position)
	_dump(mecha, 0)
	get_tree().quit(0)

func _dump(n: Node, depth: int) -> void:
	var pad := ""
	for i in depth:
		pad += "  "
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var info := "nil-mesh"
		if mi.mesh != null:
			info = "surfaces=%d aabb=%s" % [mi.mesh.get_surface_count(), str(mi.mesh.get_aabb())]
		print("[DBG] ", pad, mi.name, " vis=", mi.visible, " gpos=", (mi as Node3D).global_position, " ", info)
	for c in n.get_children():
		_dump(c, depth + 1)
