extends Control

var part_list: ItemList
var stats_label: Label
var weight_label: Label
var repair_button: Button


func _ready() -> void:
	_create_ui()


func _create_ui() -> void:
	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 20
	hbox.offset_right = -20
	hbox.offset_top = 20
	hbox.offset_bottom = -20
	add_child(hbox)

	# Parts list
	var left_panel = VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(300, 0)
	hbox.add_child(left_panel)
	var title = Label.new()
	title.text = "Hangar - Parts"
	left_panel.add_child(title)
	part_list = ItemList.new()
	part_list.custom_minimum_size = Vector2(280, 400)
	left_panel.add_child(part_list)

	# Stats panel
	var right_panel = VBoxContainer.new()
	right_panel.custom_minimum_size = Vector2(300, 0)
	hbox.add_child(right_panel)
	stats_label = Label.new()
	stats_label.text = "Select a part"
	right_panel.add_child(stats_label)
	weight_label = Label.new()
	weight_label.text = "Total Weight: 0"
	right_panel.add_child(weight_label)
	repair_button = Button.new()
	repair_button.text = "Repair (10 credits)"
	repair_button.pressed.connect(_on_repair_pressed)
	right_panel.add_child(repair_button)


func _on_repair_pressed() -> void:
	if GlobalData.credits >= 10:
		GlobalData.credits -= 10
		GlobalData.part_damage.clear()
		EventBus.weight_changed.emit(0.0)
		_refresh_parts()


func refresh() -> void:
	_refresh_parts()


func _refresh_parts() -> void:
	if part_list == null:
		return
	part_list.clear()
	var total_weight = 0.0
	for slot in GlobalData.equipped_parts:
		var part: ArmorPart = GlobalData.equipped_parts[slot]
		var damage = GlobalData.part_damage.get(slot, 0.0)
		var status = "OK" if damage < part.break_threshold else "BROKEN"
		part_list.add_item("%s [%s] - %s" % [part.part_name, slot, status])
		if damage < part.break_threshold:
			total_weight += part.weight
	if weight_label:
		weight_label.text = "Total Weight: %.1f" % total_weight
