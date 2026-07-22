extends Node

var chassis_id: String = "standard"
var equipped_parts: Dictionary = {}
var part_damage: Dictionary = {}

var board_grid: Array = []
var current_tile: Vector2i = Vector2i.ZERO
var heat: int = 0
var wanted_level: int = 0
var safehouse_upgrades: Array = []

var credits: int = 0
var spare_parts: int = 0
var data_cores: int = 0

const SAVE_PATH := "user://savegame.json"


func save_run() -> void:
	var data := {
		"chassis": chassis_id,
		"parts": _serialize_parts(),
		"damage": part_damage.duplicate(),
		"position": {"x": current_tile.x, "y": current_tile.y},
		"heat": heat,
		"wanted": wanted_level,
		"credits": credits,
		"spare_parts": spare_parts,
		"data_cores": data_cores,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


func load_run() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	var data = JSON.parse_string(file.get_as_text())
	if data == null:
		return false
	_restore_from_dict(data)
	return true


func _serialize_parts() -> Dictionary:
	var result := {}
	for slot in equipped_parts:
		result[slot] = equipped_parts[slot].resource_path
	return result


func _restore_from_dict(data: Dictionary) -> void:
	chassis_id = data.get("chassis", "standard")
	part_damage = data.get("damage", {})
	heat = data.get("heat", 0)
	wanted_level = data.get("wanted", 0)
	credits = data.get("credits", 0)
	spare_parts = data.get("spare_parts", 0)
	data_cores = data.get("data_cores", 0)
	var pos = data.get("position", {"x": 0, "y": 0})
	current_tile = Vector2i(pos.x, pos.y)
	var parts_dict: Dictionary = data.get("parts", {})
	equipped_parts.clear()
	for slot in parts_dict:
		equipped_parts[slot] = load(parts_dict[slot])
