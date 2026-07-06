extends Node

@export var heat_decay_rate: int = 1
@export var wanted_thresholds: Array[int] = [3, 6, 10]
@export var max_heat: int = 15


func _ready() -> void:
	EventBus.tile_entered.connect(_on_tile_entered)
	EventBus.combat_ended.connect(_on_combat_ended)


func _on_tile_entered(_pos: Vector2i, _data: Resource) -> void:
	modify_heat(-heat_decay_rate)


func _on_combat_ended(victory: bool) -> void:
	if victory:
		modify_heat(2)
	else:
		modify_heat(1)


func modify_heat(amount: int) -> void:
	GlobalData.heat = clampi(GlobalData.heat + amount, 0, max_heat)
	EventBus.heat_changed.emit(GlobalData.heat)
	_update_wanted()


func _update_wanted() -> void:
	var new_wanted = 0
	for threshold in wanted_thresholds:
		if GlobalData.heat >= threshold:
			new_wanted += 1
	if new_wanted != GlobalData.wanted_level:
		GlobalData.wanted_level = new_wanted
		EventBus.wanted_changed.emit(new_wanted)
