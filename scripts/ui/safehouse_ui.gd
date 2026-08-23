extends CanvasLayer

## Safehouse UI: repair individual parts or all, cost based on % HP damaged.

var root_control: Control
var panel: PanelContainer
var title_label: Label
var info_label: Label
var parts_container: VBoxContainer
var repair_all_button: Button
var sacrifice_button: Button
var leave_button: Button
var status_label: Label

const COST_PER_HP: float = 0.5  # credits per 1 HP repaired (shared with GlobalData)


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
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
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
	info_label.text = "The fleet mechanic rebuilds damaged armor from the catalog.\nStandard repair: %.1f credits per HP. Rebuilding a scrap patch is a flat catalog price." % COST_PER_HP
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

	# SACRIFICE MISSION (GDD §5): only offered when the pilot-mech bond has
	# peaked AND the machine is wrecked — push the old warhorse to its limits.
	sacrifice_button = Button.new()
	sacrifice_button.name = "SacrificeMissionButton"
	sacrifice_button.text = "SACRIFICE MISSION - Push the old warhorse to its limits"
	sacrifice_button.custom_minimum_size = Vector2(460, 40)
	sacrifice_button.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	sacrifice_button.visible = false
	sacrifice_button.pressed.connect(_on_sacrifice_pressed)
	vbox.add_child(sacrifice_button)

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

	# Sacrifice mission offer: visible only while the narrative flag is armed
	# (bond >= 80 + wrecked machine) and not yet triggered.
	sacrifice_button.visible = GlobalData.narrative.sacrifice_event_available \
		and not GlobalData.narrative.sacrifice_event_triggered

	var total_cost = 0
	var has_damaged = false

	for slot in GlobalData.MECHA_SLOTS:
		var cost := RepairSystem.get_repair_cost(slot)
		if cost <= 0:
			continue

		has_damaged = true
		total_cost += cost

		var btn = Button.new()
		btn.custom_minimum_size = Vector2(460, 32)

		var part_name = slot.to_upper()
		var part = GlobalData.weapons.equipped_parts.get(slot)
		if part is ArmorPart:
			part_name = part.part_name
		elif part is Dictionary:
			part_name = part.get("name", part.get("part_name", part_name))

		var frame_dmg = GlobalData.weapons.part_damage.get(slot + "_frame", 0.0)
		var status = "BROKEN" if frame_dmg >= 1.0 else "DAMAGED"
		btn.text = "%s [%s] - Cost: %d credits" % [part_name, status, cost]
		btn.pressed.connect(_on_repair_part_pressed.bind(slot))
		parts_container.add_child(btn)

	if not has_damaged:
		var lbl = Label.new()
		lbl.text = "All parts are in good condition."
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		parts_container.add_child(lbl)
		repair_all_button.disabled = true
	else:
		repair_all_button.text = "Repair All Parts - %d credits" % total_cost
		repair_all_button.disabled = GlobalData.currency.credits < total_cost

	# --- Professional rebuild of scrap patches (mechanic restores catalog armor) ---
	var patched := false
	for slot in GlobalData.MECHA_SLOTS:
		if not GlobalData.has_scrap_patch(slot):
			continue
		patched = true
		var cost: int = GlobalData.get_professional_repair_cost(slot)
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(460, 32)
		btn.text = "Rebuild Catalog Armor: %s (%d credits)" % [slot.to_upper(), cost]
		btn.disabled = GlobalData.currency.credits < cost
		btn.pressed.connect(_on_rebuild_catalog_pressed.bind(slot))
		parts_container.add_child(btn)
	if patched:
		var note = Label.new()
		note.text = "Scrap patches are weaker than real armor. Rebuild them here."
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", 11)
		parts_container.add_child(note)

	status_label.text = "Credits: %d" % GlobalData.currency.credits


func _on_rebuild_catalog_pressed(slot: String) -> void:
	if GlobalData.apply_professional_repair(slot):
		status_label.text = "Mechanic rebuilt %s with fresh catalog armor! Credits: %d" % [slot.to_upper(), GlobalData.currency.credits]
	else:
		status_label.text = "Not enough credits for a professional rebuild!"
	_refresh_parts_list()


func _on_repair_part_pressed(slot: String) -> void:
	var cost := RepairSystem.get_repair_cost(slot)
	if not GlobalData.currency.try_spend_credits(cost):
		status_label.text = "Not enough credits!"
		return

	GlobalData.weapons.part_damage.erase(slot)
	GlobalData.weapons.part_damage.erase(slot + "_frame")
	# Repair bond (GDD §5): repairing the mech strengthens the pilot-mech bond.
	GlobalData.narrative.record_repair()
	status_label.text = "Repaired! Credits: %d" % GlobalData.currency.credits
	_refresh_parts_list()


func _on_repair_all_pressed() -> void:
	var total_cost := 0
	for slot in GlobalData.MECHA_SLOTS:
		total_cost += RepairSystem.get_repair_cost(slot)

	if not GlobalData.currency.try_spend_credits(total_cost):
		status_label.text = "Not enough credits! Need %d" % total_cost
		return

	GlobalData.weapons.part_damage.clear()
	status_label.text = "All repaired! Credits: %d" % GlobalData.currency.credits
	_refresh_parts_list()


func _on_sacrifice_pressed() -> void:
	var se := get_tree().get_first_node_in_group("sacrifice_event")
	if se == null or not se.has_method("start_sacrifice_event"):
		status_label.text = "The sacrifice mission cannot begin here."
		return
	visible = false
	get_tree().paused = false
	se.start_sacrifice_event()


func _on_leave_pressed() -> void:
	visible = false
	get_tree().paused = false
	# Return to board movement mode (tile clicks drive movement — no flag needed)
	EventBus.repair_requested.emit()
