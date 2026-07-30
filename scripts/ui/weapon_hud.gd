extends CanvasLayer

var weapon_manager: Node = null
var root_control: Control

var left_panel: PanelContainer
var left_name_label: Label
var left_ammo_label: Label
var left_type_label: Label

var right_panel: PanelContainer
var right_name_label: Label
var right_ammo_label: Label
var right_type_label: Label

var carry_panel: PanelContainer
var carry_container: VBoxContainer
var hand_label: Label

var left_holding: bool = false
var right_holding: bool = false

var _bg_color: Color = Color(0.08, 0.08, 0.12, 0.85)
var _accent_color: Color = Color(0.3, 0.6, 1.0, 1)
var _highlight_color: Color = Color(1.0, 0.9, 0.3, 1)
var _dim_color: Color = Color(0.5, 0.5, 0.5, 1)

const WEAPON_ICONS: Dictionary = {
	0: "[RIFLE]", 1: "[MG]", 2: "[MISSILE]",
	3: "[SPREAD]", 4: "[BLADE]", 5: "[SHIELD]",
}


func _ready() -> void:
	_create_root()
	_create_left_panel()
	_create_right_panel()
	_create_carry_ui()
	_try_connect_weapon_manager()


func _process(_delta: float) -> void:
	if weapon_manager == null:
		_try_connect_weapon_manager()


func _try_connect_weapon_manager() -> void:
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	if mecha == null:
		return
	var wm = mecha.get_node_or_null("WeaponManager")
	if wm == null:
		return
	if weapon_manager == wm:
		return
	weapon_manager = wm
	weapon_manager.weapon_switched.connect(_on_weapon_switched)
	weapon_manager.ammo_changed.connect(_on_ammo_changed)
	weapon_manager.carry_updated.connect(_on_carry_updated)
	weapon_manager._emit_initial_state()
	_update_display()


func _input(event: InputEvent) -> void:
	if weapon_manager == null:
		return

	if event.is_action_pressed("weapon_left"):
		left_holding = true
		_show_carry("left")
	elif event.is_action_released("weapon_left"):
		left_holding = false
		_hide_carry()

	if event.is_action_pressed("weapon_right"):
		right_holding = true
		_show_carry("right")
	elif event.is_action_released("weapon_right"):
		right_holding = false
		_hide_carry()

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if left_holding or right_holding:
				_update_carry_display("left" if left_holding else "right")


func _create_root() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)


func _make_panel_style(bg_color: Color = _bg_color, corner: int = 8) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = corner
	style.corner_radius_top_right = corner
	style.corner_radius_bottom_left = corner
	style.corner_radius_bottom_right = corner
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.4, 0.6, 0.4)
	return style


func _create_left_panel() -> void:
	left_panel = PanelContainer.new()
	left_panel.anchor_left = 0.0
	left_panel.anchor_top = 1.0
	left_panel.anchor_right = 0.0
	left_panel.anchor_bottom = 1.0
	left_panel.offset_left = 20
	left_panel.offset_right = 220
	left_panel.offset_top = -110
	left_panel.offset_bottom = -20
	left_panel.add_theme_stylebox_override("panel", _make_panel_style())
	left_panel.visible = true
	root_control.add_child(left_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	left_panel.add_child(vbox)

	left_type_label = Label.new()
	left_type_label.text = ""
	left_type_label.add_theme_font_size_override("font_size", 10)
	left_type_label.add_theme_color_override("font_color", _accent_color)
	vbox.add_child(left_type_label)

	left_name_label = Label.new()
	left_name_label.text = "--- EMPTY ---"
	left_name_label.add_theme_font_size_override("font_size", 16)
	left_name_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(left_name_label)

	left_ammo_label = Label.new()
	left_ammo_label.text = ""
	left_ammo_label.add_theme_font_size_override("font_size", 22)
	left_ammo_label.add_theme_color_override("font_color", _highlight_color)
	vbox.add_child(left_ammo_label)

	var key_hint = Label.new()
	key_hint.text = "[LMB] Fire  |  [1] Switch"
	key_hint.add_theme_font_size_override("font_size", 9)
	key_hint.add_theme_color_override("font_color", _dim_color)
	vbox.add_child(key_hint)


func _create_right_panel() -> void:
	right_panel = PanelContainer.new()
	right_panel.anchor_left = 1.0
	right_panel.anchor_top = 1.0
	right_panel.anchor_right = 1.0
	right_panel.anchor_bottom = 1.0
	right_panel.offset_left = -220
	right_panel.offset_right = -20
	right_panel.offset_top = -110
	right_panel.offset_bottom = -20
	right_panel.add_theme_stylebox_override("panel", _make_panel_style())
	right_panel.visible = true
	root_control.add_child(right_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	right_panel.add_child(vbox)

	right_type_label = Label.new()
	right_type_label.text = ""
	right_type_label.add_theme_font_size_override("font_size", 10)
	right_type_label.add_theme_color_override("font_color", _accent_color)
	vbox.add_child(right_type_label)

	right_name_label = Label.new()
	right_name_label.text = "--- EMPTY ---"
	right_name_label.add_theme_font_size_override("font_size", 16)
	right_name_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(right_name_label)

	right_ammo_label = Label.new()
	right_ammo_label.text = ""
	right_ammo_label.add_theme_font_size_override("font_size", 22)
	right_ammo_label.add_theme_color_override("font_color", _highlight_color)
	vbox.add_child(right_ammo_label)

	var key_hint = Label.new()
	key_hint.text = "[RMB] Fire  |  [3] Switch"
	key_hint.add_theme_font_size_override("font_size", 9)
	key_hint.add_theme_color_override("font_color", _dim_color)
	vbox.add_child(key_hint)


func _create_carry_ui() -> void:
	carry_panel = PanelContainer.new()
	carry_panel.anchor_left = 0.0
	carry_panel.anchor_top = 0.5
	carry_panel.anchor_right = 0.0
	carry_panel.anchor_bottom = 0.5
	carry_panel.offset_left = 20
	carry_panel.offset_right = 260
	carry_panel.offset_top = -150
	carry_panel.offset_bottom = 150
	carry_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.05, 0.1, 0.92)))
	root_control.add_child(carry_panel)
	carry_panel.visible = false

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	carry_panel.add_child(vbox)

	hand_label = Label.new()
	hand_label.text = "LEFT HAND"
	hand_label.add_theme_font_size_override("font_size", 14)
	hand_label.add_theme_color_override("font_color", _accent_color)
	vbox.add_child(hand_label)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	carry_container = VBoxContainer.new()
	carry_container.add_theme_constant_override("separation", 1)
	vbox.add_child(carry_container)


func _show_carry(hand: String) -> void:
	if weapon_manager == null:
		return

	carry_panel.visible = true

	var viewport_width = get_viewport().get_visible_rect().size.x
	if hand == "left":
		carry_panel.anchor_left = 0.0
		carry_panel.anchor_right = 0.0
		carry_panel.offset_left = 20
		carry_panel.offset_right = 260
		hand_label.text = "LEFT HAND"
	else:
		carry_panel.anchor_left = 1.0
		carry_panel.anchor_right = 1.0
		carry_panel.offset_left = -260
		carry_panel.offset_right = -20
		hand_label.text = "RIGHT HAND"

	_update_carry_display(hand)


func _hide_carry() -> void:
	carry_panel.visible = false


func _update_carry_display(hand: String) -> void:
	if weapon_manager == null:
		return

	for child in carry_container.get_children():
		child.queue_free()

	var list: Array = weapon_manager.carry
	var highlight_idx = weapon_manager._select_idx_left if hand == "left" else weapon_manager._select_idx_right
	var is_selecting = weapon_manager._selecting_left if hand == "left" else weapon_manager._selecting_right

	if list.is_empty():
		var empty = Label.new()
		empty.text = "(no extra weapons)"
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", _dim_color)
		carry_container.add_child(empty)
		return

	for i in range(list.size()):
		var weapon: WeaponPart = list[i]
		var is_highlighted = is_selecting and (i == highlight_idx)

		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		carry_container.add_child(row)

		var indicator = Label.new()
		indicator.text = ">>" if is_highlighted else "  "
		indicator.add_theme_font_size_override("font_size", 12)
		row.add_child(indicator)

		var icon_label = Label.new()
		icon_label.text = WEAPON_ICONS.get(weapon.weapon_type, "[?]")
		icon_label.add_theme_font_size_override("font_size", 10)
		icon_label.custom_minimum_size = Vector2(55, 0)
		row.add_child(icon_label)

		var name_label = Label.new()
		name_label.text = weapon.weapon_name
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var ammo_label = Label.new()
		var current_ammo = weapon_manager._get_ammo(weapon)
		if weapon.max_ammo >= 999:
			ammo_label.text = "inf"
		else:
			ammo_label.text = "%d/%d" % [current_ammo, weapon.max_ammo]
		ammo_label.add_theme_font_size_override("font_size", 10)
		ammo_label.custom_minimum_size = Vector2(45, 0)
		ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(ammo_label)

		var color: Color = _highlight_color if is_highlighted else _dim_color
		indicator.add_theme_color_override("font_color", color)
		icon_label.add_theme_color_override("font_color", color)
		name_label.add_theme_color_override("font_color", color)
		ammo_label.add_theme_color_override("font_color", color)


func _on_weapon_switched(_hand: String, _weapon_name: String) -> void:
	_update_display()
	if carry_panel.visible:
		_update_carry_display("left" if left_holding else "right")


func _on_ammo_changed(_hand: String, _current: int, _max_ammo: int) -> void:
	_update_display()
	if carry_panel.visible:
		_update_carry_display("left" if left_holding else "right")


func _update_display() -> void:
	if weapon_manager == null:
		return

	if weapon_manager.left_hand:
		var w = weapon_manager.left_hand
		left_name_label.text = w.weapon_name
		left_type_label.text = WEAPON_ICONS.get(w.weapon_type, "[?]")
		var ammo = weapon_manager._get_ammo(w)
		if w.max_ammo >= 999:
			left_ammo_label.text = "inf"
		else:
			var res = GlobalData.get_reserve_ammo(w.get_ammo_type())
			left_ammo_label.text = "%d / %d [Res: %d]" % [ammo, w.max_ammo, res]
	else:
		left_name_label.text = "--- EMPTY ---"
		left_type_label.text = ""
		left_ammo_label.text = ""

	if weapon_manager.right_hand:
		var w = weapon_manager.right_hand
		right_name_label.text = w.weapon_name
		right_type_label.text = WEAPON_ICONS.get(w.weapon_type, "[?]")
		var ammo = weapon_manager._get_ammo(w)
		if w.max_ammo >= 999:
			right_ammo_label.text = "inf"
		else:
			var res = GlobalData.get_reserve_ammo(w.get_ammo_type())
			right_ammo_label.text = "%d / %d [Res: %d]" % [ammo, w.max_ammo, res]
	else:
		right_name_label.text = "--- EMPTY ---"
		right_type_label.text = ""
		right_ammo_label.text = ""


func _on_carry_updated(_carry_list: Array) -> void:
	_update_display()
	if carry_panel.visible:
		_update_carry_display("left" if left_holding else "right")
