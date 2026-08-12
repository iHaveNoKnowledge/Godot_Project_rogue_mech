class_name HangarReadinessPanel
extends RefCounted
# Owns the hangar's combat-readiness warning:
#   * check(on_confirm) — if the mech has legs + a body, call on_confirm
#     immediately; otherwise show a modal offering LAUNCH ANYWAY (runs
#     on_confirm) or BACK TO HANGAR (dismisses).
#
# The modal is added to the controller's root_control so it draws above the
# hangar UI; everything is reached through `controller.`.

var controller  # hangar_controller.gd
# The warning modal is stored by reference: a fresh add_child would rename a
# same-name replacement while the stale one is still queued for deletion, so a
# name lookup would silently miss it on the next check and stack modals.
var _modal: Node = null


# Run on_confirm when the mech is assembled; otherwise warn the driver first.
func check(on_confirm: Callable) -> void:
	var has_legs = GlobalData.equipped_parts.has("leg_left") or GlobalData.equipped_parts.has("leg_right")
	var has_body = GlobalData.equipped_parts.has("body")

	if has_legs and has_body:
		on_confirm.call()
		return

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
	modal.offset_top = -140
	modal.offset_bottom = 140

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
	title.text = "⚠️ WARNING: INCOMPLETE MECH ASSEMBLY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
	vbox.add_child(title)

	var msg = Label.new()
	msg.text = "คำเตือน: หุ่นของคุณประกอบไม่ครบชุด (ไม่มีขา/เกราะไม่ครบ)!\nอาจทำให้เคลื่อนที่และต่อสู้ในด่านได้ยากลำบาก\n\n(คุณยังคงเข้าเล่นด่านได้ แล้วแต่ศรัทธา - รองรับ Hover ในอนาคต)"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
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
