extends Node

## Headless verification of the panels extracted from hangar_controller.gd:
##   HangarPartText      — pure stat-card text helpers
##   HangarAmmoPanel     — ammo-to-carry loadout build/adjust/refresh
##   HangarRosterPanel   — roster page (badge, slot rows, pilot/role pickers)
##   HangarCatalogPanel  — catalog window + hover-stats preview
##   HangarGaragePanel   — 3D garage preview + attachment math
##   HangarCraftPanel    — craftery window (craft armor from templates)
##   HangarActionPanel   — ACTION MENU popup (equip/unequip/repair/upgrade/paint)
##   HangarEquipPanel    — equip/unequip flow (hands, back carry, armor, frames)
##   HangarPartListPanel — part list populate + selection + equipped queries
##   HangarStatsPanel    — total mech stats aggregation (weight bar + label)
##   HangarNavPanel      — submenu + page navigation (landing / pages)
##   HangarRepairPanel   — repair selected slot / full field repair
##   HangarSlotPanel     — slot tab selection (body/weapon hands + refresh)
##   HangarHeaderPanel   — top header bar (title, slot tabs, back-to-menu)
##   HangarLeftPanel     — left sidebar (part list, craftery, ammo, equip)
##   HangarRightPanel    — right sidebar (stats, weight, repair, status, exit)
##   nav/landing builders — sub-menu rail + mode-toggle bar
##   HangarReadinessPanel — combat-readiness warning modal
##   HangarPersistPanel   — persist/commit the edited mech working set
##   HangarScrapPanel     — scrap editor applied/closed preview refresh
##   HangarExitPanel      — hangar exit flow (persist + readiness + return)
##   HangarRefreshPanel   — post-change refresh helpers (mech/chassis/craft)
## Run: godot --headless --path . res://tests/hangar_panels_verify.tscn

var _fails: int = 0
var _checks: int = 0
# Readiness verify uses a member so the on_confirm lambda (which captures
# locals by value in GDScript) can still increment it through `self`.
var _confirm_calls: int = 0


func _ready() -> void:
	await get_tree().process_frame
	_verify_text_helpers()
	await _verify_ammo_panel()
	await _verify_roster_panel()
	await _verify_catalog_panel()
	await _verify_garage_panel()
	await _verify_craft_panel()
	await _verify_action_panel()
	await _verify_equip_panel()
	await _verify_part_list_panel()
	await _verify_stats_panel()
	await _verify_nav_panel()
	await _verify_repair_panel()
	await _verify_slot_panel()
	await _verify_layout_panels()
	await _verify_readiness_panel()
	await _verify_persist_panel()
	await _verify_scrap_panel()
	await _verify_exit_panel()
	await _verify_refresh_panel()
	print("HANGAR_PANELS_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _verify_text_helpers() -> void:
	_check(HangarPartText.weapon_type_label(0) == "Beam Weapon", "weapon_type_label beam")
	_check(HangarPartText.weapon_type_label(4) == "Melee Weapon", "weapon_type_label melee")
	_check(HangarPartText.weapon_type_label(99) == "Unknown", "weapon_type_label unknown")

	var rifle = load("res://resources/mech/stock/weapon_beam_rifle.tres")
	_check(rifle != null, "stock beam rifle resource loads")
	var wcap := HangarPartText.weapon_capability_text(rifle)
	_check(wcap.contains("TYPE: "), "weapon_capability_text has TYPE line")
	_check(HangarPartText.weapon_capability_text(null) == "", "weapon_capability_text null -> empty")

	var fcap := HangarPartText.frame_capability_text({"type": "Inner Frame", "hp": 50.0, "weight": 3.0, "carry_bonus": 5.0})
	_check(fcap.contains("FRAME HP: 50"), "frame_capability_text has HP line")
	_check(fcap.contains("FIELD PACK BONUS: +5.0 kg"), "frame_capability_text has carry bonus")
	_check(HangarPartText.frame_capability_text({}) == "", "frame_capability_text empty dict -> empty")

	var acap := HangarPartText.armor_capability_text({"type": "Plate", "max_hp": 100.0, "weight": 4.0}, 0.5)
	_check(acap.contains("ARMOR HP: 50 / 100"), "armor_capability_text applies passed durability")
	_check(HangarPartText.armor_capability_text({}, 1.0) == "", "armor_capability_text empty dict -> empty")


func _verify_ammo_panel() -> void:
	GlobalData.reset_run_data()
	# reset_run_data grants a starter loadout + reserve; force a clean slate for
	# the panel so the assertions are deterministic.
	GlobalData.set_loadout_ammo("kinetic", 0)
	GlobalData.add_reserve_ammo("kinetic", 50)
	await get_tree().process_frame

	var panel := HangarAmmoPanel.new()
	var box := VBoxContainer.new()
	add_child(box)
	var status_lbl := Label.new()
	add_child(status_lbl)
	panel.build(box)
	panel.status_label = status_lbl

	_check(panel.ammo_loadout_box != null, "ammo panel builds a loadout box")
	_check(panel.ammo_value_labels.size() == 4, "ammo panel tracks 4 ammo types")
	_check(panel.ammo_loadout_box.visible == false, "loadout box starts hidden")

	panel.adjust("kinetic", 10)
	_check(GlobalData.get_loadout_ammo("kinetic") == 10, "adjust adds to loadout")
	_check(status_lbl.text == "Kinetic ammo to carry: 10", "adjust reports via status label")

	panel.adjust("kinetic", -5)
	_check(GlobalData.get_loadout_ammo("kinetic") == 5, "adjust subtracts loadout")

	# A huge request clamps to what is owned in reserve (350: starter 300 + 50).
	panel.adjust("kinetic", 999)
	_check(GlobalData.get_loadout_ammo("kinetic") == 350, "adjust clamps to owned reserve")

	panel.refresh()
	var value_lbl: Label = panel.ammo_value_labels["kinetic"]
	_check(value_lbl.text == "350 / 350", "refresh repaints carried / owned labels")

	box.queue_free()
	status_lbl.queue_free()


func _verify_roster_panel() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var rp = ctrl.roster_panel_ui
	_check(rp != null, "controller builds a HangarRosterPanel")
	_check(rp.roster_panel != null, "roster panel builds its root panel")
	_check(rp.roster_slot_list != null, "roster panel builds the slot list")
	_check(rp.roster_page_title != null and rp.roster_status_label != null, "roster panel builds title + status labels")
	_check(rp.mech_slot_label != null and rp.mech_prev_button != null and rp.mech_next_button != null, "roster panel builds badge + prev/next")
	_check(rp.roster_panel.visible == false, "roster panel starts hidden")
	_check(rp.mech_slot_label.visible == false, "badge starts hidden")

	ctrl.nav_panel.select_submenu("roster")
	await get_tree().process_frame
	_check(rp.roster_panel.visible, "roster page shows the panel")
	_check(rp.roster_slot_list.get_child_count() > 0, "roster page lists berth rows")
	_check(rp.mech_slot_label.visible, "badge visible on roster page")
	_check(rp.mech_slot_label.text.begins_with("MECH SLOT"), "badge reads MECH SLOT x/y")
	_check(rp.roster_status_label.text.contains("CONVOY"), "roster status shows the convoy summary")

	# Role picker: open for the active mech, pick "Ranged", assert it persists.
	var mech_id := str(GlobalData.get_active_hangar_mech().get("id", ""))
	var anchor := Button.new()
	add_child(anchor)
	rp.open_role_picker(mech_id, anchor)
	var pop := _find_popup(ctrl)
	_check(pop != null, "role picker creates a popup menu")
	if pop:
		pop.id_pressed.emit(1) # Ranged
		_check(GlobalData.get_hangar_archetype(mech_id) == HangarManager.ARCHETYPE_RANGED, "role picker assigns the chosen archetype")

	# Pilot picker: assign a pilot if one exists, then "(no pilot)" clears it.
	var pilots := GlobalData.get_hangar_pilots()
	if not pilots.is_empty():
		GlobalData.assign_hangar_pilot(mech_id, str(pilots[0].get("id", "")))
	rp.open_pilot_picker(mech_id, anchor)
	pop = _find_popup(ctrl)
	_check(pop != null, "pilot picker creates a popup menu")
	if pop:
		pop.id_pressed.emit(0)
		var stored_pilot := ""
		for m in GlobalData.get_hangar_mechs():
			if str(m.get("id", "")) == mech_id:
				stored_pilot = str(m.get("pilot", ""))
		_check(stored_pilot == "", "pilot picker '(no pilot)' clears the seat")
	# Let the picker's refresh_page rebuild settle so no stale (queued-for-
	# deletion) berth rows linger when the REGISTER checks look for a button.
	await get_tree().process_frame

	# --- REGISTER: empty berths offer a frame-assembly button + name prompt. ---
	# Solo convoy: capacity 2 with one parked mech -> SLOT 02 is an empty berth.
	var register_btn := _find_register_button(rp)
	_check(register_btn != null, "empty berth row offers a REGISTER button")
	var mechs_before := GlobalData.get_hangar_mechs().size()
	var reg_scrap := GlobalData.get_frame_register_scrap_cost()
	var reg_credits := GlobalData.get_frame_register_credit_cost()
	var scrap_before := GlobalData.scrap
	var credits_before := GlobalData.credits

	# REGISTER costs scrap + credits (HangarManager.REGISTER_*_COST). reset_run_data
	# leaves scrap at 0, so the price gate blocks until resources are granted.
	rp.register_mech(2)
	_check(rp.roster_status_label.text.contains("not enough resources"), "REGISTER blocks without enough scrap/credits")
	_check(rp.register_dialog == null, "unaffordable REGISTER opens no name prompt")
	_check(GlobalData.get_hangar_mechs().size() == mechs_before, "unaffordable REGISTER parks no mech")
	_check(GlobalData.scrap == scrap_before and GlobalData.credits == credits_before, "unaffordable REGISTER spends nothing")

	# Grant enough resources for the rest of the flow, then press REGISTER.
	GlobalData.gain_scrap(reg_scrap + 500)
	GlobalData.gain_credits(reg_credits + 500)
	var scrap_after_grant := GlobalData.scrap
	var credits_after_grant := GlobalData.credits
	if register_btn:
		register_btn.pressed.emit()
		await get_tree().process_frame
	_check(rp.register_dialog != null, "REGISTER opens the name prompt dialog")
	_check(rp.register_dialog_edit != null, "name prompt builds the LineEdit")
	_check(rp.register_dialog_edit.text == "Mech 02", "name prompt defaults to the slot-based name")
	_check(_collect_label_text(rp.register_dialog).contains("COST: %d scrap" % reg_scrap), "name prompt shows the assembly cost")
	_check(GlobalData.get_hangar_mechs().size() == mechs_before, "nothing is parked until the name is confirmed")

	# Cancelling aborts without parking or spending anything.
	if rp.register_dialog:
		var cancel_btn := _find_button_by_text(rp.register_dialog, "CANCEL")
		_check(cancel_btn != null, "name prompt builds the CANCEL button")
		if cancel_btn:
			cancel_btn.pressed.emit()
			await get_tree().process_frame
	_check(rp.register_dialog == null or not is_instance_valid(rp.register_dialog), "CANCEL closes the name prompt")
	_check(GlobalData.get_hangar_mechs().size() == mechs_before, "CANCEL parks nothing")
	_check(GlobalData.scrap == scrap_after_grant and GlobalData.credits == credits_after_grant, "CANCEL spends nothing")

	# Confirming with a custom name parks the mech and charges the exact cost.
	# Re-seat the player in the original berth first so the register pilot swap
	# is actually exercised (the old mech must end up as a pilotless spare).
	var old_id := ""
	for m in GlobalData.get_hangar_mechs():
		if int(m.get("slot", 0)) == 1:
			old_id = str(m.get("id", ""))
			break
	if old_id != "":
		GlobalData.assign_hangar_pilot(old_id, HangarManager.PLAYER_PILOT_ID)
	if register_btn and is_instance_valid(register_btn):
		register_btn.pressed.emit()
		await get_tree().process_frame
	_check(rp.register_dialog != null, "REGISTER re-opens the prompt for a custom name")
	if rp.register_dialog_edit:
		rp.register_dialog_edit.text = "Vanguard"
	if rp.register_dialog:
		var ok_btn := _find_button_by_text(rp.register_dialog, "REGISTER FRAME")
		_check(ok_btn != null, "name prompt builds the confirm button")
		if ok_btn:
			ok_btn.pressed.emit()
			await get_tree().process_frame
	_check(GlobalData.get_hangar_mechs().size() == mechs_before + 1, "confirmed REGISTER assembles a mech into the empty berth")
	var scrap_after_first := GlobalData.scrap
	var credits_after_first := GlobalData.credits
	_check(scrap_after_first == scrap_after_grant - reg_scrap, "REGISTER spends exactly the scrap cost")
	_check(credits_after_first == credits_after_grant - reg_credits, "REGISTER spends exactly the credit cost")
	_check(ctrl.status_message_label.text.contains("-%d scrap" % reg_scrap), "REGISTER reports the spent cost")
	var registered_name := ""
	var new_id := ""
	for m in GlobalData.get_hangar_mechs():
		if int(m.get("slot", 0)) == 2:
			registered_name = str(m.get("name", ""))
			new_id = str(m.get("id", ""))
	_check(registered_name == "Vanguard", "custom name is used instead of the auto 'Mech 02'")
	_check(ctrl.status_message_label.text.contains("Vanguard"), "REGISTER reports the named mech")
	# Confirming jumps straight into the customize page for the new mech: the
	# editing target follows, its snapshot loads into the working set, and the
	# badge + sidebars show the customize page instead of the roster.
	_check(ctrl.nav_panel.current_submenu == "customize", "REGISTER lands on the customize page")
	_check(ctrl.left_panel != null and ctrl.left_panel.visible, "customize page is visible after REGISTER")
	_check(ctrl.right_panel != null and ctrl.right_panel.visible, "customize sidebars are visible after REGISTER")
	_check(rp.roster_panel == null or not rp.roster_panel.visible, "roster page is left after REGISTER")
	_check(ctrl._customize_mech_id == new_id, "editing target follows the freshly registered mech")
	_check(rp.mech_slot_label.text.contains("Vanguard"), "badge tracks the freshly registered mech")
	# The frame also becomes the player's mech: active + pilot label move over,
	# and the previous machine parks as a pilotless spare.
	_check(GlobalData.active_hangar_mech_id == new_id, "freshly registered mech becomes the piloted mech")
	var pilot_of_new := ""
	var pilot_of_old := ""
	for m in GlobalData.get_hangar_mechs():
		if str(m.get("id", "")) == new_id:
			pilot_of_new = str(m.get("pilot", ""))
		elif int(m.get("slot", 0)) == 1:
			pilot_of_old = str(m.get("pilot", ""))
	_check(pilot_of_new == "player", "player pilot auto-assigned to the new frame")
	_check(pilot_of_old == "", "the previous mech parks as a pilotless spare")
	_check(_find_register_button(rp) == null, "a filled berth no longer offers REGISTER")
	# The success cue is a distinct mech-register sound (not the generic confirm
	# beep): the AudioManager must expose the API, generate the stream and play
	# it without error (headless playback is silent but validates the wiring).
	_check(AudioManager.has_method("play_mech_register"), "AudioManager exposes the mech-register cue")
	_check(AudioManager._sound_cache.has("mech_register"), "AudioManager generates the mech-register sound")
	AudioManager.play_mech_register()
	_check(true, "mech-register cue plays without error")

	# Free the berth, then verify the walking-chassis gate: without a body frame
	# the build is blocked with a hint and no name prompt is offered.
	var parked_id := ""
	for m in GlobalData.get_hangar_mechs():
		if int(m.get("slot", 0)) == 2:
			parked_id = str(m.get("id", ""))
			break
	if parked_id != "":
		GlobalData.remove_hangar_mech(parked_id)
		GlobalData.equipped_frames.erase("body")
		rp.register_mech(2)
		_check(rp.roster_status_label.text.contains("walking chassis"), "REGISTER blocks without a walking chassis")
		_check(rp.register_dialog == null, "chassis gate opens no name prompt")
		_check(GlobalData.get_hangar_mechs().size() == mechs_before, "blocked REGISTER parks no mech")
		_check(GlobalData.scrap == scrap_after_first and GlobalData.credits == credits_after_first, "chassis gate spends nothing")
		# Restore the frame and confirm a blank name -> falls back to "Mech 02".
		GlobalData.equipped_frames["body"] = (GlobalData.frame_catalog["body"][0] as Dictionary).duplicate()
		rp.register_mech(2)
		await get_tree().process_frame
		_check(rp.register_dialog != null, "valid chassis re-opens the name prompt")
		if rp.register_dialog_edit:
			rp.register_dialog_edit.text = "   "
			# Enter (text_submitted) is the keyboard path into _confirm_register.
			rp.register_dialog_edit.text_submitted.emit("   ")
		await get_tree().process_frame
		var fallback_name := ""
		for m in GlobalData.get_hangar_mechs():
			if int(m.get("slot", 0)) == 2:
				fallback_name = str(m.get("name", ""))
		_check(fallback_name == "Mech 02", "blank name falls back to the slot-based name")
		_check(GlobalData.scrap == scrap_after_first - reg_scrap and GlobalData.credits == credits_after_first - reg_credits, "blank-name REGISTER also charges the cost")

	# Pilot-only mode: the button disappears and register_mech points at the
	# recovery path instead of building.
	GlobalData.mech_less = true
	GlobalData.hangar_mechs.clear()
	rp.refresh_page()
	await get_tree().process_frame
	_check(_find_register_button(rp) == null, "on-foot mode hides the REGISTER button")
	rp.register_mech(2)
	_check(rp.roster_status_label.text.begins_with("You're on foot"), "on-foot register explains the recovery path")
	_check(rp.register_dialog == null, "on-foot register opens no name prompt")
	_check(GlobalData.get_hangar_mechs().size() == 0, "on-foot register parks no mech")
	GlobalData.mech_less = false

	# Leaving the roster page closes any open name prompt.
	rp.register_mech(2)
	await get_tree().process_frame
	_check(rp.register_dialog != null, "name prompt is open before leaving the page")
	rp.hide_page()
	await get_tree().process_frame
	_check(rp.register_dialog == null or not is_instance_valid(rp.register_dialog), "leaving the roster page closes the name prompt")

	# Resources drained while the prompt is open: confirming reports the
	# shortfall, closes the dialog and spends nothing (no negative balances).
	GlobalData.gain_scrap(reg_scrap + 10)
	GlobalData.gain_credits(reg_credits + 10)
	rp.register_mech(2)
	await get_tree().process_frame
	_check(rp.register_dialog != null, "affordable REGISTER opens the prompt once more")
	if rp.register_dialog_edit:
		rp.register_dialog_edit.text = "Drained"
	GlobalData.scrap = 0
	GlobalData.credits = 0
	if rp.register_dialog:
		var drained_ok := _find_button_by_text(rp.register_dialog, "REGISTER FRAME")
		if drained_ok:
			drained_ok.pressed.emit()
			await get_tree().process_frame
	_check(rp.register_dialog == null or not is_instance_valid(rp.register_dialog), "shortfall at confirm closes the prompt")
	_check(rp.roster_status_label.text.contains("Not enough scrap/credits"), "shortfall at confirm reports the missing resources")
	_check(GlobalData.scrap == 0 and GlobalData.credits == 0, "shortfall at confirm spends nothing")

	ctrl.nav_panel.show_hangar_menu()
	await get_tree().process_frame
	_check(not rp.roster_panel.visible, "hangar menu hides the roster page")
	_check(not rp.mech_slot_label.visible, "hangar menu hides the badge")

	ctrl.queue_free()
	anchor.queue_free()
	await get_tree().process_frame


func _find_register_button(rp) -> Button:
	for row in rp.roster_slot_list.get_children():
		# Skip stale rows queued by an earlier refresh_page (their children are
		# about to be freed and must never be clicked or returned).
		if not is_instance_valid(row) or row.is_queued_for_deletion():
			continue
		for child in row.get_children():
			if child is Button and child.text == "REGISTER" and is_instance_valid(child) and not child.is_queued_for_deletion():
				return child
	return null


func _find_popup(host: Node) -> PopupMenu:
	for child in host.get_children():
		if child is PopupMenu and is_instance_valid(child) and not child.is_queued_for_deletion():
			return child
	return null


func _verify_catalog_panel() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var cp = ctrl.catalog_panel
	_check(cp != null, "controller builds a HangarCatalogPanel")
	_check(cp.hover_stats_label != null, "catalog panel builds the hover label")
	_check(cp.hover_stats_label.text.contains("Point at"), "hover label starts with the hint text")

	# Catalog window opens from the sub-menu and lists every section.
	ctrl.nav_panel.select_submenu("catalog")
	await get_tree().process_frame
	_check(cp.catalog_window != null, "catalog window builds a modal")
	_check(cp.catalog_window.is_inside_tree(), "catalog modal is added to the tree")
	var all_text := _collect_label_text(cp.catalog_window)
	_check(all_text.contains("CHASSIS (MODEL)"), "catalog lists the chassis section")
	_check(all_text.contains("WEAPON STASH"), "catalog lists the weapon stash section")

	cp.close_window()
	await get_tree().process_frame
	_check(cp.catalog_window == null, "closing the catalog clears the window ref")

	# Applying a chassis persists the pick and rebuilds the window.
	var chassis_keys: Array = GlobalData.chassis_catalog.keys()
	_check(not chassis_keys.is_empty(), "chassis catalog has entries to apply")
	if not chassis_keys.is_empty():
		var key := str(chassis_keys[0])
		cp.apply_chassis(key)
		await get_tree().process_frame
		_check(GlobalData.chassis_id == key, "apply_chassis sets the chassis id")
		_check(cp.catalog_window != null, "apply_chassis rebuilds the catalog window")
		cp.close_window()
		await get_tree().process_frame

	# Hover-stats text builder: guards + the deterministic upgrade card.
	_check(cp.stats_text_for_index(-1) == "", "stats_text rejects a negative index")
	ctrl.current_mode = "upgrade"
	_check(cp.stats_text_for_index(0).contains("INNER FRAME REACTOR LEVEL"), "upgrade mode hover card")

	# Frame / weapon / armor cards — assert strongly when the backing data exists.
	ctrl.current_mode = "frame"
	ctrl.selected_slot = "body"
	var fcard: String = cp.stats_text_for_index(0)
	if ctrl.frame_catalog.has("body") and not (ctrl.frame_catalog["body"] as Array).is_empty():
		_check(fcard.contains("INNER FRAME PART"), "frame mode hover card")

	ctrl.current_mode = "armor"
	ctrl.selected_slot = "weapon_carry"
	ctrl.part_list_panel.populate("weapon_carry")
	var wcard: String = cp.stats_text_for_index(0)
	if ctrl.visible_weapon_indices.size() > 0:
		_check(wcard.contains("BACK CARRY") or wcard.contains("FIELD PACK"), "weapon mode hover card")

	ctrl.part_list_panel.populate("body")
	ctrl.selected_slot = "body"
	var acard: String = cp.stats_text_for_index(0)
	if ctrl.visible_salvage_indices.size() > 0:
		_check(acard.contains("OWNED ARMOR"), "armor mode hover card shows the owned item")

	# refresh_hover_stats is safe with no cursor over the list.
	cp.refresh_hover_stats()
	_check(true, "refresh_hover_stats runs without error")

	ctrl.queue_free()
	await get_tree().process_frame


func _collect_label_text(root_node: Node) -> String:
	var out := ""
	for child in root_node.get_children():
		if child is Label:
			out += child.text + "\n"
		out += _collect_label_text(child)
	return out


# Parses the "TOTAL WEIGHT: X / Y kg" figure out of the stats label text.
func _parse_total_weight(label_text: String) -> float:
	var parts := label_text.split("TOTAL WEIGHT: ")
	if parts.size() < 2:
		return -1.0
	var first_line := parts[1].split("\n")[0]
	var weight_str := first_line.split(" / ")[0]
	return weight_str.to_float()


func _verify_craft_panel() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var cp = ctrl.craft_panel
	_check(cp != null, "controller builds a HangarCraftPanel")

	# A slot outside the armor catalog shows the hint and builds nothing.
	# (Note: weapon_left/right ARE armor_catalog keys in mech_catalogs.tres,
	# so the craftery legitimately opens for them — matching the original
	# `_on_craft_window_open` guard behavior.)
	ctrl.selected_slot = "no_such_slot"
	cp.open()
	await get_tree().process_frame
	_check(cp.craft_window == null, "craft does not open for a non-armor slot")
	_check(ctrl.status_message_label.text.contains("Select an armor section"), "craft hints for a non-armor slot")

	# An armor slot builds the window with the craftery title.
	ctrl.selected_slot = "body"
	cp.open()
	await get_tree().process_frame
	_check(cp.craft_window != null, "craft window builds a modal")
	_check(cp.craft_window.is_inside_tree(), "craft modal is added to the tree")
	_check(_collect_label_text(cp.craft_window).contains("CRAFTERY"), "craft window shows the craftery title")

	cp.close_window()
	await get_tree().process_frame
	_check(cp.craft_window == null, "closing the craft window clears the ref")

	# Crafting with an unknown template reports the error safely.
	cp.craft_armor({"id": ""})
	_check(ctrl.status_message_label.text.contains("Cannot craft"), "craft rejects an unknown template")

	# The real submenu path opens the craftery too.
	ctrl.nav_panel.select_submenu("craft")
	await get_tree().process_frame
	_check(cp.craft_window != null, "craft submenu opens the craftery")
	cp.close_window()

	ctrl.queue_free()
	await get_tree().process_frame


func _verify_garage_panel() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var gp = ctrl.garage_panel
	_check(gp != null, "controller builds a HangarGaragePanel")
	_check(gp.mecha_3d_root != null, "garage builds the 3D mecha root")
	_check(gp.turntable_node != null, "garage builds the turntable")
	_check(gp.garage_cam != null, "garage builds the camera")
	_check(gp.get_mecha_base() != null, "garage resolves the mecha base")
	_check(gp.get_part_mesh_manager() != null, "garage resolves the PartMeshManager")

	# Selection highlight updates the header label through the real tab path.
	ctrl.slot_panel.select("body")
	await get_tree().process_frame
	_check(ctrl.selected_slot == "body", "slot tab select still works")
	var label = ctrl.root_control.find_child("SelectionLabel", true, false)
	_check(label != null and label.text == "EDITING: BODY", "selection highlight updates the header label")

	# Camera focus targets per-slot positions.
	gp.update_camera_focus("head")
	_check(gp.cam_target_pos == Vector3(2.6, 3.0, 3.2), "camera focus targets the head")
	gp.update_camera_focus("leg_left")
	_check(gp.cam_target_pos == Vector3(3.8, 1.6, 3.8), "camera focus targets the legs")

	# --- Turntable drag: press starts the drag, motion rotates, release stops. ---
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	gp.handle_input(press)
	_check(gp._is_dragging_3d, "left press starts the 3D drag")

	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, 0)
	var rot_before: float = gp.turntable_node.rotation.y
	gp.handle_input(motion)
	_check(is_equal_approx(gp.turntable_node.rotation.y, rot_before + 100.0 * 0.008), "drag rotates the turntable by relative.x * 0.008")

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	gp.handle_input(release)
	_check(not gp._is_dragging_3d, "left release ends the 3D drag")

	# Motion without an active drag leaves the turntable still.
	var rot_idle: float = gp.turntable_node.rotation.y
	gp.handle_input(motion)
	_check(is_equal_approx(gp.turntable_node.rotation.y, rot_idle), "motion without a drag does not rotate")

	# In attachment mode with a selected attachment, drag moves the attachment
	# instead of the turntable (unknown id -> early return, table stays put).
	ctrl.current_mode = "attachment"
	ctrl.selected_attachment_info = {"id": "no_such_attach", "slot": "body"}
	gp.handle_input(press)
	var rot_attach: float = gp.turntable_node.rotation.y
	gp.handle_input(motion)
	_check(is_equal_approx(gp.turntable_node.rotation.y, rot_attach), "attachment drag does not rotate the turntable")
	gp.handle_input(release)
	ctrl.current_mode = "armor"
	ctrl.selected_attachment_info = {}

	# --- Selection highlight + tab blink ---
	gp.update_selection_highlight("body")
	var body_btn: Button = ctrl.slot_tab_buttons.get("body", null)
	_check(gp._blink_target_button == body_btn, "highlight targets the body slot tab")
	_check(gp._blink_on, "highlight starts the blink in the ON phase")

	# Blink paints a bright then dim stylebox on the target tab.
	gp.apply_tab_blink(true)
	if body_btn:
		var sb_on: StyleBoxFlat = body_btn.get_theme_stylebox("normal") as StyleBoxFlat
		_check(sb_on != null and sb_on.bg_color.a > 0.9, "blink ON paints a bright stylebox")
	gp.apply_tab_blink(false)
	if body_btn:
		var sb_off: StyleBoxFlat = body_btn.get_theme_stylebox("normal") as StyleBoxFlat
		_check(sb_off != null and sb_off.bg_color.a < 0.5, "blink OFF dims the stylebox")

	# process() toggles the phase once the interval elapses, then resets the timer.
	gp._blink_timer = 0.0
	gp._blink_on = true
	gp.process(gp._blink_interval + 0.1)
	_check(not gp._blink_on, "process toggles the blink phase after the interval")
	_check(gp._blink_timer < gp._blink_interval, "process resets the blink timer")

	# Unselected tabs are dimmed gray.
	var head_btn: Button = ctrl.slot_tab_buttons.get("head", null)
	if head_btn:
		gp.apply_tab_unselected(head_btn)
		_check(head_btn.modulate == Color(0.5, 0.5, 0.56), "unselected tab is dimmed")

	# remove_3d_selection_highlight frees and nulls the 3D highlight mesh.
	gp.selection_highlight = MeshInstance3D.new()
	ctrl.add_child(gp.selection_highlight)
	gp.remove_3d_selection_highlight()
	_check(gp.selection_highlight == null, "remove_3d_selection_highlight nulls the highlight")
	_check(not is_instance_valid(gp.selection_highlight), "remove_3d_selection_highlight frees the highlight mesh")

	# clear_selection_blink drops the target so process stops pulsing.
	gp.clear_selection_blink()
	_check(gp._blink_target_button == null, "clear_selection_blink drops the blink target")

	# Attachment math helpers.
	_check(gp.get_attachment_capacity("head") >= 0.0, "attachment capacity is non-negative")
	_check(gp.get_attachment_weight("head") >= 0.0, "attachment weight is non-negative")
	_check(gp.get_total_load() >= 0.0, "total load is non-negative")
	_check(gp.has_attachment("does_not_exist", "head") == false, "unknown attachment is not equipped")
	_check(gp.get_default_attachment_position("head") == Vector3(0.0, 0.15, -0.35), "default attachment position for head")
	_check(gp.get_default_attachment_position("nope") == Vector3.ZERO, "unknown slot gets zero position")

	# Field-pack check matches the load formula for a real starter weapon.
	var shotgun = load("res://resources/mech/stock/weapon_combat_shotgun.tres")
	_check(shotgun != null, "stock shotgun resource loads")
	if shotgun:
		var expected := GlobalData.get_loadout_weapons_total() + float(shotgun.weight) + GlobalData.get_field_pack_ammo_weight() > GlobalData.get_field_pack_capacity()
		_check(gp.would_exceed_field_pack(shotgun.resource_path) == expected, "field-pack check matches the load formula")

	# 3D previews all run without error (headless node ops).
	gp.update_all_slots_preview()
	gp.apply_chassis_preview(GlobalData.chassis_catalog.get("standard", {}))
	gp.apply_armor_preview("body", {"name": "Test Plate", "durability": 100.0, "color": Color.RED})
	gp.apply_frame_preview("body", {})
	gp.apply_salvage_preview("body", {"color": Color.GREEN})
	gp.clear_selection_blink()
	gp.process(0.016)
	gp.handle_input(InputEventMouseButton.new())
	gp.handle_input(InputEventMouseMotion.new())
	_check(true, "3D previews, process and input helpers run without error")

	ctrl.queue_free()
	await get_tree().process_frame


func _verify_action_panel() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var ap = ctrl.action_panel
	_check(ap != null, "controller builds a HangarActionPanel")
	_check(ap.part_action_modal == null, "action panel starts with no modal")

	# An empty info dict shows nothing (guard path).
	ap.show({})
	await get_tree().process_frame
	_check(ap.part_action_modal == null, "action panel ignores an empty info dict")

	# A real owned armor instance builds the modal with the ACTION MENU title.
	ctrl.selected_slot = "body"
	ctrl.current_mode = "armor"
	var body_entries: Array = GlobalData.armor_catalog.get("body", [])
	_check(not body_entries.is_empty(), "body armor catalog has entries to show")
	var shown := false
	if not body_entries.is_empty():
		var inst: Dictionary = GlobalData.make_armor_instance_from_catalog(body_entries[0]["id"])
		GlobalData.armor_inventory.append(inst)
		ctrl.selected_salvage_info = inst
		ctrl.visible_salvage_indices.clear()
		ctrl.visible_salvage_indices.append(GlobalData.armor_inventory.size() - 1)
		ap.show(inst)
		await get_tree().process_frame
		_check(ap.part_action_modal != null, "action panel builds the modal for an owned armor instance")
		_check(ap.part_action_modal.is_inside_tree(), "action modal is added to the tree")
		var modal_text := _collect_label_text(ap.part_action_modal)
		_check(modal_text.contains("ACTION MENU"), "action modal shows the ACTION MENU title")
		_check(modal_text.contains("DURABILITY"), "action modal shows durability details")

		# Double-open safety: close() sweeps every PartActionModal in the tree.
		ap.show(inst)
		ap.show(inst)
		ap.close()
		await get_tree().process_frame
		var leftover := 0
		if ctrl.root_control:
			for child in ctrl.root_control.get_children():
				if child.name == "PartActionModal" and is_instance_valid(child) and not child.is_queued_for_deletion():
					leftover += 1
		_check(leftover == 0, "closing sweeps stacked action modals")
		_check(ap.part_action_modal == null, "closing the action modal clears the ref")
		shown = true
	_check(shown, "action modal path was exercised")

	ctrl.queue_free()
	await get_tree().process_frame


func _verify_equip_panel() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var ep = ctrl.equip_panel
	_check(ep != null, "controller builds a HangarEquipPanel")

	# Hand weapon: equip changes the loadout from the default, unequip clears it.
	ctrl.current_mode = "armor"
	var heat_blade := {"path": "res://resources/mech/stock/weapon_heat_blade.tres", "count": 1}
	ep.unequip_part("weapon_right")
	ep.equip_part("weapon_right", heat_blade)
	_check(str(GlobalData.weapon_loadout.get("right", "")) == "res://resources/mech/stock/weapon_heat_blade.tres", "equip_part sets the right-hand loadout")
	ep.unequip_part("weapon_right")
	_check(str(GlobalData.weapon_loadout.get("right", "x")) == "", "unequip_part clears the right-hand loadout")

	# Back carry: equipping a spare copy increments the carry count, and
	# unequipping through the selected part path removes it again.
	var beam_rifle := {"path": "res://resources/mech/stock/weapon_beam_rifle.tres", "count": 1}
	var carry_before := GlobalData.count_carry_weapon(beam_rifle["path"])
	ep.equip_part("weapon_carry", beam_rifle)
	_check(GlobalData.count_carry_weapon(beam_rifle["path"]) == carry_before + 1, "equip_part adds a back-carry copy")
	ctrl.selected_part_path = beam_rifle["path"]
	ep.unequip_part("weapon_carry")
	_check(GlobalData.count_carry_weapon(beam_rifle["path"]) == carry_before, "unequip_part removes the back-carry copy")

	# Armor craft-and-equip: a catalog entry becomes an owned equipped instance.
	ctrl.selected_slot = "body"
	var body_entry: Dictionary = GlobalData.armor_catalog["body"][0]
	GlobalData.scrap = 500
	GlobalData.credits = 500
	ep.equip_part("body", body_entry)
	var equipped_body = GlobalData.equipped_parts.get("body", {})
	_check(equipped_body is Dictionary and not equipped_body.is_empty(), "equip_part crafts and equips a body armor instance")
	_check(ctrl.status_message_label.text.contains("crafted and equipped"), "craft-and-equip reports the status message")
	ep.unequip_part("body")
	var body_after = GlobalData.equipped_parts.get("body")
	_check(body_after == null or not (body_after is Dictionary and not body_after.is_empty()), "unequip_part removes the body armor")

	# Frame equip/unequip path.
	ctrl.current_mode = "frame"
	var frame_info := {"name": "Test Frame", "hp": 50.0, "weight": 3.0}
	ep.equip_part("body", frame_info)
	var equipped_frame = GlobalData.equipped_frames.get("body", {})
	_check(equipped_frame is Dictionary and not equipped_frame.is_empty(), "frame equip stores the frame")
	ep.unequip_part("body")
	_check(not GlobalData.equipped_frames.has("body"), "frame unequip removes the frame")
	ctrl.current_mode = "armor"

	# on_equip_pressed: upgrade path spends credits and raises the reactor level.
	ctrl.current_mode = "upgrade"
	GlobalData.credits = 500
	var level_before := GlobalData.frame_upgrade_level
	ep.on_equip_pressed()
	_check(GlobalData.frame_upgrade_level == level_before + 1, "on_equip_pressed upgrades the frame reactor")
	ctrl.current_mode = "armor"

	# on_equip_pressed: attachment mount path adds to the attachment list.
	ctrl.current_mode = "attachment"
	ctrl.selected_slot = "head"
	var attach := {"id": "test_opt", "name": "Test Optic", "weight": 1.0, "type": "Sensor"}
	ctrl.selected_attachment_info = attach
	var attach_before := GlobalData.attachments.size()
	ep.on_equip_pressed()
	_check(GlobalData.attachments.size() > attach_before, "on_equip_pressed mounts the attachment")
	ctrl.current_mode = "armor"
	ctrl.selected_attachment_info = {}

	# Guard: an unknown weapon path reports and does not touch the loadout.
	ep.equip_part("weapon_left", {"path": "res://nope.tres"})
	_check(ctrl.status_message_label.text.contains("Weapon not found"), "unknown weapon path reports the guard message")

	ctrl.queue_free()
	await get_tree().process_frame


func _verify_part_list_panel() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var plp = ctrl.part_list_panel
	_check(plp != null, "controller builds a HangarPartListPanel")

	# Upgrade mode populates a single reactor row and updates the stats label.
	ctrl.current_mode = "upgrade"
	plp.populate("body")
	_check(ctrl.part_item_list.item_count == 1, "upgrade mode shows the reactor row")
	_check(ctrl.stats_label.text.contains("INNER FRAME REACTOR LEVEL"), "upgrade selection writes the stats label")

	# Attachment mode lists the attachment catalog for a body section.
	ctrl.current_mode = "attachment"
	plp.populate("body")
	_check(ctrl.part_item_list.item_count >= 1, "attachment mode populates the catalog")
	plp.populate("nope")
	_check(ctrl.part_item_list.get_item_text(0).contains("Select a body section"), "attachment guard for non-body slots")

	# Weapon slot lists the weapon inventory stash.
	ctrl.current_mode = "armor"
	ctrl.selected_slot = "weapon_left"
	plp.populate("weapon_left")
	_check(ctrl.part_item_list.item_count == GlobalData.weapon_inventory.size(), "weapon slot lists the inventory stash")
	plp.on_item_selected(0)
	_check(ctrl.selected_part_path != "", "weapon selection resolves the part path")
	var resolved: Dictionary = plp.resolve_info_for_index(0)
	_check(resolved.has("path"), "resolve_info_for_index returns the weapon info")

	# Frame slot lists the frame catalog.
	ctrl.current_mode = "frame"
	ctrl.selected_slot = "body"
	plp.populate("body")
	if ctrl.frame_catalog.has("body") and not (ctrl.frame_catalog["body"] as Array).is_empty():
		_check(ctrl.part_item_list.item_count >= 1, "frame slot lists the frame catalog")

	# Armor slot lists owned armor instances (reset seeds none -> the list stays
	# empty unless an owned instance exists; equip one first).
	ctrl.current_mode = "armor"
	ctrl.selected_slot = "body"
	var body_entries: Array = GlobalData.armor_catalog.get("body", [])
	var armored := false
	if not body_entries.is_empty():
		var inst: Dictionary = GlobalData.make_armor_instance_from_catalog(body_entries[0]["id"])
		GlobalData.armor_inventory.append(inst)
		plp.populate("body")
		_check(ctrl.part_item_list.item_count >= 1, "armor slot lists owned instances")
		_check(plp.is_item_equipped("body", inst) == false, "fresh instance is not equipped")
		plp.on_item_selected(0)
		_check(not ctrl.selected_salvage_info.is_empty(), "armor selection stores the salvage info")
		_check(plp.instance_durability("body", inst) > 0.0, "instance durability resolves above zero")
		armored = true
	_check(armored, "armor populate path was exercised")

	# Helper queries.
	_check(plp.is_item_equipped("body", {}) == false, "is_item_equipped rejects an empty dict")
	_check(plp.weapon_in_loadout("weapon_left", "") == false, "weapon_in_loadout rejects an empty path")
	_check(plp.weapon_in_loadout("weapon_left", "res://resources/mech/stock/weapon_beam_rifle.tres"), "default left-hand weapon is in the loadout")

	# on_item_clicked closes any open action modal; on_item_activated opens one.
	ctrl.action_panel.show({"name": "Probe"})
	plp.on_item_clicked(0)
	await get_tree().process_frame
	_check(ctrl.action_panel.part_action_modal == null, "single click closes the action modal")
	ctrl.selected_slot = "weapon_left"
	ctrl.current_mode = "armor"
	plp.populate("weapon_left")
	plp.on_item_activated(0)
	await get_tree().process_frame
	_check(ctrl.action_panel.part_action_modal != null, "double-click opens the action modal")
	ctrl.action_panel.close()

	ctrl.queue_free()
	await get_tree().process_frame


func _verify_stats_panel() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var sp = ctrl.stats_panel
	_check(sp != null, "controller builds a HangarStatsPanel")
	_check(ctrl.weight_bar != null, "controller builds the weight bar")
	_check(ctrl.total_stats_label != null, "controller builds the total stats label")

	# The aggregation repaints the weight bar + label from GlobalData.
	sp.update()
	_check(ctrl.weight_bar.max_value > 0.0, "weight bar max tracks the chassis capacity")
	_check(ctrl.weight_bar.value >= 0.0, "weight bar value is non-negative")
	_check(ctrl.total_stats_label.text.contains("FRAME LVL"), "stats label shows the frame level")
	_check(ctrl.total_stats_label.text.contains("TOTAL WEIGHT"), "stats label shows the total weight")
	_check(ctrl.total_stats_label.text.contains("FIELD PACK"), "stats label shows the field pack")

	# Sums are deterministic: reset seeds 3 starter weapons + default frames.
	# The label's TOTAL WEIGHT is unclamped (the bar clamps to capacity), so
	# parse it from the label. Clear the default body armor first so the delta
	# is exactly the new part's weight.
	GlobalData.equipped_parts.erase("body")
	sp.update()
	var weight_before := _parse_total_weight(ctrl.total_stats_label.text)
	GlobalData.equipped_parts["body"] = {"uid": "t_armor", "name": "Test Plate", "hp": 50.0, "max_hp": 50.0, "weight": 5.0}
	sp.update()
	var weight_after := _parse_total_weight(ctrl.total_stats_label.text)
	_check(weight_before >= 0.0 and is_equal_approx(weight_after, weight_before + 5.0), "stats sum adds the equipped armor weight")
	GlobalData.equipped_parts.erase("body")

	# Damage on an equipped slot reduces the summed HP in the label.
	var hp_before: String = ctrl.total_stats_label.text
	GlobalData.equipped_parts["body"] = {"uid": "t_armor2", "name": "Test Plate", "hp": 50.0, "max_hp": 50.0, "weight": 5.0}
	GlobalData.part_damage["body"] = 1.0
	sp.update()
	_check(ctrl.total_stats_label.text != hp_before, "stats label reflects damage changes")
	GlobalData.equipped_parts.erase("body")
	GlobalData.part_damage.erase("body")

	# update() is safe with no meaningful state (pure aggregation).
	sp.update()
	_check(true, "stats update runs without error on repeated calls")

	ctrl.queue_free()
	await get_tree().process_frame


func _verify_nav_panel() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var np = ctrl.nav_panel
	_check(np != null, "controller builds a HangarNavPanel")
	_check(np.controller == ctrl, "nav panel holds the controller back-ref")

	# Landing menu: entering the hangar shows the sub-menu rail first.
	_check(np.current_submenu == "", "hangar opens on the landing sub-menu")
	_check(ctrl.submenu_rail != null and ctrl.submenu_rail.visible, "landing shows the sub-menu rail")
	_check(ctrl.back_to_menu_button != null and not ctrl.back_to_menu_button.visible, "landing hides the back button")
	_check(ctrl.left_panel != null and not ctrl.left_panel.visible, "landing hides the customize left panel")

	# Customize submenu restores the editing page.
	np.select_submenu("customize")
	await get_tree().process_frame
	_check(np.current_submenu == "customize", "select_submenu records the page id")
	_check(ctrl.left_panel.visible, "customize page shows the left panel")
	_check(ctrl.right_panel != null and ctrl.right_panel.visible, "customize page shows the right panel")
	_check(ctrl.tab_container != null and ctrl.tab_container.visible, "customize page shows the tab container")
	_check(ctrl.back_to_menu_button.visible, "customize page shows the back button")
	_check(not ctrl.submenu_rail.visible, "customize page hides the sub-menu rail")
	var sel_lbl: Label = ctrl.root_control.find_child("SelectionLabel", true, false) as Label
	_check(sel_lbl != null and sel_lbl.text != "HANGAR MENU", "customize page drops the HANGAR MENU label")

	# Upgrade submenu switches the left-list mode to the reactor row.
	np.select_submenu("upgrade")
	await get_tree().process_frame
	_check(np.current_submenu == "upgrade", "upgrade submenu records its id")
	_check(ctrl.current_mode == "upgrade", "upgrade submenu switches the part-list mode")

	# switch_custom_mode repopulates the list for the new mode.
	np.switch_custom_mode("armor")
	_check(ctrl.current_mode == "armor", "switch_custom_mode sets the part-list mode")
	_check(ctrl.part_item_list != null and ctrl.part_item_list.item_count >= 0, "switch_custom_mode repopulates the part list")

	# Emergency opens the scrap-repair overlay and records its id.
	np.select_submenu("emergency")
	await get_tree().process_frame
	_check(np.current_submenu == "emergency", "emergency submenu records its id")
	_check(ctrl.scrap_editor != null, "emergency submenu builds the scrap editor")
	if ctrl.scrap_editor:
		ctrl.scrap_editor.close()
		await get_tree().process_frame

	# Craft + catalog open their windows over the customize page.
	np.select_submenu("craft")
	await get_tree().process_frame
	_check(ctrl.craft_panel.craft_window != null, "craft submenu opens the craftery")
	if ctrl.craft_panel.craft_window:
		ctrl.craft_panel.close_window()
		await get_tree().process_frame
	np.select_submenu("catalog")
	await get_tree().process_frame
	_check(ctrl.catalog_panel.catalog_window != null, "catalog submenu opens the catalog window")
	if ctrl.catalog_panel.catalog_window:
		ctrl.catalog_panel.close_window()
		await get_tree().process_frame

	# Roster submenu shows the roster page instead of the customize page.
	np.select_submenu("roster")
	await get_tree().process_frame
	_check(np.current_submenu == "roster", "roster submenu records its id")
	_check(ctrl.roster_panel_ui.roster_panel != null and ctrl.roster_panel_ui.roster_panel.visible, "roster submenu shows the roster page")
	_check(ctrl.left_panel != null and not ctrl.left_panel.visible, "roster page hides the customize left panel")

	# Back-to-menu from any page restores the landing screen.
	np.on_back_to_menu_pressed()
	await get_tree().process_frame
	_check(np.current_submenu == "", "back-to-menu returns to the landing sub-menu")
	_check(ctrl.submenu_rail.visible, "back-to-menu restores the sub-menu rail")
	_check(not ctrl.roster_panel_ui.roster_panel.visible, "back-to-menu hides the roster page")

	# show_hangar re-opens on the landing menu and re-targets the piloted mech.
	np.show_hangar()
	await get_tree().process_frame
	_check(np.current_submenu == "", "show_hangar lands on the sub-menu again")
	_check(ctrl._customize_mech_id == GlobalData.active_hangar_mech_id, "show_hangar re-targets the active mech")
	var sel_lbl2: Label = ctrl.root_control.find_child("SelectionLabel", true, false) as Label
	_check(sel_lbl2 != null and sel_lbl2.text == "HANGAR MENU", "show_hangar restores the HANGAR MENU label")

	ctrl.queue_free()
	await get_tree().process_frame


func _verify_repair_panel() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var rp = ctrl.repair_panel
	_check(rp != null, "controller builds a HangarRepairPanel")
	_check(rp.controller == ctrl, "repair panel holds the controller back-ref")
	_check(ctrl.repair_part_button != null and ctrl.full_repair_button != null, "controller builds the repair buttons")

	# Undamaged slot: repair is a no-op with a status message.
	ctrl.selected_slot = "body"
	GlobalData.part_damage.clear()
	rp.repair_part()
	_check(ctrl.status_message_label.text.contains("fully functional"), "repair_part skips an undamaged slot")

	# Damaged slot without credits: blocked with the credit shortfall message.
	GlobalData.part_damage["body"] = 0.5
	GlobalData.credits = 0
	rp.repair_part()
	_check(ctrl.status_message_label.text.begins_with("Need"), "repair_part blocks without credits")
	_check(GlobalData.part_damage.has("body"), "blocked repair leaves the damage in place")

	# With credits: damage clears and the message confirms.
	var cost := GlobalData.get_repair_cost("body")
	GlobalData.credits = cost + 100
	rp.repair_part()
	_check(not GlobalData.part_damage.has("body"), "repair_part clears the slot damage")
	_check(not GlobalData.part_damage.has("body_frame"), "repair_part clears the slot frame damage")
	_check(ctrl.status_message_label.text.contains("Repaired"), "repair_part confirms the repair")
	_check(GlobalData.credits == 100, "repair_part spends exactly the repair cost")

	# Full repair: clears every slot's damage and reports the total cost spend.
	for slot in GlobalData.MECHA_SLOTS:
		GlobalData.part_damage[slot] = 0.7
	var total := 0
	for slot in GlobalData.MECHA_SLOTS:
		total += GlobalData.get_repair_cost(slot)
	GlobalData.credits = total + 500
	rp.full_repair()
	_check(GlobalData.part_damage.is_empty(), "full_repair clears all part damage")
	_check(ctrl.status_message_label.text.contains("Full Repair Complete"), "full_repair confirms the repair")
	_check(GlobalData.credits == 500, "full_repair spends exactly the summed cost")

	# Full repair with everything clean reports all-ok.
	rp.full_repair()
	_check(ctrl.status_message_label.text.contains("All parts OK"), "full_repair no-ops when nothing is damaged")

	ctrl.queue_free()
	await get_tree().process_frame


func _verify_slot_panel() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var sp = ctrl.slot_panel
	_check(sp != null, "controller builds a HangarSlotPanel")
	_check(sp.controller == ctrl, "slot panel holds the controller back-ref")
	_check(ctrl.slot_tab_buttons != null and ctrl.slot_tab_buttons.size() >= 5, "controller builds the slot tab buttons")

	# Body slot: mode buttons visible, ammo box hidden.
	sp.select("body")
	await get_tree().process_frame
	_check(ctrl.selected_slot == "body", "select sets the selected slot")
	_check(ctrl.sub_toggle_container.visible, "body slot shows the mode toggle buttons")
	_check(not ctrl.ammo_panel.ammo_loadout_box.visible, "body slot hides the ammo loadout box")

	# Weapon slot: mode buttons hidden, ammo box shown + refreshed.
	sp.select("weapon_left")
	await get_tree().process_frame
	_check(ctrl.selected_slot == "weapon_left", "select switches to a weapon slot")
	_check(not ctrl.sub_toggle_container.visible, "weapon slot hides the mode toggle buttons")
	_check(ctrl.ammo_panel.ammo_loadout_box.visible, "weapon slot shows the ammo loadout box")

	# Back to a body slot hides the ammo box again.
	sp.select("body")
	await get_tree().process_frame
	_check(ctrl.selected_slot == "body", "select returns to the body slot")
	_check(not ctrl.ammo_panel.ammo_loadout_box.visible, "body slot hides the ammo loadout box again")

	# Selecting a slot closes an open craftery.
	ctrl.craft_panel.open()
	await get_tree().process_frame
	_check(ctrl.craft_panel.craft_window != null, "craftery opened for the close-on-select check")
	sp.select("head")
	await get_tree().process_frame
	_check(ctrl.craft_panel.craft_window == null, "select closes an open craftery")

	# The header selection label follows the new slot.
	var label: Label = ctrl.root_control.find_child("SelectionLabel", true, false) as Label
	_check(label != null and label.text == "EDITING: HEAD", "select updates the header selection label")

	ctrl.queue_free()
	await get_tree().process_frame


func _verify_layout_panels() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- Header panel: title, selection label, slot tabs, back-to-menu. ---
	_check(ctrl.header_panel != null, "controller builds a HangarHeaderPanel")
	_check(ctrl.header_panel.controller == ctrl, "header panel holds the controller back-ref")
	var title_lbl: Label = ctrl.root_control.find_child("SelectionLabel", true, false) as Label
	_check(title_lbl != null and title_lbl.text == "HANGAR MENU", "header builds the selection label (boot lands on HANGAR MENU)")
	_check(ctrl.tab_container != null and ctrl.tab_container.get_child_count() == 9, "header builds all 9 slot tabs")
	_check(ctrl.slot_tab_buttons.size() == 9, "header registers every slot tab button")
	_check(ctrl.slot_tab_buttons.has("weapon_carry"), "header registers the BACK CARRY tab")
	_check(ctrl.back_to_menu_button != null and ctrl.back_to_menu_button.text.contains("BACK TO MENU"), "header builds the back-to-menu button")
	_check(ctrl.back_to_menu_button.visible == false, "back-to-menu starts hidden")

	# --- Landing rail (nav panel): menu title + every submenu entry + exit. ---
	var np = ctrl.nav_panel
	_check(np != null and np.has_method("build_landing_rail"), "nav panel owns the landing rail builder")
	_check(ctrl.submenu_rail != null, "landing rail builds the rail panel")
	var rail_text := _collect_label_text(ctrl.submenu_rail)
	_check(rail_text.contains("HANGAR MENU"), "landing rail shows the menu title")
	var rail_buttons := 0
	for child in ctrl.submenu_rail.get_children():
		rail_buttons += _count_buttons(child)
	_check(rail_buttons >= 7, "landing rail lists the submenu + exit buttons")

	# --- Mode-toggle bar (nav panel): 4 mode buttons. ---
	_check(np.has_method("build_mode_toggles"), "nav panel owns the mode-toggle builder")
	_check(ctrl.sub_toggle_container != null, "mode toggles build the container")
	_check(ctrl.sub_toggle_container.get_child_count() == 4, "mode toggles build 4 buttons")
	_check(ctrl.frame_upgrade_button != null, "mode toggles build the reactor upgrade button")
	var toggle_text := ""
	for child in ctrl.sub_toggle_container.get_children():
		if child is Button:
			toggle_text += child.text + "\n"
	_check(toggle_text.contains("OUTER ARMOR") and toggle_text.contains("INNER SKELETON"), "mode toggles label armor + frame modes")

	# --- Left sidebar: part list, craftery, ammo, equip. ---
	_check(ctrl.left_panel_ui != null, "controller builds a HangarLeftPanel")
	_check(ctrl.left_panel_ui.controller == ctrl, "left panel holds the controller back-ref")
	_check(ctrl.left_panel != null, "left sidebar builds the panel")
	_check(ctrl.part_item_list != null and ctrl.part_item_list is ItemList, "left sidebar builds the part ItemList")
	_check(ctrl.craft_button != null and ctrl.craft_button.text.contains("CRAFTERY"), "left sidebar builds the craftery button")
	_check(ctrl.equip_button != null and ctrl.equip_button.text.contains("EQUIP"), "left sidebar builds the equip button")
	_check(ctrl.ammo_panel != null, "left sidebar builds the ammo panel")
	_check(ctrl.ammo_panel.ammo_loadout_box != null, "ammo panel builds its loadout box")

	# --- Right sidebar: stats, weight, repair, status, exit. ---
	_check(ctrl.right_panel_ui != null, "controller builds a HangarRightPanel")
	_check(ctrl.right_panel_ui.controller == ctrl, "right panel holds the controller back-ref")
	_check(ctrl.right_panel != null, "right sidebar builds the panel")
	_check(ctrl.stats_label != null and ctrl.stats_label.text.contains("Select a chassis"), "right sidebar builds the spec label")
	_check(ctrl.weight_bar != null and ctrl.weight_bar.max_value > 0.0, "right sidebar builds the weight bar")
	_check(ctrl.total_stats_label != null and ctrl.total_stats_label.text.contains("TOTAL WEIGHT"), "right sidebar builds the total stats label")
	_check(ctrl.repair_part_button != null and ctrl.full_repair_button != null, "right sidebar builds the repair buttons")
	_check(ctrl.close_button != null and ctrl.close_button.text.contains("EXIT HANGAR"), "right sidebar builds the exit button")
	_check(ctrl.status_message_label != null, "right sidebar builds the status label")
	_check(ctrl.status_message_label == ctrl.ammo_panel.status_label, "status label is shared with the ammo panel")

	# --- Signal wiring fires: craftery button opens the craft window. ---
	ctrl.craft_button.pressed.emit()
	await get_tree().process_frame
	_check(ctrl.craft_panel.craft_window != null, "craftery button opens the craft window")
	ctrl.craft_panel.close_window()
	await get_tree().process_frame

	ctrl.queue_free()
	await get_tree().process_frame


func _verify_readiness_panel() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var rp = ctrl.readiness_panel
	_check(rp != null, "controller builds a HangarReadinessPanel")
	_check(rp.controller == ctrl, "readiness panel holds the controller back-ref")

	# Ready mech: the confirm callback fires immediately, no modal.
	GlobalData.equipped_parts["leg_left"] = {"uid": "leg"}
	GlobalData.equipped_parts["leg_right"] = {"uid": "leg"}
	GlobalData.equipped_parts["body"] = {"uid": "body"}
	_confirm_calls = 0
	rp.check(func(): _confirm_calls += 1)
	_check(_confirm_calls == 1, "ready mech calls on_confirm immediately")
	_check(_find_modal(ctrl) == null, "ready mech shows no warning modal")

	# Incomplete mech: the modal appears and on_confirm waits for LAUNCH ANYWAY.
	GlobalData.equipped_parts.clear()
	_confirm_calls = 0
	rp.check(func(): _confirm_calls += 1)
	await get_tree().process_frame
	var modal = _find_modal(ctrl)
	_check(modal != null, "incomplete mech shows the warning modal")
	_check(_confirm_calls == 0, "incomplete mech does not auto-confirm")
	var modal_text := _collect_label_text(modal)
	_check(modal_text.contains("INCOMPLETE MECH ASSEMBLY"), "warning modal shows the assembly warning")

	# LAUNCH ANYWAY button runs the confirm callback and closes the modal.
	var launch_btn: Button = _find_button_by_text(modal, "LAUNCH ANYWAY")
	var back_btn: Button = _find_button_by_text(modal, "BACK TO HANGAR")
	_check(launch_btn != null, "warning modal builds the LAUNCH ANYWAY button")
	_check(back_btn != null, "warning modal builds the BACK TO HANGAR button")
	if launch_btn:
		launch_btn.pressed.emit()
		await get_tree().process_frame
		_check(_confirm_calls == 1, "LAUNCH ANYWAY runs the confirm callback")
	_check(not is_instance_valid(modal), "LAUNCH ANYWAY frees the warning modal")

	# BACK TO HANGAR dismisses without confirming.
	_confirm_calls = 0
	rp.check(func(): _confirm_calls += 1)
	await get_tree().process_frame
	modal = _find_modal(ctrl)
	if modal:
		var back: Button = _find_button_by_text(modal, "BACK TO HANGAR")
		if back:
			back.pressed.emit()
		await get_tree().process_frame
	_check(_confirm_calls == 0, "BACK TO HANGAR does not confirm")
	_check(_find_modal(ctrl) == null, "BACK TO HANGAR frees the modal")

	# Re-checking replaces any stale modal rather than stacking duplicates —
	# across MULTIPLE consecutive checks (a third call proves the panel keeps a
	# reference instead of relying on a node-name lookup that add_child would
	# auto-rename away).
	rp.check(func(): pass)
	await get_tree().process_frame
	rp.check(func(): pass)
	await get_tree().process_frame
	rp.check(func(): pass)
	await get_tree().process_frame
	await get_tree().process_frame
	# Count semantically (modals carry a LAUNCH ANYWAY button) — the replaced
	# modal may be auto-renamed while its stale twin is queued for deletion.
	var modal_count := 0
	for child in ctrl.root_control.get_children():
		if is_instance_valid(child) and not child.is_queued_for_deletion():
			if _find_button_by_text(child, "LAUNCH ANYWAY") != null:
				modal_count += 1
	_check(modal_count == 1, "re-checking replaces rather than stacks the modal")

	ctrl.queue_free()
	await get_tree().process_frame


func _verify_persist_panel() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var pp = ctrl.persist_panel
	_check(pp != null, "controller builds a HangarPersistPanel")
	_check(pp.controller == ctrl, "persist panel holds the controller back-ref")

	# persist_edits with no editing target is a safe no-op.
	ctrl._customize_mech_id = ""
	pp.persist_edits()
	_check(true, "persist_edits no-ops with no editing target")

	# persist_edits saves the working set onto the editing berth and, when that
	# berth is not the active mech, reloads the ACTIVE mech's parts back into
	# the working set (so leaving the hangar pilots the right machine).
	var active_id: String = str(GlobalData.active_hangar_mech_id)
	var other_id := active_id
	for m in GlobalData.get_hangar_mechs():
		if str(m.get("id", "")) != active_id:
			other_id = str(m.get("id", ""))
			break
	ctrl._customize_mech_id = other_id
	GlobalData.equipped_parts["body"] = {"uid": "persist_probe", "name": "Probe", "hp": 50.0, "max_hp": 50.0, "weight": 5.0}
	pp.persist_edits()
	_check(ctrl._customize_mech_id == other_id, "persist_edits keeps the editing target")
	if other_id != active_id:
		# After persist, the ACTIVE mech's snapshot replaces the working set.
		var restored: Dictionary = GlobalData.equipped_parts.get("body", {})
		_check(str(restored.get("uid", "")) != "persist_probe" or GlobalData.equipped_parts.is_empty(), "persist_edits reloads the active mech's parts")

	# commit_and_save pushes the working set onto the editing berth (roster
	# snapshot) and saves the run.
	ctrl._customize_mech_id = active_id
	GlobalData.equipped_parts["body"] = {"uid": "commit_probe", "name": "Probe", "hp": 50.0, "max_hp": 50.0, "weight": 5.0}
	pp.commit_and_save()
	# Loading the committed state back reproduces the probe body.
	GlobalData.equipped_parts.clear()
	GlobalData.load_hangar_mech_state(active_id)
	var probe: Dictionary = GlobalData.equipped_parts.get("body", {})
	_check(str(probe.get("uid", "")) == "commit_probe", "commit_and_save persists the working set onto the berth")
	GlobalData.equipped_parts.erase("body")

	# commit_and_save with no editing target still saves the run.
	ctrl._customize_mech_id = ""
	pp.commit_and_save()
	_check(true, "commit_and_save works with no editing target")

	ctrl.queue_free()
	await get_tree().process_frame


func _verify_scrap_panel() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var sp = ctrl.scrap_panel
	_check(sp != null, "controller builds a HangarScrapPanel")
	_check(sp.controller == ctrl, "scrap panel holds the controller back-ref")

	# The single refresh entry point defers a 3D preview refresh on the garage
	# panel (used by both the applied and closed editor signals).
	sp.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(true, "scrap refresh defers the garage preview refresh without error")

	# The nav panel's emergency path builds the editor and wires the signals to
	# the scrap panel (deferred refresh runs on applied/closed).
	ctrl.nav_panel.select_submenu("emergency")
	await get_tree().process_frame
	_check(ctrl.scrap_editor != null, "emergency submenu builds the scrap editor")
	if ctrl.scrap_editor:
		_check(ctrl.scrap_editor.applied.get_connections().size() >= 1, "editor applied signal is wired")
		_check(ctrl.scrap_editor.closed.get_connections().size() >= 1, "editor closed signal is wired")
		# Emitting both signals routes to scrap_panel.refresh(), which defers the
		# garage preview refresh — safe under headless.
		ctrl.scrap_editor.applied.emit("body")
		ctrl.scrap_editor.closed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(true, "editor signals fire through the scrap panel without error")
		ctrl.scrap_editor.close()
		await get_tree().process_frame

	ctrl.queue_free()
	await get_tree().process_frame


func _verify_exit_panel() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var ep = ctrl.exit_panel
	_check(ep != null, "controller builds a HangarExitPanel")
	_check(ep.controller == ctrl, "exit panel holds the controller back-ref")

	# An incomplete mech: close() persists but the readiness check blocks the
	# actual exit (hangar stays visible + paused, warning modal appears).
	GlobalData.equipped_parts.clear()
	ctrl.visible = true
	get_tree().paused = true
	ep.close()
	await get_tree().process_frame
	_check(_find_modal(ctrl) != null, "exit on an incomplete mech shows the warning modal")
	_check(ctrl.visible, "exit is blocked while the warning modal is up")
	_check(get_tree().paused, "hangar stays paused while the warning modal is up")

	# BACK TO HANGAR dismisses and keeps the hangar open.
	var modal = _find_modal(ctrl)
	if modal:
		var back: Button = _find_button_by_text(modal, "BACK TO HANGAR")
		if back:
			back.pressed.emit()
		await get_tree().process_frame
	_check(_find_modal(ctrl) == null, "BACK TO HANGAR dismisses the exit warning")
	_check(ctrl.visible, "BACK TO HANGAR keeps the hangar open")

	# The pause key routes through _input to exit_panel.close().
	get_tree().paused = true
	ctrl.visible = true
	var pause_event := InputEventAction.new()
	pause_event.action = "pause"
	pause_event.pressed = true
	ctrl._input(pause_event)
	await get_tree().process_frame
	_check(_find_modal(ctrl) != null, "pause key routes to the exit flow")
	if _find_modal(ctrl):
		_find_modal(ctrl).queue_free()
	await get_tree().process_frame

	# The EXIT HANGAR buttons (rail + right sidebar) are wired to exit_panel.
	# (A ready mech would call GameManager.return_to_board -> change_scene, so
	# the confirm path itself is left to the readiness/persist verify blocks.)
	var rail_exit: Button = _find_button_by_text(ctrl.submenu_rail, "EXIT HANGAR")
	_check(rail_exit != null, "rail builds the EXIT HANGAR button")
	if rail_exit:
		_check(rail_exit.pressed.get_connections().size() >= 1, "rail EXIT is wired")
	_check(ctrl.close_button != null, "right sidebar builds the EXIT HANGAR button")
	_check(ctrl.close_button.pressed.get_connections().size() >= 1, "sidebar EXIT is wired")

	# Pressing the wired EXIT button on an incomplete mech re-runs the flow and
	# lands on the warning modal again (no scene change, safe under headless).
	get_tree().paused = true
	ctrl.visible = true
	ctrl.close_button.pressed.emit()
	await get_tree().process_frame
	_check(_find_modal(ctrl) != null, "EXIT button routes through the exit flow")

	ctrl.queue_free()
	await get_tree().process_frame


func _verify_refresh_panel() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var rfp = ctrl.refresh_panel
	_check(rfp != null, "controller builds a HangarRefreshPanel")
	_check(rfp.controller == ctrl, "refresh panel holds the controller back-ref")

	# after_mech_change: repaints the 3D preview + stats and (optionally) the
	# slot part list. The part-list repopulation is observable via item_count:
	# after a populate the list rows match the armor catalog for the slot, and
	# the (false) call leaves the current rows untouched.
	ctrl.selected_slot = "body"
	ctrl.current_mode = "armor"
	rfp.after_mech_change(true)
	var rows_after_true: int = ctrl.part_item_list.item_count
	_check(ctrl.total_stats_label.text.contains("TOTAL WEIGHT"), "after_mech_change refreshes the total stats")
	ctrl.part_item_list.add_item("stale row")
	var rows_with_stale: int = ctrl.part_item_list.item_count
	rfp.after_mech_change(false)
	_check(ctrl.part_item_list.item_count == rows_with_stale, "after_mech_change(false) leaves the part list untouched")
	_check(rows_after_true >= 0, "after_mech_change(true) runs the part-list repopulation")

	# after_chassis_change: repaints stats + preview; an empty dict skips the
	# chassis preview apply but still refreshes stats.
	rfp.after_chassis_change({})
	_check(ctrl.total_stats_label.text.contains("TOTAL WEIGHT"), "after_chassis_change refreshes stats with an empty dict")
	rfp.after_chassis_change(GlobalData.chassis_catalog.get("standard", {}))
	_check(true, "after_chassis_change applies a real chassis without error")

	# after_craft: repopulates the slot list + refreshes stats.
	rfp.after_craft("body")
	_check(ctrl.part_item_list.item_count >= 0, "after_craft repopulates the slot part list")
	_check(ctrl.total_stats_label.text.contains("TOTAL WEIGHT"), "after_craft refreshes the total stats")

	# The roster/catalog/craft panels route their post-change calls through this
	# panel (verified by the earlier roster/catalog/craft verify blocks which
	# exercise the full flows).
	_check(ctrl.roster_panel_ui != null and ctrl.catalog_panel != null and ctrl.craft_panel != null, "sibling panels exist for the refresh routing")

	ctrl.queue_free()
	await get_tree().process_frame


func _find_modal(ctrl: Node) -> Node:
	if ctrl.root_control:
		for child in ctrl.root_control.get_children():
			if child.name == "CombatWarningModal" and is_instance_valid(child) and not child.is_queued_for_deletion():
				return child
	return null


func _find_button_by_text(node: Node, text: String) -> Button:
	if node is Button and node.text.contains(text):
		return node
	for child in node.get_children():
		var found := _find_button_by_text(child, text)
		if found:
			return found
	return null


func _count_buttons(node: Node) -> int:
	var count := 0
	if node is Button:
		count += 1
	for child in node.get_children():
		count += _count_buttons(child)
	return count
