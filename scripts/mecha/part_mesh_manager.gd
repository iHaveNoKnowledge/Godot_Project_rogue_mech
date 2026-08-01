extends Node3D

var slot_meshes: Dictionary = {}

func _ready() -> void:
	EventBus.part_destroyed.connect(_on_part_destroyed)


func initialize_slot(slot_name: String, part: ArmorPart) -> void:
	var parent_node = _get_slot_parent_node(slot_name)
	if parent_node == null:
		return

	# Hide legacy placeholder primitives in mecha_base.tscn
	_hide_legacy_slot_meshes(parent_node)

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

	# 1. Build Inner Frame (Always visible detailed mechanical robotic skeleton)
	_clear_children(frame_mesh)
	if part and part.inner_frame_scene:
		var instance = part.inner_frame_scene.instantiate()
		frame_mesh.add_child(instance)
	else:
		_build_procedural_inner_frame(slot_name, frame_mesh)
	frame_mesh.visible = true

	# 2. Build Outer Armor Plate (Form-fitting plates mounted over inner frame)
	_clear_children(armor_mesh)
	if part and part.mesh_scene:
		var instance = part.mesh_scene.instantiate()
		armor_mesh.add_child(instance)
	else:
		_build_procedural_outer_armor(slot_name, armor_mesh, part)

	var armor_dmg = GlobalData.part_damage.get(slot_name + "_armor", 0.0)
	var max_hp = part.max_hp if part else 100.0
	if armor_dmg >= max_hp:
		_show_inner_frame(slot_name)
	else:
		armor_mesh.visible = true


func _hide_legacy_slot_meshes(parent_node: Node3D) -> void:
	for child in parent_node.get_children():
		if child.name != "FrameMesh" and child.name != "ArmorMesh":
			child.visible = false
			for grand in child.get_children():
				if grand is VisualInstance3D or grand is Node3D:
					grand.visible = false


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
		mat.albedo_color = Color(0.25, 0.40, 0.60)
		mat.metallic = 0.75
		mat.roughness = 0.3
		mesh_inst.material_override = mat
		debris.add_child(mesh_inst)
		
		get_tree().current_scene.add_child(debris)
		
		var impulse = Vector3(randf_range(-4, 4), randf_range(3, 7), randf_range(-4, 4))
		debris.apply_central_impulse(impulse)
		
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

# Helper materials for inner frame & armor
func _get_dark_frame_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.16, 0.20)
	mat.metallic = 0.92
	mat.roughness = 0.25
	return mat

func _get_chrome_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.88, 0.92)
	mat.metallic = 0.98
	mat.roughness = 0.10
	return mat

func _get_eye_sensor_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.12, 0.20)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.15, 0.25)
	mat.emission_energy_multiplier = 4.0
	return mat


# ==============================================================================
# SKELETAL INNER FRAME GENERATOR
# High-Detail Mechanical Robot Skeleton (Proportions matched to 30MM/AC reference)
# ==============================================================================
func _build_procedural_inner_frame(slot_name: String, container: Node3D) -> void:
	var frame_mat = _get_dark_frame_material()
	var chrome_mat = _get_chrome_material()
	var eye_mat = _get_eye_sensor_material()

	match slot_name.to_lower():
		"head":
			# Mechanical skull block sitting directly on neck
			var skull = MeshInstance3D.new()
			var s_box = BoxMesh.new()
			s_box.size = Vector3(0.24, 0.22, 0.28)
			skull.mesh = s_box
			skull.position = Vector3(0, 0.04, 0)
			skull.material_override = frame_mat
			container.add_child(skull)

			# Glowing Red Eye Sensor Lens (Front)
			var eye = MeshInstance3D.new()
			var e_box = BoxMesh.new()
			e_box.size = Vector3(0.16, 0.08, 0.06)
			eye.mesh = e_box
			eye.position = Vector3(0, 0.06, -0.14)
			eye.material_override = eye_mat
			container.add_child(eye)

			# Neck Joint Piston connecting skull directly down to chest spine (NO GAP)
			var neck = MeshInstance3D.new()
			var n_cyl = CylinderMesh.new()
			n_cyl.top_radius = 0.08
			n_cyl.bottom_radius = 0.08
			n_cyl.height = 0.26
			neck.mesh = n_cyl
			neck.position = Vector3(0, -0.13, 0)
			neck.material_override = chrome_mat
			container.add_child(neck)

		"body":
			# Central Spine Column
			var spine = MeshInstance3D.new()
			var sp_box = BoxMesh.new()
			sp_box.size = Vector3(0.18, 0.90, 0.18)
			spine.mesh = sp_box
			spine.position = Vector3(0, 0.05, 0)
			spine.material_override = frame_mat
			container.add_child(spine)

			# Ribcage Structure
			for rib_y in [0.28, 0.08, -0.12]:
				var rib = MeshInstance3D.new()
				var r_box = BoxMesh.new()
				r_box.size = Vector3(0.56, 0.08, 0.32)
				rib.mesh = r_box
				rib.position = Vector3(0, rib_y, 0)
				rib.material_override = frame_mat
				container.add_child(rib)

			# Central Power Core Reactor
			var core = MeshInstance3D.new()
			var c_cyl = CylinderMesh.new()
			c_cyl.top_radius = 0.14
			c_cyl.bottom_radius = 0.14
			c_cyl.height = 0.48
			core.mesh = c_cyl
			core.position = Vector3(0, 0.10, 0)
			core.material_override = chrome_mat
			container.add_child(core)

			# Shoulder Mounting Socket Rings (Left & Right)
			for side_x in [-0.42, 0.42]:
				var socket = MeshInstance3D.new()
				var s_cyl = CylinderMesh.new()
				s_cyl.top_radius = 0.14
				s_cyl.bottom_radius = 0.14
				s_cyl.height = 0.16
				socket.mesh = s_cyl
				socket.rotation_degrees.z = 90
				socket.position = Vector3(side_x, 0.28, 0)
				socket.material_override = frame_mat
				container.add_child(socket)

			# Waist Hydraulic Ring
			var waist = MeshInstance3D.new()
			var w_cyl = CylinderMesh.new()
			w_cyl.top_radius = 0.22
			w_cyl.bottom_radius = 0.22
			w_cyl.height = 0.12
			waist.mesh = w_cyl
			waist.position = Vector3(0, -0.38, 0)
			waist.material_override = frame_mat
			container.add_child(waist)

			for piston_x in [-0.14, 0.14]:
				var piston = MeshInstance3D.new()
				var p_cyl = CylinderMesh.new()
				p_cyl.top_radius = 0.03
				p_cyl.bottom_radius = 0.03
				p_cyl.height = 0.32
				piston.mesh = p_cyl
				piston.position = Vector3(piston_x, -0.24, 0)
				piston.material_override = chrome_mat
				container.add_child(piston)

		"arm_left", "arm_right":
			# 1. Shoulder Joint Sphere (Centered at local origin 0,0,0)
			var shoulder_joint = MeshInstance3D.new()
			var s_sphere = SphereMesh.new()
			s_sphere.radius = 0.16
			s_sphere.height = 0.32
			shoulder_joint.mesh = s_sphere
			shoulder_joint.material_override = frame_mat
			container.add_child(shoulder_joint)

			var shoulder_bolt = MeshInstance3D.new()
			var b_cyl = CylinderMesh.new()
			b_cyl.top_radius = 0.17
			b_cyl.bottom_radius = 0.17
			b_cyl.height = 0.08
			shoulder_bolt.mesh = b_cyl
			shoulder_bolt.rotation_degrees.z = 90
			shoulder_bolt.material_override = chrome_mat
			container.add_child(shoulder_bolt)

			# 2. Upper Arm Frame Shaft (from y=0 down to y=-0.38)
			var upper_arm = MeshInstance3D.new()
			var u_box = BoxMesh.new()
			u_box.size = Vector3(0.14, 0.30, 0.14)
			upper_arm.mesh = u_box
			upper_arm.position = Vector3(0, -0.22, 0)
			upper_arm.material_override = frame_mat
			container.add_child(upper_arm)

			# 3. Mechanical Elbow Disc Joint (at y=-0.38)
			var elbow_disc = MeshInstance3D.new()
			var e_cyl = CylinderMesh.new()
			e_cyl.top_radius = 0.11
			e_cyl.bottom_radius = 0.11
			e_cyl.height = 0.12
			elbow_disc.mesh = e_cyl
			elbow_disc.rotation_degrees.z = 90
			elbow_disc.position = Vector3(0, -0.38, 0)
			elbow_disc.material_override = chrome_mat
			container.add_child(elbow_disc)

			# 4. Forearm Frame Shaft (from y=-0.38 down to y=-0.76)
			var forearm_frame = MeshInstance3D.new()
			var f_box = BoxMesh.new()
			f_box.size = Vector3(0.16, 0.34, 0.16)
			forearm_frame.mesh = f_box
			forearm_frame.position = Vector3(0, -0.60, 0)
			forearm_frame.material_override = frame_mat
			container.add_child(forearm_frame)

			# 5. Hand Manipulator Claw (at y=-0.82)
			var hand_block = MeshInstance3D.new()
			var h_box = BoxMesh.new()
			h_box.size = Vector3(0.12, 0.12, 0.14)
			hand_block.mesh = h_box
			hand_block.position = Vector3(0, -0.82, 0)
			hand_block.material_override = chrome_mat
			container.add_child(hand_block)

		"leg_left", "leg_right":
			# 1. Hip Joint Sphere (Centered at local origin 0,0,0)
			var hip_joint = MeshInstance3D.new()
			var h_sphere = SphereMesh.new()
			h_sphere.radius = 0.18
			h_sphere.height = 0.36
			hip_joint.mesh = h_sphere
			hip_joint.material_override = frame_mat
			container.add_child(hip_joint)

			# 2. Thigh Frame Shaft (from y=0 down to y=-0.46)
			var thigh_frame = MeshInstance3D.new()
			var t_box = BoxMesh.new()
			t_box.size = Vector3(0.20, 0.40, 0.20)
			thigh_frame.mesh = t_box
			thigh_frame.position = Vector3(0, -0.24, 0)
			thigh_frame.material_override = frame_mat
			container.add_child(thigh_frame)

			# 3. Knee Disc Joint (at y=-0.46)
			var knee_disc = MeshInstance3D.new()
			var k_cyl = CylinderMesh.new()
			k_cyl.top_radius = 0.14
			k_cyl.bottom_radius = 0.14
			k_cyl.height = 0.14
			knee_disc.mesh = k_cyl
			knee_disc.rotation_degrees.z = 90
			knee_disc.position = Vector3(0, -0.46, 0)
			knee_disc.material_override = chrome_mat
			container.add_child(knee_disc)

			# 4. Shin Frame Shaft (from y=-0.46 down to y=-1.0)
			var shin_frame = MeshInstance3D.new()
			var s_box = BoxMesh.new()
			s_box.size = Vector3(0.22, 0.50, 0.22)
			shin_frame.mesh = s_box
			shin_frame.position = Vector3(0, -0.75, 0)
			shin_frame.material_override = frame_mat
			container.add_child(shin_frame)

			# Hydraulic Damper on Shin
			var damper = MeshInstance3D.new()
			var d_cyl = CylinderMesh.new()
			d_cyl.top_radius = 0.03
			d_cyl.bottom_radius = 0.03
			d_cyl.height = 0.44
			damper.mesh = d_cyl
			damper.position = Vector3(0, -0.75, 0.13)
			damper.material_override = chrome_mat
			container.add_child(damper)

			# 5. Ankle Disc Joint (at y=-1.03)
			var ankle = MeshInstance3D.new()
			var a_cyl = CylinderMesh.new()
			a_cyl.top_radius = 0.11
			a_cyl.bottom_radius = 0.11
			a_cyl.height = 0.10
			ankle.mesh = a_cyl
			ankle.position = Vector3(0, -1.03, 0)
			ankle.material_override = chrome_mat
			container.add_child(ankle)

			# 6. Mechanical Clawed Foot (at y=-1.08)
			var foot_block = MeshInstance3D.new()
			var ft_box = BoxMesh.new()
			ft_box.size = Vector3(0.22, 0.08, 0.24)
			foot_block.mesh = ft_box
			foot_block.position = Vector3(0, -1.08, 0)
			foot_block.material_override = frame_mat
			container.add_child(foot_block)

			for claw_x in [-0.08, 0.08]:
				var claw = MeshInstance3D.new()
				var c_box = BoxMesh.new()
				c_box.size = Vector3(0.06, 0.06, 0.26)
				claw.mesh = c_box
				claw.position = Vector3(claw_x, -1.09, -0.16)
				claw.rotation_degrees.x = -15
				claw.material_override = frame_mat
				container.add_child(claw)

			var heel = MeshInstance3D.new()
			var h_box = BoxMesh.new()
			h_box.size = Vector3(0.14, 0.06, 0.18)
			heel.mesh = h_box
			heel.position = Vector3(0, -1.09, 0.14)
			heel.rotation_degrees.x = 15
			heel.material_override = frame_mat
			container.add_child(heel)

		_:
			var box = BoxMesh.new()
			box.size = Vector3(0.2, 0.8, 0.2)
			var base_mesh = MeshInstance3D.new()
			base_mesh.mesh = box
			base_mesh.material_override = frame_mat
			container.add_child(base_mesh)


# ==============================================================================
# MODULAR OUTER ARMOR GENERATOR (FULL ARMOR)
# Form-fitting heavy armor plates mounted OVER inner frame
# ==============================================================================
func _build_procedural_outer_armor(slot_name: String, container: Node3D, part: ArmorPart) -> void:
	var col = Color(0.25, 0.40, 0.60)
	if part and "part_color" in part:
		col = part.part_color

	var armor_mat = StandardMaterial3D.new()
	armor_mat.albedo_color = col
	armor_mat.metallic = 0.80
	armor_mat.roughness = 0.30

	var dark_trim_mat = StandardMaterial3D.new()
	dark_trim_mat.albedo_color = Color(0.15, 0.18, 0.22)
	dark_trim_mat.metallic = 0.90
	dark_trim_mat.roughness = 0.25

	match slot_name.to_lower():
		"head":
			# Angular Helmet Armor Shell
			var helmet = MeshInstance3D.new()
			var h_box = BoxMesh.new()
			h_box.size = Vector3(0.36, 0.26, 0.36)
			helmet.mesh = h_box
			helmet.position = Vector3(0, 0.04, 0)
			helmet.material_override = armor_mat
			container.add_child(helmet)

			# Cheek Armor Guards
			for side_x in [-0.18, 0.18]:
				var cheek = MeshInstance3D.new()
				var c_box = BoxMesh.new()
				c_box.size = Vector3(0.06, 0.18, 0.22)
				cheek.mesh = c_box
				cheek.position = Vector3(side_x, -0.02, -0.05)
				cheek.material_override = dark_trim_mat
				container.add_child(cheek)

			# Forehead Crest / Visor Brow Guard
			var brow = MeshInstance3D.new()
			var b_prism = PrismMesh.new()
			b_prism.size = Vector3(0.18, 0.20, 0.28)
			brow.mesh = b_prism
			brow.rotation_degrees.x = -25
			brow.position = Vector3(0, 0.18, -0.05)
			brow.material_override = armor_mat
			container.add_child(brow)

			# Neck Collar Armor Protection Ring
			var collar = MeshInstance3D.new()
			var cl_cyl = CylinderMesh.new()
			cl_cyl.top_radius = 0.20
			cl_cyl.bottom_radius = 0.22
			cl_cyl.height = 0.12
			collar.mesh = cl_cyl
			collar.position = Vector3(0, -0.16, 0)
			collar.material_override = dark_trim_mat
			container.add_child(collar)

		"body":
			# Angular Chest Breastplate
			var chest = MeshInstance3D.new()
			var c_prism = PrismMesh.new()
			c_prism.size = Vector3(0.95, 0.65, 0.48)
			chest.mesh = c_prism
			chest.rotation_degrees.x = 90
			chest.position = Vector3(0, 0.12, -0.14)
			chest.material_override = armor_mat
			container.add_child(chest)

			# Side Chest Intake Vents
			for side_x in [-0.42, 0.42]:
				var vent = MeshInstance3D.new()
				var v_box = BoxMesh.new()
				v_box.size = Vector3(0.14, 0.35, 0.25)
				vent.mesh = v_box
				vent.position = Vector3(side_x, 0.15, -0.08)
				vent.material_override = dark_trim_mat
				container.add_child(vent)

			# Lower Abdominal Armor Plate
			var ab_plate = MeshInstance3D.new()
			var ab_box = BoxMesh.new()
			ab_box.size = Vector3(0.58, 0.35, 0.26)
			ab_plate.mesh = ab_box
			ab_plate.position = Vector3(0, -0.28, -0.10)
			ab_plate.material_override = armor_mat
			container.add_child(ab_plate)

		"arm_left", "arm_right":
			var is_left = slot_name.to_lower() == "arm_left"
			var dir_sign = -1.0 if is_left else 1.0

			# 1. Shoulder Pauldron Mounted OVER Shoulder Joint Pivot
			var pauldron = MeshInstance3D.new()
			var p_box = BoxMesh.new()
			p_box.size = Vector3(0.44, 0.32, 0.44)
			pauldron.mesh = p_box
			pauldron.position = Vector3(dir_sign * 0.08, 0.04, 0)
			pauldron.material_override = armor_mat
			container.add_child(pauldron)

			# Pauldron Trim Shield
			var trim = MeshInstance3D.new()
			var t_box = BoxMesh.new()
			t_box.size = Vector3(0.48, 0.10, 0.48)
			trim.mesh = t_box
			trim.position = Vector3(dir_sign * 0.08, 0.16, 0)
			trim.material_override = dark_trim_mat
			container.add_child(trim)

			# 2. Forearm Armor Guard Wrapped Around Forearm Frame (at y=-0.60)
			var forearm_guard = MeshInstance3D.new()
			var fg_box = BoxMesh.new()
			fg_box.size = Vector3(0.28, 0.36, 0.28)
			forearm_guard.mesh = fg_box
			forearm_guard.position = Vector3(0, -0.60, 0)
			forearm_guard.material_override = armor_mat
			container.add_child(forearm_guard)

			# 3. Knuckle Guard Plate
			var knuckle = MeshInstance3D.new()
			var k_box = BoxMesh.new()
			k_box.size = Vector3(0.15, 0.04, 0.15)
			knuckle.mesh = k_box
			knuckle.position = Vector3(0, -0.80, -0.02)
			knuckle.material_override = armor_mat
			container.add_child(knuckle)

		"leg_left", "leg_right":
			# 1. Thigh Armor Guard (at y=-0.24)
			var thigh_armor = MeshInstance3D.new()
			var ta_box = BoxMesh.new()
			ta_box.size = Vector3(0.32, 0.40, 0.32)
			thigh_armor.mesh = ta_box
			thigh_armor.position = Vector3(0, -0.24, 0)
			thigh_armor.material_override = armor_mat
			container.add_child(thigh_armor)

			# 2. Knee Shield Cap (at y=-0.46)
			var knee_cap = MeshInstance3D.new()
			var k_prism = PrismMesh.new()
			k_prism.size = Vector3(0.24, 0.22, 0.20)
			knee_cap.mesh = k_prism
			knee_cap.rotation_degrees.x = 90
			knee_cap.position = Vector3(0, -0.46, 0.15)
			knee_cap.material_override = armor_mat
			container.add_child(knee_cap)

			# 3. Flared Front Shin Armor Guard (at y=-0.75)
			var shin_armor = MeshInstance3D.new()
			var sa_box = BoxMesh.new()
			sa_box.size = Vector3(0.34, 0.48, 0.30)
			shin_armor.mesh = sa_box
			shin_armor.position = Vector3(0, -0.75, 0.04)
			shin_armor.material_override = armor_mat
			container.add_child(shin_armor)

			# 4. Foot Top Guard Cap (at y=-1.08)
			var foot_cap = MeshInstance3D.new()
			var fc_box = BoxMesh.new()
			fc_box.size = Vector3(0.24, 0.08, 0.26)
			foot_cap.mesh = fc_box
			foot_cap.position = Vector3(0, -1.08, -0.04)
			foot_cap.material_override = armor_mat
			container.add_child(foot_cap)

		_:
			var box = BoxMesh.new()
			box.size = Vector3(0.6, 0.6, 0.6)
			var base_mesh = MeshInstance3D.new()
			base_mesh.mesh = box
			base_mesh.material_override = armor_mat
			container.add_child(base_mesh)
