extends CanvasLayer

@onready var head_bar: ProgressBar = %HeadBar
@onready var body_bar: ProgressBar = %BodyBar
@onready var legs_bar: ProgressBar = %LegsBar
@onready var head_label: Label = %HeadLabel
@onready var body_label: Label = %BodyLabel
@onready var legs_label: Label = %LegsLabel
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
	var percent = current_hp / max_hp * 100.0
	match slot_name:
		"head":
			head_bar.value = percent
			head_label.text = "HEAD: %d/%d" % [int(current_hp), int(max_hp)]
		"body":
			body_bar.value = percent
			body_label.text = "BODY: %d/%d" % [int(current_hp), int(max_hp)]
		"legs":
			legs_bar.value = percent
			legs_label.text = "LEGS: %d/%d" % [int(current_hp), int(max_hp)]
	_update_total()


func _update_all_bars() -> void:
	if health_system == null:
		return
	for slot in health_system.parts:
		var part = health_system.parts[slot]
		var percent = part["hp"] / part["max_hp"] * 100.0
		_on_health_changed(slot, part["hp"], part["max_hp"])


func _update_total() -> void:
	if health_system == null:
		return
	var percent = health_system.get_health_percent() * 100.0
	total_label.text = "TOTAL: %d%%" % int(percent)
