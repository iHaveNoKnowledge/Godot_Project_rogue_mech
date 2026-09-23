extends CanvasLayer

## ResearchLabUI: a board node that lets the player browse and start research
## projects. Features two tabs:
## 1. FLEET BLUEPRINTS (Micro manufacturing & unit unlocks)
## 2. TECHNOLOGY DISCOVERY (Macro scientific lineage & discovery lifecycle)

const TechSys = preload("res://scripts/systems/technology_system.gd")

var root_control: Control
var panel: PanelContainer
var title_label: Label
var tab_container: HBoxContainer
var tab_blueprints_btn: Button
var tab_tech_btn: Button

# --- Tab 1: Blueprints View ---
var blueprints_view: VBoxContainer
var info_label: Label
var active_container: VBoxContainer
var projects_container: VBoxContainer

# --- Tab 2: Technology Discovery View ---
var tech_discovery_view: VBoxContainer
var tech_info_label: Label
var tech_projects_container: VBoxContainer

var current_tab: String = "blueprints" # "blueprints" or "tech_discovery"

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
	panel.offset_left = -340
	panel.offset_right = 340
	panel.offset_top = -340
	panel.offset_bottom = 340
	root_control.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.16, 0.96)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.5, 0.7, 0.5)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	title_label = Label.new()
	title_label.text = "RESEARCH LAB & TECHNOLOGY ARCHIVE"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	vbox.add_child(title_label)

	# --- Tab Bar ---
	tab_container = HBoxContainer.new()
	tab_container.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_container.add_theme_constant_override("separation", 10)
	vbox.add_child(tab_container)

	tab_blueprints_btn = Button.new()
	tab_blueprints_btn.text = "[ ⚙ FLEET BLUEPRINTS ]"
	tab_blueprints_btn.custom_minimum_size = Vector2(240, 32)
	tab_blueprints_btn.pressed.connect(_switch_tab.bind("blueprints"))
	tab_container.add_child(tab_blueprints_btn)

	tab_tech_btn = Button.new()
	tab_tech_btn.text = "[ 🔬 TECHNOLOGY DISCOVERY ]"
	tab_tech_btn.custom_minimum_size = Vector2(240, 32)
	tab_tech_btn.pressed.connect(_switch_tab.bind("tech_discovery"))
	tab_container.add_child(tab_tech_btn)

	var separator = HSeparator.new()
	vbox.add_child(separator)

	# --- View 1: Blueprints View ---
	blueprints_view = VBoxContainer.new()
	blueprints_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	blueprints_view.add_theme_constant_override("separation", 6)
	vbox.add_child(blueprints_view)

	info_label = Label.new()
	info_label.text = ""
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", 12)
	info_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	blueprints_view.add_child(info_label)

	var active_label = Label.new()
	active_label.text = "ACTIVE MANUFACTURING RESEARCH"
	active_label.add_theme_font_size_override("font_size", 13)
	active_label.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5))
	blueprints_view.add_child(active_label)

	active_container = VBoxContainer.new()
	active_container.add_theme_constant_override("separation", 4)
	blueprints_view.add_child(active_container)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	blueprints_view.add_child(scroll)

	projects_container = VBoxContainer.new()
	projects_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	projects_container.add_theme_constant_override("separation", 4)
	scroll.add_child(projects_container)

	# --- View 2: Technology Discovery View ---
	tech_discovery_view = VBoxContainer.new()
	tech_discovery_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tech_discovery_view.add_theme_constant_override("separation", 6)
	tech_discovery_view.visible = false
	vbox.add_child(tech_discovery_view)

	tech_info_label = Label.new()
	tech_info_label.text = ""
	tech_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tech_info_label.add_theme_font_size_override("font_size", 12)
	tech_info_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	tech_discovery_view.add_child(tech_info_label)

	var tech_scroll = ScrollContainer.new()
	tech_scroll.custom_minimum_size = Vector2(640, 240)
	tech_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tech_discovery_view.add_child(tech_scroll)

	tech_projects_container = VBoxContainer.new()
	tech_projects_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tech_projects_container.add_theme_constant_override("separation", 6)
	tech_scroll.add_child(tech_projects_container)

	# --- Footer Controls ---
	leave_button = Button.new()
	leave_button.text = "Leave Lab"
	leave_button.custom_minimum_size = Vector2(640, 34)
	leave_button.pressed.connect(_on_leave_pressed)
	vbox.add_child(leave_button)

	status_label = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	vbox.add_child(status_label)

	_update_tab_buttons()


func _switch_tab(tab_name: String) -> void:
	current_tab = tab_name
	_update_tab_buttons()
	_refresh()


func _update_tab_buttons() -> void:
	if tab_blueprints_btn == null or tab_tech_btn == null:
		return
	var is_bp := (current_tab == "blueprints")
	blueprints_view.visible = is_bp
	tech_discovery_view.visible = not is_bp

	tab_blueprints_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0) if is_bp else Color(0.6, 0.65, 0.7))
	tab_tech_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0) if not is_bp else Color(0.6, 0.65, 0.7))


func _on_tile_entered(pos: Vector2i, _data: Node) -> void:
	var tile_type := _get_tile_type(pos)
	if tile_type == "research_lab":
		visible = true
		_refresh()
		get_tree().paused = true


func _get_tile_type(pos: Vector2i) -> String:
	var scene = get_tree().current_scene
	if scene and scene.has_method("get_tile_type"):
		return scene.get_tile_type(pos)
	return "empty"


func _refresh() -> void:
	if TechSys:
		TechSys.init_catalog_if_needed()

	if current_tab == "blueprints":
		_refresh_blueprints_tab()
	else:
		_refresh_tech_discovery_tab()


func _refresh_blueprints_tab() -> void:
	var total_cores := GlobalData.currency.data_cores
	info_label.text = "Data Cores: %d  |  Start a manufacturing project to unlock units and weapons." % total_cores

	# --- Active research ---
	for child in active_container.get_children():
		child.queue_free()

	var has_active := false
	for project_id in GlobalData.hangar.research_projects:
		var state = GlobalData.hangar.research_projects[project_id]
		if not (state is Dictionary):
			continue
		has_active = true
		var progress: int = int(state.get("progress", 0))
		var required: int = int(state.get("required", 1))
		var project := FleetSystem.get_research_project(project_id)
		var name: String = str(project.get("name", project_id))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text = "%s: %d / %d" % [name, progress, required]
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		active_container.add_child(row)

	if not has_active:
		var empty_lbl := Label.new()
		empty_lbl.text = "No active manufacturing research."
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		active_container.add_child(empty_lbl)

	# --- Available projects ---
	for child in projects_container.get_children():
		child.queue_free()

	var available_count := 0
	for project in GlobalData.research_blueprints:
		if not (project is Dictionary):
			continue
		var pid: String = str(project.get("id", ""))
		if pid == "":
			continue
		# Skip already completed or active projects.
		if FleetSystem.is_research_completed(pid) or FleetSystem.is_research_active(pid):
			continue
		available_count += 1
		var pname: String = str(project.get("name", pid))
		var pdesc: String = str(project.get("desc", ""))
		var cost: int = int(project.get("data_cores", 1))
		var time: int = int(project.get("research_time", 6))
		var reward_type: String = str(project.get("reward_type", ""))
		var reward_name: String = str(project.get("reward_name", project.get("reward_id", "")))

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(620, 46)
		btn.text = "%s  [%d cores, %d turns]  → %s: %s" % [pname, cost, time, reward_type.capitalize(), reward_name]
		btn.tooltip_text = pdesc
		btn.disabled = GlobalData.currency.data_cores < cost
		btn.pressed.connect(_on_start_research.bind(pid))
		projects_container.add_child(btn)

	if available_count == 0:
		var done_lbl := Label.new()
		done_lbl.text = "All blueprint projects completed or in progress."
		done_lbl.add_theme_font_size_override("font_size", 11)
		done_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		projects_container.add_child(done_lbl)

	status_label.text = "Data Cores: %d | Credits: %d" % [GlobalData.currency.data_cores, GlobalData.currency.credits]


func _refresh_tech_discovery_tab() -> void:
	for child in tech_projects_container.get_children():
		child.queue_free()

	var active_tech := TechSys.get_active_research_project()
	var active_text := "Active Scientific Project: %s" % (TechSys.get_technology_definition(active_tech).get("name", active_tech) if active_tech != "" else "None")
	tech_info_label.text = "Macro Technology Lineages | %s" % active_text

	var all_techs := TechSys.get_all_technologies()
	# Sort technologies by generation then family
	all_techs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var gen_a: int = int(a.get("generation", 1))
		var gen_b: int = int(b.get("generation", 1))
		if gen_a != gen_b:
			return gen_a < gen_b
		return str(a.get("technology_family", "")) < str(b.get("technology_family", ""))
	)

	for def in all_techs:
		var tid: String = str(def.get("tech_id", ""))
		var state: int = TechSys.get_discovery_state(tid)
		var state_name: String = TechSys.get_discovery_state_name(tid)
		var gen: int = int(def.get("generation", 1))
		var fam: String = str(def.get("technology_family", "ballistic")).capitalize()

		var is_unknown := (state == TechSys.DiscoveryState.UNKNOWN)
		var display_name: String = "??? [Undiscovered Technology]" if is_unknown else str(def.get("name", tid))
		var desc: String = "No telemetry available. Encounter technology in combat or world operations." if is_unknown else str(def.get("description", ""))

		var card := PanelContainer.new()
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.11, 0.13, 0.20, 0.9)
		card_style.border_width_left = 2
		card_style.border_width_top = 1
		card_style.border_width_right = 1
		card_style.border_width_bottom = 1
		card_style.content_margin_left = 12
		card_style.content_margin_right = 12
		card_style.content_margin_top = 8
		card_style.content_margin_bottom = 8
		card_style.corner_radius_top_left = 3
		card_style.corner_radius_top_right = 3
		card_style.corner_radius_bottom_left = 3
		card_style.corner_radius_bottom_right = 3

		# State color coding
		var state_col := Color(0.5, 0.5, 0.5)
		match state:
			TechSys.DiscoveryState.UNKNOWN:
				state_col = Color(0.45, 0.45, 0.5)
				card_style.border_color = Color(0.25, 0.25, 0.3)
			TechSys.DiscoveryState.ENCOUNTERED:
				state_col = Color(0.4, 0.75, 0.9)
				card_style.border_color = Color(0.3, 0.55, 0.75)
			TechSys.DiscoveryState.SALVAGED:
				state_col = Color(1.0, 0.65, 0.25)
				card_style.border_color = Color(0.85, 0.55, 0.2)
			TechSys.DiscoveryState.IDENTIFIED:
				state_col = Color(1.0, 0.9, 0.3)
				card_style.border_color = Color(0.8, 0.75, 0.25)
			TechSys.DiscoveryState.RESEARCHED:
				state_col = Color(0.4, 0.9, 0.6)
				card_style.border_color = Color(0.3, 0.75, 0.5)
			TechSys.DiscoveryState.USABLE:
				state_col = Color(0.3, 1.0, 0.4)
				card_style.border_color = Color(0.2, 0.85, 0.35)

		card.add_theme_stylebox_override("panel", card_style)
		tech_projects_container.add_child(card)

		var c_vbox := VBoxContainer.new()
		c_vbox.add_theme_constant_override("separation", 4)
		card.add_child(c_vbox)

		# Top Row: Title, Gen/Family, State Badge
		var top_row := HBoxContainer.new()
		c_vbox.add_child(top_row)

		var name_lbl := Label.new()
		name_lbl.text = display_name
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color.WHITE if not is_unknown else Color(0.65, 0.65, 0.7))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_row.add_child(name_lbl)

		var meta_lbl := Label.new()
		meta_lbl.text = "Gen %d  |  %s" % [gen, fam]
		meta_lbl.add_theme_font_size_override("font_size", 11)
		meta_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		top_row.add_child(meta_lbl)

		var badge := Label.new()
		badge.text = "[ %s ]" % state_name
		badge.add_theme_font_size_override("font_size", 11)
		badge.add_theme_color_override("font_color", state_col)
		top_row.add_child(badge)

		# Middle Row: Description / Telemetry
		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 10)
		desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75))
		c_vbox.add_child(desc_lbl)

		# Bottom Row: Metric & Action Guidance / Buttons
		var bot_row := HBoxContainer.new()
		bot_row.add_theme_constant_override("separation", 10)
		c_vbox.add_child(bot_row)

		var action_msg := ""
		var r_meta := TechSys.get_research_metadata(tid)
		var req_ev: float = float(r_meta.get("required_evidence", 1.0))
		var cur_ev: float = TechSys.get_technology_evidence(tid)
		var cur_prog: float = TechSys.get_research_progress(tid)

		match state:
			TechSys.DiscoveryState.UNKNOWN:
				action_msg = "Next: Encounter technology in combat or world events"
			TechSys.DiscoveryState.ENCOUNTERED:
				action_msg = "Next: Salvage technology components from battle"
			TechSys.DiscoveryState.SALVAGED:
				if TechSys.can_identify_technology(tid):
					action_msg = "Evidence: %.0f / %.0f (Ready to Identify)" % [cur_ev, req_ev]
					var id_btn := Button.new()
					id_btn.text = "[ IDENTIFY ]"
					id_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
					id_btn.pressed.connect(_on_identify_tech.bind(tid))
					bot_row.add_child(id_btn)
				else:
					action_msg = "Evidence: %.0f / %.0f (Need %.0f more evidence)" % [cur_ev, req_ev, maxf(req_ev - cur_ev, 1.0)]
			TechSys.DiscoveryState.IDENTIFIED:
				var is_active_proj := (active_tech == tid)
				if is_active_proj:
					action_msg = "Research Progress: %d%% [ACTIVE PROJECT — advance days or win battles]" % int(cur_prog)
					if TechSys.can_complete_research(tid):
						var fin_btn := Button.new()
						fin_btn.text = "[ FINALIZE RESEARCH ]"
						fin_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
						fin_btn.pressed.connect(_on_finalize_tech.bind(tid))
						bot_row.add_child(fin_btn)
				else:
					action_msg = "Research Progress: %d%%" % int(cur_prog)
					if TechSys.can_start_research(tid):
						var start_btn := Button.new()
						start_btn.text = "[ START RESEARCH ]"
						start_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
						start_btn.pressed.connect(_on_start_tech_research.bind(tid))
						bot_row.add_child(start_btn)
					elif TechSys.can_complete_research(tid):
						var fin_btn := Button.new()
						fin_btn.text = "[ FINALIZE RESEARCH ]"
						fin_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
						fin_btn.pressed.connect(_on_finalize_tech.bind(tid))
						bot_row.add_child(fin_btn)
					else:
						action_msg += " (Prerequisites not yet researched)"
			TechSys.DiscoveryState.RESEARCHED:
				action_msg = "Status: RESEARCH COMPLETE — Unlocking for Mecha Loadout"
				var use_btn := Button.new()
				use_btn.text = "[ AUTHORIZE FOR MECHA ]"
				use_btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
				use_btn.pressed.connect(_on_authorize_usable.bind(tid))
				bot_row.add_child(use_btn)
			TechSys.DiscoveryState.USABLE:
				action_msg = "Status: USABLE — Authorized for Mecha Loadout"

		var act_lbl := Label.new()
		act_lbl.text = action_msg
		act_lbl.add_theme_font_size_override("font_size", 10)
		act_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
		act_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bot_row.add_child(act_lbl)
		bot_row.move_child(act_lbl, 0)

	status_label.text = "Data Cores: %d | Credits: %d" % [GlobalData.currency.data_cores, GlobalData.currency.credits]


func _on_start_research(project_id: String) -> void:
	if FleetSystem.start_research(project_id):
		var project := FleetSystem.get_research_project(project_id)
		status_label.text = "Research started: %s" % str(project.get("name", project_id))
	else:
		status_label.text = "Cannot start — not enough data cores or already active."
	_refresh()


func _on_identify_tech(tech_id: String) -> void:
	if TechSys.record_technology_identified(tech_id):
		var def := TechSys.get_technology_definition(tech_id)
		status_label.text = "Technology Identified: %s" % str(def.get("name", tech_id))
	_refresh()


func _on_start_tech_research(tech_id: String) -> void:
	if TechSys.start_research(tech_id):
		var def := TechSys.get_technology_definition(tech_id)
		status_label.text = "Active Research Started: %s" % str(def.get("name", tech_id))
	_refresh()


func _on_finalize_tech(tech_id: String) -> void:
	if TechSys.complete_technology_research(tech_id):
		var def := TechSys.get_technology_definition(tech_id)
		status_label.text = "Research Finalized: %s" % str(def.get("name", tech_id))
	_refresh()


func _on_authorize_usable(tech_id: String) -> void:
	if TechSys.record_technology_usable(tech_id):
		var def := TechSys.get_technology_definition(tech_id)
		status_label.text = "Technology Authorized for Mechas: %s" % str(def.get("name", tech_id))
	_refresh()


func _on_leave_pressed() -> void:
	visible = false
	get_tree().paused = false
	EventBus.repair_requested.emit()

