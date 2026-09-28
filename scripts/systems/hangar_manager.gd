class_name HangarManager
extends RefCounted

# -----------------------------------------------------------------------------
# HANGAR MECH ROSTER
# Built-mech roster logic extracted from GlobalData so the run-state autoload
# stays focused on state. Every function reads/writes the roster state
# (GlobalData.hangar.hangar_mechs / GlobalData.hangar.active_hangar_mech_id) through the
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

# Walking-chassis requirement: a mech needs these three inner frames equipped
# before it can be parked as a new hangar berth. Shared by build() and the
# roster page's REGISTER action so the gate can never drift between them.
const REQUIRED_WALKING_FRAMES: Array[String] = ["body", "leg_left", "leg_right"]

# Resource cost to assemble a new frame into an empty berth via the roster
# page's REGISTER action (see build()). Charged by the roster panel, not inside
# build(), so other callers (recovery grants, recruit parking, tests) stay free.
# Deliberately above a single armor craft so duplicating a chassis is a real
# decision instead of a spam action.
const REGISTER_SCRAP_COST := 25
const REGISTER_CREDIT_COST := 60


# Number of pilots in the convoy: the player driver plus every researched fleet
# unit (regardless of fielded/destroyed status — they still occupy a berth).
static func get_fleet_size() -> int:
	return maxi(1, GlobalData.hangar.fleet_roster.size() + 1)


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
	return HangarState.HANGAR_HARD_MAX


# Every pilot available in the convoy. Entries are {id, name}. Fleet units are
# keyed by their template so a pilot survives renames in the fleet roster.
static func get_pilots() -> Array:
	var pilots: Array = [{"id": PLAYER_PILOT_ID, "name": "YOU (driver)"}]
	for unit in GlobalData.hangar.fleet_roster:
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


# Pilot display name for a specific berth ("YOU (driver)", a fleet pilot's
# name, or "(no pilot)"). Single source for every surface that shows who
# drives a mech (roster badge, stats panel), so the lookup can never drift.
static func get_mech_pilot_name(mech_id: String) -> String:
	var mech := _find(mech_id)
	if mech.is_empty():
		return "(no pilot)"
	return get_pilot_name(str(mech.get("pilot", "")))


# Short status suffix for a fleet pilot shown on the roster rows (the player
# driver has none): " · DESTROYED", " · WOUNDED (nT)" while recovering, or
# " · hp/max HP" while damaged. Reads the unit's live state from the fleet.
static func get_pilot_status(pilot_id: String) -> String:
	if not pilot_id.begins_with("fleet_"):
		return ""
	var unit := FleetSystem.get_fleet_unit(pilot_id.trim_prefix("fleet_"))
	if unit.is_empty():
		return ""
	if bool(unit.get("destroyed", false)):
		return " · DESTROYED"
	if bool(unit.get("wounded", false)):
		return " · WOUNDED (%dT)" % int(unit.get("wound_turns", 0))
	var hp := float(unit.get("hp", 0.0))
	var max_hp := float(unit.get("max_hp", 0.0))
	if max_hp <= 0.0:
		return ""
	return " · %d/%d HP" % [int(hp), int(max_hp)]


static func ensure_roster() -> void:
	if not GlobalData.hangar.hangar_mechs.is_empty():
		GlobalData.narrative.mech_less = false
	elif GlobalData.narrative.mech_less:
		return
	if GlobalData.hangar.hangar_mechs.is_empty():
		var first_id := _new_id()
		GlobalData.hangar.hangar_mechs.append(_capture_snapshot(first_id, "Mech 01", PLAYER_PILOT_ID, 1))
		GlobalData.hangar.active_hangar_mech_id = first_id
	else:
		if GlobalData.hangar.active_hangar_mech_id == "" or _find(GlobalData.hangar.active_hangar_mech_id).is_empty():
			GlobalData.hangar.active_hangar_mech_id = str(GlobalData.hangar.hangar_mechs[0].get("id", ""))
	if _migrate_old_saves():
		GlobalData.save_run()


# Old saves predate pilots/slots: back-fill a stable slot number for every mech
# and hand unassigned pilots to parked mechs (player driver first). Returns true
# if anything changed so the caller can persist the migration once.
static func _migrate_old_saves() -> bool:
	var dirty := false
	var used_slots: Dictionary = {}
	var used_pilots: Dictionary = {}
	for mech in GlobalData.hangar.hangar_mechs:
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

	for mech in GlobalData.hangar.hangar_mechs:
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
	var sorted := GlobalData.hangar.hangar_mechs.duplicate()
	sorted.sort_custom(func(a, b):
		return int(a.get("slot", 0x7FFFFFFF)) < int(b.get("slot", 0x7FFFFFFF)))
	return sorted


static func get_active_mech() -> Dictionary:
	ensure_roster()
	return _find(GlobalData.hangar.active_hangar_mech_id)


static func save_active() -> bool:
	ensure_roster()
	var active := _find(GlobalData.hangar.active_hangar_mech_id)
	if active.is_empty():
		return false
	var updated := _capture_snapshot(
		GlobalData.hangar.active_hangar_mech_id,
		str(active.get("name", "Mech")),
		str(active.get("pilot", "")),
		int(active.get("slot", get_slot_of(GlobalData.hangar.active_hangar_mech_id))),
	)
	for i in range(GlobalData.hangar.hangar_mechs.size()):
		if str(GlobalData.hangar.hangar_mechs[i].get("id", "")) == GlobalData.hangar.active_hangar_mech_id:
			GlobalData.hangar.hangar_mechs[i] = updated
			return true
	return false


# Builds another hangar entry from the currently assembled parts and parks it in
# `requested_slot` (0 = first free berth). A complete walking chassis needs a
# body frame and both leg frames; armor is optional and can be installed later
# in the normal hangar editor. The newly parked mech has no pilot until one is
# assigned from the roster page.
static func build(mech_name: String = "", requested_slot: int = 0) -> Dictionary:
	for required in REQUIRED_WALKING_FRAMES:
		if not GlobalData.weapons.equipped_frames.has(required) or GlobalData.weapons.equipped_frames[required] == null:
			return {}
	if GlobalData.hangar.hangar_mechs.size() >= get_capacity():
		return {}
	if GlobalData.hangar.hangar_mechs.size() >= get_hard_max():
		return {}
	if requested_slot <= 0:
		requested_slot = _next_free_slot()
	if requested_slot > get_capacity() or _used_slots().has(requested_slot):
		return {}
	if not GlobalData.narrative.mech_less:
		save_active()
	var mech_id := _new_id()
	var display_name := mech_name.strip_edges()
	if display_name == "":
		display_name = "Mech %02d" % requested_slot
	var snapshot := _capture_snapshot(mech_id, display_name, "", requested_slot)
	GlobalData.hangar.hangar_mechs.append(snapshot)
	GlobalData.narrative.mech_less = false
	GlobalData.fuel.mech_energy = GlobalData.fuel.mech_max_energy
	return snapshot


static func get_backup_id() -> String:
	ensure_roster()
	for mech in GlobalData.hangar.hangar_mechs:
		var mech_id := str(mech.get("id", ""))
		if mech_id != "" and mech_id != GlobalData.hangar.active_hangar_mech_id:
			return mech_id
	return ""


# True when the parked mech's driver is unfit to fight: a wounded fleet pilot
# (recovering, can't fight until healed) or a destroyed one. A wounded pilot
# can still be seated (the berth waits for them) but never fights until
# healed, so their mech must not be the one the player pilots into combat.
static func is_driver_wounded(mech: Dictionary) -> bool:
	var pilot_id := str(mech.get("pilot", ""))
	if not pilot_id.begins_with("fleet_"):
		return false
	var unit := FleetSystem.get_fleet_unit(pilot_id.trim_prefix("fleet_"))
	if unit.is_empty():
		return false
	if bool(unit.get("destroyed", false)):
		return true
	return bool(unit.get("wounded", false))


# True when the piloted (active) mech's driver is a recovering fleet pilot.
static func is_active_driver_wounded() -> bool:
	return is_driver_wounded(get_active_mech())


# Best parked berth to pilot into combat when the active driver is wounded:
# prefers the player-driven machine (the driver is always fit), then any berth
# whose pilot is healthy or empty. Returns "" when no healthy backup exists.
static func get_healthy_backup_id() -> String:
	ensure_roster()
	var active_id := GlobalData.hangar.active_hangar_mech_id
	var fallback := ""
	for mech in GlobalData.hangar.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var mech_id := str(mech.get("id", ""))
		if mech_id == "" or mech_id == active_id:
			continue
		if is_driver_wounded(mech):
			continue
		if str(mech.get("pilot", "")) == PLAYER_PILOT_ID:
			return mech_id
		if fallback == "":
			fallback = mech_id
	return fallback


# Combat-entry safety net: when the piloted (active) mech's driver is a
# wounded fleet pilot, park that berth and switch the active mech to a healthy
# backup before the combat scene loads. Returns the new active mech id (""
# when nothing needed swapping, or no healthy backup exists).
static func auto_park_wounded_active() -> String:
	ensure_roster()
	if not is_active_driver_wounded():
		return ""
	var backup_id := get_healthy_backup_id()
	if backup_id == "":
		return ""
	if switch_mech(backup_id):
		return backup_id
	return ""


# Removes a parked mech from the convoy roster. Used when a machine is destroyed
# in battle. If the active mech is the one removed, the player is handed the
# first remaining berth (or none, which is a valid pilot-only convoy state).
# Handing over the berth also LOADS that reserve's state into the live working
# set (same contract as switch_mech): the destroyed machine's working set must
# not survive the removal, or the next save_active() would clobber the reserve
# berth with the wreck's loadout/damage and the next combat would rebuild the
# wreck instead of the reserve.
static func remove_mech(mech_id: String) -> bool:
	ensure_roster()
	var removed := false
	for i in range(GlobalData.hangar.hangar_mechs.size() - 1, -1, -1):
		if str(GlobalData.hangar.hangar_mechs[i].get("id", "")) == mech_id:
			GlobalData.hangar.hangar_mechs.remove_at(i)
			removed = true
	if not removed:
		return false
	if GlobalData.hangar.active_hangar_mech_id == mech_id:
		GlobalData.hangar.active_hangar_mech_id = ""
		for mech in GlobalData.hangar.hangar_mechs:
			if mech is Dictionary and not str(mech.get("id", "")).is_empty():
				GlobalData.hangar.active_hangar_mech_id = str(mech.get("id", ""))
				break
		if GlobalData.hangar.active_hangar_mech_id != "":
			load_mech_state(GlobalData.hangar.active_hangar_mech_id)
	return true


# True when the player is pilot-only (every mech lost) and the convoy can still
# retreat: squadmates must hold the convoy AND the theme must have a transport
# that parks spare mechs (a solo Valkyrion Heir has no backup truck, so losing the
# machine ends the run).
static func can_mechless_retreat() -> bool:
	if not GlobalData.narrative.mech_less:
		return false
	if get_fleet_size() < 2:
		return false
	var affiliation: Dictionary = ThemeSystem.get_affiliation()
	return bool(affiliation.get("mechless_retreat", true))


# Builds a fresh walking chassis from whatever parts the convoy still carries
# and parks it in the roster, ending pilot-only mode. Returns the new mech.
static func grant_recovery_mech() -> Dictionary:
	if GlobalData.hangar.hangar_mechs.size() >= get_capacity():
		return {}
	if GlobalData.hangar.hangar_mechs.size() >= get_hard_max():
		return {}
	save_active()
	var mech_id := _new_id()
	var slot := _next_free_slot()
	var display_name := "Mech %02d" % slot
	var snapshot := _capture_snapshot(mech_id, display_name, PLAYER_PILOT_ID, slot)
	GlobalData.hangar.hangar_mechs.append(snapshot)
	GlobalData.hangar.active_hangar_mech_id = mech_id
	GlobalData.narrative.mech_less = false
	return snapshot


# Parks a recruited character's signature mech as a new convoy berth, assigned
# to that pilot. Generates its own independent chassis, frames, armor plates,
# and unique registered weapons so it never clones or conflicts with the player's mech.
# `damage` optionally seeds heavy part damage (0..1 per slot) so a salvaged wreck arrives near-broken.
static func park_ally_mech(mech_name: String, pilot_id: String, archetype: int, damage: Dictionary = {}, custom_weapons: Dictionary = {}) -> Dictionary:
	if GlobalData.narrative.mech_less:
		return {}
	if GlobalData.hangar.hangar_mechs.size() >= get_capacity():
		return {}
	if GlobalData.hangar.hangar_mechs.size() >= get_hard_max():
		return {}
	save_active()
	var mech_id := _new_id()
	var slot := _next_free_slot()
	var arch := clampi(archetype, ARCHETYPE_RUSHER, ARCHETYPE_SUPPORT)

	# 1. Determine signature chassis for the ally
	var chassis := "standard"
	if arch == ARCHETYPE_RUSHER:
		chassis = "vanguard"
	elif arch == ARCHETYPE_HEAVY:
		chassis = "titan"
	elif arch == ARCHETYPE_SUPPORT:
		chassis = "aegis"

	# 2. Independent standard inner frames for all slots
	var frames: Dictionary = {}
	for s in GlobalData.MECHA_SLOTS:
		frames[s] = {
			"id": "standard_%s" % s,
			"type": "standard",
			"name": "Standard %s Frame" % s.capitalize(),
			"hp": 50.0
		}

	# 3. Independent standard armor plates for all slots
	var parts: Dictionary = {}
	for s in GlobalData.MECHA_SLOTS:
		var part_id := "standard_%s" % s
		var inst: Dictionary = ArmorSystem.make_armor_instance_from_catalog(part_id)
		if not inst.is_empty():
			parts[s] = inst

	# 4. Signature weapons suited to the character / archetype with fresh unique UIDs
	var left_path := str(custom_weapons.get("left", ""))
	var right_path := str(custom_weapons.get("right", ""))
	var carry_paths = custom_weapons.get("carry", [])
	if left_path == "" or right_path == "":
		if arch == ARCHETYPE_RUSHER:
			left_path = "res://resources/mech/stock/weapon_heat_blade.tres"
			right_path = "res://resources/mech/stock/weapon_beam_carbine.tres"
		elif arch == ARCHETYPE_HEAVY:
			left_path = "res://resources/mech/stock/weapon_combat_shotgun.tres"
			right_path = "res://resources/mech/stock/weapon_assault_cannon.tres"
		elif arch == ARCHETYPE_SUPPORT:
			left_path = "res://resources/mech/stock/weapon_beam_rifle.tres"
			right_path = "res://resources/mech/stock/weapon_missile.tres"
		else: # ARCHETYPE_RANGED
			left_path = "res://resources/mech/stock/weapon_beam_rifle.tres"
			right_path = "res://resources/mech/stock/weapon_combat_shotgun.tres"

	var left_uid := LoadoutSystem.register_weapon(left_path)
	var right_uid := LoadoutSystem.register_weapon(right_path)
	var carry_uids: Array = []
	if carry_paths is Array:
		for cp in carry_paths:
			var cuid := LoadoutSystem.register_weapon(str(cp))
			if cuid != "":
				carry_uids.append(cuid)

	var ally_weapon_loadout = {
		"left": left_uid,
		"right": right_uid,
		"carry": carry_uids,
		"ammo": AmmoSystem.STARTER_RESERVE.duplicate(),
	}

	var snapshot = {
		"id": mech_id,
		"name": mech_name,
		"slot": slot,
		"pilot": pilot_id,
		"chassis_id": chassis,
		"frames": frames,
		"parts": parts,
		"damage": {},
		"attachments": [],
		"weapon_loadout": ally_weapon_loadout,
		"scrap_patches": {},
		"archetype": arch,
	}

	if not damage.is_empty():
		for key in damage:
			snapshot["damage"][key] = clampf(float(damage[key]), 0.0, 1.0)

	GlobalData.hangar.hangar_mechs.append(snapshot)
	return snapshot


static func get_slot_of(mech_id: String) -> int:
	for mech in GlobalData.hangar.hangar_mechs:
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
# Renames a parked mech (identity field only — loadout/pilot/slot untouched).
# A blank name falls back to the slot-based name ("Mech 01"). Returns false
# when the berth doesn't exist. Caller persists with save_run().
static func rename_mech(mech_id: String, new_name: String) -> bool:
	ensure_roster()
	var target := _find(mech_id)
	if target.is_empty():
		return false
	var clean := new_name.strip_edges()
	if clean == "":
		clean = "Mech %02d" % int(target.get("slot", 1))
	target["name"] = clean
	return true


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
	if target.is_empty() or mech_id == GlobalData.hangar.active_hangar_mech_id:
		return not target.is_empty()
	save_active()
	load_mech_state(mech_id)
	GlobalData.hangar.active_hangar_mech_id = mech_id
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
	for old_part in GlobalData.weapons.equipped_parts.values():
		if old_part is Dictionary and old_part.has("uid"):
			var old_inst := ArmorSystem.get_armor_instance(str(old_part["uid"]))
			if not old_inst.is_empty():
				old_inst["equipped"] = false

	GlobalData.weapons.chassis_id = str(target.get("chassis_id", "standard"))
	GlobalData.weapons.equipped_frames.clear()
	var saved_frames: Dictionary = target.get("frames", {})
	for slot in saved_frames:
		GlobalData.weapons.equipped_frames[slot] = SaveGameIO.resolve_frame_value(saved_frames[slot])
	GlobalData.weapons._ensure_default_frames()

	GlobalData.weapons.equipped_parts.clear()
	var saved_parts: Dictionary = target.get("parts", {})
	for slot in saved_parts:
		var part = SaveGameIO.resolve_equipped_part(saved_parts[slot])
		GlobalData.weapons.equipped_parts[slot] = part
		if part is Dictionary and part.has("uid"):
			part["equipped"] = true

	GlobalData.weapons.part_damage = target.get("damage", {}).duplicate(true)
	GlobalData.weapons.equipped_backpack = target.get("equipped_backpack", {}).duplicate(true)
	GlobalData.weapons.frame_modules = target.get("frame_modules", {}).duplicate(true)
	GlobalData.weapons.attachments = target.get("attachments", []).duplicate(true)
	GlobalData.weapons.weapon_loadout = target.get("weapon_loadout", GlobalData.weapons.weapon_loadout).duplicate(true)
	GlobalData.weapons.scrap_patches = target.get("scrap_patches", {}).duplicate(true)
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
	for i in range(GlobalData.hangar.hangar_mechs.size()):
		if str(GlobalData.hangar.hangar_mechs[i].get("id", "")) == mech_id:
			GlobalData.hangar.hangar_mechs[i] = updated
			return true
	return false


# Replaces a parked mech's loadout fields with the ones from `snapshot` while
# keeping its identity (id/name/slot/pilot/archetype). Used to undo working-set
# edits that leaked onto a berth during the REGISTER assembly flow, so frames
# equipped for a NEW mech never rewrite an existing one.
static func restore_berth_loadout(mech_id: String, snapshot: Dictionary) -> bool:
	for i in range(GlobalData.hangar.hangar_mechs.size()):
		var entry = GlobalData.hangar.hangar_mechs[i]
		if entry is Dictionary and str(entry.get("id", "")) == mech_id:
			var updated: Dictionary = entry.duplicate(true)
			for key in ["chassis_id", "frames", "parts", "damage", "equipped_backpack", "frame_modules", "attachments", "weapon_loadout", "scrap_patches"]:
				if snapshot.has(key):
					var value = snapshot[key]
					updated[key] = value.duplicate(true) if value is Dictionary or value is Array else value
			GlobalData.hangar.hangar_mechs[i] = updated
			return true
	return false


static func _capture_snapshot(mech_id: String, mech_name: String, pilot_id: String, slot: int) -> Dictionary:
	ArmorSystem.sync_equipped_armor_durability()
	return {
		"id": mech_id,
		"name": mech_name,
		"slot": slot,
		"pilot": pilot_id,
		"chassis_id": GlobalData.weapons.chassis_id,
		"frames": SaveGameIO.serialize_frames(),
		"parts": SaveGameIO.serialize_parts(),
		"damage": GlobalData.weapons.part_damage.duplicate(true),
		"equipped_backpack": GlobalData.weapons.equipped_backpack.duplicate(true) if ("equipped_backpack" in GlobalData.weapons) else {},
		"frame_modules": GlobalData.weapons.frame_modules.duplicate(true) if ("frame_modules" in GlobalData.weapons) else {},
		"attachments": SaveGameIO.serialize_attachments(),
		"weapon_loadout": GlobalData.weapons.weapon_loadout.duplicate(true),
		"scrap_patches": GlobalData.weapons.scrap_patches.duplicate(true),
		"archetype": int(_find(mech_id).get("archetype", ARCHETYPE_RANGED)),
	}


static func _used_slots() -> Dictionary:
	var used: Dictionary = {}
	for mech in GlobalData.hangar.hangar_mechs:
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
	for mech in GlobalData.hangar.hangar_mechs:
		if mech is Dictionary and str(mech.get("pilot", "")) == pilot_id:
			return str(mech.get("id", ""))
	return ""


static func _find(mech_id: String) -> Dictionary:
	for mech in GlobalData.hangar.hangar_mechs:
		if mech is Dictionary and str(mech.get("id", "")) == mech_id:
			return mech
	return {}


static func _new_id() -> String:
	return GlobalData._new_uid("mech")
