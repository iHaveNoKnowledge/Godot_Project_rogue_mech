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
#
# The roster models a truck convoy. The hangar is the fleet's transport: a lone
# driver owns one small trailer that parks 2 mechs; every two fleet pilots buy
# one more transport, and each fleet truck parks 4 berths. So a fleet of 3
# pilots (YOU + 2 squadmates) gets 2 trucks -> 8 berths, shown as "3/8".
#
# Each parked mech also records which pilot (YOU or a fleet unit) drives it.
# Pilots are just labels in the snapshot; they can be freely reassigned between
# mechs, which moves the driver between berths without touching the loadouts.
# -----------------------------------------------------------------------------

const PLAYER_PILOT_ID := "player"

# Combat archetype a parked mech fights as when fielded as an ally. Matches the
# enemy archetype enum: 0=Rusher melee, 1=Ranged, 2=Heavy, 3=Support. Stored in
# the snapshot so the roster page can assign it per berth.
const ARCHETYPE_RUSHER := 0
const ARCHETYPE_RANGED := 1
const ARCHETYPE_HEAVY := 2
const ARCHETYPE_SUPPORT := 3


# Number of pilots in the convoy: the player driver plus every researched fleet
# unit (regardless of fielded/destroyed status — they still occupy a berth).
static func get_fleet_size() -> int:
	return maxi(1, GlobalData.fleet_roster.size() + 1)


# Parking berths in the convoy. Solo driver: 1 trailer, 2 berths. Fleet:
# ceil(fleet/2) trucks at 4 berths each (3 pilots -> 2 trucks -> 8 berths).
static func get_capacity() -> int:
	var fleet_size := get_fleet_size()
	if fleet_size <= 1:
		return 2
	return ceili(fleet_size / 2.0) * 4


# Physical hard cap for the roster array. Kept above any fleet-derived capacity
# so a save made under a bigger fleet never loses parked mechs.
static func get_hard_max() -> int:
	return GlobalData.HANGAR_HARD_MAX


# Every pilot available in the convoy. Entries are {id, name}. Fleet units are
# keyed by their template so a pilot survives renames in the fleet roster.
static func get_pilots() -> Array:
	var pilots: Array = [{"id": PLAYER_PILOT_ID, "name": "YOU (driver)"}]
	for unit in GlobalData.fleet_roster:
		if unit is Dictionary:
			pilots.append({
				"id": "fleet_%s" % str(unit.get("template_id", "")),
				"name": str(unit.get("name", "Fleet Unit")),
			})
	return pilots


static func get_pilot_name(pilot_id: String) -> String:
	if pilot_id == "":
		return "(no pilot)"
	for pilot in get_pilots():
		if str(pilot.get("id", "")) == pilot_id:
			return str(pilot.get("name", pilot_id))
	return pilot_id


static func ensure_roster() -> void:
	if GlobalData.mech_less:
		return
	if GlobalData.hangar_mechs.is_empty():
		var first_id := _new_id()
		GlobalData.hangar_mechs.append(_capture_snapshot(first_id, "Mech 01", PLAYER_PILOT_ID, 1))
		GlobalData.active_hangar_mech_id = first_id
	else:
		if GlobalData.active_hangar_mech_id == "" or _find(GlobalData.active_hangar_mech_id).is_empty():
			GlobalData.active_hangar_mech_id = str(GlobalData.hangar_mechs[0].get("id", ""))
	if _migrate_old_saves():
		GlobalData.save_run()


# Old saves predate pilots/slots: back-fill a stable slot number for every mech
# and hand unassigned pilots to parked mechs (player driver first). Returns true
# if anything changed so the caller can persist the migration once.
static func _migrate_old_saves() -> bool:
	var dirty := false
	var used_slots: Dictionary = {}
	var used_pilots: Dictionary = {}
	for mech in GlobalData.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var slot := int(mech.get("slot", 0))
		if slot > 0:
			used_slots[slot] = true
		var pilot := str(mech.get("pilot", ""))
		if pilot != "":
			used_pilots[pilot] = true

	var next_slot := 1
	var free_pilots: Array = []
	for pilot in get_pilots():
		if not used_pilots.has(str(pilot.get("id", ""))):
			free_pilots.append(str(pilot.get("id", "")))

	for mech in GlobalData.hangar_mechs:
		if not (mech is Dictionary):
			continue
		if int(mech.get("slot", 0)) <= 0:
			while used_slots.has(next_slot):
				next_slot += 1
			mech["slot"] = next_slot
			used_slots[next_slot] = true
			dirty = true
		# Only legacy entries that never had a pilot field get back-filled. A mech
		# whose pilot is explicitly "" (a spare berth) must stay empty, otherwise
		# every roster refresh would re-seat spare mechs with squadmates.
		if not mech.has("pilot"):
			var new_pilot := ""
			if not free_pilots.is_empty():
				new_pilot = free_pilots.pop_front()
			mech["pilot"] = new_pilot
			dirty = true
		if not mech.has("archetype"):
			mech["archetype"] = ARCHETYPE_RANGED
			dirty = true
	return dirty


static func get_mechs() -> Array:
	ensure_roster()
	var sorted := GlobalData.hangar_mechs.duplicate()
	sorted.sort_custom(func(a, b):
		return int(a.get("slot", 0x7FFFFFFF)) < int(b.get("slot", 0x7FFFFFFF)))
	return sorted


static func get_active_mech() -> Dictionary:
	ensure_roster()
	return _find(GlobalData.active_hangar_mech_id)


static func save_active() -> bool:
	ensure_roster()
	var active := _find(GlobalData.active_hangar_mech_id)
	if active.is_empty():
		return false
	var updated := _capture_snapshot(
		GlobalData.active_hangar_mech_id,
		str(active.get("name", "Mech")),
		str(active.get("pilot", "")),
		int(active.get("slot", get_slot_of(GlobalData.active_hangar_mech_id))),
	)
	for i in range(GlobalData.hangar_mechs.size()):
		if str(GlobalData.hangar_mechs[i].get("id", "")) == GlobalData.active_hangar_mech_id:
			GlobalData.hangar_mechs[i] = updated
			return true
	return false


# Builds another hangar entry from the currently assembled parts and parks it in
# `requested_slot` (0 = first free berth). A complete walking chassis needs a
# body frame and both leg frames; armor is optional and can be installed later
# in the normal hangar editor. The newly parked mech has no pilot until one is
# assigned from the roster page.
static func build(mech_name: String = "", requested_slot: int = 0) -> Dictionary:
	if GlobalData.mech_less:
		return {}
	for required in ["body", "leg_left", "leg_right"]:
		if not GlobalData.equipped_frames.has(required) or GlobalData.equipped_frames[required] == null:
			return {}
	if GlobalData.hangar_mechs.size() >= get_capacity():
		return {}
	if GlobalData.hangar_mechs.size() >= get_hard_max():
		return {}
	if requested_slot <= 0:
		requested_slot = _next_free_slot()
	if requested_slot > get_capacity() or _used_slots().has(requested_slot):
		return {}
	save_active()
	var mech_id := _new_id()
	var display_name := mech_name.strip_edges()
	if display_name == "":
		display_name = "Mech %02d" % requested_slot
	var snapshot := _capture_snapshot(mech_id, display_name, "", requested_slot)
	GlobalData.hangar_mechs.append(snapshot)
	return snapshot


static func get_backup_id() -> String:
	ensure_roster()
	for mech in GlobalData.hangar_mechs:
		var mech_id := str(mech.get("id", ""))
		if mech_id != "" and mech_id != GlobalData.active_hangar_mech_id:
			return mech_id
	return ""


# Removes a parked mech from the convoy roster. Used when a machine is destroyed
# in battle. If the active mech is the one removed, the player is handed the
# first remaining berth (or none, which is a valid pilot-only convoy state).
static func remove_mech(mech_id: String) -> bool:
	ensure_roster()
	var removed := false
	for i in range(GlobalData.hangar_mechs.size() - 1, -1, -1):
		if str(GlobalData.hangar_mechs[i].get("id", "")) == mech_id:
			GlobalData.hangar_mechs.remove_at(i)
			removed = true
	if not removed:
		return false
	if GlobalData.active_hangar_mech_id == mech_id:
		GlobalData.active_hangar_mech_id = ""
		for mech in GlobalData.hangar_mechs:
			if mech is Dictionary and not str(mech.get("id", "")).is_empty():
				GlobalData.active_hangar_mech_id = str(mech.get("id", ""))
				break
	return true


# True when the player is pilot-only (every mech lost) and the convoy can still
# retreat: squadmates must hold the convoy AND the theme must have a transport
# that parks spare mechs (a solo Gundam Heir has no backup truck, so losing the
# machine ends the run).
static func can_mechless_retreat() -> bool:
	if not GlobalData.mech_less:
		return false
	if get_fleet_size() < 2:
		return false
	var affiliation: Dictionary = GlobalData.get_run_affiliation()
	return bool(affiliation.get("mechless_retreat", true))


# Builds a fresh walking chassis from whatever parts the convoy still carries
# and parks it in the roster, ending pilot-only mode. Returns the new mech.
static func grant_recovery_mech() -> Dictionary:
	if GlobalData.hangar_mechs.size() >= get_capacity():
		return {}
	if GlobalData.hangar_mechs.size() >= get_hard_max():
		return {}
	save_active()
	var mech_id := _new_id()
	var slot := _next_free_slot()
	var display_name := "Mech %02d" % slot
	var snapshot := _capture_snapshot(mech_id, display_name, PLAYER_PILOT_ID, slot)
	GlobalData.hangar_mechs.append(snapshot)
	GlobalData.active_hangar_mech_id = mech_id
	GlobalData.mech_less = false
	return snapshot


static func get_slot_of(mech_id: String) -> int:
	for mech in GlobalData.hangar_mechs:
		if mech is Dictionary and str(mech.get("id", "")) == mech_id:
			return int(mech.get("slot", 0))
	return 0


# Reassigns which pilot drives `mech_id`. If the chosen pilot already sits in
# another mech, the two berths swap pilots (so a squadmate never ends up with
# two mechs). Passing "" unassigns the mech's pilot.
static func assign_pilot(mech_id: String, pilot_id: String) -> bool:
	ensure_roster()
	var target := _find(mech_id)
	if target.is_empty():
		return false
	if str(target.get("pilot", "")) == pilot_id:
		return true
	var prev_pilot := str(target.get("pilot", ""))
	var source_id := _mech_with_pilot(pilot_id)
	target["pilot"] = pilot_id
	if source_id != "" and source_id != mech_id:
		var source := _find(source_id)
		if not source.is_empty():
			source["pilot"] = prev_pilot
	return true


# Reads the combat archetype a mech fights as when fielded as an ally.
static func get_archetype(mech_id: String) -> int:
	var target := _find(mech_id)
	if target.is_empty():
		return ARCHETYPE_RANGED
	return clampi(int(target.get("archetype", ARCHETYPE_RANGED)), ARCHETYPE_RUSHER, ARCHETYPE_SUPPORT)


# Sets which combat archetype a mech fights as when fielded as an ally. Caller
# persists with save_run(). Returns false when the berth doesn't exist.
static func set_archetype(mech_id: String, archetype: int) -> bool:
	ensure_roster()
	var target := _find(mech_id)
	if target.is_empty():
		return false
	target["archetype"] = clampi(archetype, ARCHETYPE_RUSHER, ARCHETYPE_SUPPORT)
	return true


static func switch_mech(mech_id: String) -> bool:
	ensure_roster()
	var target := _find(mech_id)
	if target.is_empty() or mech_id == GlobalData.active_hangar_mech_id:
		return not target.is_empty()
	save_active()
	load_mech_state(mech_id)
	GlobalData.active_hangar_mech_id = mech_id
	return true


# Loads a parked mech's parts into the live working set (equipped frames/parts,
# chassis, damage, attachments, loadout) WITHOUT reassigning the active driver.
# Used by the customize page so the player can edit another berth's mech while
# the mech they will actually pilot in combat stays untouched.
static func load_mech_state(mech_id: String) -> bool:
	ensure_roster()
	var target := _find(mech_id)
	if target.is_empty():
		return false

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
	return true


# Snapshots the live working set back onto a specific parked mech entry. Unlike
# save_active (which writes to the active driver's mech), this targets any berth
# so the customize page can persist edits made to a non-active mech.
static func save_mech_state(mech_id: String) -> bool:
	ensure_roster()
	var target := _find(mech_id)
	if target.is_empty():
		return false
	var updated := _capture_snapshot(
		mech_id,
		str(target.get("name", "Mech")),
		str(target.get("pilot", "")),
		int(target.get("slot", get_slot_of(mech_id))),
	)
	for i in range(GlobalData.hangar_mechs.size()):
		if str(GlobalData.hangar_mechs[i].get("id", "")) == mech_id:
			GlobalData.hangar_mechs[i] = updated
			return true
	return false


static func _capture_snapshot(mech_id: String, mech_name: String, pilot_id: String, slot: int) -> Dictionary:
	GlobalData.sync_equipped_armor_durability()
	return {
		"id": mech_id,
		"name": mech_name,
		"slot": slot,
		"pilot": pilot_id,
		"chassis_id": GlobalData.chassis_id,
		"frames": SaveGameIO.serialize_frames(),
		"parts": SaveGameIO.serialize_parts(),
		"damage": GlobalData.part_damage.duplicate(true),
		"attachments": SaveGameIO.serialize_attachments(),
		"weapon_loadout": GlobalData.weapon_loadout.duplicate(true),
		"scrap_patches": GlobalData.scrap_patches.duplicate(true),
		"archetype": int(_find(mech_id).get("archetype", ARCHETYPE_RANGED)),
	}


static func _used_slots() -> Dictionary:
	var used: Dictionary = {}
	for mech in GlobalData.hangar_mechs:
		if mech is Dictionary:
			used[int(mech.get("slot", 0))] = true
	return used


static func _next_free_slot() -> int:
	var used := _used_slots()
	var slot := 1
	while used.has(slot):
		slot += 1
	return slot


static func _mech_with_pilot(pilot_id: String) -> String:
	if pilot_id == "":
		return ""
	for mech in GlobalData.hangar_mechs:
		if mech is Dictionary and str(mech.get("pilot", "")) == pilot_id:
			return str(mech.get("id", ""))
	return ""


static func _find(mech_id: String) -> Dictionary:
	for mech in GlobalData.hangar_mechs:
		if mech is Dictionary and str(mech.get("id", "")) == mech_id:
			return mech
	return {}


static func _new_id() -> String:
	return GlobalData._new_uid("mech")
