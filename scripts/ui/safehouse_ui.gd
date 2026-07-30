extends CanvasLayer

## Safehouse UI: repair individual parts or all, cost based on % HP damaged.

var root_control: Control
var panel: PanelContainer
var title_label: Label
var info_label: Label
var parts_container: VBoxContainer
var repair_all_button: Button
var leave_button: Button
var status_label: Label

const COST_PER_HP: float = 0.5  # credits per 1 HP repaired


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()
	visible = false
	EventBus.tile_entered.connect(_on_tile_entered)


func _create_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	# Center panel
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -250
	panel.offset_right = 250
	panel.offset_top = -250
	panel.offset_bottom = 250
	root_control.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.2, 0.1, 0.95)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	title_label = Label.new()
	title_label.text = "SAFEHOUSE"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title_label)

	var separator = HSeparator.new()
	vbox.add_child(separator)

	info_label = Label.new()
	info_label.text = "Select parts to repair. Cost: %.1f credits per HP." % COST_PER_HP
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(info_label)

	# Scrollable parts list
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	parts_container = VBoxContainer.new()
	parts_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parts_container.add_theme_constant_override("separation", 4)
	scroll.add_child(parts_container)

	# Repair All button
	repair_all_button = Button.new()
	repair_all_button.text = "Repair All Parts"
	repair_all_button.custom_minimum_size = Vector2(460, 36)
	repair_all_button.pressed.connect(_on_repair_all_pressed)
	vbox.add_child(repair_all_button)

	leave_button = Button.new()
	leave_button.text = "Leave Safehouse"
	leave_button.custom_minimum_size = Vector2(460, 36)
	leave_button.pressed.connect(_on_leave_pressed)
	vbox.add_child(leave_button)

	status_label = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)


func _on_tile_entered(pos: Vector2i, _data: Node) -> void:
	var tile_type = _get_tile_type(pos)
	if tile_type == "safehouse":
		visible = true
		_refresh_parts_list()
		get_tree().paused = true


func _get_tile_type(pos: Vector2i) -> String:
	var scene = get_tree().current_scene
	if scene and scene.has_method("get_tile_type"):
		return scene.get_tile_type(pos)
	return "empty"


func _refresh_parts_list() -> void:
	# Clear old buttons
	for child in parts_container.get_children():
		child.queue_free()

	var total_cost = 0.0
	var has_damaged = false

	for slot in GlobalData.equipped_parts:
		var part = GlobalData.equipped_parts[slot]
		if part == null or not (part is ArmorPart):
			continue

		var damage = GlobalData.part_damage.get(slot, 0.0)
		if damage <= 0.0:
			continue

		has_damaged = true
		var repairable_hp = damage * part.max_hp
		var cost = repairable_hp * COST_PER_HP
		total_cost += cost

		var btn = Button.new()
		btn.custom_minimum_size = Vector2(460, 32)

		var status = "OK" if damage < part.break_threshold else "BROKEN"
		btn.text = "%s [%s] - Damaged: %.0f HP - Cost: %d credits" % [
			part.part_name, status, repairable_hp, int(cost)
		]
		btn.pressed.connect(_on_repair_part_pressed.bind(slot, cost))
		parts_container.add_child(btn)

	if not has_damaged:
		var lbl = Label.new()
		lbl.text = "All parts are in good condition."
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		parts_container.add_child(lbl)
		repair_all_button.disabled = true
	else:
		repair_all_button.text = "Repair All Parts - %d credits" % int(total_cost)
		repair_all_button.disabled = GlobalData.credits < int(total_cost)

	status_label.text = "Credits: %d" % GlobalData.credits


func _on_repair_part_pressed(slot: String, cost: float) -> void:
	if GlobalData.credits < int(cost):
		status_label.text = "Not enough credits!"
		return

	GlobalData.credits -= int(cost)
	GlobalData.part_damage.erase(slot)
	status_label.text = "Repaired! Credits: %d" % GlobalData.credits
	_refresh_parts_list()


func _on_repair_all_pressed() -> void:
	var total_cost = 0.0
	var slots_to_repair: Array = []

	for slot in GlobalData.equipped_parts:
		var part = GlobalData.equipped_parts[slot]
		if part == null or not (part is ArmorPart):
			continue
		var damage = GlobalData.part_damage.get(slot, 0.0)
		if damage > 0.0:
			var cost = damage * part.max_hp * COST_PER_HP
			total_cost += cost
			slots_to_repair.append(slot)

	if GlobalData.credits < int(total_cost):
		status_label.text = "Not enough credits! Need %d" % int(total_cost)
		return

	GlobalData.credits -= int(total_cost)
	for slot in slots_to_repair:
		GlobalData.part_damage.erase(slot)
	status_label.text = "All repaired! Credits: %d" % GlobalData.credits
	_refresh_parts_list()


func _on_leave_pressed() -> void:
	visible = false
	get_tree().paused = false
	# Return to board movement mode
	var board = get_tree().current_scene
	if board:
		board.set("showing_board", true)
	EventBus.repair_requested.emit()
