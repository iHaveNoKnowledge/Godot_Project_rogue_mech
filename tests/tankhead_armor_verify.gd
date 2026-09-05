extends Node3D

var _checks: int = 0
var _fails: int = 0

func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("TANKHEAD_OK: %s" % msg)
	else:
		_fails += 1
		print("TANKHEAD_FAIL: %s" % msg)

func _ready() -> void:
	print("=== Running Tankhead Armor Verification Test ===")
	
	# 1. Verify Catalog Entries
	var catalog_res = load("res://resources/data/mech_catalogs.tres")
	_check(catalog_res != null, "mech_catalogs.tres loaded")
	
	var slots := ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]
	if catalog_res != null:
		for slot in slots:
			var entries: Array = catalog_res.armor_catalog.get(slot, [])
			var found := false
			for entry in entries:
				if entry.get("id") == "tankhead_" + slot:
					found = true
					print("Catalog entry found: %s -> %s [%s]" % [entry.get("id"), entry.get("name"), entry.get("type")])
					break
			_check(found, "Catalog contains tankhead_" + slot)

	# 2. Verify Resource Loading & Meshes
	var parts: Dictionary = {}
	for slot in slots:
		var path := "res://resources/mech/parts/%s/tankhead_%s.tres" % [slot, slot]
		var part = load(path)
		_check(part != null, "ArmorPart resource exists: " + path)
		if part != null:
			parts[slot] = part
			_check(part.mesh_scene != null, "Part %s has valid mesh_scene" % slot)
			if slot in ["arm_left", "arm_right", "leg_left", "leg_right"]:
				_check(part.mesh_scene_lower != null, "Limb %s has valid mesh_scene_lower" % slot)

	# 3. Mount onto MechaBase
	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	_check(mecha_scene != null, "mecha_base.tscn loaded")
	if mecha_scene == null:
		_finish()
		return
		
	var mecha = mecha_scene.instantiate()
	add_child(mecha)
	
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	var pmm = mecha.get_node_or_null("PartMeshManager")
	_check(pmm != null, "PartMeshManager exists on MechaBase")
	if pmm == null:
		_finish()
		return
	
	# Initialize each slot with Tankhead part
	for slot in slots:
		var part: ArmorPart = parts.get(slot)
		if part != null:
			pmm.initialize_slot(slot, part, false)
			print("Initialized slot %s with %s" % [slot, part.part_name])
	
	await get_tree().process_frame
	
	# Verify attached meshes in PartMeshManager
	for slot in slots:
		var entry: Dictionary = pmm.slot_meshes.get(slot, {})
		var armor: Node3D = entry.get("armor")
		_check(armor != null and armor.get_child_count() > 0, "Slot %s has upper armor attached" % slot)
		
		if slot in ["arm_left", "arm_right", "leg_left", "leg_right"]:
			var armor_lo: Node3D = entry.get("armor_lower")
			_check(armor_lo != null and armor_lo.get_child_count() > 0, "Slot %s has lower armor attached" % slot)

	# Dump AABBs of all armor pieces
	print("--- Armor Mesh AABBs in World Space ---")
	_dump_and_verify_aabbs(mecha)
	
	_finish()

func _dump_and_verify_aabbs(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi: MeshInstance3D = node as MeshInstance3D
		var p_name: String = node.get_parent().name if node.get_parent() != null else ""
		var gpos: Vector3 = mi.global_position
		var aabb: AABB = mi.global_transform * mi.mesh.get_aabb()
		print("  Mesh [%s] parent=%s gpos=%s aabb_size=%s" % [mi.name, p_name, str(gpos), str(aabb.size)])
		_check(not (is_nan(aabb.size.x) or is_nan(aabb.size.y) or is_nan(aabb.size.z)), "AABB has no NaNs: %s" % mi.name)
		_check(aabb.size.length_squared() > 0.0001, "AABB is non-zero: %s" % mi.name)
	for child in node.get_children():
		_dump_and_verify_aabbs(child)

func _finish() -> void:
	print("=== Tankhead Verification Finished: %d checks, %d passed, %d failed ===" % [_checks, _checks - _fails, _fails])
	if _fails == 0:
		print("ALL_TANKHEAD_ARMOR_TESTS_PASSED")
		get_tree().quit(0)
	else:
		print("TANKHEAD_ARMOR_TESTS_FAILED")
		get_tree().quit(1)
