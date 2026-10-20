extends Node3D
## ISOLATED G2d ASSET-GEOMETRY PROBE (E2-F2 Phase 12, separately approved).
##
## Preview-only test of a small wanzer lower-leg geometry correction. Method:
## mesh.duplicate() + per-vertex clamp on the IN-MEMORY copy, assigned to the
## isolated preview instance only. The imported .glb on disk is NEVER written
## (no ResourceSaver call anywhere; verified by post-run git status showing
## zero asset modifications). Clamp flattens (no vertex deletion -> no holes);
## clamped verts get explicit DOWN normals for a clean sole read.
##
## Trim planes are DERIVED, not arbitrary: ankle position transformed into the
## armor mesh-node local space (convention verified in-log: ankle_local.y must
## read approx -1.29, i.e. the documented Foot offset, else the candidate
## aborts). G2d-1 keeps armor 0.045 above the measured frame-sole depth
## (0.345); G2d-2 matches frame-sole depth. Baseline G2a untrimmed.
## Same G2a pose/settle/camera/floor/overlay conventions as the G2 scripts.
## OUTPUT ISOLATION: ONLY user://posture_abc/phase12/. Fail-closed.

const OUT_DIR := "user://posture_abc/phase12"
const TOL := 0.02
const PEN_FAIL := -0.02
const FRAME_SOLE_DEPTH := 0.345 # measured ankle->sole (Phases 6-8)

const LOADOUT := {
	"head": {"frame": {"id": "frame_head_01", "equipped": true}, "armor": {"id": "wanzer_local_head_001", "equipped": true, "path": "res://resources/mech/parts/head/wanzer_local_001.tres", "slot": "head"}},
	"body": {"frame": {"id": "frame_body_01", "equipped": true}, "armor": {"id": "wanzer_local_body_001", "equipped": true, "path": "res://resources/mech/parts/body/wanzer_local_001.tres", "slot": "body"}},
	"arm_left": {"frame": {"id": "frame_arm_left_01", "equipped": true}, "armor": {"id": "wanzer_local_arm_left_001", "equipped": true, "path": "res://resources/mech/parts/arm_left/wanzer_local_001.tres", "slot": "arm_left"}},
	"arm_right": {"frame": {"id": "frame_arm_right_01", "equipped": true}, "armor": {"id": "wanzer_local_arm_right_001", "equipped": true, "path": "res://resources/mech/parts/arm_right/wanzer_local_001.tres", "slot": "arm_right"}},
	"leg_left": {"frame": {"id": "frame_leg_left_01", "equipped": true}, "armor": {"id": "wanzer_local_leg_left_001", "equipped": true, "path": "res://resources/mech/parts/leg_left/wanzer_local_001.tres", "slot": "leg_left"}},
	"leg_right": {"frame": {"id": "frame_leg_right_01", "equipped": true}, "armor": {"id": "wanzer_local_leg_right_001", "equipped": true, "path": "res://resources/mech/parts/leg_right/wanzer_local_001.tres", "slot": "leg_right"}},
}

# G2a pose values verbatim (thigh 9 / shin -9, yaw/roll, torso/arms C-hybrid).
const G2A_POSE := {
	"Body": Vector3(-5, 0, 0), "Head": Vector3(-2.5, 0, 0),
	"ArmLeft": Vector3(15, 5, -28), "ArmLeft/ForearmLeft": Vector3(32, 0, 12),
	"ArmRight": Vector3(15, -5, 28), "ArmRight/ForearmRight": Vector3(32, 0, -12),
	"LegLeft": Vector3(9, 10, -10), "LegLeft/ShinLeft": Vector3(-9, 0, 6),
	"LegRight": Vector3(9, -10, 10), "LegRight/ShinRight": Vector3(-9, 0, -6),
	"Body/drop": Vector3(0, -0.03, 0),
}

const _BUCKETS := {
	"Head": "head", "Body": "body",
	"ArmLeft": "shoulder_l", "ArmRight": "shoulder_r",
	"ForearmLeft": "forearm_l", "ForearmRight": "forearm_r",
	"LegLeft": "thigh_l", "LegRight": "thigh_r",
	"ShinLeft": "shin_l", "ShinRight": "shin_r",
	"FootLeft": "foot_l", "FootRight": "foot_r",
}

const VIEW_PRESETS := {
	"front": {"az": 0.0, "el": 6.0},
	"side": {"az": 90.0, "el": 6.0},
	"3q": {"az": 38.0, "el": 14.0},
}

var _cam: Camera3D
var _overlay: Node3D
var _failed := false
var _saved: Array[String] = []
var _results := {}
var _union := AABB()
var _union_ready := false


func _ready() -> void:
	var out := DirAccess.open("user://")
	if out == null or not out.dir_exists("posture_abc"):
		printerr("[G2d] user://posture_abc missing (fail-closed, no repo fallback)")
		get_tree().quit(1)
		return
	if not out.dir_exists("posture_abc/phase12") and out.make_dir("posture_abc/phase12") != OK:
		printerr("[G2d] cannot create user://posture_abc/phase12 (fail-closed)")
		get_tree().quit(1)
		return
	print("[G2d] output dir: " + OS.get_user_data_dir() + "/posture_abc/phase12")
	_setup_stage()
	_overlay = Node3D.new()
	_overlay.name = "G2dOverlay"
	add_child(_overlay)

	# One FRESH isolated instance per candidate: trims can never leak across
	# candidates and no restore logic is needed. Poses/settle identical.
	var mechas := {}
	for tag in ["BASE", "G2d-1", "G2d-2"]:
		var mecha := await _assemble_frozen()
		_apply_g2a_pose(mecha)
		await _settle_frame(mecha, tag)
		if tag == "G2d-1":
			_trim_to_floor(mecha, tag, 0.005)
		elif tag == "G2d-2":
			_trim_to_floor(mecha, tag, 0.06)
		_measure_all(mecha, tag)
		mechas[tag] = mecha
	var union: AABB = _union
	_frame_shared(union)
	for tag in ["BASE", "G2d-1", "G2d-2"]:
		var mecha: Node3D = mechas[tag]
		_set_layer_visibility(mecha, true, true)
		_clear_overlay()
		await get_tree().process_frame
		for v in ["front", "side", "3q"]:
			_aim_camera(union, v)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			_save_capture("G2d_%s_%s.png" % [tag, v])
		await _capture_foot(mecha, tag, "left")
		await _capture_foot(mecha, tag, "right")
		await _capture_chain(mecha, tag, "")
		_set_layer_visibility(mecha, true, false)
		await get_tree().process_frame
		await _capture_chain(mecha, tag, "_armor")
		_set_layer_visibility(mecha, false, true)
		await get_tree().process_frame
		await _capture_chain(mecha, tag, "_frame")
		_set_layer_visibility(mecha, true, true)
	_compose_contact_sheet()
	if _failed:
		printerr("[G2d] failures occurred (see above)")
		get_tree().quit(1)
	else:
		print("[G2d] ALL_G2D_DONE files=%d" % _saved.size())
		get_tree().quit(0)


func _assemble_frozen() -> Node3D:
	var base_res: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha := base_res.instantiate() as Node3D
	mecha.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(mecha)
	await get_tree().process_frame
	await get_tree().process_frame
	var pm := mecha.get_node_or_null("PartMeshManager")
	pm.refresh_from_loadout(LOADOUT)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[G2d] assembled frozen, root=%s scale=%s" % [_v3(mecha.global_position), _v3(mecha.scale)])
	return mecha


func _find_armor_mesh_node(mecha: Node3D, side: String) -> MeshInstance3D:
	var shin := mecha.get_node_or_null("LegLeft/ShinLeft" if side == "left" else "LegRight/ShinRight") as Node3D
	if shin == null:
		return null
	var found := shin.find_child("W_leg_" + ("left" if side == "left" else "right") + "_lower", true, true)
	if found is MeshInstance3D and (found as MeshInstance3D).mesh != null:
		return found as MeshInstance3D
	# Fallback: largest mesh under the shin ArmorMesh container.
	var cont := shin.get_node_or_null("ArmorMesh") as Node3D
	var best: MeshInstance3D = null
	var best_n := 0
	if cont != null:
		var stack: Array[Node] = [cont]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var c: int = (n as MeshInstance3D).mesh.get_surface_count()
				if c > 0:
					var mi := n as MeshInstance3D
					var total := 0
					for s in range(mi.mesh.get_surface_count()):
						total += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
					if total > best_n:
						best_n = total
						best = mi
			for ch in n.get_children():
				stack.append(ch)
	return best


# SUPERSEDED (mesh-local trim plane proven ineffective; kept for audit trail).
func _run_candidate(mecha: Node3D, tag: String, keep_depth: float) -> void:
	# keep_depth < 0 means no trim (baseline). Else: duplicate the SHARED mesh
	# fresh (never trim a trim) and clamp vertices below ankle-depth plane.
	_apply_g2a_pose(mecha)
	if keep_depth >= 0.0:
		for side in ["left", "right"]:
			var mi := _find_armor_mesh_node(mecha, side)
			if mi == null:
				printerr("[G2d] %s: armor mesh node not found (%s)" % [tag, side])
				_failed = true
				return
			var ankle: Vector3 = (mecha.get_node_or_null("LegLeft/ShinLeft/FootLeft") as Node3D).global_position if side == "left" else (mecha.get_node_or_null("LegRight/ShinRight/FootRight") as Node3D).global_position
			if mi.mesh.resource_path != "":
				print("[G2d] %s: mesh resource_path=%s (duplicating, source untouched)" % [tag, mi.mesh.resource_path])
			var ankle_local: Vector3 = mi.global_transform.affine_inverse() * ankle
			print("[G2d] %s %s ankle_in_meshlocal=%s (expect y approx -1.29)" % [tag, side, _v3(ankle_local)])
			if absf(ankle_local.y + 1.291) > 0.05:
				printerr("[G2d] %s: mesh-local convention NOT confirmed (%.3f); abort trim" % [tag, ankle_local.y])
				_failed = true
				return
			var moved := _trim_mesh_copy(mi, ankle_local.y - keep_depth, tag, side)
			if moved < 0:
				_failed = true
				return
	print("[G2d] %s candidate ready (trim=%s)" % [tag, ("none" if keep_depth < 0.0 else "ankle-%.3f" % keep_depth)])


# SUPERSEDED by _trim_to_floor (world-horizontal clamp); kept for audit trail.
func _trim_mesh_copy(mi: MeshInstance3D, plane_y: float, tag: String, side: String) -> int:
	# Always duplicate from the PRISTINE shared mesh (stored on first trim),
	# so deeper trims never stack on already-clamped duplicates.
	if not mi.has_meta("g2d_pristine"):
		if not (mi.mesh is ArrayMesh):
			printerr("[G2d] %s: mesh is not ArrayMesh, cannot trim safely" % tag)
			return -1
		mi.set_meta("g2d_pristine", mi.mesh)
		print("[G2d] %s %s: pristine shared mesh stored (source file untouched)" % [tag, side])
	var dup := (mi.get_meta("g2d_pristine") as ArrayMesh).duplicate()
	var total_moved := 0
	for s in range(dup.get_surface_count()):
		var mdt := MeshDataTool.new()
		if mdt.create_from_surface(dup, s) != OK:
			printerr("[G2d] %s: MeshDataTool failed surface %d" % [tag, s])
			return -1
		var moved := 0
		for v in range(mdt.get_vertex_count()):
			var p: Vector3 = mdt.get_vertex(v)
			if p.y < plane_y:
				p.y = plane_y
				mdt.set_vertex(v, p)
				mdt.set_vertex_normal(v, Vector3.DOWN)
				moved += 1
		if moved > 0:
			mdt.commit_to_surface(dup)
			total_moved += moved
	mi.mesh = dup
	mi.set_meta("g2d_trimmed", true)
	var post: AABB = (mi.mesh as ArrayMesh).get_aabb()
	print("[G2d] %s %s: post-assign surfaces=%d aabb_min=%s (proves commit persistence)" % [tag, side, (mi.mesh as ArrayMesh).get_surface_count(), _v3(post.position)])
	print("[G2d] %s %s: clamped %d verts to y=%.3f on in-memory duplicate (shared resource untouched)" % [tag, side, total_moved, plane_y])
	return total_moved


func _settle_frame(mecha: Node3D, tag: String) -> void:
	# Frame-anchored settle (differs DELIBERATELY from the G2c min-policy:
	# here the trim — not the hips — owns armor clearance, so hips serve
	# frame contact only). Order matters: trim runs AFTER this.
	for i in range(4):
		await get_tree().process_frame
		var fs: float = _frame_sole(mecha)
		var am: float = _armor_min_all(mecha)
		print("[G2d] %s settle iter %d frame_sole=%.3f armor_min=%.3f" % [tag, i, fs, am])
		# abs(): leg shifts are mecha-local while soles read world (x1.15),
		# so steps overshoot and converge by alternating sign — stop only
		# inside the band, never on a penetrating overshoot.
		if absf(fs) <= TOL:
			break
		for path in ["LegLeft", "LegRight"]:
			var n := mecha.get_node_or_null(path) as Node3D
			n.position.y -= fs
		_level_ankles(mecha)


func _trim_to_floor(mecha: Node3D, tag: String, target_world_y: float) -> void:
	# World-horizontal clamp on an in-memory duplicate (shared .glb untouched):
	# every vertex of the lower-leg armor whose WORLD y sits below the target
	# is lifted to it (flatten, never delete -> no holes). Valid only for the
	# settled pose it was computed in (documented per candidate).
	for side in ["left", "right"]:
		var mi := _find_armor_mesh_node(mecha, side)
		if mi == null or not (mi.mesh is ArrayMesh):
			printerr("[G2d] %s: armor mesh unavailable (%s)" % [tag, side])
			_failed = true
			return
		var dup := (mi.mesh as ArrayMesh).duplicate()
		var inv: Transform3D = mi.global_transform.affine_inverse()
		var down_local: Vector3 = (inv.basis * Vector3.DOWN).normalized()
		# NOTE: MeshDataTool.commit_to_surface APPENDS (verified: 2->3
		# surfaces, originals untouched), so commit into a FRESH mesh.
		var out := ArrayMesh.new()
		var total_moved := 0
		for s in range(dup.get_surface_count()):
			var mdt := MeshDataTool.new()
			if mdt.create_from_surface(dup, s) != OK:
				printerr("[G2d] %s: MeshDataTool failed surface %d" % [tag, s])
				_failed = true
				return
			var moved := 0
			for v in range(mdt.get_vertex_count()):
				var vw: Vector3 = mi.global_transform * mdt.get_vertex(v)
				if vw.y < target_world_y:
					vw.y = target_world_y
					mdt.set_vertex(v, inv * vw)
					mdt.set_vertex_normal(v, down_local)
					moved += 1
			mdt.commit_to_surface(out)
			out.surface_set_material(out.get_surface_count() - 1, dup.surface_get_material(s))
			total_moved += moved
		mi.mesh = out
		mi.set_meta("g2d_trimmed", true)
		var post: AABB = (mi.mesh as ArrayMesh).get_aabb()
		print("[G2d] %s %s: lifted %d verts to world y=%.3f on in-memory duplicate" % [tag, side, total_moved, target_world_y])
		print("[G2d] %s %s: node=%s post_surfaces=%d post_aabb_min_local=%s" % [tag, side, str(mi.get_path()), (mi.mesh as ArrayMesh).get_surface_count(), _v3(post.position)])


func _apply_g2a_pose(mecha: Node3D) -> void:
	var rest: Dictionary = FrameVariantData.STANDARD_REST
	for path in ["LegLeft", "LegRight", "LegLeft/ShinLeft", "LegRight/ShinRight"]:
		(mecha.get_node_or_null(path) as Node3D).position = rest[path]
	var table := {
		"Body": Vector3(-5, 0, 0), "Head": Vector3(-2.5, 0, 0),
		"ArmLeft": Vector3(15, 5, -28), "ArmLeft/ForearmLeft": Vector3(32, 0, 12),
		"ArmRight": Vector3(15, -5, 28), "ArmRight/ForearmRight": Vector3(32, 0, -12),
		"LegLeft": Vector3(9, 10, -10), "LegLeft/ShinLeft": Vector3(-9, 0, 6),
		"LegRight": Vector3(9, -10, 10), "LegRight/ShinRight": Vector3(-9, 0, -6),
		"Body/drop": Vector3(0, -0.03, 0),
	}
	var body := mecha.get_node_or_null("Body") as Node3D
	for path in table:
		if String(path) == "Body/drop":
			continue
		var n := mecha.get_node_or_null(String(path)) as Node3D
		var deg: Vector3 = table[path]
		n.rotation = Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z))
	body.position.y = (rest["Body"] as Vector3).y + (table["Body/drop"] as Vector3).y
	var head := mecha.get_node_or_null("Head") as Node3D
	head.position = body.position + MechaRig.HEAD_COLLAR_LOCAL.rotated(Vector3.RIGHT, body.rotation.x)
	_level_ankles(mecha)


# _rerun_for_capture removed (per-instance flow needs no recap); captures run
# on the same instance right after measurement.


func _level_ankles(mecha: Node3D) -> void:
	for side in [["LegLeft", "LegLeft/ShinLeft", "LegLeft/ShinLeft/FootLeft"], ["LegRight", "LegRight/ShinRight", "LegRight/ShinRight/FootRight"]]:
		var leg := mecha.get_node_or_null(side[0]) as Node3D
		var shin := mecha.get_node_or_null(side[1]) as Node3D
		var foot := mecha.get_node_or_null(side[2]) as Node3D
		if leg == null or shin == null or foot == null:
			continue
		var comp: Vector2 = MechaFootIK.ankle_compensation(leg.rotation.x, shin.rotation.x, leg.rotation.z, shin.rotation.z)
		foot.rotation = Vector3(comp.x, 0.0, comp.y)


func _frame_sole(mecha: Node3D) -> float:
	var fb := _bucket_aabb(mecha, "foot_l")
	return fb.position.y if fb.size.length_squared() > 0.0 else NAN


func _armor_min_all(mecha: Node3D) -> float:
	var worst := 999.0
	for side in ["LegLeft", "LegRight"]:
		var shin_name := "ShinLeft" if side == "LegLeft" else "ShinRight"
		var stack: Array[Node] = [mecha.get_node_or_null(side + "/" + shin_name)]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
				var mi := n as MeshInstance3D
				var b: AABB = mi.global_transform * mi.mesh.get_aabb()
				worst = minf(worst, b.position.y)
			for c in n.get_children():
				stack.append(c)
	return worst


# (Duplicate _settle_frame removed here; canonical definition lives above.)


func _dump_lowest_meshes(mecha: Node3D, tag: String) -> void:
	var rows: Array = []
	for side in ["LegLeft", "LegRight"]:
		var stack: Array[Node] = [mecha.get_node_or_null(side)]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
				var mi := n as MeshInstance3D
				var b: AABB = mi.global_transform * mi.mesh.get_aabb()
				rows.append([b.position.y, str(mi.get_path())])
			for c in n.get_children():
				stack.append(c)
	rows.sort()
	for i in range(mini(6, rows.size())):
		print("[G2d] %s lowestmesh[%d] y=%.3f %s" % [tag, i, rows[i][0], rows[i][1]])


func _measure_all(mecha: Node3D, tag: String) -> void:
	var hip := (mecha.get_node_or_null("LegLeft") as Node3D).global_position
	var knee := (mecha.get_node_or_null("LegLeft/ShinLeft") as Node3D).global_position
	var ankle := (mecha.get_node_or_null("LegLeft/ShinLeft/FootLeft") as Node3D).global_position
	var fl := _bucket_aabb(mecha, "foot_l")
	var fr := _bucket_aabb(mecha, "foot_r")
	var am: float = _armor_min_all(mecha)
	var head := mecha.get_node_or_null("Head") as Node3D
	var body := mecha.get_node_or_null("Body") as Node3D
	var collar: Vector3 = body.position + MechaRig.HEAD_COLLAR_LOCAL.rotated(Vector3.RIGHT, body.rotation.x)
	print("[G2d] %s frame L=%.3f R=%.3f armor_min=%.3f ankle=%s collar=%.4f root=%.4f sil_min=%.3f" % [tag, fl.position.y if fl.size.length_squared() > 0.0 else NAN, fr.position.y if fr.size.length_squared() > 0.0 else NAN, am, _v3(ankle), (head.position - collar).length(), mecha.global_position.y, _silhouette_aabb(mecha).position.y])
	if _union_ready:
		_union = _union.merge(_silhouette_aabb(mecha))
	else:
		_union = _silhouette_aabb(mecha)
		_union_ready = true
	_dump_lowest_meshes(mecha, tag)


# --- overlay + capture + stage helpers (proven pattern, small labels)
func _marker_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.0
	m.no_depth_test = true
	return m


func _add_marker(pos: Vector3, color: Color, r: float = 0.035) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	mi.mesh = s
	mi.material_override = _marker_mat(color)
	mi.position = pos
	_overlay.add_child(mi)


func _add_label(text: String, pos: Vector3, pixel: float = 0.004) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = 48
	l.pixel_size = pixel
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = Color(1, 1, 1)
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0)
	_overlay.add_child(l)


func _clear_overlay() -> void:
	for c in _overlay.get_children():
		_overlay.remove_child(c)
		c.queue_free()


func _bucket_aabb(mecha: Node, bucket: String) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [mecha]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
			var mi := n as MeshInstance3D
			var tag := ""
			var anc := mi.get_parent()
			while anc != null:
				if _BUCKETS.has(String(anc.name)):
					tag = _BUCKETS[String(anc.name)]
					break
				anc = anc.get_parent()
			if tag == bucket:
				var b: AABB = mi.global_transform * mi.mesh.get_aabb()
				if first:
					box = b
					first = false
				else:
					box = box.merge(b)
		for c in n.get_children():
			stack.append(c)
	return box


func _silhouette_aabb(mecha: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [mecha]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
			var mi := n as MeshInstance3D
			var b: AABB = mi.global_transform * mi.mesh.get_aabb()
			if first:
				box = b
				first = false
			else:
				box = box.merge(b)
		for c in n.get_children():
			stack.append(c)
	return box


func _set_layer_visibility(mecha: Node3D, armor: bool, frame: bool) -> void:
	var stack: Array[Node] = [mecha]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var p := n.get_parent()
			var pname := String(p.name) if p != null else ""
			if pname == "ArmorMesh":
				(n as MeshInstance3D).visible = armor
			elif pname == "FrameMesh":
				(n as MeshInstance3D).visible = frame
		for c in n.get_children():
			stack.append(c)


func _capture_foot(mecha: Node3D, tag: String, side: String) -> void:
	_clear_overlay()
	var foot_b := "foot_l" if side == "left" else "foot_r"
	var shin_b := "shin_l" if side == "left" else "shin_r"
	var fb := _bucket_aabb(mecha, foot_b)
	var sb := _bucket_aabb(mecha, shin_b)
	var ankle: Vector3 = (mecha.get_node_or_null("LegLeft/ShinLeft/FootLeft") as Node3D).global_position if side == "left" else (mecha.get_node_or_null("LegRight/ShinRight/FootRight") as Node3D).global_position
	var known := fb.size.length_squared() > 0.0
	var sole: float = fb.position.y if known else NAN
	var fc: Vector3 = fb.get_center() if known else ankle
	var strip := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.2, 0.012, 0.5)
	strip.mesh = bm
	strip.material_override = _marker_mat(Color(1.0, 0.45, 0.0))
	strip.position = Vector3(fc.x, 0.006, fc.z)
	_overlay.add_child(strip)
	_add_marker(ankle, Color(0.1, 1.0, 0.2))
	_add_marker(Vector3(fc.x, sb.position.y, fc.z), Color(1.0, 1.0, 1.0), 0.025)
	if known:
		_add_marker(Vector3(fc.x, sole, fc.z), Color(0.2, 0.8, 1.0))
		_add_label("%s FOOT_%s sole=%+.3f %s" % [tag, side.to_upper(), sole, _clearance_word(sole)], Vector3(fc.x, sole + 0.45, fc.z), 0.004)
	else:
		_add_label("%s FOOT_%s sole=UNKNOWN" % [tag, side.to_upper()], Vector3(fc.x, 1.35, fc.z), 0.004)
	_add_label("ankle=%s shin_min=%.2f" % [_v3(ankle), sb.position.y], Vector3(fc.x, (sole + 0.28) if known else 1.12, fc.z), 0.0035)
	_ensure_cam()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 1.7
	_cam.near = 0.05
	_cam.far = 200.0
	_place_cam(Vector3(fc.x, 0.95, fc.z), 90.0 if side == "left" else 270.0, 6.0, 9.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_capture("G2d_%s_foot_%s.png" % [tag, side])


func _capture_chain(mecha: Node3D, tag: String, suffix: String = "") -> void:
	_clear_overlay()
	var hip := (mecha.get_node_or_null("LegLeft") as Node3D).global_position
	var knee := (mecha.get_node_or_null("LegLeft/ShinLeft") as Node3D).global_position
	var ankle := (mecha.get_node_or_null("LegLeft/ShinLeft/FootLeft") as Node3D).global_position
	var foot_box := _bucket_aabb(mecha, "foot_l")
	var known := foot_box.size.length_squared() > 0.0
	var sole: float = foot_box.position.y if known else NAN
	var word := _clearance_word(sole) if known else "UNKNOWN"
	_add_marker(hip, Color(1.0, 0.15, 0.15))
	_add_marker(knee, Color(1.0, 0.9, 0.1))
	_add_marker(ankle, Color(0.1, 1.0, 0.2))
	if known:
		_add_marker(Vector3(ankle.x, sole, ankle.z), Color(0.2, 0.8, 1.0))
	var strip := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4.5, 0.012, 0.4)
	strip.mesh = bm
	strip.material_override = _marker_mat(Color(1.0, 0.45, 0.0))
	strip.position = Vector3(hip.x, 0.006, ankle.z)
	_overlay.add_child(strip)
	_add_label("%s CHAIN%s hip=%s knee=%s" % [tag, suffix, _v3(hip), _v3(knee)], Vector3(hip.x, hip.y + 0.55, 0.0), 0.005)
	_add_label("ankle=%s sole=%s %s" % [_v3(ankle), ("%.3f" % sole) if known else "UNKNOWN", word], Vector3(hip.x, hip.y + 0.28, 0.0), 0.0045)
	print("[G2d] %s chain%s sole=%s(%s)" % [tag, suffix, ("%.3f" % sole) if known else "UNKNOWN", word])
	_ensure_cam()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 4.6
	_cam.near = 0.05
	_cam.far = 200.0
	_place_cam(Vector3(hip.x, 2.35, 0.0), 90.0, 6.0, 12.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_capture("G2d_%s_chain%s.png" % [tag, suffix])


func _clearance_word(v: float) -> String:
	if v < -TOL:
		return "PENETRATING"
	if v <= TOL:
		return "TOUCHING"
	return "FLOATING"


func _ensure_cam() -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "G2dOrthoCam"
		add_child(_cam)
	_cam.make_current()


func _place_cam(focus: Vector3, az_deg: float, el_deg: float, dist: float) -> void:
	var az: float = deg_to_rad(az_deg)
	var el: float = deg_to_rad(el_deg)
	_cam.global_position = focus + Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)) * dist
	_cam.look_at(focus, Vector3.UP)


func _setup_stage() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -35, 0)
	key.light_energy = 1.2
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 130, 0)
	fill.light_energy = 0.5
	add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 55, 0)
	rim.light_energy = 0.8
	add_child(rim)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.85, 0.85, 0.87)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.72, 0.72, 0.74)
	ground.material_override = gmat
	add_child(ground)
	var floor_body := StaticBody3D.new()
	floor_body.name = "PreviewPhysFloor"
	floor_body.collision_layer = 2
	floor_body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.2, 40)
	col.shape = box
	col.position = Vector3(0, -0.1, 0)
	floor_body.add_child(col)
	add_child(floor_body)


func _frame_shared(union: AABB) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "G2dOrthoCam"
		add_child(_cam)
	var vp := get_viewport().get_visible_rect().size
	var aspect: float = vp.x / maxf(vp.y, 1.0)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = maxf(union.size.y, union.size.x / aspect) * 1.15
	_cam.near = 0.05
	_cam.far = 200.0
	_cam.make_current()
	print("[G2d] ortho shared framing ready")


func _aim_camera(union: AABB, view: String) -> void:
	var preset: Dictionary = VIEW_PRESETS[view]
	var az: float = deg_to_rad(preset["az"])
	var el: float = deg_to_rad(preset["el"])
	var focus: Vector3 = union.get_center()
	var dist: float = maxf(union.size.y, union.size.x) * 2.0 + 4.0
	_cam.global_position = focus + Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)) * dist
	_cam.look_at(focus, Vector3.UP)


func _save_capture(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s" % [OUT_DIR, fname])
	if err != OK:
		printerr("[G2d] SAVE FAILED %s err=%d (no repo fallback by design)" % [fname, err])
		_failed = true
	else:
		_saved.append(fname)
		print("[G2d] saved %s size=%s" % [fname, img.get_size()])


func _compose_contact_sheet() -> void:
	var order: Array[String] = []
	for tag in ["BASE", "G2d-1", "G2d-2"]:
		for v in ["side", "foot_left", "chain"]:
			order.append("G2d_%s_%s.png" % [tag, v])
	var cell_w := 480
	var cell_h := 270
	var sheet := Image.create(3 * cell_w, 3 * cell_h, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.16, 0.16, 0.18))
	var ok := true
	for i in range(order.size()):
		var cell: Image = Image.load_from_file("%s/%s" % [OUT_DIR, order[i]])
		if cell == null or cell.is_empty():
			printerr("[G2d] sheet: cannot load %s (cell outstanding)" % order[i])
			ok = false
			continue
		cell.resize(cell_w, cell_h)
		sheet.blit_rect(cell, Rect2i(0, 0, cell_w, cell_h), Vector2i((i % 3) * cell_w, (i / 3) * cell_h))
	if not ok:
		print("[G2d] CONTACT_SHEET_OUTSTANDING (individual captures stand)")
		return
	var err := sheet.save_png("%s/G2d_contact_sheet.png" % OUT_DIR)
	if err != OK:
		print("[G2d] CONTACT_SHEET_OUTSTANDING save err=%d" % err)
	else:
		_saved.append("G2d_contact_sheet.png")
		print("[G2d] saved G2d_contact_sheet.png size=%s" % sheet.get_size())


func _v3(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
