class_name HangarPersistPanel
extends RefCounted
# Owns the hangar's mech-editing persist/save flow:
#   * persist_edits()  — on exit: save the working set onto the berth being
#                        edited, then reload the ACTIVE mech's parts so combat
#                        loads the machine the player actually pilots.
#   * commit_and_save() — after equip/unequip: push the working set onto the
#                        edited berth (fresh roster snapshot) and save the run.
#
# The editing target (_customize_mech_id) stays on the controller; this panel
# reads/writes it through `controller.`.

var controller  # hangar_controller.gd


# Save the current working set onto the mech that's open in the editor, then
# (if that isn't the active/piloting mech) reload the active mech's parts so the
# player leaves the hangar with the machine they'll actually pilot.
func persist_edits() -> void:
	var editing_id: String = controller.get_editing_mech_id()
	if editing_id == "":
		return
	GlobalData.save_hangar_mech_state(editing_id)
	controller._customize_mech_id = editing_id
	if editing_id != GlobalData.active_hangar_mech_id:
		GlobalData.load_hangar_mech_state(GlobalData.active_hangar_mech_id)


# Persist the working set back onto the berth being edited (so its roster
# snapshot is fresh), then save the run. Called after equip/unequip so edits to
# a non-active mech on the customize page land on the right entry.
func commit_and_save() -> void:
	if controller._customize_mech_id != "":
		GlobalData.save_hangar_mech_state(controller._customize_mech_id)
	GlobalData.save_run()
