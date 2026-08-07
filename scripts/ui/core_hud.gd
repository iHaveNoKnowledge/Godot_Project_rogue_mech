extends CanvasLayer

@onready var armor_bars: Dictionary = {
	"head": %HeadArmorBar,
	"body": %BodyArmorBar,
	"arm_left": %ArmLArmorBar,
	"leg_left": %LegLArmorBar,
	"arm_right": %ArmRArmorBar,
	"leg_right": %LegRArmorBar,
}

@onready var frame_bars: Dictionary = {
	"head": %HeadFrameBar,
	"body": %BodyFrameBar,
	"arm_left": %ArmLFrameBar,
	"leg_left": %LegLFrameBar,
	"arm_right": %ArmRFrameBar,
	"leg_right": %LegRFrameBar,
}

@onready var armor_values: Dictionary = {
	"head": %HeadArmorValue,
	"body": %BodyArmorValue,
	"arm_left": %ArmLArmorValue,
	"leg_left": %LegLArmorValue,
	"arm_right": %ArmRArmorValue,
	"leg_right": %LegRArmorValue,
}

@onready var frame_values: Dictionary = {
	"head": %HeadFrameValue,
	"body": %BodyFrameValue,
	"arm_left": %ArmLFrameValue,
	"leg_left": %LegLFrameValue,
	"arm_right": %ArmRFrameValue,
	"leg_right": %LegRFrameValue,
}

var health_system: Node = null


func _ready() -> void:
	await get_tree().process_frame
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	if mecha:
		health_system = mecha.get_node_or_null("HealthSystem")
		if health_system:
			health_system.health_changed.connect(_on_health_changed)
			health_system.armor_broken.connect(_on_armor_broken)
			health_system.part_destroyed.connect(_on_part_destroyed)
			_update_all_bars()


func _on_health_changed(slot_name: String, _layer: String, _current_hp: float, _max_hp: float) -> void:
	_refresh(slot_name)


func _on_armor_broken(slot_name: String) -> void:
	_refresh(slot_name)


func _on_part_destroyed(slot_name: String) -> void:
	_refresh(slot_name)


func _refresh(slot_name: String) -> void:
	if not armor_bars.has(slot_name) or health_system == null:
		return
	if not health_system.parts.has(slot_name):
		return
	var part = health_system.parts[slot_name]
	armor_bars[slot_name].setup(part["armor_hp"], part["max_armor"], part["destroyed"])
	frame_bars[slot_name].setup(part["frame_hp"], part["max_frame"], part["destroyed"])
	armor_values[slot_name].text = "%d" % int(part["armor_hp"])
	frame_values[slot_name].text = "%d" % int(part["frame_hp"])


func _update_all_bars() -> void:
	for slot_name in armor_bars:
		_refresh(slot_name)
