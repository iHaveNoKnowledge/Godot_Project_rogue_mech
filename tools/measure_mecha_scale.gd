extends Node3D

const BASE_SCENE := "res://scenes/mecha/mecha_base.tscn"

const SETS: Dictionary = {
	"bare_frame": {},
	"wanzer_local": {
		"head": "res://resources/mech/parts/head/wanzer_local_001.tres",
		"body": "res://resources/mech/parts/body/wanzer_local_001.tres",
		"arm_left": "res://resources/mech/parts/arm_left/wanzer_local_001.tres",
		"arm_right": "res://resources/mech/parts/arm_right/wanzer_local_001.tres",
		"leg_left": "res://resources/mech/parts/leg_left/wanzer_local_001.tres",
		"leg_right": "res://resources/mech/parts/leg_right/wanzer_local_001.tres",
	},
	"wanzer_001": {
		"head": "res://resources/mech/parts/head/wanzer_head_001.tres",
		"body": "res://resources/mech/parts/body/wanzer_body_001.tres",
		"arm_left": "res://resources/mech/parts/arm_left/wanzer_arm_left_001.tres",
		"arm_right": "res://resources/mech/parts/arm_right/wanzer_arm_right_001.tres",
		"leg_left": "res://resources/mech/parts/leg_left/wanzer_leg_left_001.tres",
		"leg_right": "res://resources/mech/parts/leg_right/wanzer_leg_right_001.tres",
	},
	"procedural_blender": {
		"head": "res://resources/mech/parts/head/procedural_blender.tres",
		"body": "res://resources/mech/parts/body/procedural_blender.tres",
		"arm_left": "res://resources/mech/parts/arm_left/procedural_blender.tres",
		"arm_right": "res://resources/mech/parts/arm_right/procedural_blender.tres",
		"leg_left": "res://resources/mech/parts/leg_left/procedural_blender.tres",
		"leg_right": "res://resources/mech/parts/leg_right/procedural_blender.tres",
	},
	"wanzer_legacy": {
		"head": "res://resources/mech/parts/head/wanzer_head.tres",
		"body": "res://resources/mech/parts/body/wanzer_body.tres",
		"arm_left": "res://resources/mech/parts/arm_left/wanzer_arm_left.tres",
		"arm_right": "res://resources/mech/parts/arm_right/wanzer_arm_right.tres",
		"leg_left": "res://resources/mech/parts/leg_left/wanzer_leg_left.tres",
		"leg_right": "res://resources/mech/parts/leg_right/wanzer_leg_right.tres",
	},
}

const PIVOT_PATHS: Array[String] = [
	"Head", "Body",
	"ArmLeft", "ArmLeft/ForearmLeft",
	"ArmRight", "ArmRight/ForearmRight",
	"LegLeft", "LegLeft/ShinLeft", "LegLeft/ShinLeft/FootLeft",
	"LegRight", "LegRight/ShinRight", "LegRight/ShinRight/FootRight",
]

const REGION_PATHS: Dictionary = {
	"head": "Head", "body": "Body",
	"arm_left": "ArmLeft", "arm_right": "ArmRight",
	"leg_left": "LegLeft", "leg_right": "LegRight",
}

const FRAME_HOLD: Array[String] = ["Head", "Body", "ArmLeft", "ArmRight", "LegLeft", "LegRight"]


func _ready() -> void:
	var data := await _measure_with_loadout("global_default", {})
	print("[MEASURE] === global_default ===")
	_report(data)
	for set_name in SETS:
		data = await _measure_with_loadout(set_name, SETS[set_name])
		print("[MEASURE] === %s ===" % set_name)
		_report(data)
	print("[MEASURE] done")
	get_tree().quit(0)


func _measure_with_loadout(set_name: String, paths: Dictionary) -> Dictionary:
	var mecha: Node3D = (load(BASE_SCENE) as PackedScene).instantiate()
	var rest := _capture_rest(mecha)
	add_child(mecha)
	mecha.process_mode = Node.PROCESS_MODE_DISABLED
	if not paths.is_empty():
		var pm = mecha.get_node_or_null("PartMeshManager")
		if pm:
			pm.refresh_from_loadout(_build_loadout(paths))
	_apply_rest(mecha, rest)
	for i in 2:
		await get_tree().process_frame
	_apply_rest(mecha, rest)
	var data := _collect(mecha)
	mecha.queue_free()
	await get_tree().process_frame
	return data


func _capture_rest(mecha: Node3D) -> Dictionary:
	var rest: Dictionary = {"__root__": mecha.transform}
	for path in PIVOT_PATHS:
		var n := mecha.get_node_or_null(path) as Node3D
		if n:
			rest[path] = n.transform
	return rest


func _apply_rest(mecha: Node3D, rest: Dictionary) -> void:
	for path in rest:
		if path == "__root__":
			mecha.transform = rest[path]
			continue
		var n := mecha.get_node_or_null(path) as Node3D
		if n:
			n.transform = rest[path]


func _build_loadout(paths: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for slot in GlobalData.MECHA_SLOTS:
		var entry: Dictionary = {"frame": {"id": "frame_%s_01" % slot, "equipped": true}, "armor": null}
		if paths.has(slot):
			entry["armor"] = {"id": slot, "equipped": true, "path": paths[slot], "slot": slot}
		out[slot] = entry
	return out


func _collect(mecha: Node3D) -> Dictionary:
	var boxes: Array = []
	_gather_meshes(mecha, boxes)
	var data: Dictionary = {
		"root_scale": mecha.scale,
		"pivots": {},
		"rest_locals": {},
		"chain": {},
		"regions": {},
		"frame_boxes": [],
		"meshes": boxes,
		"union": _union(boxes),
		"top_meshes": [],
		"skels": [],
	}
	for path in PIVOT_PATHS:
		var n := mecha.get_node_or_null(path) as Node3D
		if n:
			data["pivots"][path] = n.global_position
			data["rest_locals"][path] = n.transform.origin
	var leg := mecha.get_node_or_null("LegLeft") as Node3D
	var shin := mecha.get_node_or_null("LegLeft/ShinLeft") as Node3D
	var foot := mecha.get_node_or_null("LegLeft/ShinLeft/FootLeft") as Node3D
	if leg and shin and foot:
		data["chain"] = {
			"thigh": leg.global_position.distance_to(shin.global_position),
			"shin": shin.global_position.distance_to(foot.global_position),
		}
	for slot in REGION_PATHS:
		var n := mecha.get_node_or_null(REGION_PATHS[slot]) as Node3D
		if n == null:
			continue
		var rb: Array = []
		_gather_meshes(n, rb)
		if not rb.is_empty():
			data["regions"][slot] = _union(rb)
	for path in FRAME_HOLD:
		var n := mecha.get_node_or_null(path) as Node3D
		if n == null:
			continue
		var fm := n.get_node_or_null("FrameMesh") as Node3D
		var am := n.get_node_or_null("ArmorMesh") as Node3D
		var fs := fm.global_transform.basis.get_scale() if fm else Vector3.ZERO
		var as_ := am.global_transform.basis.get_scale() if am else Vector3.ZERO
		print("[MEASURE] %-10s FrameMesh_gscale=%s ArmorMesh_gscale=%s" % [path, str(fs), str(as_)])
	for skel in mecha.find_children("*", "Skeleton3D", true, false):
		data["skels"].append({"path": str(mecha.get_path_to(skel)), "bones": skel.get_bone_count()})
	var tall: Array = []
	for item in boxes:
		tall.append({"name": str(item[0].name), "top": (item[1] as AABB).end.y, "path": str(mecha.get_path_to(item[0]))})
	tall.sort_custom(func(a, b): return a["top"] > b["top"])
	data["top_meshes"] = tall.slice(0, 5)
	return data


func _gather_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree():
			out.append([mi, mi.global_transform * mi.mesh.get_aabb()])
	for c in n.get_children():
		_gather_meshes(c, out)


func _union(boxes: Array) -> AABB:
	if boxes.is_empty():
		return AABB()
	var aabb: AABB = boxes[0][1]
	for i in range(1, boxes.size()):
		aabb = aabb.merge(boxes[i][1])
	return aabb


func _report(data: Dictionary) -> void:
	print("[MEASURE] mesh_count=%d root_scale=%s" % [data["meshes"].size(), str(data["root_scale"])])
	for path in data["pivots"]:
		print("[MEASURE] pivot %-30s local=%s world=%s" % [path, str(data["rest_locals"][path]), str(data["pivots"][path])])
	if not data["chain"].is_empty():
		print("[MEASURE] chain thigh=%.4f shin=%.4f" % [data["chain"]["thigh"], data["chain"]["shin"]])
	for slot in data["regions"]:
		var b: AABB = data["regions"][slot]
		print("[MEASURE] region %-10s min=%s max=%s size=%s" % [slot, str(b.position), str(b.end), str(b.size)])
	var u: AABB = data["union"]
	print("[MEASURE] UNION min=%s max=%s size=%s height_above_ground=%.4f" % [str(u.position), str(u.end), str(u.size), u.end.y - maxf(u.position.y, 0.0)])
	print("[MEASURE] visible_height=%.4f foot_bottom=%.4f" % [u.size.y, u.position.y])
	for s in data["skels"]:
		print("[MEASURE] skeleton %s bones=%d" % [s["path"], s["bones"]])
	for m in data["top_meshes"]:
		print("[MEASURE] top mesh %-40s top=%.4f %s" % [m["name"], m["top"], m["path"]])
