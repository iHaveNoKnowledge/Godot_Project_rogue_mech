class_name HangarLeftPanel
extends RefCounted
# Owns the hangar's left sidebar (part catalog list & salvaged drops) build:
#   * the part ItemList (selection/click/activate route to HangarPartListPanel)
#   * the CRAFTERY shortcut button (routes to HangarCraftPanel)
#   * the ammo loadout box (HangarAmmoPanel builds itself in here)
#   * the EQUIP SELECTION button (routes to HangarEquipPanel)
#
# All node handles stay owned by the controller; this panel only builds them
# and wires the signals through `controller.`.

var controller  # hangar_controller.gd


# Build the left sidebar into `root` (the full-rect RootControl).
func build(root: Control) -> void:
	# Left Sidebar (Part Catalog List & Salvaged Drops)
	var left_panel = PanelContainer.new()
	left_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_panel.offset_top = 128
	left_panel.offset_bottom = -20
	left_panel.offset_left = 20
	left_panel.custom_minimum_size = Vector2(330, 0)
	controller.left_panel = left_panel
	root.add_child(left_panel)

	var style_left = StyleBoxFlat.new()
	style_left.bg_color = Color(0.08, 0.1, 0.15, 0.88)
	style_left.corner_radius_top_left = 8
	style_left.corner_radius_bottom_left = 8
	style_left.content_margin_left = 12
	style_left.content_margin_right = 12
	style_left.content_margin_top = 12
	style_left.content_margin_bottom = 12
	left_panel.add_theme_stylebox_override("panel", style_left)

	var left_box = VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 10)
	left_panel.add_child(left_box)

	var list_title = Label.new()
	list_title.text = "SCAVENGER INVENTORY & CATALOG"
	list_title.add_theme_font_size_override("font_size", 14)
	list_title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	left_box.add_child(list_title)

	controller.part_item_list = ItemList.new()
	controller.part_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controller.part_item_list.item_selected.connect(func(i: int): if controller.part_list_panel: controller.part_list_panel.on_item_selected(i))
	controller.part_item_list.item_clicked.connect(func(i: int, p: Vector2, b: int): if controller.part_list_panel: controller.part_list_panel.on_item_clicked(i, p, b))
	controller.part_item_list.item_activated.connect(func(i: int): if controller.part_list_panel: controller.part_list_panel.on_item_activated(i))
	left_box.add_child(controller.part_item_list)

	controller.craft_button = Button.new()
	controller.craft_button.text = "🏭 CRAFTERY (craft parts in a separate window)"
	controller.craft_button.custom_minimum_size = Vector2(0, 30)
	controller.craft_button.pressed.connect(func(): if controller.craft_panel: controller.craft_panel.open())
	left_box.add_child(controller.craft_button)

	controller.ammo_panel = HangarAmmoPanel.new()
	controller.ammo_panel.build(left_box)

	controller.equip_button = Button.new()
	controller.equip_button.text = "EQUIP SELECTION"
	controller.equip_button.custom_minimum_size = Vector2(0, 42)
	controller.equip_button.pressed.connect(func(): if controller.equip_panel: controller.equip_panel.on_equip_pressed())
	left_box.add_child(controller.equip_button)
