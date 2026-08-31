extends Node
class_name WarProductionQueue

## Craft/Repair Queue 60-180s — Phase1 per PLAN.md 7.5

var _queue: Array[Dictionary] = []


func queue_craft(item_id: String, type: String, duration: float) -> void:
	_queue.append({"id": item_id, "type": type, "remaining": duration, "total": duration})


func queue_repair(slot: String, duration: float) -> void:
	_queue.append({"id": slot, "type": "repair", "remaining": duration, "total": duration})


func _process(delta: float) -> void:
	for entry in _queue:
		entry["remaining"] -= delta
	var completed: Array[Dictionary] = []
	for entry in _queue:
		if entry["remaining"] <= 0:
			completed.append(entry)
	for entry in completed:
		_queue.erase(entry)
		_complete(entry)


func _complete(entry: Dictionary) -> void:
	match entry["type"]:
		"craft":
			pass # Grant via GlobalData — handled by caller polling is_ready
		"repair":
			var slot = str(entry["id"])
			GlobalData.weapons.part_damage.erase(slot)
			GlobalData.weapons.part_damage.erase(slot + "_frame")


func get_progress(item_id: String) -> float:
	for entry in _queue:
		if str(entry["id"]) == item_id:
			return clampf(1.0 - entry["remaining"] / entry["total"], 0.0, 1.0)
	return 1.0


func is_queued(item_id: String) -> bool:
	for entry in _queue:
		if str(entry["id"]) == item_id:
			return true
	return false
