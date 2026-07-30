extends Node3D

var slot_meshes: Dictionary = {}


func _ready() -> void:
	EventBus.part_destroyed.connect(_on_part_destroyed)


func initialize_slot(slot_name: String, part: ArmorPart) -> void:
	var parent_node = _get_slot_parent_node(slot_name)
	if parent_node == null:
		return

	var frame_mesh = parent_node.get_node_or_null("FrameMesh")
	if frame_mesh == null:
		frame_mesh = Node3D.new()
		frame_mesh.name = "FrameMesh"
		parent_node.add_child(frame_mesh)

	var armor_mesh = parent_node.get_node_or_null("ArmorMesh")
	if armor_mesh == null:
		armor_mesh = Node3D.new()
		armor_mesh.name = "ArmorMesh"
		parent_node.add_child(armor_mesh)

	slot_meshes[slot_name] = {"armor": armor_mesh, "frame": frame_mesh}

	# 1. Build Inner Frame (Always visible slim skeletal frame)
	_clear_children(frame_mesh)
	if part and part.inner_frame_scene:
		var instance = part.inner_frame_scene.instantiate()
		frame_mesh.add_child(instance)
	else:
		_build_procedural_inner_frame(slot_name, frame_mesh)
	frame_mesh.visible = true

	# 2. Build Outer Armor Plate (Layered on top, hidden on Armor Break)
	_clear_children(armor_mesh)
	if part and part.mesh_scene:
		var instance = part.mesh_scene.instantiate()
		armor_mesh.add_child(instance)
	else:
		_build_procedural_outer_armor(slot_name, armor_mesh, part)

	var armor_dmg = GlobalData.part_damage.get(slot_name + "_armor", 0.0)
	var max_hp = part.durability if part else 100.0
	if armor_dmg >= max_hp:
		_show_inner_frame(slot_name)
	else:
		armor_mesh.visible = true


func _get_slot_parent_node(slot_name: String) -> Node3D:
	var mecha = get_parent()
	if not mecha:
		return null
	match slot_name.to_lower():
		"head": return mecha.get_node_or_null("Head")
		"body": return mecha.get_node_or_null("Body")
		"arm_left": return mecha.get_node_or_null("ArmLeft")
		"arm_right": return mecha.get_node_or_null("ArmRight")
		"leg_left": return mecha.get_node_or_null("LegLeft")
		"leg_right": return mecha.get_node_or_null("LegRight")
	return null


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _on_part_destroyed(slot_name: String) -> void:
	_show_inner_frame(slot_name)
	_spawn_break_vfx(slot_name)


func _show_inner_frame(slot_name: String) -> void:
	var entry = slot_meshes.get(slot_name)
	if entry == null:
		return
	# Remove outer armor plate mesh, exposing thin skeletal inner frame underneath
	entry["armor"].visible = false
	entry["frame"].visible = true


func repair_slot(slot_name: String) -> void:
	var entry = slot_meshes.get(slot_name)
	if entry == null:
		return
	entry["armor"].visible = true
	entry["frame"].visible = true


func _destroy_frame(slot_name: String) -> void:
	var entry = slot_meshes.get(slot_name)
	if entry == null:
		return
	entry["armor"].visible = false
	entry["frame"].visible = false
	_spawn_destroy_vfx(slot_name)


func _spawn_break_vfx(slot_name: String) -> void:
	var entry = slot_meshes.get(slot_name)
	if entry == null or entry["frame"] == null:
		return
	var origin_pos = entry["frame"].global_position
	
	# Spawn 5 flying armor debris chunks (armor plate popping off)
	for i in range(5):
		var debris = RigidBody3D.new()
		debris.global_position = origin_pos + Vector3(randf_range(-0.3, 0.3), randf_range(0.2, 0.6), randf_range(-0.3, 0.3))
		
		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(randf_range(0.15, 0.35), randf_range(0.15, 0.35), randf_range(0.1, 0.2))
		col.shape = shape
		debris.add_child(col)
		
		var mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = shape.size
		mesh_inst.mesh = box
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.38, 0.42)
		mat.metallic = 0.7
		mat.roughness = 0.4
		mesh_inst.material_override = mat
		debris.add_child(mesh_inst)
		
		get_tree().current_scene.add_child(debris)
		
		# Impulse to pop armor off away from mech center
		var impulse = Vector3(randf_range(-4, 4), randf_range(3, 7), randf_range(-4, 4))
		debris.apply_central_impulse(impulse)
		
		# Auto cleanup after 3 seconds
		var tween = debris.create_tween()
		tween.tween_property(mesh_inst, "scale", Vector3.ZERO, 0.5).set_delay(2.5)
		tween.tween_callback(debris.queue_free)
		
	var vfx_scene = load("res://scenes/mecha/effects/vfx_armor_break.tscn")
	if vfx_scene:
		var vfx = vfx_scene.instantiate()
		entry["armor"].get_parent().add_child(vfx)
		vfx.global_position = entry["armor"].global_position


func _spawn_destroy_vfx(slot_name: String) -> void:
	pass

func _build_procedural_inner_frame(slot_name: String, container: Node3D) -> void:
	var mesh_inst = MeshInstance3D.new()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.22, 0.25)
	mat.metallic = 0.95
	mat.roughness = 0.3
	mesh_inst.material_override = mat

	match slot_name.to_lower():
		"head":
			var cyl = CylinderMesh.new()
			cyl.top_radius = 0.08
			cyl.bottom_radius = 0.12
			cyl.height = 0.35
			mesh_inst.mesh = cyl
		"body":
			var box = BoxMesh.new()
			box.size = Vector3(0.4, 1.4, 0.35)
			mesh_inst.mesh = box
		"arm_left", "arm_right":
			var cyl = CylinderMesh.new()
			cyl.top_radius = 0.07
			cyl.bottom_radius = 0.07
			cyl.height = 1.2
			mesh_inst.mesh = cyl
		"leg_left", "leg_right":
			var cyl = CylinderMesh.new()
			cyl.top_radius = 0.09
			cyl.bottom_radius = 0.09
			cyl.height = 1.6
			mesh_inst.mesh = cyl
		_:
			var box = BoxMesh.new()
			box.size = Vector3(0.2, 0.8, 0.2)
			mesh_inst.mesh = box

	container.add_child(mesh_inst)

func _build_procedural_outer_armor(slot_name: String, container: Node3D, part: ArmorPart) -> void:
	var mesh_inst = MeshInstance3D.new()
	var mat = StandardMaterial3D.new()
	var col = Color(0.4, 0.45, 0.52)
	if part and "part_color" in part:
		col = part.part_color
	mat.albedo_color = col
	mat.metallic = 0.7
	mat.roughness = 0.35
	mesh_inst.material_override = mat

	match slot_name.to_lower():
		"head":
			var box = BoxMesh.new()
			box.size = Vector3(0.52, 0.45, 0.52)
			mesh_inst.mesh = box
		"body":
			var box = BoxMesh.new()
			box.size = Vector3(1.1, 0.95, 0.85)
			mesh_inst.mesh = box
		"arm_left", "arm_right":
			var box = BoxMesh.new()
			box.size = Vector3(0.45, 0.85, 0.45)
			mesh_inst.mesh = box
		"leg_left", "leg_right":
			var box = BoxMesh.new()
			box.size = Vector3(0.55, 1.1, 0.55)
			mesh_inst.mesh = box
		_:
			var box = BoxMesh.new()
			box.size = Vector3(0.6, 0.6, 0.6)
			mesh_inst.mesh = box

	container.add_child(mesh_inst)
