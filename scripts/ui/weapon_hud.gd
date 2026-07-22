extends Control

var left_label: Label
var right_label: Label
var carry_label: Label
var ammo_left_label: Label
var ammo_right_label: Label
var drop_hint_label: Label


func _ready() -> void:
	_create_ui()
	EventBus.game_state_changed.connect(_on_game_state_changed)
	await get_tree().process_frame
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	var wm = mecha.get_node_or_null("WeaponManager") if mecha else null
	if wm:
		wm.weapon_switched.connect(_on_weapon_switched)
		wm.ammo_changed.connect(_on_ammo_changed)
		wm.carry_updated.connect(_on_carry_updated)
		wm.weapon_dropped.connect(_on_weapon_dropped)


func _create_ui() -> void:
	var bottom = VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 20
	bottom.offset_right = -20
	bottom.offset_bottom = -10
	bottom.offset_top = -120
	add_child(bottom)

	# Hands row
	var hands_row = HBoxContainer.new()
	bottom.add_child(hands_row)

	# Left hand
	var left_vbox = VBoxContainer.new()
	hands_row.add_child(left_vbox)
	var left_title = Label.new()
	left_title.text = "[L] - Press 1"
	left_vbox.add_child(left_title)
	left_label = Label.new()
	left_label.text = "Empty"
	left_vbox.add_child(left_label)
	ammo_left_label = Label.new()
	ammo_left_label.text = ""
	left_vbox.add_child(ammo_left_label)

	# Right hand
	var right_vbox = VBoxContainer.new()
	hands_row.add_child(right_vbox)
	var right_title = Label.new()
	right_title.text = "[R] - Press 3"
	right_vbox.add_child(right_title)
	right_label = Label.new()
	right_label.text = "Empty"
	right_vbox.add_child(right_label)
	ammo_right_label = Label.new()
	ammo_right_label.text = ""
	right_vbox.add_child(ammo_right_label)

	# Carry row
	var carry_row = HBoxContainer.new()
	bottom.add_child(carry_row)
	var carry_title = Label.new()
	carry_title.text = "[Carry] "
	carry_row.add_child(carry_title)
	carry_label = Label.new()
	carry_label.text = "Empty"
	carry_row.add_child(carry_label)

	# Drop hint
	drop_hint_label = Label.new()
	drop_hint_label.text = "Hold 1/3 + 2 = Drop from hand | Hold 1/3 + Scroll + 2 = Drop from carry"
	bottom.add_child(drop_hint_label)


func _on_weapon_switched(hand: String, weapon_name: String) -> void:
	match hand:
		"left":
			if left_label:
				left_label.text = weapon_name
		"right":
			if right_label:
				right_label.text = weapon_name


func _on_ammo_changed(hand: String, current: int, max_ammo: int) -> void:
	match hand:
		"left":
			if ammo_left_label:
				ammo_left_label.text = "%d / %d" % [current, max_ammo]
		"right":
			if ammo_right_label:
				ammo_right_label.text = "%d / %d" % [current, max_ammo]


func _on_carry_updated(carry_list: Array) -> void:
	if carry_label == null:
		return
	if carry_list.is_empty():
		carry_label.text = "Empty"
		return
	var names: PackedStringArray = []
	for w in carry_list:
		names.append(w.weapon_name)
	carry_label.text = ", ".join(names)


func _on_weapon_dropped(hand: String, _weapon: WeaponPart) -> void:
	match hand:
		"left":
			if left_label:
				left_label.text = "Empty"
			if ammo_left_label:
				ammo_left_label.text = ""
		"right":
			if right_label:
				right_label.text = "Empty"
			if ammo_right_label:
				ammo_right_label.text = ""


func _on_game_state_changed(_old: String, new_state: String) -> void:
	visible = true
