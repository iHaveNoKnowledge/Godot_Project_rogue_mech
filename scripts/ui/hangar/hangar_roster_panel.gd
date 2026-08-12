class_name HangarRosterPanel
extends RefCounted

## Mech roster page (truck-convoy parking): the header badge showing which berth
## is being edited, one row per berth (pilot + role pickers, switch button), and
## the two popup pickers. Extracted from hangar_controller.gd.
##
## The controller keeps the cross-page editing state (_customize_mech_id) and the
## 3D/stats refreshes; this panel calls back into it through a small API
## (get_editing_mech_id / set_editing_mech_id / refresh_panel.after_mech_change).
## `controller` (the hangar node) is also the parent popup menus are attached to.

var controller: Node

var roster_panel: PanelContainer = null
var roster_slot_list: VBoxContainer = null
var roster_page_title: Label = null
var roster_status_label: Label = null
var mech_slot_label: Label = null
var mech_prev_button: Button = null
var mech_next_button: Button = null
# Name-prompt modal used by the REGISTER action on empty berths. Kept as
# members so callers (and the test suite) can drive the LineEdit + confirm.
var register_dialog: Control = null
var register_dialog_edit: LineEdit = null
# Rename-prompt modal opened from an occupied roster row (same test-drivable
# pattern as the register prompt).
var rename_dialog: Control = null
var rename_dialog_edit: LineEdit = null
# Pending-register banner shown on the customize page while a berth is being
# assembled: the required walking-chassis checklist (BODY + both legs) and the
# REGISTER FRAME confirm, locked until every required frame is equipped.
var pending_register_banner: Control = null
var pending_register_button: Button = null
var pending_register_status_label: Label = null
var _pending_register_slot: int = -1
# Pre-flow loadout snapshots of the berths the working set can leak onto while
# the player assembles frames (the editing target + the active driver), so the
# registration can restore them once it completes or is abandoned.
var _pending_original_editing: Dictionary = {}
var _pending_original_active: Dictionary = {}


## Header badge + prev/next switcher, built into the top header row.
func build_badge_header(hdr_box: HBoxContainer) -> void:
	# Mech-slot switcher: which berth in the hangar convoy is being edited.
	# Prev/next wrap around, exactly like paging through parked mechs.
	mech_prev_button = Button.new()
	mech_prev_button.text = "◀"
	mech_prev_button.tooltip_text = "Previous hangar mech"
	mech_prev_button.custom_minimum_size = Vector2(34, 32)
	mech_prev_button.focus_mode = Control.FOCUS_NONE
	mech_prev_button.visible = false
	mech_prev_button.pressed.connect(func(): cycle_hangar_mech(-1))
	hdr_box.add_child(mech_prev_button)

	mech_slot_label = Label.new()
	mech_slot_label.name = "MechSlotLabel"
	mech_slot_label.text = "MECH SLOT 1/2"
	mech_slot_label.add_theme_font_size_override("font_size", 14)
	mech_slot_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	mech_slot_label.visible = false
	hdr_box.add_child(mech_slot_label)

	mech_next_button = Button.new()
	mech_next_button.text = "▶"
	mech_next_button.tooltip_text = "Next hangar mech"
	mech_next_button.custom_minimum_size = Vector2(34, 32)
	mech_next_button.focus_mode = Control.FOCUS_NONE
	mech_next_button.visible = false
	mech_next_button.pressed.connect(func(): cycle_hangar_mech(1))
	hdr_box.add_child(mech_next_button)


## Roster page panel: opens from the hangar menu, shows the truck-convoy
## parking grid (one row per berth) with the 3D mech preview behind it.
func build(root: Control) -> void:
	var roster_panel = PanelContainer.new()
	roster_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	roster_panel.offset_top = 128
	roster_panel.offset_bottom = -20
	roster_panel.offset_left = 20
	roster_panel.custom_minimum_size = Vector2(540, 0)
	roster_panel.visible = false
	self.roster_panel = roster_panel
	root.add_child(roster_panel)

	var style_roster = StyleBoxFlat.new()
	style_roster.bg_color = Color(0.07, 0.09, 0.14, 0.94)
	style_roster.corner_radius_top_left = 8
	style_roster.corner_radius_bottom_left = 8
	style_roster.content_margin_left = 14
	style_roster.content_margin_right = 14
	style_roster.content_margin_top = 14
	style_roster.content_margin_bottom = 14
	roster_panel.add_theme_stylebox_override("panel", style_roster)

	var roster_box = VBoxContainer.new()
	roster_box.add_theme_constant_override("separation", 8)
	roster_panel.add_child(roster_box)

	roster_page_title = Label.new()
	roster_page_title.text = "HANGAR ROSTER"
	roster_page_title.add_theme_font_size_override("font_size", 16)
	roster_page_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	roster_box.add_child(roster_page_title)

	var roster_desc = Label.new()
	roster_desc.text = "Every berth in the transport convoy. Parked mechs keep their own \
loadout and pilot. New mechs come from assembling frames in the editor or from \
events out in the field (surrenders, captures, shops)."
	roster_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	roster_desc.add_theme_font_size_override("font_size", 11)
	roster_box.add_child(roster_desc)

	var roster_sep = HSeparator.new()
	roster_box.add_child(roster_sep)

	roster_slot_list = VBoxContainer.new()
	roster_slot_list.add_theme_constant_override("separation", 4)
	roster_slot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_box.add_child(roster_slot_list)

	roster_status_label = Label.new()
	roster_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	roster_status_label.add_theme_font_size_override("font_size", 11)
	roster_box.add_child(roster_status_label)


func set_panel_visible(v: bool) -> void:
	if roster_panel:
		roster_panel.visible = v
	# Leaving the roster page (or the hangar) must not leave any prompt up.
	if not v:
		close_register_dialog()
		close_rename_dialog()


func set_badge_visible(v: bool) -> void:
	if mech_slot_label:
		mech_slot_label.visible = v
	if mech_prev_button:
		mech_prev_button.visible = v
	if mech_next_button:
		mech_next_button.visible = v


## Full roster page: show the panel + badge and repaint both.
func show_page() -> void:
	set_panel_visible(true)
	set_badge_visible(true)
	refresh_badge()
	refresh_page()


func hide_page() -> void:
	set_panel_visible(false)
	set_badge_visible(false)


# Header badge: which berth is being edited, e.g. "MECH SLOT 3/8 · Mech 03".
func refresh_badge() -> void:
	if mech_slot_label == null:
		return
	if GlobalData.mech_less:
		mech_slot_label.text = "ON FOOT — NO MECH PARKED"
		return
	var capacity := GlobalData.get_hangar_capacity()
	var mechs := GlobalData.get_hangar_mechs()
	var editing_id: String = controller.get_editing_mech_id()
	var editing: Dictionary = {}
	for m in mechs:
		if str(m.get("id", "")) == editing_id:
			editing = m
			break
	var slot := int(editing.get("slot", 0))
	if slot <= 0:
		slot = GlobalData.get_hangar_slot_of(editing_id)
	if slot <= 0:
		slot = 1
	var name_str := str(editing.get("name", "Mech")) if not editing.is_empty() else "Mech"
	# Show who drives the berth being edited: the pilot label resolves fleet
	# pilots and the player driver ("(no pilot)" for an empty seat).
	var pilot_str := GlobalData.get_hangar_pilot_name(str(editing.get("pilot", ""))) if not editing.is_empty() else "(no pilot)"
	var driver_note := ""
	if editing_id == GlobalData.active_hangar_mech_id:
		driver_note = " · PILOTING"
	mech_slot_label.text = "MECH SLOT %d/%d · %s · PILOT: %s%s" % [slot, capacity, name_str, pilot_str, driver_note]


# Pages between parked mechs (wrap-around). This only changes which mech is
# being edited on the customize/roster page — it does NOT switch the player's
# active (piloting) mech, which stays untouched until the player assigns a
# pilot or drives it into combat.
func cycle_hangar_mech(direction: int) -> void:
	var mechs := GlobalData.get_hangar_mechs()
	if mechs.size() <= 1:
		return
	# Editing target defaults to the active mech on first open.
	var current_id: String = controller.get_editing_mech_id()
	# Persist edits made on the berth we're leaving before loading the next one.
	if current_id != "":
		GlobalData.save_hangar_mech_state(current_id)
	var index := -1
	for i in range(mechs.size()):
		if str(mechs[i].get("id", "")) == current_id:
			index = i
			break
	if index < 0:
		index = 0
	var next := (index + direction + mechs.size()) % mechs.size()
	var target_id := str(mechs[next].get("id", ""))
	if not GlobalData.load_hangar_mech_state(target_id):
		return
	controller.set_editing_mech_id(target_id)
	controller.selected_chassis_key = GlobalData.chassis_id
	refresh_badge()
	controller.refresh_panel.after_mech_change(true)
	if roster_panel and roster_panel.visible:
		refresh_page()


func refresh_page() -> void:
	if roster_slot_list == null:
		return
	GlobalData.ensure_hangar_roster()
	var capacity := GlobalData.get_hangar_capacity()
	var fleet := GlobalData.get_hangar_fleet_size()
	var mechs := GlobalData.get_hangar_mechs()
	var by_slot: Dictionary = {}
	for mech in mechs:
		if mech is Dictionary:
			by_slot[int(mech.get("slot", 0))] = mech

	for child in roster_slot_list.get_children():
		child.queue_free()

	roster_page_title.text = "HANGAR ROSTER — MECH %d/%d" % [mechs.size(), capacity]

	for slot in range(1, capacity + 1):
		build_slot_row(slot, by_slot.get(slot, {}), false)

	# Saves written under a bigger fleet can exceed today's capacity. Never drop
	# those mechs: show them as over-capacity rows (still switchable/assignable).
	for slot in by_slot.keys():
		if int(slot) > capacity:
			build_slot_row(int(slot), by_slot[int(slot)], true)

	if roster_status_label:
		var affiliation := GlobalData.get_run_affiliation()
		var aff_prefix := "%s · %s" % [
			affiliation.get("name", "Mech Convoy"),
			affiliation.get("transport", "Truck convoy"),
		]
		if GlobalData.mech_less:
			roster_status_label.text = "%s\nON FOOT — every mech is gone. Board combat tiles become recovery missions until you rebuild a chassis." \
				% aff_prefix
			return
		var convoy_desc := ""
		if fleet <= 1:
			convoy_desc = "SOLO CONVOY · 1 trailer · 2 berths"
		else:
			convoy_desc = "FLEET CONVOY · %d pilots · %d trucks · %d berths" \
				% [fleet, ceili(fleet / 2.0), capacity]
		roster_status_label.text = "%s\n%s\nNew mechs are obtained by assembling frames from your inventory or through events (surrenders, captures, shops)." \
			% [aff_prefix, convoy_desc]


func build_slot_row(slot: int, mech: Dictionary, over_capacity: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	roster_slot_list.add_child(row)

	var slot_lbl := Label.new()
	slot_lbl.text = "SLOT %02d" % slot
	slot_lbl.custom_minimum_size = Vector2(70, 0)
	slot_lbl.add_theme_font_size_override("font_size", 12)
	slot_lbl.add_theme_color_override("font_color", Color(0.5, 0.6, 0.75))
	row.add_child(slot_lbl)

	if mech.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "EMPTY BERTH"
		empty_lbl.custom_minimum_size = Vector2(180, 0)
		empty_lbl.add_theme_color_override("font_color", Color(0.45, 0.5, 0.6))
		row.add_child(empty_lbl)

		# REGISTER assembles the currently built parts into this berth. While on
		# foot (mech_less) the hangar has nothing to build from — a chassis has to
		# come back through recovery missions, so the button is withheld.
		if not GlobalData.mech_less:
			var register_btn := Button.new()
			register_btn.text = "REGISTER"
			register_btn.tooltip_text = "Assemble a mech frame into this berth from the currently assembled parts (%d scrap + %d cr; needs a body + both leg frames)." % [
				GlobalData.get_frame_register_scrap_cost(), GlobalData.get_frame_register_credit_cost()]
			register_btn.custom_minimum_size = Vector2(96, 28)
			register_btn.focus_mode = Control.FOCUS_NONE
			register_btn.pressed.connect(register_mech.bind(slot))
			row.add_child(register_btn)

		var hint := Label.new()
		hint.text = "Assemble a frame from the current build · %d scrap + %d cr" % [
			GlobalData.get_frame_register_scrap_cost(), GlobalData.get_frame_register_credit_cost()] \
			if not GlobalData.mech_less else "On foot — rebuild a chassis through recovery missions"
		hint.custom_minimum_size = Vector2(200, 0)
		hint.add_theme_font_size_override("font_size", 10)
		hint.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
		row.add_child(hint)
		return

	var mech_id := str(mech.get("id", ""))
	var is_active := mech_id == GlobalData.active_hangar_mech_id

	var name_lbl := Label.new()
	name_lbl.text = "%s%s" % [
		str(mech.get("name", "Unnamed Mech")),
		" [ACTIVE]" if is_active else "",
	]
	name_lbl.custom_minimum_size = Vector2(150, 0)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4) if is_active else Color(0.85, 0.9, 0.95))
	row.add_child(name_lbl)

	var pilot_lbl := Label.new()
	pilot_lbl.text = "PILOT: %s" % GlobalData.get_hangar_pilot_name(str(mech.get("pilot", "")))
	pilot_lbl.custom_minimum_size = Vector2(160, 0)
	pilot_lbl.add_theme_font_size_override("font_size", 11)
	pilot_lbl.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0))
	row.add_child(pilot_lbl)

	var pilot_btn := Button.new()
	pilot_btn.text = "PILOT ▾"
	pilot_btn.custom_minimum_size = Vector2(80, 28)
	pilot_btn.focus_mode = Control.FOCUS_NONE
	pilot_btn.pressed.connect(open_pilot_picker.bind(mech_id, pilot_btn))
	row.add_child(pilot_btn)

	var role_btn := Button.new()
	role_btn.text = "ROLE ▾"
	role_btn.custom_minimum_size = Vector2(80, 28)
	role_btn.focus_mode = Control.FOCUS_NONE
	role_btn.pressed.connect(open_role_picker.bind(mech_id, role_btn))
	row.add_child(role_btn)

	var rename_btn := Button.new()
	rename_btn.text = "RENAME"
	rename_btn.custom_minimum_size = Vector2(76, 28)
	rename_btn.focus_mode = Control.FOCUS_NONE
	rename_btn.tooltip_text = "Rename this parked mech"
	rename_btn.pressed.connect(open_rename_dialog.bind(mech_id))
	row.add_child(rename_btn)

	if not is_active and not over_capacity:
		var switch_btn := Button.new()
		switch_btn.text = "SWITCH"
		switch_btn.custom_minimum_size = Vector2(80, 28)
		switch_btn.focus_mode = Control.FOCUS_NONE
		switch_btn.pressed.connect(on_switch_mech_pressed.bind(mech_id))
		row.add_child(switch_btn)


# REGISTER — assembles the currently built parts (the working set) into an
# empty convoy berth as a parked mech. Pressing it jumps into the customize
# page (INNER SKELETON mode, BODY slot) so the player can equip the frames the
# new mech needs; the pending banner then confirms the registration, locked
# until a walking chassis (body + both legs) is equipped. On confirm the frame
# becomes the player's mech (active + pilot) and costs scrap + credits.
func register_mech(slot: int) -> void:
	if GlobalData.mech_less:
		_set_status("You're on foot — rebuild a chassis through recovery missions.")
		return
	close_register_dialog()
	# Jump straight into the frame picker so equipping BODY + both legs is the
	# very next action. The chassis + price gates now live on the banner's
	# REGISTER FRAME confirm (and the confirm-time re-check), not on this press.
	controller.nav_panel.select_submenu("customize")
	controller.slot_panel.select("body")
	controller.nav_panel.switch_custom_mode("frame")
	start_pending_register(slot)


# True when the working set has the walking chassis the register flow needs: a
# body frame plus both leg frames (the same set build_hangar_mech requires).
func _has_walking_chassis() -> bool:
	for required in HangarManager.REQUIRED_WALKING_FRAMES:
		if not GlobalData.equipped_frames.has(required) or GlobalData.equipped_frames[required] == null:
			return false
	return true


# Arms the pending registration for `slot`: raises the banner on the customize
# page and records which berth the confirmation should fill.
func start_pending_register(slot: int) -> void:
	close_pending_register()
	_pending_register_slot = slot
	_capture_pending_originals()
	build_pending_register_banner(slot)
	_set_status("Assembling SLOT %02d — equip a BODY + both legs (INNER SKELETON), then press REGISTER FRAME." % slot)


# Snapshots the loadouts of the berths the working set can leak onto during the
# assembly (the editing target + the active driver) so they can be restored
# once the registration completes or is abandoned.
func _capture_pending_originals() -> void:
	_pending_original_editing = {}
	_pending_original_active = {}
	var editing_id: String = controller.get_editing_mech_id()
	var active_id: String = GlobalData.active_hangar_mech_id
	for m in GlobalData.get_hangar_mechs():
		var mid := str(m.get("id", ""))
		if mid == editing_id:
			# Deep-copy: get_hangar_mechs() only shallow-duplicates the array, so
			# without this the "original" would share the live entry dict and any
			# in-place mutation would corrupt the restore.
			_pending_original_editing = m.duplicate(true)
		if mid == active_id:
			_pending_original_active = m.duplicate(true)


# Reverts the captured berth loadouts and reloads the previously-edited berth
# into the working set, so abandoning an assembly leaves every existing mech
# exactly as it was (the frames equipped mid-flow were meant for the NEW mech).
func _restore_pending_flow() -> void:
	var had_originals := not _pending_original_editing.is_empty() or not _pending_original_active.is_empty()
	_restore_captured_berths()
	var editing_id := str(_pending_original_editing.get("id", ""))
	if editing_id != "":
		GlobalData.load_hangar_mech_state(editing_id)
	if had_originals:
		GlobalData.save_run()
	_pending_original_editing = {}
	_pending_original_active = {}


# Restores the captured berth loadouts WITHOUT touching the working set — used
# after a successful registration, where the working set already holds the new
# mech's state.
func _restore_pending_roster_only() -> void:
	_restore_captured_berths()
	_pending_original_editing = {}
	_pending_original_active = {}


# Shared by the two restore paths: writes the pre-flow loadouts back onto the
# captured berths (identity fields — id/name/slot/pilot/archetype — are kept).
func _restore_captured_berths() -> void:
	if not _pending_original_editing.is_empty():
		GlobalData.restore_berth_loadout(str(_pending_original_editing.get("id", "")), _pending_original_editing)
	if not _pending_original_active.is_empty():
		GlobalData.restore_berth_loadout(str(_pending_original_active.get("id", "")), _pending_original_active)


# Floating panel on the customize page: the required-frame checklist plus the
# REGISTER FRAME confirm (locked until a walking chassis is equipped) and an
# abandon button. Lives on the customize page so the player can switch slots /
# modes freely while assembling.
func build_pending_register_banner(slot: int) -> void:
	var modal := PanelContainer.new()
	modal.name = "PendingRegisterBanner"
	modal.anchor_left = 0.5
	modal.anchor_right = 0.5
	modal.anchor_top = 0.0
	modal.anchor_bottom = 0.0
	modal.offset_left = -190
	modal.offset_right = 190
	modal.offset_top = 132
	modal.offset_bottom = 262

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.18, 0.97)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = controller._highlight_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	modal.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	modal.add_child(vbox)

	var title := Label.new()
	title.text = "🔩 REGISTER — SLOT %02d" % slot
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", controller._highlight_color)
	title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title)

	var cost_lbl := Label.new()
	cost_lbl.text = "COST: %d scrap + %d cr" % [
		GlobalData.get_frame_register_scrap_cost(), GlobalData.get_frame_register_credit_cost()]
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	cost_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(cost_lbl)

	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 11)
	vbox.add_child(status)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)

	var ok_btn := Button.new()
	ok_btn.text = "REGISTER FRAME"
	ok_btn.custom_minimum_size = Vector2(130, 32)
	ok_btn.disabled = true
	ok_btn.pressed.connect(_on_pending_register_pressed)
	btn_row.add_child(ok_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "✕"
	cancel_btn.custom_minimum_size = Vector2(34, 32)
	cancel_btn.tooltip_text = "Abandon this assembly"
	cancel_btn.pressed.connect(close_pending_register)
	btn_row.add_child(cancel_btn)

	if controller.root_control:
		controller.root_control.add_child(modal)
	else:
		controller.add_child(modal)
	pending_register_banner = modal
	pending_register_button = ok_btn
	pending_register_status_label = status
	refresh_pending_register()


# Re-evaluates the pending banner: repaints the required-frame checklist (✓/✗)
# and locks/unlocks the REGISTER FRAME confirm. Hooked into the persist flow
# (persist_panel.commit_and_save) so every equip/unequip refreshes it.
func refresh_pending_register() -> void:
	if pending_register_banner == null or not is_instance_valid(pending_register_banner):
		return
	var parts: Array[String] = []
	for required in HangarManager.REQUIRED_WALKING_FRAMES:
		var ok := GlobalData.equipped_frames.has(required) and GlobalData.equipped_frames[required] != null
		# Readable names for the checklist ("LEFT LEG" not "LEG LEFT").
		var label: String
		match required:
			"leg_left":
				label = "LEFT LEG"
			"leg_right":
				label = "RIGHT LEG"
			_:
				label = required.to_upper()
		parts.append("%s %s" % [label, "✓" if ok else "✗"])
	if pending_register_status_label:
		pending_register_status_label.text = "   ".join(parts)
	if pending_register_button:
		pending_register_button.disabled = not _has_walking_chassis()


# REGISTER FRAME on the banner: opens the name prompt, locked out with a status
# message while the chassis is incomplete or the price is out of reach.
func _on_pending_register_pressed() -> void:
	var slot := _pending_register_slot
	if slot < 0:
		return
	if not _has_walking_chassis():
		_set_status("REGISTER needs a walking chassis (body + both leg frames) equipped.")
		return
	if not _can_afford_register():
		_set_status("REGISTER needs %d scrap + %d cr — not enough resources." % [
			GlobalData.get_frame_register_scrap_cost(), GlobalData.get_frame_register_credit_cost()])
		return
	close_register_dialog()
	build_register_dialog(slot)


# Drops the pending registration (banner + slot). Unless the registration
# already succeeded (revert_working_set = false), also reverts the loadout
# leaks onto the pre-flow berths. Called on abandon, on the hangar menu / exit,
# and after a successful registration.
func close_pending_register(revert_working_set: bool = true) -> void:
	if pending_register_banner and is_instance_valid(pending_register_banner):
		pending_register_banner.queue_free()
	pending_register_banner = null
	pending_register_button = null
	pending_register_status_label = null
	_pending_register_slot = -1
	if revert_working_set:
		_restore_pending_flow()


# Small modal asking for the new frame's name; confirming builds it into the
# berth, cancelling aborts without touching the roster.
func build_register_dialog(slot: int) -> void:
	var modal := PanelContainer.new()
	modal.name = "RegisterMechDialog"
	modal.anchor_left = 0.5
	modal.anchor_right = 0.5
	modal.anchor_top = 0.5
	modal.anchor_bottom = 0.5
	modal.offset_left = -240
	modal.offset_right = 240
	modal.offset_top = -125
	modal.offset_bottom = 125

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.16, 0.97)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = controller._highlight_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	modal.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	modal.add_child(vbox)

	var title := Label.new()
	title.text = "🔩 ASSEMBLE FRAME — SLOT %02d" % slot
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", controller._highlight_color)
	title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title)

	var cost_lbl := Label.new()
	cost_lbl.text = "COST: %d scrap + %d cr" % [
		GlobalData.get_frame_register_scrap_cost(), GlobalData.get_frame_register_credit_cost()]
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	cost_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(cost_lbl)

	var hint := Label.new()
	hint.text = "Name the frame you are assembling from the current build. Once\nregistered it becomes your piloted mech — tune it right away."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)

	var edit := LineEdit.new()
	edit.text = "Mech %02d" % slot
	edit.placeholder_text = "Frame name / callsign"
	edit.custom_minimum_size = Vector2(0, 34)
	edit.select_all()
	edit.text_submitted.connect(func(_t: String): _confirm_register(slot))
	vbox.add_child(edit)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var ok_btn := Button.new()
	ok_btn.text = "REGISTER FRAME"
	ok_btn.custom_minimum_size = Vector2(120, 34)
	ok_btn.pressed.connect(func(): _confirm_register(slot))
	btn_row.add_child(ok_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(120, 34)
	cancel_btn.pressed.connect(func(): close_register_dialog())
	btn_row.add_child(cancel_btn)

	if controller.root_control:
		controller.root_control.add_child(modal)
	else:
		controller.add_child(modal)
	register_dialog = modal
	register_dialog_edit = edit
	edit.grab_focus()


# Shared affordability gate for the REGISTER price (register_mech + the confirm
# re-check), so a future cost tweak can't drift the two checks apart.
func _can_afford_register() -> bool:
	return GlobalData.scrap >= GlobalData.get_frame_register_scrap_cost() \
		and GlobalData.credits >= GlobalData.get_frame_register_credit_cost()


# Writes the same status text to the roster page's label AND the customize
# sidebar's shared status label, so a message is never hidden by whichever page
# the player is currently looking at.
func _set_status(text: String) -> void:
	if roster_status_label:
		roster_status_label.text = text
	if controller and controller.status_message_label:
		controller.status_message_label.text = text


func _confirm_register(slot: int) -> void:
	var chosen := ""
	if register_dialog_edit and is_instance_valid(register_dialog_edit):
		chosen = register_dialog_edit.text.strip_edges()
	close_register_dialog()
	# The dialog only blocks its own rect, so resources could have changed while
	# it was open — re-check the price before spending anything.
	if not _can_afford_register():
		_set_status("Not enough scrap/credits to assemble the frame.")
		return
	var new_mech := GlobalData.build_hangar_mech(chosen, slot)
	if new_mech.is_empty():
		# Re-check the chassis gate for an accurate message (frames could have
		# changed while the dialog was open).
		_set_status("REGISTER needs a walking chassis (body + both leg frames) equipped."
			if not _has_walking_chassis() else "No free berth in the convoy.")
		return
	# Charged here (not in build()) so recovery grants / recruit parking stay free.
	GlobalData.try_spend_scrap(GlobalData.get_frame_register_scrap_cost())
	GlobalData.try_spend_credits(GlobalData.get_frame_register_credit_cost())
	# The freshly assembled frame becomes the player's mech: it takes over as
	# the active/piloted machine (the previous one parks as a pilotless spare)
	# so tuning it on the customize page carries straight into the next fight.
	var new_id := str(new_mech.get("id", ""))
	controller.set_editing_mech_id(new_id)
	if GlobalData.switch_hangar_mech(new_id):
		controller.selected_chassis_key = GlobalData.chassis_id
	GlobalData.assign_hangar_pilot(new_id, HangarManager.PLAYER_PILOT_ID)
	# The assembled frames leaked onto the pre-flow berths via equip commits
	# (commit_and_save) and build()/switch_mech()'s save_active() — the new mech
	# is the only one that should carry the new build, so restore their loadouts
	# (the pilot swap above is preserved: restore never touches identity fields).
	_restore_pending_roster_only()
	GlobalData.save_run()
	# Distinct cue: the frame is assembled and takes over as the player's mech.
	AudioManager.play_mech_register()
	refresh_page()
	controller.refresh_panel.after_mech_change(false)
	controller.nav_panel.select_submenu("customize")
	close_pending_register(false)
	_set_status("Registered %s in SLOT %02d (-%d scrap, -%d cr). It is now your piloted mech — tune it here." % [
		str(new_mech.get("name", "Mech")), slot,
		GlobalData.get_frame_register_scrap_cost(), GlobalData.get_frame_register_credit_cost()])


func close_register_dialog() -> void:
	if register_dialog and is_instance_valid(register_dialog):
		register_dialog.queue_free()
	register_dialog = null
	register_dialog_edit = null


# RENAME — small modal that renames a parked mech straight from its roster row.
# The name field is pre-filled with the current name (selected, so typing
# replaces it); a blank confirm falls back to the slot-based name.
func open_rename_dialog(mech_id: String) -> void:
	var mech: Dictionary = {}
	for m in GlobalData.get_hangar_mechs():
		if str(m.get("id", "")) == mech_id:
			mech = m
			break
	if mech.is_empty():
		return
	close_rename_dialog()
	build_rename_dialog(mech)


func build_rename_dialog(mech: Dictionary) -> void:
	var modal := PanelContainer.new()
	modal.name = "RenameMechDialog"
	modal.anchor_left = 0.5
	modal.anchor_right = 0.5
	modal.anchor_top = 0.5
	modal.anchor_bottom = 0.5
	modal.offset_left = -200
	modal.offset_right = 200
	modal.offset_top = -110
	modal.offset_bottom = 110

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.16, 0.97)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = controller._highlight_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	modal.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	modal.add_child(vbox)

	var title := Label.new()
	title.text = "✏️ RENAME MECH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", controller._highlight_color)
	title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "SLOT %02d · currently \"%s\"" % [int(mech.get("slot", 1)), str(mech.get("name", "Mech"))]
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)

	var edit := LineEdit.new()
	edit.text = str(mech.get("name", "Mech"))
	edit.placeholder_text = "Frame name / callsign"
	edit.custom_minimum_size = Vector2(0, 34)
	edit.select_all()
	edit.text_submitted.connect(func(_t: String): _confirm_rename(str(mech.get("id", ""))))
	vbox.add_child(edit)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var ok_btn := Button.new()
	ok_btn.text = "RENAME"
	ok_btn.custom_minimum_size = Vector2(120, 34)
	ok_btn.pressed.connect(func(): _confirm_rename(str(mech.get("id", ""))))
	btn_row.add_child(ok_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(120, 34)
	cancel_btn.pressed.connect(close_rename_dialog)
	btn_row.add_child(cancel_btn)

	if controller.root_control:
		controller.root_control.add_child(modal)
	else:
		controller.add_child(modal)
	rename_dialog = modal
	rename_dialog_edit = edit
	edit.grab_focus()


func _confirm_rename(mech_id: String) -> void:
	var chosen := ""
	if rename_dialog_edit and is_instance_valid(rename_dialog_edit):
		chosen = rename_dialog_edit.text
	close_rename_dialog()
	if not GlobalData.rename_hangar_mech(mech_id, chosen):
		_set_status("Unable to rename that berth.")
		return
	GlobalData.save_run()
	refresh_badge()
	refresh_page()
	var final_name := ""
	for m in GlobalData.get_hangar_mechs():
		if str(m.get("id", "")) == mech_id:
			final_name = str(m.get("name", ""))
			break
	_set_status("Renamed to %s." % final_name)


func close_rename_dialog() -> void:
	if rename_dialog and is_instance_valid(rename_dialog):
		rename_dialog.queue_free()
	rename_dialog = null
	rename_dialog_edit = null


# Popup picker choosing which combat archetype a mech fights as when fielded as
# an ally (Rusher / Ranged / Heavy / Support). The role is stored on the berth
# and read by SpawnManager when the hangar's piloted mechs tag into battle.
func open_role_picker(mech_id: String, anchor_btn: Button) -> void:
	for existing in controller.get_children():
		if existing is PopupMenu and is_instance_valid(existing):
			existing.queue_free()
	var pop := PopupMenu.new()
	controller.add_child(pop)
	var roles := [
		{"archetype": HangarManager.ARCHETYPE_RUSHER, "label": "Rusher  — close-range melee rush"},
		{"archetype": HangarManager.ARCHETYPE_RANGED, "label": "Ranged — engage from distance"},
		{"archetype": HangarManager.ARCHETYPE_HEAVY, "label": "Heavy  — slow, high-damage guns"},
		{"archetype": HangarManager.ARCHETYPE_SUPPORT, "label": "Support — heal teammates"},
	]
	var current := GlobalData.get_hangar_archetype(mech_id)
	for i in range(roles.size()):
		var role: Dictionary = roles[i]
		var label := str(role["label"])
		if int(role["archetype"]) == current:
			label = "● " + label
		pop.add_item(label, i)
	pop.id_pressed.connect(func(id):
		var archetype: int = int(roles[id]["archetype"])
		if GlobalData.set_hangar_archetype(mech_id, archetype):
			GlobalData.save_run()
			pop.queue_free()
			refresh_page()
	)
	pop.popup_hide.connect(func():
		if is_instance_valid(pop):
			pop.queue_free()
	)
	pop.popup(Rect2i(anchor_btn.global_position, Vector2i(320, 0)))


func on_switch_mech_pressed(mech_id: String) -> void:
	if not GlobalData.switch_hangar_mech(mech_id):
		if roster_status_label:
			roster_status_label.text = "Unable to load that hangar mech."
		return
	# The player is now piloting this berth, so the editor follows along.
	controller.set_editing_mech_id(mech_id)
	controller.selected_chassis_key = GlobalData.chassis_id
	GlobalData.save_run()
	refresh_badge()
	refresh_page()
	controller.refresh_panel.after_mech_change(false)
	if roster_status_label:
		roster_status_label.text = "Loaded %s." % str(GlobalData.get_active_hangar_mech().get("name", "Mech"))


func mech_label_for_pilot(pilot_id: String) -> String:
	for mech in GlobalData.get_hangar_mechs():
		if str(mech.get("pilot", "")) == pilot_id:
			return "· %s" % str(mech.get("name", "Mech"))
	return ""


# Popup picker listing every pilot in the convoy; selecting one drives that
# mech (swapping berths when the pilot already sits elsewhere). "(no pilot)"
# clears the seat.
func open_pilot_picker(mech_id: String, anchor_btn: Button) -> void:
	for existing in controller.get_children():
		if existing is PopupMenu and is_instance_valid(existing):
			existing.queue_free()
	var pop := PopupMenu.new()
	controller.add_child(pop)
	pop.add_item("(no pilot)", 0)
	var pilots := GlobalData.get_hangar_pilots()
	for i in range(pilots.size()):
		var pilot: Dictionary = pilots[i]
		pop.add_item("%s  %s" % [
			str(pilot.get("name", "?")),
			mech_label_for_pilot(str(pilot.get("id", ""))),
		], i + 1)
	pop.id_pressed.connect(func(id):
		var pilot_id := "" if id == 0 else str(pilots[id - 1].get("id", ""))
		if GlobalData.assign_hangar_pilot(mech_id, pilot_id):
			pop.queue_free()
			refresh_page()
	)
	pop.popup_hide.connect(func():
		if is_instance_valid(pop):
			pop.queue_free()
	)
	pop.popup(Rect2i(anchor_btn.global_position, Vector2i(280, 0)))
