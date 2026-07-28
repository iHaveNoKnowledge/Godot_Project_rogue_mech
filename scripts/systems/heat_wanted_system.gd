extends Node

@export var heat_decay_rate: int = 1
@export var wanted_thresholds: Array[int] = [4, 7, 11]
@export var max_heat: int = 15


func _ready() -> void:
	EventBus.tile_entered.connect(_on_tile_entered)
	EventBus.combat_ended.connect(_on_combat_ended)
	update_forces_thresholds()


func _on_tile_entered(_pos: Vector2i, _data: Node) -> void:
	modify_heat(-heat_decay_rate)
	_apply_notoriety_decay()
	process_turn_mobilization()


func _apply_notoriety_decay() -> void:
	if GlobalData.max_notoriety_multiplier > 1.0:
		GlobalData.max_notoriety_multiplier = maxf(1.0, GlobalData.max_notoriety_multiplier - 0.05)


func update_forces_thresholds() -> void:
	# Early game gateway: If heat < 3, max caps do not expand beyond base
	if GlobalData.heat < 3:
		GlobalData.enemy_forces["grunt_max"] = 30
		GlobalData.enemy_forces["ace_max"] = 2
		GlobalData.enemy_forces["boss_max"] = 1
		return

	var h = GlobalData.heat
	if h >= 11:
		GlobalData.enemy_forces["grunt_max"] = 150
		GlobalData.enemy_forces["ace_max"] = 8
		GlobalData.enemy_forces["boss_max"] = 2
	elif h >= 7:
		GlobalData.enemy_forces["grunt_max"] = 110
		GlobalData.enemy_forces["ace_max"] = 6
		GlobalData.enemy_forces["boss_max"] = 1
	elif h >= 3:
		GlobalData.enemy_forces["grunt_max"] = 60
		GlobalData.enemy_forces["ace_max"] = 4
		GlobalData.enemy_forces["boss_max"] = 1


func process_turn_mobilization() -> void:
	update_forces_thresholds()
	var forces = GlobalData.enemy_forces
	# Gradually increase current towards max on board turn
	forces["grunt_current"] = mini(forces["grunt_max"], forces["grunt_current"] + randi_range(5, 15))
	forces["ace_current"] = mini(forces["ace_max"], forces["ace_current"] + 1)
	forces["boss_current"] = mini(forces["boss_max"], forces["boss_current"] + 1)


func _on_combat_ended(victory: bool) -> void:
	var base_gain = 1
	var current_mult = 1.0 + (GlobalData.last_squad_size * 0.25)
	if current_mult > GlobalData.max_notoriety_multiplier:
		GlobalData.max_notoriety_multiplier = current_mult

	var effective_mult = GlobalData.max_notoriety_multiplier
	var scaled_gain = int(round(base_gain * effective_mult))
	modify_heat(scaled_gain)


func modify_heat(amount: int) -> void:
	GlobalData.heat = clampi(GlobalData.heat + amount, 0, max_heat)
	EventBus.heat_changed.emit(GlobalData.heat)
	update_forces_thresholds()
	_update_wanted()


func add_wave_heat() -> void:
	# Called when a wave is cleared
	var base_gain = 3
	var effective_mult = GlobalData.max_notoriety_multiplier
	var scaled_gain = int(round(base_gain * effective_mult))
	modify_heat(scaled_gain)


func _update_wanted() -> void:
	var new_wanted = 0
	for threshold in wanted_thresholds:
		if GlobalData.heat >= threshold:
			new_wanted += 1
	if new_wanted != GlobalData.wanted_level:
		GlobalData.wanted_level = new_wanted
		EventBus.wanted_changed.emit(new_wanted)


func get_extra_enemy_count() -> int:
	return GlobalData.wanted_level


func get_enemy_damage_multiplier() -> float:
	return 1.0 + (GlobalData.wanted_level * 0.15)

