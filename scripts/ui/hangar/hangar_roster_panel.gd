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
# Live checklist rows (required frame -> {mark, name} labels) in the pending
# banner; each row ticks ✓/✗ as the matching frame is equipped/unequipped.
var pending_checklist_labels: Dictionary = {}
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
	style_roster.bg_color = Color(0.09, 0.09, 0.09, 0.96)
	style_roster.corner_radius_top_left = 0
	style_roster.corner_radius_bottom_left = 0
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
	if GlobalData.narrative.mech_less:
		mech_slot_label.text = "ON FOOT — NO MECH PARKED"
		return
	var capacity := HangarManager.get_capacity()
	var mechs := HangarManager.get_mechs()
	var editing_id: String = controller.get_editing_mech_id()
	var editing: Dictionary = {}
	for m in mechs:
		if str(m.get("id", "")) == editing_id:
			editing = m
			break
	var slot := int(editing.get("slot", 0))
	if slot <= 0:
		slot = HangarManager.get_slot_of(editing_id)
	if slot <= 0:
		slot = 1
	var name_str := str(editing.get("name", "Mech")) if not editing.is_empty() else "Mech"
	# Show who drives the berth being edited: the berth->pilot lookup is shared
	# with the stats panel (resolves fleet pilots + the player driver).
	var pilot_str := HangarManager.get_mech_pilot_name(editing_id)
	var driver_note := ""
	if editing_id == GlobalData.hangar.active_hangar_mech_id:
		driver_note = " · PILOTING"
	mech_slot_label.text = "MECH SLOT %d/%d · %s · PILOT: %s%s" % [slot, capacity, name_str, pilot_str, driver_note]


# Pages between parked mechs (wrap-around). This only changes which mech is
# being edited on the customize/roster page — it does NOT switch the player's
# active (piloting) mech, which stays untouched until the player assigns a
# pilot or drives it into combat.
func cycle_hangar_mech(direction: int) -> void:
	var mechs := HangarManager.get_mechs()
	if mechs.size() <= 1:
		return
	# Editing target defaults to the active mech on first open.
	var current_id: String = controller.get_editing_mech_id()
	# Persist edits made on the berth we're leaving before loading the next one.
	if current_id != "":
		HangarManager.save_mech_state(current_id)
	var index := -1
	for i in range(mechs.size()):
		if str(mechs[i].get("id", "")) == current_id:
			index = i
			break
	if index < 0:
		index = 0
	var next := (index + direction + mechs.size()) % mechs.size()
	var target_id := str(mechs[next].get("id", ""))
	if not HangarManager.load_mech_state(target_id):
		return
	controller.set_editing_mech_id(target_id)
	controller.selected_chassis_key = GlobalData.weapons.chassis_id
	refresh_badge()
	controller.refresh_panel.after_mech_change(true)
	if roster_panel and roster_panel.visible:
		refresh_page()


func refresh_page() -> void:
	if roster_slot_list == null:
		return
	HangarManager.ensure_roster()
	var capacity := HangarManager.get_capacity()
	var fleet := HangarManager.get_fleet_size()
	var mechs := HangarManager.get_mechs()
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

	# The persistent wounded-pilot banner follows every roster mutation (heal,
	# assign, switch, register) — repaint it here, the single refresh seam.
	if controller and controller.wounded_banner:
		controller.wounded_banner.refresh()

	if roster_status_label:
		var affiliation := ThemeSystem.get_affiliation()
		var aff_prefix := "%s · %s" % [
			affiliation.get("name", "Mech Convoy"),
			affiliation.get("transport", "Truck convoy"),
		]
		if GlobalData.narrative.mech_less:
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
		if not GlobalData.narrative.mech_less:
			var register_btn := Button.new()
			register_btn.text = "REGISTER"
			register_btn.tooltip_text = "Assemble a mech frame into this berth from the currently assembled parts (free; needs a body + both leg frames)."
			register_btn.custom_minimum_size = Vector2(96, 28)
			register_btn.focus_mode = Control.FOCUS_NONE
			register_btn.pressed.connect(register_mech.bind(slot))
			row.add_child(register_btn)

		var hint := Label.new()
		hint.text = "Assemble a frame from the current build · free (needs a body + both leg frames)" \
			if not GlobalData.narrative.mech_less else "On foot — rebuild a chassis through recovery missions"
		hint.custom_minimum_size = Vector2(200, 0)
		hint.add_theme_font_size_override("font_size", 10)
		hint.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
		row.add_child(hint)
		return

	var mech_id := str(mech.get("id", ""))
	var is_active := mech_id == GlobalData.hangar.active_hangar_mech_id

	var name_lbl := Label.new()
	name_lbl.text = "%s%s" % [
		str(mech.get("name", "Unnamed Mech")),
		" [ACTIVE]" if is_active else "",
	]
	name_lbl.custom_minimum_size = Vector2(150, 0)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4) if is_active else Color(0.85, 0.9, 0.95))
	row.add_child(name_lbl)

	var pilot_id := str(mech.get("pilot", ""))
	# Fleet pilots carry their live status (HP / wounded countdown / destroyed)
	# on the row; hurt or dead drivers are tinted red for a quick read.
	var pilot_status := HangarManager.get_pilot_status(pilot_id)
	var is_wounded := pilot_status.contains("WOUNDED")
	# A wounded pilot can be seated but is NOT fielded until healed: the mech
	# stays parked (its ally never tags into combat), so mark the row clearly.
	if is_wounded:
		pilot_status += " · RECOVERING (not fielded)"
	var pilot_lbl := Label.new()
	pilot_lbl.text = "PILOT: %s%s" % [HangarManager.get_pilot_name(pilot_id), pilot_status]
	pilot_lbl.add_theme_color_override("font_color",
		Color(1.0, 0.5, 0.5) if is_wounded or pilot_status.contains("DESTROYED") else Color(0.55, 0.8, 1.0))
	pilot_lbl.custom_minimum_size = Vector2(160, 0)
	pilot_lbl.add_theme_font_size_override("font_size", 11)
	# Hovering a WOUNDED row explains the countdown: recovery ticks down on every
	# board move, and the HEAL button skips the wait for credits.
	if pilot_id.begins_with("fleet_") and is_wounded:
		var template_id := pilot_id.trim_prefix("fleet_")
		var turns := 0
		var unit := FleetSystem.get_fleet_unit(template_id)
		if not unit.is_empty():
			turns = maxi(int(unit.get("wound_turns", 1)), 1)
		var heal_cost := RecruitSystem.get_wound_heal_cost(template_id)
		pilot_lbl.tooltip_text = "WOUNDED — recovering (%d board move%s left).\nReturns to the field at half HP when the timer ends,\nor press HEAL (%d cr) to recover now at full HP." % [
			turns, "s" if turns != 1 else "", heal_cost]
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

	# Wounded fleet pilots get a HEAL button: spend credits on the roster to
	# clear their recovery countdown and return them to the field at full HP.
	if pilot_id.begins_with("fleet_") and is_wounded:
		var template_id := pilot_id.trim_prefix("fleet_")
		var heal_cost := RecruitSystem.get_wound_heal_cost(template_id)
		var heal_btn := Button.new()
		heal_btn.text = "HEAL (%dcr)" % heal_cost
		heal_btn.custom_minimum_size = Vector2(88, 28)
		heal_btn.focus_mode = Control.FOCUS_NONE
		heal_btn.tooltip_text = "Spend %d credits to heal this pilot now (full HP, back in the field)." % heal_cost
		heal_btn.pressed.connect(heal_pilot.bind(template_id))
		row.add_child(heal_btn)

	if not is_active and not over_capacity:
		var switch_btn := Button.new()
		switch_btn.text = "SWITCH"
		switch_btn.custom_minimum_size = Vector2(80, 28)
		switch_btn.focus_mode = Control.FOCUS_NONE
		switch_btn.pressed.connect(on_switch_mech_pressed.bind(mech_id))
		row.add_child(switch_btn)


# REGISTER — starts a from-zero assembly that ends as a parked mech in an
# empty convoy berth. Pressing it wipes the working set (blank slate, no parts
# carried over from the current mech) and jumps into the customize page
# (INNER SKELETON mode, BODY slot) so the player can equip the frames the new
# mech needs; the pending banner then confirms the registration, locked until
# a walking chassis (body + both legs) is equipped. On confirm the frame
# becomes the player's mech (active + pilot) — assembly is free, the frame
# belongs to the player.
func register_mech(slot: int) -> void:
	if GlobalData.narrative.mech_less:
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
		if not GlobalData.weapons.equipped_frames.has(required) or GlobalData.weapons.equipped_frames[required] == null:
			return false
	return true


# Arms the pending registration for `slot`: raises the banner on the customize
# page and records which berth the confirmation should fill.
func start_pending_register(slot: int) -> void:
	close_pending_register()
	_pending_register_slot = slot
	_capture_pending_originals()
	# A fresh frame is assembled from nothing: wipe the current working set so
	# the customize page starts from an empty build (no hand-me-down frames,
	# armor or attachments from the machine being edited), then repaint the
	# garage + part list around the blank slate. The banner's REGISTER FRAME
	# stays locked until a walking chassis is equipped.
	GlobalData.clear_working_set()
	# The new mech starts UNARMED too: clear_working_set() keeps the current
	# weapon loadout (so a mech whose frame was lost keeps its arms), but a
	# brand-new build must not inherit the previous mech's weapons — that
	# created duplicate copies of the same weapon model on two berths.
	GlobalData.weapons.weapon_loadout = {"left": "", "right": "", "carry": [], "ammo": {}}
	build_pending_register_banner(slot)
	controller.refresh_panel.after_mech_change(true)
	_set_status("Assembling SLOT %02d — equip a BODY + both legs (INNER SKELETON), then press REGISTER FRAME." % slot)


# Snapshots the loadouts of the berths the working set can leak onto during the
# assembly (the editing target + the active driver) so they can be restored
# once the registration completes or is abandoned.
func _capture_pending_originals() -> void:
	_pending_original_editing = {}
	_pending_original_active = {}
	var editing_id: String = controller.get_editing_mech_id()
	var active_id: String = GlobalData.hangar.active_hangar_mech_id
	for m in HangarManager.get_mechs():
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
		HangarManager.load_mech_state(editing_id)
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
		HangarManager.restore_berth_loadout(str(_pending_original_editing.get("id", "")), _pending_original_editing)
	if not _pending_original_active.is_empty():
		HangarManager.restore_berth_loadout(str(_pending_original_active.get("id", "")), _pending_original_active)


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
	# Below the 80px header + mode-toggle bar. If the persistent wounded-pilot
	# banner (offset_top 122, content-height) is showing, stack below it instead
	# of overlapping, so the two center-top panels never collide.
	var banner_top := 132
	if controller and controller.wounded_banner and controller.wounded_banner.banner_panel:
		var wounded: PanelContainer = controller.wounded_banner.banner_panel
		if wounded.visible and wounded.size.y > 0.0:
			banner_top = int(122.0 + wounded.size.y + 8.0)
	modal.offset_top = banner_top
	modal.offset_bottom = banner_top + 168

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.09, 0.96)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = controller._highlight_color
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
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

	var free_lbl := Label.new()
	free_lbl.text = "FREE ASSEMBLY — the frame is yours to build however you like."
	free_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	free_lbl.add_theme_color_override("font_color", Color(0.45, 0.85, 0.5))
	free_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(free_lbl)

	# Required-frame checklist: one row per frame, ticking off live as the
	# player equips each piece (refreshed on every committed edit).
	var checklist_box := VBoxContainer.new()
	checklist_box.add_theme_constant_override("separation", 2)
	vbox.add_child(checklist_box)
	pending_checklist_labels.clear()
	for required in HangarManager.REQUIRED_WALKING_FRAMES:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		var mark := Label.new()
		mark.add_theme_font_size_override("font_size", 12)
		row.add_child(mark)
		var name_lbl := Label.new()
		name_lbl.add_theme_font_size_override("font_size", 11)
		match required:
			"leg_left":
				name_lbl.text = "LEFT LEG"
			"leg_right":
				name_lbl.text = "RIGHT LEG"
			_:
				name_lbl.text = required.to_upper()
		row.add_child(name_lbl)
		checklist_box.add_child(row)
		pending_checklist_labels[required] = {"mark": mark, "name": name_lbl}

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
	refresh_pending_register()


# Re-evaluates the pending banner: repaints the required-frame checklist (✓/✗)
# and locks/unlocks the REGISTER FRAME confirm. Hooked into the persist flow
# (persist_panel.commit_and_save) so every equip/unequip refreshes it.
func refresh_pending_register() -> void:
	if pending_register_banner == null or not is_instance_valid(pending_register_banner):
		return
	var done_color := Color(0.45, 0.9, 0.5)
	var missing_color := Color(0.95, 0.4, 0.4)
	var dim_color := Color(0.6, 0.65, 0.75)
	for required in HangarManager.REQUIRED_WALKING_FRAMES:
		var ok := GlobalData.weapons.equipped_frames.has(required) and GlobalData.weapons.equipped_frames[required] != null
		var row: Dictionary = pending_checklist_labels.get(required, {})
		var mark: Label = row.get("mark")
		var name_lbl: Label = row.get("name")
		if mark:
			mark.text = "✓" if ok else "✗"
			mark.add_theme_color_override("font_color", done_color if ok else missing_color)
		if name_lbl:
			name_lbl.add_theme_color_override("font_color", Color.WHITE if ok else dim_color)
	if pending_register_button:
		pending_register_button.disabled = not _has_walking_chassis()


# REGISTER FRAME on the banner: opens the name prompt, locked out with a status
# message while the chassis is incomplete. Assembly is free — the frame belongs
# to the player, so no resource gate is applied.
func _on_pending_register_pressed() -> void:
	var slot := _pending_register_slot
	if slot < 0:
		return
	if not _has_walking_chassis():
		_set_status("REGISTER needs a walking chassis (body + both leg frames) equipped.")
		return
	close_register_dialog()
	build_register_dialog(slot)


# Drops the pending registration (banner + slot). Unless the registration
# already succeeded (revert_working_set = false), also reverts the loadout
# leaks onto the pre-flow berths. Called on abandon, on the hangar menu / exit,
# and after a successful registration.
# True while a REGISTER assembly is armed (the pending banner is up). The
# garage preview reads this to decide whether missing frame slots should render
# as translucent ghosts instead of disappearing.
func is_pending_register_active() -> bool:
	return pending_register_banner != null and is_instance_valid(pending_register_banner)


func close_pending_register(revert_working_set: bool = true) -> void:
	var was_armed := pending_register_banner != null and is_instance_valid(pending_register_banner)
	if pending_register_banner and is_instance_valid(pending_register_banner):
		pending_register_banner.queue_free()
	pending_register_banner = null
	pending_register_button = null
	pending_checklist_labels.clear()
	_pending_register_slot = -1
	if revert_working_set:
		_restore_pending_flow()
		# The assembly is gone: repaint the customize page around the restored
		# working set so ghost frames don't linger on slots that have gear again.
		# Only when something was actually armed (boot/menu visits call this
		# with nothing pending and must not stomp the panel state).
		if was_armed and controller and controller.refresh_panel:
			controller.refresh_panel.after_mech_change(true)


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
	style.bg_color = Color(0.09, 0.09, 0.09, 0.96)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = controller._highlight_color
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
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

	var hint := Label.new()
	hint.text = "Name the frame — registering it makes it your piloted mech."
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


# Assembly is free — the frame belongs to the player, so no resource gate is
# needed on the confirm path.


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
	var new_mech := HangarManager.build(chosen, slot)
	if new_mech.is_empty():
		# Re-check the chassis gate for an accurate message (frames could have
		# changed while the dialog was open).
		_set_status("REGISTER needs a walking chassis (body + both leg frames) equipped."
			if not _has_walking_chassis() else "No free berth in the convoy.")
		return
	# Assembly is free — the frame is the player's own, so nothing is charged.
	# The freshly assembled frame takes over as the player's mech (the previous
	# one parks as a pilotless spare) so tuning it on the customize page carries
	# straight into the next fight. Registering just names it: no pilot pick.
	var new_id := str(new_mech.get("id", ""))
	controller.set_editing_mech_id(new_id)
	if HangarManager.switch_mech(new_id):
		controller.selected_chassis_key = GlobalData.weapons.chassis_id
	HangarManager.assign_pilot(new_id, HangarManager.PLAYER_PILOT_ID)
	# The assembled frames leaked onto the pre-flow berths via equip commits
	# (commit_and_save) and build()/switch_mech()'s save_active() — the new mech
	# is the only one that should carry the new build, so restore their loadouts
	# (the pilot swap above is preserved: restore never touches identity fields).
	_restore_pending_roster_only()
	GlobalData.save_run()
	# Distinct cue: the frame is assembled and takes over as the player's mech.
	AudioManager.play_mech_register()
	refresh_page()
	# Close the pending banner BEFORE the final refresh so the new mech's
	# missing slots render as plain empty (ghosts are only for the in-progress
	# assembly, not for the finished build the player now tunes).
	close_pending_register(false)
	controller.refresh_panel.after_mech_change(false)
	controller.nav_panel.select_submenu("customize")
	_set_status("Registered %s in SLOT %02d — it is now your piloted mech — tune it here." % [
		str(new_mech.get("name", "Mech")), slot])


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
	for m in HangarManager.get_mechs():
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
	style.bg_color = Color(0.09, 0.09, 0.09, 0.96)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = controller._highlight_color
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
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
	if not HangarManager.rename_mech(mech_id, chosen):
		_set_status("Unable to rename that berth.")
		return
	GlobalData.save_run()
	refresh_badge()
	refresh_page()
	var final_name := ""
	for m in HangarManager.get_mechs():
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
	var current := HangarManager.get_archetype(mech_id)
	for i in range(roles.size()):
		var role: Dictionary = roles[i]
		var label := str(role["label"])
		if int(role["archetype"]) == current:
			label = "● " + label
		pop.add_item(label, i)
	pop.id_pressed.connect(func(id):
		var archetype: int = int(roles[id]["archetype"])
		if HangarManager.set_archetype(mech_id, archetype):
			GlobalData.save_run()
			pop.queue_free()
			refresh_page()
	)
	pop.popup_hide.connect(func():
		if is_instance_valid(pop):
			pop.queue_free()
	)
	pop.popup(Rect2i(anchor_btn.global_position, Vector2i(320, 0)))


# HEAL on a wounded fleet-pilot row: spend the credit cost to clear the
# recovery countdown immediately. Reports the result through the shared status
# label and repaints the roster so the button disappears once healed.
func heal_pilot(template_id: String) -> void:
	var cost := RecruitSystem.get_wound_heal_cost(template_id)
	if cost <= 0:
		_set_status("That pilot is not wounded — nothing to heal.")
		return
	if not RecruitSystem.heal_wounded_pilot(template_id):
		# The heal spends the credits itself; a failure here means the price
		# moved (or resources were drained while the roster was open).
		if GlobalData.currency.credits < cost:
			_set_status("Need %d credits to heal this pilot." % cost)
		else:
			_set_status("The pilot could not be healed.")
		return
	GlobalData.save_run()
	refresh_badge()
	refresh_page()
	var unit := FleetSystem.get_fleet_unit(template_id)
	_set_status("%s is healed and ready to fight (-%d credits)." % [
		str(unit.get("name", "The pilot")), cost])


func on_switch_mech_pressed(mech_id: String) -> void:
	if not HangarManager.switch_mech(mech_id):
		if roster_status_label:
			roster_status_label.text = "Unable to load that hangar mech."
		return
	# The player is now piloting this berth, so the editor follows along. The
	# YOU seat moves over too: the piloted mech (what combat loads) and the
	# roster's driver label must agree, or the badge/garage/sortie point at a
	# different mech than the one actually fielded.
	HangarManager.assign_pilot(mech_id, HangarManager.PLAYER_PILOT_ID)
	controller.set_editing_mech_id(mech_id)
	controller.selected_chassis_key = GlobalData.weapons.chassis_id
	GlobalData.save_run()
	refresh_badge()
	refresh_page()
	controller.refresh_panel.after_mech_change(false)
	if roster_status_label:
		roster_status_label.text = "Loaded %s." % str(HangarManager.get_active_mech().get("name", "Mech"))


func mech_label_for_pilot(pilot_id: String) -> String:
	for mech in HangarManager.get_mechs():
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
	var pilots := HangarManager.get_pilots()
	for i in range(pilots.size()):
		var pilot: Dictionary = pilots[i]
		var pilot_id := str(pilot.get("id", ""))
		# Fleet pilots carry their live status (HP / wounded countdown /
		# destroyed) here too — same suffix the roster rows show, so a hurt or
		# dead driver is readable before assigning them.
		var status := HangarManager.get_pilot_status(pilot_id)
		var marker := ""
		if status.contains("WOUNDED"):
			marker = "⚠ "
		elif status.contains("DESTROYED"):
			marker = "⛔ "
		# Wounded pilots stay ASSIGNABLE (the seat waits for them) but are
		# flagged RECOVERING — they will not tag into combat until healed.
		var suffix := ""
		if status.contains("WOUNDED"):
			suffix = " · RECOVERING"
		var label := "%s%s%s%s  %s" % [
			marker,
			str(pilot.get("name", "?")),
			status,
			suffix,
			mech_label_for_pilot(pilot_id),
		]
		pop.add_item(label, i + 1)
		if status.contains("WOUNDED"):
			# Same recovery explanation as the roster-row tooltip: the countdown
			# ticks on every board move and HEAL skips the wait for credits.
			var template_id := pilot_id.trim_prefix("fleet_") if pilot_id.begins_with("fleet_") else ""
			var turns := 0
			var unit := FleetSystem.get_fleet_unit(template_id) if template_id != "" else {}
			if not unit.is_empty():
				turns = maxi(int(unit.get("wound_turns", 1)), 1)
			var heal_cost := RecruitSystem.get_wound_heal_cost(template_id)
			pop.set_item_tooltip(i + 1, "WOUNDED — recovering (%d board move%s left).\nCan be assigned to a mech, but they will NOT fight until healed.\nRecover at half HP when the timer ends, or heal from its roster row for %d cr." % [
				turns, "s" if turns != 1 else "", heal_cost])
		elif status.contains("DESTROYED"):
			pop.set_item_tooltip(i + 1, "This pilot was lost in combat — they cannot be assigned.")
			pop.set_item_disabled(i + 1, true)
	pop.id_pressed.connect(func(id):
		var pilot_id := "" if id == 0 else str(pilots[id - 1].get("id", ""))
		if HangarManager.assign_pilot(mech_id, pilot_id):
			pop.queue_free()
			# Seating the player in a berth means they pilot it: switch the
			# active mech (what combat loads) to follow the YOU label, so the
			# two can never disagree again.
			if pilot_id == HangarManager.PLAYER_PILOT_ID and mech_id != GlobalData.hangar.active_hangar_mech_id:
				HangarManager.switch_mech(mech_id)
				controller.set_editing_mech_id(mech_id)
				controller.selected_chassis_key = GlobalData.weapons.chassis_id
				GlobalData.save_run()
				refresh_badge()
				controller.refresh_panel.after_mech_change(false)
			refresh_page()
	)
	pop.popup_hide.connect(func():
		if is_instance_valid(pop):
			pop.queue_free()
	)
	pop.popup(Rect2i(anchor_btn.global_position, Vector2i(280, 0)))
