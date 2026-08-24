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
		# Apply HP from equipped inner frame (matching Hangar display which adds the upgrade bonus)
		if GlobalData.weapons.equipped_frames.has(slot):
			var f = GlobalData.weapons.equipped_frames[slot]
			var f_hp = f.get("hp", parts[slot]["max_frame"]) + LoadoutSystem.get_frame_upgrade_hp_bonus()
			parts[slot]["frame_hp"] = f_hp
			parts[slot]["max_frame"] = f_hp

		# Apply HP & armor_class from equipped outer armor
		if GlobalData.weapons.equipped_parts.has(slot):
			var p = GlobalData.weapons.equipped_parts[slot]
			if p and p.get("max_hp") != null:
				parts[slot]["armor_hp"] = p.max_hp
				parts[slot]["max_armor"] = p.max_hp
			elif p and p.get("hp") != null:
				parts[slot]["armor_hp"] = p.get("hp")
				parts[slot]["max_armor"] = p.get("hp")
			if p and p.get("armor_class") != null:
				parts[slot]["armor_class"] = p.armor_class
			elif p and p.get("armor") != null:
				# Dictionary format from hangar stores "armor" not "armor_class"
				parts[slot]["armor_class"] = maxf(p.get("armor", 10.0) / 10.0, 0.1)
			# Which attack type this plate defends against (heat/pierce/blunt).
			# Empty means a balanced plate that always uses its armor_class.
			if p and p.get("defense_type") != null:
				parts[slot]["defense_type"] = str(p.defense_type)

		# -----------------------------------------------------------------------
		# Scrap emergency patch: this slot was rebuilt from scrap in the
		# intermission screen, so it uses WEAKER scrap stats (scaled by the
		# driver's repair-skill tier) instead of the real armor plate. If the
		# real frame was destroyed, the scrap structure stands in for it.
		# -----------------------------------------------------------------------
		if GlobalData.weapons.scrap_patches.has(slot):
			var patch = GlobalData.weapons.scrap_patches[slot]
			var scrap_armor: float = patch.get("scrap_armor_hp", parts[slot]["max_armor"])
			parts[slot]["armor_hp"] = scrap_armor
			parts[slot]["max_armor"] = scrap_armor
			parts[slot]["armor_class"] = patch.get("armor_class", parts[slot]["armor_class"])
			if GlobalData.weapons.part_damage.get(slot + "_frame", 0.0) >= 1.0:
				var scrap_frame: float = patch.get("scrap_frame_hp", parts[slot]["max_frame"])
				parts[slot]["frame_hp"] = scrap_frame
				parts[slot]["max_frame"] = scrap_frame
			# The patch rebuilt the slot, so no persistent damage applies to it.
			GlobalData.weapons.part_damage.erase(slot)
			GlobalData.weapons.part_damage.erase(slot + "_frame")
			GlobalData.weapons.part_hit_meta.erase(slot)
			continue

		# -----------------------------------------------------------------------
		# Restore persistent damage from previous combat / Hangar session.
		# Armor damage key: "slot_name"       (ratio 0.0 = full, 1.0 = destroyed)
		# Frame damage key: "slot_name_frame" (ratio 0.0 = full, 1.0 = destroyed)
		# -----------------------------------------------------------------------
		var armor_dmg_ratio = GlobalData.weapons.part_damage.get(slot, 0.0)
		if armor_dmg_ratio > 0.0:
			var lost = parts[slot]["max_armor"] * clampf(armor_dmg_ratio, 0.0, 1.0)
			parts[slot]["armor_hp"] = maxf(parts[slot]["max_armor"] - lost, 0.0)
			if parts[slot]["armor_hp"] <= 0.0:
				parts[slot]["armor_broken"] = true
				parts[slot]["armor_hp"] = 0.0

		var frame_dmg_ratio = GlobalData.weapons.part_damage.get(slot + "_frame", 0.0)
		if frame_dmg_ratio > 0.0:
			var lost_f = parts[slot]["max_frame"] * clampf(frame_dmg_ratio, 0.0, 1.0)
			parts[slot]["frame_hp"] = maxf(parts[slot]["max_frame"] - lost_f, 0.0)
			if parts[slot]["frame_hp"] <= 0.0:
				parts[slot]["destroyed"] = true
				parts[slot]["frame_hp"] = 0.0

	is_player = true


func _find_meshes() -> void:
	for slot in GlobalData.MECHA_SLOTS:
		var node_name: String = GlobalData.SLOT_TO_NODE.get(slot, "")
		if node_name == "":
			continue
		var node = get_node_or_null("../" + node_name + "/" + node_name + "Mesh")
		if node:
			parts[slot]["mesh"] = node
			_original_colors[slot] = node.material_override.albedo_color if node.material_override else _armor_color


func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if is_destroyed:
		return
	# Shield absorption (passes the attack type so the plate's anti-type plating
	# decides the drain rate: 40% vs its own type, 100% vs the other two).
	var wm = _get_weapon_manager()
	if wm and wm.is_shield_active():
		amount = wm.absorb_damage_with_shield(amount, damage_type)
		if amount <= 0.0:
			return
	super.take_damage(amount, damage_type)


func take_damage_to_part(slot_name: String, amount: float, damage_type: String = "kinetic", layer: String = "", hit_pos: Vector3 = Vector3.ZERO) -> void:
	if is_destroyed:
		return
	# Shield absorption
	var wm = _get_weapon_manager()
	if wm and wm.is_shield_active():
		amount = wm.absorb_damage_with_shield(amount, damage_type)
		if amount <= 0.0:
			return
	super.take_damage_to_part(slot_name, amount, damage_type, layer, hit_pos)


func take_damage_at_point(amount: float, world_pos: Vector3, damage_type: String = "kinetic") -> void:
	if is_destroyed:
		return
	# Shield absorption
	var wm = _get_weapon_manager()
	if wm and wm.is_shield_active():
		amount = wm.absorb_damage_with_shield(amount, damage_type)
		if amount <= 0.0:
			return
	super.take_damage_at_point(amount, world_pos, damage_type)


func take_damage_to_part_at(slot_name: String, amount: float, world_pos: Vector3, damage_type: String = "kinetic") -> void:
	if is_destroyed:
		return
	var wm = _get_weapon_manager()
	if wm and wm.is_shield_active():
		amount = wm.absorb_damage_with_shield(amount, damage_type)
		if amount <= 0.0:
			return
	super.take_damage_to_part_at(slot_name, amount, world_pos, damage_type)


func _get_weapon_manager():
	var mecha = get_parent()
	if mecha:
		return mecha.get_node_or_null("WeaponManager")
	return null
