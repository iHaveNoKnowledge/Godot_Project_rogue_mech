extends SceneTree

func _init() -> void:
	print("=== Running Modular Part Verification ===")
	
	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	if not mecha_scene:
		printerr("FAIL: Could not load mecha_base.tscn")
		quit(1)
		return
		
	var mecha = mecha_scene.instantiate()
	root.add_child(mecha)
	
	var part_manager = mecha.get_node_or_null("PartMeshManager")
	if not part_manager:
		printerr("FAIL: PartMeshManager not found")
		quit(1)
		return
		
	var slots = ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]
	var packs = ["scout", "line", "vanguard"]
	
	for pack in packs:
		print("Testing Pack: ", pack)
		for slot in slots:
			var tres_path = "res://resources/mech/parts/%s/%s_%s.tres" % [slot, pack, slot]
			var part: ArmorPart = load(tres_path)
			if not part:
				printerr("FAIL: Could not load part resource: ", tres_path)
				quit(1)
				return
			
			part_manager.initialize_slot(slot, part, false)
			print(" -> Initialized slot: %s with part: %s (HP: %f, Armor: %f)" % [slot, part.part_name, part.max_hp, part.armor_class])
			
	print("=== ALL MODULAR PARTS VERIFIED SUCCESSFULLY! ===")
	quit(0)
