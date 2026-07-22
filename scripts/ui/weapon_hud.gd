extends CanvasLayer

var weapon_manager: Node = null
var panel: PanelContainer = null
var current_label: Label = null
var carry_container: VBoxContainer = null
var carry_labels: Array = []

var left_holding: bool = false
var right_holding: bool = false
var selected_hand: String = ""

var _bg_color: Color = Color(0.1, 0.1, 0.1, 0.85)
var _accent_color: Color = Color(0.3, 0.6, 1.0, 1)


func _ready() -> void:
	_create_ui()
	await get_tree().process_frame
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	weapon_manager = mecha.get_node_or_null("WeaponManager") if mecha else null
	if weapon_manager:
		weapon_manager.weapon_switched.connect(_on_weapon_switched)
		weapon_manager.ammo_changed.connect(_on_ammo_changed)
		weapon_manager.carry_updated.connect(_on_carry_updated)
		weapon_manager._emit_initial_state()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("weapon_left"):
		left_holding = true
		selected_hand = "left"
		_show_carry_list()
	elif event.is_action_released("weapon_left"):
		left_holding = false
		if not right_holding:
			selected_hand = ""
			_hide_carry_list()

	if event.is_action_pressed("weapon_right"):
		right_holding = true
		selected_hand = "right"
		_show_carry_list()
	elif event.is_action_released("weapon_right"):
		right_holding = false
		if not left_holding:
			selected_hand = ""
			_hide_carry_list()


func _create_ui() -> void:
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 20
	panel.offset_right = -20
	panel.offset_bottom = -10
	panel.offset_top = -200

	var style = StyleBoxFlat.new()
	style.bg_color = _bg_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	current_label = Label.new()
	current_label.text = "[L] Empty  |  [R] Empty"
	current_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(current_label)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	carry_container = VBoxContainer.new()
	carry_container.add_theme_constant_override("separation", 2)
	carry_container.visible = false
	vbox.add_child(carry_container)

	panel.visible = false


func _show_carry_list() -> void:
	if weapon_manager == null:
		return

	panel.visible = true
	carry_container.visible = true
	_update_carry_display()


func _hide_carry_list() -> void:
	carry_container.visible = false
	panel.visible = false


func _update_carry_display() -> void:
	if weapon_manager == null:
		return

	for child in carry_container.get_children():
		child.queue_free()
	carry_labels.clear()

	var hand_name = selected_hand
	var current_weapon = null
	if hand_name == "left":
		current_weapon = weapon_manager.left_hand
	else:
		current_weapon = weapon_manager.right_hand

	if current_weapon:
		var header = Label.new()
		header.text = "Current: %s" % current_weapon.weapon_name
		header.add_theme_font_size_override("font_size", 14)
		header.add_theme_color_override("font_color", _accent_color)
		carry_container.add_child(header)

	var sep = HSeparator.new()
	carry_container.add_child(sep)

	var carry = weapon_manager.get_carry()
	if carry.is_empty():
		var empty = Label.new()
		empty.text = "Carry: Empty"
		empty.add_theme_font_size_override("font_size", 12)
		carry_container.add_child(empty)
	else:
		for i in range(carry.size()):
			var weapon = carry[i]
			var ammo_text = "inf" if weapon.max_ammo >= 999 else str(weapon_manager.ammo_pool.get(weapon.weapon_name, 0))
			var max_text = "inf" if weapon.max_ammo >= 999 else str(weapon.max_ammo)

			var row = Label.new()
			row.text = "%s    %s/%s" % [weapon.weapon_name, ammo_text, max_text]
			row.add_theme_font_size_override("font_size", 12)
			carry_container.add_child(row)
			carry_labels.append(row)


func _on_weapon_switched(hand: String, weapon_name: String) -> void:
	_update_current_display()


func _on_ammo_changed(hand: String, current: int, max_ammo: int) -> void:
	_update_current_display()


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
	if selected_hand != "":
		_update_carry_display()
