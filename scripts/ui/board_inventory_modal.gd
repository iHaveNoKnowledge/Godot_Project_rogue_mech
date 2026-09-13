class_name BoardInventoryModal
extends PanelContainer

## -----------------------------------------------------------------------------
## BOARD INVENTORY MODAL — Interactive Cargo & Field Logistics Management
##
## Allows players to:
##   • Manage and consume Energy & Fuel items to directly refuel the Convoy truck
##     or recharge the active Mecha power core.
##   • Administer Medkits and Combat Rations to heal wounded pilots or restore stamina.
##   • Inspect spare armor plates, weapons, and frame parts with durability stats.
##   • Review reserve ammunition stocks.
## -----------------------------------------------------------------------------

signal modal_closed

var current_category: String = "fuel" # "fuel", "medical", "parts", "ammo"
var selected_item_id: String = ""
var selected_item_data: Dictionary = {}

var tab_buttons: Dictionary = {}
var item_list_container: VBoxContainer
var detail_container: VBoxContainer
var currency_label: RichTextLabel
var toast_label: Label
var toast_timer: float = 0.0

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	_build_ui()
	switch_category("fuel")

func _build_ui() -> void:
	# Outer dark transparent backdrop styling
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.04, 0.05, 0.07, 0.94)
	add_theme_stylebox_override("panel", bg_style)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var modal_panel := PanelContainer.new()
	modal_panel.custom_minimum_size = Vector2(960, 620)
	var modal_style := StyleBoxFlat.new()
	modal_style.bg_color = Color(0.08, 0.10, 0.13, 0.98)
	modal_style.border_width_left = 2
	modal_style.border_width_top = 2
	modal_style.border_width_right = 2
	modal_style.border_width_bottom = 2
	modal_style.border_color = Color(0.25, 0.55, 0.85, 0.8)
	modal_style.corner_radius_top_left = 6
	modal_style.corner_radius_top_right = 6
	modal_style.corner_radius_bottom_left = 6
	modal_style.corner_radius_bottom_right = 6
	modal_style.content_margin_left = 18
	modal_style.content_margin_right = 18
	modal_style.content_margin_top = 14
	modal_style.content_margin_bottom = 14
	modal_panel.add_theme_stylebox_override("panel", modal_style)
	center.add_child(modal_panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	modal_panel.add_child(main_vbox)

	# --- 1. HEADER ROW ---
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 12)
	main_vbox.add_child(header_hbox)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_box)

	var title_lbl := Label.new()
	title_lbl.text = "📦 CONVOY CARGO & INVENTORY"
	title_lbl.add_theme_font_size_override("font_size", 17)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title_box.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "Field logistics, fuel canisters, medical supplies, rations, and spare parts."
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
	title_box.add_child(sub_lbl)

	# Currency & Fuel Overview Badge
	var cur_panel := PanelContainer.new()
	var cur_style := StyleBoxFlat.new()
	cur_style.bg_color = Color(0.12, 0.14, 0.18, 0.95)
	cur_style.border_width_left = 1
	cur_style.border_width_top = 1
	cur_style.border_width_right = 1
	cur_style.border_width_bottom = 1
	cur_style.border_color = Color(0.35, 0.45, 0.55, 0.8)
	cur_style.corner_radius_top_left = 3
	cur_style.corner_radius_top_right = 3
	cur_style.corner_radius_bottom_left = 3
	cur_style.corner_radius_bottom_right = 3
	cur_style.content_margin_left = 12
	cur_style.content_margin_right = 12
	cur_style.content_margin_top = 4
	cur_style.content_margin_bottom = 4
	cur_panel.add_theme_stylebox_override("panel", cur_style)
	header_hbox.add_child(cur_panel)

	currency_label = RichTextLabel.new()
	currency_label.bbcode_enabled = true
	currency_label.fit_content = true
	currency_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	currency_label.custom_minimum_size = Vector2(300, 24)
	cur_panel.add_child(currency_label)

	var close_btn := Button.new()
	close_btn.text = "✕ CLOSE (ESC)"
	close_btn.custom_minimum_size = Vector2(120, 32)
	close_btn.pressed.connect(close)
	header_hbox.add_child(close_btn)

	# --- 2. CATEGORY TABS ---
	var tabs_hbox := HBoxContainer.new()
	tabs_hbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(tabs_hbox)

	var categories = [
		{"id": "fuel", "label": "⚡ ENERGY & FUEL", "col": Color(0.2, 0.85, 1.0)},
		{"id": "medical", "label": "💊 MEDICAL & RATIONS", "col": Color(0.3, 0.95, 0.6)},
		{"id": "parts", "label": "🛡️ SPARE PARTS & ARMS", "col": Color(1.0, 0.8, 0.3)},
		{"id": "ammo", "label": "📦 AMMO RESERVES", "col": Color(0.9, 0.5, 1.0)}
	]

	for cat in categories:
		var btn := Button.new()
		btn.text = cat["label"]
		btn.custom_minimum_size = Vector2(180, 34)
		btn.focus_mode = Control.FOCUS_NONE
		var cid: String = cat["id"]
		btn.pressed.connect(func(): switch_category(cid))
		tabs_hbox.add_child(btn)
		tab_buttons[cid] = btn

	var sep := HSeparator.new()
	main_vbox.add_child(sep)

	# --- 3. MAIN CONTENT (Split View: Left List, Right Detail) ---
	var split_hbox := HBoxContainer.new()
	split_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_hbox.add_theme_constant_override("separation", 14)
	main_vbox.add_child(split_hbox)

	# Left Column: Item List (Scrollable)
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(440, 0)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left_style := StyleBoxFlat.new()
	left_style.bg_color = Color(0.06, 0.07, 0.09, 0.95)
	left_style.border_width_left = 1
	left_style.border_width_top = 1
	left_style.border_width_right = 1
	left_style.border_width_bottom = 1
	left_style.border_color = Color(0.25, 0.32, 0.4, 0.6)
	left_style.content_margin_left = 8
	left_style.content_margin_right = 8
	left_style.content_margin_top = 8
	left_style.content_margin_bottom = 8
	left_panel.add_theme_stylebox_override("panel", left_style)
	split_hbox.add_child(left_panel)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(scroll)

	item_list_container = VBoxContainer.new()
	item_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list_container.add_theme_constant_override("separation", 6)
	scroll.add_child(item_list_container)

	# Right Column: Detail & Action Panel
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var right_style := StyleBoxFlat.new()
	right_style.bg_color = Color(0.07, 0.08, 0.11, 0.95)
	right_style.border_width_left = 1
	right_style.border_width_top = 1
	right_style.border_width_right = 1
	right_style.border_width_bottom = 1
	right_style.border_color = Color(0.25, 0.45, 0.7, 0.6)
	right_style.content_margin_left = 14
	right_style.content_margin_right = 14
	right_style.content_margin_top = 14
	right_style.content_margin_bottom = 14
	right_panel.add_theme_stylebox_override("panel", right_style)
	split_hbox.add_child(right_panel)

	detail_container = VBoxContainer.new()
	detail_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_container.add_theme_constant_override("separation", 10)
	right_panel.add_child(detail_container)

	# Toast Alert Label
	toast_label = Label.new()
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 12)
	toast_label.add_theme_color_override("font_color", Color(0.3, 0.95, 0.6))
	main_vbox.add_child(toast_label)

	_refresh_currency_badge()

func _process(delta: float) -> void:
	if toast_timer > 0.0:
		toast_timer -= delta
		if toast_timer <= 0.0 and toast_label:
			toast_label.text = ""

func show_toast(msg: String, is_warning: bool = false, duration: float = 3.0) -> void:
	if toast_label:
		toast_label.text = ("⚠️ " if is_warning else "✅ ") + msg
		toast_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35) if is_warning else Color(0.35, 0.95, 0.6))
		toast_timer = duration

func _refresh_currency_badge() -> void:
	if currency_label:
		var c_fuel := GlobalData.fuel.convoy_fuel if GlobalData.fuel else 0.0
		var c_max := GlobalData.fuel.convoy_max_fuel if GlobalData.fuel else 500.0
		currency_label.text = "[color=#ffd700]💰 %d CR[/color]  |  [color=#00e5ff]🔩 %d SC[/color]  |  [color=#ffaa33]🚚 FUEL: %.0f/%.0f[/color]" % [
			GlobalData.currency.credits, GlobalData.currency.scrap, c_fuel, c_max
		]

func switch_category(cat: String) -> void:
	current_category = cat
	for cid in tab_buttons:
		var btn: Button = tab_buttons[cid]
		if cid == cat:
			btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
			var st := StyleBoxFlat.new()
			st.bg_color = Color(0.18, 0.28, 0.42, 0.95)
			st.border_width_bottom = 3
			st.border_color = Color(0.3, 0.85, 1.0)
			btn.add_theme_stylebox_override("normal", st)
		else:
			btn.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
			var st := StyleBoxFlat.new()
			st.bg_color = Color(0.10, 0.12, 0.15, 0.9)
			btn.add_theme_stylebox_override("normal", st)

	_populate_category_items()

func _populate_category_items() -> void:
	if item_list_container == null: return
	for ch in item_list_container.get_children():
		item_list_container.remove_child(ch)
		ch.queue_free()

	selected_item_id = ""
	selected_item_data = {}

	match current_category:
		"fuel":
			_populate_fuel_items()
		"medical":
			_populate_medical_items()
		"parts":
			_populate_parts_items()
		"ammo":
			_populate_ammo_items()

func _populate_fuel_items() -> void:
	var entries := GlobalData.FUEL_CONSUMABLES
	var has_items := false
	for entry in entries:
		var item_id: String = str(entry.get("id", ""))
		var count: int = GlobalData.get_fuel_item_count(item_id)
		var btn := _create_item_row(entry.get("name", "Fuel Item"), count, "⚡ FUEL", Color(0.2, 0.85, 1.0), count > 0)
		btn.pressed.connect(func(): _select_fuel_item(entry, count))
		item_list_container.add_child(btn)
		if count > 0:
			has_items = true
			if selected_item_id == "":
				_select_fuel_item(entry, count)

	if not has_items and selected_item_id == "":
		_render_empty_detail("No fuel canisters or energy cells in cargo. Purchase fuel at cities or seize enemy depots.")

func _populate_medical_items() -> void:
	var entries: Array = PilotSystem.HEAL_ITEMS
	var has_items := false
	for entry in entries:
		var item_id: String = str(entry.get("id", ""))
		var count: int = PilotSystem.get_item_count(item_id)
		var is_food: bool = int(entry.get("stamina", 0)) > 0
		var tag := "🍱 RATION" if is_food else "💊 MEDKIT"
		var tag_col := Color(0.4, 0.9, 0.4) if is_food else Color(0.3, 0.85, 1.0)
		var btn := _create_item_row(entry.get("name", "Medical Item"), count, tag, tag_col, count > 0)
		btn.pressed.connect(func(): _select_medical_item(entry, count))
		item_list_container.add_child(btn)
		if count > 0:
			has_items = true
			if selected_item_id == "":
				_select_medical_item(entry, count)

	if not has_items and selected_item_id == "":
		_render_empty_detail("No medkits or rations in cargo. Purchase supplies at Trading Cities or safehouses.")

func _populate_parts_items() -> void:
	var weapons: Array = GlobalData.weapons.weapon_inventory
	var armors: Array = GlobalData.weapons.armor_inventory

	if weapons.is_empty() and armors.is_empty():
		_render_empty_detail("No spare weapons or armor plates in storage. Salvage parts from combat or craft them in the Hangar.")
		return

	for w in weapons:
		if w is Dictionary:
			var wname = str(w.get("name", "Weapon"))
			var dur = GlobalData.get_durability_ratio(w) * 100.0
			var btn := _create_item_row(wname, 1, "🔫 WEAPON", Color(1.0, 0.7, 0.3), true, "Dur: %.0f%%" % dur)
			btn.pressed.connect(func(): _select_weapon_part(w))
			item_list_container.add_child(btn)
			if selected_item_id == "":
				_select_weapon_part(w)

	for a in armors:
		if a is Dictionary:
			var aname = str(a.get("name", "Armor Plate"))
			var dur = GlobalData.get_durability_ratio(a) * 100.0
			var slot = str(a.get("slot", "body")).to_upper()
			var btn := _create_item_row(aname, 1, "🛡️ " + slot, Color(0.3, 0.85, 1.0), true, "Dur: %.0f%%" % dur)
			btn.pressed.connect(func(): _select_armor_part(a))
			item_list_container.add_child(btn)
			if selected_item_id == "":
				_select_armor_part(a)

func _populate_ammo_items() -> void:
	for ammo_id in AmmoSystem.ORDER:
		var a := {"id": ammo_id, "name": AmmoSystem.display_name(ammo_id), "desc": str(AmmoSystem.DESCS.get(ammo_id, ""))}
		var count := LoadoutSystem.get_reserve_ammo(a["id"])
		var btn := _create_item_row(a["name"], count, "📦 AMMO", Color(0.85, 0.45, 1.0), count > 0)
		btn.pressed.connect(func(): _select_ammo_item(a, count))
		item_list_container.add_child(btn)
		if selected_item_id == "":
			_select_ammo_item(a, count)

func _create_item_row(item_name: String, count: int, tag: String, tag_color: Color, is_available: bool, sub_text: String = "") -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 42)
	btn.focus_mode = Control.FOCUS_NONE

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 10)
	btn.add_child(hbox)

	var margin := Control.new()
	margin.custom_minimum_size = Vector2(4, 0)
	hbox.add_child(margin)

	var tag_lbl := Label.new()
	tag_lbl.text = "[ %s ]" % tag
	tag_lbl.add_theme_font_size_override("font_size", 10)
	tag_lbl.add_theme_color_override("font_color", tag_color if is_available else Color(0.5, 0.5, 0.5))
	hbox.add_child(tag_lbl)

	var name_lbl := Label.new()
	name_lbl.text = item_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95) if is_available else Color(0.5, 0.5, 0.5))
	hbox.add_child(name_lbl)

	if sub_text != "":
		var sub := Label.new()
		sub.text = sub_text
		sub.add_theme_font_size_override("font_size", 11)
		sub.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
		hbox.add_child(sub)

	var count_lbl := Label.new()
	count_lbl.text = "x%d" % count
	count_lbl.add_theme_font_size_override("font_size", 12)
	count_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if count > 0 else Color(0.4, 0.4, 0.4))
	hbox.add_child(count_lbl)

	var rmargin := Control.new()
	rmargin.custom_minimum_size = Vector2(6, 0)
	hbox.add_child(rmargin)

	return btn

func _clear_detail() -> void:
	if detail_container == null: return
	for ch in detail_container.get_children():
		ch.queue_free()

func _render_empty_detail(msg: String) -> void:
	_clear_detail()
	var lbl := Label.new()
	lbl.text = msg
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	detail_container.add_child(lbl)

# --- Detail View Handlers ---

func _select_fuel_item(entry: Dictionary, count: int) -> void:
	selected_item_id = str(entry.get("id", ""))
	selected_item_data = entry
	_clear_detail()

	var title := Label.new()
	title.text = "⚡ %s (Stock: x%d)" % [entry.get("name", "Fuel Item"), count]
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.25, 0.9, 1.0))
	detail_container.add_child(title)

	var desc := Label.new()
	desc.text = str(entry.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	detail_container.add_child(desc)

	var sep := HSeparator.new()
	detail_container.add_child(sep)

	# Status Section: Convoy Fuel & Mecha Energy
	var status_hdr := Label.new()
	status_hdr.text = "CURRENT ENERGY & FUEL LEVELS:"
	status_hdr.add_theme_font_size_override("font_size", 12)
	status_hdr.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	detail_container.add_child(status_hdr)

	var c_fuel := GlobalData.fuel.convoy_fuel if GlobalData.fuel else 0.0
	var c_max := GlobalData.fuel.convoy_max_fuel if GlobalData.fuel else 500.0
	var m_energy := GlobalData.fuel.mech_energy if GlobalData.fuel else 0.0
	var m_max := GlobalData.fuel.mech_max_energy if GlobalData.fuel else 1000.0

	var convoy_bar_row := HPPartBar.create_row("Convoy Fuel", c_fuel, c_max, false, false, 280, 10, 11)
	detail_container.add_child(convoy_bar_row)

	var mech_bar_row := HPPartBar.create_row("Mech Energy", m_energy, m_max, true, false, 280, 10, 11)
	detail_container.add_child(mech_bar_row)

	var sep2 := HSeparator.new()
	detail_container.add_child(sep2)

	# Action Buttons
	var c_gain := float(entry.get("convoy_fuel", 150.0))
	var m_gain := float(entry.get("mech_energy", 300.0))

	var btn_box := HBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 10)
	detail_container.add_child(btn_box)

	var refuel_convoy_btn := Button.new()
	refuel_convoy_btn.text = "🚚 Refuel Convoy (+%.0f Fuel)" % c_gain
	refuel_convoy_btn.custom_minimum_size = Vector2(210, 38)
	refuel_convoy_btn.disabled = (count <= 0)
	refuel_convoy_btn.pressed.connect(func(): _use_fuel_on_target(entry, "convoy"))
	btn_box.add_child(refuel_convoy_btn)

	var recharge_mech_btn := Button.new()
	recharge_mech_btn.text = "🤖 Recharge Mech (+%.0f Energy)" % m_gain
	recharge_mech_btn.custom_minimum_size = Vector2(210, 38)
	recharge_mech_btn.disabled = (count <= 0)
	recharge_mech_btn.pressed.connect(func(): _use_fuel_on_target(entry, "mecha"))
	btn_box.add_child(recharge_mech_btn)

func _use_fuel_on_target(entry: Dictionary, target: String) -> void:
	var item_id: String = str(entry.get("id", ""))
	var item_name: String = str(entry.get("name", "Fuel"))
	var gained := GlobalData.use_fuel_item(item_id, target)
	if gained > 0.0:
		if target == "convoy":
			show_toast("Refueled Convoy Truck (+%.0f Fuel) using %s!" % [gained, item_name], false)
		else:
			show_toast("Charged Mecha Energy (+%.0f Energy) using %s!" % [gained, item_name], false)
		GlobalData.save_run()
		_refresh_currency_badge()
		_populate_category_items()
	else:
		if target == "convoy":
			show_toast("Convoy Fuel tank is already full (%.0f/%.0f)!" % [GlobalData.fuel.convoy_fuel, GlobalData.fuel.convoy_max_fuel], true)
		else:
			show_toast("Mecha Energy core is already fully charged (%.0f/%.0f)!" % [GlobalData.fuel.mech_energy, GlobalData.fuel.mech_max_energy], true)

func _select_medical_item(entry: Dictionary, count: int) -> void:
	selected_item_id = str(entry.get("id", ""))
	selected_item_data = entry
	_clear_detail()

	var is_food: bool = int(entry.get("stamina", 0)) > 0
	var title := Label.new()
	title.text = "%s %s (Stock: x%d)" % ["🍱" if is_food else "💊", entry.get("name", "Medical Item"), count]
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.3, 0.95, 0.6))
	detail_container.add_child(title)

	var desc := Label.new()
	desc.text = str(entry.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	detail_container.add_child(desc)

	var sep := HSeparator.new()
	detail_container.add_child(sep)

	# Pilot Status List
	var pilot_hdr := Label.new()
	pilot_hdr.text = "SELECT PILOT TO ADMINISTER:"
	pilot_hdr.add_theme_font_size_override("font_size", 12)
	pilot_hdr.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	detail_container.add_child(pilot_hdr)

	var p_hp := PilotSystem.get_hp()
	var p_max_hp := PilotSystem.get_max_hp()
	var p_stamina := GlobalData.fuel.pilot_stamina if GlobalData.fuel else 50.0
	var p_max_stamina := GlobalData.fuel.pilot_max_stamina if GlobalData.fuel else 50.0

	var hp_row := HPPartBar.create_row("Pilot HP", p_hp, p_max_hp, false, false, 280, 10, 11)
	detail_container.add_child(hp_row)

	var stam_row := HPPartBar.create_row("Stamina", p_stamina, p_max_stamina, true, false, 280, 10, 11)
	detail_container.add_child(stam_row)

	var sep2 := HSeparator.new()
	detail_container.add_child(sep2)

	var heal_val := int(entry.get("heal", 0))
	var stam_val := int(entry.get("stamina", 0))

	var use_btn := Button.new()
	if is_food:
		use_btn.text = "🍱 Consume Ration (+%d Stamina, +%d HP)" % [stam_val, heal_val]
	elif heal_val == 0:
		use_btn.text = "💉 Use Surgical Kit (Restore 100% HP)"
	else:
		use_btn.text = "💉 Use Medkit (+%d HP)" % heal_val
	use_btn.custom_minimum_size = Vector2(280, 38)
	use_btn.disabled = (count <= 0)
	use_btn.pressed.connect(func(): _use_medical_on_player(entry))
	detail_container.add_child(use_btn)

func _use_medical_on_player(entry: Dictionary) -> void:
	var item_id: String = str(entry.get("id", ""))
	var item_name: String = str(entry.get("name", "Medical Item"))
	var is_food: bool = int(entry.get("stamina", 0)) > 0
	var heal_val: float = float(entry.get("heal", 0.0))
	var stam_val: float = float(entry.get("stamina", 0.0))

	var cur_hp := PilotSystem.get_hp()
	var max_hp := PilotSystem.get_max_hp()
	var cur_stam := GlobalData.fuel.pilot_stamina if GlobalData.fuel else 50.0
	var max_stam := GlobalData.fuel.pilot_max_stamina if GlobalData.fuel else 50.0

	var healed: float = 0.0
	var stam_gained: float = 0.0

	if is_food:
		if cur_hp >= max_hp and cur_stam >= max_stam:
			show_toast("Pilot is already at full HP and Stamina!", true)
			return
		if stam_val > 0.0 and GlobalData.fuel:
			var needed_stam = max_stam - cur_stam
			stam_gained = minf(stam_val, needed_stam)
			GlobalData.fuel.pilot_stamina = clampf(cur_stam + stam_val, 0.0, max_stam)
		if heal_val > 0.0 and cur_hp < max_hp:
			healed = PilotSystem.heal(heal_val)

		GlobalData.pilot.pilot_items[item_id] = PilotSystem.get_item_count(item_id) - 1
		if GlobalData.pilot.pilot_items[item_id] <= 0:
			GlobalData.pilot.pilot_items.erase(item_id)

		show_toast("Consumed %s! Restored +%.0f Stamina, +%.0f HP." % [item_name, stam_gained, healed], false)
	else:
		if not PilotSystem.is_injured():
			show_toast("Pilot is already at full health (%.0f/%.0f HP)!" % [cur_hp, max_hp], true)
			return
		healed = PilotSystem.use_heal_item(item_id)
		if healed > 0.0:
			show_toast("Applied %s! Healed +%.0f HP." % [item_name, healed], false)

	GlobalData.save_run()
	_populate_category_items()

func _select_weapon_part(w: Dictionary) -> void:
	_clear_detail()
	var title := Label.new()
	title.text = "🔫 %s" % str(w.get("name", "Weapon"))
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	detail_container.add_child(title)

	var dur := GlobalData.get_durability_ratio(w) * 100.0
	var dur_row := HPPartBar.create_row("Durability", dur, 100.0, false, false, 280, 10, 11, true)
	detail_container.add_child(dur_row)

	var info_lbl := Label.new()
	info_lbl.text = "SPARE WEAPON IN STORAGE\nTo equip this weapon to your active loadout, visit the 3D Hangar from the main menu."
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_lbl.add_theme_font_size_override("font_size", 12)
	info_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	detail_container.add_child(info_lbl)

func _select_armor_part(a: Dictionary) -> void:
	_clear_detail()
	var title := Label.new()
	title.text = "🛡️ %s" % str(a.get("name", "Armor Plate"))
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	detail_container.add_child(title)

	var dur := GlobalData.get_durability_ratio(a) * 100.0
	var dur_row := HPPartBar.create_row("Durability", dur, 100.0, false, false, 280, 10, 11, true)
	detail_container.add_child(dur_row)

	var info_lbl := Label.new()
	info_lbl.text = "SLOT: %s\nMAX HP: %.0f | WEIGHT: %.1f kg\n\nTo mount or replace this armor plate on your mecha, open the 3D Hangar." % [
		str(a.get("slot", "body")).to_upper(),
		float(a.get("hp", 30.0)),
		float(a.get("weight", 10.0))
	]
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_lbl.add_theme_font_size_override("font_size", 12)
	info_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	detail_container.add_child(info_lbl)

func _select_ammo_item(a: Dictionary, count: int) -> void:
	_clear_detail()
	var title := Label.new()
	title.text = "📦 %s (Reserve: %d)" % [a["name"], count]
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.85, 0.5, 1.0))
	detail_container.add_child(title)

	var desc := Label.new()
	desc.text = "%s\n\nAmmo reserves automatically reload equipped weapons during missions." % a["desc"]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	detail_container.add_child(desc)

func close() -> void:
	modal_closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		close()
