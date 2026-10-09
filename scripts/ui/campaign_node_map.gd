class_name CampaignNodeMap
extends Control

## ---------------------------------------------------------------------------
## STRATEGIC NODE MAP UI & NAVIGATION CONTROLLER — Phase C2.7
##
## Crime Boss: Rockay City & FTL-inspired strategic campaign interface.
## Consumes authoritative strategic systems:
##   - CampaignNodeRegistry: strategic Nodes & explicit Routes
##   - CampaignPlayerMovement: strategic player position and route movement
##   - CampaignNodeInspection: read-only node situation observation
##   - CampaignPlayerDispatch: action intent validation & routing
##   - CampaignTurnExecutive: sole campaign-turn authority
##   - FactionSystem, CampaignTerritory, CampaignBase, CampaignForce
##   - SaveGameIO / GlobalData: persistence & run state
##
## Zero duplicate authorities. Zero tactical grid traversal.
## ---------------------------------------------------------------------------

const CampaignNodeRegistry = preload("res://scripts/systems/campaign_node_registry.gd")
const CampaignPlayerMovement = preload("res://scripts/systems/campaign_player_movement.gd")
const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")
const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")
const CampaignTurnExecutive = preload("res://scripts/systems/campaign_turn_executive.gd")
const CampaignTerritory = preload("res://scripts/systems/campaign_territory.gd")
const CampaignBase = preload("res://scripts/systems/campaign_base.gd")
const CampaignResupplyAction = preload("res://scripts/systems/campaign_resupply_action.gd")
const CampaignTradeAction = preload("res://scripts/systems/campaign_trade_action.gd")

const FONT_SEMIBOLD = preload("res://resources/fonts/ChakraPetch-SemiBold.ttf")
const FONT_MEDIUM = preload("res://resources/fonts/ChakraPetch-Medium.ttf")
const FONT_REGULAR = preload("res://resources/fonts/ChakraPetch-Regular.ttf")

const COLOR_BG = Color(0.05, 0.05, 0.06, 1.0)
const COLOR_PANEL_BG = Color(0.08, 0.09, 0.10, 0.95)
const COLOR_BORDER = Color(0.20, 0.22, 0.25, 1.0)
const COLOR_BORDER_HIGHLIGHT = Color(0.20, 0.70, 0.90, 1.0)
const COLOR_TEXT_MAIN = Color(0.92, 0.94, 0.96, 1.0)
const COLOR_TEXT_MUTED = Color(0.55, 0.58, 0.62, 1.0)
const COLOR_REACHABLE = Color(0.18, 0.75, 0.85, 1.0)
const COLOR_CURRENT_PLAYER = Color(0.95, 0.78, 0.25, 1.0)
const COLOR_UNREACHABLE = Color(0.35, 0.38, 0.42, 1.0)
const COLOR_SUCCESS = Color(0.28, 0.85, 0.45, 1.0)
const COLOR_DANGER = Color(0.90, 0.30, 0.30, 1.0)

var _selected_node_id: String = ""
var _hovered_node_id: String = ""
var _rendered_nodes: Dictionary = {} # node_id -> Dictionary of layout data
var _rendered_routes: Array = [] # list of Dictionary { "a": String, "b": String }
var _node_buttons: Dictionary = {} # node_id -> Button
var _last_action_result: Dictionary = {}

# UI Component References
var _header_scenario_label: Label
var _header_turn_label: Label
var _header_faction_label: Label
var _header_resources_label: Label

var _map_scroll: ScrollContainer
var _map_canvas: Control
var _map_nodes_container: Control

var _info_title: Label
var _info_type: Label
var _info_presence_status: Label
var _info_details_label: Label
var _info_forces_label: Label

var _travel_button: Button
var _actions_container: VBoxContainer
var _feedback_label: Label

var _turn_label: Label
var _end_turn_button: Button
var _turn_status_label: Label


func _ready() -> void:
	_create_ui_structure()
	refresh_map()
	# Auto-select player's current node if available
	var current_node := CampaignPlayerMovement.get_current_node_id()
	if current_node != "" and CampaignNodeRegistry.has_node(current_node):
		select_node(current_node)
	elif not _rendered_nodes.is_empty():
		select_node(str(_rendered_nodes.keys()[0]))


# -----------------------------------------------------------------------------
# UI CONSTRUCTION
# -----------------------------------------------------------------------------
func _create_ui_structure() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Main background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = COLOR_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Root Vertical Layout
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 0)
	add_child(root_vbox)

	# --- TOP HEADER BAR ---
	var header_panel := PanelContainer.new()
	header_panel.custom_minimum_size = Vector2(0, 52)
	var header_style := _create_flat_stylebox(Color(0.07, 0.08, 0.09, 0.98), COLOR_BORDER, 0, 1)
	header_style.content_margin_left = 16
	header_style.content_margin_right = 16
	header_style.content_margin_top = 8
	header_style.content_margin_bottom = 8
	header_panel.add_theme_stylebox_override("panel", header_style)
	root_vbox.add_child(header_panel)

	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 16)
	header_panel.add_child(header_hbox)

	_header_scenario_label = Label.new()
	_header_scenario_label.text = "STRATEGIC OPERATIONS MAP"
	_header_scenario_label.add_theme_font_override("font", FONT_SEMIBOLD)
	_header_scenario_label.add_theme_font_size_override("font_size", 16)
	_header_scenario_label.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	header_hbox.add_child(_header_scenario_label)

	_header_turn_label = Label.new()
	_header_turn_label.text = "TURN: 1"
	_header_turn_label.add_theme_font_override("font", FONT_MEDIUM)
	_header_turn_label.add_theme_font_size_override("font_size", 13)
	_header_turn_label.add_theme_color_override("font_color", COLOR_REACHABLE)
	header_hbox.add_child(_header_turn_label)

	_header_faction_label = Label.new()
	_header_faction_label.text = "FACTION: FEDERATION"
	_header_faction_label.add_theme_font_override("font", FONT_MEDIUM)
	_header_faction_label.add_theme_font_size_override("font_size", 12)
	_header_faction_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	header_hbox.add_child(_header_faction_label)

	_header_resources_label = Label.new()
	_header_resources_label.text = "CREDITS: 0 | SCRAP: 0 | CORES: 0"
	_header_resources_label.add_theme_font_override("font", FONT_MEDIUM)
	_header_resources_label.add_theme_font_size_override("font_size", 12)
	_header_resources_label.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	_header_resources_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_resources_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_hbox.add_child(_header_resources_label)

	var save_btn := _create_button("SAVE", false, false, Vector2(70, 32))
	save_btn.pressed.connect(_on_save_pressed)
	header_hbox.add_child(save_btn)

	var hangar_btn := _create_button("HANGAR", false, false, Vector2(80, 32))
	hangar_btn.pressed.connect(_on_hangar_pressed)
	header_hbox.add_child(hangar_btn)

	var menu_btn := _create_button("MAIN MENU", false, true, Vector2(90, 32))
	menu_btn.pressed.connect(_on_menu_pressed)
	header_hbox.add_child(menu_btn)

	# --- MAIN WORKSPACE AREA (MAP CANVAS + RIGHT SIDEBAR) ---
	var workspace_hbox := HBoxContainer.new()
	workspace_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace_hbox.add_theme_constant_override("separation", 0)
	root_vbox.add_child(workspace_hbox)

	# Left/Center: Interactive Map Canvas Container
	var map_container := PanelContainer.new()
	map_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var map_bg_style := _create_flat_stylebox(Color(0.04, 0.04, 0.05, 1.0), COLOR_BORDER, 0, 1)
	map_container.add_theme_stylebox_override("panel", map_bg_style)
	workspace_hbox.add_child(map_container)

	_map_scroll = ScrollContainer.new()
	_map_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_container.add_child(_map_scroll)

	_map_canvas = Control.new()
	_map_canvas.custom_minimum_size = Vector2(950, 680)
	_map_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_map_canvas.draw.connect(_on_map_canvas_draw)
	_map_scroll.add_child(_map_canvas)

	_map_nodes_container = Control.new()
	_map_nodes_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_nodes_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_canvas.add_child(_map_nodes_container)

	# Right: Information & Action Dock
	var sidebar_panel := PanelContainer.new()
	sidebar_panel.custom_minimum_size = Vector2(350, 0)
	sidebar_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sidebar_style := _create_flat_stylebox(COLOR_PANEL_BG, COLOR_BORDER, 0, 1)
	sidebar_style.content_margin_left = 18
	sidebar_style.content_margin_right = 18
	sidebar_style.content_margin_top = 16
	sidebar_style.content_margin_bottom = 16
	sidebar_panel.add_theme_stylebox_override("panel", sidebar_style)
	workspace_hbox.add_child(sidebar_panel)

	var sidebar_scroll := ScrollContainer.new()
	sidebar_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar_panel.add_child(sidebar_scroll)

	var sidebar_vbox := VBoxContainer.new()
	sidebar_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar_vbox.add_theme_constant_override("separation", 12)
	sidebar_scroll.add_child(sidebar_vbox)

	# --- Sidebar Section 1: Selected Node Header & Situation ---
	var sec1_label := Label.new()
	sec1_label.text = "LOCATION INTELLIGENCE"
	sec1_label.add_theme_font_override("font", FONT_SEMIBOLD)
	sec1_label.add_theme_font_size_override("font_size", 11)
	sec1_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	sidebar_vbox.add_child(sec1_label)

	_info_title = Label.new()
	_info_title.text = "NO SELECTION"
	_info_title.add_theme_font_override("font", FONT_SEMIBOLD)
	_info_title.add_theme_font_size_override("font_size", 18)
	_info_title.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	sidebar_vbox.add_child(_info_title)

	_info_type = Label.new()
	_info_type.text = "TYPE: -- // SECTOR: --"
	_info_type.add_theme_font_override("font", FONT_MEDIUM)
	_info_type.add_theme_font_size_override("font_size", 12)
	_info_type.add_theme_color_override("font_color", COLOR_REACHABLE)
	sidebar_vbox.add_child(_info_type)

	_info_presence_status = Label.new()
	_info_presence_status.text = "STATUS: --"
	_info_presence_status.add_theme_font_override("font", FONT_MEDIUM)
	_info_presence_status.add_theme_font_size_override("font_size", 12)
	_info_presence_status.add_theme_color_override("font_color", COLOR_CURRENT_PLAYER)
	sidebar_vbox.add_child(_info_presence_status)

	_info_details_label = Label.new()
	_info_details_label.text = "Territory: --\nBase: --"
	_info_details_label.add_theme_font_override("font", FONT_REGULAR)
	_info_details_label.add_theme_font_size_override("font_size", 11)
	_info_details_label.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	sidebar_vbox.add_child(_info_details_label)

	_info_forces_label = Label.new()
	_info_forces_label.text = "Forces: none"
	_info_forces_label.add_theme_font_override("font", FONT_REGULAR)
	_info_forces_label.add_theme_font_size_override("font_size", 11)
	_info_forces_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	_info_forces_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar_vbox.add_child(_info_forces_label)

	sidebar_vbox.add_child(_create_separator())

	# --- Sidebar Section 2: Strategic Navigation & Actions ---
	var sec2_label := Label.new()
	sec2_label.text = "STRATEGIC OPERATIONS"
	sec2_label.add_theme_font_override("font", FONT_SEMIBOLD)
	sec2_label.add_theme_font_size_override("font_size", 11)
	sec2_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	sidebar_vbox.add_child(sec2_label)

	_travel_button = _create_button("TRAVEL TO NODE", true, false, Vector2(0, 36))
	_travel_button.pressed.connect(_on_travel_pressed)
	sidebar_vbox.add_child(_travel_button)

	_actions_container = VBoxContainer.new()
	_actions_container.add_theme_constant_override("separation", 6)
	sidebar_vbox.add_child(_actions_container)

	_feedback_label = Label.new()
	_feedback_label.text = "Ready"
	_feedback_label.add_theme_font_override("font", FONT_REGULAR)
	_feedback_label.add_theme_font_size_override("font_size", 11)
	_feedback_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar_vbox.add_child(_feedback_label)

	sidebar_vbox.add_child(_create_separator())

	# --- Sidebar Section 3: Campaign Turn Progression ---
	var sec3_label := Label.new()
	sec3_label.text = "CAMPAIGN SIMULATION"
	sec3_label.add_theme_font_override("font", FONT_SEMIBOLD)
	sec3_label.add_theme_font_size_override("font_size", 11)
	sec3_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	sidebar_vbox.add_child(sec3_label)

	_turn_label = Label.new()
	_turn_label.text = "Turn: 1"
	_turn_label.add_theme_font_override("font", FONT_MEDIUM)
	_turn_label.add_theme_font_size_override("font_size", 13)
	_turn_label.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	sidebar_vbox.add_child(_turn_label)

	_end_turn_button = _create_button("END CAMPAIGN TURN", false, false, Vector2(0, 36))
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	sidebar_vbox.add_child(_end_turn_button)

	_turn_status_label = Label.new()
	_turn_status_label.text = "Turn ready."
	_turn_status_label.add_theme_font_override("font", FONT_REGULAR)
	_turn_status_label.add_theme_font_size_override("font_size", 10)
	_turn_status_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	_turn_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar_vbox.add_child(_turn_status_label)


# -----------------------------------------------------------------------------
# STRATEGIC MAP RENDERING & TOPOLOGY SYNCHRONIZATION
# -----------------------------------------------------------------------------
func refresh_map() -> void:
	_update_header()
	_rebuild_node_widgets()
	_rebuild_routes_data()
	if _map_canvas:
		_map_canvas.queue_redraw()
	_update_info_panel()


func _update_header() -> void:
	if _header_scenario_label:
		var s_id := GlobalData.current_campaign_scenario_id if GlobalData else ""
		_header_scenario_label.text = "SCENARIO: %s" % (s_id.to_upper() if s_id != "" else "TACTICAL CAMPAIGN")
	if _header_turn_label:
		_header_turn_label.text = "TURN: %d" % CampaignTurnExecutive.get_turn()
	if _header_faction_label:
		var f_id := GlobalData.current_campaign_faction_id if GlobalData else ""
		_header_faction_label.text = "FACTION: %s" % (f_id.to_upper() if f_id != "" else "FEDERATION")
	if _header_resources_label:
		var creds := int(GlobalData.currency.credits) if (GlobalData and GlobalData.currency) else 0
		var scrap := int(GlobalData.currency.scrap) if (GlobalData and GlobalData.currency) else 0
		var cores := int(GlobalData.currency.data_cores) if (GlobalData and GlobalData.currency) else 0
		var fuel_cur := int(GlobalData.fuel.convoy_fuel) if (GlobalData and GlobalData.fuel) else 0
		var fuel_max := int(GlobalData.fuel.convoy_max_fuel) if (GlobalData and GlobalData.fuel) else 0
		_header_resources_label.text = "CREDITS: %d | SCRAP: %d | CORES: %d | FUEL: %d/%d" % [
			creds, scrap, cores, fuel_cur, fuel_max
		]


func _rebuild_node_widgets() -> void:
	if not _map_nodes_container:
		return

	# Clear previous node widgets
	for child in _map_nodes_container.get_children():
		child.queue_free()
	_rendered_nodes.clear()
	_node_buttons.clear()

	var nodes := CampaignNodeRegistry.get_nodes()
	var total_nodes := nodes.size()
	var player_node_id := CampaignPlayerMovement.get_current_node_id()

	for i in total_nodes:
		var node_data: Dictionary = nodes[i]
		var node_id := str(node_data.get("id", ""))
		if node_id == "":
			continue

		# Resolve map position or fallback
		var pos := _resolve_node_position(node_data, i, total_nodes)
		_rendered_nodes[node_id] = {
			"id": node_id,
			"node_type": str(node_data.get("node_type", "")),
			"sector": int(node_data.get("sector", 1)),
			"position": pos,
			"data": node_data,
		}

		# Create node UI button
		var btn := _create_node_button(node_id, _rendered_nodes[node_id], player_node_id)
		btn.position = pos - btn.custom_minimum_size * 0.5
		_map_nodes_container.add_child(btn)
		_node_buttons[node_id] = btn


func _resolve_node_position(node_data: Dictionary, index: int, total: int) -> Vector2:
	var raw_pos = node_data.get("map_position", Vector2(-1, -1))
	if raw_pos is Vector2 and raw_pos.x >= 0 and raw_pos.y >= 0 and raw_pos != Vector2.ZERO:
		return raw_pos

	# Deterministic layout fallback: distribute across comfortable canvas space
	return calculate_fallback_position(index, total, int(node_data.get("sector", 1)))


static func calculate_fallback_position(index: int, total: int, sector: int = 1, bounds: Rect2 = Rect2(120, 100, 700, 480)) -> Vector2:
	if total <= 1:
		return bounds.position + bounds.size * 0.5
	var step_x := bounds.size.x / maxf(1.0, float(total - 1))
	var x := bounds.position.x + float(index) * step_x
	var wave := sin(float(index) * 1.2) * (bounds.size.y * 0.22)
	var y := bounds.position.y + bounds.size.y * 0.5 + wave
	return Vector2(round(x), round(y))


func _create_node_button(node_id: String, layout_info: Dictionary, player_node_id: String) -> Button:
	var btn := Button.new()
	btn.name = "NodeBtn_%s" % node_id
	btn.custom_minimum_size = Vector2(130, 48)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	var is_player_here := (node_id == player_node_id)
	var is_reachable := is_node_reachable(node_id)
	var is_selected := (node_id == _selected_node_id)

	var node_type := str(layout_info.get("node_type", "")).to_upper()
	var short_name := node_id.replace("node_frontier_", "").replace("node_", "").to_upper()

	var prefix := ""
	if is_player_here:
		prefix = "★ "
	elif is_reachable:
		prefix = "► "

	btn.text = "%s%s\n[%s]" % [prefix, short_name, node_type]
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Styling
	var bg_col := Color(0.10, 0.12, 0.14, 0.95)
	var border_col := COLOR_BORDER
	var text_col := COLOR_TEXT_MAIN

	if is_player_here:
		bg_col = Color(0.18, 0.15, 0.08, 0.98)
		border_col = COLOR_CURRENT_PLAYER
		text_col = COLOR_CURRENT_PLAYER
	elif is_selected:
		bg_col = Color(0.12, 0.18, 0.22, 0.98)
		border_col = COLOR_BORDER_HIGHLIGHT
		text_col = COLOR_TEXT_MAIN
	elif is_reachable:
		bg_col = Color(0.08, 0.16, 0.18, 0.95)
		border_col = COLOR_REACHABLE
		text_col = COLOR_REACHABLE

	var normal_style := _create_flat_stylebox(bg_col, border_col, 0, 2 if (is_player_here or is_selected) else 1)
	var hover_style := _create_flat_stylebox(bg_col.lightened(0.12), COLOR_BORDER_HIGHLIGHT, 0, 2)
	var pressed_style := _create_flat_stylebox(bg_col.lightened(0.20), COLOR_BORDER_HIGHLIGHT, 0, 2)

	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	btn.add_theme_font_override("font", FONT_MEDIUM)
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_color_override("font_color", text_col)

	btn.pressed.connect(_on_node_clicked.bind(node_id))
	btn.mouse_entered.connect(_on_node_hovered.bind(node_id))
	btn.mouse_exited.connect(_on_node_unhovered.bind(node_id))

	return btn


func _rebuild_routes_data() -> void:
	_rendered_routes.clear()
	var raw_routes := CampaignNodeRegistry.get_routes()
	var seen: Dictionary = {}

	for r in raw_routes:
		var a := str(r.get("a", ""))
		var b := str(r.get("b", ""))
		if a == "" or b == "" or a == b:
			continue
		var key := "%s<->%s" % [a, b] if a < b else "%s<->%s" % [b, a]
		if not seen.has(key):
			seen[key] = true
			_rendered_routes.append({ "a": a, "b": b })


func _on_map_canvas_draw() -> void:
	if not _map_canvas:
		return

	var player_node_id := CampaignPlayerMovement.get_current_node_id()

	# Draw Route Connections
	for r in _rendered_routes:
		var a_id := str(r.get("a", ""))
		var b_id := str(r.get("b", ""))
		if not _rendered_nodes.has(a_id) or not _rendered_nodes.has(b_id):
			continue

		var pos_a: Vector2 = _rendered_nodes[a_id]["position"]
		var pos_b: Vector2 = _rendered_nodes[b_id]["position"]

		var is_connected_to_player := (a_id == player_node_id or b_id == player_node_id)
		var is_selected_route := (is_connected_to_player and (a_id == _selected_node_id or b_id == _selected_node_id))

		var line_color := Color(0.20, 0.23, 0.28, 0.8)
		var line_width := 2.0

		if is_selected_route:
			line_color = Color(0.35, 0.95, 1.0, 1.0)
			line_width = 4.0
		elif is_connected_to_player:
			line_color = COLOR_REACHABLE
			line_width = 3.0

		_map_canvas.draw_line(pos_a, pos_b, line_color, line_width, true)

		# Midpoint waypoint indicator
		var mid := (pos_a + pos_b) * 0.5
		_map_canvas.draw_circle(mid, 3.0, line_color)


# -----------------------------------------------------------------------------
# SELECTION, INSPECTION & INFORMATION DOCK
# -----------------------------------------------------------------------------
func select_node(node_id: String) -> void:
	if node_id == "" or not CampaignNodeRegistry.has_node(node_id):
		return
	_selected_node_id = node_id
	_rebuild_node_widgets()
	if _map_canvas:
		_map_canvas.queue_redraw()
	_update_info_panel()


func get_selected_node_id() -> String:
	return _selected_node_id


func get_rendered_nodes() -> Array:
	return _rendered_nodes.keys()


func get_rendered_routes() -> Array:
	return _rendered_routes.duplicate(true)


func is_node_reachable(node_id: String) -> bool:
	if node_id == "":
		return false
	var player_node_id := CampaignPlayerMovement.get_current_node_id()
	if player_node_id == "" or player_node_id == node_id:
		return false
	return CampaignNodeRegistry.has_route(CampaignNodeRegistry.make_route_id(player_node_id, node_id))


func _update_info_panel() -> void:
	if _selected_node_id == "" or not CampaignNodeRegistry.has_node(_selected_node_id):
		_clear_info_panel()
		return

	var inspection := CampaignNodeInspection.inspect_node(_selected_node_id)
	if not bool(inspection.get("ok", false)):
		_clear_info_panel()
		return

	var node: Dictionary = inspection.get("node", {})
	var node_type := str(node.get("node_type", "")).to_upper()
	var sector := int(node.get("sector", 1))
	var player_node_id := CampaignPlayerMovement.get_current_node_id()
	var is_player_here := (_selected_node_id == player_node_id)
	var is_reachable := is_node_reachable(_selected_node_id)

	_info_title.text = _selected_node_id.replace("node_frontier_", "").replace("node_", "").to_upper()
	_info_type.text = "TYPE: %s // SECTOR: %d" % [node_type, sector]

	if is_player_here:
		_info_presence_status.text = "STATUS: ★ CURRENT PLAYER LOCATION"
		_info_presence_status.add_theme_color_override("font_color", COLOR_CURRENT_PLAYER)
	elif is_reachable:
		_info_presence_status.text = "STATUS: ► REACHABLE (1 ROUTE HOP)"
		_info_presence_status.add_theme_color_override("font_color", COLOR_REACHABLE)
	else:
		_info_presence_status.text = "STATUS: ✖ UNREACHABLE (NO DIRECT ROUTE)"
		_info_presence_status.add_theme_color_override("font_color", COLOR_UNREACHABLE)

	# Territory & Base details
	var terr: Dictionary = inspection.get("territory", {})
	var base: Dictionary = inspection.get("base", {})
	var details_text := ""
	if not terr.is_empty():
		details_text += "Territory: %s (Control: %s, Controller: %s)\n" % [
			str(terr.get("id", "")),
			CampaignTerritory.control_to_name(int(terr.get("control", 0))),
			str(terr.get("controller", "none")).to_upper()
		]
	else:
		details_text += "Territory: Unclaimed\n"

	if not base.is_empty():
		details_text += "Base: %s [%s] (Controller: %s)" % [
			str(base.get("id", "")),
			str(base.get("base_type", "")),
			str(base.get("controller", "none")).to_upper()
		]
	else:
		details_text += "Base: None"

	_info_details_label.text = details_text

	# Forces details
	var forces: Array = inspection.get("forces", [])
	if forces.is_empty():
		_info_forces_label.text = "Forces: none present"
	else:
		var f_lines: Array = []
		for f in forces:
			f_lines.append("• %s [%s] Faction: %s | Units: %s | Str: %s" % [
				str(f.get("slug", f.get("id", ""))),
				str(f.get("force_type", "")),
				str(f.get("faction", "")).to_upper(),
				str(f.get("unit_count", "0")),
				str(f.get("strength", "0"))
			])
		_info_forces_label.text = "\n".join(f_lines)

	# Update Movement & Contextual Action Buttons
	_update_action_buttons(is_player_here, is_reachable, node_type, inspection)


func _clear_info_panel() -> void:
	_info_title.text = "NO SELECTION"
	_info_type.text = "TYPE: -- // SECTOR: --"
	_info_presence_status.text = "STATUS: --"
	_info_details_label.text = "Territory: --\nBase: --"
	_info_forces_label.text = "Forces: none"
	_travel_button.visible = false
	for child in _actions_container.get_children():
		child.queue_free()


func _update_action_buttons(is_player_here: bool, is_reachable: bool, node_type: String, inspection: Dictionary) -> void:
	# Travel button: enabled only when reachable and not currently at the node
	_travel_button.visible = is_reachable and not is_player_here
	_travel_button.disabled = not is_reachable

	# Clear previous contextual action buttons
	for child in _actions_container.get_children():
		child.queue_free()

	if not is_player_here:
		return

	# Player is at this node: expose authoritative campaign actions
	# 1. Investigate (Always available at current node)
	var inv_btn := _create_button("INVESTIGATE LOCATION", false, false, Vector2(0, 32))
	inv_btn.pressed.connect(_on_action_investigate_pressed)
	_actions_container.add_child(inv_btn)

	# 2. Resupply (if valid resupply node type)
	if CampaignResupplyAction.is_resupply_node_type(node_type):
		var resupply_btn := _create_button("RESUPPLY CONVOY / MECHA", false, false, Vector2(0, 32))
		resupply_btn.pressed.connect(_on_action_resupply_pressed)
		_actions_container.add_child(resupply_btn)

	# 3. Trade (if valid trade node type)
	if CampaignTradeAction.is_trade_node_type(node_type):
		var trade_btn := _create_button("TRADE SUPPLIES", false, false, Vector2(0, 32))
		trade_btn.pressed.connect(_on_action_trade_pressed)
		_actions_container.add_child(trade_btn)

	# 4. Capture (if hostile/neutral base present)
	var base: Dictionary = inspection.get("base", {})
	if not base.is_empty() and str(base.get("controller", "")) != GlobalData.current_campaign_faction_id:
		var capture_btn := _create_button("CAPTURE BASE", false, false, Vector2(0, 32))
		capture_btn.pressed.connect(_on_action_capture_pressed)
		_actions_container.add_child(capture_btn)

	# 5. Attack (if hostile forces present)
	var forces: Array = inspection.get("forces", [])
	var has_hostiles := false
	for f in forces:
		if str(f.get("faction", "")) != GlobalData.current_campaign_faction_id:
			has_hostiles = true
			break
	if has_hostiles:
		var attack_btn := _create_button("ENGAGE ENEMY FORCES", false, false, Vector2(0, 32))
		attack_btn.pressed.connect(_on_action_attack_pressed)
		_actions_container.add_child(attack_btn)


# -----------------------------------------------------------------------------
# STRATEGIC MOVEMENT & ACTION EXECUTION
# -----------------------------------------------------------------------------
func travel_to_node(destination_node_id: String) -> Dictionary:
	var cur := CampaignPlayerMovement.get_current_node_id()
	if destination_node_id == cur:
		var fail_res := {
			"ok": false,
			"changed": false,
			"from_node_id": cur,
			"to_node_id": destination_node_id,
			"reason": "already_at_node"
		}
		if _feedback_label:
			_feedback_label.text = "Already at %s" % destination_node_id
			_feedback_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
		return fail_res

	var receipt := CampaignPlayerMovement.move_player_to_node(destination_node_id)
	if bool(receipt.get("ok", false)) and bool(receipt.get("changed", false)):
		if _feedback_label:
			_feedback_label.text = "Traveled to %s" % destination_node_id
			_feedback_label.add_theme_color_override("font_color", COLOR_SUCCESS)
		select_node(destination_node_id)
		refresh_map()
		if GlobalData:
			GlobalData.save_run()
		return receipt
	else:
		var reason := str(receipt.get("reason", "failed"))
		if _feedback_label:
			_feedback_label.text = "Travel rejected: %s" % reason
			_feedback_label.add_theme_color_override("font_color", COLOR_DANGER)
		return {
			"ok": false,
			"changed": false,
			"from_node_id": cur,
			"to_node_id": destination_node_id,
			"reason": reason
		}


func dispatch_node_action(action_id: String, payload: Dictionary = {}) -> Dictionary:
	var intent := CampaignPlayerDispatch.create_intent(action_id, _selected_node_id, payload)
	var result := CampaignPlayerDispatch.dispatch_intent(intent)
	_last_action_result = result.duplicate(true)

	if bool(result.get("ok", false)):
		var reason := str(result.get("reason", "success"))
		_feedback_label.text = "Action '%s' succeeded: %s" % [action_id.to_upper(), reason]
		_feedback_label.add_theme_color_override("font_color", COLOR_SUCCESS)
		refresh_map()
	else:
		var reason := str(result.get("reason", "failed"))
		_feedback_label.text = "Action '%s' rejected: %s" % [action_id.to_upper(), reason]
		_feedback_label.add_theme_color_override("font_color", COLOR_DANGER)

	return result


func advance_turn() -> Dictionary:
	var receipt := CampaignTurnExecutive.advance_campaign_turn("player_end_turn")
	if bool(receipt.get("ok", false)):
		_turn_status_label.text = "Turn %d completed successfully." % int(receipt.get("turn", 0))
		_turn_status_label.add_theme_color_override("font_color", COLOR_SUCCESS)
	else:
		_turn_status_label.text = "Turn advance rejected: %s" % str(receipt.get("error", "failed"))
		_turn_status_label.add_theme_color_override("font_color", COLOR_DANGER)
	refresh_map()
	GlobalData.save_run()
	return receipt


func _on_action_investigate_pressed() -> void:
	dispatch_node_action("investigate")


func _on_action_resupply_pressed() -> void:
	dispatch_node_action("resupply")


func _on_action_trade_pressed() -> void:
	dispatch_node_action("trade", { "operation": "buy", "item_id": "fuel_canister", "quantity": 1 })


func _on_action_capture_pressed() -> void:
	dispatch_node_action("capture")


func _on_action_attack_pressed() -> void:
	dispatch_node_action("attack")


func _on_node_clicked(node_id: String) -> void:
	select_node(node_id)


func _on_node_hovered(node_id: String) -> void:
	_hovered_node_id = node_id
	if _map_canvas:
		_map_canvas.queue_redraw()


func _on_node_unhovered(node_id: String) -> void:
	if _hovered_node_id == node_id:
		_hovered_node_id = ""
		if _map_canvas:
			_map_canvas.queue_redraw()


func _on_travel_pressed() -> void:
	if _selected_node_id != "":
		travel_to_node(_selected_node_id)


func _on_end_turn_pressed() -> void:
	advance_turn()


func _on_save_pressed() -> void:
	var ok := GlobalData.save_run()
	if ok:
		_feedback_label.text = "Campaign saved successfully."
		_feedback_label.add_theme_color_override("font_color", COLOR_SUCCESS)
	else:
		_feedback_label.text = "Failed to save campaign."
		_feedback_label.add_theme_color_override("font_color", COLOR_DANGER)


func _on_hangar_pressed() -> void:
	GlobalData.save_run()
	GameManager.enter_hangar()


func _on_menu_pressed() -> void:
	GlobalData.save_run()
	GameManager.return_to_menu()


# -----------------------------------------------------------------------------
# UI STYLE HELPERS
# -----------------------------------------------------------------------------
func _create_button(text: String, is_primary: bool = false, is_ghost: bool = false, min_size: Vector2 = Vector2.ZERO) -> Button:
	var btn := Button.new()
	btn.text = text
	if min_size != Vector2.ZERO:
		btn.custom_minimum_size = min_size
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER

	var bg := Color(0.10, 0.11, 0.12, 1.0)
	var border := COLOR_BORDER
	var text_col := COLOR_TEXT_MAIN

	if is_primary:
		bg = Color(0.12, 0.22, 0.28, 1.0)
		border = COLOR_REACHABLE
		text_col = Color(0.95, 0.98, 1.0, 1.0)
	elif is_ghost:
		bg = Color(0, 0, 0, 0)
		border = Color(0, 0, 0, 0)
		text_col = COLOR_TEXT_MUTED

	var normal := _create_flat_stylebox(bg, border, 0, 1)
	var hover := _create_flat_stylebox(bg.lightened(0.15) if not is_ghost else Color(0.15, 0.15, 0.15, 1.0), COLOR_BORDER_HIGHLIGHT, 0, 1)
	var pressed := _create_flat_stylebox(bg.lightened(0.25), COLOR_BORDER_HIGHLIGHT, 0, 1)
	var disabled := _create_flat_stylebox(Color(0.06, 0.06, 0.06, 1.0), Color(0.12, 0.12, 0.12, 1.0), 0, 1)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	btn.add_theme_font_override("font", FONT_MEDIUM)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", text_col)

	return btn


func _create_flat_stylebox(bg_color: Color, border_color: Color, corner_radius: int = 0, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _create_separator() -> HSeparator:
	var sep := HSeparator.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.18, 0.20, 0.22, 1.0)
	s.border_width_top = 1
	s.border_color = Color(0.18, 0.20, 0.22, 1.0)
	sep.add_theme_stylebox_override("separator", s)
	return sep
