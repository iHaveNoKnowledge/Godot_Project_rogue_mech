class_name WeaponVisualFactory
extends RefCounted


## Builds a shared weapon model (Node3D) for a WeaponPart resource.
## Used by BOTH the Hangar preview and the battle WeaponManager so the weapon
## shown in the garage is the exact same model that appears on the mech's hands.
static func build(weapon: WeaponPart) -> Node3D:
	var mount := Node3D.new()
	if weapon == null:
		return mount

	if weapon.mesh_scene:
		mount.add_child(weapon.mesh_scene.instantiate())
		return mount

	var mesh_instance := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.8
	mat.roughness = 0.2

	var w_type = weapon.weapon_type
	var name_lower = weapon.weapon_name.to_lower()

	if name_lower.contains("pile") or (w_type == WeaponPart.WeaponType.MELEE and name_lower.contains("bunker")):
		var box = BoxMesh.new()
		box.size = Vector3(0.45, 0.45, 1.5)
		mesh_instance.mesh = box
		mat.albedo_color = Color(0.2, 0.25, 0.22)

		var spike = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.04
		cyl.bottom_radius = 0.12
		cyl.height = 1.3
		spike.mesh = cyl
		spike.rotation_degrees.x = -90
		spike.position = Vector3(0, 0, 0.9)
		var spike_mat = StandardMaterial3D.new()
		spike_mat.metallic = 0.95
		spike_mat.albedo_color = Color(0.8, 0.85, 0.9)
		spike.material_override = spike_mat
		mount.add_child(spike)

	elif w_type == WeaponPart.WeaponType.BEAM_RIFLE:
		var box = BoxMesh.new()
		box.size = Vector3(0.25, 0.35, 1.8)
		mesh_instance.mesh = box
		mat.albedo_color = Color(0.15, 0.4, 0.7)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.6, 1.0)

	elif w_type == WeaponPart.WeaponType.MACHINE_GUN:
		var box = BoxMesh.new()
		box.size = Vector3(0.3, 0.3, 1.2)
		mesh_instance.mesh = box
		mat.albedo_color = Color(0.3, 0.3, 0.32)

	elif w_type == WeaponPart.WeaponType.SHOTGUN:
		var box = BoxMesh.new()
		box.size = Vector3(0.35, 0.35, 1.1)
		mesh_instance.mesh = box
		mat.albedo_color = Color(0.45, 0.3, 0.15)

	elif w_type == WeaponPart.WeaponType.MISSILE:
		var box = BoxMesh.new()
		box.size = Vector3(0.5, 0.5, 1.0)
		mesh_instance.mesh = box
		mat.albedo_color = Color(0.6, 0.2, 0.1)

	elif w_type == WeaponPart.WeaponType.SHIELD:
		var box = BoxMesh.new()
		box.size = Vector3(0.2, 1.6, 1.0)
		mesh_instance.mesh = box
		mat.albedo_color = Color(0.2, 0.35, 0.5)

	else:
		var box = BoxMesh.new()
		box.size = Vector3(0.15, 0.15, 1.4)
		mesh_instance.mesh = box
		mat.albedo_color = Color(0.7, 0.7, 0.7)

	mesh_instance.material_override = mat
	mount.add_child(mesh_instance)
	return mount
