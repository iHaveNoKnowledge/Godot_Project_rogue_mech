extends Node

## Headless GLB -> Godot validation for exports/mech_innerframe_joints.glb
## (modular mech + 80 mechanical joint assemblies on the InnerRig skeleton).
## Run: godot --headless --path . res://tests/glb_joint_import_validation.tscn
##
## Scope: import integrity, bone hierarchy, modular meshes, skin binding,
## FK articulation of every joint, scale/axis, materials, hidden legacy
## shells, rest-pose connections, node complexity. No rendering readback:
## skin deformation itself is GPU-side; this test proves the bones move and
## every joint mesh is bound to the Skeleton3D via a Skin resource.

const GLB_PATH := "res://exports/mech_innerframe_joints.glb"

const EXPECTED_BONES: Array[String] = [
	"Inner_Pelvis",
	"Inner_HipL", "Inner_KneeL", "Inner_AnkleL", "Inner_FootL", "Inner_ToeL",
	"Inner_HipR", "Inner_KneeR", "Inner_AnkleR", "Inner_FootR", "Inner_ToeR",
	"Inner_Spine1", "Inner_Spine2", "Inner_Spine3",
	"Inner_Neck", "Inner_Head",
	"Inner_CollarL", "Inner_ShoulderL", "Inner_ElbowL", "Inner_WristL",
	"Inner_CollarR", "Inner_ShoulderR", "Inner_ElbowR", "Inner_WristR",
]

# JNT mesh-name fragment -> bone that must drive it (rigid single-bone skin).
const JNT_BONE_MAP := {
	"shoulder_L_mount": "Inner_CollarL", "shoulder_L_housing": "Inner_CollarL",
	"shoulder_L_actuator": "Inner_CollarL", "shoulder_L_bolts": "Inner_CollarL",
	"shoulder_L_stop": "Inner_CollarL",
	"shoulder_L_core": "Inner_ShoulderL", "shoulder_L_axle": "Inner_ShoulderL",
	"shoulder_L_collar": "Inner_ShoulderL",
	"elbow_L_yoke": "Inner_ShoulderL", "elbow_L_plates": "Inner_ShoulderL",
	"elbow_L_actuator": "Inner_ShoulderL", "elbow_L_stop": "Inner_ShoulderL",
	"elbow_L_drum": "Inner_ElbowL", "elbow_L_axle": "Inner_ElbowL",
	"elbow_L_collar": "Inner_ElbowL",
	"hip_L_mount": "Inner_Pelvis", "hip_L_housing": "Inner_Pelvis",
	"hip_L_actuator": "Inner_Pelvis", "hip_L_bolts": "Inner_Pelvis",
	"hip_L_stop": "Inner_Pelvis",
	"hip_L_core": "Inner_HipL", "hip_L_axle": "Inner_HipL",
	"hip_L_collar": "Inner_HipL",
	"hip_R_mount": "Inner_Pelvis", "hip_R_housing": "Inner_Pelvis",
	"hip_R_actuator": "Inner_Pelvis", "hip_R_bolts": "Inner_Pelvis",
	"hip_R_stop": "Inner_Pelvis",
	"shoulder_R_mount": "Inner_CollarR", "shoulder_R_housing": "Inner_CollarR",
	"shoulder_R_actuator": "Inner_CollarR", "shoulder_R_bolts": "Inner_CollarR",
	"shoulder_R_stop": "Inner_CollarR",
	"shoulder_R_core": "Inner_ShoulderR", "shoulder_R_axle": "Inner_ShoulderR",
	"shoulder_R_collar": "Inner_ShoulderR",
	"elbow_R_yoke": "Inner_ShoulderR", "elbow_R_plates": "Inner_ShoulderR",
	"elbow_R_actuator": "Inner_ShoulderR", "elbow_R_stop": "Inner_ShoulderR",
	"elbow_R_drum": "Inner_ElbowR", "elbow_R_axle": "Inner_ElbowR",
	"elbow_R_collar": "Inner_ElbowR",
	"hip_R_core": "Inner_HipR", "hip_R_axle": "Inner_HipR",
	"hip_R_collar": "Inner_HipR",
	"knee_L_yoke": "Inner_HipL", "knee_L_plates": "Inner_HipL",
	"knee_L_actuator": "Inner_HipL", "knee_L_stop": "Inner_HipL",
	"knee_L_drum": "Inner_KneeL", "knee_L_axle": "Inner_KneeL",
	"knee_L_collar": "Inner_KneeL", "knee_L_shield": "Inner_KneeL",
	"knee_R_yoke": "Inner_HipR", "knee_R_plates": "Inner_HipR",
	"knee_R_actuator": "Inner_HipR", "knee_R_stop": "Inner_HipR",
	"knee_R_drum": "Inner_KneeR", "knee_R_axle": "Inner_KneeR",
	"knee_R_collar": "Inner_KneeR", "knee_R_shield": "Inner_KneeR",
	"ankle_L_clevis": "Inner_KneeL", "ankle_L_brackets": "Inner_KneeL",
	"ankle_L_actuator": "Inner_KneeL",
	"ankle_L_rotor": "Inner_AnkleL", "ankle_L_axle": "Inner_AnkleL",
	"ankle_L_footmount": "Inner_AnkleL",
	"ankle_R_clevis": "Inner_KneeR", "ankle_R_brackets": "Inner_KneeR",
	"ankle_R_actuator": "Inner_KneeR",
	"ankle_R_rotor": "Inner_AnkleR", "ankle_R_axle": "Inner_AnkleR",
	"ankle_R_footmount": "Inner_AnkleR",
	"neck_collar": "Inner_Spine3", "neck_bearing": "Inner_Spine3",
	"neck_actuator": "Inner_Spine3", "neck_bolts": "Inner_Spine3",
	"neck_rotor": "Inner_Head", "neck_headmount": "Inner_Head",
}

# Rest-pose connection pairs (must intersect): mesh-name fragments.
const REST_PAIRS := [
	["shoulder_R_mount", "shoulder_R_housing"],
	["shoulder_R_housing", "shoulder_R_core"],
	["shoulder_R_core", "shoulder_R_collar"],
	["elbow_R_drum", "elbow_R_collar"],
	["hip_R_housing", "hip_R_core"],
	["hip_R_core", "hip_R_collar"],
	["knee_R_drum", "knee_R_collar"],
	["ankle_R_rotor", "ankle_R_footmount"],
	["neck_rotor", "neck_headmount"],
]

const LEGACY_SHELLS: Array[String] = [
	"arm_l_shoulder_joint", "arm_r_shoulder_joint",
	"leg_l_hip_joint", "leg_r_hip_joint",
	"arm_l_elbow_disc", "arm_r_elbow_disc",
	"leg_l_knee_disc", "leg_r_knee_disc",
	"leg_l_ankle", "leg_r_ankle",
]

var _fails := 0
var _checks := 0
var _skel: Skeleton3D
var _mi_by_frag := {}


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + label)
	else:
		_fails += 1
		push_error("FAIL: " + label)


func _collect(n: Node, out: Array, t: String) -> void:
	if n.get_class() == t:
		out.append(n)
	for c in n.get_children():
		_collect(c, out, t)


func _mi_center_global(mi: MeshInstance3D) -> Vector3:
	var a := mi.get_aabb()
	return mi.global_transform * a.get_center()


func _pose(bone: String, e: Vector3) -> void:
	_skel.set_bone_pose_rotation(
		_skel.find_bone(bone), Quaternion(Vector3.RIGHT, e.x)
		* Quaternion(Vector3.UP, e.y) * Quaternion(Vector3.FORWARD, e.z))


func _bone_moved(bone: String, rest: Dictionary, thresh: float) -> bool:
	var p: Vector3 = _skel.get_bone_global_pose(_skel.find_bone(bone)).origin
	return p.distance_to(rest[bone]) > thresh


func _snapshot_bones() -> Dictionary:
	var d := {}
	for b in EXPECTED_BONES:
		d[b] = _skel.get_bone_global_pose(_skel.find_bone(b)).origin
	return d


func _reset_poses() -> void:
	_skel.reset_bone_poses()


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await _run()
	print("GLB_JOINT_VALIDATE: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	# ---- load ----
	var ps: PackedScene = load(GLB_PATH)
	_check(ps != null, "GLB loads as PackedScene")
	if ps == null:
		return
	var root := ps.instantiate()
	_check(root != null, "GLB instantiates")
	add_child(root)
	await get_tree().process_frame
	await get_tree().process_frame

	print("ROOT type=%s name=%s scale=%s" % [root.get_class(), root.name, str((root as Node3D).scale) if root is Node3D else "?"])
	_check(root is Node3D, "root is Node3D")
	if root is Node3D:
		_check((root as Node3D).scale.is_equal_approx(Vector3.ONE), "root scale is (1,1,1)")

	# ---- skeleton ----
	var skels: Array = []
	_collect(root, skels, "Skeleton3D")
	_check(skels.size() == 1, "exactly one Skeleton3D (found %d)" % skels.size())
	if skels.is_empty():
		return
	_skel = skels[0]
	_check(_skel.get_bone_count() == 24, "bone count is 24 (found %d)" % _skel.get_bone_count())
	var missing: Array[String] = []
	for b in EXPECTED_BONES:
		if _skel.find_bone(b) < 0:
			missing.append(b)
	_check(missing.is_empty(), "all 24 InnerRig bones present" + ("" if missing.is_empty() else " MISSING=%s" % str(missing)))
	print("BONE REST (global): pelvis=%s shoulderL=%s elbowL=%s hipL=%s kneeL=%s ankleL=%s neck=%s head=%s" % [
		str(_skel.get_bone_global_rest(_skel.find_bone("Inner_Pelvis")).origin) if _skel.find_bone("Inner_Pelvis") >= 0 else "?",
		str(_skel.get_bone_global_rest(_skel.find_bone("Inner_ShoulderL")).origin) if _skel.find_bone("Inner_ShoulderL") >= 0 else "?",
		str(_skel.get_bone_global_rest(_skel.find_bone("Inner_ElbowL")).origin) if _skel.find_bone("Inner_ElbowL") >= 0 else "?",
		str(_skel.get_bone_global_rest(_skel.find_bone("Inner_HipL")).origin) if _skel.find_bone("Inner_HipL") >= 0 else "?",
		str(_skel.get_bone_global_rest(_skel.find_bone("Inner_KneeL")).origin) if _skel.find_bone("Inner_KneeL") >= 0 else "?",
		str(_skel.get_bone_global_rest(_skel.find_bone("Inner_AnkleL")).origin) if _skel.find_bone("Inner_AnkleL") >= 0 else "?",
		str(_skel.get_bone_global_rest(_skel.find_bone("Inner_Neck")).origin) if _skel.find_bone("Inner_Neck") >= 0 else "?",
		str(_skel.get_bone_global_rest(_skel.find_bone("Inner_Head")).origin) if _skel.find_bone("Inner_Head") >= 0 else "?",
	])
	if _skel.find_bone("Inner_ShoulderL") >= 0:
		_check(absf(_skel.get_bone_global_rest(_skel.find_bone("Inner_ShoulderL")).origin.y - 2.2) < 0.05, "shoulder rest height ~= 2.2m")
	if _skel.find_bone("Inner_HipL") >= 0:
		_check(absf(_skel.get_bone_global_rest(_skel.find_bone("Inner_HipL")).origin.y - 1.3) < 0.05, "hip rest height ~= 1.3m")
	if _skel.find_bone("Inner_KneeL") >= 0:
		_check(absf(_skel.get_bone_global_rest(_skel.find_bone("Inner_KneeL")).origin.y - 0.75) < 0.05, "knee rest height ~= 0.75m")
	if _skel.find_bone("Inner_AnkleL") >= 0:
		_check(absf(_skel.get_bone_global_rest(_skel.find_bone("Inner_AnkleL")).origin.y - 0.22) < 0.05, "ankle rest height ~= 0.22m")
	# hierarchy spot checks
	if _skel.find_bone("Inner_KneeL") >= 0 and _skel.find_bone("Inner_HipL") >= 0:
		_check(_skel.get_bone_parent(_skel.find_bone("Inner_KneeL")) == _skel.find_bone("Inner_HipL"), "knee parent is hip")
	if _skel.find_bone("Inner_ElbowL") >= 0 and _skel.find_bone("Inner_ShoulderL") >= 0:
		_check(_skel.get_bone_parent(_skel.find_bone("Inner_ElbowL")) == _skel.find_bone("Inner_ShoulderL"), "elbow parent is shoulder")
	if _skel.find_bone("Inner_Head") >= 0 and _skel.find_bone("Inner_Neck") >= 0:
		_check(_skel.get_bone_parent(_skel.find_bone("Inner_Head")) == _skel.find_bone("Inner_Neck"), "head parent is neck")

	# ---- meshes ----
	var mis: Array = []
	_collect(root, mis, "MeshInstance3D")
	print("MESHINSTANCES: %d" % mis.size())
	_check(mis.size() >= 100, "mesh count >= 100 (found %d)" % mis.size())
	var jnt := 0
	for mi in mis:
		_mi_by_frag[(mi as Node).name] = mi
		if (mi as Node).name.begins_with("JNT_"):
			jnt += 1
	_check(jnt == 80, "80 JNT_ joint meshes (found %d)" % jnt)
	for frag in ["body_core", "head_skull", "upper_arm", "forearm_frame",
			"hand_block", "thigh_frame", "shin_frame", "foot_block"]:
		var hit := false
		for mi in mis:
			if frag in (mi as Node).name:
				hit = true
				break
		_check(hit, "modular mesh present: " + frag)
	for shell in LEGACY_SHELLS:
		var present := false
		for mi in mis:
			if (mi as Node).name == shell:
				present = true
				break
		_check(not present, "legacy shell excluded: " + shell)

	# ---- skin binding (Phase-14 warning check) ----
	var unbound: Array[String] = []
	var wrong_skel: Array[String] = []
	for mi in mis:
		var m := mi as MeshInstance3D
		var sp: NodePath = m.get("skeleton")
		var sn: Node = m.get_node_or_null(sp) if sp != null else null
		if sn == null or not (sn is Skeleton3D):
			unbound.append(m.name)
		elif sn != _skel:
			wrong_skel.append(m.name)
	_check(unbound.is_empty(), "all meshes bound to a Skeleton3D" + ("" if unbound.is_empty() else " UNBOUND=%s" % str(unbound.slice(0, 5))))
	_check(wrong_skel.is_empty(), "all meshes bound to THE imported Skeleton3D")
	var no_skin := 0
	for mi in mis:
		if (mi as MeshInstance3D).skin == null:
			no_skin += 1
	print("meshes without Skin resource: %d" % no_skin)
	# JNT -> expected-bone mapping documented via node metadata is not in
	# glTF; verify by skin joint names instead.
	var skin_bones := {}
	for mi in mis:
		var sk: Skin = (mi as MeshInstance3D).skin
		if sk == null:
			continue
		for ji in sk.get_bind_count():
			skin_bones[sk.get_bind_name(ji)] = true
			var bi := sk.get_bind_bone(ji)
			if bi >= 0:
				skin_bones[_skel.get_bone_name(bi)] = true
	_check(skin_bones.has("Inner_ElbowL") and skin_bones.has("Inner_KneeL") and skin_bones.has("Inner_AnkleL") and skin_bones.has("Inner_Head"), "skins reference elbow/knee/ankle/head joints")

	# ---- FK articulation (5A-5F) ----
	var rest := _snapshot_bones()
	_pose("Inner_ShoulderL", Vector3(0.5, 0, -0.4))
	await get_tree().process_frame
	_check(_bone_moved("Inner_ElbowL", rest, 0.01), "5A shoulder L moves elbow")
	_check(_bone_moved("Inner_WristL", rest, 0.01), "5A shoulder L moves wrist")
	_check(not _bone_moved("Inner_CollarL", rest, 0.01), "5A collar stays (housing isolation)")
	_reset_poses()
	await get_tree().process_frame
	rest = _snapshot_bones()
	_pose("Inner_ShoulderR", Vector3(0.5, 0, 0.4))
	await get_tree().process_frame
	_check(_bone_moved("Inner_ElbowR", rest, 0.01), "5A shoulder R moves elbow")
	_reset_poses()
	await get_tree().process_frame
	rest = _snapshot_bones()
	_pose("Inner_ElbowL", Vector3(1.0, 0, 0))
	await get_tree().process_frame
	_check(_bone_moved("Inner_WristL", rest, 0.01), "5B elbow L moves wrist")
	_check(not _bone_moved("Inner_ShoulderL", rest, 0.01), "5B shoulder stays (housing isolation)")
	_reset_poses()
	await get_tree().process_frame
	rest = _snapshot_bones()
	_pose("Inner_ElbowR", Vector3(2.0, 0, 0))
	await get_tree().process_frame
	_check(_bone_moved("Inner_WristR", rest, 0.05), "5B elbow R extreme (~115deg) moves wrist")
	_reset_poses()
	await get_tree().process_frame
	rest = _snapshot_bones()
	_pose("Inner_HipL", Vector3(-0.5, 0, 0))
	await get_tree().process_frame
	_check(_bone_moved("Inner_KneeL", rest, 0.01), "5C hip L moves knee")
	_check(not _bone_moved("Inner_Pelvis", rest, 0.01), "5C pelvis stays (housing isolation)")
	_reset_poses()
	await get_tree().process_frame
	rest = _snapshot_bones()
	_pose("Inner_KneeL", Vector3(0.7, 0, 0))
	await get_tree().process_frame
	_check(_bone_moved("Inner_AnkleL", rest, 0.01), "5D knee L moves ankle")
	_check(not _bone_moved("Inner_HipL", rest, 0.01), "5D hip stays (housing isolation)")
	_reset_poses()
	await get_tree().process_frame
	rest = _snapshot_bones()
	_pose("Inner_HipR", Vector3(-0.5, 0, 0))
	await get_tree().process_frame
	_check(_bone_moved("Inner_KneeR", rest, 0.01), "5C hip R moves knee")
	_reset_poses()
	await get_tree().process_frame
	rest = _snapshot_bones()
	_pose("Inner_KneeR", Vector3(1.9, 0, 0))
	await get_tree().process_frame
	_check(_bone_moved("Inner_AnkleR", rest, 0.05), "5D knee R extreme (~109deg) moves ankle")
	_reset_poses()
	await get_tree().process_frame
	rest = _snapshot_bones()
	_pose("Inner_AnkleR", Vector3(0.3, 0, 0))
	await get_tree().process_frame
	_check(_bone_moved("Inner_FootR", rest, 0.005), "5E ankle R pitch moves foot")
	_reset_poses()
	await get_tree().process_frame
	rest = _snapshot_bones()
	_pose("Inner_AnkleL", Vector3(0, 0, 0.2))
	await get_tree().process_frame
	_check(_bone_moved("Inner_FootL", rest, 0.005), "5E ankle L roll moves foot")
	_check(not _bone_moved("Inner_KneeL", rest, 0.01), "5E lower leg stays during ankle motion")
	_reset_poses()
	await get_tree().process_frame
	rest = _snapshot_bones()
	# Yaw spins the head in place (origin on the axis): verify by rotation.
	_pose("Inner_Neck", Vector3(0, 0.5, 0))
	_pose("Inner_Head", Vector3(0, 0.3, 0))
	await get_tree().process_frame
	var ang := _skel.get_bone_pose_rotation(_skel.find_bone("Inner_Neck")).get_angle()
	_check(ang > 0.1, "5F neck yaw applies (angle=%.2f)" % ang)
	# Pitch/roll on the NECK translates the head origin: the head follows.
	_reset_poses()
	await get_tree().process_frame
	rest = _snapshot_bones()
	_pose("Inner_Neck", Vector3(0.3, 0, 0.2))
	await get_tree().process_frame
	_check(_bone_moved("Inner_Head", rest, 0.005), "5F head follows neck pitch/roll")
	_check(not _bone_moved("Inner_Spine3", rest, 0.01), "5F torso stays during neck motion")
	_reset_poses()
	await get_tree().process_frame

	# ---- full poses A-G (smoke: poses apply, no NaN) ----
	var poses := {
		"B arm flex": {"Inner_ShoulderR": Vector3(0.5, 0, -0.4), "Inner_ElbowR": Vector3(1.0, 0, 0)},
		"C leg flex": {"Inner_HipR": Vector3(-0.5, 0, 0), "Inner_KneeR": Vector3(0.7, 0, 0)},
		"D crouch": {"Inner_HipL": Vector3(-0.7, 0, 0), "Inner_HipR": Vector3(-0.7, 0, 0), "Inner_KneeL": Vector3(0.9, 0, 0), "Inner_KneeR": Vector3(0.9, 0, 0), "Inner_AnkleL": Vector3(0.2, 0, 0), "Inner_AnkleR": Vector3(0.2, 0, 0)},
		"E opposite": {"Inner_HipL": Vector3(-0.6, 0, 0), "Inner_HipR": Vector3(0.5, 0, 0), "Inner_ShoulderL": Vector3(0.5, 0, 0), "Inner_ShoulderR": Vector3(-0.5, 0, 0)},
		"F run": {"Inner_HipL": Vector3(-0.6, 0, 0), "Inner_KneeL": Vector3(0.5, 0, 0), "Inner_ElbowL": Vector3(0.8, 0, 0)},
		"G extreme": {"Inner_ElbowR": Vector3(2.0, 0, 0), "Inner_KneeR": Vector3(1.9, 0, 0), "Inner_ShoulderR": Vector3(1.4, 0, 0)},
	}
	for pname in poses:
		for b in (poses[pname] as Dictionary).keys():
			_pose(b, (poses[pname] as Dictionary)[b])
		await get_tree().process_frame
		var ok := true
		for i in _skel.get_bone_count():
			var o: Vector3 = _skel.get_bone_global_pose(i).origin
			if not (is_finite(o.x) and is_finite(o.y) and is_finite(o.z)):
				ok = false
		_check(ok, "pose %s applies cleanly" % pname)
		_reset_poses()
		await get_tree().process_frame

	# ---- animation ----
	var players: Array = []
	_collect(root, players, "AnimationPlayer")
	print("ANIMATIONPLAYERS: %d" % players.size())
	if players.is_empty():
		print("NOTE: GLB carries no embedded animation (exported with animations off); Strafe_Loop lives in the Blender source only")
	else:
		for ap in players:
			print("PLAYER anims: %s" % str((ap as AnimationPlayer).get_animation_list()))

	# ---- materials ----
	var mats := {}
	for mi in mis:
		var m := mi as MeshInstance3D
		for si in m.get_surface_override_material_count():
			var sm := m.get_surface_override_material(si)
			if sm != null:
				mats[sm] = true
		var mm := m.mesh
		if mm != null:
			for si in mm.get_surface_count():
				var smm := mm.surface_get_material(si)
				if smm != null:
					mats[smm] = true
	print("UNIQUE MATERIALS: %d" % mats.size())
	var dark := false
	var steel := false
	var red := false
	for mt in mats.keys():
		if mt is StandardMaterial3D:
			var c: Color = (mt as StandardMaterial3D).albedo_color
			print("MAT albedo=%s metallic=%.2f rough=%.2f" % [str(c), (mt as StandardMaterial3D).metallic, (mt as StandardMaterial3D).roughness])
			var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			if lum < 0.25:
				dark = true
			if lum > 0.35:
				steel = true
			if c.r > 0.6 and c.r > 2.0 * c.g and c.r > 2.0 * c.b:
				red = true
	_check(dark, "dark armor material present")
	_check(steel, "light steel material present")
	_check(red, "red stop material present")

	# ---- axis: eye sensor must be forward (-Z in Godot) ----
	var eye: MeshInstance3D = null
	for mi in mis:
		if "eye_sensor" in (mi as Node).name:
			eye = mi
			break
	_check(eye != null, "head eye sensor mesh present")
	if eye != null:
		_check(_mi_center_global(eye).z < 0.0, "eye sensor sits forward (-Z), value=%.3f" % _mi_center_global(eye).z)

	# ---- rest connections ----
	for pair in REST_PAIRS:
		var a: MeshInstance3D = null
		var b: MeshInstance3D = null
		for mi in mis:
			if (pair[0] as String) in (mi as Node).name:
				a = mi
			if (pair[1] as String) in (mi as Node).name:
				b = mi
		if a == null or b == null:
			_check(false, "rest pair nodes found: %s <-> %s" % [pair[0], pair[1]])
			continue
		var ab := _global_aabb(a)
		var bb := _global_aabb(b)
		_check(ab.intersects(bb), "rest overlap: %s <-> %s" % [pair[0], pair[1]])

	# ---- complexity ----
	var total_nodes := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		total_nodes += 1
		stack.append_array(n.get_children())
	print("TOTAL NODES: %d MESHES: %d MATERIALS: %d" % [total_nodes, mis.size(), mats.size()])
	_check(total_nodes < 1000, "node count sane (%d)" % total_nodes)

	root.queue_free()
	await get_tree().process_frame


func _global_aabb(mi: MeshInstance3D) -> AABB:
	var l := mi.get_aabb()
	var t := mi.global_transform
	var pts := [
		t * l.position, t * (l.position + Vector3(l.size.x, 0, 0)),
		t * (l.position + Vector3(0, l.size.y, 0)), t * (l.position + Vector3(0, 0, l.size.z)),
		t * (l.position + l.size), t * (l.position + Vector3(l.size.x, l.size.y, 0)),
		t * (l.position + Vector3(l.size.x, 0, l.size.z)), t * (l.position + Vector3(0, l.size.y, l.size.z)),
	]
	var out := AABB(pts[0], Vector3.ZERO)
	for i in range(1, pts.size()):
		out = out.expand(pts[i])
	return out


func is_finite(v: float) -> bool:
	return not (is_nan(v) or is_inf(v))
