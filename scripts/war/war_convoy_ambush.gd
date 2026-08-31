extends Node
class_name WarConvoyAmbush

## Convoy ถูกปล้นระหว่างขน — random intercept (per PLAN.md Phase3)

@export var ambush_chance: float = 0.12

var _timer: float = 0.0


func _process(delta: float) -> void:
	_timer += delta
	if _timer < 30.0:
		return
	_timer = 0
	if randf() > ambush_chance:
		return
	_trigger_ambush()


func _trigger_ambush() -> void:
	var trucks = get_tree().get_nodes_in_group("logistic_truck")
	if trucks.is_empty():
		return
	var truck = trucks[randi() % trucks.size()] as Node3D
	if truck == null:
		return
	# Spawn 2 enemies near truck
	for i in 2:
		var pos = truck.global_position + Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))
		var enemy_scene = load("res://scenes/mecha/mecha_base.tscn")
		if enemy_scene:
			var enemy = enemy_scene.instantiate()
			enemy.position = pos
			enemy.add_to_group("enemy")
			get_tree().current_scene.add_child(enemy)
