extends CanvasLayer

## ResearchLabUI: a board node that lets the player browse and start research
## projects. Each project costs data_cores to begin and takes research_time
## (board moves = 1pt, combats = 2pts) to complete. Completed projects
## unlock ally units, gundam-tier gear, or special abilities.

var root_control: Control
var panel: PanelContainer
var title_label: Label
var info_label: Label
var projects_container: VBoxContainer
var active_container: VBoxContainer
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
	panel.offset_left = -320
	panel.offset_right = 320
	panel.offset_top = -320
	panel.offset_bottom = 320
	root_control.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.2, 0.95)
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
	title_label.text = "RESEARCH LAB"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	vbox.add_child(title_label)

	var separator = HSeparator.new()
	vbox.add_child(separator)

	info_label = Label.new()
	info_label.text = ""
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", 12)
	info_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	vbox.add_child(info_label)

	# Active research section
	var active_label = Label.new()
	active_label.text = "ACTIVE RESEARCH"
	active_label.add_theme_font_size_override("font_size", 14)
	active_label.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5))
	vbox.add_child(active_label)

	active_container = VBoxContainer.new()
	active_container.add_theme_constant_override("separation", 4)
	vbox.add_child(active_container)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	projects_container = VBoxContainer.new()
	projects_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	projects_container.add_theme_constant_override("separation", 4)
	scroll.add_child(projects_container)

	leave_button = Button.new()
	leave_button.text = "Leave Lab"
	leave_button.custom_minimum_size = Vector2(600, 36)
	leave_button.pressed.connect(_on_leave_pressed)
	vbox.add_child(leave_button)

	status_label = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)


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
	var total_cores := GlobalData.data_cores
	info_label.text = "Data Cores: %d  |  Start a project to unlock new units and gear." % total_cores

	# --- Active research ---
	for child in active_container.get_children():
		child.queue_free()

	var has_active := false
	for project_id in GlobalData.research_projects:
		var state = GlobalData.research_projects[project_id]
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
		empty_lbl.text = "No active research."
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
		btn.custom_minimum_size = Vector2(600, 50)
		btn.text = "%s  [%d cores, %d turns]  → %s: %s" % [pname, cost, time, reward_type.capitalize(), reward_name]
		btn.tooltip_text = pdesc
		btn.disabled = GlobalData.data_cores < cost
		btn.pressed.connect(_on_start_research.bind(pid))
		projects_container.add_child(btn)

	if available_count == 0:
		var done_lbl := Label.new()
		done_lbl.text = "All projects completed or in progress."
		done_lbl.add_theme_font_size_override("font_size", 11)
		done_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		projects_container.add_child(done_lbl)

	status_label.text = "Data Cores: %d | Credits: %d" % [GlobalData.data_cores, GlobalData.credits]


func _on_start_research(project_id: String) -> void:
	if FleetSystem.start_research(project_id):
		var project := FleetSystem.get_research_project(project_id)
		status_label.text = "Research started: %s" % str(project.get("name", project_id))
	else:
		status_label.text = "Cannot start — not enough data cores or already active."
	_refresh()


func _on_leave_pressed() -> void:
	visible = false
	get_tree().paused = false
	EventBus.repair_requested.emit()
