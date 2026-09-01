extends CanvasLayer
## War Launch Setup — Dynamic Fitting + Ace Right (PLAN.md 6.3, 7)
## Skeleton: Quick Launch / Custom Fitting + Ace 30s reservation

signal launch_requested(category: String, fitting: Dictionary)
signal closed

var _panel: PanelContainer
var _status_label: Label
var _ace_label: Label
var _ace_timer: Timer
var _ace_holder: String = ""
var _ace_remaining: float = 0.0
var _is_ace_phase: bool = false

var _fitting: Dictionary = {
	"main_hand": "",
	"off_hand": "",
	"backpack": "cargo",
	"shoulder_left": "",
	"shoulder_right": "",
}

var _deployment: WarDeploymentManager = null


func _ready() -> void:
	layer = 20
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_deployment = WarDeploymentManager.new()
	_build_ui()
	_ace_timer = Timer.new()
	_ace_timer.wait_time = 1.0
	_ace_timer.timeout.connect(_on_ace_tick)
	add_child(_ace_timer)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -360
	_panel.offset_right = 360
	_panel.offset_top = -280
	_panel.offset_bottom = 280
	add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.14, 0.97)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.7, 1.0, 0.9)
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "WAR LAUNCH SETUP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "Quick Launch = spawn ทันที / Custom Fitting = เลือก Main/Off/Backpack/Q-E ก่อน spawn"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	vbox.add_child(desc)

	vbox.add_child(HSeparator.new())

	# Fitting row
	var fitting_row := HBoxContainer.new()
	fitting_row.add_theme_constant_override("separation", 8)
	vbox.add_child(fitting_row)
	for key in ["main_hand", "off_hand", "backpack", "shoulder_left", "shoulder_right"]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fitting_row.add_child(col)
		var lbl := Label.new()
		lbl.text = key.to_upper()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9))
		col.add_child(lbl)
		var val := Label.new()
		val.name = "Val_%s" % key
		val.text = str(_fitting.get(key, "-"))
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.add_theme_font_size_override("font_size", 11)
		col.add_child(val)
		var btn := Button.new()
		btn.text = "CHANGE"
		btn.custom_minimum_size = Vector2(0, 24)
		btn.pressed.connect(_on_change_fitting.bind(key))
		col.add_child(btn)

	vbox.add_child(HSeparator.new())

	# Category buttons
	var cat_row := HBoxContainer.new()
	cat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cat_row.add_theme_constant_override("separation", 10)
	vbox.add_child(cat_row)
	for cat in ["line", "iron", "strike", "valkyrion"]:
		var btn := Button.new()
		btn.name = "Btn_%s" % cat
		btn.text = cat.to_upper()
		btn.custom_minimum_size = Vector2(110, 44)
		btn.pressed.connect(_on_launch.bind(cat))
		cat_row.add_child(btn)

	_ace_label = Label.new()
	_ace_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ace_label.add_theme_font_size_override("font_size", 12)
	_ace_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vbox.add_child(_ace_label)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_status_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)
	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.custom_minimum_size = Vector2(120, 36)
	close_btn.pressed.connect(_on_close)
	btn_row.add_child(close_btn)

	_refresh_status()


func open_setup(ace_holder: String = "") -> void:
	visible = true
	if get_tree():
		get_tree().paused = true
	_ace_holder = ace_holder
	if ace_holder != "":
		_is_ace_phase = true
		_ace_remaining = WarBalance.ACE_RIGHT_TIMEOUT
		_ace_timer.start()
	else:
		_is_ace_phase = false
		_ace_remaining = 0.0
		_ace_timer.stop()
	_refresh_status()


func _on_ace_tick() -> void:
	_ace_remaining -= 1.0
	if _ace_remaining <= 0.0:
		_is_ace_phase = false
		_ace_timer.stop()
		_ace_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
		_ace_label.text = "ACE TIMEOUT — PUBLIC SPAWN OPEN"
	else:
		_refresh_status()


func _refresh_status() -> void:
	if not _status_label:
		return
	if _deployment:
		_status_label.text = _deployment.get_status_text()
	else:
		_status_label.text = "Deploy caps: line 5 | iron/strike 3 | valkyrion 1"
	for key in _fitting.keys():
		var lbl: Label = _panel.find_child("Val_%s" % key, true, false) as Label
		if lbl:
			lbl.text = str(_fitting.get(key, "-")) if str(_fitting.get(key, "")) != "" else "-"
	if _is_ace_phase:
		_ace_label.text = "ACE RIGHT: %s has %.0fs to claim Valkyrion" % [_ace_holder, _ace_remaining]
	else:
		if _ace_holder != "" and _ace_remaining <= 0.0:
			_ace_label.text = "PUBLIC — anyone can spawn Valkyrion"
		else:
			_ace_label.text = "VALKYRION: %s" % ("LOCKED — no blueprint" if not _has_valkyrion_blueprint() else "READY")


func _has_valkyrion_blueprint() -> bool:
	return GlobalData.has_method("has_blueprint") and false or true


func _on_change_fitting(slot: String) -> void:
	if slot == "backpack":
		var opts := ["cargo", "booster", "combat"]
		var cur: String = str(_fitting.get(slot, "cargo"))
		var idx := opts.find(cur)
		_fitting[slot] = opts[(idx + 1) % opts.size()]
	else:
		_fitting[slot] = "wep_%s_%d" % [slot, randi() % 100] if str(_fitting.get(slot, "")) == "" else ""
	_refresh_status()


func _on_launch(category: String) -> void:
	if _deployment and not _deployment.can_deploy(category):
		_status_label.text = "CAP FULL / COOLDOWN — cannot deploy %s" % category
		return
	if category == "valkyrion" and _is_ace_phase and _ace_holder != str(GlobalData.hangar.active_hangar_mech_id if GlobalData.hangar else ""):
		# In real multiplayer, check merit holder; solo = player is ace so allow
		pass
	if _deployment:
		_deployment.on_deployed(category)
	launch_requested.emit(category, _fitting.duplicate())
	visible = false
	if get_tree():
		get_tree().paused = false


func _on_close() -> void:
	visible = false
	if get_tree():
		get_tree().paused = false
	_ace_timer.stop()
	closed.emit()
