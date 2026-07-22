extends CanvasLayer

@onready var bars: Dictionary = {
	"head": {"armor_bar": %HeadArmorBar, "frame_bar": %HeadFrameBar, "label": %HeadLabel},
	"body": {"armor_bar": %BodyArmorBar, "frame_bar": %BodyFrameBar, "label": %BodyLabel},
	"arm_left": {"armor_bar": %ArmLeftArmorBar, "frame_bar": %ArmLeftFrameBar, "label": %ArmLeftLabel},
	"arm_right": {"armor_bar": %ArmRightArmorBar, "frame_bar": %ArmRightFrameBar, "label": %ArmRightLabel},
	"leg_left": {"armor_bar": %LegLeftArmorBar, "frame_bar": %LegLeftFrameBar, "label": %LegLeftLabel},
	"leg_right": {"armor_bar": %LegRightArmorBar, "frame_bar": %LegRightFrameBar, "label": %LegRightLabel},
}
@onready var armor_total: Label = %ArmorTotal
@onready var frame_total: Label = %FrameTotal

var health_system: Node = null


func _ready() -> void:
	await get_tree().process_frame
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	if mecha:
		health_system = mecha.get_node_or_null("HealthSystem")
		if health_system:
			health_system.health_changed.connect(_on_health_changed)
			_update_all_bars()


func _on_health_changed(slot_name: String, layer: String, current_hp: float, max_hp: float) -> void:
	if not bars.has(slot_name):
		return
	var entry = bars[slot_name]
	var percent = current_hp / max_hp * 100.0

	if layer == "armor":
		entry["armor_bar"].value = percent
	else:
		entry["frame_bar"].value = percent

	_update_label(slot_name)
	_update_totals()


func _update_label(slot_name: String) -> void:
	if not bars.has(slot_name) or health_system == null:
		return
	var part = health_system.parts[slot_name]
	var entry = bars[slot_name]
	entry["label"].text = "%s: A%d/F%d" % [
		slot_name.to_upper(),
		int(part["armor_hp"]),
		int(part["frame_hp"])
	]


func _update_all_bars() -> void:
	if health_system == null:
		return
	for slot in health_system.parts:
		var part = health_system.parts[slot]
		_on_health_changed(slot, "armor", part["armor_hp"], part["max_armor"])
		_on_health_changed(slot, "frame", part["frame_hp"], part["max_frame"])


func _update_totals() -> void:
	if health_system == null:
		return
	armor_total.text = "ARMOR: %d%%" % int(health_system.get_armor_percent() * 100.0)
	frame_total.text = "FRAME: %d%%" % int(health_system.get_frame_percent() * 100.0)
