extends CanvasLayer

var root_control: Control
var panel: PanelContainer
var title_label: Label
var rewards_label: Label
var continue_button: Button

var rewards: Dictionary = {}

# Heat gained when the player abandons a battle through a retreat zone.
const ESCAPE_HEAT_PENALTY := 4

var is_escaped := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()
	visible = false
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.combat_escaped.connect(_on_combat_escaped)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_pressed() and not event.is_echo():
		if event is InputEventKey:
			if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]:
				get_viewport().set_input_as_handled()
				_on_continue_pressed()


func _create_ui() -> void:
	root_control = Control.new()
	root_control.process_mode = Node.PROCESS_MODE_ALWAYS
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	# Center panel
	panel = PanelContainer.new()
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -250
	panel.offset_right = 250
	panel.offset_top = -150
	panel.offset_bottom = 150
	root_control.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.15, 0.2, 0.95)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 25
	style.content_margin_right = 25
	style.content_margin_top = 25
	style.content_margin_bottom = 25
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	title_label = Label.new()
	title_label.text = "COMBAT VICTORY"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title_label)

	var separator = HSeparator.new()
	vbox.add_child(separator)

	rewards_label = Label.new()
	rewards_label.text = ""
	rewards_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(rewards_label)

	continue_button = Button.new()
	continue_button.process_mode = Node.PROCESS_MODE_ALWAYS
	continue_button.mouse_filter = Control.MOUSE_FILTER_STOP
	continue_button.text = "Continue [Enter / Space / Click]"
	continue_button.custom_minimum_size = Vector2(200, 44)
	continue_button.pressed.connect(_on_continue_pressed)
	vbox.add_child(continue_button)


func _on_combat_ended(victory: bool) -> void:
	if victory:
		_show_victory_rewards()
	else:
		_show_defeat_screen()


func _on_combat_escaped() -> void:
	if is_escaped:
		return
	is_escaped = true
	if HeatWantedSystem:
		HeatWantedSystem.modify_heat(ESCAPE_HEAT_PENALTY)
	_show_escape_screen()


func _show_victory_rewards() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var is_duel := (GameManager.combat_node_type == "duel")
	var is_boss = GameManager.is_boss_combat
	var is_final_sector = (GlobalData.current_sector >= GlobalData.max_sectors)
	var is_raid = (GameManager.combat_node_type == "enemy_base")

	var credits_gained = randi_range(30, 80) + randi_range(1, 5)
	var scrap_gained = randi_range(4, 10)
	var heat_gained = 2
	var data_cores_gained = 0

	if is_duel:
		# Duel wins grant no standard loot — the outcome is the rival joining,
		# a salvaged wreck, or parts (already applied by RecruitSystem).
		credits_gained = 0
		scrap_gained = 0
		heat_gained = 1

	if is_raid:
		credits_gained += 60
		scrap_gained += 10

	if is_boss:
		var ending: Dictionary = GlobalData.get_theme_ending()
		title_label.text = "SECTOR %d CLEARED!" % GlobalData.current_sector
		credits_gained += 105
		scrap_gained += 15
		data_cores_gained = 1
		GlobalData.gain_data_cores(data_cores_gained)

		if is_final_sector:
			title_label.text = "CAMPAIGN VICTORY!"
			rewards_label.text = "%s\n\n" % ending.get("victory_text", "The war is over. You won.")
			continue_button.text = "Finish Run [Enter / Space]"
		else:
			rewards_label.text = "%s\n\n" % ending.get("name", "Sector Battle")
			continue_button.text = "Proceed to Sector %d [Enter / Space]" % (GlobalData.current_sector + 1)
	else:
		if is_raid:
			title_label.text = "RESEARCH BASE DESTROYED!"
			continue_button.text = "Continue [Enter / Space / Click]"
		elif is_duel:
			title_label.text = "DUEL RESOLVED"
			continue_button.text = "Return to Board [Enter / Space / Click]"
		else:
			title_label.text = "COMBAT VICTORY"
			continue_button.text = "Continue [Enter / Space / Click]"

	GlobalData.gain_credits(credits_gained)
	GlobalData.gain_scrap(scrap_gained)

	rewards = {
		"credits": credits_gained,
		"scrap": scrap_gained,
		"heat": heat_gained,
		"data_cores": data_cores_gained
	}

	if is_duel:
		var duel_text := GlobalData.duel_result_text
		GlobalData.duel_result_text = ""
		if duel_text != "":
			rewards_label.text = "%s\n" % duel_text
	else:
		rewards_label.text = ""
		if not is_boss or not is_final_sector:
			rewards_label.text += "Rewards:\n"
			rewards_label.text += "+%d Credits\n" % credits_gained
			rewards_label.text += "+%d Scrap (Material)\n" % scrap_gained
			if data_cores_gained > 0:
				rewards_label.text += "+%d Data Cores (Research Item)\n" % data_cores_gained
			rewards_label.text += "+%d Heat\n" % heat_gained
			rewards_label.text += "\nTotal Credits: %d | Scrap: %d" % [GlobalData.credits, GlobalData.scrap]

	await get_tree().process_frame
	if continue_button:
		continue_button.grab_focus()


func _show_escape_screen() -> void:
	visible = true
	title_label.text = "WITHDREW FROM COMBAT"
	rewards_label.text = "You held position in the retreat zone and abandoned the battle.\n\nNo rewards are collected for a retreat.\n\n+%d Heat — enemy forces tighten their pursuit." % ESCAPE_HEAT_PENALTY
	continue_button.text = "Return to Board [Enter / Space / Click]"
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	await get_tree().process_frame
	if continue_button:
		continue_button.grab_focus()


func _show_defeat_screen() -> void:
	visible = true
	var ending: Dictionary = GlobalData.get_theme_ending()
	title_label.text = "DEFEATED"
	rewards_label.text = ending.get("defeat_text", "Your mech has been destroyed.\n\nReturning to main menu...")
	continue_button.text = "Continue [Enter / Space / Click]"
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	await get_tree().process_frame
	if continue_button:
		continue_button.grab_focus()


func _on_continue_pressed() -> void:
	visible = false
	get_tree().paused = false
	if is_escaped:
		is_escaped = false
		GameManager.is_escaping = false
		GameManager.return_to_board()
	elif title_label.text == "DEFEATED":
		GameManager.game_over()
	elif GameManager.is_boss_combat:
		if GlobalData.current_sector >= GlobalData.max_sectors:
			GameManager.end_run(true)
		else:
			GameManager.advance_to_next_sector()
	else:
		GameManager.return_to_board()
