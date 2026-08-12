class_name HangarReadinessPanel
extends RefCounted
# Owns the hangar's combat-readiness warning:
#   * check(on_confirm) — when the mech is fully assembled (legs + body) and
#     the piloted (active) mech's driver is fit to fight, call on_confirm
#     immediately; otherwise collect every warning (incomplete assembly, a
#     wounded recovering driver) into one modal offering LAUNCH ANYWAY (runs
#     on_confirm) or BACK TO HANGAR (dismisses).
#
# The modal is added to the controller's root_control so it draws above the
# hangar UI; everything is reached through `controller.`.

var controller  # hangar_controller.gd
# The warning modal is stored by reference: a fresh add_child would rename a
# same-name replacement while the stale one is still queued for deletion, so a
# name lookup would silently miss it on the next check and stack modals.
var _modal: Node = null


# Run on_confirm when the mech is assembled and the driver is combat-ready;
# otherwise warn the driver first (incomplete assembly and/or a wounded
# piloted driver who will not fight until healed).
func check(on_confirm: Callable) -> void:
	var has_legs = GlobalData.equipped_parts.has("leg_left") or GlobalData.equipped_parts.has("leg_right")
	var has_body = GlobalData.equipped_parts.has("body")
	var warnings: Array[String] = []
	if not (has_legs and has_body):
		warnings.append("Mech assembly is incomplete (missing a body or legs).")
	var driver_warning := _wounded_driver_warning()
	if driver_warning != "":
		warnings.append(driver_warning)

	if warnings.is_empty():
		on_confirm.call()
		return

	# Single modal for every warning, so a driver with several issues sees one
	# decision (LAUNCH ANYWAY / BACK TO HANGAR) instead of stacked prompts.
	_show_warning_modal(warnings, on_confirm)


# "" when the piloted (active) mech's driver is fit to fight; otherwise a
# short warning naming the recovering pilot. The active mech is what the player
# drives into battle — if a fleet pilot sits in its seat while wounded, they
# will NOT tag into combat as a squadmate until the countdown ends or the
# roster's HEAL clears it.
func _wounded_driver_warning() -> String:
	# Shared boolean from the roster system: only fleet pilots can be wounded,
	# so this is a single lookup for the driver's state (the message below adds
	# the name + countdown the boolean can't carry).
	if not GlobalData.is_active_driver_wounded():
		return ""
	var mech = GlobalData.get_active_hangar_mech()
	if mech.is_empty():
		return ""
	var pilot_id := str(mech.get("pilot", ""))
	var unit := GlobalData.get_fleet_unit(pilot_id.trim_prefix("fleet_"))
	var turns := maxi(int(unit.get("wound_turns", 1)), 1)
	# The combat-entry safety net parks this berth and auto-swaps a healthy
	# backup, so the warning is informational — the driver never fights.
	return "Pilot %s is WOUNDED (recovering %d move%s) — the game will park this mech and auto-swap a healthy backup on combat entry." % [
		str(unit.get("name", pilot_id)), turns, "s" if turns != 1 else ""]


func _show_warning_modal(warnings: Array[String], on_confirm: Callable) -> void:

	if _modal and is_instance_valid(_modal) and not _modal.is_queued_for_deletion():
		_modal.queue_free()

	var modal = PanelContainer.new()
	modal.name = "CombatWarningModal"
	modal.anchor_left = 0.5
	modal.anchor_right = 0.5
	modal.anchor_top = 0.5
	modal.anchor_bottom = 0.5
	modal.offset_left = -240
	modal.offset_right = 240
	modal.offset_top = -150
	modal.offset_bottom = 150

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.08, 0.08, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 0.4, 0.2)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	modal.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	modal.add_child(vbox)

	var title = Label.new()
	title.text = "⚠️ WARNING: NOT COMBAT READY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
	vbox.add_child(title)

	var msg = Label.new()
	msg.text = "\n".join(warnings) + "\n\nคุณยังคงเข้าเล่นด่านได้ (LAUNCH ANYWAY) หรือกลับไปจัดการใน hangar (BACK TO HANGAR)"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(msg)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 15)
	vbox.add_child(hbox)

	var launch_btn = Button.new()
	launch_btn.text = "LAUNCH ANYWAY (ลุยเลย)"
	launch_btn.custom_minimum_size = Vector2(140, 36)
	launch_btn.pressed.connect(func():
		modal.queue_free()
		on_confirm.call()
	)
	hbox.add_child(launch_btn)

	var back_btn = Button.new()
	back_btn.text = "BACK TO HANGAR (แต่งหุ่นต่อ)"
	back_btn.custom_minimum_size = Vector2(150, 36)
	back_btn.pressed.connect(func(): modal.queue_free())
	hbox.add_child(back_btn)

	_modal = modal
	controller.root_control.add_child(modal)
