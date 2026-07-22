extends Node3D

signal health_changed(slot_name: String, current_hp: float, max_hp: float)
signal part_destroyed_visual(slot_name: String)
signal mecha_destroyed()

var parts: Dictionary = {
	"head": {"hp": 50.0, "max_hp": 50.0, "armor_class": 1.2, "broken": false, "mesh": null},
	"body": {"hp": 100.0, "max_hp": 100.0, "armor_class": 1.0, "broken": false, "mesh": null},
	"legs": {"hp": 80.0, "max_hp": 80.0, "armor_class": 0.8, "broken": false, "mesh": null},
}

var total_hp: float = 0.0
var max_total_hp: float = 0.0
var is_destroyed: bool = false

var _original_colors: Dictionary = {}
var _damage_color: Color = Color(0.8, 0.2, 0.2, 1)
var _broken_color: Color = Color(0.3, 0.3, 0.3, 1)


func _ready() -> void:
	add_to_group("mecha")
	_find_meshes()
	_calculate_totals()
	EventBus.damage_received.connect(_on_damage_received)


func _find_meshes() -> void:
	var head_node = get_node_or_null("../Head/HeadMesh")
	var body_node = get_node_or_null("../Body/BodyMesh")
	var legs_left = get_node_or_null("../LegLeft/LegLeftMesh")
	var legs_right = get_node_or_null("../LegRight/LegRightMesh")

	if head_node:
		parts["head"]["mesh"] = head_node
		_original_colors["head"] = head_node.material_override.albedo_color if head_node.material_override else Color(0.6, 0.65, 0.7, 1)
	if body_node:
		parts["body"]["mesh"] = body_node
		_original_colors["body"] = body_node.material_override.albedo_color if body_node.material_override else Color(0.6, 0.65, 0.7, 1)
	if legs_left:
		parts["legs"]["mesh"] = legs_left
		_original_colors["legs"] = legs_left.material_override.albedo_color if legs_left.material_override else Color(0.6, 0.65, 0.7, 1)


func _calculate_totals() -> void:
	total_hp = 0.0
	max_total_hp = 0.0
	for slot in parts:
		total_hp += parts[slot]["hp"]
		max_total_hp += parts[slot]["max_hp"]


func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if is_destroyed:
		return

	var weakest_slot = ""
	var weakest_hp = INF
	for slot in parts:
		if not parts[slot]["broken"] and parts[slot]["hp"] < weakest_hp:
			weakest_hp = parts[slot]["hp"]
			weakest_slot = slot

	if weakest_slot == "":
		return

	var part = parts[weakest_slot]
	var reduced = amount / maxf(part["armor_class"], 0.1)
	part["hp"] = maxf(part["hp"] - reduced, 0.0)

	health_changed.emit(weakest_slot, part["hp"], part["max_hp"])
	EventBus.damage_received.emit(weakest_slot, reduced, damage_type)

	_update_part_visual(weakest_slot)

	if part["hp"] <= 0.0:
		_on_part_destroyed(weakest_slot)


func _on_part_destroyed(slot_name: String) -> void:
	parts[slot_name]["broken"] = true
	parts[slot_name]["hp"] = 0.0
	_hide_part(slot_name)
	EventBus.part_destroyed.emit(slot_name)
	part_destroyed_visual.emit(slot_name)
	_calculate_totals()

	if total_hp <= 0.0:
		_on_mecha_destroyed()


func _on_mecha_destroyed() -> void:
	is_destroyed = true
	EventBus.mecha_destroyed.emit()
	for slot in parts:
		_hide_part(slot)


func _update_part_visual(slot_name: String) -> void:
	var mesh = parts[slot_name]["mesh"]
	if mesh == null or mesh.material_override == null:
		return

	var hp_ratio = parts[slot_name]["hp"] / parts[slot_name]["max_hp"]
	var original = _original_colors.get(slot_name, Color(0.6, 0.65, 0.7, 1))
	mesh.material_override.albedo_color = original.lerp(_damage_color, 1.0 - hp_ratio)


func _hide_part(slot_name: String) -> void:
	var mesh = parts[slot_name]["mesh"]
	if mesh:
		mesh.visible = false


func _on_damage_received(_slot: String, _amount: float, _type: String) -> void:
	pass


func get_health_percent() -> float:
	if max_total_hp <= 0.0:
		return 0.0
	return total_hp / max_total_hp


func is_part_broken(slot_name: String) -> bool:
	return parts.get(slot_name, {}).get("broken", false)
