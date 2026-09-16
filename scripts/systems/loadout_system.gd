class_name LoadoutSystem
extends RefCounted

# -----------------------------------------------------------------------------
# WEAPON LOADOUT + FIELD PACK + FRAME UPGRADES
# What the mech carries into battle and how much that weighs, extracted from
# GlobalData. The Hangar configures loadout, WeaponManager reads it at battle
# start; weight/capacity math lives here so the hangar, HUD and pickups agree.
# GlobalData keeps thin facades for all existing callers.
#
# - FIELD PACK: what the mech physically carries into battle (hand weapons,
#   back-carry weapons, and the ammo loadout). Weight capacity comes from the
#   equipped Inner Frames (each frame adds a "carry_bonus").
#
# - Loadout refs: weapon_loadout["left"] / ["right"] / ["carry"] hold the
#   INSTANCE UID of each physical weapon ("" = unarmed / empty). Every stash
#   entry is one physical copy, so equipping a specific instance marks exactly
#   that copy as [E] in the hangar — same-model copies never share the badge.
#   All path-based read queries (weapon_equipped_slot, is_weapon_in_carry, ...)
#   resolve refs through the stash, so legacy callers keep working unchanged.
# -----------------------------------------------------------------------------


# Maps a mech slot name to the mecha-root-relative node path holding that
# section's meshes. Single source of truth for all part visuals.
static func get_slot_node_path(slot: String) -> String:
	return GlobalData.SLOT_TO_NODE.get(slot, "")


# Total Field Pack weight capacity in kg = base + sum of equipped frames.
static func get_field_pack_capacity() -> float:
	var capacity: float = GlobalData.FIELD_PACK_BASE_CAPACITY
	for slot in GlobalData.weapons.equipped_frames:
		var f = GlobalData.weapons.equipped_frames[slot]
		if f is Dictionary:
			capacity += float(f.get("carry_bonus", 0.0))
	return capacity


# Current Field Pack load weight in kg (hand weapons + carry weapons + ammo).
# Shoulder hardpoint weapons are bolted to the chassis like armor: they count
# toward the chassis TOTAL load (get_loadout_weapons_total), not toward the
# portable pack capacity, so mounting a shoulder pod never needs pack room.
static func get_field_pack_weight() -> float:
	return get_hand_carry_weight() + get_field_pack_ammo_weight()


# Weight of the portable loadout: both hands + back-carry weapons.
static func get_hand_carry_weight() -> float:
	var total := 0.0
	var left = get_equipped_weapon("left")
	if left:
		total += float(left.weight)
	var right = get_equipped_weapon("right")
	if right:
		total += float(right.weight)
	for w in get_carry_weapons():
		total += float(w.weight)
	return total


# Weight of both shoulder hardpoint weapons (chassis load, not pack load).
static func get_shoulder_weight() -> float:
	var total := 0.0
	var shldr_l = get_equipped_shoulder("left")
	if shldr_l:
		total += float(shldr_l.weight)
	var shldr_r = get_equipped_shoulder("right")
	if shldr_r:
		total += float(shldr_r.weight)
	return total


# True when a loadout slot's weapon rides in the portable field pack (hands +
# back carry). Shoulder hardpoints are chassis-mounted and never consume pack
# capacity. Accepts both vocabularies: "left"/"carry" and
# "weapon_left"/"weapon_carry"/"shoulder_left".
static func pack_counts_slot(slot: String) -> bool:
	var s := str(slot).trim_prefix("weapon_")
	return s == "left" or s == "right" or s == "carry"


# Exact pack-capacity check for a pending equip. The target slot's current
# occupant leaves the pack (when it rides in the pack), a moved copy's old
# slot is freed the same way, and the newcomer counts only outside shoulders.
# Refs accept instance uids OR legacy paths (resolved through the stash), so a
# uid occupant always subtracts correctly — never a false "pack full".
static func pack_would_exceed(target_slot: String, new_path: String, replaced_ref = "", moved_from_slot: String = "", freed_ref = "") -> bool:
	var pack := get_field_pack_weight()
	if pack_counts_slot(target_slot):
		var old_path := ref_to_path(replaced_ref)
		if old_path != "" and ResourceLoader.exists(old_path):
			var old_res = load(old_path)
			if old_res:
				pack -= float(old_res.weight)
	if str(freed_ref) != "" and pack_counts_slot(moved_from_slot):
		var freed_path := ref_to_path(freed_ref)
		if freed_path != "" and ResourceLoader.exists(freed_path):
			var freed_res = load(freed_path)
			if freed_res:
				pack -= float(freed_res.weight)
	if pack_counts_slot(target_slot) and new_path != "" and ResourceLoader.exists(new_path):
		var new_res = load(new_path)
		if new_res:
			pack += float(new_res.weight)
	return pack > get_field_pack_capacity()


# Weight of the ammo the player chose to carry (the "ammo" loadout).
static func get_field_pack_ammo_weight() -> float:
	var total := 0.0
	for ammo_type in GlobalData.weapons.weapon_loadout.get("ammo", {}):
		total += GlobalData.AMMO_WEIGHT_PER_UNIT.get(ammo_type, 0.01) * float(get_loadout_ammo(ammo_type))
	return total


# -----------------------------------------------------------------------------
# LOADOUT REF RESOLUTION
# A slot ref is either an instance uid (current saves) or a legacy resource
# path (old saves / direct callers). These helpers translate between the two.
# -----------------------------------------------------------------------------

# The stash instance with the given uid ("" when unknown).
static func get_weapon_instance(uid: String) -> Dictionary:
	return _instance_by_uid(uid)


static func _instance_by_uid(uid: String) -> Dictionary:
	if uid == "":
		return {}
	for inst in GlobalData.weapons.weapon_inventory:
		if str(inst.get("uid", "")) == uid:
			return inst
	return {}


# Resolves any slot ref to the weapon resource path: uid -> instance path,
# path -> itself. Unknown uids fall back to the raw string so legacy paths
# keep working even when no stash instance matches.
static func ref_to_path(ref) -> String:
	var s := str(ref)
	if s == "":
		return ""
	if s.begins_with("res://"):
		return s
	var inst := _instance_by_uid(s)
	if not inst.is_empty():
		return str(inst.get("path", ""))
	return s


# True when the uid currently sits in any loadout slot (left / right / shoulder_left / shoulder_right / carry).
static func _is_uid_in_loadout(uid: String) -> bool:
	if uid == "":
		return false
	if str(GlobalData.weapons.weapon_loadout.get("left", "")) == uid:
		return true
	if str(GlobalData.weapons.weapon_loadout.get("right", "")) == uid:
		return true
	if str(GlobalData.weapons.weapon_loadout.get("shoulder_left", "")) == uid:
		return true
	if str(GlobalData.weapons.weapon_loadout.get("shoulder_right", "")) == uid:
		return true
	var carry = GlobalData.weapons.weapon_loadout.get("carry", [])
	return carry is Array and uid in carry


# Chooses the instance a path-based equip should use: a SPARE copy first (so
# equipping a second pile bunker takes a fresh instance and the first stays
# in its slot), falling back to an already-equipped copy (the weapon MOVES to
# the new slot — the caller frees the old one). "" when the model isn't owned.
static func _uid_for_equip(path: String, exclude_uids: Array = []) -> String:
	if path == "":
		return ""
	for inst in GlobalData.weapons.weapon_inventory:
		var uid := str(inst.get("uid", ""))
		if uid != "" and str(inst.get("path", "")) == path and not _is_uid_in_loadout(uid) and not (uid in exclude_uids):
			return uid
	for inst in GlobalData.weapons.weapon_inventory:
		var uid := str(inst.get("uid", ""))
		if uid != "" and str(inst.get("path", "")) == path and not (uid in exclude_uids):
			return uid
	# If this weapon was newly acquired during combat (e.g. looted from field) or needed for a distinct slot, register a fresh instance
	if ResourceLoader.exists(path):
		var uid := register_weapon(path)
		return uid
	return ""


# Normalizes an equip ref (uid or path) to a uid. Paths resolve through
# _uid_for_equip (spare-first); unknown uids return "".
static func _ref_to_uid(ref) -> String:
	var s := str(ref)
	if s == "":
		return ""
	if s.begins_with("res://"):
		return _uid_for_equip(s)
	if not _instance_by_uid(s).is_empty():
		return s
	return ""


# Legacy-save migration: converts a path ref to the uid of the matching stash
# instance when one exists, keeping the path otherwise (reads still resolve it).
static func migrate_ref_to_uid(ref) -> String:
	var s := str(ref)
	if s == "" or not s.begins_with("res://"):
		return s
	var uid := _uid_for_equip(s)
	return uid if uid != "" else s


# -----------------------------------------------------------------------------
# READING THE LOADOUT
# -----------------------------------------------------------------------------

# Returns the equipped WeaponPart for the given hand ("left"/"right").
# Reads the central weapon_loadout so the Hangar and battle share one source.
# An explicitly-unarmed hand ("") returns null; only a missing/blank slot falls
# back to the default stock weapon for that hand.
static func get_equipped_weapon(side: String) -> WeaponPart:
	var key := "left" if side == "left" else "right"
	var path := ref_to_path(GlobalData.weapons.weapon_loadout.get(key, ""))
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		path = GlobalData.DEFAULT_LEFT_WEAPON_PATH if side == "left" else GlobalData.DEFAULT_RIGHT_WEAPON_PATH
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is WeaponPart:
			var dup: WeaponPart = (res as WeaponPart).duplicate(true) as WeaponPart
			dup.source_path = path
			return dup
	return null


# The instance uid currently held in a hand ("" = unarmed).
static func get_equipped_weapon_uid(side: String) -> String:
	return str(GlobalData.weapons.weapon_loadout.get("left", "") if side == "left" else GlobalData.weapons.weapon_loadout.get("right", ""))


# Returns the equipped WeaponPart for the given shoulder ("left"/"right").
# Returns null when unequipped.
static func get_equipped_shoulder(side: String) -> WeaponPart:
	var key := "shoulder_left" if side == "left" else "shoulder_right"
	var path := ref_to_path(GlobalData.weapons.weapon_loadout.get(key, ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res = load(path)
	if res is WeaponPart:
		var dup: WeaponPart = (res as WeaponPart).duplicate(true) as WeaponPart
		dup.source_path = path
		return dup
	return null


# The instance uid currently equipped on a shoulder ("" = empty).
static func get_equipped_shoulder_uid(side: String) -> String:
	var key := "shoulder_left" if side == "left" else "shoulder_right"
	return str(GlobalData.weapons.weapon_loadout.get(key, ""))


# Returns the WeaponParts the mech carries on its back into battle (from loadout).
static func get_carry_weapons() -> Array[WeaponPart]:
	var result: Array[WeaponPart] = []
	var carry_refs = GlobalData.weapons.weapon_loadout.get("carry", [])
	if not (carry_refs is Array):
		return result
	for ref in carry_refs:
		var path := ref_to_path(ref)
		if path != "" and ResourceLoader.exists(path):
			var res = load(path)
			if res is WeaponPart:
				var dup: WeaponPart = (res as WeaponPart).duplicate(true) as WeaponPart
				dup.source_path = path
				result.append(dup)
	return result




# Total weight of all loadout weapons (both hands + shoulders + back).
# Chassis TOTAL-load accounting (hangar weight bar, mech overweight checks).
# Field-pack capacity uses get_field_pack_weight() instead (no shoulders).
static func get_loadout_weapons_total() -> float:
	return get_hand_carry_weight() + get_shoulder_weight()


# Total weight of all loadout weapons (both hands + shoulders + back).
static func get_loadout_weapon_weight() -> float:
	return get_loadout_weapons_total()


# A weapon model may only be equipped in ONE slot at a time (left hand, right
# hand, shoulder_left, shoulder_right, or back carry) per physical copy. Returns the slot holding the model,
# or "" when it isn't equipped anywhere.
static func weapon_equipped_slot(path: String) -> String:
	if ref_to_path(GlobalData.weapons.weapon_loadout.get("left", "")) == path:
		return "left"
	if ref_to_path(GlobalData.weapons.weapon_loadout.get("right", "")) == path:
		return "right"
	if ref_to_path(GlobalData.weapons.weapon_loadout.get("shoulder_left", "")) == path:
		return "shoulder_left"
	if ref_to_path(GlobalData.weapons.weapon_loadout.get("shoulder_right", "")) == path:
		return "shoulder_right"
	if is_weapon_in_carry(path):
		return "carry"
	return ""


# Like weapon_equipped_slot but matches the exact INSTANCE by uid — the slot
# holding this specific physical copy ("" when it isn't equipped).
static func weapon_equipped_slot_by_uid(uid: String) -> String:
	if uid == "":
		return ""
	if str(GlobalData.weapons.weapon_loadout.get("left", "")) == uid:
		return "left"
	if str(GlobalData.weapons.weapon_loadout.get("right", "")) == uid:
		return "right"
	if str(GlobalData.weapons.weapon_loadout.get("shoulder_left", "")) == uid:
		return "shoulder_left"
	if str(GlobalData.weapons.weapon_loadout.get("shoulder_right", "")) == uid:
		return "shoulder_right"
	var carry = GlobalData.weapons.weapon_loadout.get("carry", [])
	if carry is Array and uid in carry:
		return "carry"
	return ""


# Slot lookup that accepts a uid OR a path ref (the hangar equip flow passes
# the clicked instance's uid; combat sync and legacy callers pass paths).
static func weapon_equipped_slot_ref(ref) -> String:
	var s := str(ref)
	if s.begins_with("res://"):
		return weapon_equipped_slot(s)
	return weapon_equipped_slot_by_uid(s)


# Returns the slot ("left"/"right"/"shoulder_left"/"shoulder_right"/"carry") holding `path` inside an arbitrary
# loadout dictionary (e.g. a parked mech's roster snapshot), or "" when absent.
# Refs are resolved through the stash, so uid-based snapshots match paths too.
static func weapon_slot_in_loadout(loadout: Dictionary, path: String) -> String:
	if ref_to_path(loadout.get("left", "")) == path:
		return "left"
	if ref_to_path(loadout.get("right", "")) == path:
		return "right"
	if ref_to_path(loadout.get("shoulder_left", "")) == path:
		return "shoulder_left"
	if ref_to_path(loadout.get("shoulder_right", "")) == path:
		return "shoulder_right"
	var carry = loadout.get("carry", [])
	if carry is Array:
		for ref in carry:
			if ref_to_path(ref) == path:
				return "carry"
	return ""


# -----------------------------------------------------------------------------
# WRITING THE LOADOUT (equip semantics — spare copies first)
# -----------------------------------------------------------------------------

# Assigns a weapon to a hand. `ref` is the instance uid of the clicked copy or
# a resource path (resolved to a spare instance; "" clears the hand). Equipping
# an instance already held in ANOTHER slot moves it there (frees the old slot);
# a fresh spare instance simply takes the hand alongside existing copies.
static func set_hand_weapon(side: String, ref) -> bool:
	var key := "left" if side == "left" else "right"
	var uid := _ref_to_uid(ref)
	if uid == "":
		GlobalData.weapons.weapon_loadout[key] = ""
		return true
	# One physical copy lives in one slot: free the slot holding this instance.
	var slot := weapon_equipped_slot_by_uid(uid)
	if slot != "" and slot != key:
		if slot == "carry":
			remove_carry_weapon(uid)
		else:
			GlobalData.weapons.weapon_loadout[slot] = ""
	GlobalData.weapons.weapon_loadout[key] = uid
	return true


# Assigns a weapon to a shoulder slot ("left"/"right"). `ref` is instance uid or path.
static func set_shoulder_weapon(side: String, ref) -> bool:
	var key := "shoulder_left" if side == "left" else "shoulder_right"
	var uid := _ref_to_uid(ref)
	if uid == "":
		GlobalData.weapons.weapon_loadout[key] = ""
		return true
	var slot := weapon_equipped_slot_by_uid(uid)
	if slot != "" and slot != key:
		if slot == "carry":
			remove_carry_weapon(uid)
		else:
			GlobalData.weapons.weapon_loadout[slot] = ""
	GlobalData.weapons.weapon_loadout[key] = uid
	return true


static func is_weapon_in_carry(path: String) -> bool:
	var carry_paths = GlobalData.weapons.weapon_loadout.get("carry", [])
	if not (carry_paths is Array):
		return false
	for ref in carry_paths:
		if ref_to_path(ref) == path:
			return true
	return false


# Whether this exact instance (by uid) is on the back pack.
static func is_weapon_in_carry_by_uid(uid: String) -> bool:
	if uid == "":
		return false
	var carry_paths = GlobalData.weapons.weapon_loadout.get("carry", [])
	return carry_paths is Array and uid in carry_paths


# Puts a weapon copy on the back pack. Each owned copy is a separate instance:
# putting a model on the pack uses one copy; with spare copies the pack simply
# takes another instance (a hand keeps its copy). Only when this is the LAST
# free copy is the model moved from a hand onto the pack.
static func add_carry_weapon(ref) -> bool:
	var uid := _ref_to_uid(ref)
	if uid == "":
		return false
	var path := ref_to_path(uid)
	var carry_paths = GlobalData.weapons.weapon_loadout.get("carry", [])
	if not (carry_paths is Array):
		carry_paths = []
	# This exact copy is already on the pack and no spare exists: no-op.
	if uid in carry_paths and not has_spare_weapon(path):
		return false
	var slot := weapon_equipped_slot_by_uid(uid)
	if slot != "" and slot != "carry" and not has_spare_weapon(path):
		GlobalData.weapons.weapon_loadout[slot] = ""
	carry_paths.append(uid)
	GlobalData.weapons.weapon_loadout["carry"] = carry_paths
	return true


# How many physical copies of a weapon model are currently on the back pack.
static func count_carry_weapon(path: String) -> int:
	var carry_paths = GlobalData.weapons.weapon_loadout.get("carry", [])
	if not (carry_paths is Array):
		return 0
	var count := 0
	for ref in carry_paths:
		if ref_to_path(ref) == path:
			count += 1
	return count


# How many physical copies of a weapon model the player owns in the stash
# (one inventory entry per instance). Two pile bunkers = two entries = 2.
static func count_owned_weapon(path: String) -> int:
	var owned := 0
	for entry in GlobalData.weapons.weapon_inventory:
		if str(entry.get("path", "")) == path:
			owned += 1
	return owned


# How many loadout slots (hands, shoulders, back pack) currently hold a
# copy of this weapon model. With separate instances, a model can fill several
# slots at once as long as the player owns enough copies.
static func count_equipped_weapon(path: String) -> int:
	var n := 0
	if ref_to_path(GlobalData.weapons.weapon_loadout.get("left", "")) == path:
		n += 1
	if ref_to_path(GlobalData.weapons.weapon_loadout.get("right", "")) == path:
		n += 1
	if ref_to_path(GlobalData.weapons.weapon_loadout.get("shoulder_left", "")) == path:
		n += 1
	if ref_to_path(GlobalData.weapons.weapon_loadout.get("shoulder_right", "")) == path:
		n += 1
	var carry = GlobalData.weapons.weapon_loadout.get("carry", [])
	if carry is Array:
		for ref in carry:
			if ref_to_path(ref) == path:
				n += 1
	return n


# True when the player owns at least one copy of the model that is NOT in a
# loadout slot (i.e. equipping it again should not move the slot's copy).
static func has_spare_weapon(path: String) -> bool:
	return count_owned_weapon(path) > count_equipped_weapon(path)


# -----------------------------------------------------------------------------
# FLEET-WIDE SPARE TRACKING
# A weapon model may fill several loadout slots, but every slot must hold a
# DIFFERENT physical copy (uid). To know whether a free copy exists the hangar
# must count slots across the WHOLE fleet: the editing berth's live central
# loadout plus every parked mech's roster snapshot. These helpers power the
# cross-mech swap decisions (equip gate + "used by other mech" marking).
# -----------------------------------------------------------------------------

# Count of loadout slots holding a copy of `path` inside one loadout dict.
static func weapon_slots_in_loadout(loadout: Dictionary, path: String) -> int:
	var n := 0
	if ref_to_path(loadout.get("left", "")) == path:
		n += 1
	if ref_to_path(loadout.get("right", "")) == path:
		n += 1
	if ref_to_path(loadout.get("shoulder_left", "")) == path:
		n += 1
	if ref_to_path(loadout.get("shoulder_right", "")) == path:
		n += 1
	var carry = loadout.get("carry", [])
	if carry is Array:
		for ref in carry:
			if ref_to_path(ref) == path:
				n += 1
	return n


# How many slots across the whole fleet hold a copy of `path`. The berth being
# edited (`editing_id`, "" = none) contributes its LIVE central loadout; every
# other parked mech contributes its snapshot.
static func fleet_weapon_slots_used(path: String, editing_id: String = "") -> int:
	var n := 0
	if editing_id != "":
		n += weapon_slots_in_loadout(GlobalData.weapons.weapon_loadout, path)
	for mech in GlobalData.hangar.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var mid := str(mech.get("id", ""))
		if mid == "" or mid == editing_id:
			continue
		var loadout = mech.get("weapon_loadout", {})
		if loadout is Dictionary:
			n += weapon_slots_in_loadout(loadout, path)
	return n


# True when at least one owned copy of `path` is NOT in any fleet loadout slot
# (a free spare exists, so equipping it again would not move another mech's
# copy). Pass the editing mech id so its live loadout counts as a slot.
static func has_fleet_spare_weapon(path: String, editing_id: String = "") -> bool:
	if path == "":
		return false
	return count_owned_weapon(path) > fleet_weapon_slots_used(path, editing_id)


static func remove_carry_weapon(ref) -> void:
	var target := str(ref)
	var carry_paths = GlobalData.weapons.weapon_loadout.get("carry", [])
	if not (carry_paths is Array):
		return
	var erase_idx := -1
	for i in range(carry_paths.size()):
		var r := str(carry_paths[i])
		if target.begins_with("res://"):
			if ref_to_path(r) == target:
				erase_idx = i
				break
		elif r == target:
			erase_idx = i
			break
	if erase_idx >= 0:
		carry_paths.remove_at(erase_idx)
		GlobalData.weapons.weapon_loadout["carry"] = carry_paths


# -----------------------------------------------------------------------------
# COMBAT SYNC — writes the battle's actual hands/back back into the loadout.
# The slot's CURRENT uid is preferred (that instance entered the battle), so
# unchanged weapons keep their identity; only genuinely new pickups resolve to
# a spare/fresh instance.
# -----------------------------------------------------------------------------

static func resolve_hand_uid_for_sync(side: String, path: String) -> String:
	if path == "":
		return ""
	var key := "left" if side == "left" else "right"
	var cur := str(GlobalData.weapons.weapon_loadout.get(key, ""))
	var inst := _instance_by_uid(cur)
	if not inst.is_empty() and str(inst.get("path", "")) == path:
		return cur
	return _uid_for_equip(path)


static func resolve_shoulder_uid_for_sync(side: String, path: String) -> String:
	if path == "":
		return ""
	var key := "shoulder_left" if side == "left" else "shoulder_right"
	var cur := str(GlobalData.weapons.weapon_loadout.get(key, ""))
	var inst := _instance_by_uid(cur)
	if not inst.is_empty() and str(inst.get("path", "")) == path:
		return cur
	return _uid_for_equip(path)


static func resolve_carry_uids_for_sync(paths: Array) -> Array:
	var current = GlobalData.weapons.weapon_loadout.get("carry", [])
	if not (current is Array):
		current = []
	var used := {}
	var result: Array = []
	for p in paths:
		var path := str(p)
		if path == "":
			continue
		var found := ""
		for ref in current:
			var rs := str(ref)
			if rs in used:
				continue
			var inst := _instance_by_uid(rs)
			if not inst.is_empty() and str(inst.get("path", "")) == path:
				found = rs
				break
		if found == "":
			found = _uid_for_equip(path, used.keys())
		if found != "":
			used[found] = true
			result.append(found)
	return result


# Returns how much ammo of the given type the player carries into the next battle.
static func get_loadout_ammo(ammo_type: String) -> int:
	var ammo = GlobalData.weapons.weapon_loadout.get("ammo", {})
	if not (ammo is Dictionary):
		return 0
	return ammo.get(ammo_type.to_lower(), 0)


# Sets how much ammo of the given type the player carries into the next battle.
static func set_loadout_ammo(ammo_type: String, amount: int) -> void:
	var ammo = GlobalData.weapons.weapon_loadout.get("ammo", {})
	if not (ammo is Dictionary):
		ammo = {}
	ammo[ammo_type.to_lower()] = max(0, amount)
	GlobalData.weapons.weapon_loadout["ammo"] = ammo


static func get_loadout_ammo_dict() -> Dictionary:
	var ammo = GlobalData.weapons.weapon_loadout.get("ammo", {})
	if not (ammo is Dictionary):
		return {}
	return ammo.duplicate()


static func get_equipped_part_id(slot: String) -> String:
	var part = GlobalData.weapons.equipped_parts.get(slot)
	if part == null:
		return ""
	if part is Dictionary:
		var pid = part.get("id", "")
		if pid != "":
			return pid
		return part.get("name", part.get("path", ""))
	if part is Resource:
		if "id" in part and part.id != "":
			return part.id
		if "part_name" in part and part.part_name != "":
			return part.part_name
		return part.resource_path
	return ""


# Returns the chassis stats dict for the currently selected chassis_id.
# Used by mecha_controller at combat start so it doesn't rely on @export chassis resource.
# Keys: "speed" (float), "max_weight" (float), "color" (Color), "name" (String)
static func get_chassis_stats() -> Dictionary:
	var result: Dictionary = GlobalData.chassis_catalog.get(GlobalData.weapons.chassis_id, GlobalData.chassis_catalog.get("standard", {
		"name": "Standard", "speed": 14.0, "max_weight": 75.0, "color": Color(0.6, 0.65, 0.7)
	})).duplicate(true)
	if not result.has("attachment_capacity"):
		var capacity := float(result.get("max_weight", 75.0))
		result["attachment_capacity"] = {"head": capacity * 0.10, "body": capacity * 0.35, "arm_left": capacity * 0.14, "arm_right": capacity * 0.14, "leg_left": capacity * 0.16, "leg_right": capacity * 0.16}
	result["movement_type"] = {"standard": "biped", "titan": "heavy", "vanguard": "light", "aegis": "hover", "brawler": "brawler"}.get(GlobalData.weapons.chassis_id, "biped")
	result["water_traversal"] = result["movement_type"] == "hover"
	# Power stat gates one-hand gripping of heavy two-hand weapons (rail/minigun).
	# It comes from the chassis plus the strength of both arm frames.
	if not result.has("power"):
		result["power"] = {"standard": 12.0, "titan": 18.0, "vanguard": 8.0, "aegis": 14.0, "brawler": 13.0}.get(GlobalData.weapons.chassis_id, 12.0)
	return result


# -----------------------------------------------------------------------------
# FRAME UPGRADES — the Inner Frame research branch adds flat HP / carry bonuses.
# -----------------------------------------------------------------------------


static func get_frame_upgrade_hp_bonus() -> float:
	return float(maxi(GlobalData.weapons.frame_upgrade_level - 1, 0)) * GlobalData.FRAME_UPGRADE_HP_BONUS


static func get_frame_upgrade_weight_bonus() -> float:
	return float(maxi(GlobalData.weapons.frame_upgrade_level - 1, 0)) * GlobalData.FRAME_UPGRADE_WEIGHT_BONUS


static func get_frame_upgrade_cost() -> int:
	return GlobalData.weapons.frame_upgrade_level * GlobalData.FRAME_UPGRADE_BASE_COST


# -----------------------------------------------------------------------------
# DEPOT AMMO / WEAPON INVENTORY — permanent storage outside the field pack.
# -----------------------------------------------------------------------------


static func get_reserve_ammo(ammo_type: String) -> int:
	return GlobalData.weapons.ammo_inventory.get(ammo_type.to_lower(), 0)


static func add_reserve_ammo(ammo_type: String, amount: int) -> void:
	var type = ammo_type.to_lower()
	GlobalData.weapons.ammo_inventory[type] = GlobalData.weapons.ammo_inventory.get(type, 0) + amount


static func consume_reserve_ammo(ammo_type: String, amount: int) -> int:
	var type = ammo_type.to_lower()
	var current = get_reserve_ammo(type)
	var taken = mini(current, amount)
	GlobalData.weapons.ammo_inventory[type] = current - taken
	return taken


static func register_weapon(path: String, weapon_name: String = "") -> String:
	# The real weapon model name wins over any caller-provided label (e.g. the
	# run-start code once registered everything as "Starter"). Keeps the stash
	# listing readable no matter who called in.
	var display_name := weapon_name
	if ResourceLoader.exists(path):
		var res = load(path)
		if res and ("weapon_name" in res) and str(res.weapon_name) != "":
			display_name = str(res.weapon_name)
	if display_name == "":
		display_name = "Weapon"
	# Each copy of a weapon model is its OWN inventory instance (fresh uid /
	# durability / upgrade level) — same as armor. Picking up or crafting
	# another pile bunker appends a second "Pile Bunker" entry; the stash never
	# merges same-model copies into a x2 count. The new uid is returned so the
	# caller can reference this exact copy in a loadout slot.
	var uid: String = GlobalData._new_uid("w")
	GlobalData.weapons.weapon_inventory.append({
		"uid": uid,
		"path": path,
		"name": display_name,
		"durability": 1.0,
		"upgrade_level": 1
	})
	return uid
