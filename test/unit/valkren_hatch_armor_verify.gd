extends Node
## VALKREN HATCH ARMOR VERIFY — transform ownership, not position hacks.
##
## Invariant under test: HatchArmor.global = HatchCover.global x HatchArmor.local
## with HatchArmor.local STABLE across open/close. The hatch motion owner
## (ArmorMesh/SlidingCarriage) carries equipped hatch-zone armor automatically.
##
## Covers (§8-10): closed alignment sanity, open follows, close returns,
## 5x open/close cycles without drift, armor replacement A->B->A.
## Prints Body/HatchCover/HatchArmor transforms at each stage (§12).

const PMM_SCRIPT := preload("res://scripts/mecha/part_mesh_manager.gd")

var _fails := 0
var _checks := 0
var _mech = null
var _pmm = null


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("VALKREN_HATCH OK: " + name)
	else:
		_fails += 1
		printerr("VALKREN_HATCH FAIL: " + name)


func _meshes_under(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_meshes_under(c, out)


func _under_carriage(m: Node, carriage: Node) -> bool:
	var p: Node = m.get_parent()
	while p != null:
		if p == carriage:
			return true
		p = p.get_parent()
	return false


## Armor mesh transform expressed in the carriage (motion owner) space.
func _in_carriage_space(m: Node3D, carriage: Node3D) -> Transform3D:
	return carriage.global_transform.affine_inverse() * m.global_transform


func _equip_body(tres_path: String) -> void:
	var part := ArmorPart.new()
	part.slot_id = "body"
	part.mesh_scene = load(tres_path) as PackedScene
	var std_frame: Dictionary = ArmorSystem.get_frame_catalog_entry("frame_body_01")
	_pmm.initialize_slot("body", part, false, std_frame)


func _body_roots() -> Array:
	var entry: Dictionary = _pmm.get("slot_meshes")["body"]
	return [entry["frame"] as Node, entry["armor"] as Node]


func _snapshot(tag: String) -> Dictionary:
	var roots := _body_roots()
	var frame_mesh: Node = roots[0]
	var armor_mesh: Node = roots[1]
	var carriage_f: Node3D = _pmm._find_hatch_carriage(frame_mesh)
	var carriage_a: Node3D = _pmm._find_hatch_carriage(armor_mesh)
	var body: Node3D = _mech.get_node_or_null("Body")
	print("--- %s ---" % tag)
	print("Body g=%s" % str(body.global_transform.origin) if body else "Body MISSING")
	if carriage_f:
		print("HatchCover(frame) loc=%s g=%s" % [str(carriage_f.position), str(carriage_f.global_position)])
	if carriage_a:
		print("HatchCover(armor) loc=%s g=%s parent=%s" % [str(carriage_a.position), str(carriage_a.global_position), carriage_a.get_parent().name])
	var hatch: Array = []
	var fixed: Array = []
	var allm: Array = []
	_meshes_under(armor_mesh, allm)
	for m in allm:
		if carriage_a != null and _under_carriage(m, carriage_a):
			hatch.append(m)
		else:
			fixed.append(m)
	for m in hatch:
		print("HatchArmor %s loc=%s g=%s" % [m.name, str((m as Node3D).position), str((m as Node3D).global_position)])
	# Value snapshots (node refs alone would alias post-pose transforms).
	var pre_locals := {}
	var pre_globals := {}
	for m in hatch + fixed:
		pre_locals[m] = (m as Node3D).transform
		pre_globals[m] = (m as Node3D).global_position
	return {"frame": frame_mesh, "armor": armor_mesh, "cf": carriage_f, "ca": carriage_a,
		"hatch": hatch, "fixed": fixed, "pre_locals": pre_locals, "pre_globals": pre_globals}


func _check_cycles() -> void:
	# 5x open/close: carriage pose deterministic, armor-local stable (no drift).
	var snap0 := _snapshot("closed-0")
	_check(snap0["ca"] != null, "armor motion owner exists")
	if snap0["ca"] == null:
		return
	var base_local := {}
	for m in snap0["hatch"]:
		base_local[m] = _in_carriage_space(m, snap0["ca"])
	for i in range(5):
		_pmm.set_cockpit_open(true, false)
		await get_tree().process_frame
		var sn := _snapshot("open-%d" % (i + 1))
		_check((sn["ca"] as Node3D).position.is_equal_approx(PMM_SCRIPT.HATCH_OPEN_POS),
			"cycle %d: armor carriage reaches open pose" % (i + 1))
		_check((sn["cf"] as Node3D).position.is_equal_approx(PMM_SCRIPT.HATCH_OPEN_POS),
			"cycle %d: frame carriage reaches open pose" % (i + 1))
		for m in sn["hatch"]:
			if base_local.has(m):
				var d: float = _in_carriage_space(m, sn["ca"]).origin.distance_to((base_local[m] as Transform3D).origin)
				_check(d < 0.003, "cycle %d: %s local-to-owner stable (%.4f)" % [i + 1, (m as Node).name, d])
		_pmm.set_cockpit_open(false, false)
		await get_tree().process_frame
		var sc := _snapshot("closed-%d" % (i + 1))
		_check((sc["ca"] as Node3D).position.is_equal_approx(Vector3.ZERO),
			"cycle %d: armor carriage returns closed" % (i + 1))
		for m in sc["hatch"]:
			if base_local.has(m):
				var d2: float = _in_carriage_space(m, sc["ca"]).origin.distance_to((base_local[m] as Transform3D).origin)
				_check(d2 < 0.003, "cycle %d: %s no drift after close (%.4f)" % [i + 1, (m as Node).name, d2])


func _check_follow() -> void:
	# Hatch armor globals must travel with the carriage; fixed armor stays.
	var s0 := _snapshot("follow-closed")
	# Carriage pose must be captured as a VALUE before opening — s0["ca"] is a
	# live node reference and would read the OPEN pose after set_cockpit_open
	# (same aliasing trap as the mesh arrays' pre_globals value snapshots).
	var ca0_global: Transform3D = (s0["ca"] as Node3D).global_transform
	_pmm.set_cockpit_open(true, false)
	await get_tree().process_frame
	await get_tree().process_frame
	var s1 := _snapshot("follow-open")
	var dc: float = (s1["ca"] as Node3D).global_position.distance_to(ca0_global.origin)
	_check(dc > 0.3, "carriage travels on open (%.3f)" % dc)
	for m in s1["hatch"]:
		var dm: float = (m as Node3D).global_position.distance_to(s0["pre_globals"][m] as Vector3)
		_check(dm > 0.3, "%s follows hatch (moved %.3f)" % [(m as Node).name, dm])
		var before_owner: Vector3 = ca0_global.affine_inverse() * (s0["pre_globals"][m] as Vector3)
		var dl: float = _in_carriage_space(m, s1["ca"]).origin.distance_to(before_owner)
		_check(dl < 0.05, "%s keeps local relation to owner (%.4f)" % [(m as Node).name, dl])
	for m in s1["fixed"]:
		var dd: float = (m as Node3D).transform.origin.distance_to(((s0["pre_locals"][m] as Transform3D)).origin)
		_check(dd < 0.003, "fixed %s static during open" % (m as Node).name)
	_pmm.set_cockpit_open(false, false)
	await get_tree().process_frame
	# Deterministic return is proven bob-independently in _check_cycles
	# (carriage local == ZERO and armor-local stable across 5 cycles).
	_snapshot("follow-reclosed")


func _check_replacement() -> void:
	for step in [["B", "res://resources/mech/parts/body/body_003_valkyrion.tres"],
			["A2", "res://resources/mech/parts/body/body_valkyrion.tres"]]:
		_equip_body(step[1])
		await get_tree().process_frame
		var sn := _snapshot("equip-%s-closed" % step[0])
		_check(sn["ca"] != null, "equip %s: armor motion owner exists" % step[0])
		if sn["ca"] == null:
			continue
		_check((sn["ca"] as Node).get_parent() == sn["armor"], "equip %s: owner under ArmorMesh" % step[0])
		_pmm.set_cockpit_open(true, false)
		await get_tree().process_frame
		_check((sn["ca"] as Node3D).position.is_equal_approx(PMM_SCRIPT.HATCH_OPEN_POS),
			"equip %s: replacement armor follows open" % step[0])
		_pmm.set_cockpit_open(false, false)
		await get_tree().process_frame
		_check((sn["ca"] as Node3D).position.is_equal_approx(Vector3.ZERO),
			"equip %s: replacement armor returns closed" % step[0])


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
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
	_mech = load("res://scenes/mecha/mecha_base.tscn").instantiate()
	_mech.position = Vector3(0, 10, 0)
	add_child(_mech)
	var frames := 0
	while not _mech.is_on_floor() and frames < 180:
		await get_tree().physics_frame
		frames += 1
	_pmm = _mech.get_node_or_null("PartMeshManager")
	_check(_pmm != null, "PartMeshManager present")
	if _pmm == null:
		get_tree().quit(1)
		return
	# Armor A (Valkyrion Prime).
	_equip_body("res://resources/mech/parts/body/body_valkyrion.tres")
	await get_tree().process_frame
	var s := _snapshot("equip-A-closed")
	_check(s["ca"] != null, "equip A: armor motion owner exists")
	_check((s["hatch"] as Array).size() >= 1, "equip A: hatch-zone armor classified under owner")
	if s["ca"] != null and (s["hatch"] as Array).size() >= 1:
		_check((s["ca"] as Node).get_parent() == s["armor"], "owner parented under ArmorMesh (not Body root)")
		# Closed sanity: no kilometer-scale offsets anywhere on the armor.
		var body: Node3D = _mech.get_node_or_null("Body")
		for m in (s["hatch"] as Array) + (s["fixed"] as Array):
			var dd: float = (m as Node3D).global_position.distance_to(body.global_position)
			_check(dd < 3.0, "closed %s sane bounds (%.2f from Body)" % [(m as Node).name, dd])
		await _check_cycles()
		await _check_follow()
	await _check_replacement()
	_mech.queue_free()
	print("VALKREN_HATCH_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("VALKREN_HATCH_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_VALKREN_HATCH_TESTS_PASSED")
		get_tree().quit(0)
