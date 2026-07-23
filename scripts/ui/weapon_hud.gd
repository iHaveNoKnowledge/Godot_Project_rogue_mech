extends CanvasLayer

var weapon_manager: Node = null
var root_control: Control
var ammo_panel: PanelContainer
var current_label: Label
var carry_panel: PanelContainer
var carry_container: VBoxContainer
var hand_label: Label

var left_holding: bool = false
var right_holding: bool = false

var _bg_color: Color = Color(0.1, 0.1, 0.1, 0.85)
var _accent_color: Color = Color(0.3, 0.6, 1.0, 1)
var _highlight_color: Color = Color(1.0, 0.9, 0.3, 1)


func _ready() -> void:
	_create_root()
	_create_ammo_ui()
	_create_carry_ui()
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	weapon_manager = mecha.get_node_or_null("WeaponManager") if mecha else null
	if weapon_manager:
		weapon_manager.weapon_switched.connect(_on_weapon_switched)
		weapon_manager.ammo_changed.connect(_on_ammo_changed)
		weapon_manager.carry_updated.connect(_on_carry_updated)
		weapon_manager._emit_initial_state()
	_update_current_display()


func _input(event: InputEvent) -> void:
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


func _create_root() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)


func _create_ammo_ui() -> void:
	ammo_panel = PanelContainer.new()
	ammo_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	ammo_panel.offset_left = 20
	ammo_panel.offset_right = -20
	ammo_panel.offset_bottom = -10
	ammo_panel.offset_top = -60

	var style = StyleBoxFlat.new()
	style.bg_color = _bg_color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	ammo_panel.add_theme_stylebox_override("panel", style)
	root_control.add_child(ammo_panel)

	current_label = Label.new()
	current_label.text = "[L] Empty  |  [R] Empty"
	current_label.add_theme_font_size_override("font_size", 16)
	ammo_panel.add_child(current_label)


func _create_carry_ui() -> void:
	carry_panel = PanelContainer.new()
	carry_panel.offset_left = 0
	carry_panel.offset_right = 200
	carry_panel.offset_top = 200
	carry_panel.offset_bottom = 500

	var style = StyleBoxFlat.new()
	style.bg_color = _bg_color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	carry_panel.add_theme_stylebox_override("panel", style)
	root_control.add_child(carry_panel)
	carry_panel.visible = false

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	carry_panel.add_child(vbox)

	hand_label = Label.new()
	hand_label.text = "LEFT HAND"
	hand_label.add_theme_font_size_override("font_size", 14)
	hand_label.add_theme_color_override("font_color", _accent_color)
	vbox.add_child(hand_label)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	carry_container = VBoxContainer.new()
	carry_container.add_theme_constant_override("separation", 2)
	vbox.add_child(carry_container)


func _show_carry(hand: String) -> void:
	if weapon_manager == null:
		return

	carry_panel.visible = true

	var viewport_width = get_viewport().get_visible_rect().size.x
	if hand == "left":
		carry_panel.offset_left = 20
		carry_panel.offset_right = 220
		carry_panel.offset_top = 100
		carry_panel.offset_bottom = 300
		hand_label.text = "LEFT HAND"
	else:
		carry_panel.offset_left = viewport_width - 220
		carry_panel.offset_right = viewport_width - 20
		carry_panel.offset_top = 100
		carry_panel.offset_bottom = 300
		hand_label.text = "RIGHT HAND"

	_update_carry_display(hand)


func _hide_carry() -> void:
	carry_panel.visible = false


func _update_carry_display(hand: String) -> void:
	if weapon_manager == null:
		return

	for child in carry_container.get_children():
		child.queue_free()

	var current_weapon = weapon_manager.left_hand if hand == "left" else weapon_manager.right_hand

	if current_weapon:
		var current_ammo = weapon_manager._get_ammo(current_weapon)
		var current_max = current_weapon.max_ammo
		var ammo_text = "inf" if current_max >= 999 else "%d/%d" % [current_ammo, current_max]
		var current_row = Label.new()
		current_row.text = "► %s  %s" % [current_weapon.weapon_name, ammo_text]
		current_row.add_theme_font_size_override("font_size", 13)
		current_row.add_theme_color_override("font_color", _highlight_color)
		carry_container.add_child(current_row)

	var carry = weapon_manager.get_carry()
	if carry.is_empty():
		var empty = Label.new()
		empty.text = "  (empty)"
		empty.add_theme_font_size_override("font_size", 12)
		carry_container.add_child(empty)
	else:
		for weapon in carry:
			var ammo_text = "inf" if weapon.max_ammo >= 999 else str(weapon_manager.ammo_pool.get(weapon.weapon_name, 0))
			var max_text = "inf" if weapon.max_ammo >= 999 else str(weapon.max_ammo)

			var row = Label.new()
			row.text = "  %s  %s/%s" % [weapon.weapon_name, ammo_text, max_text]
			row.add_theme_font_size_override("font_size", 12)
			carry_container.add_child(row)


func _on_weapon_switched(hand: String, weapon_name: String) -> void:
	_update_current_display()
	if carry_panel.visible:
		_update_carry_display("left" if left_holding else "right")


func _on_ammo_changed(hand: String, current: int, max_ammo: int) -> void:
	_update_current_display()
	if carry_panel.visible:
		_update_carry_display("left" if left_holding else "right")


func _update_current_display() -> void:
	if weapon_manager == null:
		return

	var left_name = weapon_manager.left_hand.weapon_name if weapon_manager.left_hand else "Empty"
	var right_name = weapon_manager.right_hand.weapon_name if weapon_manager.right_hand else "Empty"
	var left_ammo = weapon_manager._get_ammo(weapon_manager.left_hand) if weapon_manager.left_hand else 0
	var right_ammo = weapon_manager._get_ammo(weapon_manager.right_hand) if weapon_manager.right_hand else 0
	var left_max = weapon_manager.left_hand.max_ammo if weapon_manager.left_hand else 0
	var right_max = weapon_manager.right_hand.max_ammo if weapon_manager.right_hand else 0

	var left_text = "%s (%d/%d)" % [left_name, left_ammo, left_max] if weapon_manager.left_hand else "Empty"
	var right_text = "%s (%d/%d)" % [right_name, right_ammo, right_max] if weapon_manager.right_hand else "Empty"

	current_label.text = "[L] %s  |  [R] %s" % [left_text, right_text]


func _on_carry_updated(carry_list: Array) -> void:
	if carry_panel.visible:
		_update_carry_display("left" if left_holding else "right")
