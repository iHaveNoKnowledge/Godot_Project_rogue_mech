extends Resource
class_name ArmorPart

@export var part_name: String = ""
@export var slot_id: String = ""
@export var mesh_scene: PackedScene
@export var mesh_scene_lower: PackedScene
@export var inner_frame_scene: PackedScene
@export var inner_frame_scene_lower: PackedScene
@export var max_hp: float = 100.0
@export var max_frame_hp: float = 50.0
@export var weight: float = 10.0
@export var armor_class: float = 1.0
@export var break_threshold: float = 0.3
@export var part_color: Color = Color(0.4, 0.45, 0.52)
@export var icon: Texture2D
@export var defense_type: String = "standard"
@export var resistance: Dictionary = {"heat": 1.0, "pierce": 1.0, "impact": 1.0}
@export var tech_id: String = "" # TechnologySystem ID (""; empty = technology-neutral legacy armor)

func get_resistance(damage_type: String) -> float:
	if resistance.has(damage_type):
		return float(resistance[damage_type])
	match defense_type:
		"heavy", "reinforced":
			match damage_type:
				"impact": return 0.7
				"pierce": return 0.8
				"heat": return 1.0
		"energy", "heat_resistant":
			match damage_type:
				"heat": return 0.6
				"pierce": return 1.0
				"impact": return 1.0
		"reactive":
			match damage_type:
				"pierce": return 0.6
				"impact": return 0.9
				"heat": return 1.1
	return 1.0
