extends CanvasLayer

## CityShopUI: a trading city board node. Buys healing items (pilot medkits)
## and personal pilot ammo with credits. The pilot heals with these items —
## there is no direct credits-for-HP trade here.

var root_control: Control
var panel: PanelContainer
var title_label: Label
var info_label: Label
var pilot_label: Label
var stock_container: VBoxContainer
var leave_button: Button
var status_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()
	visible = false
	EventBus.tile_entered.connect(_on_tile_entered)


func _create_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = -300
	panel.offset_bottom = 300
	root_control.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.15, 0.05, 0.95)
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
	title_label.text = "CITY TRADING POST"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title_label)

	var separator = HSeparator.new()
	vbox.add_child(separator)

	pilot_label = Label.new()
	pilot_label.text = ""
	pilot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pilot_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(pilot_label)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 240)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	stock_container = VBoxContainer.new()
	stock_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stock_container.add_theme_constant_override("separation", 4)
	scroll.add_child(stock_container)

	leave_button = Button.new()
	leave_button.text = "Leave City"
	leave_button.custom_minimum_size = Vector2(560, 36)
	leave_button.pressed.connect(_on_leave_pressed)
	vbox.add_child(leave_button)

	status_label = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)


func _on_tile_entered(pos: Vector2i, _data: Node) -> void:
	var tile_type := _get_tile_type(pos)
	if tile_type == "city":
		visible = true
		_refresh()
		get_tree().paused = true


func _get_tile_type(pos: Vector2i) -> String:
	var scene = get_tree().current_scene
	if scene and scene.has_method("get_tile_type"):
		return scene.get_tile_type(pos)
	return "empty"


func _refresh() -> void:
	var ammo_bits: Array[String] = []
	for ammo_type in AmmoSystem.PILOT_ORDER:
		ammo_bits.append("%s %d" % [AmmoSystem.display_name(ammo_type), PilotSystem.get_ammo(ammo_type)])
	pilot_label.text = "PILOT STATUS: HP %d / %d%s\nPERSONAL AMMO: %s | Credits: %d" % [
		int(PilotSystem.get_hp()),
		int(PilotSystem.get_max_hp()),
		"  (INJURED — buy medkits to heal)" if PilotSystem.get_hp() < PilotSystem.get_max_hp() else "",
		" | ".join(ammo_bits),
		GlobalData.currency.credits,
	]

	for child in stock_container.get_children():
		child.queue_free()

	# Healing items
	for item in PilotSystem.HEAL_ITEMS:
		var item_id := str(item.get("id", ""))
		var price := PilotSystem.get_item_price(item_id)
		var owned := PilotSystem.get_item_count(item_id)
		var heal_label := "FULL" if int(item.get("heal", 0)) <= 0 else "%d HP" % int(item.get("heal", 0))
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(560, 34)
		btn.text = "%s — heals %s (%d credits)  [owned: %d]" % [
			item.get("name", item_id), heal_label, price, owned
		]
		btn.tooltip_text = str(item.get("desc", ""))
		btn.disabled = GlobalData.currency.credits < price
		btn.pressed.connect(_on_buy_item.bind(item_id))
		stock_container.add_child(btn)

	# Personal ammo
	var ammo_sep = HSeparator.new()
	stock_container.add_child(ammo_sep)
	for ammo_type in AmmoSystem.PILOT_ORDER:
		var price := PilotSystem.get_ammo_price(ammo_type)
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(560, 30)
		btn.text = "+20 %s ammo (%d credits)" % [AmmoSystem.display_name(ammo_type), price * 20]
		btn.disabled = GlobalData.currency.credits < price * 20
		btn.pressed.connect(_on_buy_ammo.bind(ammo_type))
		stock_container.add_child(btn)

	# Fuel Consumables for Convoy & Mecha (Usable anywhere via Inventory)
	var fuel_sep = HSeparator.new()
	stock_container.add_child(fuel_sep)
	var fuel_hdr = Label.new()
	fuel_hdr.text = "CONVOY FUEL CONSUMABLES (stored in stash, use in Inventory)"
	fuel_hdr.add_theme_font_size_override("font_size", 12)
	fuel_hdr.add_theme_color_override("font_color", Color(0.2, 0.9, 1.0))
	stock_container.add_child(fuel_hdr)

	for fc in GlobalData.FUEL_CONSUMABLES:
		var item_id: String = str(fc.get("id", ""))
		var item_name: String = str(fc.get("name", item_id))
		var price: int = int(fc.get("price", 100))
		var owned: int = GlobalData.get_fuel_item_count(item_id)
		var c_fuel: float = float(fc.get("convoy_fuel", 100.0))
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(560, 34)
		btn.text = "⛽ %s (+%.0f Convoy Fuel) — %d credits  [owned: %d]" % [
			item_name, c_fuel, price, owned
		]
		btn.tooltip_text = str(fc.get("desc", ""))
		btn.disabled = GlobalData.currency.credits < price
		btn.pressed.connect(_on_buy_fuel_item.bind(item_id, price))
		stock_container.add_child(btn)

	# Drop Tanks (GDD §2.4)
	var dt_sep = HSeparator.new()
	stock_container.add_child(dt_sep)
	var dt_label = Label.new()
	dt_label.text = "EXTERNAL DROP TANKS (bolt-on fuel canisters)"
	dt_label.add_theme_font_size_override("font_size", 12)
	dt_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.1))
	stock_container.add_child(dt_label)
	var dt_desc = Label.new()
	dt_desc.text = "Adds +40 fuel capacity per tank. Tanks are fragile — enemy fire can detonate them."
	dt_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dt_desc.add_theme_font_size_override("font_size", 10)
	dt_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	stock_container.add_child(dt_desc)
	var current_tanks: int = GlobalData.fuel.drop_tanks_attached
	var max_tanks: int = GlobalData.DROP_TANK_MAX_ATTACHED
	if current_tanks < max_tanks:
		var dt_price := GlobalData.DROP_TANK_COST_CREDITS
		var dt_btn = Button.new()
		dt_btn.custom_minimum_size = Vector2(560, 34)
		dt_btn.text = "Attach Drop Tank (%d credits)  [%d/%d]" % [dt_price, current_tanks, max_tanks]
		dt_btn.tooltip_text = "Bolt an external fuel canister to the backpack. +40 fuel capacity, +30 HP." 
		dt_btn.disabled = GlobalData.currency.credits < dt_price
		dt_btn.pressed.connect(_on_buy_drop_tank)
		stock_container.add_child(dt_btn)
	else:
		var maxed_label = Label.new()
		maxed_label.text = "All %d drop tank slots filled." % max_tanks
		maxed_label.add_theme_font_size_override("font_size", 11)
		maxed_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		stock_container.add_child(maxed_label)
	if current_tanks > 0:
		var detach_btn = Button.new()
		detach_btn.custom_minimum_size = Vector2(560, 30)
		detach_btn.text = "Detach ALL drop tanks (free)" 
		detach_btn.tooltip_text = "Remove all external fuel canisters. Fuel in the tanks is lost."
		detach_btn.pressed.connect(_on_detach_drop_tanks)
		stock_container.add_child(detach_btn)

	status_label.text = "Credits: %d" % GlobalData.currency.credits


func _on_buy_item(item_id: String) -> void:
	if PilotSystem.buy_item(item_id):
		status_label.text = "Bought %s! Credits: %d" % [
			PilotSystem.get_heal_item(item_id).get("name", item_id), GlobalData.currency.credits
		]
	else:
		status_label.text = "Not enough credits!"
	_refresh()


func _on_buy_ammo(ammo_type: String) -> void:
	var bought := PilotSystem.buy_ammo(ammo_type, 20)
	if bought > 0:
		status_label.text = "Bought %d %s ammo! Credits: %d" % [
			bought, ammo_type, GlobalData.currency.credits
		]
	else:
		status_label.text = "Not enough credits!"
	_refresh()


func _on_buy_fuel_item(item_id: String, price: int) -> void:
	if GlobalData.currency.try_spend_credits(price):
		GlobalData.add_fuel_item(item_id, 1)
		var item_entry := GlobalData.get_fuel_item_entry(item_id)
		status_label.text = "Purchased %s! Credits: %d" % [
			item_entry.get("name", item_id), GlobalData.currency.credits
		]
	else:
		status_label.text = "Not enough credits!"
	_refresh()


func _on_buy_drop_tank() -> void:
	if GlobalData.fuel.drop_tanks_attached >= GlobalData.DROP_TANK_MAX_ATTACHED:
		status_label.text = "All drop tank slots filled!"
		return
	if not GlobalData.currency.try_spend_credits(GlobalData.DROP_TANK_COST_CREDITS):
		status_label.text = "Not enough credits!"
		return
	GlobalData.fuel.drop_tanks_attached += 1
	GlobalData.fuel.drop_tank_fuel += GlobalData.DROP_TANK_CAPACITY_PER
	status_label.text = "Drop tank attached! [%d/%d] Credits: %d" % [
		GlobalData.fuel.drop_tanks_attached, GlobalData.DROP_TANK_MAX_ATTACHED, GlobalData.currency.credits
	]
	_refresh()


func _on_detach_drop_tanks() -> void:
	if GlobalData.fuel.drop_tanks_attached <= 0:
		status_label.text = "No drop tanks to detach."
		return
	GlobalData.fuel.drop_tanks_attached = 0
	GlobalData.fuel.drop_tank_fuel = 0.0
	status_label.text = "All drop tanks detached."
	_refresh()


func _on_leave_pressed() -> void:
	visible = false
	get_tree().paused = false
	EventBus.repair_requested.emit()
