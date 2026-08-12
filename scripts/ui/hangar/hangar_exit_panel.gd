class_name HangarExitPanel
extends RefCounted
# Owns the hangar's exit flow:
#   * close() — persist any edits, pass through the combat-readiness check,
#               then hide the hangar, unpause, save the run and return to the
#               board (or fall back to the intermission state).
#
# The engine-level pause-key handler stays on the controller (`_input`), which
# simply delegates here. All nodes are reached through `controller.`.

var controller  # hangar_controller.gd


# Persist any edits made on the customize page to the berth being edited,
# then restore the ACTIVE mech (the one the player actually pilots) back into
# the working set so combat loads the right machine.
func close() -> void:
	# Drop any in-progress frame assembly first (reverts loadout leaks back onto
	# the pre-flow berths) so its edits never persist as normal customize edits.
	if controller.roster_panel_ui:
		controller.roster_panel_ui.close_pending_register()
	controller.persist_panel.persist_edits()
	controller.readiness_panel.check(func():
		controller.visible = false
		controller.get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		GlobalData.save_run()
		if GameManager and GameManager.has_method("return_to_board"):
			GameManager.return_to_board()
		else:
			EventBus.game_state_changed.emit("HANGAR", "INTERMISSION")
	)
