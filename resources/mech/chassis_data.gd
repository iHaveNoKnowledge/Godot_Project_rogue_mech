extends Resource
class_name ChassisData

@export var chassis_name: String = "Standard Frame"
@export var base_speed: float = 8.0
@export var base_turn_rate: float = 2.0
@export var weight_capacity: float = 100.0
@export var slot_layout: Array[String] = ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]
@export var eject_pilot_scene: PackedScene
@export var chassis_mesh: PackedScene
