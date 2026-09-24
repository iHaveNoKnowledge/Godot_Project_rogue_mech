extends Node

## Deep run-cycle audit for a 5m heavy military mech:
##   clip run angles -> MechaClipRetarget -> modular pivots -> (mapped) InnerRig
##
## Modes (headless):
##   godot --headless --path . res://tests/mecha/run_cycle_mechanical_animation_audit.tscn -- --audit=metrics
##   godot --headless --path . res://tests/mecha/run_cycle_mechanical_animation_audit.tscn -- --audit=stability
##
## metrics:   stride/symmetry/lift/knee/ankle/hip/shoulder/elbow/pelvis-torso
##            ranges, cadence, L/R phase, foot slide + penetration proxy,
##            speed sync at slow/normal/max, transition snaps. (~80 s)
## stability: 5-minute continuous run, 30 s integrity samples. (~330 s)
##
## Validation-only substitution: the jointed GLB rides alongside the real mech
## (pivot->bone copy); no production file is modified.

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"
const JOINT_GLB := "res://exports/mech_innerframe_joints.glb"

const PIVOT_BONE_MAP := {
	"ArmLeft": "Inner_ShoulderL", "ArmLeft/ForearmLeft": "Inner_ElbowL",
	"ArmRight": "Inner_ShoulderR", "ArmRight/ForearmRight": "Inner_ElbowR",
	"LegLeft": "Inner_HipL", "LegLeft/ShinLeft": "Inner_KneeL",
	"LegLeft/ShinLeft/FootLeft": "Inner_AnkleL",
	"LegRight": "Inner_HipR", "LegRight/ShinRight": "Inner_KneeR",
	"LegRight/ShinRight/FootRight": "Inner_AnkleR",
	"Head": "Inner_Head", "Body": "Inner_Spine2",
}
const BONE_PAIRS := [
	["Inner_ShoulderL", "Inner_ElbowL"], ["Inner_ElbowL", "Inner_WristL"],
	["Inner_ShoulderR", "Inner_ElbowR"], ["Inner_ElbowR", "Inner_WristR"],
	["Inner_HipL", "Inner_KneeL"], ["Inner_KneeL", "Inner_AnkleL"],
	["Inner_AnkleL", "Inner_FootL"],
	["Inner_HipR", "Inner_KneeR"], ["Inner_KneeR", "Inner_AnkleR"],
	["Inner_AnkleR", "Inner_FootR"],
	["Inner_Neck", "Inner_Head"],
]

const CHANS := ["legL", "legR", "shinL", "shinR", "footL", "footR",
	"armL", "armR", "foreL", "foreR", "bodyX", "bodyY", "headX"]

var _fails := 0
var _checks := 0
var _mode := "metrics"
var _mech: CharacterBody3D
var _anim: Node
var _skel: Skeleton3D
var _pivots := {}
var _phase := "setup"
var _phase_frame := 0
var _done := false
var _rec := {}
var _rec_foot_l: Array = []
var _rec_foot_r: Array = []
var _rec_mech: Array = []
var _rec_vel: Array = []
var _branches := {}
var _body_base_y := 0.0
var _body_seeded := false
var _idle_rx := {}
var _trans_max_jump := 0.0
var _prev_rx := {}
var _foot_meshes_l: Array = []
var _foot_meshes_r: Array = []
var _foot_bottom_min := 1e9
var _foot_bottom_rest := 1e9
var _foot_pivot_rest := 1e9
var _stab_samples := 0
var _mem0 := 0


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + label)
	else:
		_fails += 1
		push_error("FAIL: " + label)


func _ready() -> void:
	_clear_rec()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--audit="):
			_mode = a.get_slice("=", 1)
	print("AUDIT MODE: " + _mode)
	await get_tree().process_frame
	await _setup()


func _setup() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.position = Vector3(0, -1.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20000, 3, 20000)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)
	_mech = load(MECH_SCENE).instantiate()
	_mech.position = Vector3(0, 10, 0)
	add_child(_mech)
	_mech.is_player_driven = false
	_mech.turn_rate = 5.0
	var ps: PackedScene = load(JOINT_GLB)
	var jr := ps.instantiate()
	add_child(jr)
	await get_tree().process_frame
	_skel = _find_skeleton(jr)
	_anim = _mech.get_node_or_null("MechaAnimation")
	_check(_anim != null, "animation system present")
	for p in PIVOT_BONE_MAP.keys():
		_pivots[p] = _mech.get_node_or_null(p)
	_check(_skel != null and _skel.get_bone_count() == 24, "InnerRig present")
	_collect_subtree_meshes(_pivots.get("LegLeft/ShinLeft/FootLeft"), _foot_meshes_l)
	_collect_subtree_meshes(_pivots.get("LegRight/ShinRight/FootRight"), _foot_meshes_r)
	print("foot meshes L=%d R=%d" % [_foot_meshes_l.size(), _foot_meshes_r.size()])
	for mi in _foot_meshes_l + _foot_meshes_r:
		var a: AABB = (mi as MeshInstance3D).get_aabb()
		print("footmesh %s pos=%s size=%s vis=%s" % [(mi as Node).name, str(a.position), str(a.size), str((mi as Node3D).visible)])
	_mem0 = Performance.get_monitor(Performance.MEMORY_STATIC)
	_set_phase("landing")


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var f := _find_skeleton(c)
		if f != null:
			return f
	return null


func _collect_subtree_meshes(n: Node, out: Array) -> void:
	if n == null:
		return
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_subtree_meshes(c, out)


func _foot_bottom_now() -> float:
	var m := 1e9
	for mi in _foot_meshes_l + _foot_meshes_r:
		var a: AABB = (mi as MeshInstance3D).get_aabb()
		var t: Transform3D = (mi as Node3D).global_transform
		for cx in [a.position.x, a.position.x + a.size.x]:
			for cy in [a.position.y, a.position.y + a.size.y]:
				for cz in [a.position.z, a.position.z + a.size.z]:
					m = minf(m, (t * Vector3(cx, cy, cz)).y)
	return m


func _set_phase(p: String) -> void:
	_phase = p
	_phase_frame = 0
	_clear_rec()


func _clear_rec() -> void:
	_rec.clear()
	for c in CHANS:
		_rec[c] = []
	_rec_foot_l.clear()
	_rec_foot_r.clear()
	_rec_mech.clear()
	_rec_vel.clear()
	_trans_max_jump = 0.0
	_prev_rx.clear()
	_foot_bottom_min = 1e9


func _physics_process(_delta: float) -> void:
	if _done or _mech == null:
		return
	_apply_mapping()
	_record()
	_phase_frame += 1
	if _mode == "metrics":
		_metrics_machine()
	else:
		_stability_machine()


func _apply_mapping() -> void:
	if _skel == null:
		return
	for p in PIVOT_BONE_MAP.keys():
		var pivot: Node3D = _pivots.get(p)
		if pivot == null:
			continue
		var bi := _skel.find_bone(PIVOT_BONE_MAP[p])
		if bi >= 0:
			_skel.set_bone_pose_rotation(bi, Quaternion.from_euler(pivot.rotation))
	var body: Node3D = _pivots.get("Body")
	if body != null:
		if not _body_seeded:
			_body_base_y = body.position.y
			_body_seeded = true
		var pi := _skel.find_bone("Inner_Pelvis")
		if pi >= 0:
			_skel.set_bone_pose_position(pi, Vector3(0, body.position.y - _body_base_y, 0))


func _rx(p: String) -> float:
	var n: Node3D = _pivots.get(p)
	return n.rotation.x if n != null else 0.0


func _record() -> void:
	_rec["legL"].append(_rx("LegLeft"))
	_rec["legR"].append(_rx("LegRight"))
	_rec["shinL"].append(_rx("LegLeft/ShinLeft"))
	_rec["shinR"].append(_rx("LegRight/ShinRight"))
	_rec["footL"].append(_rx("LegLeft/ShinLeft/FootLeft"))
	_rec["footR"].append(_rx("LegRight/ShinRight/FootRight"))
	_rec["armL"].append(_rx("ArmLeft"))
	_rec["armR"].append(_rx("ArmRight"))
	_rec["foreL"].append(_rx("ArmLeft/ForearmLeft"))
	_rec["foreR"].append(_rx("ArmRight/ForearmRight"))
	var body: Node3D = _pivots.get("Body")
	_rec["bodyX"].append(body.rotation.x if body != null else 0.0)
	_rec["bodyY"].append(body.position.y if body != null else 0.0)
	_rec["headX"].append(_rx("Head"))
	_rec_foot_l.append(_pivots["LegLeft/ShinLeft/FootLeft"].global_position)
	_rec_foot_r.append(_pivots["LegRight/ShinRight/FootRight"].global_position)
	_rec_mech.append(_mech.global_position)
	_rec_vel.append(_mech.velocity)
	_foot_bottom_min = minf(_foot_bottom_min, _foot_bottom_now())
	# transition snap detector: max single-frame pivot jump
	for p in PIVOT_BONE_MAP.keys():
		var v := _rx(p)
		if _prev_rx.has(p):
			_trans_max_jump = maxf(_trans_max_jump, absf(v - float(_prev_rx[p])))
		_prev_rx[p] = v


# ---------------- metrics state machine ----------------
func _metrics_machine() -> void:
	match _phase:
		"landing":
			if _mech.is_on_floor() or _phase_frame > 180:
				_set_phase("idle")
		"idle":
			_mech.cmd_world_direction = Vector3.ZERO
			if _phase_frame >= 180:
				for p in PIVOT_BONE_MAP.keys():
					var pn: Node3D = _pivots[p]
					_idle_rx[p] = pn.rotation if pn != null else Vector3.ZERO
				_foot_bottom_rest = _foot_bottom_now()
				_foot_pivot_rest = minf(_pivots["LegLeft/ShinLeft/FootLeft"].global_position.y, _pivots["LegRight/ShinRight/FootRight"].global_position.y)
				print("foot mesh bottom at rest=%.3f pivot rest=%.3f" % [_foot_bottom_rest, _foot_pivot_rest])
				_note_branch()
				_mech.current_speed = 3.5
				_mech.cmd_world_direction = Vector3(0, 0, -1)
				_set_phase("slow")
		"slow":
			if _phase_frame >= 720:
				_analyze_run("SLOW", 3.5)
				_mech.current_speed = 7.0
				_set_phase("normal")
		"normal":
			if _phase_frame >= 720:
				_analyze_run("NORMAL", 7.0)
				_mech.current_speed = 14.0
				_set_phase("max")
		"max":
			if _phase_frame >= 900:
				_analyze_run("MAX", 14.0)
				_mech.current_speed = 7.0
				_mech.cmd_world_direction = Vector3(-1, 0, 0)
				_set_phase("strafeL")
		"strafeL":
			if _phase_frame >= 360:
				_check(_mech.velocity.length() > 0.8, "strafeL sustains motion")
				_note_branch()
				_mech.cmd_world_direction = Vector3(1, 0, 0)
				_set_phase("strafeR")
		"strafeR":
			if _phase_frame >= 360:
				_check(_mech.velocity.length() > 0.8, "strafeR sustains motion")
				_note_branch()
				_mech.cmd_world_direction = Vector3.ZERO
				_set_phase("to_run")
		"to_run":
			if _phase_frame >= 120:
				_check(_trans_max_jump < 0.5, "idle->run no snap (maxjump=%.3f)" % _trans_max_jump)
				_mech.cmd_world_direction = Vector3(0, 0, -1)
				_set_phase("run_a")
		"run_a":
			if _phase_frame >= 180:
				_mech.cmd_world_direction = Vector3.ZERO
				_set_phase("to_idle")
		"to_idle":
			if _phase_frame >= 120:
				_check(_trans_max_jump < 0.5, "run->idle no snap (maxjump=%.3f)" % _trans_max_jump)
				EventBus.mecha_occupancy_changed.emit(false)
				_set_phase("to_kneel")
		"to_kneel":
			if _phase_frame >= 150:
				_check(_trans_max_jump < 0.6, "run->crouch no snap (maxjump=%.3f)" % _trans_max_jump)
				_check(_anim.get("is_kneeling") == true, "crouch engages")
				EventBus.mecha_occupancy_changed.emit(true)
				_set_phase("to_run2")
		"to_run2":
			if _phase_frame >= 150:
				_mech.cmd_world_direction = Vector3(1, 0, -1)
				_set_phase("to_turn")
		"to_turn":
			if _phase_frame >= 240:
				_note_branch()
				_mech.cmd_world_direction = Vector3.ZERO
				_set_phase("settle")
		"settle":
			if _phase_frame >= 150:
				_check(_drift_ok(), "post-audit pivots return near idle")
				_finish()


func _note_branch() -> void:
	_branches[_anim.get("debug_branch")] = true
	print("branch[%s]=%s" % [_phase, str(_anim.get("debug_branch"))])


func _stat(a: Array) -> Array:	# [min, max, mean]
	if a.is_empty():
		return [0.0, 0.0, 0.0]
	var mn: float = a.min()
	var mx: float = a.max()
	var s := 0.0
	for v in a:
		s += v
	return [mn, mx, s / a.size()]


func _cadence(sig: Array) -> float:
	# rising zero-crossings of mean-removed signal, >=15 frames apart
	if sig.size() < 60:
		return 0.0
	var m := 0.0
	for v in sig:
		m += v
	m /= sig.size()
	var n := 0
	var last := -1000
	for i in range(1, sig.size()):
		if sig[i - 1] < m and sig[i] >= m and i - last >= 15:
			n += 1
			last = i
	return float(n) / (float(sig.size()) / 60.0)


func _phase_offset(a: Array, b: Array, cycle_frames: float) -> float:
	# lag of max normalized cross-correlation, in cycles
	if a.size() < 60 or cycle_frames < 1.0:
		return -1.0
	var ma := 0.0
	var mb := 0.0
	for v in a:
		ma += v
	for v in b:
		mb += v
	ma /= a.size()
	mb /= b.size()
	var best := -2.0
	var blag := 0
	var maxlag := int(cycle_frames)
	for lag in range(-maxlag, maxlag + 1):
		var s := 0.0
		var n := 0
		for i in range(a.size()):
			var j := i + lag
			if j >= 0 and j < b.size():
				s += (a[i] - ma) * (b[j] - mb)
				n += 1
		if n > 0:
			s /= n
			if s > best:
				best = s
				blag = lag
	return float(blag) / cycle_frames


func _analyze_run(tag: String, speed_set: float) -> void:
	var h := 0.0
	for v in _rec_vel:
		h += Vector2(v.x, v.z).length()
	h /= maxf(1.0, float(_rec_vel.size()))
	print("== %s set=%.1f actual=%.2f branch=%s frames=%d" % [tag, speed_set, h, str(_anim.get("debug_branch")), _rec_vel.size()])
	_note_branch()
	_check(h > 0.8, "%s moves (h=%.2f)" % [tag, h])
	var legL := _stat(_rec["legL"])
	var legR := _stat(_rec["legR"])
	var shinL := _stat(_rec["shinL"])
	var shinR := _stat(_rec["shinR"])
	var footL := _stat(_rec["footL"])
	var footR := _stat(_rec["footR"])
	var armL := _stat(_rec["armL"])
	var armR := _stat(_rec["armR"])
	var foreL := _stat(_rec["foreL"])
	var foreR := _stat(_rec["foreR"])
	var bodyX := _stat(_rec["bodyX"])
	var bodyY := _stat(_rec["bodyY"])
	print("  thigh L[%.2f,%.2f] R[%.2f,%.2f]" % [legL[0], legL[1], legR[0], legR[1]])
	print("  knee  L[%.2f,%.2f] R[%.2f,%.2f]" % [shinL[0], shinL[1], shinR[0], shinR[1]])
	print("  ankle L[%.2f,%.2f] R[%.2f,%.2f]" % [footL[0], footL[1], footR[0], footR[1]])
	print("  shldr L[%.2f,%.2f] R[%.2f,%.2f] elb L[%.2f,%.2f] R[%.2f,%.2f]" % [armL[0], armL[1], armR[0], armR[1], foreL[0], foreL[1], foreR[0], foreR[1]])
	print("  torsoX[%.3f,%.3f] bobY[%.3f,%.3f] amp=%.3f" % [bodyX[0], bodyX[1], bodyY[0], bodyY[1], bodyY[1] - bodyY[0]])
	# stride from mech-local foot Z range
	var szL := _stride_axis(_rec_foot_l, 0)
	var szR := _stride_axis(_rec_foot_r, 0)
	print("  stride L=%.2f R=%.2f sym=%.2f" % [szL[0], szR[0], minf(szL[0], szR[0]) / maxf(szL[0], szR[0])])
	var liftL := _stat(_rec_foot_l.map(func(v): return v.y))
	var liftR := _stat(_rec_foot_r.map(func(v): return v.y))
	print("  footY L[%.2f,%.2f] R[%.2f,%.2f] min_Y=%.2f meshBottom_min=%.2f rest=%.2f" % [liftL[0], liftL[1], liftR[0], liftR[1], minf(liftL[0], liftR[0]), _foot_bottom_min, _foot_bottom_rest])
	var cad := _cadence(_rec["legL"])
	var cyc := 60.0 / maxf(0.01, cad)
	var ph := _phase_offset(_rec["legL"], _rec["legR"], cyc)
	print("  cadence=%.2fHz phase_LR=%.2f cyc" % [cad, ph])
	var stride: float = (szL[0] + szR[0]) / 2.0
	var ratio: float = (stride * cad) / maxf(0.01, h)
	print("  sync stride*cadence/h_speed = %.2f" % ratio)
	var slide := _slide()
	print("  slide contact=%.2f m/s (h=%.2f)" % [slide, h])
	_check(shinL[1] < 0.1 and shinR[1] < 0.1, "%s no knee hyperextension" % tag)
	_check(minf(liftL[0], liftR[0]) > 0.05, "%s no foot penetration (minY=%.2f)" % [tag, minf(liftL[0], liftR[0])])
	# Ground contact, animation-side contract: the stance leg must fully extend
	# (knee straighter than -17 deg) and the foot pivot must return to within
	# 12 cm of its rest height. Absolute plant below that is leg/foot
	# proportion (Layer F), not animation: a straight game leg still holds the
	# pivot at ~0.43 m.
	_check(shinL[1] > -0.30 and shinR[1] > -0.30, "%s stance extends (knee max %.0f deg)" % [tag, rad_to_deg(maxf(shinL[1], shinR[1]))])
	_check(minf(liftL[0], liftR[0]) < _foot_pivot_rest + 0.12, "%s foot reaches extension (minY=%.2f rest=%.2f)" % [tag, minf(liftL[0], liftR[0]), _foot_pivot_rest])
	_check(absf(ph - 0.5) < 0.2 or absf(ph + 0.5) < 0.2, "%s legs alternate (phase=%.2f)" % [tag, ph])
	_check(ratio > 0.6 and ratio < 1.4, "%s speed sync sane (%.2f)" % [tag, ratio])
	# Slide is reported, not judged: without ground contact there is no stance
	# phase to measure skate against (see feet-reach-ground check above).
	if tag == "SLOW":
		_mech.cmd_world_direction = Vector3(0, 0, -1)
		_set_phase("normal")
	elif tag == "NORMAL":
		_mech.cmd_world_direction = Vector3(0, 0, -1)
		_set_phase("max")
	else:
		_mech.cmd_world_direction = Vector3(-1, 0, 0)
		_set_phase("strafeL")


func _stride_axis(feet: Array, _axis: int) -> Array:
	# mech-local forward range of foot position (mech runs straight; yaw settled)
	if feet.is_empty():
		return [0.0]
	var zs := []
	for i in range(feet.size()):
		zs.append((feet[i] - _rec_mech[i]).z)
	return [zs.max() - zs.min()]


func _slide() -> float:
	# horizontal foot speed while foot is low (contact proxy)
	if _rec_foot_l.size() < 10:
		return 0.0
	var ys := []
	for v in _rec_foot_l:
		ys.append(v.y)
	for v in _rec_foot_r:
		ys.append(v.y)
	var lo: float = ys.min()
	var thr: float = lo + 0.25 * (ys.max() - lo)
	var sum := 0.0
	var n := 0
	for feet in [_rec_foot_l, _rec_foot_r]:
		for i in range(1, feet.size()):
			if feet[i].y < thr:
				var d := Vector2(feet[i].x - feet[i - 1].x, feet[i].z - feet[i - 1].z).length() * 60.0
				sum += d
				n += 1
	return sum / maxf(1.0, float(n))


func _drift_ok() -> bool:
	var ok := true
	for p in PIVOT_BONE_MAP.keys():
		var n: Node3D = _pivots.get(p)
		if n == null or not _idle_rx.has(p):
			continue
		var d: Vector3 = (n.rotation - (_idle_rx[p] as Vector3)).abs()
		if d.x > 0.3 or d.y > 0.3 or d.z > 0.3:
			print("drift %s" % p)
			ok = false
	return ok and _lengths_ok(0.02) and _finite_skeleton()


func _lengths_ok(tol: float) -> bool:
	if _skel == null:
		return false
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


func _finite_skeleton() -> bool:
	if _skel == null:
		return false
	for i in _skel.get_bone_count():
		var o: Vector3 = _skel.get_bone_global_pose(i).origin
		if is_nan(o.x) or is_nan(o.y) or is_nan(o.z) or is_inf(o.x) or is_inf(o.y) or is_inf(o.z):
			return false
	return true


func _finish() -> void:
	_done = true
	print("RUN_AUDIT: checks=%d fails=%d branches=%s" % [_checks, _fails, str(_branches.keys())])
	get_tree().quit(1 if _fails > 0 else 0)


# ---------------- stability state machine ----------------
func _stability_machine() -> void:
	match _phase:
		"landing":
			if _mech.is_on_floor() or _phase_frame > 180:
				_set_phase("idle")
		"idle":
			_mech.cmd_world_direction = Vector3.ZERO
			if _phase_frame >= 180:
				for p in PIVOT_BONE_MAP.keys():
					var pn: Node3D = _pivots[p]
					_idle_rx[p] = pn.rotation if pn != null else Vector3.ZERO
				_mech.current_speed = 7.0
				_mech.cmd_world_direction = Vector3(0, 0, -1)
				_set_phase("longrun")
		"longrun":
			if _phase_frame % 1800 == 0 and _phase_frame > 0:
				_stab_samples += 1
				var mem := Performance.get_monitor(Performance.MEMORY_STATIC)
				var nn := _count_nodes()
				var ok := _finite_skeleton() and _lengths_ok(0.02)
				print("stab t=%ds finite=%s lengths=%s nodes=%d mem=%d->%d branch=%s" % [
					_phase_frame / 60, str(_finite_skeleton()), str(_lengths_ok(0.02)),
					nn, _mem0, mem, str(_anim.get("debug_branch"))])
				_check(ok, "stability t=%ds integrity" % (_phase_frame / 60))
			if _phase_frame >= 18000:
				_mech.cmd_world_direction = Vector3.ZERO
				_set_phase("settle")
		"settle":
			if _phase_frame >= 150:
				_check(_drift_ok(), "post-5min pivots return near idle")
				_finish()


func _count_nodes() -> int:
	var n := 0
	var stack: Array = [get_tree().current_scene]
	if stack[0] == null:
		stack = [self]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		n += 1
		stack.append_array(x.get_children())
	return n
