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
	var part_name = part.part_name.to_lower() if (part and "part_name" in part) else ""
	var col = Color(0.4, 0.45, 0.52) # Default Armor Color
	if part and "part_color" in part:
		col = part.part_color
		
	var mat = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.75
	mat.roughness = 0.3
	
	var spike_mat = StandardMaterial3D.new()
	spike_mat.albedo_color = Color(0.18, 0.20, 0.22) # Dark Steel Spikes
	spike_mat.metallic = 0.95
	spike_mat.roughness = 0.2
	
	var is_spiky = part_name.contains("spike") or part_name.contains("raider") or part_name.contains("zaku") or part_name.contains("barbatos") or randf() < 0.65
	
	match slot_name.to_lower():
		"head":
			# Armored Visor + Crest Horn
			var base_mesh = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(0.5, 0.4, 0.5)
			base_mesh.mesh = box
			base_mesh.material_override = mat
			container.add_child(base_mesh)
			
			# Spiky Head Horn / Crest
			var horn = MeshInstance3D.new()
			var prism = PrismMesh.new()
			prism.size = Vector3(0.15, 0.35, 0.4)
			horn.mesh = prism
			horn.rotation_degrees.x = -20
			horn.position = Vector3(0, 0.3, -0.05)
			horn.material_override = spike_mat
			container.add_child(horn)
			
		"body":
			# Angled Chest Armor + Spiked Collar Ribs
			var chest = MeshInstance3D.new()
			var prism = PrismMesh.new()
			prism.size = Vector3(1.1, 0.9, 0.8)
			chest.mesh = prism
			chest.rotation_degrees.x = 90
			chest.material_override = mat
			container.add_child(chest)
			
			if is_spiky:
				for dir_x in [-0.55, 0.55]:
					var spike = MeshInstance3D.new()
					var cone = CylinderMesh.new()
					cone.top_radius = 0.0
					cone.bottom_radius = 0.12
					cone.height = 0.45
					spike.mesh = cone
					spike.position = Vector3(dir_x, 0.35, 0)
					spike.rotation_degrees.z = -55 if dir_x > 0 else 55
					spike.material_override = spike_mat
					container.add_child(spike)
					
		"arm_left", "arm_right":
			var is_left = slot_name.to_lower() == "arm_left"
			var dir_sign = -1.0 if is_left else 1.0
			
			# Shoulder Armor Shield / Pauldron
			var pauldron = MeshInstance3D.new()
			var p_mesh = CylinderMesh.new()
			p_mesh.top_radius = 0.28
			p_mesh.bottom_radius = 0.38
			p_mesh.height = 0.6
			pauldron.mesh = p_mesh
			pauldron.material_override = mat
			pauldron.position = Vector3(0, 0.3, 0)
			container.add_child(pauldron)
			
			# Spiky Shoulder Spikes (3 spikes radiating outwards)
			if is_spiky:
				for spike_angle in [-30.0, 0.0, 30.0]:
					var s = MeshInstance3D.new()
					var cone = CylinderMesh.new()
					cone.top_radius = 0.0
					cone.bottom_radius = 0.1
					cone.height = 0.5
					s.mesh = cone
					s.material_override = spike_mat
					s.position = Vector3(dir_sign * 0.35, 0.35, 0)
					s.rotation_degrees.z = -70 * dir_sign
					s.rotation_degrees.x = spike_angle
					container.add_child(s)
					
			# Forearm Armor Plate
			var forearm = MeshInstance3D.new()
			var f_box = BoxMesh.new()
			f_box.size = Vector3(0.42, 0.6, 0.42)
			forearm.mesh = f_box
			forearm.position = Vector3(0, -0.3, 0)
			forearm.material_override = mat
			container.add_child(forearm)

		"leg_left", "leg_right":
			# Thigh & Shin Armor Guard
			var shin = MeshInstance3D.new()
			var prism = PrismMesh.new()
			prism.size = Vector3(0.55, 1.1, 0.55)
			shin.mesh = prism
			shin.rotation_degrees.x = 90
			shin.material_override = mat
			container.add_child(shin)
			
			# Knee Spike Guard
			if is_spiky:
				var k_spike = MeshInstance3D.new()
				var cone = CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.11
				cone.height = 0.45
				k_spike.mesh = cone
				k_spike.material_override = spike_mat
				k_spike.position = Vector3(0, 0.25, 0.32)
				k_spike.rotation_degrees.x = 65
				container.add_child(k_spike)

		_:
			var box = BoxMesh.new()
			box.size = Vector3(0.6, 0.6, 0.6)
			var base_mesh = MeshInstance3D.new()
			base_mesh.mesh = box
			base_mesh.material_override = mat
			container.add_child(base_mesh)
