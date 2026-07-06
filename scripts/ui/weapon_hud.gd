extends Control

var weapon_name_label: Label
var ammo_label: Label
var weapon_list: HBoxContainer
var current_weapons: Array = []


func _ready() -> void:
	_create_ui()
	EventBus.game_state_changed.connect(_on_game_state_changed)


func _create_ui() -> void:
	var bottom = HBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 20
	bottom.offset_right = -20
	bottom.offset_bottom = -20
	bottom.offset_top = -80
	add_child(bottom)

	# Weapon info
	var info_vbox = VBoxContainer.new()
	bottom.add_child(info_vbox)

	weapon_name_label = Label.new()
	weapon_name_label.text = "---"
	info_vbox.add_child(weapon_name_label)

	ammo_label = Label.new()
	ammo_label.text = "Ammo: 0 / 0"
	info_vbox.add_child(ammo_label)

	# Weapon slots
	weapon_list = HBoxContainer.new()
	weapon_list.offset_left = 400
	bottom.add_child(weapon_list)


func update_weapon_display(weapon_name: String, current_ammo: int, max_ammo: int) -> void:
	if weapon_name_label:
		weapon_name_label.text = weapon_name
	if ammo_label:
		ammo_label.text = "Ammo: %d / %d" % [current_ammo, max_ammo]


func update_weapon_slots(weapons: Array, active_index: int) -> void:
	if weapon_list == null:
		return
	for child in weapon_list.get_children():
		child.queue_free()
	for i in weapons.size():
		var slot = PanelContainer.new()
		slot.custom_minimum_size = Vector2(80, 40)
		if i == active_index:
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.3, 0.6, 1.0)
			slot.add_theme_stylebox_override("panel", style)
		weapon_list.add_child(slot)
		var label = Label.new()
		label.text = weapons[i].weapon_name
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(label)


func _on_game_state_changed(_old: String, new_state: String) -> void:
	visible = new_state == "COMBAT"
