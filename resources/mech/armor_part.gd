extends Resource
class_name ArmorPart

@export var part_name: String = ""
@export var slot_id: String = ""
@export var mesh_scene: PackedScene
@export var inner_frame_scene: PackedScene
@export var max_hp: float = 100.0
@export var max_frame_hp: float = 50.0
@export var weight: float = 10.0
@export var armor_class: float = 1.0
@export var break_threshold: float = 0.3
@export var icon: Texture2D
