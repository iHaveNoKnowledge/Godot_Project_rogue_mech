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
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
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
	pilot_label.text = "PILOT STATUS: HP %d / %d%s\nPERSONAL AMMO: Kin %d | En %d | Exp %d | Ms %d | Credits: %d" % [
		int(GlobalData.get_pilot_hp()),
		int(GlobalData.get_pilot_max_hp()),
		"  (INJURED — buy medkits to heal)" if GlobalData.get_pilot_hp() < GlobalData.get_pilot_max_hp() else "",
		GlobalData.get_pilot_ammo("kinetic"),
		GlobalData.get_pilot_ammo("energy"),
		GlobalData.get_pilot_ammo("explosive"),
		GlobalData.get_pilot_ammo("missile"),
		GlobalData.credits,
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
		btn.disabled = GlobalData.credits < price
		btn.pressed.connect(_on_buy_item.bind(item_id))
		stock_container.add_child(btn)

	# Personal ammo
	var ammo_sep = HSeparator.new()
	stock_container.add_child(ammo_sep)
	for ammo_type in ["kinetic", "energy", "explosive", "missile"]:
		var price := PilotSystem.get_ammo_price(ammo_type)
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(560, 30)
		btn.text = "+20 %s ammo (%d credits)" % [ammo_type.capitalize(), price * 20]
		btn.disabled = GlobalData.credits < price * 20
		btn.pressed.connect(_on_buy_ammo.bind(ammo_type))
		stock_container.add_child(btn)

	status_label.text = "Credits: %d" % GlobalData.credits


func _on_buy_item(item_id: String) -> void:
	if PilotSystem.buy_item(item_id):
		status_label.text = "Bought %s! Credits: %d" % [
			PilotSystem.get_heal_item(item_id).get("name", item_id), GlobalData.credits
		]
	else:
		status_label.text = "Not enough credits!"
	_refresh()


func _on_buy_ammo(ammo_type: String) -> void:
	var bought := PilotSystem.buy_ammo(ammo_type, 20)
	if bought > 0:
		status_label.text = "Bought %d %s ammo! Credits: %d" % [
			bought, ammo_type, GlobalData.credits
		]
	else:
		status_label.text = "Not enough credits!"
	_refresh()


func _on_leave_pressed() -> void:
	visible = false
	get_tree().paused = false
	EventBus.repair_requested.emit()
