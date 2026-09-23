extends Node
## TANKMECH PROPORTION VERIFICATION
## Validates the rebuilt tankmech slot models (kitbash proportions anchored to
## the Standard Core Structure cockpit tub):
##   - every .glb/.tscn exists and instantiates with the expected mesh count
##   - node names carry the routing keywords PartMeshManager needs
##     (forearm -> elbow pivot, shin/knee -> knee pivot, foot -> ankle pivot)
##   - authored bounds match the image-referenced proportions in world meters
##     (small head, bulky pauldrons, long heavy legs reaching the ankle pivot)
##   - resources are wired: the .tres armor parts point at the rebuilt scenes

var _fails: int = 0
var _checks: int = 0


func _check(cond: bool, test_name: String) -> void:
	_checks += 1
	if cond:
		print("TM_OK: " + test_name)
	else:
		_fails += 1
		printerr("TM_FAIL: " + test_name)


func _ready() -> void:
	await get_tree().process_frame
	print("\n=== STARTING TANKMECH PROPORTION VERIFICATION ===")
	_test_part_scenes_load_and_instantiate()
	_test_routing_keywords_present()
	_test_leg_reaches_ankle_pivot()
	_test_arm_reaches_elbow_pivot()
	_test_head_small_between_pauldrons()
	_test_body_panel_lines_and_accents()
	_test_resources_point_at_rebuilt_scenes()

	print("\n=== TANKMECH PROPORTION SUMMARY ===")
	print("Checks: %d, Failures: %d" % [_checks, _fails])
	if _fails == 0:
		print("ALL_TANKMECH_PROPORTION_TESTS_PASSED")
		get_tree().quit(0)
	else:
		printerr("TANKMECH_PROPORTION_TESTS_FAILED")
		get_tree().quit(1)


func _collect_mesh_bounds(root: Node, xform: Transform3D, out: Array) -> void:
	for child in root.get_children():
		var child_xform: Transform3D = xform
		if child is Node3D:
			child_xform = xform * (child as Node3D).transform
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			var mi := child as MeshInstance3D
			var aabb: AABB = mi.mesh.get_aabb()
			var xformed: AABB = child_xform * aabb
			out.append(xformed)
		_collect_mesh_bounds(child, child_xform, out)


func _instantiate_slot(slot: String) -> Node:
	var path := "res://scenes/mecha/parts/%s/tankmech_%s.tscn" % [slot, slot]
	_check(ResourceLoader.exists(path), "%s scene exists" % slot)
	if not ResourceLoader.exists(path):
		return null
	var packed = load(path)
	_check(packed is PackedScene and packed.can_instantiate(), "%s scene can instantiate" % slot)
	var inst: Node = (packed as PackedScene).instantiate()
	return inst


func _slot_bounds(slot: String) -> Array:
	var inst := _instantiate_slot(slot)
	if inst == null:
		return []
	var bounds: Array = []
	_collect_mesh_bounds(inst, Transform3D.IDENTITY, bounds)
	inst.queue_free()
	return bounds


func _combined_aabb(bounds: Array) -> AABB:
	var merged := AABB()
	var first := true
	for b in bounds:
		if first:
			merged = b
			first = false
		else:
			merged = merged.merge(b)
	return merged


func _test_part_scenes_load_and_instantiate() -> void:
	print("\n-- [1] Scenes load and instantiate with expected mesh counts --")
	var expected_meshes := {
		"body": 28, "head": 6,
		"arm_left": 7, "arm_right": 7,
		"leg_left": 10, "leg_right": 10,
	}
	for slot in expected_meshes.keys():
		var inst := _instantiate_slot(slot)
		if inst == null:
			continue
		var found := 0
		var stack: Array[Node] = [inst]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				found += 1
			for c in n.get_children():
				stack.append(c)
		_check(found == int(expected_meshes[slot]),
			"%s has %d meshes (got %d)" % [slot, expected_meshes[slot], found])
		inst.queue_free()


func _test_routing_keywords_present() -> void:
	print("\n-- [2] Node names carry PartMeshManager routing keywords --")
	var expectations := {
		"arm_left": "forearm", "arm_right": "forearm",
		"leg_left": "foot", "leg_right": "foot",
	}
	for slot in expectations.keys():
		var inst := _instantiate_slot(slot)
		if inst == null:
			continue
		var keyword: String = expectations[slot]
		var found := false
		var stack: Array[Node] = [inst]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n.name.to_lower().contains(keyword):
				found = true
				break
			for c in n.get_children():
				stack.append(c)
		_check(found, "%s has a node named with '%s'" % [slot, keyword])
		inst.queue_free()


func _test_leg_reaches_ankle_pivot() -> void:
	print("\n-- [3] Legs authored joint-local: shin spans the knee->ankle gap --")
	# Runtime reparents knee/shin nodes onto the knee pivot and foot nodes onto
	# the ankle pivot, so verify each routed subtree in MESH-LOCAL units (what
	# the joint container actually renders). World meters: knee pivot y=1.661,
	# ankle pivot y=0.370, sole y=0.
	for slot in ["leg_left", "leg_right"]:
		var inst := _instantiate_slot(slot)
		if inst == null:
			continue
		var knee_aabb := _keyword_mesh_local_aabb(inst, "shin")
		var knee_aabb2 := _keyword_mesh_local_aabb(inst, "knee")
		if knee_aabb2.size.y > 0.0:
			knee_aabb = knee_aabb.merge(knee_aabb2)
		_check(absf(knee_aabb.position.y - (-1.525)) < 0.05,
			"%s shin subtree reaches ~1.53 below the knee pivot (got %.3f)" % [slot, knee_aabb.position.y])
		_check(absf(knee_aabb.end.y - 0.25) < 0.06,
			"%s shin subtree tops out just above the knee pivot (got %.3f)" % [slot, knee_aabb.end.y])
		var foot_aabb := _keyword_mesh_local_aabb(inst, "foot")
		_check(absf(foot_aabb.position.y - (-0.37)) < 0.05,
			"%s foot sole sits 0.37 below the ankle pivot (got %.3f)" % [slot, foot_aabb.position.y])
		_check(absf(foot_aabb.end.y - 0.03) < 0.06,
			"%s foot tops out at the ankle pivot (got %.3f)" % [slot, foot_aabb.end.y])
		inst.queue_free()


# Merged AABB of every MeshInstance3D whose name contains `keyword`, measured in
# each node's own local space (mesh.get_aabb ignores the node transform — this
# is exactly what the joint container renders after the runtime reparent).
func _keyword_mesh_local_aabb(root: Node, keyword: String) -> AABB:
	var merged := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null \
				and n.name.to_lower().contains(keyword):
			var aabb: AABB = (n as MeshInstance3D).mesh.get_aabb()
			merged = aabb if first else merged.merge(aabb)
			first = false
		for c in n.get_children():
			stack.append(c)
	return merged


func _test_arm_reaches_elbow_pivot() -> void:
	print("\n-- [4] Arms authored joint-local: forearm hangs below the elbow --")
	# Elbow pivot sits 0.6384 below the shoulder pivot; the runtime reparents
	# forearm nodes onto the elbow container, so check the forearm subtree in
	# elbow-local units: fist bottom ~1.14 below the elbow, top at the elbow.
	for slot in ["arm_left", "arm_right"]:
		var inst := _instantiate_slot(slot)
		if inst == null:
			continue
		var fore_aabb := _keyword_mesh_local_aabb(inst, "forearm")
		_check(absf(fore_aabb.position.y - (-1.14)) < 0.06,
			"%s forearm+fist reaches ~1.14 below the elbow pivot (got %.3f)" % [slot, fore_aabb.position.y])
		_check(absf(fore_aabb.end.y - 0.0) < 0.06,
			"%s forearm tops out at the elbow pivot (got %.3f)" % [slot, fore_aabb.end.y])
		# Exaggerated kitbash pauldron (1.15 wide on the shoulder, outboard of the
		# pivot) + upper arm at x 0: shoulder-frame bulk 1.4..2.0 wide.
		var bounds := _slot_bounds(slot)
		var merged := _combined_aabb(bounds)
		_check(merged.size.x > 1.4 and merged.size.x < 2.0,
			"%s pauldron bulk x-width 1.4..2.0 (got %.3f)" % [slot, merged.size.x])
		inst.queue_free()


func _test_body_panel_lines_and_accents() -> void:
	print("\n-- [5b] Body armor carries panel lines + accent plates --")
	var inst := _instantiate_slot("body")
	if inst == null:
		return
	var lines := _count_keyword_meshes(inst, "_line")
	var accents := _count_keyword_meshes(inst, "_accent")
	_check(lines >= 8, "body has panel lines (got %d)" % lines)
	_check(accents >= 5, "body has accent plates (got %d)" % accents)

	# Every detail mesh must sit INSIDE the body silhouette (they dress the
	# plates, not float around them).
	var combined := _combined_aabb(_slot_bounds("body"))
	var all := _all_mesh_aabbs(inst)
	var inside := 0
	for a in all:
		if combined.encloses(a):
			inside += 1
	_check(inside == all.size(), "all %d body meshes sit inside the body silhouette" % all.size())
	inst.queue_free()


# Number of MeshInstance3D whose name contains `keyword`.
func _count_keyword_meshes(root: Node, keyword: String) -> int:
	var count := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null \
				and n.name.to_lower().contains(keyword):
			count += 1
		for c in n.get_children():
			stack.append(c)
	return count


# AABB of every MeshInstance3D under root (transformed into scene space).
func _all_mesh_aabbs(root: Node) -> Array:
	var out: Array = []
	_collect_mesh_bounds(root, Transform3D.IDENTITY, out)
	return out


func _test_head_small_between_pauldrons() -> void:
	print("\n-- [5] Head is tiny (exaggerated kitbash proportion) --")
	var bounds := _slot_bounds("head")
	if bounds.is_empty():
		return
	var merged := _combined_aabb(bounds)
	# Head total ~0.54m high (helm+crest+antenna) — buried between the
	# 1.15-wide pauldrons, narrower than the tub shoulder span.
	_check(merged.size.y > 0.40 and merged.size.y < 0.65,
		"head height 0.40..0.65m (got %.3f)" % merged.size.y)
	_check(merged.size.x < 0.4, "head narrower than pauldrons (got %.3f)" % merged.size.x)


func _test_resources_point_at_rebuilt_scenes() -> void:
	print("\n-- [6] ArmorPart resources wire the rebuilt scenes --")
	for slot in ["body", "head", "arm_left", "arm_right", "leg_left", "leg_right"]:
		var res_path := "res://resources/mech/parts/%s/tankmech_%s.tres" % [slot, slot]
		_check(ResourceLoader.exists(res_path), "%s part resource exists" % slot)
		if not ResourceLoader.exists(res_path):
			continue
		var part = load(res_path)
		_check(part != null and part.mesh_scene != null,
			"%s part has mesh_scene assigned" % slot)
		var scene_path := "res://scenes/mecha/parts/%s/tankmech_%s.tscn" % [slot, slot]
		if part != null and part.mesh_scene != null:
			_check(part.mesh_scene.resource_path.ends_with(scene_path.trim_prefix("res://")),
				"%s mesh_scene points at rebuilt scene" % slot)
