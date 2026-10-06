extends SceneTree

## Headless exporter: assembles the PROCEDURAL inner frame for every mecha slot
## (exactly what PartMeshManager._build_procedural_inner_frame() builds in game)
## and writes GLB modeling references for Blender / any DCC.
##
## Run:
##   Godot_console.exe --headless --path <project> --script res://tools/export_procedural_innerframe.gd
##
## MechaBase now at scale 1.0 with true world meters (4.73m tall). Author new parts at TRUE SIZE:
## model at 1 unit = 1 meter, import into Godot with scale 1.0, origin at joint pivot (JNT_*).
## Two files are written (both now true scale, kept for compatibility):
##   exports/procedural_innerframe_local.glb — author at this true scale
##   exports/procedural_innerframe.glb — same true scale (legacy WORLD)
##
## Every exported mesh node carries no rotation/scale — vertices are
## pre-transformed — and JNT_* empties mark the joint pivots a replacement
## part's origin must sit on.

const GAME_SCALE := 1.0

## Standard-frame cockpit asset (same file PartMeshManager uses for the body):
## tub + waist core sized for a 180 cm seated pilot. Passed as frame_data so
## headless exports don't depend on GlobalData (which can't compile headless).
const COCKPIT_MODEL := "res://assets/models/mech_cockpit_tub.glb"

const EXPORT_CONFIGS := [
	{"path": "res://exports/procedural_innerframe_local.glb", "scale": 1.0, "tag": "TRUE  (author at this scale - 1 unit = 1m)"},
	{"path": "res://exports/procedural_innerframe.glb", "scale": GAME_SCALE, "tag": "TRUE  (same)"},
]

## slot -> [node name, local position] — mirrors mecha_base.tscn upper pivots (TRUE WORLD at scale 1.0).
const UPPER_PIVOTS := {
	"head": ["Head", Vector3(0, 4.4436, -0.07728)],
	"body": ["Body", Vector3(0, 3.4776, 0)],
	"arm_left": ["ArmLeft", Vector3(-1.31376, 3.9606, 0)],
	"arm_right": ["ArmRight", Vector3(1.31376, 3.9606, 0)],
	"leg_left": ["LegLeft", Vector3(-0.73416, 2.5116, 0)],
	"leg_right": ["LegRight", Vector3(0.73416, 2.5116, 0)],
}

## slot -> lower-joint pivot (null when the slot has none) — mirrors
## part_mesh_manager._LOWER_NODE_NAMES plus the tscn transforms (TRUE WORLD).
const LOWER_PIVOTS := {
	"arm_left": ["ForearmLeft", Vector3(0, -0.73416, 0)],
	"arm_right": ["ForearmRight", Vector3(0, -0.73416, 0)],
	"leg_left": ["ShinLeft", Vector3(0, -1.0626, 0)],
	"leg_right": ["ShinRight", Vector3(0, -1.0626, 0)],
}

## slot -> ankle/foot pivot — mirrors part_mesh_manager._FOOT_NODE_NAMES
## (Foot hangs off the Shin at ankle height, TRUE WORLD).
const FOOT_PIVOTS := {
	"leg_left": ["FootLeft", Vector3(0, -1.024, 0)],
	"leg_right": ["FootRight", Vector3(0, -1.024, 0)],
}

## Piece names in the exact order _build_procedural_inner_frame adds them,
## keyed by segment ("upper" = frame container on the upper pivot, "lower" =
## frame_lower container on the lower pivot, "foot" = frame_foot container on
## the ankle pivot). Used to give exported meshes readable names.
const PIECE_LABELS := {
	"head": {"upper": ["skull", "eye_sensor", "neck"], "lower": [], "foot": []},
	"body": {"upper": [
		"spine", "rib_top", "rib_mid", "rib_low", "core",
		"socket_l", "socket_r", "waist", "piston_l", "piston_r",
	], "lower": [], "foot": []},
	"arm_left": {"upper": ["shoulder_joint", "shoulder_bolt", "upper_arm"], "lower": ["elbow_disc", "forearm_frame", "hand_block"], "foot": []},
	"arm_right": {"upper": ["shoulder_joint", "shoulder_bolt", "upper_arm"], "lower": ["elbow_disc", "forearm_frame", "hand_block"], "foot": []},
	"leg_left": {"upper": ["hip_joint", "thigh_frame"], "lower": ["knee_disc", "shin_frame", "damper"], "foot": ["ankle", "ankle_flange_l", "ankle_flange_r", "foot_block", "skid_l", "skid_r", "roller", "heel", "claw_l", "claw_r"]},
	"leg_right": {"upper": ["hip_joint", "thigh_frame"], "lower": ["knee_disc", "shin_frame", "damper"], "foot": ["ankle", "ankle_flange_l", "ankle_flange_r", "foot_block", "skid_l", "skid_r", "roller", "heel", "claw_l", "claw_r"]},
}


var _ran := false


func _initialize() -> void:
	pass


func _process(_delta: float) -> bool:
	# Nodes added during _initialize() are not yet inside the tree (their
	# global transforms are invalid), so run on the first processed frame.
	if not _ran:
		_ran = true
		var ok := _run()
		quit(0 if ok else 1)
	return true


func _run() -> bool:
	var all_ok := true
	for cfg in EXPORT_CONFIGS:
		if not _export_one(cfg["path"], cfg["scale"], cfg["tag"]):
			all_ok = false
	return all_ok


func _export_one(out_path: String, scale: float, tag: String) -> bool:
	print("[EXPORT] === %s ===" % tag)
	# --- 1. Rebuild the pivot hierarchy of mecha_base.tscn -------------------
	var build_root := Node3D.new()
	build_root.name = "InnerFrameBuild"
	build_root.scale = Vector3.ONE * scale
	root.add_child(build_root)

	var joint_markers := {}
	for slot in GlobalData.MECHA_SLOTS:
		joint_markers[slot] = _pivot(build_root, UPPER_PIVOTS[slot][0], UPPER_PIVOTS[slot][1])
	# Lower pivots hang off their upper pivot (ForearmLeft under ArmLeft etc.)
	for slot in LOWER_PIVOTS:
		_pivot(joint_markers[slot], LOWER_PIVOTS[slot][0], LOWER_PIVOTS[slot][1])
	# Foot pivots hang off the lower pivot (FootLeft under ShinLeft etc.)
	var foot_markers := {}
	for slot in FOOT_PIVOTS:
		var shin: Node3D = joint_markers[slot].get_node(LOWER_PIVOTS[slot][0])
		foot_markers[slot] = _pivot(shin, FOOT_PIVOTS[slot][0], FOOT_PIVOTS[slot][1])

	# --- 2. Build the procedural inner frames exactly like in game -----------
	var manager := Node3D.new()
	manager.name = "PartMeshManager"
	manager.set_script(load("res://scripts/mecha/part_mesh_manager.gd"))
	build_root.add_child(manager)

	for slot in GlobalData.MECHA_SLOTS:
		var frame_data: Variant = null
		if slot == "body":
			frame_data = {"model_path": COCKPIT_MODEL}
		manager.initialize_slot(slot, null, false, frame_data)

	# --- 3. Bake every generated primitive into clean, scale-free nodes ------
	var out_root := Node3D.new()
	out_root.name = "ProceduralInnerFrame"
	root.add_child(out_root)

	for slot in GlobalData.MECHA_SLOTS:
		out_root.add_child(_joint_empty("JNT_" + UPPER_PIVOTS[slot][0], joint_markers[slot].global_position))
	for slot in LOWER_PIVOTS:
		var lp: Node3D = joint_markers[slot].get_node(LOWER_PIVOTS[slot][0])
		out_root.add_child(_joint_empty("JNT_" + LOWER_PIVOTS[slot][0], lp.global_position))
	for slot in FOOT_PIVOTS:
		var fp: Node3D = foot_markers[slot]
		out_root.add_child(_joint_empty("JNT_" + FOOT_PIVOTS[slot][0], fp.global_position))

	var used_names := {}
	var total_tris := 0
	var total_meshes := 0
	var merged_aabb := AABB()

	# The procedural builder adds pieces in a fixed order per slot; name the
	# exported meshes after that order so they are meaningful in a DCC.
	for slot in GlobalData.MECHA_SLOTS:
		var entry: Dictionary = manager.slot_meshes.get(slot, {})
		var labels: Dictionary = PIECE_LABELS.get(slot, {})
		for segment in ["frame", "frame_lower", "frame_foot"]:
			var container: Node3D = entry.get(segment)
			if container == null:
				continue
			var seg_key := "upper" if segment == "frame" else ("lower" if segment == "frame_lower" else "foot")
			var seg_labels: Array = labels.get(seg_key, [])
			var idx := 0
			# Walk all descendants (not just direct children) so nested asset
			# pieces (WaistCore / SlidingCarriage / CockpitTub children) are baked
			# too. Direct children keep their PIECE_LABELS names; nested ones fall
			# back to their node names.
			var stack: Array = container.get_children()
			stack.reverse()
			while not stack.is_empty():
				var child: Node = stack.pop_back()
				for grand in child.get_children():
					stack.push_back(grand)
				if not (child is MeshInstance3D) or (child as MeshInstance3D).mesh == null:
					continue
				if not _is_effectively_visible(child, container):
					continue  # e.g. hidden CockpitPilot mannequin
				var label: String
				if child.get_parent() == container:
					label = seg_labels[idx] if idx < seg_labels.size() else _sanitize(String(child.name))
					idx += 1
				else:
					# Nested pieces (asset children like WaistCore/CockpitTub parts,
					# finger armor segments): keep the real node name; the slot
					# prefix is added by the _bake_piece call below.
					var raw := String(child.name)
					label = raw if raw != "" else "piece"
				var baked_stats := _bake_piece(child, "%s_%s" % [slot.replace("_left", "_l").replace("_right", "_r"), label], out_root, used_names)
				total_meshes += 1
				total_tris += baked_stats[0]
				var ab: AABB = baked_stats[1]
				merged_aabb = ab if merged_aabb.size == Vector3.ZERO else merged_aabb.merge(ab)

	print("[EXPORT] meshes=%d tris=%d" % [total_meshes, total_tris])
	print("[EXPORT] aabb min=%s max=%s height=%.3f width=%.3f depth=%.3f" % [
		merged_aabb.position, merged_aabb.end,
		merged_aabb.size.y, merged_aabb.size.x, merged_aabb.size.z])

	# --- 4. Write the GLB -----------------------------------------------------
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	if gltf.append_from_scene(out_root, state, 0) != OK:
		push_error("GLTF append_from_scene failed")
		return false
	var bytes := gltf.generate_buffer(state)
	if bytes.is_empty():
		push_error("GLTF generate_buffer produced no data")
		return false

	var abs_out := ProjectSettings.globalize_path(out_path)
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	var f := FileAccess.open(abs_out, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write %s (err %d)" % [abs_out, FileAccess.get_open_error()])
		return false
	f.store_buffer(bytes)
	f.close()
	print("[EXPORT] wrote %s (%d bytes)" % [abs_out, bytes.size()])

	# Free this pass's nodes before rebuilding at the next scale.
	root.remove_child(build_root)
	build_root.free()
	root.remove_child(out_root)
	out_root.free()
	return true


func _pivot(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n


func _joint_empty(node_name: String, world_pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = world_pos
	return n


## Bakes one source MeshInstance3D into a clean translation-only node whose
## vertices carry the full world transform (rotation + GAME_SCALE). Returns
## [triangle count, world-space AABB].
func _bake_piece(mi: MeshInstance3D, label: String, out_root: Node3D, used_names: Dictionary) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in mi.mesh.get_surface_count():
		st.set_material(mi.get_active_material(s))
		st.append_from(mi.mesh, s, Transform3D(mi.global_transform.basis, Vector3.ZERO))
	var baked := st.commit()
	if baked == null:
		return [0, AABB()]
	var tris := baked.get_faces().size() / 3

	var name := label
	var n := 1
	while used_names.has(name):
		name = "%s_%d" % [label, n]
		n += 1
	used_names[name] = true

	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = baked
	node.transform = Transform3D(Basis.IDENTITY, mi.global_transform.origin)
	out_root.add_child(node)
	return [tris, node.global_transform * baked.get_aabb()]


## Strips Godot's auto-generated "@Class@N" noise down to something readable.
func _sanitize(raw: String) -> String:
	var s := raw.to_lower().trim_prefix("@").get_slice("@", 0)
	return s if s != "" else "piece"


## True when the node and every ancestor up to (excluding) the container is
## visible. Used to skip hidden subtrees like the CockpitPilot mannequin.
func _is_effectively_visible(n: Node, container: Node) -> bool:
	var cur: Node = n
	while cur != null and cur != container:
		if cur is Node3D and not (cur as Node3D).visible:
			return false
		if cur is VisualInstance3D and not (cur as VisualInstance3D).visible:
			return false
		cur = cur.get_parent()
	return true
