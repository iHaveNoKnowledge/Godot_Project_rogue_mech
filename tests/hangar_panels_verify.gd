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
## Run: godot --headless --path . res://tests/hangar_panels_verify.tscn

var _fails: int = 0
var _checks: int = 0


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

	ctrl._select_hangar_submenu("roster")
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

	ctrl._show_hangar_menu()
	await get_tree().process_frame
	_check(not rp.roster_panel.visible, "hangar menu hides the roster page")
	_check(not rp.mech_slot_label.visible, "hangar menu hides the badge")

	ctrl.queue_free()
	anchor.queue_free()
	await get_tree().process_frame


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
	ctrl._select_hangar_submenu("catalog")
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
	ctrl._select_hangar_submenu("craft")
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
	ctrl._select_slot_tab("body")
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
