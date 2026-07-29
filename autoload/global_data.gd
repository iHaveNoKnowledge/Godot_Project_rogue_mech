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

var current_sector: int = 1
var max_sectors: int = 3

# --- ระบบเพิ่มเติมใหม่ (Added for Rogue Expansion) ---
# กำลังพลทั้งหมดของศัตรูในภาคสนาม (Current / Max)
var enemy_forces: Dictionary = {
	"boss_current": 1, "boss_max": 1,
	"ace_current": 1, "ace_max": 2,
	"grunt_current": 10, "grunt_max": 20
}

var last_combat_squad_size: int = 1 # ขนาดกองกำลังของเราตอนปะทะครั้งล่าสุด
var max_notoriety_multiplier: float = 1.0 # ค่าคูณความระแวงจำสะสมของศัตรู
var stalking_aces: Array[String] = [] # เก็บรายชื่อ ID ของ Ace ที่ผู้เล่นเคยหนีมาและกำลังตามล่าอยู่
var stalking_chance: float = 0.0 # โอกาสสุ่มเจอ Stalking Ace ระหว่างสู้ด่านปกติ
# --------------------------------------------------

const SAVE_PATH := "user://savegame.json"


func reset_run_data() -> void:
	equipped_parts.clear()
	part_damage.clear()
	board_grid.clear()
	current_tile = Vector2i.ZERO
	heat = 0
	wanted_level = 0
	safehouse_upgrades.clear()
	credits = 100
	spare_parts = 10
	data_cores = 0
	current_sector = 1
	enemy_forces = {
		"boss_current": 1, "boss_max": 1,
		"ace_current": 1, "ace_max": 2,
		"grunt_current": 10, "grunt_max": 20
	}
	last_combat_squad_size = 1
	max_notoriety_multiplier = 1.0
	stalking_aces.clear()
	stalking_chance = 0.0


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
		"sector": current_sector,
		"enemy_forces": enemy_forces.duplicate(),
		"last_combat_squad_size": last_combat_squad_size,
		"max_notoriety_multiplier": max_notoriety_multiplier,
		"stalking_aces": stalking_aces,
		"stalking_chance": stalking_chance
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


func _restore_from_dict(data: Dictionary) -> void:
	chassis_id = data.get("chassis", "standard")
	part_damage = data.get("damage", {})
	heat = data.get("heat", 0)
	wanted_level = data.get("wanted", 0)
	credits = data.get("credits", 0)
	spare_parts = data.get("spare_parts", 0)
	data_cores = data.get("data_cores", 0)
	current_sector = data.get("sector", 1)
	
	var pos = data.get("position", {"x": 0, "y": 0})
	current_tile = Vector2i(pos.x, pos.y)
	var parts_dict: Dictionary = data.get("parts", {})
	equipped_parts.clear()
	for slot in parts_dict:
		equipped_parts[slot] = load(parts_dict[slot])
		
	# Restore expansion state
	enemy_forces = data.get("enemy_forces", {
		"boss_current": 1, "boss_max": 1,
		"ace_current": 1, "ace_max": 2,
		"grunt_current": 10, "grunt_max": 20
	}).duplicate()
	last_combat_squad_size = data.get("last_combat_squad_size", 1)
	max_notoriety_multiplier = data.get("max_notoriety_multiplier", 1.0)
	
	stalking_aces.clear()
	var loaded_aces = data.get("stalking_aces", [])
	if loaded_aces is Array:
		stalking_aces.assign(loaded_aces)
		
	stalking_chance = data.get("stalking_chance", 0.0)



func _serialize_parts() -> Dictionary:
	var result := {}
	for slot in equipped_parts:
		result[slot] = equipped_parts[slot].resource_path
	return result
