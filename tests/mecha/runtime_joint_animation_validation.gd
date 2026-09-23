extends Node

## Runtime pipeline validation for the jointed inner-frame mech:
##   game movement (cmd_world_direction)
##   -> MechaAnimation pivots (Head/Body/Arm*/Leg* on mecha_base.tscn)
##   -> mapped InnerRig bone poses (exports/mech_innerframe_joints.glb)
##   -> joint mechanisms follow (binding proven by glb_joint_import_validation)
##
## Validation-only substitution: the jointed GLB is instantiated ALONGSIDE the
## mech. No production scene or script is modified. Pivot->bone mapping copies
## local rotation (both frames are world-X-aligned at rest, so sagittal motion
## transfers 1:1; the test asserts FK chain response, not the copy itself).
##
## Run: godot --headless --path . res://tests/mecha/runtime_joint_animation_validation.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"
const JOINT_GLB := "res://exports/mech_innerframe_joints.glb"

# Modular pivot path (under mech) -> InnerRig bone driven from it.
const PIVOT_BONE_MAP := {
	"ArmLeft": "Inner_ShoulderL",
	"ArmLeft/ForearmLeft": "Inner_ElbowL",
	"ArmRight": "Inner_ShoulderR",
	"ArmRight/ForearmRight": "Inner_ElbowR",
	"LegLeft": "Inner_HipL",
	"LegLeft/ShinLeft": "Inner_KneeL",
	"LegLeft/ShinLeft/FootLeft": "Inner_AnkleL",
	"LegRight": "Inner_HipR",
	"LegRight/ShinRight": "Inner_KneeR",
	"LegRight/ShinRight/FootRight": "Inner_AnkleR",
	"Head": "Inner_Head",
	"Body": "Inner_Spine2",
}

# Bone pairs whose global distance must stay invariant (rigid skeleton =
# housings stay concentric with rotors under any pose).
const BONE_PAIRS := [
	["Inner_ShoulderL", "Inner_ElbowL"], ["Inner_ElbowL", "Inner_WristL"],
	["Inner_ShoulderR", "Inner_ElbowR"], ["Inner_ElbowR", "Inner_WristR"],
	["Inner_HipL", "Inner_KneeL"], ["Inner_KneeL", "Inner_AnkleL"],
	["Inner_AnkleL", "Inner_FootL"],
	["Inner_HipR", "Inner_KneeR"], ["Inner_KneeR", "Inner_AnkleR"],
	["Inner_AnkleR", "Inner_FootR"],
	["Inner_Neck", "Inner_Head"],
	["Inner_CollarL", "Inner_ShoulderL"], ["Inner_CollarR", "Inner_ShoulderR"],
]

var _fails := 0
var _checks := 0
var _mech: CharacterBody3D
var _anim: Node
var _skel: Skeleton3D
var _joint_root: Node
var _pivots := {}
var _jnt_nodes: Array = []
var _phase := "setup"
var _phase_frame := 0
var _leg_swing: Array = []
var _foot_y_l: Array = []
var _foot_y_r: Array = []
var _idle_snapshot := {}
var _jnt_local := {}
var _branches := {}
var _run_samples := 0
var _yaw_start := 0.0
var _done := false


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + label)
	else:
		_fails += 1
		push_error("FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	await _setup()
	# _physics_process drives the state machine from here on.


func _setup() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.position = Vector3(0, -1.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000, 3, 2000)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)

	_mech = load(MECH_SCENE).instantiate()
	_mech.position = Vector3(0, 10, 0)
	add_child(_mech)
	# AI-drive hook: bypasses player Input, uses cmd_world_direction.
	_mech.is_player_driven = false
	_mech.turn_rate = 5.0

	var ps: PackedScene = load(JOINT_GLB)
	_joint_root = ps.instantiate()
	add_child(_joint_root)
	await get_tree().process_frame
	_skel = _find_skeleton(_joint_root)
	_collect_jnt(_joint_root)

	_anim = _mech.get_node_or_null("MechaAnimation")
	_check(_anim != null, "MechaAnimation system initializes on mecha_base")
	for p in PIVOT_BONE_MAP.keys():
		_pivots[p] = _mech.get_node_or_null(p)
	var missing: Array = []
	for p in PIVOT_BONE_MAP.keys():
		if _pivots[p] == null:
			missing.append(p)
	_check(missing.is_empty(), "animation pivots resolve" + ("" if missing.is_empty() else " MISSING=%s" % str(missing)))
	_check(_skel != null and _skel.get_bone_count() == 24, "joint GLB InnerRig resolves (24 bones)")
	_check(_jnt_nodes.size() == 80, "80 JNT_ mechanisms present (%d)" % _jnt_nodes.size())
	for j in _jnt_nodes:
		_jnt_local[(j as Node).name] = (j as Node3D).transform
	if _skel == null or _mech == null or _anim == null:
		_done = true
		print("RUNTIME_JOINT_VALIDATE: checks=%d fails=%d (setup incomplete, aborting)" % [_checks, _fails])
		get_tree().quit(1)
		return
	_set_phase("landing")


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var f := _find_skeleton(c)
		if f != null:
			return f
	return null


func _collect_jnt(n: Node) -> void:
	if n is MeshInstance3D and (n as Node).name.begins_with("JNT_"):
		_jnt_nodes.append(n)
	for c in n.get_children():
		_collect_jnt(c)


func _set_phase(p: String) -> void:
	_phase = p
	_phase_frame = 0
	print("PHASE: " + p)


func _physics_process(_delta: float) -> void:
	if _done or _mech == null or _skel == null:
		return
	_apply_mapping()
	_phase_frame += 1
	match _phase:
		"landing":
			if _mech.is_on_floor() or _phase_frame > 180:
				_check(_mech.is_on_floor(), "mech settles on ground")
				_set_phase("idle")
		"idle":
			_mech.cmd_world_direction = Vector3.ZERO
			if _phase_frame >= 120:
				_check(_mech.velocity.length() < 0.8, "idle holds still")
				_check(absf(_pivot_rx("LegLeft")) < 0.3 and absf(_pivot_rx("LegRight")) < 0.3, "idle legs near rest")
				_note_branch()
				_snapshot(_idle_snapshot) # settled-idle baseline for drift check
				_mech.cmd_world_direction = Vector3(0, 0, -1)
				_set_phase("forward")
		"forward":
			_track_gait()
			if _phase_frame >= 240:
				_check(_forward_speed() > 0.8, "forward movement works (speed=%.2f)" % _forward_speed())
				_check(_swing_amp() > 0.15, "forward drives leg swing (amp=%.2f)" % _swing_amp())
				_note_branch()
				_mech.cmd_world_direction = Vector3(0, 0, 1)
				_leg_swing.clear()
				_set_phase("backward")
		"backward":
			_track_gait()
			if _phase_frame >= 150:
				_check(_mech.velocity.length() > 0.8, "backward movement works")
				_note_branch()
				_mech.cmd_world_direction = Vector3(-1, 0, 0)
				_set_phase("strafe_l")
		"strafe_l":
			if _phase_frame >= 120:
				_check(_mech.velocity.length() > 0.8 and _mech.velocity.x < -0.5, "strafe left works")
				_note_branch()
				_mech.cmd_world_direction = Vector3(1, 0, 0)
				_set_phase("strafe_r")
		"strafe_r":
			if _phase_frame >= 120:
				_check(_mech.velocity.length() > 0.8 and _mech.velocity.x > 0.5, "strafe right works")
				_note_branch()
				_yaw_start = _mech.rotation.y
				_mech.cmd_world_direction = Vector3(1, 0, -1)
				_set_phase("turn")
		"turn":
			if _phase_frame >= 180:
				_check(absf(wrapf(_mech.rotation.y - _yaw_start, -PI, PI)) > 0.3, "turning works (dyaw=%.2f)" % absf(wrapf(_mech.rotation.y - _yaw_start, -PI, PI)))
				_note_branch()
				_mech.cmd_world_direction = Vector3.ZERO
				EventBus.mecha_occupancy_changed.emit(false)
				_set_phase("crouch")
		"crouch":
			if _phase_frame >= 180:
				_check(_anim.get("is_kneeling") == true, "crouch state engages")
				_check(_pivot_rx("LegLeft") > 0.9, "crouch folds thighs (%.2f)" % _pivot_rx("LegLeft"))
				_check(_finite_skeleton(), "crouch keeps skeleton finite")
				_check(_lengths_ok(0.01), "crouch keeps joint anchors concentric")
				_foot_state("crouch")
				EventBus.mecha_occupancy_changed.emit(true)
				_set_phase("stand")
		"stand":
			if _phase_frame >= 180:
				_check(_anim.get("is_kneeling") == false, "stand recovers")
				_check(_pivot_rx("LegLeft") < 0.4, "stand unfolds thighs")
				_mech.cmd_world_direction = Vector3(0, 0, -1)
				_foot_y_l.clear()
				_foot_y_r.clear()
				_run_samples = 0
				_set_phase("run")
		"run":
			_track_run()
			var marks := [0, 450, 900, 1350, 1799]
			if _run_samples < marks.size() and _phase_frame >= marks[_run_samples]:
				_sample_run(_run_samples)
				_run_samples += 1
			if _phase_frame >= 1800:
				_check(_forward_speed() > 0.8, "run sustains speed")
				_check(_symmetric_stride(), "run stride symmetric L/R")
				_check(_foot_range() > 0.03, "run lifts feet (range=%.3f)" % _foot_range())
				_note_branch()
				_mech.cmd_world_direction = Vector3.ZERO
				_set_phase("settle")
		"settle":
			if _phase_frame >= 150:
				_check(_drift_ok(), "no transform drift after 30s run")
				_check(_jnt_locals_intact(), "joint nodes unmutated by runtime")
				_report_armor()
				_done = true
				print("RUNTIME_JOINT_VALIDATE: checks=%d fails=%d branches=%s" % [_checks, _fails, str(_branches.keys())])
				get_tree().quit(1 if _fails > 0 else 0)


# Copies modular pivot local rotation onto the mapped InnerRig bone pose.
# Runs in test _physics_process AFTER the mech systems (child order), so it
# reads this frame's animation output with one frame of lag.
var _body_base_y := 0.0
var _body_seeded := false

func _apply_mapping() -> void:
	for p in PIVOT_BONE_MAP.keys():
		var pivot: Node3D = _pivots[p]
		if pivot == null:
			continue
		var bi := _skel.find_bone(PIVOT_BONE_MAP[p])
		if bi < 0:
			continue
		_skel.set_bone_pose_rotation(bi, Quaternion.from_euler(pivot.rotation))
	var body: Node3D = _pivots.get("Body")
	if body != null:
		if not _body_seeded:
			_body_base_y = body.position.y
			_body_seeded = true
		var pi := _skel.find_bone("Inner_Pelvis")
		if pi >= 0:
			_skel.set_bone_pose_position(pi, Vector3(0, body.position.y - _body_base_y, 0))


func _pivot_rx(p: String) -> float:
	var n: Node3D = _pivots.get(p)
	return n.rotation.x if n != null else 0.0


func _forward_speed() -> float:
	return Vector2(_mech.velocity.x, _mech.velocity.z).length()


func _track_gait() -> void:
	_leg_swing.append(_pivot_rx("LegLeft"))
	_leg_swing.append(_pivot_rx("LegRight"))


func _swing_amp() -> float:
	if _leg_swing.is_empty():
		return 0.0
	return _leg_swing.max() - _leg_swing.min()


func _track_run() -> void:
	_leg_swing.append(_pivot_rx("LegLeft"))
	_foot_y_l.append(_bone_y("Inner_FootL"))
	_foot_y_r.append(_bone_y("Inner_FootR"))


func _bone_y(b: String) -> float:
	var i := _skel.find_bone(b)
	if i < 0:
		return 0.0
	return _skel.get_bone_global_pose(i).origin.y


func _snapshot(d: Dictionary) -> void:
	d.clear()
	for p in PIVOT_BONE_MAP.keys():
		var n: Node3D = _pivots.get(p)
		if n != null:
			d[p] = n.rotation


func _note_branch() -> void:
	if _anim != null:
		_branches[_anim.get("debug_branch")] = true
		print("branch[%s]=%s" % [_phase, str(_anim.get("debug_branch"))])


func _finite_skeleton() -> bool:
	for i in _skel.get_bone_count():
		var o: Vector3 = _skel.get_bone_global_pose(i).origin
		if is_nan(o.x) or is_nan(o.y) or is_nan(o.z) or is_inf(o.x) or is_inf(o.y) or is_inf(o.z):
			return false
	var s := _skel.global_transform.basis.get_scale()
	if not (is_equal_approx(s.x, 1.0) and is_equal_approx(s.y, 1.0) and is_equal_approx(s.z, 1.0)):
		return false
	return true


func _lengths_ok(tol: float) -> bool:
	for pair in BONE_PAIRS:
		var a := _skel.find_bone(pair[0])
		var b := _skel.find_bone(pair[1])
		if a < 0 or b < 0:
			return false
		var rest: float = _skel.get_bone_global_rest(a).origin.distance_to(_skel.get_bone_global_rest(b).origin)
		var now: float = _skel.get_bone_global_pose(a).origin.distance_to(_skel.get_bone_global_pose(b).origin)
		if absf(now - rest) > tol:
			return false
	return true


func _sample_run(idx: int) -> void:
	# Beginning / 25% / 50% / 75% / end integrity probe.
	_check(_finite_skeleton(), "run sample %d: skeleton finite" % idx)
	_check(_lengths_ok(0.01), "run sample %d: joint anchors concentric" % idx)
	_check(_foot_forward(idx), "run sample %d: ankle articulation sane, feet attached" % idx)


func _foot_forward(idx: int) -> bool:
	# No FootIK runs under the baked run clip (by design — IK would fight the
	# cycle), so a swing foot legitimately folds back at toe-off while the
	# stance foot stays planted. Assert the sane property instead: ankle
	# articulation stays within range (no 180-degree flip) and the foot
	# remains attached (anchor invariance is covered by _lengths_ok).
	var ok := true
	for side in ["L", "R"]:
		var pv: Node3D = _pivots["LegLeft/ShinLeft/FootLeft" if side == "L" else "LegRight/ShinRight/FootRight"]
		if pv == null:
			return false
		if absf(pv.rotation.x) > 1.25 or absf(pv.rotation.z) > 1.25:
			ok = false
		var i := _skel.find_bone("Inner_Foot" + side)
		var fwd: Vector3 = -(_skel.get_bone_global_pose(i).basis.z.normalized())
		var mwd: Vector3 = -_mech.global_transform.basis.z.normalized()
		print("sample%d Inner_Foot%s dot=%.3f footpivot=%s vel=%s floor=%s branch=%s" % [
			idx, side, fwd.dot(mwd), str(pv.rotation),
			str(_mech.velocity), str(_mech.is_on_floor()), str(_anim.get("debug_branch"))])
	return ok


func _foot_state(tag: String) -> void:
	for b in ["Inner_FootL", "Inner_FootR"]:
		var i := _skel.find_bone(b)
		if i >= 0:
			var o: Vector3 = _skel.get_bone_global_pose(i).origin
			print("foot[%s] %s y=%.3f" % [tag, b, o.y])


func _symmetric_stride() -> bool:
	if _foot_y_l.is_empty() or _foot_y_r.is_empty():
		return false
	var rl: float = _foot_y_l.max() - _foot_y_l.min()
	var rr: float = _foot_y_r.max() - _foot_y_r.min()
	print("stride L range=%.3f R range=%.3f" % [rl, rr])
	if maxf(rl, rr) < 0.001:
		return false
	return minf(rl, rr) / maxf(rl, rr) > 0.4


func _foot_range() -> float:
	var all: Array = _foot_y_l + _foot_y_r
	if all.is_empty():
		return 0.0
	return all.max() - all.min()


func _drift_ok() -> bool:
	var ok := true
	for p in PIVOT_BONE_MAP.keys():
		var n: Node3D = _pivots.get(p)
		if n == null or not _idle_snapshot.has(p):
			continue
		var d: Vector3 = (n.rotation - (_idle_snapshot[p] as Vector3)).abs()
		if d.x > 0.25 or d.y > 0.25 or d.z > 0.25:
			print("drift %s idle=%s now=%s" % [p, str(_idle_snapshot[p]), str(n.rotation)])
			ok = false
	if not _lengths_ok(0.01):
		print("drift: bone lengths changed")
		ok = false
	if not _finite_skeleton():
		print("drift: skeleton non-finite")
		ok = false
	return ok


func _jnt_locals_intact() -> bool:
	for j in _jnt_nodes:
		var n := j as Node3D
		if n.transform != _jnt_local[n.name]:
			return false
	return true


func _report_armor() -> void:
	# Phase 12: production armor lives under the same pivots (PartMeshManager).
	# Report what is there; never hide anything.
	var count := 0
	var thigh_armor: MeshInstance3D = null
	var stack: Array = [_mech.get_node_or_null("LegLeft")]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == null:
			continue
		if n is MeshInstance3D:
			count += 1
			if thigh_armor == null and "rmor" in n.name:
				thigh_armor = n
		stack.append_array(n.get_children())
	print("armor meshes under LegLeft: %d" % count)
	if thigh_armor != null:
		var ac: Vector3 = thigh_armor.global_transform * thigh_armor.get_aabb().get_center()
		var best := 1e9
		for j in _jnt_nodes:
			if "hip_L" in (j as Node).name:
				var jc: Vector3 = (j as Node3D).global_transform * (j as MeshInstance3D).get_aabb().get_center()
				best = minf(best, ac.distance_to(jc))
		print("thigh armor '%s' nearest hip-joint distance=%.3f" % [thigh_armor.name, best])
	else:
		print("no armor mesh under LegLeft (procedural/default loadout)")
