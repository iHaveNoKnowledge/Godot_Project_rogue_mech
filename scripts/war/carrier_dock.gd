extends Node3D
class_name CarrierDock

## Carrier Dock — 2 ช่องจอดหลังกระบะ FREEZE+Reparent แก้ Jitter (per PLAN.md)

var _docked: Array[Node] = [null, null]


func create_carrier(pos: Vector3) -> Node3D:
	var carrier = CharacterBody3D.new()
	carrier.name = "Carrier"
	carrier.position = pos
	carrier.add_to_group("vehicle")
	carrier.add_to_group("carrier")
	carrier.collision_layer = 1
	carrier.collision_mask = 2
	var body = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(5.0, 2.5, 10.0)
	body.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.38, 0.32)
	body.material_override = mat
	carrier.add_child(body)
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(5.0, 2.5, 10.0)
	col.shape = shape
	carrier.add_child(col)
	# 2 Dock areas
	for i in 2:
		var dock = Area3D.new()
		dock.name = "Dock%d" % i
		dock.position = Vector3(-1.2 + i * 2.4, 1.5, -1.0)
		var dcol = CollisionShape3D.new()
		var dshape = BoxShape3D.new()
		dshape.size = Vector3(2.2, 2.0, 3.0)
		dcol.shape = dshape
		dock.add_child(dcol)
		dock.body_entered.connect(_on_dock_entered.bind(dock, i))
		dock.set_meta("dock_index", i)
		var lbl = Label3D.new()
		lbl.text = "DOCK %d\n[F] DOCK" % i
		lbl.font_size = 16
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.position = Vector3(0, 1.0, 0)
		dock.add_child(lbl)
		carrier.add_child(dock)
	# Weapon Rack
	var rack = Node3D.new()
	rack.name = "WeaponRack"
	rack.position = Vector3(0, 1.2, 2.5)
	carrier.add_child(rack)
	for w in 6:
		var slot = MeshInstance3D.new()
		var b = BoxMesh.new()
		b.size = Vector3(0.5, 0.3, 1.2)
		slot.mesh = b
		slot.position = Vector3(-1.5 + (w % 3) * 1.5, 0, (w / 3) * 1.0)
		var m = StandardMaterial3D.new()
		m.albedo_color = Color(0.6, 0.6, 0.65)
		slot.material_override = m
		rack.add_child(slot)
	carrier.add_child(_create_nav_agent())
	return carrier


func _create_nav_agent() -> NavigationAgent3D:
	var agent = NavigationAgent3D.new()
	agent.name = "NavAgent"
	agent.path_desired_distance = 1.5
	agent.target_desired_distance = 2.0
	return agent


func _on_dock_entered(body: Node, dock: Area3D, idx: int) -> void:
	if not body.is_in_group("mecha"):
		return
	if _docked[idx] != null:
		return
	dock_mech(body as Node3D, dock.get_parent() as Node3D, idx)


func dock_mech(mech: Node3D, carrier: Node3D, idx: int) -> void:
	if mech == null or carrier == null:
		return
	# FREEZE: disable physics/process
	mech.set_physics_process(false)
	if mech.has_method("set_frozen"):
		mech.set_frozen(true)
	# Reparent as child of carrier dock — fix jitter
	var dock_node = carrier.get_node_or_null("Dock%d" % idx)
	if dock_node == null:
		return
	var old_parent = mech.get_parent()
	if old_parent:
		old_parent.remove_child(mech)
	dock_node.add_child(mech)
	mech.position = Vector3.ZERO
	mech.rotation = Vector3.ZERO
	mech.set_meta("is_docked", true)
	mech.set_meta("docked_carrier", carrier.get_instance_id())
	_docked[idx] = mech
	# Park in HangarState
	if GlobalData.hangar:
		GlobalData.hangar.set_meta("docked_%d" % idx, mech.name)


func undock_mech(idx: int, carrier: Node3D) -> void:
	var mech = _docked[idx]
	if mech == null or not is_instance_valid(mech):
		return
	var dock_node = carrier.get_node_or_null("Dock%d" % idx)
	if dock_node and mech.get_parent() == dock_node:
		dock_node.remove_child(mech)
		carrier.get_parent().add_child(mech)
		mech.global_position = carrier.global_position + Vector3(5, 1, 0)
	mech.set_physics_process(true)
	if mech.has_method("set_frozen"):
		mech.set_frozen(false)
	mech.remove_meta("is_docked")
	_docked[idx] = null
