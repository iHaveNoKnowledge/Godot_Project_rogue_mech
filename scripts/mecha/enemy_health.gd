extends MechaHealthBase


func _init_parts() -> void:
	parts = {
		"body": {
			"armor_hp": 100.0, "max_armor": 100.0, "armor_class": 0.8,
			"frame_hp": 100.0, "max_frame": 100.0,
			"armor_broken": false, "destroyed": false, "mesh": null
		},
	}
	is_player = false


func _find_meshes() -> void:
	var node = get_node_or_null("../BodyMesh")
	if node:
		parts["body"]["mesh"] = node
		_original_colors["body"] = node.material_override.albedo_color if node.material_override else Color(0.8, 0.2, 0.2, 1)
