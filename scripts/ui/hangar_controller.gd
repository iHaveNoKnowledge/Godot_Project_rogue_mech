extends Node3D

## 3D Hangar Garage Controller (Gundam Barbatos / Vidar Style)
## - Core Power comes from the Inner Frame (Alaya-Vijnana Skeleton) which can be upgraded with Reactor Levels.
## - Outer Armor Plating allows visual freedom & scavenged enemy armor patching (Zaku Green, Tank Grey, Crimson Ace).
## - Live 3D Viewport Turntable renders mix-and-matched scavenger armor colors over the dark Gundam Inner Frame!

var root_control: Control
var _bg_color: Color = Color(0.08, 0.08, 0.12, 0.85)
var _accent_color: Color = Color(0.3, 0.6, 1.0, 1.0)
var _highlight_color: Color = Color(1.0, 0.9, 0.3, 1.0)
var _dim_color: Color = Color(0.5, 0.5, 0.5, 1.0)
var current_mode: String = "armor" # "armor", "frame", "attachment", "chassis", "upgrade"
var selected_slot: String = "head"
var selected_part_path: String = ""
var selected_part_id: String = ""
var selected_salvage_info: Dictionary = {}
var visible_salvage_indices: Array[int] = []
var selected_frame_info: Dictionary = {}
var selected_attachment_info: Dictionary = {}
var selected_chassis_key: String = "standard"
var visible_weapon_indices: Array[int] = []
var action_panel: HangarActionPanel = null
var equip_panel: HangarEquipPanel = null
var part_list_panel: HangarPartListPanel = null
var stats_panel: HangarStatsPanel = null
var nav_panel: HangarNavPanel = null
var repair_panel: HangarRepairPanel = null
var slot_panel: HangarSlotPanel = null
# Slot tab buttons keyed by slot id, reused for UI-only selection highlight.
var slot_tab_buttons: Dictionary = {}

# Top-level hangar sub-menu (landing screen): [CUSTOMIZE | EMERGENCY REPAIR |
# UPGRADE | CRAFT | CATALOG]. It is the FIRST thing shown after entering the
# hangar as a long vertical list on the left; each choice opens its own page.
var scrap_editor: CanvasLayer = null
# Landing sub-menu rail + the page widgets it toggles.
var submenu_rail: PanelContainer = null
var back_to_menu_button: Button = null
var left_panel: PanelContainer = null
var right_panel: PanelContainer = null

# Attachment Catalog — lives in GlobalData (loaded from resources/data/mech_catalogs.tres).
var attachment_catalog: Array:
	get:
		return GlobalData.attachment_catalog

# UI Nodes
var tab_container: HBoxContainer
var sub_toggle_container: HBoxContainer
var part_item_list: ItemList
var stats_label: Label
var total_stats_label: Label
var weight_bar: ProgressBar
var equip_button: Button
var craft_button: Button
var frame_upgrade_button: Button
var repair_part_button: Button
var full_repair_button: Button
var close_button: Button
var status_message_label: Label
# Mech roster page lives in HangarRosterPanel (badge, slot rows, pilot/role
# pickers). The controller keeps only the shared editing state below.
var roster_panel_ui: HangarRosterPanel = null
var catalog_panel: HangarCatalogPanel = null
var garage_panel: HangarGaragePanel = null
var craft_panel: HangarCraftPanel = null
# The mech berth currently open in the customize/roster editor. This is separate
# from GlobalData.active_hangar_mech_id (the mech the player actually pilots in
# combat): prev/next cycles this editing target without reassigning the driver.
var _customize_mech_id: String = ""

# Inner Frame Catalog
# NOTE: First entry per slot must match GlobalData.equipped_frames default names so
# the starter frames show up as "[E]" equipped in the list.
# "carry_bonus" = kg of Field Pack capacity this frame adds (frame = class system).
# Data lives in GlobalData (loaded from resources/data/mech_catalogs.tres).
var frame_catalog: Dictionary:
	get:
		return GlobalData.frame_catalog

# Outer Armor Catalog
## Armor catalog is now stored in GlobalData.armor_catalog (single source of truth).
## This computed property provides a local alias for convenience.
var armor_catalog: Dictionary:
	get:
		return GlobalData.armor_catalog


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	garage_panel = HangarGaragePanel.new()
	garage_panel.controller = self
	garage_panel.build_garage()
	_build_ui_layout()
	nav_panel.show_hangar()
	if has_node("/root/AudioManager"):
		AudioManager.play_hangar_music()


# Returns credits_cost for next frame upgrade level.
# Single source of truth — use this instead of inline calculations.
func _get_upgrade_cost() -> int:
	return GlobalData.get_frame_upgrade_cost()


# --- 2D OVERLAY UI ---
func _build_ui_layout() -> void:
	roster_panel_ui = HangarRosterPanel.new()
	roster_panel_ui.controller = self
	catalog_panel = HangarCatalogPanel.new()
	catalog_panel.controller = self
	craft_panel = HangarCraftPanel.new()
	craft_panel.controller = self
	action_panel = HangarActionPanel.new()
	action_panel.controller = self
	equip_panel = HangarEquipPanel.new()
	equip_panel.controller = self
	part_list_panel = HangarPartListPanel.new()
	part_list_panel.controller = self
	stats_panel = HangarStatsPanel.new()
	stats_panel.controller = self
	nav_panel = HangarNavPanel.new()
	nav_panel.controller = self
	repair_panel = HangarRepairPanel.new()
	repair_panel.controller = self
	slot_panel = HangarSlotPanel.new()
	slot_panel.controller = self
	var root = Control.new()
	root.name = "RootControl"
	root_control = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top Header Bar
	var header = PanelContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.custom_minimum_size = Vector2(0, 80)
	root.add_child(header)
	header.mouse_filter = Control.MOUSE_FILTER_PASS

	var style_hdr = StyleBoxFlat.new()
	style_hdr.bg_color = Color(0.06, 0.08, 0.12, 0.92)
	header.add_theme_stylebox_override("panel", style_hdr)

	var header_vbox = VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 2)
	header.add_child(header_vbox)

	var hdr_box = HBoxContainer.new()
	hdr_box.add_theme_constant_override("separation", 15)
	header_vbox.add_child(hdr_box)

	var title_lbl = Label.new()
	title_lbl.text = " 🛠️ 3D MECHA GARAGE "
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	hdr_box.add_child(title_lbl)

	var selection_label = Label.new()
	selection_label.name = "SelectionLabel"
	selection_label.text = "EDITING: CHASSIS"
	selection_label.add_theme_font_size_override("font_size", 14)
	selection_label.add_theme_color_override("font_color", Color(0.25, 0.9, 1.0))
	hdr_box.add_child(selection_label)

	# Mech-slot switcher (badge + prev/next) lives in the roster panel.
	roster_panel_ui.build_badge_header(hdr_box)

	tab_container = HBoxContainer.new()
	tab_container.add_theme_constant_override("separation", 4)
	hdr_box.add_child(tab_container)

	var slots = [
		{"id": "head", "label": "HEAD"},
		{"id": "body", "label": "BODY"},
		{"id": "arm_left", "label": "L.ARM"},
		{"id": "arm_right", "label": "R.ARM"},
		{"id": "leg_left", "label": "L.LEGS"},
		{"id": "leg_right", "label": "R.LEGS"},
		{"id": "weapon_left", "label": "L.HAND"},
		{"id": "weapon_right", "label": "R.HAND"},
		{"id": "weapon_carry", "label": "BACK CARRY"}
	]

	for slot_info in slots:
		var btn = Button.new()
		btn.text = slot_info["label"]
		btn.custom_minimum_size = Vector2(72, 36)
		btn.pressed.connect(func(): if slot_panel: slot_panel.select(slot_info["id"]))
		slot_tab_buttons[slot_info["id"]] = btn
		tab_container.add_child(btn)

	# Spacer pushes the back-to-menu button to the far right of the header.
	var hdr_spacer = Control.new()
	hdr_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_box.add_child(hdr_spacer)

	back_to_menu_button = Button.new()
	back_to_menu_button.text = "◀ BACK TO MENU"
	back_to_menu_button.custom_minimum_size = Vector2(150, 32)
	back_to_menu_button.focus_mode = Control.FOCUS_NONE
	back_to_menu_button.pressed.connect(func(): nav_panel.on_back_to_menu_pressed())
	back_to_menu_button.visible = false
	hdr_box.add_child(back_to_menu_button)

	# Hangar sub-menu rail: the landing screen. A long vertical list on the left
	# shown first after entering the hangar; each entry opens its own page.
	var submenu_panel = PanelContainer.new()
	submenu_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	submenu_panel.offset_top = 90
	submenu_panel.offset_bottom = -20
	submenu_panel.offset_left = 20
	submenu_panel.custom_minimum_size = Vector2(250, 0)
	submenu_rail = submenu_panel
	root.add_child(submenu_panel)

	var style_rail = StyleBoxFlat.new()
	style_rail.bg_color = Color(0.08, 0.1, 0.15, 0.92)
	style_rail.corner_radius_top_left = 8
	style_rail.corner_radius_top_right = 8
	style_rail.corner_radius_bottom_left = 8
	style_rail.corner_radius_bottom_right = 8
	style_rail.content_margin_left = 14
	style_rail.content_margin_right = 14
	style_rail.content_margin_top = 14
	style_rail.content_margin_bottom = 14
	submenu_panel.add_theme_stylebox_override("panel", style_rail)

	var rail_box = VBoxContainer.new()
	rail_box.add_theme_constant_override("separation", 8)
	submenu_panel.add_child(rail_box)

	var rail_title = Label.new()
	rail_title.text = "HANGAR MENU"
	rail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rail_title.add_theme_font_size_override("font_size", 18)
	rail_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	rail_box.add_child(rail_title)

	var rail_sep = HSeparator.new()
	rail_box.add_child(rail_sep)

	var submenu_items = [
		{"id": "roster", "label": "ROSTER (จัดเก็บหุ่น)"},
		{"id": "customize", "label": "CUSTOMIZE (แต่งหุ่น)"},
		{"id": "emergency", "label": "EMERGENCY REPAIR (ซ่อมแซม)"},
		{"id": "upgrade", "label": "UPGRADE (อัพเกรด)"},
		{"id": "craft", "label": "CRAFT (คราฟ)"},
		{"id": "catalog", "label": "CATALOG (แคตตาล็อก)"},
	]
	for item in submenu_items:
		var sbtn = Button.new()
		sbtn.text = item["label"]
		sbtn.custom_minimum_size = Vector2(0, 34)
		sbtn.focus_mode = Control.FOCUS_NONE
		sbtn.pressed.connect(func(): nav_panel.select_submenu(item["id"]))
		rail_box.add_child(sbtn)

	var rail_spacer = Control.new()
	rail_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail_box.add_child(rail_spacer)

	var rail_exit = Button.new()
	rail_exit.text = "EXIT HANGAR"
	rail_exit.custom_minimum_size = Vector2(0, 40)
	rail_exit.focus_mode = Control.FOCUS_NONE
	rail_exit.pressed.connect(_on_close_pressed)
	rail_box.add_child(rail_exit)

	# Sub-Toggle Bar for Armor Plating vs Inner Skeleton Frame vs Power Upgrade
	sub_toggle_container = HBoxContainer.new()
	sub_toggle_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub_toggle_container.offset_top = 86
	sub_toggle_container.add_theme_constant_override("separation", 8)
	root.add_child(sub_toggle_container)

	var btn_armor = Button.new()
	btn_armor.text = "🛡️ OUTER ARMOR (SCAVENGER)"
	btn_armor.custom_minimum_size = Vector2(170, 32)
	btn_armor.pressed.connect(func(): nav_panel.switch_custom_mode("armor"))
	sub_toggle_container.add_child(btn_armor)

	var btn_frame = Button.new()
	btn_frame.text = "⚙️ INNER SKELETON FRAME"
	btn_frame.custom_minimum_size = Vector2(170, 32)
	btn_frame.pressed.connect(func(): nav_panel.switch_custom_mode("frame"))
	sub_toggle_container.add_child(btn_frame)

	var btn_attachment = Button.new()
	btn_attachment.text = "🔩 FREE ATTACHMENT"
	btn_attachment.custom_minimum_size = Vector2(170, 32)
	btn_attachment.pressed.connect(func(): nav_panel.switch_custom_mode("attachment"))
	sub_toggle_container.add_child(btn_attachment)

	frame_upgrade_button = Button.new()
	frame_upgrade_button.text = "⚡ REACTOR POWER UPGRADE"
	frame_upgrade_button.custom_minimum_size = Vector2(180, 32)
	frame_upgrade_button.pressed.connect(func(): nav_panel.switch_custom_mode("upgrade"))
	sub_toggle_container.add_child(frame_upgrade_button)

	# Left Sidebar (Part Catalog List & Salvaged Drops)
	var left_panel = PanelContainer.new()
	left_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_panel.offset_top = 128
	left_panel.offset_bottom = -20
	left_panel.offset_left = 20
	left_panel.custom_minimum_size = Vector2(330, 0)
	self.left_panel = left_panel
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

	part_item_list = ItemList.new()
	part_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	part_item_list.item_selected.connect(func(i: int): if part_list_panel: part_list_panel.on_item_selected(i))
	part_item_list.item_clicked.connect(func(i: int, p: Vector2, b: int): if part_list_panel: part_list_panel.on_item_clicked(i, p, b))
	part_item_list.item_activated.connect(func(i: int): if part_list_panel: part_list_panel.on_item_activated(i))
	left_box.add_child(part_item_list)

	craft_button = Button.new()
	craft_button.text = "🏭 CRAFTERY (craft parts in a separate window)"
	craft_button.custom_minimum_size = Vector2(0, 30)
	craft_button.pressed.connect(func(): if craft_panel: craft_panel.open())
	left_box.add_child(craft_button)

	ammo_panel = HangarAmmoPanel.new()
	ammo_panel.build(left_box)

	equip_button = Button.new()
	equip_button.text = "EQUIP SELECTION"
	equip_button.custom_minimum_size = Vector2(0, 42)
	equip_button.pressed.connect(func(): if equip_panel: equip_panel.on_equip_pressed())
	left_box.add_child(equip_button)

	# Right Sidebar (Stats & Gundam Frame Core Power Panel)
	var right_panel = PanelContainer.new()
	right_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_panel.offset_top = 128
	right_panel.offset_bottom = -20
	right_panel.offset_right = -20
	right_panel.offset_left = -370
	right_panel.custom_minimum_size = Vector2(350, 0)
	self.right_panel = right_panel
	root.add_child(right_panel)

	var style_right = StyleBoxFlat.new()
	style_right.bg_color = Color(0.08, 0.1, 0.15, 0.88)
	style_right.corner_radius_top_right = 8
	style_right.corner_radius_bottom_right = 8
	style_right.content_margin_left = 14
	style_right.content_margin_right = 14
	style_right.content_margin_top = 14
	style_right.content_margin_bottom = 14
	right_panel.add_theme_stylebox_override("panel", style_right)

	var right_box = VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 10)
	right_panel.add_child(right_box)

	var stats_title = Label.new()
	stats_title.text = "GUNDAM FRAME CORE SPECIFICATIONS"
	stats_title.add_theme_font_size_override("font_size", 14)
	stats_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	right_box.add_child(stats_title)

	stats_label = Label.new()
	stats_label.text = "Select a chassis, frame, or armor to view specifications"
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_box.add_child(stats_label)

	# Hover preview (title + stat card) lives in the catalog panel.
	catalog_panel.build_hover_stats_label(right_box)

	var sep = HSeparator.new()
	right_box.add_child(sep)

	var total_title = Label.new()
	total_title.text = "FRAME VS. ARMOR DUAL CAPACITY"
	total_title.add_theme_font_size_override("font_size", 13)
	right_box.add_child(total_title)

	weight_bar = ProgressBar.new()
	weight_bar.custom_minimum_size = Vector2(0, 22)
	weight_bar.max_value = 85.0
	right_box.add_child(weight_bar)

	total_stats_label = Label.new()
	total_stats_label.text = "FRAME HP: 150 | ARMOR HP: 210\nTOTAL WEIGHT: 42.0 / 75.0 kg"
	right_box.add_child(total_stats_label)

	var sep2 = HSeparator.new()
	right_box.add_child(sep2)

	repair_part_button = Button.new()
	repair_part_button.text = "Repair Selected Slot"
	repair_part_button.pressed.connect(func(): if repair_panel: repair_panel.repair_part())
	right_box.add_child(repair_part_button)

	full_repair_button = Button.new()
	full_repair_button.text = "Full Field Repair"
	full_repair_button.pressed.connect(func(): if repair_panel: repair_panel.full_repair())
	right_box.add_child(full_repair_button)

	# Mech roster page (parking grid) lives in the roster panel.
	roster_panel_ui.build(root)

	status_message_label = Label.new()
	status_message_label.text = ""
	status_message_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	right_box.add_child(status_message_label)

	if ammo_panel:
		ammo_panel.status_label = status_message_label

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_child(spacer)

	close_button = Button.new()
	close_button.text = "EXIT HANGAR"
	close_button.custom_minimum_size = Vector2(0, 44)
	close_button.pressed.connect(_on_close_pressed)
	right_box.add_child(close_button)


# --- HANGAR MECH ROSTER (truck-convoy parking page) ---

# Cross-page editing state lives on the controller (_customize_mech_id) because
# the customize page reads/writes the same berth. These accessors are the seam
# the roster panel (HangarRosterPanel) uses; the default is the piloted mech.
func get_editing_mech_id() -> String:
	return _customize_mech_id if _customize_mech_id != "" else GlobalData.active_hangar_mech_id


func set_editing_mech_id(id: String) -> void:
	_customize_mech_id = id


# Called by the roster panel after the edited berth changes: repaints the 3D
# preview + total stats, and (optionally) the current slot's part list — the
# same refresh set the old in-controller cycle/switch logic ran.
func refresh_after_mech_change(repopulate_parts: bool) -> void:
	garage_panel.update_all_slots_preview()
	stats_panel.update()
	if repopulate_parts:
		part_list_panel.populate(selected_slot)


# Called by the catalog panel after applying a chassis: repaints total stats
# + the 3D preview with the new model — same refresh set the old in-controller
# chassis apply ran.
func refresh_after_chassis_change(chassis_info: Dictionary) -> void:
	stats_panel.update()
	garage_panel.update_all_slots_preview()
	if not chassis_info.is_empty() and garage_panel:
		garage_panel.apply_chassis_preview(chassis_info)


# Called by the craft panel after a successful craft: repopulates the slot's
# part list and refreshes total stats — the same refresh set the old
# in-controller craft flow ran.
func refresh_after_craft(slot: String) -> void:
	part_list_panel.populate(slot)
	stats_panel.update()


# --- AMMO LOADOUT UI (how much ammo to carry into the next battle) ---
# Lives in its own panel script; builds into the left panel during layout.
var ammo_panel: HangarAmmoPanel = null


# --- 3D CAMERA & MOUSE DRAG PROCESS ---
func _process(delta: float) -> void:
	if not visible:
		return

	if garage_panel:
		garage_panel.process(delta)

	# Live hover preview of the list row under the cursor (customize page).
	if catalog_panel:
		catalog_panel.refresh_hover_stats()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# The emergency repair editor is a full-screen modal: don't rotate the hangar
	# turntable or drag attachments while it is open on top.
	if _is_scrap_editor_open():
		return
	if garage_panel:
		garage_panel.handle_input(event)


func _is_scrap_editor_open() -> bool:
	return scrap_editor != null and is_instance_valid(scrap_editor) and scrap_editor.visible


func _on_close_pressed() -> void:
	# Persist any edits made on the customize page to the berth being edited,
	# then restore the ACTIVE mech (the one the player actually pilots) back into
	# the working set so combat loads the right machine.
	_persist_customize_edits()
	_check_combat_readiness_warning(func():
		visible = false
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		GlobalData.save_run()
		if GameManager and GameManager.has_method("return_to_board"):
			GameManager.return_to_board()
		else:
			EventBus.game_state_changed.emit("HANGAR", "INTERMISSION")
	)


# Save the current working set onto the mech that's open in the editor, then
# (if that isn't the active/piloting mech) reload the active mech's parts so the
# player leaves the hangar with the machine they'll actually pilot.
func _persist_customize_edits() -> void:
	var editing_id := get_editing_mech_id()
	if editing_id == "":
		return
	GlobalData.save_hangar_mech_state(editing_id)
	_customize_mech_id = editing_id
	if editing_id != GlobalData.active_hangar_mech_id:
		GlobalData.load_hangar_mech_state(GlobalData.active_hangar_mech_id)


# Persist the working set back onto the berth being edited (so its roster
# snapshot is fresh), then save the run. Called after equip/unequip so edits to
# a non-active mech on the customize page land on the right entry.
func _commit_editing_mech_and_save() -> void:
	if _customize_mech_id != "":
		GlobalData.save_hangar_mech_state(_customize_mech_id)
	GlobalData.save_run()


func _check_combat_readiness_warning(on_confirm: Callable) -> void:
	var has_legs = GlobalData.equipped_parts.has("leg_left") or GlobalData.equipped_parts.has("leg_right")
	var has_body = GlobalData.equipped_parts.has("body")
	
	if has_legs and has_body:
		on_confirm.call()
		return
		
	var old = get_node_or_null("CombatWarningModal")
	if old: old.queue_free()
	
	var modal = PanelContainer.new()
	modal.name = "CombatWarningModal"
	modal.anchor_left = 0.5
	modal.anchor_right = 0.5
	modal.anchor_top = 0.5
	modal.anchor_bottom = 0.5
	modal.offset_left = -240
	modal.offset_right = 240
	modal.offset_top = -140
	modal.offset_bottom = 140

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.08, 0.08, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 0.4, 0.2)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	modal.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	modal.add_child(vbox)

	var title = Label.new()
	title.text = "⚠️ WARNING: INCOMPLETE MECH ASSEMBLY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
	vbox.add_child(title)

	var msg = Label.new()
	msg.text = "คำเตือน: หุ่นของคุณประกอบไม่ครบชุด (ไม่มีขา/เกราะไม่ครบ)!\nอาจทำให้เคลื่อนที่และต่อสู้ในด่านได้ยากลำบาก\n\n(คุณยังคงเข้าเล่นด่านได้ แล้วแต่ศรัทธา - รองรับ Hover ในอนาคต)"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(msg)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 15)
	vbox.add_child(hbox)

	var launch_btn = Button.new()
	launch_btn.text = "LAUNCH ANYWAY (ลุยเลย)"
	launch_btn.custom_minimum_size = Vector2(140, 36)
	launch_btn.pressed.connect(func():
		modal.queue_free()
		on_confirm.call()
	)
	hbox.add_child(launch_btn)

	var back_btn = Button.new()
	back_btn.text = "BACK TO HANGAR (แต่งหุ่นต่อ)"
	back_btn.custom_minimum_size = Vector2(150, 36)
	back_btn.pressed.connect(func(): modal.queue_free())
	hbox.add_child(back_btn)

	root_control.add_child(modal)


# A patch was applied (or the editor closed): re-sync the hangar's own 3D mech
# preview so the crude scrap armor shows on the correct skeleton parts.
func _on_scrap_editor_applied(_slot: String) -> void:
	garage_panel.call_deferred("update_all_slots_preview")


func _on_scrap_editor_closed() -> void:
	garage_panel.call_deferred("update_all_slots_preview")


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		_on_close_pressed()
