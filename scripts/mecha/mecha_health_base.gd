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
	add_to_group("mecha")
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

	if is_player:
		EventBus.damage_received.emit(slot_name, reduced, damage_type)

	if part["armor_hp"] <= 0.0:
		_on_armor_broken(slot_name)


func _apply_frame_damage(slot_name: String, amount: float, damage_type: String) -> void:
	var part = parts[slot_name]
	part["frame_hp"] = maxf(part["frame_hp"] - amount, 0.0)

	_update_part_visual(slot_name)
	health_changed.emit(slot_name, "frame", part["frame_hp"], part["max_frame"])

	if is_player:
		EventBus.damage_received.emit(slot_name, amount, damage_type)

	if part["frame_hp"] <= 0.0:
		_on_frame_destroyed(slot_name)


func _on_armor_broken(slot_name: String) -> void:
	parts[slot_name]["armor_broken"] = true
	parts[slot_name]["armor_hp"] = 0.0
	_show_frame(slot_name)
	armor_broken.emit(slot_name)
	_calculate_totals()


func _on_frame_destroyed(slot_name: String) -> void:
	parts[slot_name]["destroyed"] = true
	parts[slot_name]["frame_hp"] = 0.0
	_hide_part(slot_name)
	part_destroyed.emit(slot_name)
	_calculate_totals()

	if total_frame_hp <= 0.0:
		_on_mecha_destroyed()


func _on_mecha_destroyed() -> void:
	is_destroyed = true
	mecha_destroyed.emit()

	EffectManager.spawn_explosion(global_position + Vector3(0, 1.5, 0))

	for slot in parts:
		_hide_part(slot)


func _update_part_visual(slot_name: String) -> void:
	var mesh = parts[slot_name]["mesh"]
	if mesh == null or mesh.material_override == null:
		return

	var part = parts[slot_name]
	if part["armor_broken"]:
		var frame_ratio = part["frame_hp"] / part["max_frame"]
		mesh.material_override.albedo_color = _frame_color.lerp(_damage_color, 1.0 - frame_ratio)
	else:
		var armor_ratio = part["armor_hp"] / part["max_armor"]
		mesh.material_override.albedo_color = _armor_color.lerp(_damage_color, 1.0 - armor_ratio)


func _show_frame(slot_name: String) -> void:
	var mesh = parts[slot_name]["mesh"]
	if mesh and mesh.material_override:
		mesh.material_override.albedo_color = _frame_color


func _hide_part(slot_name: String) -> void:
	var mesh = parts[slot_name]["mesh"]
	if mesh:
		mesh.visible = false


func _on_damage_received(_slot: String, _amount: float, _type: String) -> void:
	pass


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
