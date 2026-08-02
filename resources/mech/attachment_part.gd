extends Resource
class_name AttachmentPart

@export var attachment_id: String = ""
@export var attachment_name: String = ""
@export_enum("head", "body", "arm_left", "arm_right", "leg_left", "leg_right") var slot_id: String = "body"
@export var weight: float = 1.0
@export var power_cost: float = 0.0
@export var description: String = ""
@export var mesh_scene: PackedScene
@export var icon: Texture2D
