extends CanvasLayer

@onready var bars: Dictionary = {
	"head": %HeadBar,
	"body": %BodyBar,
	"arm_left": %ArmLBar,
	"leg_left": %LegLBar,
	"arm_right": %ArmRBar,
	"leg_right": %LegRBar,
}

@onready var value_labels: Dictionary = {
	"head": %HeadValue,
	"body": %BodyValue,
	"arm_left": %ArmLValue,
	"leg_left": %LegLValue,
	"arm_right": %ArmRValue,
	"leg_right": %LegRValue,
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
	if not bars.has(slot_name) or health_system == null:
		return
	if not health_system.parts.has(slot_name):
		return
	var part = health_system.parts[slot_name]
	bars[slot_name].setup(part["armor_hp"], part["max_armor"], part["frame_hp"], part["max_frame"], part["destroyed"])
	var label: Label = value_labels[slot_name]
	if part["destroyed"]:
		label.text = "DESTROYED"
	elif part["armor_broken"]:
		label.text = "%d" % int(part["frame_hp"])
	else:
		label.text = "%d" % int(part["armor_hp"])


func _update_all_bars() -> void:
	for slot_name in bars:
		_refresh(slot_name)
