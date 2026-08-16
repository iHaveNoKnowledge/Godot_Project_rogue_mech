extends Node3D

const PilotLoadoutEditorScript = preload("res://scripts/ui/hangar/hangar_pilot_loadout_editor.gd")

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
var readiness_panel: HangarReadinessPanel = null
var persist_panel: HangarPersistPanel = null
var scrap_panel: HangarScrapPanel = null
var exit_panel: HangarExitPanel = null
var refresh_panel: HangarRefreshPanel = null
var header_panel: HangarHeaderPanel = null
var left_panel_ui: HangarLeftPanel = null
var right_panel_ui: HangarRightPanel = null
# Slot tab buttons keyed by slot id, reused for UI-only selection highlight.
var slot_tab_buttons: Dictionary = {}

# Top-level hangar sub-menu (landing screen): [CUSTOMIZE | EMERGENCY REPAIR |
# UPGRADE | CRAFT | CATALOG]. It is the FIRST thing shown after entering the
# hangar as a long vertical list on the left; each choice opens its own page.
var scrap_editor: CanvasLayer = null
var pilot_loadout_editor: CanvasLayer = null
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
# Pilot roster page (who rides with the convoy): read-mostly list of every
# pilot with live status + the mech they drive. Shares the pilot list source
# with the roster page's pickers and the REGISTER dialog.
var pilots_panel_ui: HangarPilotsPanel = null
# SORTIE page (who tags along into combat): lists every piloted hangar mech
# with a FIELDED/STANDBY toggle driving the pilot's fleet-unit fielded flag.
var sortie_panel_ui: HangarSortiePanel = null
var catalog_panel: HangarCatalogPanel = null
var garage_panel: HangarGaragePanel = null
var craft_panel: HangarCraftPanel = null
# Persistent top banner warning when any parked mech has a wounded fleet pilot
# assigned (recovering drivers never tag into combat until healed).
var wounded_banner: HangarWoundedBanner = null
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
	pilot_loadout_editor = PilotLoadoutEditorScript.new()
	pilot_loadout_editor.controller = self
	pilot_loadout_editor.layer = 20
	add_child(pilot_loadout_editor)
	pilot_loadout_editor.visible = false
	if AudioManager:
		AudioManager.play_hangar_music()


# Returns credits_cost for next frame upgrade level.
# Single source of truth — use this instead of inline calculations.
func _get_upgrade_cost() -> int:
	return GlobalData.get_frame_upgrade_cost()


# --- 2D OVERLAY UI ---
func _build_ui_layout() -> void:
	roster_panel_ui = HangarRosterPanel.new()
	roster_panel_ui.controller = self
	pilots_panel_ui = HangarPilotsPanel.new()
	pilots_panel_ui.controller = self
	sortie_panel_ui = HangarSortiePanel.new()
	sortie_panel_ui.controller = self
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
	readiness_panel = HangarReadinessPanel.new()
	readiness_panel.controller = self
	persist_panel = HangarPersistPanel.new()
	persist_panel.controller = self
	scrap_panel = HangarScrapPanel.new()
	scrap_panel.controller = self
	exit_panel = HangarExitPanel.new()
	exit_panel.controller = self
	refresh_panel = HangarRefreshPanel.new()
	refresh_panel.controller = self
	header_panel = HangarHeaderPanel.new()
	header_panel.controller = self
	left_panel_ui = HangarLeftPanel.new()
	left_panel_ui.controller = self
	right_panel_ui = HangarRightPanel.new()
	right_panel_ui.controller = self
	wounded_banner = HangarWoundedBanner.new()
	wounded_banner.controller = self

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
	# Persistent wounded-pilot banner drawn above every page.
	wounded_banner.build(root)
	# Pilot roster page (who rides with the convoy).
	pilots_panel_ui.build(root)
	# SORTIE page (pick who tags along into combat).
	sortie_panel_ui.build(root)


# --- HANGAR MECH ROSTER (truck-convoy parking page) ---

# Cross-page editing state lives on the controller (_customize_mech_id) because
# the customize page reads/writes the same berth. These accessors are the seam
# the roster panel (HangarRosterPanel) uses; the default is the piloted mech.
func get_editing_mech_id() -> String:
	return _customize_mech_id if _customize_mech_id != "" else GlobalData.active_hangar_mech_id


func set_editing_mech_id(id: String) -> void:
	_customize_mech_id = id


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


# Opens the pilot personal-loadout editor for the given pilot (weapons / ammo /
# items they carry on foot). Hidden behind the scrap-editor gate: while any
# full-screen editor is open the hangar's 3D garage keeps rendering underneath.
func open_pilot_loadout_editor(pilot_id: String, pilot_name: String) -> void:
	if pilot_loadout_editor == null:
		return
	pilot_loadout_editor.open(pilot_id, pilot_name)


# ESC steps BACK one menu level at a time instead of always leaving the
# hangar: full-screen editors close first, then popup windows (craft / catalog /
# action), then an open submenu page returns to the hangar menu, and only at the
# hangar menu root does ESC actually exit to the board.
func _input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("pause") or exit_panel == null:
		return
	# Full-screen modal editors close first.
	if _is_scrap_editor_open():
		scrap_editor.close()
		return
	if pilot_loadout_editor and pilot_loadout_editor.visible:
		pilot_loadout_editor.close()
		return
	# Popup windows close next.
	if craft_panel and craft_panel.craft_window and is_instance_valid(craft_panel.craft_window):
		craft_panel.close_window()
		return
	if catalog_panel and catalog_panel.catalog_window and is_instance_valid(catalog_panel.catalog_window):
		catalog_panel.close_window()
		return
	if action_panel and action_panel.part_action_modal and is_instance_valid(action_panel.part_action_modal):
		action_panel.close()
		return
	# On a submenu page, return to the hangar menu first.
	if nav_panel and nav_panel.current_submenu != "":
		nav_panel.show_hangar_menu()
		return
	# At the hangar menu root, exit to the board.
	exit_panel.close()
