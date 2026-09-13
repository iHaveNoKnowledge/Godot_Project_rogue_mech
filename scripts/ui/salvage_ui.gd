extends Control

var _salvage_script = preload("res://scripts/systems/salvage_system.gd")
var _salvage_system: Node = null

var weapon_list: ItemList
var tag_button: Button
var salvage_count_label: Label
var current_weapons: Array[WeaponPart] = []


func _get_salvage() -> Node:
	if _salvage_system == null:
		_salvage_system = Node.new()
		_salvage_system.set_script(_salvage_script)
	return _salvage_system


func _ready() -> void:
	_create_ui()
	visible = false


func _create_ui() -> void:
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(500, 400)
	center.add_child(vbox)

	var title = Label.new()
	title.text = "Salvage — Tag weapons to keep"
	vbox.add_child(title)

	weapon_list = ItemList.new()
	weapon_list.custom_minimum_size = Vector2(480, 300)
	weapon_list.item_selected.connect(_on_item_selected)
	vbox.add_child(weapon_list)

	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)

	tag_button = Button.new()
	tag_button.text = "Tag / Untag"
	tag_button.pressed.connect(_on_tag_pressed)
	hbox.add_child(tag_button)

	salvage_count_label = Label.new()
	salvage_count_label.text = "Tagged: 0"
	hbox.add_child(salvage_count_label)

	var confirm_button = Button.new()
	confirm_button.text = "Confirm Salvage"
	confirm_button.pressed.connect(_on_confirm)
	hbox.add_child(confirm_button)


func show_weapons(weapons: Array[WeaponPart]) -> void:
	current_weapons = weapons
	visible = true
	_refresh_list()


func _refresh_list() -> void:
	weapon_list.clear()
	for weapon in current_weapons:
		var tagged = " [TAGGED]" if _get_salvage().is_tagged(weapon) else ""
		var tier := clampi(int(weapon.rarity), 0, 3)
		weapon_list.add_item("%s %s - %s%s" % [PartTierStyle.tier_tag(tier), weapon.weapon_name, weapon.description, tagged])
		PartTierStyle.apply_itemlist_row(weapon_list, weapon_list.item_count - 1, tier)
	salvage_count_label.text = "Tagged: %d" % _get_salvage().get_salvaged_count()


func _on_item_selected(index: int) -> void:
	if index < current_weapons.size():
		var weapon = current_weapons[index]
		tag_button.text = "Untag" if _get_salvage().is_tagged(weapon) else "Tag"


func _on_tag_pressed() -> void:
	var index = weapon_list.get_current_item()
	if index < 0 or index >= current_weapons.size():
		return
	var weapon = current_weapons[index]
	if _get_salvage().is_tagged(weapon):
		_get_salvage().untag_salvage(weapon)
	else:
		_get_salvage().tag_for_salvage(weapon)
	_refresh_list()


func _on_confirm() -> void:
	_get_salvage().salvage_all()
	visible = false
