extends CanvasLayer

var root_control: Control
var part_list: ItemList
var stats_label: Label
var weight_label: Label
var repair_button: Button
var repair_part_button: Button
var close_button: Label
var status_label: Label

const COST_PER_HP: float = 0.5
var selected_slot: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()
	visible = false


func _create_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	# Main panel
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -350
	panel.offset_right = 350
	panel.offset_top = -250
	panel.offset_bottom = 250
	root_control.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	panel.add_child(hbox)

	# Parts list (left side)
	var left_panel = VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(300, 0)
	hbox.add_child(left_panel)

	var title = Label.new()
	title.text = "HANGAR - PARTS"
	title.add_theme_font_size_override("font_size", 18)
	left_panel.add_child(title)

	var sep = HSeparator.new()
	left_panel.add_child(sep)

	part_list = ItemList.new()
	part_list.custom_minimum_size = Vector2(280, 350)
	part_list.item_selected.connect(_on_part_selected)
	left_panel.add_child(part_list)

	# Stats panel (right side)
	var right_panel = VBoxContainer.new()
	right_panel.custom_minimum_size = Vector2(300, 0)
	hbox.add_child(right_panel)

	stats_label = Label.new()
	stats_label.text = "Select a part to view stats"
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_panel.add_child(stats_label)

	var sep2 = HSeparator.new()
	right_panel.add_child(sep2)

	weight_label = Label.new()
	weight_label.text = "Total Weight: 0"
	right_panel.add_child(weight_label)

	repair_part_button = Button.new()
	repair_part_button.text = "Repair Selected Part"
	repair_part_button.custom_minimum_size = Vector2(280, 36)
	repair_part_button.pressed.connect(_on_repair_part_pressed)
	right_panel.add_child(repair_part_button)

	repair_button = Button.new()
	repair_button.text = "Full Repair"
	repair_button.custom_minimum_size = Vector2(280, 40)
	repair_button.pressed.connect(_on_repair_pressed)
	right_panel.add_child(repair_button)

	status_label = Label.new()
	status_label.text = ""
	right_panel.add_child(status_label)

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(spacer)

	close_button = Label.new()
	close_button.text = "Press ESC to close"
	close_button.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_panel.add_child(close_button)


func show_hangar() -> void:
	visible = true
	_refresh_parts()
	get_tree().paused = true


func _on_part_selected(index: int) -> void:
	if index < 0:
		return
	selected_slot = GlobalData.equipped_parts.keys()[index]
	var part: ArmorPart = GlobalData.equipped_parts[selected_slot]
	if part:
		var dmg = GlobalData.part_damage.get(selected_slot, 0.0)
		var status = "OK" if dmg < part.break_threshold else "BROKEN"
		var current_hp = part.max_hp - (dmg * part.max_hp)
		var repair_hp = dmg * part.max_hp
		var cost = int(repair_hp * COST_PER_HP)
		stats_label.text = "Name: %s\nSlot: %s\nStatus: %s\n\nHP: %.0f / %.0f\nWeight: %.1f\nArmor Class: %.1f\nBreak Threshold: %.0f%%\n\nRepair Cost: %d credits (%.0f HP)" % [
			part.part_name, selected_slot, status,
			current_hp, part.max_hp,
			part.weight, part.armor_class, part.break_threshold * 100,
			cost, repair_hp
		]
		repair_part_button.text = "Repair %s - %d credits" % [part.part_name, cost]
		repair_part_button.disabled = GlobalData.credits < cost or dmg <= 0.0


func _on_repair_part_pressed() -> void:
	if selected_slot == "" or not GlobalData.equipped_parts.has(selected_slot):
		status_label.text = "Select a part first!"
		return

	var part: ArmorPart = GlobalData.equipped_parts[selected_slot]
	var dmg = GlobalData.part_damage.get(selected_slot, 0.0)
	if dmg <= 0.0:
		status_label.text = "Part is already OK!"
		return

	var cost = int(dmg * part.max_hp * COST_PER_HP)
	if GlobalData.credits < cost:
		status_label.text = "Not enough credits! Need %d" % cost
		return

	GlobalData.credits -= cost
	GlobalData.part_damage.erase(selected_slot)
	EventBus.weight_changed.emit(0.0)
	status_label.text = "Repaired %s! Credits: %d" % [part.part_name, GlobalData.credits]
	_refresh_parts()


func _on_repair_pressed() -> void:
	var total_cost = 0.0
	var slots_to_repair: Array = []
	for slot in GlobalData.equipped_parts:
		var part: ArmorPart = GlobalData.equipped_parts[slot]
		var dmg = GlobalData.part_damage.get(slot, 0.0)
		if dmg > 0.0:
			var cost = dmg * part.max_hp * COST_PER_HP
			total_cost += cost
			slots_to_repair.append(slot)

	if slots_to_repair.is_empty():
		status_label.text = "All parts are OK!"
		return

	if GlobalData.credits < int(total_cost):
		status_label.text = "Not enough credits! Need %d" % int(total_cost)
		return

	GlobalData.credits -= int(total_cost)
	for slot in slots_to_repair:
		GlobalData.part_damage.erase(slot)
	EventBus.weight_changed.emit(0.0)
	status_label.text = "All repaired! Credits: %d" % GlobalData.credits
	_refresh_parts()


func _refresh_parts() -> void:
	if part_list == null:
		return
	part_list.clear()
	var total_weight = 0.0
	var total_repair_cost = 0.0
	for slot in GlobalData.equipped_parts:
		var part: ArmorPart = GlobalData.equipped_parts[slot]
		var dmg = GlobalData.part_damage.get(slot, 0.0)
		var status = "OK" if dmg < part.break_threshold else "BROKEN"
		var cost = int(dmg * part.max_hp * COST_PER_HP) if dmg > 0.0 else 0
		var label = "%s [%s] - %s" % [part.part_name, slot, status]
		if cost > 0:
			label += " (%d cr)" % cost
			total_repair_cost += cost
		part_list.add_item(label)
		if dmg < part.break_threshold:
			total_weight += part.weight
	if weight_label:
		weight_label.text = "Total Weight: %.1f" % total_weight
	repair_button.text = "Full Repair - %d credits" % int(total_repair_cost)
	repair_button.disabled = GlobalData.credits < int(total_repair_cost) or total_repair_cost <= 0


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		visible = false
		get_tree().paused = false
