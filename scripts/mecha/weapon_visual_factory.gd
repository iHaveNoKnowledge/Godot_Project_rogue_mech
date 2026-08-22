class_name WeaponVisualFactory
extends RefCounted

# Shared mount transforms (hangar preview and battle use the same placements).
const HAND_LEFT_POS := Vector3(-0.85, 1.4, 0.4)
const HAND_RIGHT_POS := Vector3(0.85, 1.4, 0.4)
# Back-carry mount sits BEHIND the torso: the mech faces -Z, so the chest
# plate ends at roughly Z -0.4 and the backpack's rear surface at Z +0.55.
# The old -0.55 value put the "back" weapons inside the chest — they poked
# straight through the body. +0.62 parks them just clear of the backpack so
# they read as strapped on, not buried in the torso.
const BACK_Y := 1.75
const BACK_Z := 0.62
const BACK_ROT_DEG := Vector3(-15, 0, 0)
const CARRY_SPREAD := 0.44
const CARRY_OFFSET_STEP := 0.22


# Hand position in the forearm node's local space (bottom of the forearm mesh).
const HAND_FOREARM_POS := Vector3(0.0, -0.72, 0.0)
const HAND_MOUNT_ROT_DEG := Vector3(-80.0, 0.0, 0.0)


# Returns the mount position for a hand ("left"/"right").
static func hand_mount_position(hand: String) -> Vector3:
	return HAND_LEFT_POS if hand == "left" else HAND_RIGHT_POS


# Mounts a weapon onto a hand of the mecha. Reuses the existing node (if the
# given hand already has a mount) so swapping does not pile up stale models.
# The weapon is parented to the Forearm* node (when present) so it sits in the
# hand and follows the arm animations instead of floating at a fixed offset.
static func mount_hand(mecha: Node3D, hand: String, weapon: WeaponPart, node_name: String) -> Node3D:
	var side := "Left" if hand == "left" else "Right"
	var forearm := mecha.get_node_or_null("Arm" + side + "/Forearm" + side) as Node3D
	var mount: Node3D = null
	if forearm != null:
		# Free any stale root-anchored mount from a previous version.
		var stale := mecha.get_node_or_null(node_name)
		if stale != null:
			stale.queue_free()
		mount = forearm.get_node_or_null(node_name)
		if mount == null or not mount.is_inside_tree() or mount.is_queued_for_deletion():
			# The old mount is queued for deletion (e.g. hangar unequip called the
			# preview in the same frame): drop it and build a fresh one so the new
			# weapon isn't added to a node that vanishes at the end of the frame.
			if mount != null and mount.is_inside_tree():
				forearm.remove_child(mount)
			mount = Node3D.new()
			mount.name = node_name
			forearm.add_child(mount)
		mount.position = HAND_FOREARM_POS
		mount.rotation_degrees = HAND_MOUNT_ROT_DEG
	else:
		mount = mecha.get_node_or_null(node_name)
		if mount == null or not mount.is_inside_tree() or mount.is_queued_for_deletion():
			if mount != null and mount.is_inside_tree():
				mecha.remove_child(mount)
			mount = Node3D.new()
			mount.name = node_name
			mecha.add_child(mount)
		mount.position = hand_mount_position(hand)
		mount.rotation_degrees = Vector3.ZERO
	for child in mount.get_children():
		child.queue_free()
	if weapon == null:
		return mount
	mount.add_child(build(weapon))
	return mount


# Renders back-carried weapons spread horizontally across the back pack. Reuses
# the existing node (if one is mounted) so swapping does not pile up stale models.
static func mount_carry(mecha: Node3D, weapons: Array, node_name: String) -> Node3D:
	var back_mount = mecha.get_node_or_null(node_name)
	if back_mount == null or not back_mount.is_inside_tree() or back_mount.is_queued_for_deletion():
		# Hangar unequip queue_frees the carry mount and refreshes the preview in
		# the same frame: never reuse a node that is about to die (it would take
		# the fresh weapon models with it when the frame ends).
		if back_mount != null and back_mount.is_inside_tree():
			mecha.remove_child(back_mount)
		back_mount = Node3D.new()
		back_mount.name = node_name
		mecha.add_child(back_mount)
	for child in back_mount.get_children():
		child.queue_free()
	if weapons.is_empty():
		return back_mount
	var offset := -((weapons.size() - 1) * CARRY_OFFSET_STEP)
	for weapon in weapons:
		if weapon == null:
			continue
		var wmount := Node3D.new()
		wmount.position = Vector3(offset, BACK_Y, BACK_Z)
		wmount.rotation_degrees = BACK_ROT_DEG
		wmount.add_child(build(weapon))
		back_mount.add_child(wmount)
		offset += CARRY_SPREAD
	return back_mount


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
		box.size = Vector3(0.42, 0.42, 1.4)
		mesh_instance.mesh = box
		mesh_instance.position = Vector3(0.0, 0.05, -0.45)
		mat.albedo_color = Color(0.2, 0.25, 0.22)

		var spike = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.04
		cyl.bottom_radius = 0.12
		cyl.height = 1.3
		spike.mesh = cyl
		spike.rotation_degrees.x = 90
		spike.position = Vector3(0, 0.05, -1.25)
		var spike_mat = StandardMaterial3D.new()
		spike_mat.metallic = 0.95
		spike_mat.albedo_color = Color(0.8, 0.85, 0.9)
		spike.material_override = spike_mat
		mount.add_child(spike)

	elif w_type == WeaponPart.WeaponType.BEAM_RIFLE:
		var box = BoxMesh.new()
		box.size = Vector3(0.25, 0.35, 1.8)
		mesh_instance.mesh = box
		mesh_instance.position = Vector3(0.0, 0.08, -0.65)
		mat.albedo_color = Color(0.15, 0.4, 0.7)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.6, 1.0)

	elif w_type == WeaponPart.WeaponType.MACHINE_GUN:
		var box = BoxMesh.new()
		box.size = Vector3(0.28, 0.3, 1.3)
		mesh_instance.mesh = box
		mesh_instance.position = Vector3(0.0, 0.08, -0.45)
		mat.albedo_color = Color(0.3, 0.3, 0.32)

	elif w_type == WeaponPart.WeaponType.SHOTGUN:
		var box = BoxMesh.new()
		box.size = Vector3(0.32, 0.32, 1.2)
		mesh_instance.mesh = box
		mesh_instance.position = Vector3(0.0, 0.08, -0.4)
		mat.albedo_color = Color(0.45, 0.3, 0.15)

	elif w_type == WeaponPart.WeaponType.MISSILE:
		var box = BoxMesh.new()
		box.size = Vector3(0.48, 0.48, 0.95)
		mesh_instance.mesh = box
		mesh_instance.position = Vector3(0.0, 0.12, -0.3)
		mat.albedo_color = Color(0.6, 0.2, 0.1)

	elif w_type == WeaponPart.WeaponType.SHIELD:
		var box = BoxMesh.new()
		box.size = Vector3(0.16, 1.25, 0.65)
		mesh_instance.mesh = box
		mesh_instance.position = Vector3(-0.16, 0.2, -0.1)
		mat.albedo_color = Color(0.2, 0.35, 0.5)

	else:
		var box = BoxMesh.new()
		box.size = Vector3(0.12, 0.18, 1.4)
		mesh_instance.mesh = box
		mesh_instance.position = Vector3(0.0, 0.0, -0.55)
		mat.albedo_color = Color(0.7, 0.7, 0.7)

	mesh_instance.material_override = mat
	mount.add_child(mesh_instance)
	return mount
