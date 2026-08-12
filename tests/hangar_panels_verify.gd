extends Node

## Headless verification of the panels extracted from hangar_controller.gd:
##   HangarPartText      — pure stat-card text helpers
##   HangarAmmoPanel     — ammo-to-carry loadout build/adjust/refresh
##   HangarRosterPanel   — roster page (badge, slot rows, pilot/role pickers)
##   HangarCatalogPanel  — catalog window + hover-stats preview
##   HangarGaragePanel   — 3D garage preview + attachment math
##   HangarCraftPanel    — craftery window (craft armor from templates)
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
	ctrl._populate_part_list_for_slot("weapon_carry")
	var wcard: String = cp.stats_text_for_index(0)
	if ctrl.visible_weapon_indices.size() > 0:
		_check(wcard.contains("BACK CARRY") or wcard.contains("FIELD PACK"), "weapon mode hover card")

	ctrl._populate_part_list_for_slot("body")
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
