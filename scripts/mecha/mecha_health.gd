extends MechaHealthBase


func _init_parts() -> void:
	parts = {
		"head": {
			"armor_hp": 30.0, "max_armor": 30.0, "armor_class": 1.2,
			"frame_hp": 20.0, "max_frame": 20.0,
			"armor_broken": false, "destroyed": false, "mesh": null
		},
		"body": {
			"armor_hp": 60.0, "max_armor": 60.0, "armor_class": 1.0,
			"frame_hp": 40.0, "max_frame": 40.0,
			"armor_broken": false, "destroyed": false, "mesh": null
		},
		"arm_left": {
			"armor_hp": 25.0, "max_armor": 25.0, "armor_class": 0.9,
			"frame_hp": 15.0, "max_frame": 15.0,
			"armor_broken": false, "destroyed": false, "mesh": null
		},
		"arm_right": {
			"armor_hp": 25.0, "max_armor": 25.0, "armor_class": 0.9,
			"frame_hp": 15.0, "max_frame": 15.0,
			"armor_broken": false, "destroyed": false, "mesh": null
		},
		"leg_left": {
			"armor_hp": 30.0, "max_armor": 30.0, "armor_class": 0.8,
			"frame_hp": 20.0, "max_frame": 20.0,
			"armor_broken": false, "destroyed": false, "mesh": null
		},
		"leg_right": {
			"armor_hp": 30.0, "max_armor": 30.0, "armor_class": 0.8,
			"frame_hp": 20.0, "max_frame": 20.0,
			"armor_broken": false, "destroyed": false, "mesh": null
		},
	}

	for slot in parts:
		if GlobalData.equipped_frames.has(slot):
			var f = GlobalData.equipped_frames[slot]
			var f_hp = f.get("hp", parts[slot]["max_frame"])
			parts[slot]["frame_hp"] = f_hp
			parts[slot]["max_frame"] = f_hp

		if GlobalData.equipped_parts.has(slot):
			var p = GlobalData.equipped_parts[slot]
			if p and p.get("max_hp") != null:
				parts[slot]["armor_hp"] = p.max_hp
				parts[slot]["max_armor"] = p.max_hp
			if p and p.get("armor_class") != null:
				parts[slot]["armor_class"] = p.armor_class

	is_player = true


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
			_original_colors[slot] = node.material_override.albedo_color if node.material_override else _armor_color


func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if is_destroyed:
		return
	# Shield absorption
	var wm = _get_weapon_manager()
	if wm and wm.is_shield_active():
		amount = wm.absorb_damage_with_shield(amount)
		if amount <= 0.0:
			return
	super.take_damage(amount, damage_type)


func take_damage_to_part(slot_name: String, amount: float, damage_type: String = "kinetic") -> void:
	if is_destroyed:
		return
	# Shield absorption
	var wm = _get_weapon_manager()
	if wm and wm.is_shield_active():
		amount = wm.absorb_damage_with_shield(amount)
		if amount <= 0.0:
			return
	super.take_damage_to_part(slot_name, amount, damage_type)


func _get_weapon_manager():
	var mecha = get_parent()
	if mecha:
		return mecha.get_node_or_null("WeaponManager")
	return null
