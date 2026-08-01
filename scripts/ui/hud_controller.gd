extends Control

var armor_bars: Dictionary = {}
var frame_bars: Dictionary = {}
var heat_label: Label
var wanted_label: Label


func _ready() -> void:
	_create_ui()
	EventBus.damage_received.connect(_on_damage_received)
	EventBus.part_destroyed.connect(_on_part_destroyed)
	EventBus.heat_changed.connect(_on_heat_changed)
	EventBus.wanted_changed.connect(_on_wanted_changed)


func _create_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	vbox.offset_right = -20
	vbox.offset_top = 20
	add_child(vbox)

	for slot in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
		var slot_vbox = VBoxContainer.new()
		vbox.add_child(slot_vbox)

		var label = Label.new()
		label.text = slot.capitalize()
		slot_vbox.add_child(label)

		# Armor bar
		var armor_hbox = HBoxContainer.new()
		slot_vbox.add_child(armor_hbox)
		var armor_label = Label.new()
		armor_label.text = "Armor: "
		armor_label.custom_minimum_size = Vector2(50, 0)
		armor_hbox.add_child(armor_label)
		var armor_bar = ProgressBar.new()
		armor_bar.custom_minimum_size = Vector2(120, 12)
		armor_bar.max_value = 100
		armor_bar.value = 100
		armor_hbox.add_child(armor_bar)
		armor_bars[slot] = armor_bar

		# Frame bar
		var frame_hbox = HBoxContainer.new()
		slot_vbox.add_child(frame_hbox)
		var frame_label = Label.new()
		frame_label.text = "Frame: "
		frame_label.custom_minimum_size = Vector2(50, 0)
		frame_hbox.add_child(frame_label)
		var frame_bar = ProgressBar.new()
		frame_bar.custom_minimum_size = Vector2(120, 12)
		frame_bar.max_value = 100
		frame_bar.value = 100
		frame_hbox.add_child(frame_bar)
		frame_bars[slot] = frame_bar

	heat_label = Label.new()
	heat_label.text = "Heat: 0"
	vbox.add_child(heat_label)

	wanted_label = Label.new()
	wanted_label.text = "Wanted: 0"
	vbox.add_child(wanted_label)


func _on_damage_received(slot_name: String, _raw_damage: float, _damage_type: String) -> void:
	if armor_bars.has(slot_name):
		# Key format matches mecha_health_base: "slot_name" = armor damage ratio
		var armor_dmg = GlobalData.part_damage.get(slot_name, 0.0)
		armor_bars[slot_name].value = (1.0 - armor_dmg) * 100.0
	if frame_bars.has(slot_name):
		# Key format matches mecha_health_base: "slot_name_frame" = frame damage ratio
		var frame_dmg = GlobalData.part_damage.get(slot_name + "_frame", 0.0)
		frame_bars[slot_name].value = (1.0 - frame_dmg) * 100.0


func _on_part_destroyed(slot_name: String) -> void:
	if armor_bars.has(slot_name):
		armor_bars[slot_name].value = 0


func _on_heat_changed(new_heat: int) -> void:
	if heat_label:
		heat_label.text = "Heat: %d" % new_heat


func _on_wanted_changed(new_wanted: int) -> void:
	if wanted_label:
		wanted_label.text = "Wanted: %d" % new_wanted
