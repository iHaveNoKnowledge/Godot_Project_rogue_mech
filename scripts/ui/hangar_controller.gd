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
var _last_selected_item_index: int = -1
var visible_weapon_indices: Array[int] = []
# When true, _on_part_item_selected should only update stats text and NOT change
# the 3D model preview. Set during _populate_part_list_for_slot() auto-selects.
var _is_populating: bool = false
var action_panel: HangarActionPanel = null
var equip_panel: HangarEquipPanel = null
# Slot tab buttons keyed by slot id, reused for UI-only selection highlight.
var slot_tab_buttons: Dictionary = {}

# Top-level hangar sub-menu (landing screen): [CUSTOMIZE | EMERGENCY REPAIR |
# UPGRADE | CRAFT | CATALOG]. It is the FIRST thing shown after entering the
# hangar as a long vertical list on the left; each choice opens its own page.
var hangar_submenu_buttons: Dictionary = {}
var current_submenu: String = "" # "" = landing menu
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
	show_hangar()
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
		btn.pressed.connect(func(): _select_slot_tab(slot_info["id"]))
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
	back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
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
		sbtn.pressed.connect(func(): _select_hangar_submenu(item["id"]))
		hangar_submenu_buttons[item["id"]] = sbtn
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
	btn_armor.pressed.connect(func(): _switch_custom_mode("armor"))
	sub_toggle_container.add_child(btn_armor)

	var btn_frame = Button.new()
	btn_frame.text = "⚙️ INNER SKELETON FRAME"
	btn_frame.custom_minimum_size = Vector2(170, 32)
	btn_frame.pressed.connect(func(): _switch_custom_mode("frame"))
	sub_toggle_container.add_child(btn_frame)

	var btn_attachment = Button.new()
	btn_attachment.text = "🔩 FREE ATTACHMENT"
	btn_attachment.custom_minimum_size = Vector2(170, 32)
	btn_attachment.pressed.connect(func(): _switch_custom_mode("attachment"))
	sub_toggle_container.add_child(btn_attachment)

	frame_upgrade_button = Button.new()
	frame_upgrade_button.text = "⚡ REACTOR POWER UPGRADE"
	frame_upgrade_button.custom_minimum_size = Vector2(180, 32)
	frame_upgrade_button.pressed.connect(func(): _switch_custom_mode("upgrade"))
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
	part_item_list.item_selected.connect(_on_part_item_selected)
	part_item_list.item_clicked.connect(_on_part_item_clicked)
	part_item_list.item_activated.connect(_on_part_item_activated)
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
	repair_part_button.pressed.connect(_on_repair_part_pressed)
	right_box.add_child(repair_part_button)

	full_repair_button = Button.new()
	full_repair_button.text = "Full Field Repair"
	full_repair_button.pressed.connect(_on_full_repair_pressed)
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

func _show_roster_page() -> void:
	current_submenu = "roster"
	if craft_panel:
		craft_panel.close_window()
	if catalog_panel:
		catalog_panel.close_window()
	if scrap_editor != null and is_instance_valid(scrap_editor) and scrap_editor.visible:
		scrap_editor.close()
	if submenu_rail:
		submenu_rail.visible = false
	if back_to_menu_button:
		back_to_menu_button.visible = true
	if tab_container:
		tab_container.visible = false
	if sub_toggle_container:
		sub_toggle_container.visible = false
	if left_panel:
		left_panel.visible = false
	if right_panel:
		right_panel.visible = false
	if roster_panel_ui:
		roster_panel_ui.show_page()
	garage_panel.call_deferred("update_all_slots_preview")


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
	_update_total_stats()
	if repopulate_parts:
		_populate_part_list_for_slot(selected_slot)


# Called by the catalog panel after applying a chassis: repaints total stats
# + the 3D preview with the new model — same refresh set the old in-controller
# chassis apply ran.
func refresh_after_chassis_change(chassis_info: Dictionary) -> void:
	_update_total_stats()
	garage_panel.update_all_slots_preview()
	if not chassis_info.is_empty() and garage_panel:
		garage_panel.apply_chassis_preview(chassis_info)


# Called by the craft panel after a successful craft: repopulates the slot's
# part list and refreshes total stats — the same refresh set the old
# in-controller craft flow ran.
func refresh_after_craft(slot: String) -> void:
	_populate_part_list_for_slot(slot)
	_update_total_stats()


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


func show_hangar() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Open the editor on the mech the player is currently piloting.
	_customize_mech_id = GlobalData.active_hangar_mech_id
	_update_total_stats()
	AudioManager.play_hangar_music()
	garage_panel.call_deferred("update_all_slots_preview")
	# Entering the hangar shows the landing sub-menu first — the customize page
	# only appears once the driver picks a topic (CUSTOMIZE / UPGRADE / etc).
	_show_hangar_menu()


func _switch_custom_mode(mode: String) -> void:
	current_mode = mode
	_populate_part_list_for_slot(selected_slot)


# --- HANGAR SUB-MENU (landing list: CUSTOMIZE / EMERGENCY REPAIR / UPGRADE / CRAFT / CATALOG) ---

# Landing screen: the long vertical sub-menu list. Every page widget is hidden
# until the driver picks a topic.
func _show_hangar_menu() -> void:
	current_submenu = ""
	if craft_panel:
		craft_panel.close_window()
	if catalog_panel:
		catalog_panel.close_window()
	if scrap_editor != null and is_instance_valid(scrap_editor) and scrap_editor.visible:
		scrap_editor.close()
	if submenu_rail:
		submenu_rail.visible = true
	if back_to_menu_button:
		back_to_menu_button.visible = false
	if tab_container:
		tab_container.visible = false
	if sub_toggle_container:
		sub_toggle_container.visible = false
	if left_panel:
		left_panel.visible = false
	if right_panel:
		right_panel.visible = false
	if roster_panel_ui:
		roster_panel_ui.hide_page()
	if root_control:
		var label := root_control.find_child("SelectionLabel", true, false) as Label
		if label:
			label.text = "HANGAR MENU"
	if garage_panel:
		garage_panel.clear_selection_blink()


# The customize page (mech center, part list left, stats right). Also the base
# surface for upgrade/craft/catalog which open their windows over it.
func _show_customize_page() -> void:
	if submenu_rail:
		submenu_rail.visible = false
	if back_to_menu_button:
		back_to_menu_button.visible = true
	if tab_container:
		tab_container.visible = true
	if left_panel:
		left_panel.visible = true
	if right_panel:
		right_panel.visible = true
	if roster_panel_ui:
		roster_panel_ui.set_panel_visible(false)
		roster_panel_ui.set_badge_visible(true)
	if sub_toggle_container:
		sub_toggle_container.visible = not selected_slot.begins_with("weapon")
	if roster_panel_ui:
		roster_panel_ui.refresh_badge()
	_populate_part_list_for_slot(selected_slot)
	garage_panel.update_selection_highlight(selected_slot)


func _on_back_to_menu_pressed() -> void:
	if craft_panel:
		craft_panel.close_window()
	if catalog_panel:
		catalog_panel.close_window()
	if scrap_editor != null and is_instance_valid(scrap_editor) and scrap_editor.visible:
		scrap_editor.close()
	_show_hangar_menu()


func _select_hangar_submenu(id: String) -> void:
	current_submenu = id
	if craft_panel:
		craft_panel.close_window()
	if catalog_panel:
		catalog_panel.close_window()
	match id:
		"emergency":
			# Emergency scrap repair is a full-screen overlay opened straight from
			# the landing menu; the menu stays behind so closing the editor
			# returns the driver to the hangar menu.
			_init_scrap_editor()
			var first_slot := ""
			for slot in GlobalData.MECHA_SLOTS:
				if GlobalData.get_emergency_repair_scrap_cost(slot) > 0:
					first_slot = slot
					break
			scrap_editor.open(first_slot)
		"upgrade":
			_show_customize_page()
			_switch_custom_mode("upgrade")
		"craft":
			_show_customize_page()
			if not armor_catalog.has(selected_slot):
				selected_slot = "body"
				garage_panel.update_selection_highlight(selected_slot)
				_populate_part_list_for_slot(selected_slot)
			if craft_panel:
				craft_panel.open()
		"catalog":
			_show_customize_page()
			if catalog_panel:
				catalog_panel.build_window()
		"roster":
			_show_roster_page()
		_:
			# "customize" (and any fallback): restore the standard editing view.
			_show_customize_page()


func _init_scrap_editor() -> void:
	if scrap_editor != null:
		return
	scrap_editor = preload("res://scripts/ui/scrap_repair_editor.gd").new()
	scrap_editor.applied.connect(_on_scrap_editor_applied)
	scrap_editor.closed.connect(_on_scrap_editor_closed)
	add_child(scrap_editor)


# A patch was applied (or the editor closed): re-sync the hangar's own 3D mech
# preview so the crude scrap armor shows on the correct skeleton parts.
func _on_scrap_editor_applied(_slot: String) -> void:
	garage_panel.call_deferred("update_all_slots_preview")


func _on_scrap_editor_closed() -> void:
	garage_panel.call_deferred("update_all_slots_preview")


func _select_slot_tab(slot: String) -> void:
	selected_slot = slot
	if craft_panel:
		craft_panel.close_window()
	sub_toggle_container.visible = not slot.begins_with("weapon")
	if ammo_panel:
		ammo_panel.ammo_loadout_box.visible = slot.begins_with("weapon")
		if ammo_panel.ammo_loadout_box.visible:
			ammo_panel.refresh()
	garage_panel.update_camera_focus(slot)
	_populate_part_list_for_slot(slot)
	_update_total_stats()
	garage_panel.update_selection_highlight(slot)


func _is_item_equipped(slot: String, info: Dictionary) -> bool:
	if info.is_empty():
		return false

	if slot.begins_with("weapon"):
		return _is_weapon_in_loadout(slot, info.get("path", ""))

	if current_mode == "frame":
		var cur_frame = GlobalData.equipped_frames.get(slot, {})
		if cur_frame is Dictionary and not cur_frame.is_empty():
			var name_a = cur_frame.get("name", cur_frame.get("part_name", "")).to_lower()
			var name_b = info.get("name", info.get("part_name", "")).to_lower()
			if name_a != "" and name_b != "":
				return name_a == name_b
		return false
	else:
		var cur = GlobalData.equipped_parts.get(slot)
		if cur == null:
			return false

		# 0. Match by instance uid (authoritative for owned instances)
		if cur is Dictionary and cur.has("uid") and info.has("uid"):
			return cur["uid"] == info["uid"]

		# 1. Match by unique ID if available
		var cur_id = ""
		if cur is Dictionary:
			cur_id = cur.get("id", "")
		elif cur is Resource and "id" in cur:
			cur_id = cur.id
		var info_id = info.get("id", "")
		# Catalog IDs are authoritative. Do not fall back to path/name when both
		# entries share the same Resource path.
		if info_id != "":
			return cur_id != "" and cur_id == info_id
		if cur_id != "":
			return false

		# 2. Match by Resource file path
		var cur_path = ""
		if cur is Dictionary:
			cur_path = cur.get("path", "")
		elif cur is Resource:
			cur_path = cur.resource_path
		var info_path = info.get("path", "")
		if cur_path != "" and info_path != "" and cur_path == info_path:
			return true

		# 3. Match by Part Name
		var cur_name = ""
		if cur is Dictionary:
			cur_name = cur.get("name", cur.get("part_name", "")).to_lower()
		elif cur is Resource and "part_name" in cur:
			cur_name = cur.part_name.to_lower()
		var info_name = info.get("name", info.get("part_name", "")).to_lower()
		if cur_name != "" and info_name != "":
			return cur_name == info_name

		return false


# Current durability fraction (0..1) of an owned armor instance. Uses the live
# combat damage cache for the equipped one, otherwise the instance's persisted
# durability.
func _get_instance_durability(slot: String, inst: Dictionary) -> float:
	if _is_item_equipped(slot, inst):
		return GlobalData.get_part_durability(slot)
	return GlobalData.get_durability_ratio(inst)


# Whether a weapon path is part of the current loadout for this weapon slot.
func _is_weapon_in_loadout(slot: String, path: String) -> bool:
	if path == "":
		return false
	if slot == "weapon_carry":
		return GlobalData.is_weapon_in_carry(path)
	var hand = "left" if slot == "weapon_left" else "right"
	return str(GlobalData.weapon_loadout.get(hand, "")) == path


func _populate_part_list_for_slot(slot: String) -> void:
	action_panel.close()
	part_item_list.clear()
	_last_selected_item_index = -1
	visible_salvage_indices.clear()
	_is_populating = true  # Block 3D preview during auto-populate

	if current_mode == "upgrade":
		var cost = _get_upgrade_cost()
		part_item_list.add_item("Upgrade Inner Frame to Level %d (%d cr)" % [
			GlobalData.frame_upgrade_level + 1, cost
		])
		if part_item_list.item_count > 0:
			part_item_list.select(0)
			_last_selected_item_index = 0
			_on_part_item_selected(0)
		_is_populating = false
		return

	if current_mode == "attachment":
		if slot not in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
			part_item_list.add_item("Select a body section first")
		else:
			var capacity = garage_panel.get_attachment_capacity(slot)
			var used = garage_panel.get_attachment_weight(slot)
			for info in attachment_catalog:
				var prefix = "[E] " if garage_panel.has_attachment(info["id"], slot) else "    "
				part_item_list.add_item("%s%s (%.1fkg / %.1fkg capacity)" % [prefix, info["name"], info["weight"], capacity])
			if part_item_list.item_count > 0:
				part_item_list.select(0)
				_last_selected_item_index = 0
				_on_part_item_selected(0)
		_is_populating = false
		return

	var is_destroyed = GlobalData.part_damage.get(slot + "_frame", 0.0) >= 1.0

	if current_mode == "frame" and frame_catalog.has(slot):
		var items = frame_catalog[slot]
		# Roguelike: a destroyed frame is gone. Hide the equipped broken frame so
		# it can no longer be repaired or re-selected from the list.
		var frame_gone: bool = GlobalData.part_damage.get(slot + "_frame", 0.0) >= 1.0
		for info in items:
			var is_eq = _is_item_equipped(slot, info)
			if is_eq and frame_gone:
				continue
			var prefix = "[X] " if is_eq and is_destroyed else ("[E] " if is_eq else "     ")
			var fname = info.get("name", "Frame Part")
			var fhp = info.get("hp", 20.0)
			var fwt = info.get("weight", 3.0)
			var state_tag = " [DESTROYED]" if (is_eq and is_destroyed) else ""
			var label_str = "%s%s (HP: %.0f, %.1fkg)%s" % [prefix, fname, fhp, fwt, state_tag]
			part_item_list.add_item(label_str)
		if items.size() > 0:
			part_item_list.select(0)
			_last_selected_item_index = 0
			_on_part_item_selected(0)
	elif slot.begins_with("weapon"):
		# Weapons come from the central inventory stash (GlobalData.weapon_inventory),
		# NOT from armor_catalog — the stash is the single source of owned weapons.
		visible_weapon_indices.clear()
		for index in range(GlobalData.weapon_inventory.size()):
			var inv = GlobalData.weapon_inventory[index]
			var wpath = inv.get("path", "")
			var wname = inv.get("name", "Weapon")
			var wdur = GlobalData.get_durability_ratio(inv)
			var is_eq = _is_weapon_in_loadout(slot, wpath)
			var prefix = "[E] " if is_eq else "    "
			# Same-model copies are distinct items: show how many you own and, on
			# the carry slot, how many are actually on the pack right now.
			var count := int(inv.get("count", 1))
			var count_str := " x%d" % count if count > 1 else ""
			var label_str = "%s%s%s (DUR: %.0f%%)" % [prefix, wname, count_str, wdur * 100.0]
			part_item_list.add_item(label_str)
			visible_weapon_indices.append(index)
		if part_item_list.item_count > 0:
			part_item_list.select(0)
			_last_selected_item_index = 0
			_on_part_item_selected(0)
	elif armor_catalog.has(slot):
		# EQUIP list = owned armor instances only. The equipped slot is matched
		# strictly by instance uid, so exactly one item ever shows "[E]". The
		# currently equipped instance is always included by uid even if its stored
		# slot tag is missing/stale (legacy saves). Crafting lives in the separate
		# Craftery window and never alters what appears here.
		visible_salvage_indices.clear()
		var shown_uids := {}
		var equipped_uid := ""
		var eq_part = GlobalData.equipped_parts.get(slot)
		if eq_part is Dictionary:
			equipped_uid = str(eq_part.get("uid", ""))
		for inst_index in range(GlobalData.armor_inventory.size()):
			var inst = GlobalData.armor_inventory[inst_index]
			var uid = str(inst.get("uid", ""))
			if str(inst.get("slot", "")) != slot and uid != equipped_uid:
				continue
			if uid in shown_uids and uid != "":
				continue
			if uid != "":
				shown_uids[uid] = true
			visible_salvage_indices.append(inst_index)
			var is_eq = _is_item_equipped(slot, inst)
			# Roguelike: a destroyed part is gone. Hide the equipped broken armor
			# so it can no longer be selected, repaired, or re-equipped.
			if is_eq and (GlobalData.part_damage.get(slot, 0.0) >= 1.0 or GlobalData.part_damage.get(slot + "_frame", 0.0) >= 1.0):
				continue
			var prefix = "[E] " if is_eq else "    "
			var state_tag = " [DESTROYED]" if (is_eq and is_destroyed) else ""
			var dur_pct = _get_instance_durability(slot, inst)
			var inst_label = "%s%s [%s] (%.0f%%)%s" % [prefix, inst.get("name", "Armor"), inst.get("type", "Instance"), dur_pct * 100.0, state_tag]
			part_item_list.add_item(inst_label)
		if part_item_list.item_count > 0:
			part_item_list.select(0)
			_last_selected_item_index = 0
			_on_part_item_selected(0)

	_is_populating = false  # Restore flag



func _on_part_item_selected(index: int) -> void:
	if current_mode == "upgrade":
		var cost = _get_upgrade_cost()
		stats_label.text = "INNER FRAME REACTOR LEVEL: %d -> %d\n\nEFFECTS:\n+25 FRAME HP per slot\n+15.0 kg MAX WEIGHT CAPACITY\n+1.5 m/s DASH THRUST SPEED\n\nUPGRADE COST: %d Credits" % [
			GlobalData.frame_upgrade_level, GlobalData.frame_upgrade_level + 1, cost
		]
		selected_salvage_info = {}
		return

	if current_mode == "attachment":
		if index < 0 or index >= attachment_catalog.size(): return
		selected_attachment_info = attachment_catalog[index].duplicate(true)
		selected_attachment_info["slot"] = selected_slot
		var capacity = garage_panel.get_attachment_capacity(selected_slot)
		var used = garage_panel.get_attachment_weight(selected_slot, selected_attachment_info["id"])
		stats_label.text = "ATTACHMENT: %s\n\nTARGET SECTION: %s\nWEIGHT: %.1f kg\nSECTION CAPACITY: %.1f kg\nCURRENT LOAD: %.1f kg\nPOWER COST: %.1f\n\nDrag on the 3D Mecha to place this module." % [
			selected_attachment_info["name"], selected_slot.to_upper(), selected_attachment_info["weight"], capacity, used, selected_attachment_info["power_cost"]
		]
		return

	if current_mode == "frame" and frame_catalog.has(selected_slot):
		var frame_items = frame_catalog[selected_slot]
		if index >= 0 and index < frame_items.size():
			selected_frame_info = frame_items[index]
			selected_part_path = ""
			selected_part_id = ""
			selected_salvage_info = {}

			var fname = selected_frame_info.get("name", selected_frame_info.get("part_name", "Inner Frame"))
			var fcap = HangarPartText.frame_capability_text(selected_frame_info)
			var is_eq = _is_item_equipped(selected_slot, selected_frame_info)
			if is_eq:
				var frame_dmg = GlobalData.part_damage.get(selected_slot + "_frame", 0.0)
				stats_label.text = "INNER FRAME PART: %s  [E]\nDURABILITY: %.0f%%\n\n%s\n\nThis frame is currently equipped." % [
					fname, (1.0 - clampf(frame_dmg, 0.0, 1.0)) * 100.0, fcap
				]
			else:
				stats_label.text = "INNER FRAME PART: %s\nDURABILITY: 100%%\n\n%s\n\nEquip this frame to install it fresh at 100%% HP." % [
					fname, fcap
				]
			# Only change 3D model when user explicitly picks a part, not on section switch
			if not _is_populating:
				garage_panel.apply_frame_preview(selected_slot, selected_frame_info)
		_update_total_stats()
		return

	if selected_slot.begins_with("weapon"):
		if index >= 0 and index < visible_weapon_indices.size():
			var inv_idx = visible_weapon_indices[index]
			var inv = GlobalData.weapon_inventory[inv_idx]
			var wpath = inv.get("path", "")
			selected_part_path = wpath
			selected_part_id = wpath
			selected_frame_info = {}
			selected_salvage_info = {}

			var wname = inv.get("name", "Weapon")
			var wdur = GlobalData.get_durability_ratio(inv)
			var wwt := 0.0
			var wtype := "Unknown"
			var wcap := ""
			var res = null
			if wpath != "" and ResourceLoader.exists(wpath):
				res = load(wpath)
				if res:
					wwt = float(res.weight) if "weight" in res and res.weight != null else 0.0
					wtype = HangarPartText.weapon_type_label(res.weapon_type) if "weapon_type" in res else "Unknown"
					wcap = HangarPartText.weapon_capability_text(res)

			if selected_slot == "weapon_carry":
				var eq = GlobalData.is_weapon_in_carry(wpath)
				var carried := GlobalData.count_carry_weapon(wpath)
				var owned := int(inv.get("count", 1))
				var prefix = "[E] " if eq else ""
				var copies := ""
				if owned > 1:
					copies = "\nOWNED: x%d | ON PACK: x%d" % [owned, carried]
				stats_label.text = "BACK CARRY: %s%s\nDURABILITY: %.0f%%%s\n\n%s\nWEIGHT: %.1f kg\n\nAssigns a copy to the mech's back pack (FIELD PACK).\nFIELD PACK: %.1f / %.1f kg\nPick weapons from the stash below." % [
					prefix, wname, wdur * 100.0, copies, wcap if not wcap.is_empty() else "TYPE: %s" % wtype,
					wwt,
					GlobalData.get_field_pack_weight(), GlobalData.get_field_pack_capacity()
				]
			else:
				var hand = "left" if selected_slot == "weapon_left" else "right"
				var eq = str(GlobalData.weapon_loadout.get(hand, "")) == wpath
				var prefix = "[E] " if eq else ""
				stats_label.text = "%s HAND WEAPON: %s%s\nDURABILITY: %.0f%%\n\n%s\nWEIGHT: %.1f kg\n\nEquip this weapon to the %s hand.\nFIELD PACK: %.1f / %.1f kg" % [
					hand.to_upper(), prefix, wname, wdur * 100.0, wcap if not wcap.is_empty() else "TYPE: %s" % wtype,
					wwt, hand,
					GlobalData.get_field_pack_weight(), GlobalData.get_field_pack_capacity()
				]
			# Only change 3D model when user explicitly picks a part, not on section switch
			if not _is_populating:
				garage_panel.preview_weapon_on_hand(selected_slot, inv)
		_update_total_stats()
		return

	if armor_catalog.has(selected_slot):
		if index >= 0 and index < visible_salvage_indices.size():
			var salvaged_idx = visible_salvage_indices[index]
			selected_salvage_info = GlobalData.armor_inventory[salvaged_idx]
			selected_part_path = ""
			selected_part_id = ""
			selected_frame_info = {}

			var item_name = selected_salvage_info.get("name", selected_salvage_info.get("part_name", "Armor Instance"))
			var acap = HangarPartText.armor_capability_text(selected_salvage_info, _get_instance_durability(selected_slot, selected_salvage_info))

			var is_eq = _is_item_equipped(selected_slot, selected_salvage_info)
			if is_eq:
				stats_label.text = "OWNED ARMOR: %s  [E]\nDURABILITY: %.0f%%\n\n%s\n\nThis plate is currently equipped." % [
					item_name, _get_instance_durability(selected_slot, selected_salvage_info) * 100.0, acap
				]
			else:
				var dur_pct = _get_instance_durability(selected_slot, selected_salvage_info)
				stats_label.text = "OWNED ARMOR: %s\nDURABILITY: %.0f%%\n\n%s\n\nEquip this plate to install it." % [
					item_name, dur_pct * 100.0, acap
				]
			# Only change 3D model when user explicitly picks a part, not on section switch
			if not _is_populating:
				garage_panel.apply_salvage_preview(selected_slot, selected_salvage_info)
	_update_total_stats()


func _on_part_item_clicked(index: int, _at_position: Vector2 = Vector2.ZERO, _mouse_button_index: int = 1) -> void:
	# Single click: select & close any open modal. The Action Popup opens on
	# double-click (item_activated) so a click never accidentally triggers it.
	if index != _last_selected_item_index:
		_last_selected_item_index = index
		_on_part_item_selected(index)
	action_panel.close()


func _on_part_item_activated(index: int) -> void:
	# Double-click (or Enter): Open the Action Popup Modal!
	var info_to_show: Dictionary = _resolve_part_info_for_index(index)
	if not info_to_show.is_empty():
		action_panel.show(info_to_show)


func _resolve_part_info_for_index(index: int) -> Dictionary:
	var info_to_show: Dictionary = {}
	if not selected_salvage_info.is_empty():
		info_to_show = selected_salvage_info
	elif not selected_frame_info.is_empty():
		info_to_show = selected_frame_info
	elif current_mode == "frame" and frame_catalog.has(selected_slot):
		var items = frame_catalog[selected_slot]
		if index >= 0 and index < items.size():
			info_to_show = items[index]
	elif selected_slot.begins_with("weapon"):
		if index >= 0 and index < visible_weapon_indices.size():
			var inv_idx = visible_weapon_indices[index]
			info_to_show = GlobalData.weapon_inventory[inv_idx]
	elif armor_catalog.has(selected_slot):
		if index >= 0 and index < visible_salvage_indices.size():
			info_to_show = GlobalData.armor_inventory[visible_salvage_indices[index]]
	return info_to_show


func _on_repair_part_pressed() -> void:
	var repair_cost := GlobalData.get_repair_cost(selected_slot)
	if repair_cost <= 0:
		status_message_label.text = "%s is fully functional!" % selected_slot.to_upper()
		return
	if not GlobalData.try_spend_credits(repair_cost):
		status_message_label.text = "Need %d credits!" % repair_cost
		return
	GlobalData.part_damage.erase(selected_slot)
	GlobalData.part_damage.erase(selected_slot + "_frame")
	status_message_label.text = "Repaired %s!" % selected_slot.to_upper()
	_update_total_stats()
	garage_panel.update_all_slots_preview()


func _on_full_repair_pressed() -> void:
	var total_cost := 0
	for slot in GlobalData.MECHA_SLOTS:
		total_cost += GlobalData.get_repair_cost(slot)

	if total_cost <= 0:
		status_message_label.text = "All parts OK!"
		return

	if not GlobalData.try_spend_credits(total_cost):
		status_message_label.text = "Need %d credits!" % total_cost
		return

	GlobalData.part_damage.clear()
	status_message_label.text = "Full Repair Complete!"
	_update_total_stats()
	garage_panel.update_all_slots_preview()


func _update_total_stats() -> void:
	var chassis_info = GlobalData.chassis_catalog.get(GlobalData.chassis_id, GlobalData.chassis_catalog["standard"])
	var max_weight = chassis_info["max_weight"] + GlobalData.get_frame_upgrade_weight_bonus()

	var total_frame_weight = 0.0
	var total_armor_weight = 0.0
	var total_frame_hp = 0.0
	var total_armor_hp = 0.0
	var total_attachment_weight = 0.0

	for slot in GlobalData.equipped_frames:
		var f = GlobalData.equipped_frames[slot]
		var max_fhp = f.get("hp", 0.0) + GlobalData.get_frame_upgrade_hp_bonus()
		total_frame_weight += f.get("weight", 0.0)
		total_frame_hp += max_fhp * (1.0 - clampf(GlobalData.part_damage.get(slot + "_frame", 0.0), 0.0, 1.0))

	for slot in GlobalData.equipped_parts:
		var p = GlobalData.equipped_parts[slot]
		if p and p.get("weight") != null:
			total_armor_weight += p.weight
		if p and (p.get("hp") != null or p.get("max_hp") != null):
			var max_ahp = float(p.get("hp", p.get("max_hp", 0.0)))
			total_armor_hp += max_ahp * (1.0 - clampf(GlobalData.part_damage.get(slot, 0.0), 0.0, 1.0))

	for attachment in GlobalData.attachments:
		total_attachment_weight += float(attachment.get("weight", 0.0))

	var total_weapon_weight = GlobalData.get_loadout_weapon_weight()
	var total_weight = total_frame_weight + total_armor_weight + total_attachment_weight + total_weapon_weight

	var field_pack_weight = GlobalData.get_field_pack_weight()
	var field_pack_capacity = GlobalData.get_field_pack_capacity()

	if weight_bar:
		weight_bar.max_value = max_weight
		weight_bar.value = total_weight

	if total_stats_label:
		total_stats_label.text = "FRAME LVL: %d | FRAME HP: %.0f | ARMOR HP: %.0f\nFRAME W: %.1fkg | ARMOR W: %.1fkg | ATTACH W: %.1fkg | WEAPON W: %.1fkg\nTOTAL WEIGHT: %.1f / %.1f kg\nFIELD PACK: %.1f / %.1f kg\nCREDITS: %d cr   |   SCRAP: %d" % [
			GlobalData.frame_upgrade_level, total_frame_hp, total_armor_hp,
			total_frame_weight, total_armor_weight, total_attachment_weight, total_weapon_weight,
			total_weight, max_weight,
			field_pack_weight, field_pack_capacity,
			GlobalData.credits, GlobalData.scrap
		]


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		_on_close_pressed()
