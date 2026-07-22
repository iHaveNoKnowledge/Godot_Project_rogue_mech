extends Node3D

signal health_changed(slot_name: String, current_hp: float, max_hp: float)
signal part_destroyed_visual(slot_name: String)
signal mecha_destroyed()

@export var body_mesh: MeshInstance3D

var parts: Dictionary = {
	"head": {"hp": 50.0, "max_hp": 50.0, "armor_class": 1.2, "broken": false},
	"body": {"hp": 100.0, "max_hp": 100.0, "armor_class": 1.0, "broken": false},
	"legs": {"hp": 80.0, "max_hp": 80.0, "armor_class": 0.8, "broken": false},
}

var total_hp: float = 0.0
var max_total_hp: float = 0.0
var is_destroyed: bool = false

var _original_color: Color
var _damage_color: Color = Color(0.8, 0.2, 0.2, 1)
var _broken_color: Color = Color(0.3, 0.3, 0.3, 1)


func _ready() -> void:
	add_to_group("mecha")
	_calculate_totals()
	if body_mesh and body_mesh.material_override:
		_original_color = body_mesh.material_override.albedo_color
	else:
		_original_color = Color(0.6, 0.65, 0.7, 1)
	EventBus.damage_received.connect(_on_damage_received)


func _calculate_totals() -> void:
	total_hp = 0.0
	max_total_hp = 0.0
	for slot in parts:
		total_hp += parts[slot]["hp"]
		max_total_hp += parts[slot]["max_hp"]


func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if is_destroyed:
		return

	# Find weakest non-broken part
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

	_update_visual_damage()

	if part["hp"] <= 0.0:
		_on_part_destroyed(weakest_slot)


func _on_part_destroyed(slot_name: String) -> void:
	parts[slot_name]["broken"] = true
	parts[slot_name]["hp"] = 0.0
	EventBus.part_destroyed.emit(slot_name)
	part_destroyed_visual.emit(slot_name)
	_calculate_totals()

	if total_hp <= 0.0:
		_on_mecha_destroyed()


func _on_mecha_destroyed() -> void:
	is_destroyed = true
	EventBus.mecha_destroyed.emit()
	if body_mesh and body_mesh.material_override:
		body_mesh.material_override.albedo_color = _broken_color


func _update_visual_damage() -> void:
	if not body_mesh or not body_mesh.material_override:
		return

	var damage_ratio = 1.0 - (total_hp / max_total_hp)
	body_mesh.material_override.albedo_color = _original_color.lerp(_damage_color, damage_ratio)


func _on_damage_received(_slot: String, _amount: float, _type: String) -> void:
	pass


func get_health_percent() -> float:
	if max_total_hp <= 0.0:
		return 0.0
	return total_hp / max_total_hp


func is_part_broken(slot_name: String) -> bool:
	return parts.get(slot_name, {}).get("broken", false)
