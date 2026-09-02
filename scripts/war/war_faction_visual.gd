extends RefCounted
class_name WarFactionVisual

## ติวสีหุ่นตามฝั่ง — Friendly น้ำเงินอ่อน / Enemy แดงสนิม

static func apply_team_tint(mecha: Node3D, team: String) -> void:
	if mecha == null:
		return
	var tint := Color(0.6, 0.7, 1.0, 1.0) if team == "friendly" else Color(1.0, 0.45, 0.4, 1.0)
	var mgr = mecha.get_node_or_null("PartMeshManager")
	if mgr == null:
		return
	for slot in GlobalData.MECHA_SLOTS:
		var entry = mgr.slot_meshes.get(slot, null)
		if entry == null:
			continue
		for key in ["armor", "armor_lower", "frame", "frame_lower"]:
			var c = entry.get(key, null)
			if c is Node3D and is_instance_valid(c):
				for child in c.get_children():
					_tint_recursive(child, tint, team)


static func _tint_recursive(node: Node, tint: Color, team: String) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override is StandardMaterial3D:
			var m := (mi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
			m.albedo_color = m.albedo_color.lerp(tint, 0.25)
			mi.material_override = m
		elif mi.mesh:
			for i in range(mi.mesh.get_surface_count()):
				var mat = mi.mesh.surface_get_material(i)
				if mat is StandardMaterial3D:
					var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					dup.albedo_color = dup.albedo_color.lerp(tint, 0.25)
					mi.set_surface_override_material(i, dup)
	for child in node.get_children():
		_tint_recursive(child, tint, team)


static func get_tier_ids(tier: String) -> Dictionary:
	match tier.to_lower():
		"line":
			return {"head":"head_line","body":"body_line","arm_left":"arm_left_line","arm_right":"arm_right_line","leg_left":"leg_left_line","leg_right":"leg_right_line"}
		"iron":
			return {"head":"head_iron","body":"body_iron","arm_left":"arm_left_iron","arm_right":"arm_right_iron","leg_left":"leg_left_iron","leg_right":"leg_right_iron"}
		"strike":
			return {"head":"head_strike","body":"body_strike","arm_left":"arm_left_strike","arm_right":"arm_right_strike","leg_left":"leg_left_strike","leg_right":"leg_right_strike"}
		"valkyrion":
			return {"head":"head_valkyrion","body":"body_valkyrion","arm_left":"arm_left_valkyrion","arm_right":"arm_right_valkyrion","leg_left":"leg_left_valkyrion","leg_right":"leg_right_valkyrion"}
		_:
			return {}


## Faction Standard Archetype (GM vs Zaku)
static func get_faction_archetype(team: String, tier: String = "line") -> Dictionary:
	if team == "friendly":
		# GM / Federation Style: Visor Head, clean angular Line-Issue plating, White/Cobalt palette
		return {
			"style": "gm_federation",
			"tier": tier,
			"chassis": "standard",
			"slots": {
				"head": "head_001",
				"body": "body_line",
				"arm_left": "arm_left_line",
				"arm_right": "arm_right_line",
				"legs": "legs_line",
				"backpack": "cargo"
			},
			"weapons": {
				"left": "res://resources/mech/stock/weapon_machine_gun.tres",
				"right": "res://resources/mech/stock/weapon_shotgun.tres"
			},
			"tint": Color(0.65, 0.8, 1.0, 1.0)
		}
	else:
		# Zaku / Outlaw Style: Mono-Eye Head, curved industrial Pilgrim/Iron plating, Dark Red/Rust palette
		return {
			"style": "zaku_outlaw",
			"tier": tier,
			"chassis": "pilgrim",
			"slots": {
				"head": "head_002",
				"body": "body_iron",
				"arm_left": "arm_left_iron",
				"arm_right": "arm_right_iron",
				"legs": "legs_iron",
				"backpack": "combat"
			},
			"weapons": {
				"left": "res://resources/mech/stock/weapon_pile_bunker.tres",
				"right": "res://resources/mech/stock/weapon_machine_gun.tres"
			},
			"tint": Color(1.0, 0.4, 0.35, 1.0)
		}


## Live Fitting: Apply faction armor and team tint to mecha
static func apply_faction_archetype(mecha: Node3D, team: String, tier: String = "line") -> void:
	if mecha == null:
		return
	var pmm = mecha.get_node_or_null("PartMeshManager")
	var arch := get_faction_archetype(team, tier)
	var slots: Dictionary = arch.get("slots", {})
	if pmm and pmm.has_method("initialize_slot"):
		for slot in GlobalData.MECHA_SLOTS:
			var part_id: String = str(slots.get(slot, ""))
			if part_id != "":
				var part = pmm.build_part_for_slot({"id": part_id, "slot": slot})
				pmm.initialize_slot(slot, part, false)
	apply_team_tint(mecha, team)

