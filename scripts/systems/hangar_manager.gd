class_name HangarManager
extends RefCounted

# -----------------------------------------------------------------------------
# HANGAR MECH ROSTER
# Built-mech roster logic extracted from GlobalData so the run-state autoload
# stays focused on state. Every function reads/writes the roster state
# (GlobalData.hangar_mechs / GlobalData.active_hangar_mech_id) through the
# GlobalData singleton, and GlobalData keeps thin build_hangar_mech()/
# switch_hangar_mech()/... facades for its existing callers.
#
# A roster entry is a built machine that can be selected in the hangar. It is
# deliberately a loadout snapshot, so entering a different mech never mutates
# the catalog or invents a placeholder backup body.
# -----------------------------------------------------------------------------


static func ensure_roster() -> void:
	if not GlobalData.hangar_mechs.is_empty():
		if GlobalData.active_hangar_mech_id == "" or _find(GlobalData.active_hangar_mech_id).is_empty():
			GlobalData.active_hangar_mech_id = str(GlobalData.hangar_mechs[0].get("id", ""))
		return
	var first_id := _new_id()
	GlobalData.hangar_mechs.append(_capture_snapshot(first_id, "Mech 01"))
	GlobalData.active_hangar_mech_id = first_id


static func get_mechs() -> Array:
	ensure_roster()
	return GlobalData.hangar_mechs


static func get_active_mech() -> Dictionary:
	ensure_roster()
	return _find(GlobalData.active_hangar_mech_id)


static func save_active() -> bool:
	ensure_roster()
	var active := _find(GlobalData.active_hangar_mech_id)
	if active.is_empty():
		return false
	var updated := _capture_snapshot(GlobalData.active_hangar_mech_id, str(active.get("name", "Mech")))
	for i in range(GlobalData.hangar_mechs.size()):
		if str(GlobalData.hangar_mechs[i].get("id", "")) == GlobalData.active_hangar_mech_id:
			GlobalData.hangar_mechs[i] = updated
			return true
	return false


# Builds another hangar entry from the currently assembled parts. A complete
# walking chassis needs a body frame and both leg frames; armor is optional and
# can be installed later in the normal hangar editor.
static func build(mech_name: String = "") -> Dictionary:
	for required in ["body", "leg_left", "leg_right"]:
		if not GlobalData.equipped_frames.has(required) or GlobalData.equipped_frames[required] == null:
			return {}
	if GlobalData.hangar_mechs.size() >= GlobalData.HANGAR_MAX_SLOTS:
		return {}
	save_active()
	var mech_id := _new_id()
	var display_name := mech_name.strip_edges()
	if display_name == "":
		display_name = "Mech %02d" % (GlobalData.hangar_mechs.size() + 1)
	var snapshot := _capture_snapshot(mech_id, display_name)
	GlobalData.hangar_mechs.append(snapshot)
	return snapshot


static func get_backup_id() -> String:
	ensure_roster()
	for mech in GlobalData.hangar_mechs:
		var mech_id := str(mech.get("id", ""))
		if mech_id != "" and mech_id != GlobalData.active_hangar_mech_id:
			return mech_id
	return ""


static func switch_mech(mech_id: String) -> bool:
	ensure_roster()
	var target := _find(mech_id)
	if target.is_empty() or mech_id == GlobalData.active_hangar_mech_id:
		return not target.is_empty()
	save_active()

	# Release the old armor instances before attaching the target references.
	for old_part in GlobalData.equipped_parts.values():
		if old_part is Dictionary and old_part.has("uid"):
			var old_inst := GlobalData.get_armor_instance(str(old_part["uid"]))
			if not old_inst.is_empty():
				old_inst["equipped"] = false

	GlobalData.chassis_id = str(target.get("chassis_id", "standard"))
	GlobalData.equipped_frames.clear()
	var saved_frames: Dictionary = target.get("frames", {})
	for slot in saved_frames:
		GlobalData.equipped_frames[slot] = SaveGameIO.resolve_frame_value(saved_frames[slot])
	GlobalData._ensure_default_frames()

	GlobalData.equipped_parts.clear()
	var saved_parts: Dictionary = target.get("parts", {})
	for slot in saved_parts:
		var part = SaveGameIO.resolve_equipped_part(saved_parts[slot])
		GlobalData.equipped_parts[slot] = part
		if part is Dictionary and part.has("uid"):
			part["equipped"] = true

	GlobalData.part_damage = target.get("damage", {}).duplicate(true)
	GlobalData.attachments = target.get("attachments", []).duplicate(true)
	GlobalData.weapon_loadout = target.get("weapon_loadout", GlobalData.weapon_loadout).duplicate(true)
	GlobalData.scrap_patches = target.get("scrap_patches", {}).duplicate(true)
	GlobalData.active_hangar_mech_id = mech_id
	return true


static func _capture_snapshot(mech_id: String, mech_name: String) -> Dictionary:
	GlobalData.sync_equipped_armor_durability()
	return {
		"id": mech_id,
		"name": mech_name,
		"chassis_id": GlobalData.chassis_id,
		"frames": SaveGameIO.serialize_frames(),
		"parts": SaveGameIO.serialize_parts(),
		"damage": GlobalData.part_damage.duplicate(true),
		"attachments": SaveGameIO.serialize_attachments(),
		"weapon_loadout": GlobalData.weapon_loadout.duplicate(true),
		"scrap_patches": GlobalData.scrap_patches.duplicate(true),
	}


static func _find(mech_id: String) -> Dictionary:
	for mech in GlobalData.hangar_mechs:
		if mech is Dictionary and str(mech.get("id", "")) == mech_id:
			return mech
	return {}


static func _new_id() -> String:
	return GlobalData._new_uid("mech")
