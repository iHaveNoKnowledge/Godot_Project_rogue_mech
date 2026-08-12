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
var header_panel: HangarHeaderPanel = null
var left_panel_ui: HangarLeftPanel = null
var right_panel_ui: HangarRightPanel = null
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
	header_panel = HangarHeaderPanel.new()
	header_panel.controller = self
	left_panel_ui = HangarLeftPanel.new()
	left_panel_ui.controller = self
	right_panel_ui = HangarRightPanel.new()
	right_panel_ui.controller = self

	var root = Control.new()
	root.name = "RootControl"
	root_control = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top header bar (title, slot tabs, back-to-menu) + badge from the roster panel.
	header_panel.build(root)
	# Landing sub-menu rail + the mode-toggle bar (armor / frame / attachment / upgrade).
	nav_panel.build_landing_rail(root)
	nav_panel.build_mode_toggles(root)
	# Left sidebar (part list, craftery, ammo loadout, equip) + right sidebar
	# (stats, weight bar, repair buttons, status message, exit).
	left_panel_ui.build(root)
	right_panel_ui.build(root)


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
