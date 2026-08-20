class_name HangarAmmoPanel
extends RefCounted

## Ammo-to-carry loadout panel for the hangar's customize page. Builds the
## per-type +/-, owned-count rows and reads/writes GlobalData.loadout_ammo
## through the same rules as the rest of the game (owned cap, field-pack
## weight limit). Extracted from hangar_controller.gd.

var ammo_loadout_box: VBoxContainer
var ammo_value_labels: Dictionary = {}
# Assigned by the controller once the main status label exists.
var status_label: Label = null


func build(parent_box: VBoxContainer) -> void:
	ammo_loadout_box = VBoxContainer.new()
	ammo_loadout_box.add_theme_constant_override("separation", 3)
	parent_box.add_child(ammo_loadout_box)
	ammo_loadout_box.visible = false

	var title = Label.new()
	title.text = "AMMO TO CARRY (กระสุนที่แบกไป)"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	ammo_loadout_box.add_child(title)

	var ammo_types := ["kinetic", "energy", "explosive", "missile"]
	var ammo_names := {"kinetic": "Kinetic", "energy": "Energy", "explosive": "Explosive", "missile": "Missile"}
	for ammo_type in ammo_types:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		ammo_loadout_box.add_child(row)

		var name_lbl = Label.new()
		name_lbl.text = ammo_names[ammo_type]
		name_lbl.custom_minimum_size = Vector2(80, 0)
		name_lbl.add_theme_font_size_override("font_size", 11)
		row.add_child(name_lbl)

		var minus = Button.new()
		minus.text = "-"
		minus.custom_minimum_size = Vector2(26, 26)
		minus.pressed.connect(func(): adjust(ammo_type, -10))
		row.add_child(minus)

		var value_lbl = Label.new()
		value_lbl.text = "0"
		value_lbl.custom_minimum_size = Vector2(50, 0)
		value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_lbl.add_theme_font_size_override("font_size", 11)
		row.add_child(value_lbl)
		ammo_value_labels[ammo_type] = value_lbl

		var plus = Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(26, 26)
		plus.pressed.connect(func(): adjust(ammo_type, 10))
		row.add_child(plus)

		var stash_lbl = Label.new()
		stash_lbl.text = "owned: %d" % LoadoutSystem.get_reserve_ammo(ammo_type)
		stash_lbl.custom_minimum_size = Vector2(0, 0)
		stash_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stash_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stash_lbl.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
		stash_lbl.add_theme_font_size_override("font_size", 10)
		row.add_child(stash_lbl)


func adjust(ammo_type: String, delta: int) -> void:
	var owned = LoadoutSystem.get_reserve_ammo(ammo_type)
	var current = LoadoutSystem.get_loadout_ammo(ammo_type)
	var target = clampi(current + delta, 0, owned)
	var ammo_weight_per_unit = GlobalData.AMMO_WEIGHT_PER_UNIT.get(ammo_type, 0.01)
	var capacity = LoadoutSystem.get_field_pack_capacity()

	var i = current
	if target < current:
		i = target
	else:
		var base_weight = LoadoutSystem.get_field_pack_ammo_weight() - current * ammo_weight_per_unit
		while i < target:
			if base_weight + (i + 1) * ammo_weight_per_unit > capacity:
				break
			i += 1
	LoadoutSystem.set_loadout_ammo(ammo_type, i)
	refresh()
	if status_label:
		status_label.text = "%s ammo to carry: %d" % [ammo_type.capitalize(), i]
	GlobalData.save_run()


func refresh() -> void:
	if ammo_loadout_box == null:
		return
	for ammo_type in ammo_value_labels:
		var owned = LoadoutSystem.get_reserve_ammo(ammo_type)
		var carried = LoadoutSystem.get_loadout_ammo(ammo_type)
		var value_lbl: Label = ammo_value_labels[ammo_type]
		value_lbl.text = "%d / %d" % [carried, owned]
		var row: HBoxContainer = value_lbl.get_parent()
		var stash_lbl: Label = row.get_child(row.get_child_count() - 1)
		if stash_lbl is Label:
			stash_lbl.text = "owned: %d" % owned
