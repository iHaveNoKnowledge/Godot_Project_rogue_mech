extends Node

## Upper-body armor forensic audit: body/chest, head, shoulder vs pivots/frame.
## Measures only; structural checks (finite, follows-pivot, L/R symmetric).
## Run: godot --headless --path . res://tests/mecha/upper_armor_proportion_audit.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"

var _fails := 0
var _checks := 0


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + label)
	else:
		_fails += 1
		push_error("FAIL: " + label)


func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)


func _box(meshes: Array) -> AABB:
	var b := AABB()
	var first := true
	for m in meshes:
		var a: AABB = (m as MeshInstance3D).get_aabb()
		var t: Transform3D = (m as Node3D).global_transform
		for cx in [a.position.x, a.position.x + a.size.x]:
			for cy in [a.position.y, a.position.y + a.size.y]:
				for cz in [a.position.z, a.position.z + a.size.z]:
					var p: Vector3 = t * Vector3(cx, cy, cz)
					if first:
						b = AABB(p, Vector3.ZERO)
						first = false
					else:
						b = b.expand(p)
	return b


func _finite(v: Vector3) -> bool:
	return not (is_nan(v.x) or is_nan(v.y) or is_nan(v.z) or is_inf(v.x) or is_inf(v.y) or is_inf(v.z))


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("UPPER_ARMOR_AUDIT: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.position = Vector3(0, -1.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 3, 200)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)
	var mech: CharacterBody3D = load(MECH_SCENE).instantiate()
	mech.position = Vector3(0, 10, 0)
	add_child(mech)
	await get_tree().process_frame
	var f := 0
	while not mech.is_on_floor() and f < 180:
		await get_tree().physics_frame
		f += 1
	await get_tree().physics_frame
	await get_tree().physics_frame

	var body_p: Node3D = mech.get_node_or_null("Body")
	var head_p: Node3D = mech.get_node_or_null("Head")
	var armL: Node3D = mech.get_node_or_null("ArmLeft")
	var armR: Node3D = mech.get_node_or_null("ArmRight")
	_check(body_p != null and head_p != null and armL != null and armR != null, "pivots resolve")
	print("PIVOT body=%s head=%s armL=%s armR=%s" % [str(body_p.global_position), str(head_p.global_position), str(armL.global_position), str(armR.global_position)])

	var pmm: Node = mech.get_node_or_null("PartMeshManager")
	var slots: Dictionary = pmm.get("slot_meshes") if pmm else {}
	for slot in ["body", "head", "arm_left", "arm_right"]:
		_report_slot(mech, slots, slot)
	_check_layout(mech, slots, body_p, head_p, armL, armR)

	# head rotation sweep: armor must follow rigidly (locals bit-identical)
	if head_p:
		var hms: Array = []
		_collect_named(head_p, "ArmorMesh", hms)
		_check(not hms.is_empty(), "head armor carrier resolves")
		var hmesh: Array = []
		for h in hms:
			_meshes(h, hmesh)
		var hpre := _locals(hmesh)
		for e in [Vector3(0, 0.5, 0), Vector3(0, -0.5, 0), Vector3(0.3, 0, 0), Vector3(-0.2, 0, 0), Vector3.ZERO]:
			head_p.rotation = e
			await get_tree().physics_frame
			await get_tree().physics_frame
		_check(_locals(hmesh) == hpre, "head armor rigid through rotation sweep")
		head_p.rotation = Vector3.ZERO
		await get_tree().physics_frame
		print("HEAD helm rest box c=%s s=%s" % [str(_slot_box(slots, "head").get_center()), str(_slot_box(slots, "head").size)])
	# shoulder swing sweep L/R: armor local transforms must be bit-identical
	# before/after (global AABB size legitimately changes when a rigid
	# assembly rotates, so locals are the correct rigidity probe).
	for side in ["Left", "Right"]:
		var arm: Node3D = mech.get_node_or_null("Arm" + side)
		if arm == null:
			continue
		var pre := _locals(_carrier_meshes(mech, side))
		for a in [0.6, -0.6, 0.0]:
			arm.rotation.x = a
			await get_tree().physics_frame
		var post := _locals(_carrier_meshes(mech, side))
		_check(pre == post, "shoulder %s armor rigid under swing" % side)
		arm.rotation.x = 0.0
		await get_tree().physics_frame
	mech.queue_free()
	await get_tree().process_frame


func _slot_box(slots: Dictionary, slot: String) -> AABB:
	var e: Dictionary = slots.get(slot, {})
	var ms: Array = []
	for k in ["armor", "armor_lower", "armor_foot"]:
		if e.get(k) != null:
			_meshes(e[k], ms)
	return _box(ms)


func _frame_box(slots: Dictionary, slot: String) -> AABB:
	var e: Dictionary = slots.get(slot, {})
	var ms: Array = []
	for k in ["frame", "frame_lower", "frame_foot"]:
		if e.get(k) != null:
			_meshes(e[k], ms)
	return _box(ms)


func _report_slot(mech: Node, slots: Dictionary, slot: String) -> void:
	var e: Dictionary = slots.get(slot, {})
	if e.is_empty():
		print("SLOT %s: empty" % slot)
		return
	var ab := _slot_box(slots, slot)
	var fb := _frame_box(slots, slot)
	print("SLOT %s armor c=%s s=%s | frame c=%s s=%s" % [slot, str(ab.get_center()), str(ab.size), str(fb.get_center()), str(fb.size)])
	_check(_finite(ab.get_center()) and _finite(ab.size), "%s armor finite" % slot)


func _check_layout(mech: Node, slots: Dictionary, body_p: Node3D, head_p: Node3D, armL: Node3D, armR: Node3D) -> void:
	# Permanent regression guard: placement contract per slot, derived from
	# measured validated behavior (generous bands on a 5 m mech).
	var bab := _slot_box(slots, "body")
	var fbb := _frame_box(slots, "body")
	var d: Vector3 = (bab.get_center() - fbb.get_center()).abs()
	_check(d.x < 0.3 and d.y < 0.3 and d.z < 0.3, "body armor centered on frame (d=%s)" % str(d))
	var hab := _slot_box(slots, "head")
	var hd: Vector3 = hab.get_center() - head_p.global_position
	_check(absf(hd.x) < 0.1 and absf(hd.y) < 0.5 and absf(hd.z) < 0.35, "head armor centered on pivot (d=%s)" % str(hd))
	_check(hab.get_center().y > head_p.global_position.y, "helm shell sits above pivot")
	var pl := _named_center(mech, "ArmLeft", "pauldron")
	var pr := _named_center(mech, "ArmRight", "pauldron")
	_check(pl.x < 900.0 and pr.x < 900.0, "pauldrons present both sides")
	if pl.x < 900.0 and pr.x < 900.0:
		_check(absf(pl.y - armL.global_position.y) < 0.35, "pauldron L centered on shoulder")
		_check(absf(absf(pr.x) - absf(pl.x)) < 0.1, "pauldrons mirrored L/R")
		_check(absf(pl.y - pr.y) < 0.1, "pauldrons level L/R")
	# Hatch boundary: compartment never hatch-owned; body armor under a
	# carriage is reported (hatch plate when present) but the tub must not be.
	var tub: Node = mech.get_node_or_null("Body").get_node_or_null("FrameMesh/CockpitTub") if mech.get_node_or_null("Body") else null
	if tub == null:
		tub = _find_sub(mech, "CockpitTub")
	_check(tub != null, "compartment tub present")
	if tub != null:
		_check(not _under_named(tub, "SlidingCarriage"), "compartment not hatch-owned")


func _collect_named(n: Node, sub: String, out: Array) -> void:
	if sub in n.name:
		out.append(n)
	for c in n.get_children():
		_collect_named(c, sub, out)


func _locals(meshes: Array) -> Array:
	var out: Array = []
	for m in meshes:
		out.append((m as Node3D).transform)
	return out


func _carrier_meshes(mech: Node, side: String) -> Array:
	var out: Array = []
	var arm: Node = mech.get_node_or_null("Arm" + side)
	if arm:
		_meshes(arm, out)
	return out


func _named_center(mech: Node, pivot_path: String, sub: String) -> Vector3:
	var pivot: Node3D = mech.get_node_or_null(pivot_path)
	var found: Array = []
	if pivot:
		_collect_named(pivot, sub, found)
	var ms: Array = []
	for f in found:
		_meshes(f, ms)
	if ms.is_empty():
		return Vector3(999, 999, 999)
	return _box(ms).get_center()


func _find_sub(n: Node, sub: String) -> Node:
	if sub in n.name:
		return n
	for c in n.get_children():
		var f := _find_sub(c, sub)
		if f != null:
			return f
	return null


func _under_named(n: Node, sub: String) -> bool:
	var p := n.get_parent()
	while p != null:
		if sub in p.name:
			return true
		p = p.get_parent()
	return false
