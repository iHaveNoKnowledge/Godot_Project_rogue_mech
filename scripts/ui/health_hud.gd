extends CanvasLayer

@onready var bars: Dictionary = {
	"head": {"bar": %HeadBar, "label": %HeadLabel},
	"body": {"bar": %BodyBar, "label": %BodyLabel},
	"arm_left": {"bar": %ArmLeftBar, "label": %ArmLeftLabel},
	"arm_right": {"bar": %ArmRightBar, "label": %ArmRightLabel},
	"leg_left": {"bar": %LegLeftBar, "label": %LegLeftLabel},
	"leg_right": {"bar": %LegRightBar, "label": %LegRightLabel},
}
@onready var total_label: Label = %TotalLabel

var health_system: Node = null


func _ready() -> void:
	await get_tree().process_frame
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	if mecha:
		health_system = mecha.get_node_or_null("HealthSystem")
		if health_system:
			health_system.health_changed.connect(_on_health_changed)
			_update_all_bars()


func _on_health_changed(slot_name: String, current_hp: float, max_hp: float) -> void:
	if not bars.has(slot_name):
		return
	var entry = bars[slot_name]
	var percent = current_hp / max_hp * 100.0
	entry["bar"].value = percent
	entry["label"].text = "%s: %d/%d" % [slot_name.to_upper(), int(current_hp), int(max_hp)]
	_update_total()


func _update_all_bars() -> void:
	if health_system == null:
		return
	for slot in health_system.parts:
		var part = health_system.parts[slot]
		_on_health_changed(slot, part["hp"], part["max_hp"])


func _update_total() -> void:
	if health_system == null:
		return
	var percent = health_system.get_health_percent() * 100.0
	total_label.text = "TOTAL: %d%%" % int(percent)
