extends MechaHealthBase


func _init_parts() -> void:
	parts = {
		"head": {
			"armor_hp": 40.0, "max_armor": 40.0, "armor_class": 1.0,
			"frame_hp": 30.0, "max_frame": 30.0,
			"armor_broken": false, "destroyed": false, "mesh": null
		},
		"body": {
			"armor_hp": 80.0, "max_armor": 80.0, "armor_class": 0.9,
			"frame_hp": 60.0, "max_frame": 60.0,
			"armor_broken": false, "destroyed": false, "mesh": null
		},
		"arm_left": {
			"armor_hp": 30.0, "max_armor": 30.0, "armor_class": 0.8,
			"frame_hp": 20.0, "max_frame": 20.0,
			"armor_broken": false, "destroyed": false, "mesh": null
		},
		"arm_right": {
			"armor_hp": 30.0, "max_armor": 30.0, "armor_class": 0.8,
			"frame_hp": 20.0, "max_frame": 20.0,
			"armor_broken": false, "destroyed": false, "mesh": null
		},
		"leg_left": {
			"armor_hp": 40.0, "max_armor": 40.0, "armor_class": 0.7,
			"frame_hp": 30.0, "max_frame": 30.0,
			"armor_broken": false, "destroyed": false, "mesh": null
		},
		"leg_right": {
			"armor_hp": 40.0, "max_armor": 40.0, "armor_class": 0.7,
			"frame_hp": 30.0, "max_frame": 30.0,
			"armor_broken": false, "destroyed": false, "mesh": null
		},
	}
	is_player = false


func _find_meshes() -> void:
	var mappings = {
		"head": "../Head/HeadMesh",
		"body": "../Body/BodyMesh",
		"arm_left": "../ArmLeft/ArmLeftMesh",
		"arm_right": "../ArmRight/ArmRightMesh",
		"leg_left": "../LegLeft/LegLeftMesh",
		"leg_right": "../LegRight/LegRightMesh",
	}
	for slot in mappings:
		var node = get_node_or_null(mappings[slot])
		if node:
			parts[slot]["mesh"] = node
			_original_colors[slot] = node.material_override.albedo_color if node.material_override else Color(0.8, 0.2, 0.2, 1)
