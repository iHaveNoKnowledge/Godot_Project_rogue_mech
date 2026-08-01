extends Node3D

var slot_meshes: Dictionary = {}

func _ready() -> void:
	EventBus.part_destroyed.connect(_on_part_destroyed)


func initialize_slot(slot_name: String, part: ArmorPart) -> void:
	var parent_node = _get_slot_parent_node(slot_name)
	if parent_node == null:
		return

	# Hide legacy placeholder blocky primitives in mecha_base.tscn
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
			if child is VisualInstance3D or child is Node3D:
				child.visible = false


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
	# Remove outer armor plate mesh, exposing skeletal inner frame underneath
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
		mat.albedo_color = Color(0.25, 0.40, 0.60) # Armor plate debris color
		mat.metallic = 0.75
		mat.roughness = 0.3
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

# Helper materials for inner frame & armor
func _get_dark_frame_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.16, 0.20) # Dark metallic steel frame
	mat.metallic = 0.92
	mat.roughness = 0.25
	return mat

func _get_chrome_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.88, 0.92) # Chrome hydraulic piston
	mat.metallic = 0.98
	mat.roughness = 0.10
	return mat

func _get_eye_sensor_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.12, 0.20) # Glowing red eye sensor
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.15, 0.25)
	mat.emission_energy_multiplier = 4.0
	return mat


# ==============================================================================
# SKELETAL INNER FRAME GENERATOR (NO ARMOR)
# Detailed mechanical robot skeleton with joints, pistons, ribcage, 5-finger hands
# ==============================================================================
func _build_procedural_inner_frame(slot_name: String, container: Node3D) -> void:
	var frame_mat = _get_dark_frame_material()
	var chrome_mat = _get_chrome_material()
	var eye_mat = _get_eye_sensor_material()

	match slot_name.to_lower():
		"head":
			# Mechanical skull block
			var skull = MeshInstance3D.new()
			var s_box = BoxMesh.new()
			s_box.size = Vector3(0.24, 0.22, 0.28)
			skull.mesh = s_box
			skull.material_override = frame_mat
			container.add_child(skull)

			# Glowing Red Eye Sensor Lens (Front)
			var eye = MeshInstance3D.new()
			var e_box = BoxMesh.new()
			e_box.size = Vector3(0.16, 0.08, 0.06)
			eye.mesh = e_box
			eye.position = Vector3(0, 0.02, -0.14)
			eye.material_override = eye_mat
			container.add_child(eye)

			# Neck Joint Disc
			var neck = MeshInstance3D.new()
			var n_cyl = CylinderMesh.new()
			n_cyl.top_radius = 0.09
			n_cyl.bottom_radius = 0.09
			n_cyl.height = 0.12
			neck.mesh = n_cyl
			neck.position = Vector3(0, -0.14, 0)
			neck.material_override = chrome_mat
			container.add_child(neck)

		"body":
			# Central Spine Column
			var spine = MeshInstance3D.new()
			var sp_box = BoxMesh.new()
			sp_box.size = Vector3(0.16, 1.0, 0.16)
			spine.mesh = sp_box
			spine.material_override = frame_mat
			container.add_child(spine)

			# Mechanical Ribcage Structure (3 Rib Bars)
			for rib_y in [0.25, 0.0, -0.25]:
				var rib = MeshInstance3D.new()
				var r_box = BoxMesh.new()
				r_box.size = Vector3(0.48, 0.08, 0.30)
				rib.mesh = r_box
				rib.position = Vector3(0, rib_y, 0)
				rib.material_override = frame_mat
				container.add_child(rib)

			# Central Power Core Cylinder inside ribcage
			var core = MeshInstance3D.new()
			var c_cyl = CylinderMesh.new()
			c_cyl.top_radius = 0.12
			c_cyl.bottom_radius = 0.12
			c_cyl.height = 0.45
			core.mesh = c_cyl
			core.position = Vector3(0, 0.05, 0)
			core.material_override = chrome_mat
			container.add_child(core)

			# Hydraulic Waist Ring & Pistons
			var waist_ring = MeshInstance3D.new()
			var w_cyl = CylinderMesh.new()
			w_cyl.top_radius = 0.22
			w_cyl.bottom_radius = 0.22
			w_cyl.height = 0.10
			waist_ring.mesh = w_cyl
			waist_ring.position = Vector3(0, -0.45, 0)
			waist_ring.material_override = frame_mat
			container.add_child(waist_ring)

			for piston_x in [-0.14, 0.14]:
				var piston = MeshInstance3D.new()
				var p_cyl = CylinderMesh.new()
				p_cyl.top_radius = 0.03
				p_cyl.bottom_radius = 0.03
				p_cyl.height = 0.35
				piston.mesh = p_cyl
				piston.position = Vector3(piston_x, -0.30, 0)
				piston.material_override = chrome_mat
				container.add_child(piston)

		"arm_left", "arm_right":
			var is_left = slot_name.to_lower() == "arm_left"
			var dir_sign = -1.0 if is_left else 1.0

			# 1. Shoulder Spherical Joint with Bolt Disc
			var shoulder_joint = MeshInstance3D.new()
			var s_sphere = SphereMesh.new()
			s_sphere.radius = 0.16
			s_sphere.height = 0.32
			shoulder_joint.mesh = s_sphere
			shoulder_joint.material_override = frame_mat
			container.add_child(shoulder_joint)

			var shoulder_bolt = MeshInstance3D.new()
			var b_cyl = CylinderMesh.new()
			b_cyl.top_radius = 0.18
			b_cyl.bottom_radius = 0.18
			b_cyl.height = 0.06
			shoulder_bolt.mesh = b_cyl
			shoulder_bolt.rotation_degrees.z = 90
			shoulder_bolt.material_override = chrome_mat
			container.add_child(shoulder_bolt)

			# 2. Upper Arm Twin Structural Rods + Central Chrome Piston
			for rod_x in [-0.06, 0.06]:
				var rod = MeshInstance3D.new()
				var r_cyl = CylinderMesh.new()
				r_cyl.top_radius = 0.035
				r_cyl.bottom_radius = 0.035
				r_cyl.height = 0.45
				rod.mesh = r_cyl
				rod.position = Vector3(rod_x, -0.22, 0)
				rod.material_override = frame_mat
				container.add_child(rod)

			var upper_piston = MeshInstance3D.new()
			var up_cyl = CylinderMesh.new()
			up_cyl.top_radius = 0.025
			up_cyl.bottom_radius = 0.025
			up_cyl.height = 0.40
			upper_piston.mesh = up_cyl
			upper_piston.position = Vector3(0, -0.22, 0)
			upper_piston.material_override = chrome_mat
			container.add_child(upper_piston)

			# 3. Dual-Disc Mechanical Elbow Hinge
			var elbow = MeshInstance3D.new()
			var e_cyl = CylinderMesh.new()
			e_cyl.top_radius = 0.11
			e_cyl.bottom_radius = 0.11
			e_cyl.height = 0.14
			elbow.mesh = e_cyl
			elbow.rotation_degrees.x = 90
			elbow.position = Vector3(0, -0.45, 0)
			elbow.material_override = chrome_mat
			container.add_child(elbow)

			# 4. Tapered Forearm Mechanical Frame
			var forearm_frame = MeshInstance3D.new()
			var f_box = BoxMesh.new()
			f_box.size = Vector3(0.18, 0.42, 0.18)
			forearm_frame.mesh = f_box
			forearm_frame.position = Vector3(0, -0.68, 0)
			forearm_frame.material_override = frame_mat
			container.add_child(forearm_frame)

			# 5. Articulated 5-Finger Mechanical Robot Hand
			var palm = MeshInstance3D.new()
			var p_box = BoxMesh.new()
			p_box.size = Vector3(0.14, 0.08, 0.14)
			palm.mesh = p_box
			palm.position = Vector3(0, -0.92, 0)
			palm.material_override = frame_mat
			container.add_child(palm)

			# 4 Mechanical Fingers
			for f_idx in range(4):
				var finger = MeshInstance3D.new()
				var fg_box = BoxMesh.new()
				fg_box.size = Vector3(0.025, 0.12, 0.025)
				finger.mesh = fg_box
				var f_offset_z = -0.045 + (f_idx * 0.03)
				finger.position = Vector3(dir_sign * 0.04, -0.98, f_offset_z)
				finger.material_override = chrome_mat
				container.add_child(finger)

			# Thumb
			var thumb = MeshInstance3D.new()
			var th_box = BoxMesh.new()
			th_box.size = Vector3(0.03, 0.10, 0.03)
			thumb.mesh = th_box
			thumb.position = Vector3(-dir_sign * 0.05, -0.95, -0.02)
			thumb.rotation_degrees.z = 35 * dir_sign
			thumb.material_override = chrome_mat
			container.add_child(thumb)

		"leg_left", "leg_right":
			# 1. Hip Ball Socket Joint
			var hip = MeshInstance3D.new()
			var h_sphere = SphereMesh.new()
			h_sphere.radius = 0.16
			h_sphere.height = 0.32
			hip.mesh = h_sphere
			hip.material_override = frame_mat
			container.add_child(hip)

			# 2. Thigh Structural Twin Rods + Hydraulic Cylinder
			for rod_z in [-0.06, 0.06]:
				var rod = MeshInstance3D.new()
				var r_cyl = CylinderMesh.new()
				r_cyl.top_radius = 0.045
				r_cyl.bottom_radius = 0.045
				r_cyl.height = 0.55
				rod.mesh = r_cyl
				rod.position = Vector3(0, -0.28, rod_z)
				rod.material_override = frame_mat
				container.add_child(rod)

			var thigh_piston = MeshInstance3D.new()
			var tp_cyl = CylinderMesh.new()
			tp_cyl.top_radius = 0.032
			tp_cyl.bottom_radius = 0.032
			tp_cyl.height = 0.50
			thigh_piston.mesh = tp_cyl
			thigh_piston.position = Vector3(0, -0.28, 0)
			thigh_piston.material_override = chrome_mat
			container.add_child(thigh_piston)

			# 3. Circular Knee Disc Hinge Joint
			var knee_disc = MeshInstance3D.new()
			var k_cyl = CylinderMesh.new()
			k_cyl.top_radius = 0.14
			k_cyl.bottom_radius = 0.14
			k_cyl.height = 0.12
			knee_disc.mesh = k_cyl
			knee_disc.rotation_degrees.z = 90
			knee_disc.position = Vector3(0, -0.58, 0)
			knee_disc.material_override = chrome_mat
			container.add_child(knee_disc)

			# 4. Tapered Dual-Strut Shin Frame
			var shin_frame = MeshInstance3D.new()
			var s_box = BoxMesh.new()
			s_box.size = Vector3(0.20, 0.55, 0.20)
			shin_frame.mesh = s_box
			shin_frame.position = Vector3(0, -0.88, 0)
			shin_frame.material_override = frame_mat
			container.add_child(shin_frame)

			# Front Hydraulic Damper on Shin
			var damper = MeshInstance3D.new()
			var d_cyl = CylinderMesh.new()
			d_cyl.top_radius = 0.03
			d_cyl.bottom_radius = 0.03
			d_cyl.height = 0.45
			damper.mesh = d_cyl
			damper.position = Vector3(0, -0.88, 0.12)
			damper.material_override = chrome_mat
			container.add_child(damper)

			# 5. Ankle Disc Joint
			var ankle = MeshInstance3D.new()
			var a_cyl = CylinderMesh.new()
			a_cyl.top_radius = 0.10
			a_cyl.bottom_radius = 0.10
			a_cyl.height = 0.08
			ankle.mesh = a_cyl
			ankle.position = Vector3(0, -1.18, 0)
			ankle.material_override = chrome_mat
			container.add_child(ankle)

			# 6. Mechanical Clawed Foot (Toes + Heel)
			var foot_block = MeshInstance3D.new()
			var ft_box = BoxMesh.new()
			ft_box.size = Vector3(0.18, 0.08, 0.22)
			foot_block.mesh = ft_box
			foot_block.position = Vector3(0, -1.22, 0)
			foot_block.material_override = frame_mat
			container.add_child(foot_block)

			# Front Claws
			for claw_x in [-0.07, 0.07]:
				var claw = MeshInstance3D.new()
				var c_box = BoxMesh.new()
				c_box.size = Vector3(0.06, 0.06, 0.25)
				claw.mesh = c_box
				claw.position = Vector3(claw_x, -1.23, -0.16)
				claw.rotation_degrees.x = -15
				claw.material_override = frame_mat
				container.add_child(claw)

			# Heel Spur
			var heel = MeshInstance3D.new()
			var h_box = BoxMesh.new()
			h_box.size = Vector3(0.12, 0.06, 0.18)
			heel.mesh = h_box
			heel.position = Vector3(0, -1.23, 0.14)
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
# Form-fitting armor plates mounted OVER the skeletal inner frame
# ==============================================================================
func _build_procedural_outer_armor(slot_name: String, container: Node3D, part: ArmorPart) -> void:
	var part_name = part.part_name.to_lower() if (part and "part_name" in part) else ""
	var col = Color(0.25, 0.40, 0.60) # Default Mecha Navy Blue (as drawn in concept sketch!)
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
			h_box.size = Vector3(0.36, 0.28, 0.36)
			helmet.mesh = h_box
			helmet.material_override = armor_mat
			container.add_child(helmet)

			# Cheek Armor Guards
			for side_x in [-0.18, 0.18]:
				var cheek = MeshInstance3D.new()
				var c_box = BoxMesh.new()
				c_box.size = Vector3(0.06, 0.18, 0.22)
				cheek.mesh = c_box
				cheek.position = Vector3(side_x, -0.04, -0.05)
				cheek.material_override = dark_trim_mat
				container.add_child(cheek)

			# Forehead Crest / Brow Guard
			var brow = MeshInstance3D.new()
			var b_prism = PrismMesh.new()
			b_prism.size = Vector3(0.18, 0.22, 0.30)
			brow.mesh = b_prism
			brow.rotation_degrees.x = -25
			brow.position = Vector3(0, 0.18, -0.05)
			brow.material_override = armor_mat
			container.add_child(brow)

		"body":
			# Angular Chest Breastplate
			var chest = MeshInstance3D.new()
			var c_prism = PrismMesh.new()
			c_prism.size = Vector3(0.95, 0.65, 0.45)
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
			ab_box.size = Vector3(0.55, 0.35, 0.25)
			ab_plate.mesh = ab_box
			ab_plate.position = Vector3(0, -0.28, -0.10)
			ab_plate.material_override = armor_mat
			container.add_child(ab_plate)

		"arm_left", "arm_right":
			var is_left = slot_name.to_lower() == "arm_left"
			var dir_sign = -1.0 if is_left else 1.0

			# 1. Shoulder Pauldron Mounted OVER Top Shoulder Joint
			var pauldron = MeshInstance3D.new()
			var p_box = BoxMesh.new()
			p_box.size = Vector3(0.44, 0.32, 0.44)
			pauldron.mesh = p_box
			pauldron.position = Vector3(dir_sign * 0.08, 0.08, 0)
			pauldron.material_override = armor_mat
			container.add_child(pauldron)

			# Pauldron Trim Shield
			var trim = MeshInstance3D.new()
			var t_box = BoxMesh.new()
			t_box.size = Vector3(0.48, 0.10, 0.48)
			trim.mesh = t_box
			trim.position = Vector3(dir_sign * 0.08, 0.20, 0)
			trim.material_override = dark_trim_mat
			container.add_child(trim)

			# 2. Forearm Armor Guard Wrapped Around Forearm Frame
			var forearm_guard = MeshInstance3D.new()
			var fg_box = BoxMesh.new()
			fg_box.size = Vector3(0.28, 0.38, 0.28)
			forearm_guard.mesh = fg_box
			forearm_guard.position = Vector3(0, -0.68, 0)
			forearm_guard.material_override = armor_mat
			container.add_child(forearm_guard)

			# 3. Knuckle Guard Plate
			var knuckle = MeshInstance3D.new()
			var k_box = BoxMesh.new()
			k_box.size = Vector3(0.15, 0.04, 0.15)
			knuckle.mesh = k_box
			knuckle.position = Vector3(0, -0.89, -0.02)
			knuckle.material_override = armor_mat
			container.add_child(knuckle)

		"leg_left", "leg_right":
			# 1. Thigh Armor Guard
			var thigh_armor = MeshInstance3D.new()
			var ta_box = BoxMesh.new()
			ta_box.size = Vector3(0.32, 0.42, 0.32)
			thigh_armor.mesh = ta_box
			thigh_armor.position = Vector3(0, -0.28, 0)
			thigh_armor.material_override = armor_mat
			container.add_child(thigh_armor)

			# 2. Knee Shield Cap
			var knee_cap = MeshInstance3D.new()
			var k_prism = PrismMesh.new()
			k_prism.size = Vector3(0.24, 0.22, 0.20)
			knee_cap.mesh = k_prism
			knee_cap.rotation_degrees.x = 90
			knee_cap.position = Vector3(0, -0.58, 0.16)
			knee_cap.material_override = armor_mat
			container.add_child(knee_cap)

			# 3. Flared Front Shin Armor Guard
			var shin_armor = MeshInstance3D.new()
			var sa_box = BoxMesh.new()
			sa_box.size = Vector3(0.34, 0.52, 0.30)
			shin_armor.mesh = sa_box
			shin_armor.position = Vector3(0, -0.88, 0.04)
			shin_armor.material_override = armor_mat
			container.add_child(shin_armor)

			# 4. Foot Top Guard Cap
			var foot_cap = MeshInstance3D.new()
			var fc_box = BoxMesh.new()
			fc_box.size = Vector3(0.22, 0.08, 0.26)
			foot_cap.mesh = fc_box
			foot_cap.position = Vector3(0, -1.20, -0.04)
			foot_cap.material_override = armor_mat
			container.add_child(foot_cap)

		_:
			var box = BoxMesh.new()
			box.size = Vector3(0.6, 0.6, 0.6)
			var base_mesh = MeshInstance3D.new()
			base_mesh.mesh = box
			base_mesh.material_override = armor_mat
			container.add_child(base_mesh)
