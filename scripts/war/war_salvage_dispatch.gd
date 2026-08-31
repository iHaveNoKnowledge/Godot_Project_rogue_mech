extends Node
class_name WarSalvageDispatch

## Enemy drop 35-50% Part/Weapon + call Truck from branch base (per PLAN.md 7.6)

func try_spawn_salvage(pos: Vector3, parent: Node) -> void:
	if randf() > 0.45:
		return
	var is_weapon = randf() < 0.5
	var salvage = Area3D.new()
	salvage.name = "Salvage"
	salvage.position = pos + Vector3(0, 0.5, 0)
	salvage.add_to_group("salvage")
	var mi = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(1.5, 1.0, 1.5)
	mi.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.65, 0.2) if is_weapon else Color(0.6, 0.65, 0.7)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 1.0
	mi.material_override = mat
	salvage.add_child(mi)
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(3, 2, 3)
	col.shape = shape
	salvage.add_child(col)
	var lbl = Label3D.new()
	lbl.text = "SALVAGE %s\nCall Truck [T]" % ("WEAPON" if is_weapon else "PART")
	lbl.font_size = 18
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0, 2.0, 0)
	salvage.add_child(lbl)
	salvage.set_meta("is_weapon", is_weapon)
	parent.add_child(salvage)


func dispatch_truck(from_base_pos: Vector3, salvage: Node) -> Node3D:
	var truck = WarLogisticSystem.new().create_truck(from_base_pos, from_base_pos)
	truck.set_meta("target_salvage", salvage.get_instance_id())
	# Simple AI: move toward salvage
	var agent = truck.get_node_or_null("NavAgent") as NavigationAgent3D
	if agent:
		agent.target_position = salvage.global_position
	truck.get_parent().add_child(truck)
	return truck
