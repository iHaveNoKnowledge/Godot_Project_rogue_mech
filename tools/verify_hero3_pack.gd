extends SceneTree

func _init() -> void:
	print("=== Verifying Hero3 Vanguard Pack ===")
	var fails := 0

	var scenes := {
		"head": ["res://scenes/mecha/parts/head/hero3_head.tscn"],
		"body": ["res://scenes/mecha/parts/body/hero3_body.tscn"],
		"arm_left": [
			"res://scenes/mecha/parts/arm_left/hero3_arm_left_upper.tscn",
			"res://scenes/mecha/parts/arm_left/hero3_arm_left_lower.tscn"],
		"arm_right": [
			"res://scenes/mecha/parts/arm_right/hero3_arm_right_upper.tscn",
			"res://scenes/mecha/parts/arm_right/hero3_arm_right_lower.tscn"],
		"leg_left": [
			"res://scenes/mecha/parts/leg_left/hero3_leg_left_upper.tscn",
			"res://scenes/mecha/parts/leg_left/hero3_leg_left_lower.tscn"],
		"leg_right": [
			"res://scenes/mecha/parts/leg_right/hero3_leg_right_upper.tscn",
			"res://scenes/mecha/parts/leg_right/hero3_leg_right_lower.tscn"],
	}

	for slot: String in scenes:
		for path: String in scenes[slot]:
			var ps: PackedScene = load(path)
			if ps == null:
				print("FAIL load: ", path)
				fails += 1
				continue
			var inst: Node = ps.instantiate()
			var mi := _find_mesh(inst)
			if mi == null or mi.mesh == null:
				print("FAIL no mesh: ", path)
				fails += 1
				continue
			var surf: int = mi.mesh.get_surface_count() if mi.mesh is ArrayMesh else 1
			var aabb: AABB = mi.mesh.get_aabb()
			print("OK ", path, " surfaces=", surf, " size=", aabb.size)
			inst.queue_free()

	for slot: String in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
		var tpath := "res://resources/mech/parts/%s/hero3_%s.tres" % [slot, slot]
		var part: Resource = load(tpath)
		if part == null:
			print("FAIL tres load: ", tpath)
			fails += 1
			continue
		if part.get("slot_id") != slot:
			print("FAIL slot mismatch: ", tpath)
			fails += 1
			continue
		if part.get("mesh_scene") == null:
			print("FAIL no mesh_scene: ", tpath)
			fails += 1
			continue
		print("OK tres ", tpath, " hp=", part.get("max_hp"))

	var catalog: Resource = load("res://resources/data/mech_catalogs.tres")
	var found := 0
	for slot: String in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
		for entry in catalog.get("armor_catalog")[slot]:
			if entry.get("id") == "hero3_" + slot:
				found += 1
	print("catalog hero3 entries: ", found, "/6")
	if found != 6:
		fails += 1

	if fails == 0:
		print("=== HERO3 VERIFY: ALL PASS ===")
	else:
		print("=== HERO3 VERIFY: ", fails, " FAILURES ===")
	quit(fails)

func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c: Node in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null
