class_name MechaHealthBase
extends Node3D

signal health_changed(slot_name: String, layer: String, current_hp: float, max_hp: float)
signal armor_broken(slot_name: String)
signal part_destroyed(slot_name: String)
signal mecha_destroyed()

@export var is_player: bool = false

var parts: Dictionary = {}
var total_armor_hp: float = 0.0
var total_frame_hp: float = 0.0
var max_total_armor: float = 0.0
var max_total_frame: float = 0.0
var is_destroyed: bool = false

var _original_colors: Dictionary = {}
var _armor_color: Color = Color(0.6, 0.65, 0.7, 1)
var _frame_color: Color = Color(0.4, 0.4, 0.45, 1)
var _damage_color: Color = Color(0.8, 0.2, 0.2, 1)
var _broken_color: Color = Color(0.2, 0.2, 0.2, 1)


func _ready() -> void:
	_init_parts()
	_find_meshes()
	_calculate_totals()
	EventBus.damage_received.connect(_on_damage_received)


func _init_parts() -> void:
	pass


func _find_meshes() -> void:
	pass


func _calculate_totals() -> void:
	total_armor_hp = 0.0
	total_frame_hp = 0.0
	max_total_armor = 0.0
	max_total_frame = 0.0
	for slot in parts:
		total_armor_hp += parts[slot]["armor_hp"]
		total_frame_hp += parts[slot]["frame_hp"]
		max_total_armor += parts[slot]["max_armor"]
		max_total_frame += parts[slot]["max_frame"]


func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if is_destroyed:
		return

	var target_slot = _select_target()
	if target_slot == "":
		return

	var part = parts[target_slot]

	if not part["armor_broken"]:
		_apply_armor_damage(target_slot, amount, damage_type)
	else:
		_apply_frame_damage(target_slot, amount, damage_type)


func take_damage_to_part(slot_name: String, amount: float, damage_type: String = "kinetic") -> void:
	if is_destroyed:
		return
	if not parts.has(slot_name):
		slot_name = _select_target()
	if slot_name == "":
		return

	var part = parts[slot_name]
	if not part["armor_broken"]:
		_apply_armor_damage(slot_name, amount, damage_type)
	else:
		_apply_frame_damage(slot_name, amount, damage_type)


func _select_target() -> String:
	var candidates = []
	for slot in parts:
		if not parts[slot]["destroyed"]:
			candidates.append(slot)

	if candidates.is_empty():
		return ""

	candidates.sort_custom(func(a, b):
		var hp_a = parts[a]["armor_hp"] if not parts[a]["armor_broken"] else parts[a]["frame_hp"]
		var hp_b = parts[b]["armor_hp"] if not parts[b]["armor_broken"] else parts[b]["frame_hp"]
		return hp_a < hp_b
	)

	return candidates[0]


func _apply_armor_damage(slot_name: String, amount: float, damage_type: String) -> void:
	var part = parts[slot_name]
	var reduced = amount / maxf(part["armor_class"], 0.1)
	part["armor_hp"] = maxf(part["armor_hp"] - reduced, 0.0)

	_update_part_visual(slot_name)
	health_changed.emit(slot_name, "armor", part["armor_hp"], part["max_armor"])

	# Persist damage to GlobalData so Hangar shows correct state after combat.
	# Key format: "slot_name" for armor damage ratio (0.0 = full, 1.0 = destroyed)
	if is_player and part["max_armor"] > 0.0:
		GlobalData.part_damage[slot_name] = 1.0 - (part["armor_hp"] / part["max_armor"])

	if is_player:
		EventBus.damage_received.emit(slot_name, reduced, damage_type)
	if _is_friendly():
		EventBus.friendly_damage_received.emit(reduced)

	if part["armor_hp"] <= 0.0:
		_on_armor_broken(slot_name)


func _apply_frame_damage(slot_name: String, amount: float, damage_type: String) -> void:
	var part = parts[slot_name]
	part["frame_hp"] = maxf(part["frame_hp"] - amount, 0.0)

	_update_part_visual(slot_name)
	health_changed.emit(slot_name, "frame", part["frame_hp"], part["max_frame"])

	# Persist frame damage to GlobalData with "_frame" suffix to distinguish from armor.
	# Key format: "slot_name_frame" for frame damage ratio (0.0 = full, 1.0 = destroyed)
	if is_player and part["max_frame"] > 0.0:
		GlobalData.part_damage[slot_name + "_frame"] = 1.0 - (part["frame_hp"] / part["max_frame"])

	if is_player:
		EventBus.damage_received.emit(slot_name, amount, damage_type)
	if _is_friendly():
		EventBus.friendly_damage_received.emit(amount)

	if part["frame_hp"] <= 0.0:
		_on_frame_destroyed(slot_name)


func _on_armor_broken(slot_name: String) -> void:
	parts[slot_name]["armor_broken"] = true
	parts[slot_name]["armor_hp"] = 0.0
	_show_frame(slot_name)
	armor_broken.emit(slot_name)
	_calculate_totals()
	if has_node("/root/AudioManager"):
		AudioManager.play_armor_break(global_position + Vector3(0, 1.5, 0))


func _on_frame_destroyed(slot_name: String) -> void:
	parts[slot_name]["destroyed"] = true
	parts[slot_name]["frame_hp"] = 0.0
	_hide_part(slot_name)
	if is_player:
		_spawn_scrap_wreckage(slot_name)
		_spawn_part_scrap_pickup(slot_name)
		# The arm frame holding the weapon broke → the weapon on that hand is
		# dropped as a recoverable pickup (the weapon itself is NOT destroyed).
		if slot_name == "arm_left":
			_drop_hand_weapon_pickup("left", slot_name)
		elif slot_name == "arm_right":
			_drop_hand_weapon_pickup("right", slot_name)
	part_destroyed.emit(slot_name)
	_calculate_totals()

	if total_frame_hp <= 0.0:
		_on_mecha_destroyed()


func _on_mecha_destroyed() -> void:
	is_destroyed = true
	mecha_destroyed.emit()

	EffectManager.spawn_explosion(global_position + Vector3(0, 1.5, 0))
	if has_node("/root/AudioManager"):
		AudioManager.play_explosion(global_position + Vector3(0, 1.5, 0))

	for slot in parts:
		_hide_part(slot)

	# Handle player death
	if is_player:
		await get_tree().create_timer(2.0).timeout
		EventBus.combat_ended.emit(false)
		GameManager.game_over()


func _get_section_node(slot_name: String) -> Node3D:
	var mecha = get_parent()
	if mecha == null:
		return null
	match slot_name:
		"head":
			return mecha.get_node_or_null("Head")
		"body":
			return mecha.get_node_or_null("Body")
		"arm_left":
			return mecha.get_node_or_null("ArmLeft")
		"arm_right":
			return mecha.get_node_or_null("ArmRight")
		"leg_left":
			return mecha.get_node_or_null("LegLeft")
		"leg_right":
			return mecha.get_node_or_null("LegRight")
	return null


func _get_visual_container(slot_name: String, container_name: String) -> Node3D:
	var section = _get_section_node(slot_name)
	if section == null:
		return null
	return section.get_node_or_null(container_name)


func _apply_color_to_container(container: Node3D, color: Color) -> void:
	if container == null:
		return
	for child in container.get_children():
		if child is MeshInstance3D:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			mat.metallic = 0.6
			mat.roughness = 0.4
			child.material_override = mat


func _update_part_visual(slot_name: String) -> void:
	var mesh = parts[slot_name]["mesh"]
	var part = parts[slot_name]

	if part["armor_broken"]:
		var frame_ratio = part["frame_hp"] / maxf(part["max_frame"], 0.001)
		var color = _frame_color.lerp(_damage_color, 1.0 - frame_ratio)
		_apply_color_to_container(_get_visual_container(slot_name, "FrameMesh"), color)
		if mesh and mesh.material_override:
			mesh.material_override.albedo_color = color
	else:
		var armor_ratio = part["armor_hp"] / maxf(part["max_armor"], 0.001)
		var color = _armor_color.lerp(_damage_color, 1.0 - armor_ratio)
		_apply_color_to_container(_get_visual_container(slot_name, "ArmorMesh"), color)
		if mesh and mesh.material_override:
			mesh.material_override.albedo_color = color


func _show_frame(slot_name: String) -> void:
	var armor_container = _get_visual_container(slot_name, "ArmorMesh")
	if armor_container:
		armor_container.visible = false
	var frame_container = _get_visual_container(slot_name, "FrameMesh")
	if frame_container:
		frame_container.visible = true
	var mesh = parts[slot_name]["mesh"]
	if mesh and mesh.material_override:
		mesh.material_override.albedo_color = _frame_color


func _hide_part(slot_name: String) -> void:
	var armor_container = _get_visual_container(slot_name, "ArmorMesh")
	if armor_container:
		armor_container.visible = false
	var frame_container = _get_visual_container(slot_name, "FrameMesh")
	if frame_container:
		frame_container.visible = false
	var mesh = parts[slot_name]["mesh"]
	if mesh:
		mesh.visible = false


func _spawn_scrap_wreckage(slot_name: String) -> void:
	var section = _get_section_node(slot_name)
	if section == null:
		return
	var world = get_tree().current_scene
	if world == null:
		return

	var scrap := RigidBody3D.new()
	scrap.name = "Scrap_%s" % slot_name
	scrap.position = section.global_position + Vector3(0, 0.5, 0)
	scrap.add_to_group("scrap")
	scrap.collision_layer = 8
	scrap.collision_mask = 1

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = _get_scrap_size(slot_name)
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.33, 0.3)
	mat.metallic = 0.7
	mat.roughness = 0.6
	mesh_inst.material_override = mat
	scrap.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	scrap.add_child(col)

	world.add_child(scrap)
	scrap.apply_central_impulse(Vector3(randf_range(-3, 3), randf_range(4, 8), randf_range(-3, 3)))
	scrap.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))


func _get_scrap_size(slot_name: String) -> Vector3:
	match slot_name:
		"head":
			return Vector3(0.5, 0.45, 0.55)
		"body":
			return Vector3(0.9, 1.1, 0.7)
		"arm_left", "arm_right":
			return Vector3(0.4, 0.8, 0.4)
		"leg_left", "leg_right":
			return Vector3(0.5, 0.9, 0.5)
	return Vector3(0.5, 0.5, 0.5)


# The destroyed player part leaves a collectible scrap-material pickup so the
# wreckage actually becomes crafting material (matches the visual debris above).
func _spawn_part_scrap_pickup(slot_name: String) -> void:
	var scrap_amount := 3
	match slot_name:
		"head":
			scrap_amount = 4
		"body":
			scrap_amount = 5
		"arm_left", "arm_right", "leg_left", "leg_right":
			scrap_amount = 3
	var section = _get_section_node(slot_name)
	if section == null:
		return
	var loot = get_node_or_null("/root/GameWorld/LootSystem")
	if loot == null or not loot.has_method("spawn_scrap_pickup"):
		return
	loot.spawn_scrap_pickup(section.global_position + Vector3(0, 0.5, 0), scrap_amount)


# The arm frame holding the weapon broke → drop the weapon on that hand as a
# recoverable pickup. The weapon itself is NOT destroyed, only the frame was.
func _drop_hand_weapon_pickup(hand: String, arm_slot: String) -> void:
	var mecha = get_parent()
	if mecha == null:
		return
	var wm = mecha.get_node_or_null("WeaponManager")
	if wm == null or not wm.has_method("drop_weapon_from_destroyed_arm"):
		return
	var weapon: WeaponPart = wm.drop_weapon_from_destroyed_arm(hand)
	if weapon == null:
		return

	var world = get_tree().current_scene
	if world == null:
		return

	var section = _get_section_node(arm_slot)
	var drop_pos: Vector3 = global_position + Vector3(0, 1.0, 0)
	if section:
		drop_pos = section.global_position + Vector3(0, 0.5, 0)

	var pickup := Area3D.new()
	pickup.collision_layer = 0
	pickup.collision_mask = 1
	pickup.set_script(load("res://scripts/mecha/weapon_pickup.gd"))
	pickup.weapon_resource = weapon
	world.add_child(pickup)
	pickup.global_position = drop_pos

	# Keep the same pickup shape as the stock pickups in game_world.tscn.
	# The weapon model visual is created automatically by weapon_pickup._create_visual().
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.5, 1.3)
	collision.shape = shape
	pickup.add_child(collision)


func _on_damage_received(_slot: String, _amount: float, _type: String) -> void:
	pass


# A friendly unit is the player mech or a fielded ally (group "ally").
func _is_friendly() -> bool:
	if is_player:
		return true
	var parent = get_parent()
	return parent != null and parent.is_in_group("ally")


func get_health_percent() -> float:
	var max_total = max_total_armor + max_total_frame
	if max_total <= 0.0:
		return 0.0
	return (total_armor_hp + total_frame_hp) / max_total


func get_armor_percent() -> float:
	if max_total_armor <= 0.0:
		return 0.0
	return total_armor_hp / max_total_armor


func get_frame_percent() -> float:
	if max_total_frame <= 0.0:
		return 0.0
	return total_frame_hp / max_total_frame


func is_part_destroyed(slot_name: String) -> bool:
	return parts.get(slot_name, {}).get("destroyed", false)


func is_armor_broken(slot_name: String) -> bool:
	return parts.get(slot_name, {}).get("armor_broken", false)
