class_name HangarSprayBooth
extends RefCounted

## Hangar Spray Booth — immersive paint shop for armor parts.
## Opens as a full modal over the hangar. Shows a 12-color military palette
## + custom ColorPicker, live swatch preview, spray can VFX and undo.
## The actual color is written to the same fields as the old PAINT button
## (`info["color"]` + `info["part_color"]` + equipped copy) so saves stay compatible.

var controller: Node = null
var booth_panel: Control = null

var _current_slot: String = ""
var _current_info: Dictionary = {}
var _selected_color: Color = Color(0.25, 0.40, 0.60)
var _original_color: Color = Color(0.25, 0.40, 0.60)
var _history: Array[Color] = []

# Expanded military palette — 16 swatches covering Valkyrion / Zaku / Ace tones
const PALETTE: Array[Color] = [
	Color(0.25, 0.40, 0.60), # Navy Blue
	Color(0.80, 0.20, 0.20), # Crimson Red
	Color(0.90, 0.90, 0.95), # Valkyrion White
	Color(0.20, 0.65, 0.35), # Zaku Green
	Color(0.85, 0.70, 0.20), # Gold Trim
	Color(0.20, 0.22, 0.26), # Dark Steel
	Color(0.55, 0.55, 0.58), # Titanium Grey
	Color(0.75, 0.35, 0.10), # Desert Sand / Rust
	Color(0.10, 0.55, 0.75), # Sky Blue
	Color(0.45, 0.15, 0.65), # Royal Purple
	Color(0.15, 0.75, 0.60), # Teal Aqua
	Color(0.90, 0.55, 0.10), # Safety Orange
	Color(0.30, 0.30, 0.32), # Gunmetal
	Color(0.60, 0.80, 0.20), # Lime Camo
	Color(0.85, 0.85, 0.80), # Off-White
	Color(0.05, 0.05, 0.08), # Jet Black
]

var _swatch_buttons: Array[Button] = []
var _preview_rect: ColorRect = null
var _spray_btn: Button = null
var _undo_btn: Button = null
var _custom_picker: ColorPickerButton = null


func is_open() -> bool:
	return booth_panel != null and is_instance_valid(booth_panel)


func close() -> void:
	if booth_panel and is_instance_valid(booth_panel):
		booth_panel.queue_free()
	booth_panel = null
	_swatch_buttons.clear()
	_preview_rect = null
	_spray_btn = null
	_undo_btn = null
	_custom_picker = null


func open(slot: String, info: Dictionary) -> void:
	if info.is_empty():
		return
	# Only armor instances can be painted (same gate as old PAINT button)
	if not info.has("uid"):
		if controller and controller.has_method("show_toast"):
			controller.show_toast("Craft or acquire this part before painting!", true)
		return
	close()
	_current_slot = slot
	_current_info = info
	_selected_color = info.get("color", info.get("part_color", PALETTE[0]))
	if _selected_color == Color.TRANSPARENT or _selected_color.a < 0.05:
		_selected_color = PALETTE[0]
	_original_color = _selected_color
	_history.clear()
	_history.append(_original_color)
	_build_modal()


func _build_modal() -> void:
	var root = controller.root_control if controller and controller.root_control else controller
	if root == null:
		return

	var overlay = PanelContainer.new()
	overlay.name = "SprayBoothModal"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	# Dim background behind booth
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.04, 0.05, 0.08, 0.92)
	bg_style.border_width_left = 2
	bg_style.border_width_top = 2
	bg_style.border_width_right = 2
	bg_style.border_width_bottom = 2
	bg_style.border_color = controller._accent_color if controller else Color(0.3, 0.6, 1.0)
	overlay.add_theme_stylebox_override("panel", bg_style)
	root.add_child(overlay)
	booth_panel = overlay

	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	# Center the booth card
	var center = CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay.add_child(center)

	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(720, 520)
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.10, 0.12, 0.18, 0.98)
	card_style.border_width_left = 1
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.border_color = Color(0.35, 0.65, 1.0, 0.9)
	card_style.corner_radius_top_left = 6
	card_style.corner_radius_top_right = 6
	card_style.corner_radius_bottom_left = 6
	card_style.corner_radius_bottom_right = 6
	card_style.content_margin_left = 16
	card_style.content_margin_right = 16
	card_style.content_margin_top = 14
	card_style.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	# ── Header ──
	var part_name = _current_info.get("name", _current_info.get("part_name", _current_slot))
	var header = Label.new()
	header.text = "🎨  SPRAY BOOTH  —  %s  [%s]" % [part_name.to_upper(), _current_slot.to_upper()]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	vbox.add_child(header)

	var sub = Label.new()
	sub.text = "เลือกสีพ่น • พรีวิว realtime บนหุ่น • กด SPRAY เพื่อพ่นสี"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	# ── Top row: Preview swatch + Spray can visual ──
	var top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 16)
	vbox.add_child(top_row)

	# Left: large preview swatch
	var preview_box = VBoxContainer.new()
	preview_box.custom_minimum_size = Vector2(200, 0)
	top_row.add_child(preview_box)

	var preview_label = Label.new()
	preview_label.text = "PREVIEW"
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.add_theme_font_size_override("font_size", 11)
	preview_label.add_theme_color_override("font_color", Color(0.6, 0.75, 0.95))
	preview_box.add_child(preview_label)

	var preview_frame = PanelContainer.new()
	preview_frame.custom_minimum_size = Vector2(180, 110)
	var pf_style = StyleBoxFlat.new()
	pf_style.bg_color = _selected_color
	pf_style.border_width_left = 2
	pf_style.border_width_top = 2
	pf_style.border_width_right = 2
	pf_style.border_width_bottom = 2
	pf_style.border_color = Color.WHITE
	pf_style.corner_radius_top_left = 4
	pf_style.corner_radius_top_right = 4
	pf_style.corner_radius_bottom_left = 4
	pf_style.corner_radius_bottom_right = 4
	preview_frame.add_theme_stylebox_override("panel", pf_style)
	preview_box.add_child(preview_frame)

	var inner_rect = ColorRect.new()
	inner_rect.color = _selected_color
	inner_rect.custom_minimum_size = Vector2(176, 106)
	preview_frame.add_child(inner_rect)
	_preview_rect = inner_rect

	var hex_lbl = Label.new()
	hex_lbl.text = "#%02X%02X%02X" % [int(_selected_color.r * 255), int(_selected_color.g * 255), int(_selected_color.b * 255)]
	hex_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hex_lbl.add_theme_font_size_override("font_size", 10)
	hex_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	preview_box.add_child(hex_lbl)
	# Store ref to update hex on color change
	hex_lbl.set_meta("is_hex_label", true)
	preview_box.set_meta("hex_label", hex_lbl)
	preview_box.set_meta("preview_frame", preview_frame)

	# Right: spray can illustration + info
	var can_box = VBoxContainer.new()
	can_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	can_box.add_theme_constant_override("separation", 6)
	top_row.add_child(can_box)

	var can_title = Label.new()
	can_title.text = "SPRAY CAN  •  %s" % _current_slot.to_upper()
	can_title.add_theme_font_size_override("font_size", 12)
	can_title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	can_box.add_child(can_title)

	var can_desc = Label.new()
	can_desc.text = "คลิกสีด้านล่างเพื่อพรีวิว • กด [ SPRAY ] เพื่อพ่นสีลงชิ้นส่วนจริง\nสีจะติดทันทีบนโมเดล 3D ในโรงเก็บ (turntable ด้านหลัง)"
	can_desc.add_theme_font_size_override("font_size", 11)
	can_desc.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
	can_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	can_box.add_child(can_desc)

	var cost_lbl = Label.new()
	cost_lbl.text = "Cost: FREE in Hangar  •  Undo ได้ 1 ครั้ง"
	cost_lbl.add_theme_font_size_override("font_size", 10)
	cost_lbl.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6))
	can_box.add_child(cost_lbl)

	vbox.add_child(HSeparator.new())

	# ── Palette grid ──
	var palette_title = Label.new()
	palette_title.text = "MILITARY PALETTE — คลิกเพื่อพรีวิว"
	palette_title.add_theme_font_size_override("font_size", 11)
	palette_title.add_theme_color_override("font_color", Color(0.6, 0.75, 0.95))
	vbox.add_child(palette_title)

	var grid = GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	for col in PALETTE:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(64, 32)
		var sb = StyleBoxFlat.new()
		sb.bg_color = col
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.border_color = Color.WHITE if col.is_equal_approx(_selected_color) else Color(0.2, 0.2, 0.25)
		sb.corner_radius_top_left = 3
		sb.corner_radius_top_right = 3
		sb.corner_radius_bottom_left = 3
		sb.corner_radius_bottom_right = 3
		btn.add_theme_stylebox_override("normal", sb)
		var sb_h = sb.duplicate()
		sb_h.border_color = Color(1.0, 0.9, 0.3)
		sb_h.bg_color = col.lightened(0.12)
		btn.add_theme_stylebox_override("hover", sb_h)
		btn.add_theme_stylebox_override("pressed", sb_h)
		btn.pressed.connect(_on_palette_pressed.bind(col, btn))
		grid.add_child(btn)
		_swatch_buttons.append(btn)

	# Custom color picker row
	var custom_row = HBoxContainer.new()
	custom_row.add_theme_constant_override("separation", 10)
	vbox.add_child(custom_row)

	var custom_lbl = Label.new()
	custom_lbl.text = "CUSTOM:"
	custom_lbl.add_theme_font_size_override("font_size", 11)
	custom_lbl.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))
	custom_row.add_child(custom_lbl)

	var picker = ColorPickerButton.new()
	picker.color = _selected_color
	picker.custom_minimum_size = Vector2(160, 28)
	picker.color_changed.connect(_on_custom_color_changed)
	custom_row.add_child(picker)
	_custom_picker = picker

	var custom_hint = Label.new()
	custom_hint.text = "← เลือกสีอิสระ (hex / wheel)"
	custom_hint.add_theme_font_size_override("font_size", 10)
	custom_hint.add_theme_color_override("font_color", Color(0.55, 0.60, 0.68))
	custom_row.add_child(custom_hint)

	vbox.add_child(HSeparator.new())

	# ── Action buttons ──
	var action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(action_row)

	var spray = Button.new()
	spray.text = "▶  SPRAY PAINT  !"
	spray.custom_minimum_size = Vector2(220, 42)
	var spray_style = StyleBoxFlat.new()
	spray_style.bg_color = Color(0.15, 0.65, 0.35, 0.95)
	spray_style.border_width_left = 1
	spray_style.border_width_top = 1
	spray_style.border_width_right = 1
	spray_style.border_width_bottom = 1
	spray_style.border_color = Color(0.4, 1.0, 0.6)
	spray_style.corner_radius_top_left = 4
	spray_style.corner_radius_top_right = 4
	spray_style.corner_radius_bottom_left = 4
	spray_style.corner_radius_bottom_right = 4
	spray.add_theme_stylebox_override("normal", spray_style)
	spray.add_theme_color_override("font_color", Color.WHITE)
	spray.add_theme_font_size_override("font_size", 13)
	spray.pressed.connect(_on_spray_pressed)
	action_row.add_child(spray)
	_spray_btn = spray

	var undo = Button.new()
	undo.text = "↩ UNDO"
	undo.custom_minimum_size = Vector2(110, 42)
	undo.disabled = true
	var undo_style = StyleBoxFlat.new()
	undo_style.bg_color = Color(0.22, 0.24, 0.30, 0.95)
	undo_style.border_width_left = 1
	undo_style.border_width_top = 1
	undo_style.border_width_right = 1
	undo_style.border_width_bottom = 1
	undo_style.border_color = Color(0.5, 0.55, 0.65)
	undo_style.corner_radius_top_left = 4
	undo_style.corner_radius_top_right = 4
	undo_style.corner_radius_bottom_left = 4
	undo_style.corner_radius_bottom_right = 4
	undo.add_theme_stylebox_override("normal", undo_style)
	undo.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	undo.pressed.connect(_on_undo_pressed)
	action_row.add_child(undo)
	_undo_btn = undo

	var close_btn = Button.new()
	close_btn.text = "CLOSE"
	close_btn.custom_minimum_size = Vector2(110, 42)
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.28, 0.18, 0.18, 0.95)
	close_style.border_width_left = 1
	close_style.border_width_top = 1
	close_style.border_width_right = 1
	close_style.border_width_bottom = 1
	close_style.border_color = Color(0.85, 0.35, 0.35)
	close_style.corner_radius_top_left = 4
	close_style.corner_radius_top_right = 4
	close_style.corner_radius_bottom_left = 4
	close_style.corner_radius_bottom_right = 4
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.85))
	close_btn.pressed.connect(close)
	action_row.add_child(close_btn)

	# ESC also closes (handled by hangar_controller._input pause gate, so add direct)
	overlay.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			close()
	)


func _on_palette_pressed(col: Color, _btn: Button) -> void:
	_selected_color = col
	if _custom_picker:
		_custom_picker.color = col
	_refresh_preview()


func _on_custom_color_changed(col: Color) -> void:
	_selected_color = col
	_refresh_preview()


func _refresh_preview() -> void:
	if _preview_rect:
		_preview_rect.color = _selected_color
	# Update hex label and preview frame border
	if booth_panel:
		var card = booth_panel.find_child("PanelContainer", true, false)
		# Find hex label via traversal
		for lbl in booth_panel.find_children("*", "Label", true, false):
			if lbl.has_meta("is_hex_label"):
				lbl.text = "#%02X%02X%02X" % [int(_selected_color.r * 255), int(_selected_color.g * 255), int(_selected_color.b * 255)]
				break
	# Highlight active swatch
	for i in range(_swatch_buttons.size()):
		var btn = _swatch_buttons[i]
		if not is_instance_valid(btn):
			continue
		var col = PALETTE[i] if i < PALETTE.size() else Color.WHITE
		var is_active = col.is_equal_approx(_selected_color)
		for state in ["normal", "hover", "pressed"]:
			var sb = btn.get_theme_stylebox(state) as StyleBoxFlat
			if sb:
				sb.border_color = Color(1.0, 0.9, 0.3) if is_active else (Color.WHITE if state == "normal" and is_active else Color(0.2, 0.2, 0.25))
	# Live 3D preview: tint the mech part in garage without saving yet
	if controller and controller.garage_panel:
		var preview_info = _current_info.duplicate(true)
		preview_info["color"] = _selected_color
		preview_info["part_color"] = _selected_color
		controller.garage_panel.apply_armor_preview(_current_slot, preview_info)


func _on_spray_pressed() -> void:
	# Apply to data
	var prev_color: Color = _current_info.get("color", _current_info.get("part_color", _original_color))
	_history.append(prev_color)
	if _history.size() > 8:
		_history.remove_at(0)
	if _undo_btn:
		_undo_btn.disabled = false

	_current_info["color"] = _selected_color
	_current_info["part_color"] = _selected_color

	# Sync equipped copy if this instance is mounted (same uid gate as old PAINT)
	var equipped = GlobalData.weapons.equipped_parts.get(_current_slot)
	if equipped is Dictionary and _current_info.has("uid") and equipped.get("uid", "") == str(_current_info["uid"]):
		equipped["color"] = _selected_color
		equipped["part_color"] = _selected_color

	GlobalData.save_run()

	if controller:
		controller.status_message_label.text = "SPRAYED: %s → #%02X%02X%02X" % [_current_slot.to_upper(), int(_selected_color.r*255), int(_selected_color.g*255), int(_selected_color.b*255)]
		if controller.has_method("show_toast"):
			controller.show_toast("Spray paint applied!", false)
		controller.refresh_after_part_mutation(_current_slot)

	_spawn_spray_vfx()
	_original_color = _selected_color


func _on_undo_pressed() -> void:
	if _history.is_empty():
		return
	var undo_color: Color = _history.pop_back()
	_selected_color = undo_color
	_current_info["color"] = undo_color
	_current_info["part_color"] = undo_color
	var equipped = GlobalData.weapons.equipped_parts.get(_current_slot)
	if equipped is Dictionary and _current_info.has("uid") and equipped.get("uid", "") == str(_current_info["uid"]):
		equipped["color"] = undo_color
		equipped["part_color"] = undo_color
	if _custom_picker:
		_custom_picker.color = undo_color
	_refresh_preview()
	GlobalData.save_run()
	if controller:
		controller.refresh_after_part_mutation(_current_slot)
		controller.status_message_label.text = "Undo: restored previous color"
	if _history.is_empty() and _undo_btn:
		_undo_btn.disabled = true
	_spawn_spray_vfx(true)


func _spawn_spray_vfx(is_undo: bool = false) -> void:
	if controller == null or controller.garage_panel == null:
		return
	var mecha = controller.garage_panel.get_mecha_base()
	if mecha == null:
		return
	# Find world position of the painted slot for the puff
	var slot_node = mecha.get_node_or_null(GlobalData.SLOT_TO_NODE.get(_current_slot, ""))
	var puff_pos := Vector3(0, 1.2, 0)
	if slot_node and slot_node is Node3D:
		puff_pos = (slot_node as Node3D).global_position + Vector3(0, 0.5, 0.6)
	else:
		puff_pos = mecha.global_position + Vector3(0, 1.2, 0.8)

	var tree = controller.get_tree()
	if tree == null:
		return
	var col = _selected_color
	if is_undo:
		col = Color(0.7, 0.72, 0.75)
	# Quick spray cone particles using EffectFactory flashes + dust
	EffectFactory.spawn_flash(tree, puff_pos, col, 0.55, 0.35, 4.0, true, 1.8)
	EffectFactory.spawn_dust_puffs(tree, puff_pos, 6, 0.12, 0.22, 0.6, 1.1, Color(col.r, col.g, col.b, 0.55), 0.35)
	# Extra sparkle for the can nozzle
	EffectFactory.spawn_flash(tree, puff_pos + Vector3(0.4, 0.3, 0.5), Color.WHITE, 0.18, 0.15, 6.0, true, 2.0)
	if AudioManager:
		AudioManager.play_sfx("spray_paint" if AudioManager.sfx._sound_cache.has("spray_paint") else "ui_confirm", puff_pos, -2.0)
		AudioManager.play_ui_confirm()
