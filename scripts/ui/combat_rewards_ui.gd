extends CanvasLayer

var root_control: Control
var panel: PanelContainer
var title_label: Label
var rewards_label: Label
var continue_button: Button
var loot_picker: HBoxContainer = null
var loot_left_list: VBoxContainer = null
var loot_right_list: VBoxContainer = null
var take_all_button: Button = null

var rewards: Dictionary = {}

# Items from this battle still waiting on the left ("dropped") / picked to take
# back on the right. Populated from GlobalData.battle_loot on the victory screen;
# Continue grants the right-side entries and discards the left.
var _left_items: Array = []
var _right_items: Array = []

# Live loot-summary state: the fixed "Rewards:..." tail that stays pinned below
# the summary line, and whether the loot summary owns the label (vs. duel /
# ending text). Moving items between the columns calls _refresh_loot_summary()
# so the "stripped for +X Scrap" figure updates in real time.
var _rewards_tail: String = ""
var _loot_summary_active: bool = false

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
	panel.offset_left = -360
	panel.offset_right = 360
	panel.offset_top = -240
	panel.offset_bottom = 240
	root_control.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.15, 0.2, 0.95)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 25
	style.content_margin_right = 25
	style.content_margin_top = 20
	style.content_margin_bottom = 20
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

	# Two-column battle loot picker: left = items that dropped this battle,
	# right = items the player takes back. Click an item to move it across.
	loot_picker = HBoxContainer.new()
	loot_picker.add_theme_constant_override("separation", 18)
	loot_picker.custom_minimum_size = Vector2(0, 220)
	vbox.add_child(loot_picker)

	loot_left_list = _new_loot_list()
	loot_right_list = _new_loot_list()
	loot_picker.add_child(_column_frame("BATTLE DROPS — click to take", loot_left_list, true))
	loot_picker.add_child(_column_frame("TAKE BACK — click to return", loot_right_list))

	rewards_label = Label.new()
	rewards_label.text = ""
	rewards_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rewards_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rewards_label.custom_minimum_size = Vector2(0, 60)
	vbox.add_child(rewards_label)

	continue_button = Button.new()
	continue_button.process_mode = Node.PROCESS_MODE_ALWAYS
	continue_button.mouse_filter = Control.MOUSE_FILTER_STOP
	continue_button.text = "Continue [Enter / Space / Click]"
	continue_button.custom_minimum_size = Vector2(200, 44)
	continue_button.pressed.connect(_on_continue_pressed)
	vbox.add_child(continue_button)


func _new_loot_list() -> VBoxContainer:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return list


func _column_frame(header: String, list: VBoxContainer, with_take_all: bool = false) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(310, 0)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.05, 0.07, 0.1, 0.6)
	frame_style.corner_radius_top_left = 8
	frame_style.corner_radius_top_right = 8
	frame_style.corner_radius_bottom_left = 8
	frame_style.corner_radius_bottom_right = 8
	frame_style.content_margin_left = 12
	frame_style.content_margin_right = 12
	frame_style.content_margin_top = 10
	frame_style.content_margin_bottom = 10
	frame.add_theme_stylebox_override("panel", frame_style)

	var column_vbox := VBoxContainer.new()
	column_vbox.add_theme_constant_override("separation", 8)
	frame.add_child(column_vbox)

	var head := Label.new()
	head.text = header
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 15)
	column_vbox.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column_vbox.add_child(scroll)

	scroll.add_child(list)

	# One-click "take every drop" — moves the whole BATTLE DROPS column to
	# TAKE BACK instead of clicking each row. Lives under the left column.
	if with_take_all:
		take_all_button = Button.new()
		take_all_button.process_mode = Node.PROCESS_MODE_ALWAYS
		take_all_button.mouse_filter = Control.MOUSE_FILTER_STOP
		take_all_button.text = "Take All ▸"
		take_all_button.custom_minimum_size = Vector2(0, 34)
		take_all_button.pressed.connect(_on_take_all_pressed)
		column_vbox.add_child(take_all_button)
	return frame


# Populates both loot columns from the battle pool. Called when the victory
# screen opens; keeps whatever the player already moved on re-population.
func _populate_loot_picker() -> void:
	for child in loot_left_list.get_children():
		child.queue_free()
	for child in loot_right_list.get_children():
		child.queue_free()
	for entry in _left_items:
		_add_loot_row(loot_left_list, entry, false)
	for entry in _right_items:
		_add_loot_row(loot_right_list, entry, true)
	if take_all_button:
		take_all_button.disabled = _left_items.is_empty()


func _add_loot_row(list: VBoxContainer, entry: Dictionary, in_right: bool) -> void:
	var btn := Button.new()
	btn.text = _loot_entry_label(entry)
	btn.custom_minimum_size = Vector2(0, 34)
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = "Click to move to the other column."
	btn.pressed.connect(func() -> void:
		_toggle_loot_entry(entry)
	)
	list.add_child(btn)


func _loot_entry_label(entry: Dictionary) -> String:
	match str(entry.get("type", "")):
		"weapon":
			var w: WeaponPart = entry.get("weapon")
			if w:
				return "[W] %s (%d scrap)" % [w.weapon_name, _salvage_value(entry)]
			return "[W] Weapon"
		"armor":
			var inst: Dictionary = entry.get("instance", {})
			var name := str(inst.get("name", "Plate"))
			var slot := str(inst.get("slot", ""))
			var dur := int(float(inst.get("durability", 1.0)) * 100.0)
			return "[A] %s [%s] %d%% (%d scrap)" % [name, slot, dur, _salvage_value(entry)]
	return str(entry.get("type", "Item"))


func _toggle_loot_entry(entry: Dictionary) -> void:
	if _left_items.has(entry):
		_left_items.erase(entry)
		_right_items.append(entry)
	elif _right_items.has(entry):
		_right_items.erase(entry)
		_left_items.append(entry)
	_populate_loot_picker()
	_refresh_loot_summary()
	AudioManager.play_ui_confirm()


# "Take All ▸" moves every remaining BATTLE DROPS item to TAKE BACK at once.
func _on_take_all_pressed() -> void:
	if _left_items.is_empty():
		return
	for entry in _left_items:
		_right_items.append(entry)
	_left_items.clear()
	_populate_loot_picker()
	_refresh_loot_summary()
	AudioManager.play_ui_confirm()


# Grants every item on the TAKE BACK side: weapons are registered into the depot
# stash, armor instances appended to the convoy inventory. Items the player left
# in BATTLE DROPS are NOT wasted — they are auto-salvaged into scrap (the convoy
# mechanics strip whatever the player didn't pick). Clears the battle pool either way.
func _grant_take_back_loot() -> void:
	for entry in _right_items:
		match str(entry.get("type", "")):
			"weapon":
				var w: WeaponPart = entry.get("weapon")
				if w:
					GlobalData.register_weapon(w.resource_path, w.weapon_name)
			"armor":
				var inst: Dictionary = entry.get("instance", {})
				if not inst.is_empty():
					var uid := str(inst.get("uid", ""))
					if uid == "" or GlobalData.get_armor_instance(uid).is_empty():
						GlobalData.armor_inventory.append(inst)
	# Unclaimed drops are stripped for scrap instead of being left behind.
	var salvaged_scrap := 0
	for entry in _left_items:
		salvaged_scrap += _salvage_value(entry)
	if salvaged_scrap > 0:
		GlobalData.gain_scrap(salvaged_scrap)
		GlobalData.run_notice = "Unclaimed drops salvaged for +%d scrap." % salvaged_scrap
	GlobalData.battle_loot.clear()
	_left_items.clear()
	_right_items.clear()


# Scrap value of a loot entry the player did not take back: the convoy strips
# armor plates with the same base formula the craftery uses to price them, and
# weapons by their combat weight + damage tier — then multiplies by the part's
# RARITY TIER so higher-tier loot sells for noticeably more. 0 for anything
# not strippable.
func _salvage_value(entry: Dictionary) -> int:
	match str(entry.get("type", "")):
		"weapon":
			var w: WeaponPart = entry.get("weapon")
			if w == null:
				return 0
			var base := w.weight * 1.5 + w.damage * 0.2
			return maxi(2, int(round(base * RARITY_SCRAP_MULTIPLIERS[clampi(w.rarity, 0, 3)])))
		"armor":
			var inst: Dictionary = entry.get("instance", {})
			if inst.is_empty():
				return 0
			var base_cost := GlobalData.get_armor_scrap_cost(inst)
			return maxi(1, int(round(base_cost * RARITY_SCRAP_MULTIPLIERS[_armor_rarity_tier(inst)])))
	return 0


# Scrap multiplier per rarity tier (indexed by tier 0..3): common parts strip
# for their base value, while rare/legendary loot is worth several times more.
# Weapons carry an explicit rarity 0-3; armor has no rarity field, so its tier
# is derived from the catalog type label below.
const RARITY_SCRAP_MULTIPLIERS: Array[float] = [1.0, 1.6, 2.5, 4.0]


# Armor rarity tier derived from the catalog type label: standard / light
# plating are common (0), heavy armor uncommon (1), high-mobility rare (2),
# and gundam-tier armor legendary (3).
func _armor_rarity_tier(inst: Dictionary) -> int:
	var atype := str(inst.get("type", ""))
	if atype.contains("Gundam"):
		return 3
	if atype.contains("High-Mobility"):
		return 2
	if atype.contains("Heavy"):
		return 1
	return 0


# Rebuilds the loot-summary block from the CURRENT left/right split so the
# "stripped for +X Scrap" figure is always accurate while the player moves
# items between the columns. Splices the fixed rewards tail back underneath.
func _refresh_loot_summary() -> void:
	if not _loot_summary_active or rewards_label == null:
		return
	var loot_summary := ""
	if _left_items.is_empty():
		loot_summary = "No salvage dropped in this battle.\n"
	else:
		var unclaimed_scrap := 0
		for entry in _left_items:
			unclaimed_scrap += _salvage_value(entry)
		loot_summary = "Click items in BATTLE DROPS to take them back.\n"
		if unclaimed_scrap > 0:
			loot_summary += "Unclaimed drops are stripped for +%d Scrap.\n" % unclaimed_scrap
	rewards_label.text = loot_summary + _rewards_tail


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

	# Load the battle loot into the two-column picker (drops on the left).
	_left_items = GlobalData.battle_loot.duplicate()
	_right_items.clear()
	_populate_loot_picker()
	if loot_picker:
		loot_picker.visible = not _left_items.is_empty()

	if is_duel:
		_loot_summary_active = false
		var duel_text := GlobalData.duel_result_text
		GlobalData.duel_result_text = ""
		if duel_text != "":
			rewards_label.text = "%s\n" % duel_text
	else:
		_loot_summary_active = true
		# The fixed block under the live summary line (rebuilt each toggle via
		# _refresh_loot_summary, which splices it back below the updated figure).
		_rewards_tail = ""
		if not is_boss or not is_final_sector:
			_rewards_tail = "Rewards:\n"
			_rewards_tail += "+%d Credits\n" % credits_gained
			_rewards_tail += "+%d Scrap (Material)\n" % scrap_gained
			if data_cores_gained > 0:
				_rewards_tail += "+%d Data Cores (Research Item)\n" % data_cores_gained
			_rewards_tail += "+%d Heat\n" % heat_gained
			_rewards_tail += "\nTotal Credits: %d | Scrap: %d" % [GlobalData.credits, GlobalData.scrap]
		_refresh_loot_summary()

	await get_tree().process_frame
	if continue_button:
		continue_button.grab_focus()


func _show_escape_screen() -> void:
	visible = true
	_loot_summary_active = false
	title_label.text = "WITHDREW FROM COMBAT"
	rewards_label.text = "You held position in the retreat zone and abandoned the battle.\n\nNo rewards are collected for a retreat.\n\n+%d Heat — enemy forces tighten their pursuit." % ESCAPE_HEAT_PENALTY
	continue_button.text = "Return to Board [Enter / Space / Click]"
	# Abandoned loot is left on the field.
	GlobalData.battle_loot.clear()
	_left_items.clear()
	_right_items.clear()
	_populate_loot_picker()
	if loot_picker:
		loot_picker.visible = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	await get_tree().process_frame
	if continue_button:
		continue_button.grab_focus()


func _show_defeat_screen() -> void:
	visible = true
	_loot_summary_active = false
	var ending: Dictionary = GlobalData.get_theme_ending()
	title_label.text = "DEFEATED"
	rewards_label.text = ending.get("defeat_text", "Your mech has been destroyed.\n\nReturning to main menu...")
	continue_button.text = "Continue [Enter / Space / Click]"
	# Lost loot is left on the field.
	GlobalData.battle_loot.clear()
	_left_items.clear()
	_right_items.clear()
	_populate_loot_picker()
	if loot_picker:
		loot_picker.visible = false
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
		_grant_take_back_loot()
		if GlobalData.current_sector >= GlobalData.max_sectors:
			GameManager.end_run(true)
		else:
			GameManager.advance_to_next_sector()
	else:
		_grant_take_back_loot()
		GameManager.return_to_board()
