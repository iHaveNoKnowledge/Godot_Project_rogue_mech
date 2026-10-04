extends Node
## HAND ASSEMBLY VERIFY — modular manipulator visual (no new joints).
##
## Pins the procedural hand contract from the hand/wrist audit:
##  1. Each Forearm container carries palm + 4 fingers + thumb (visual only).
##  2. Continuous chain wrist stub -> palm -> fingers (no floating gaps).
##  3. The variant-aware hand mount lands inside the palm span (grip).
##  4. Thumbs mirror L/R; structure identical across frame variants.
##  5. No new pivots, no animation/mount/combat changes (covered by suites).

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("HAND OK: " + name)
	else:
		_fails += 1
		printerr("HAND FAIL: " + name)


func _freeze(n: Node) -> void:
	n.set_process(false)
	n.set_physics_process(false)
	for c in n.get_children():
		_freeze(c)


func _hand_parts(container: Node) -> Dictionary:
	var out := {"palm": null, "fingers": [], "thumb": null}
	if container == null:
		return out
	for c in container.get_children():
		if not (c is MeshInstance3D):
			continue
		var n := String((c as Node).name)
		if n == "HandPalm":
			out["palm"] = c
		elif n.begins_with("HandFinger"):
			(out["fingers"] as Array).append(c)
		elif n == "HandThumb":
			out["thumb"] = c
	return out


func _local_aabb(mi: MeshInstance3D) -> AABB:
	return (mi as Node3D).transform * (mi.mesh as BoxMesh).get_aabb() if mi != null and mi.mesh is BoxMesh else AABB()


func _build_arms(vid: String) -> Array:
	var scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mech: Node3D = scene.instantiate()
	if vid != "":
		FrameVariantResolver.apply_variant(mech, vid)
	_freeze(mech)
	add_child(mech)
	_freeze(mech)
	return [mech]


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var pmm_owner := _build_arms("")
	var mech: Node3D = pmm_owner[0]
	var pmm = mech.get_node_or_null("PartMeshManager")
	_check(pmm != null, "PartMeshManager exists")
	for slot in ["arm_left", "arm_right"]:
		var part := ArmorPart.new()
		part.slot_id = slot
		pmm.initialize_slot(slot, part, false)
	await get_tree().process_frame
	_test_structure(pmm)
	_test_chain(pmm)
	_test_grip(pmm, mech)
	_test_mirror(pmm)
	await _test_variants()
	await _test_coexistence(mech)
	mech.queue_free()
	await get_tree().process_frame
	print("HAND_ASSEMBLY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("HAND_ASSEMBLY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_HAND_ASSEMBLY_TESTS_PASSED")
		get_tree().quit(0)


# --- 1. structure -----------------------------------------------------------------
func _test_structure(pmm: Node) -> void:
	for slot in ["arm_left", "arm_right"]:
		var entry: Dictionary = pmm.slot_meshes.get(slot, {})
		var hp := _hand_parts(entry.get("frame_lower"))
		_check(hp["palm"] != null, slot + " palm present")
		_check((hp["fingers"] as Array).size() == 4, slot + " has 4 fingers")
		_check(hp["thumb"] != null, slot + " thumb present")
		# No new pivots: hand pieces are meshes under the Forearm container.
		var pivots := 0
		for c in (entry.get("frame_lower") as Node).get_children():
			if c is Node3D and not (c is MeshInstance3D):
				pivots += 1
		_check(pivots == 0, slot + " adds no pivots (meshes only)")


# --- 2. continuous chain, no gaps ----------------------------------------------------
func _test_chain(pmm: Node) -> void:
	for slot in ["arm_left", "arm_right"]:
		var entry: Dictionary = pmm.slot_meshes.get(slot, {})
		var cont: Node3D = entry.get("frame_lower")
		var stub: MeshInstance3D = null
		for c in cont.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh:
				var s: Vector3 = ((c as MeshInstance3D).mesh as BoxMesh).size
				# Unnamed wrist stub block authored as (0.20, 0.18, 0.22).
				if s.is_equal_approx(Vector3(0.20, 0.18, 0.22)):
					stub = c
		_check(stub != null, slot + " wrist stub retained")
		var hp := _hand_parts(cont)
		# AABB.position.y = lowest point, .end.y = highest (Y-up, parts hang down).
		var stub_low: float = _local_aabb(stub).position.y
		var palm_high: float = _local_aabb(hp["palm"]).end.y
		# Overlap of at least 5mm: stub bottom -0.56, palm top -0.55.
		var ov: float = palm_high - stub_low
		_check(ov >= 0.005 and ov <= 0.05, slot + " palm overlaps wrist stub (no gap, ov=%.3f)" % ov)
		var palm_low: float = _local_aabb(hp["palm"]).position.y
		var finger_low := 999.0
		for f in (hp["fingers"] as Array):
			finger_low = minf(finger_low, _local_aabb(f).position.y)
		_check(finger_low < palm_low, slot + " fingers extend below palm (gripping mass)")


# --- 3. mount lands inside the palm -----------------------------------------------------
func _test_grip(pmm: Node, mech: Node3D) -> void:
	var entry: Dictionary = pmm.slot_meshes.get("arm_left", {})
	var hp := _hand_parts(entry.get("frame_lower"))
	var palm_box := _local_aabb(hp["palm"])
	var mount: Vector3 = FrameVariantResolver.hand_mount_local_for(mech)
	_check(mount.y >= palm_box.position.y and mount.y <= palm_box.end.y, "variant hand mount y=%.3f inside palm span [%.3f, %.3f]" % [mount.y, palm_box.position.y, palm_box.end.y])
	_check(absf(mount.x) <= palm_box.size.x, "mount centered over palm width")


# --- 4. mirror --------------------------------------------------------------------------------
func _test_mirror(pmm: Node) -> void:
	var el: Dictionary = pmm.slot_meshes.get("arm_left", {})
	var er: Dictionary = pmm.slot_meshes.get("arm_right", {})
	var tl: Node3D = (_hand_parts(el.get("frame_lower"))["thumb"] as Node3D)
	var tr: Node3D = (_hand_parts(er.get("frame_lower"))["thumb"] as Node3D)
	_check(tl != null and tr != null and tl.position.x < 0.0 and tr.position.x > 0.0, "thumbs on outer sides")
	_check(absf(absf(tl.position.x) - absf(tr.position.x)) < 0.0001, "thumbs mirrored exactly")
	var pl: BoxMesh = (_hand_parts(el.get("frame_lower"))["palm"] as MeshInstance3D).mesh
	var pr: BoxMesh = (_hand_parts(er.get("frame_lower"))["palm"] as MeshInstance3D).mesh
	_check((pl.size as Vector3).is_equal_approx(pr.size), "palms identical L/R")


# --- 5. variants carry the same structure --------------------------------------------------
func _test_variants() -> void:
	for vid in ["heavy", "extended"]:
		var holder := _build_arms(vid)
		var mech: Node3D = holder[0]
		var pmm = mech.get_node_or_null("PartMeshManager")
		for slot in ["arm_left", "arm_right"]:
			var part := ArmorPart.new()
			part.slot_id = slot
			pmm.initialize_slot(slot, part, false)
		await get_tree().process_frame
		var ok := true
		for slot in ["arm_left", "arm_right"]:
			var entry: Dictionary = pmm.slot_meshes.get(slot, {})
			var hp := _hand_parts(entry.get("frame_lower"))
			if hp["palm"] == null or (hp["fingers"] as Array).size() != 4 or hp["thumb"] == null:
				ok = false
		_check(ok, vid + " variant carries identical hand structure (via pivots, no new data)")
		mech.queue_free()
		await get_tree().process_frame


# --- 6. weapon coexistence ------------------------------------------------------------------
func _test_coexistence(mech: Node3D) -> void:
	var w := WeaponPart.new()
	w.weapon_type = WeaponPart.WeaponType.BEAM_RIFLE
	var mount = WeaponVisualFactory.mount_hand(mech, "left", w, "HandCoex")
	_check((mount as Node3D).position.is_equal_approx(WeaponVisualFactory.HAND_FOREARM_POS), "rifle mount local unchanged with hand present")
	_check(WeaponVisualFactory.find_muzzle_node(mount) != null, "rifle muzzle resolves with hand present")
	var blade := WeaponPart.new()
	blade.weapon_type = WeaponPart.WeaponType.MELEE
	blade.weapon_name = "Heat Blade"
	var mount2 = WeaponVisualFactory.mount_hand(mech, "right", blade, "HandCoexBlade")
	_check(mount2 != null and WeaponVisualFactory.find_muzzle_node(mount2) != null, "melee coexists with hand (grip origin intact)")
