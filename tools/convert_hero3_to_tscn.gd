extends SceneTree

func _init() -> void:
	print("=== Converting Hero3 GLBs to native Godot PackedScene (.tscn) ===")

	var files := [
		"res://scenes/mecha/parts/head/hero3_head.glb",
		"res://scenes/mecha/parts/body/hero3_body.glb",
		"res://scenes/mecha/parts/arm_left/hero3_arm_left_upper.glb",
		"res://scenes/mecha/parts/arm_left/hero3_arm_left_lower.glb",
		"res://scenes/mecha/parts/arm_right/hero3_arm_right_upper.glb",
		"res://scenes/mecha/parts/arm_right/hero3_arm_right_lower.glb",
		"res://scenes/mecha/parts/leg_left/hero3_leg_left_upper.glb",
		"res://scenes/mecha/parts/leg_left/hero3_leg_left_lower.glb",
		"res://scenes/mecha/parts/leg_right/hero3_leg_right_upper.glb",
		"res://scenes/mecha/parts/leg_right/hero3_leg_right_lower.glb"
	]

	for glb_path: String in files:
		var gltf := GLTFDocument.new()
		var state := GLTFState.new()
		var err := gltf.append_from_file(glb_path, state)
		if err != OK:
			print("ERROR: Failed to append GLTF from ", glb_path, " code=", err)
			continue
		var scene_node: Node = gltf.generate_scene(state)
		if scene_node == null:
			print("ERROR: Failed to generate scene for ", glb_path)
			continue

		_set_owner_recursive(scene_node, scene_node)

		var packed := PackedScene.new()
		var pack_err := packed.pack(scene_node)
		if pack_err != OK:
			print("ERROR: Failed to pack scene for ", glb_path, " code=", pack_err)
			continue

		var tscn_path: String = glb_path.replace(".glb", ".tscn")
		var save_err := ResourceSaver.save(packed, tscn_path)
		if save_err != OK:
			print("ERROR: Failed to save ", tscn_path, " code=", save_err)
		else:
			print("SUCCESS: Converted ", glb_path, " -> ", tscn_path)

	print("=== Done Converting GLBs ===")
	quit(0)

func _set_owner_recursive(node: Node, root_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = root_node
		_set_owner_recursive(child, root_node)
