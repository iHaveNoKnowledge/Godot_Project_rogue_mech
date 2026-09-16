extends RefCounted
class_name MechaRagdoll

## True ragdoll for Godot 4.6.2 — no plugin required.
## Converts the procedural MechaBase (Head/Body/Arm*/Leg*/Shin*/Forearm*)
## into connected RigidBody3D pieces with PinJoint3D constraints.
## Call spawn_ragdoll(mecha) from MechaHealthBase._collapse_mech() when
## body frame is destroyed or total_frame_hp <= 0.

const RAGDOLL_MASS: Dictionary = {
	"head": 15.0,
	"body": 120.0,
	"arm_left": 32.0,
	"arm_right": 32.0,
	"forearm_left": 24.0,
	"forearm_right": 24.0,
	"leg_left": 58.0,
	"leg_right": 58.0,
	"shin_left": 40.0,
	"shin_right": 40.0,
	"foot_left": 20.0,
	"foot_right": 20.0,
}

const RAGDOLL_BOX: Dictionary = {
	"head": Vector3(0.55, 0.50, 0.55),
	"body": Vector3(0.95, 1.1, 0.72),
	"arm_left": Vector3(0.48, 0.55, 0.48),
	"arm_right": Vector3(0.48, 0.55, 0.48),
	"forearm_left": Vector3(0.42, 0.48, 0.42),
	"forearm_right": Vector3(0.42, 0.48, 0.42),
	"leg_left": Vector3(0.48, 0.50, 0.48),
	"leg_right": Vector3(0.48, 0.50, 0.48),
	"shin_left": Vector3(0.48, 0.55, 0.46),
	"shin_right": Vector3(0.48, 0.55, 0.46),
	"foot_left": Vector3(0.42, 0.20, 0.56),
	"foot_right": Vector3(0.42, 0.20, 0.56),
}

## Segments that exist as Node3D pivots in MechaBase / EnemyDummy
const SEGMENT_NODE_PATH: Dictionary = {
	"head": "Head",
	"body": "Body",
	"arm_left": "ArmLeft",
	"arm_right": "ArmRight",
	"forearm_left": "ArmLeft/ForearmLeft",
	"forearm_right": "ArmRight/ForearmRight",
	"leg_left": "LegLeft",
	"leg_right": "LegRight",
	"shin_left": "LegLeft/ShinLeft",
	"shin_right": "LegRight/ShinRight",
	"foot_left": "LegLeft/ShinLeft/FootLeft",
	"foot_right": "LegRight/ShinRight/FootRight",
}

## Joint connections — PinJoint3D between each parent -> child
const JOINTS: Array = [
	["body", "head"],
	["body", "arm_left"],
	["body", "arm_right"],
	["body", "leg_left"],
	["body", "leg_right"],
	["arm_left", "forearm_left"],
	["arm_right", "forearm_right"],
	["leg_left", "shin_left"],
	["leg_right", "shin_right"],
	["shin_left", "foot_left"],
	["shin_right", "foot_right"],
]


static func spawn_ragdoll(mecha: CharacterBody3D) -> Dictionary:
	if mecha == null or not is_instance_valid(mecha):
		return {}
	var tree := mecha.get_tree()
	if tree == null:
		return {}
	var world: Node = tree.current_scene
	if world == null:
		world = mecha.get_parent()
		if world == null:
			return {}

	# Prevent double-spawn
	if mecha.has_meta("ragdoll_bodies") and mecha.get_meta("ragdoll_bodies") is Array and not (mecha.get_meta("ragdoll_bodies") as Array).is_empty():
		return {"bodies": mecha.get_meta("ragdoll_bodies"), "joints": mecha.get_meta("ragdoll_joints") if mecha.has_meta("ragdoll_joints") else []}

	var bodies: Dictionary = {} # seg_name -> RigidBody3D
	var created: Array[RigidBody3D] = []
	var joints_created: Array[Joint3D] = []

	# Collect segment global transforms first (before we hide anything)
	var seg_xform: Dictionary = {}
	for seg in SEGMENT_NODE_PATH:
		var path: String = SEGMENT_NODE_PATH[seg]
		var node: Node3D = mecha.get_node_or_null(path) as Node3D
		if node != null and is_instance_valid(node):
			seg_xform[seg] = node.global_transform
		else:
			seg_xform[seg] = Transform3D.IDENTITY.translated(mecha.global_position + _fallback_offset(seg))

	# Disable original collision so it doesn't block falling pieces
	var main_col := mecha.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if main_col:
		main_col.set_deferred("disabled", true)
	var hitbox := mecha.get_node_or_null("Hitbox") as Area3D
	if hitbox:
		hitbox.monitoring = false
		hitbox.monitorable = false

	# Create a RigidBody per segment
	for seg in SEGMENT_NODE_PATH:
		var xf: Transform3D = seg_xform[seg]
		var rb := RigidBody3D.new()
		rb.name = "Ragdoll_%s" % seg
		rb.mass = float(RAGDOLL_MASS.get(seg, 300.0))
		rb.gravity_scale = 2.4 # matches mecha gravity (20 m/s^2) for heavy, crunching collapse
		rb.collision_layer = 8 # keep same as scrap
		rb.collision_mask = 1 | 2 # Environment + Mecha (ground)
		rb.linear_damp = 1.2 # strong friction to prevent floaty sliding
		rb.angular_damp = 2.8 # heavy rotational damping to prevent toy-like spinning
		rb.continuous_cd = true
		rb.contact_monitor = true
		rb.max_contacts_reported = 4
		rb.add_to_group("ragdoll")
		rb.add_to_group("ragdoll_part")

		# Collision shape — Box approximating the part
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = RAGDOLL_BOX.get(seg, Vector3(0.4, 0.4, 0.4))
		col.shape = shape
		rb.add_child(col)

		# Visuals — clone MeshInstances from the original segment
		var seg_node: Node3D = mecha.get_node_or_null(SEGMENT_NODE_PATH[seg]) as Node3D
		if seg_node != null:
			_clone_visuals_to(seg_node, rb, xf)

		# Fallback primitive if clone produced nothing (e.g. missing catalog)
		if _count_meshes(rb) == 0:
			var fallback := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = shape.size
			fallback.mesh = box
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.45, 0.45, 0.48)
			m.metallic = 0.25
			m.roughness = 0.65
			fallback.material_override = m
			rb.add_child(fallback)

		world.add_child(rb)
		# Must set global after added to scene
		rb.global_transform = xf

		# Heavy topple impulse — downward slump into ground, no floaty pop-up
		var topple_fwd: Vector3 = -mecha.global_transform.basis.z
		topple_fwd.y = 0.0
		topple_fwd = topple_fwd.normalized() if topple_fwd.length_squared() > 0.01 else Vector3.FORWARD
		var topple_side: Vector3 = mecha.global_transform.basis.x
		topple_side.y = 0.0
		topple_side = topple_side.normalized() if topple_side.length_squared() > 0.01 else Vector3.RIGHT

		if seg == "body":
			# Body collapses heavily down and topples forward
			var body_imp: Vector3 = topple_fwd * randf_range(-2.0, 3.0) + Vector3(0, -6.0, 0)
			rb.apply_central_impulse(body_imp * 12.0)
			rb.apply_torque_impulse(Vector3(randf_range(-15.0, -30.0), randf_range(-6, 6), randf_range(-6, 6)))
		else:
			# Limbs slump down with minor spread
			var limb_imp: Vector3 = topple_fwd * randf_range(-1.5, 1.5) + topple_side * randf_range(-1.5, 1.5) + Vector3(0, -4.0, 0)
			rb.apply_central_impulse(limb_imp * 5.0)
			rb.apply_torque_impulse(Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4)))

		bodies[seg] = rb
		created.append(rb)

	# Create PinJoints between connected segments
	for pair in JOINTS:
		var a_name: String = pair[0]
		var b_name: String = pair[1]
		if not bodies.has(a_name) or not bodies.has(b_name):
			continue
		var a_body: RigidBody3D = bodies[a_name]
		var b_body: RigidBody3D = bodies[b_name]
		if not is_instance_valid(a_body) or not is_instance_valid(b_body):
			continue
		var joint := PinJoint3D.new()
		joint.name = "Joint_%s_%s" % [a_name, b_name]
		# Place joint at midpoint — both bodies use this world point as anchor
		var mid: Vector3 = (a_body.global_position + b_body.global_position) * 0.5
		world.add_child(joint)
		joint.global_position = mid
		joint.node_a = a_body.get_path()
		joint.node_b = b_body.get_path()
		joint.set_param(PinJoint3D.PARAM_BIAS, 0.3)
		joint.set_param(PinJoint3D.PARAM_DAMPING, 1.5)
		joints_created.append(joint)

	# Hide original mecha visuals (keep node alive for BreachGlow / countdown)
	_hide_original_visuals(mecha)

	# Store on mecha for later scorch / blast / cleanup
	mecha.set_meta("ragdoll_bodies", created)
	mecha.set_meta("ragdoll_joints", joints_created)
	mecha.set_meta("ragdoll_map", bodies)

	return {"bodies": created, "joints": joints_created, "map": bodies}


static func apply_blast_to_ragdoll(mecha: Node, blast_pos: Vector3, force: float = 18.0) -> void:
	if mecha == null or not is_instance_valid(mecha) or not mecha.has_meta("ragdoll_bodies"):
		return
	var arr = mecha.get_meta("ragdoll_bodies")
	if not arr is Array:
		return
	for rb in arr:
		if not is_instance_valid(rb) or not rb is RigidBody3D:
			continue
		var dir: Vector3 = (rb.global_position - blast_pos)
		var dist: float = dir.length()
		if dist < 0.3:
			dist = 0.3
		dir /= dist
		var falloff := clampf(1.0 - (dist / 12.0), 0.25, 1.0)
		(rb as RigidBody3D).apply_central_impulse(dir * force * falloff + Vector3(0, force * 0.35 * falloff, 0))
		(rb as RigidBody3D).angular_velocity += Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4)) * falloff


static func scorch_ragdolls(mecha: Node) -> void:
	if mecha == null or not is_instance_valid(mecha) or not mecha.has_meta("ragdoll_bodies"):
		return
	var arr = mecha.get_meta("ragdoll_bodies")
	if not arr is Array:
		return
	for rb in arr:
		if not is_instance_valid(rb):
			continue
		for child in rb.get_children():
			if child is MeshInstance3D:
				var mi := child as MeshInstance3D
				var scorch := StandardMaterial3D.new()
				scorch.albedo_color = Color(0.06, 0.06, 0.06)
				scorch.metallic = 0.05
				scorch.roughness = 0.95
				scorch.emission_enabled = true
				scorch.emission = Color(0.95, 0.25, 0.05)
				scorch.emission_energy_multiplier = 1.0
				mi.material_override = scorch
				if rb.get_tree():
					var t := mi.create_tween()
					t.tween_property(scorch, "emission_energy_multiplier", 0.0, 2.5)


# --- Helpers ---------------------------------------------------------------

static func _fallback_offset(seg: String) -> Vector3:
	match seg:
		"head": return Vector3(0, 4.4436, -0.07728)
		"body": return Vector3(0, 3.4776, 0)
		"arm_left": return Vector3(-1.311, 3.956, 0)
		"arm_right": return Vector3(1.311, 3.956, 0)
		"forearm_left": return Vector3(-1.311, 3.22, 0)
		"forearm_right": return Vector3(1.311, 3.22, 0)
		"leg_left": return Vector3(-0.736, 2.507, 0)
		"leg_right": return Vector3(0.736, 2.507, 0)
		"shin_left": return Vector3(-0.736, 1.449, 0)
		"shin_right": return Vector3(0.736, 1.449, 0)
		"foot_left": return Vector3(-0.736, 0.425, 0)
		"foot_right": return Vector3(0.736, 0.425, 0)
		_: return Vector3.ZERO


static func _clone_visuals_to(source: Node3D, target: RigidBody3D, seg_global: Transform3D) -> void:
	var meshes := _collect_mesh_instances(source)
	for orig in meshes:
		var mi := orig as MeshInstance3D
		if not is_instance_valid(mi):
			continue
		var clone := MeshInstance3D.new()
		clone.mesh = mi.mesh
		if mi.material_override != null:
			clone.material_override = mi.material_override
		elif mi.mesh != null and mi.mesh.get_surface_count() > 0:
			# Try surface override 0
			var surf_mat := mi.get_surface_override_material(0)
			if surf_mat != null:
				clone.material_override = surf_mat
		# Preserve world-relative offset inside the segment
		# All procedural meshes are children of FrameMesh/ArmorMesh which live
		# under the segment node — convert their global offset to body-local.
		var world_xf: Transform3D = mi.global_transform
		var local_xf: Transform3D = seg_global.affine_inverse() * world_xf
		clone.transform = local_xf
		target.add_child(clone)


static func _collect_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node == null or not is_instance_valid(node):
		return out

	var armor_mesh_node := node.get_node_or_null("ArmorMesh") as Node3D
	var armor_meshes: Array = []
	if armor_mesh_node != null and armor_mesh_node.visible:
		_collect_recursive(armor_mesh_node, armor_meshes)

	if not armor_meshes.is_empty():
		# Outer armor exists and is visible -> use outer armor model, exclude inner frame boxes!
		out.append_array(armor_meshes)
		# Also collect accessories (e.g. Backpack / Thrusters under Body)
		for child in node.get_children():
			if child.name == "ArmorMesh" or child.name == "FrameMesh":
				continue
			if child.name.begins_with("Forearm") or child.name.begins_with("Shin") or child.name.begins_with("Foot"):
				continue
			if child is Light3D or child is CollisionShape3D or child.is_in_group("pilot"):
				continue
			_collect_recursive(child, out)
	else:
		# No outer armor -> use inner frame or other visual nodes
		_collect_recursive(node, out)

	return out

static func _collect_recursive(node: Node, into: Array) -> void:
	# Skip hidden branches (e.g. hidden FrameMesh procedural boxes while armor is on, or hidden drop tanks)
	if node is Node3D and not (node as Node3D).visible:
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.visible and mi.mesh != null:
			into.append(mi)
	for child in node.get_children():
		# Never recurse into ragdoll plumbing, lights, or pilots
		if child is Light3D or child is CollisionShape3D or child.is_in_group("pilot"):
			continue
		# Also do NOT recurse into child limb segments (e.g. Forearm under Arm, Shin under Leg, Foot under Shin)
		if child.name.begins_with("Forearm") or child.name.begins_with("Shin") or child.name.begins_with("Foot"):
			continue
		_collect_recursive(child, into)


static func _count_meshes(rb: RigidBody3D) -> int:
	var c := 0
	for child in rb.get_children():
		if child is MeshInstance3D:
			c += 1
	return c


static func _hide_original_visuals(mecha: Node3D) -> void:
	# Hide every MeshInstance under the slot nodes but keep Node3D transforms
	# alive (the mecha node itself must stay for glow/countdown/timers).
	for seg in SEGMENT_NODE_PATH:
		var n := mecha.get_node_or_null(SEGMENT_NODE_PATH[seg]) as Node3D
		if n == null:
			continue
		_hide_meshes_recursive(n)
	# Also hide any top-level legacy meshes on the mecha root, skipping pilots
	for child in mecha.get_children():
		if child.is_in_group("pilot"):
			continue
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false

static func _hide_meshes_recursive(node: Node) -> void:
	if node.is_in_group("pilot"):
		return
	if node is MeshInstance3D:
		(node as MeshInstance3D).visible = false
	for child in node.get_children():
		_hide_meshes_recursive(child)
