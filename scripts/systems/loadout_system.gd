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
# -----------------------------------------------------------------------------


# Maps a mech slot name to the mecha-root-relative node path holding that
# section's meshes. Single source of truth for all part visuals.
static func get_slot_node_path(slot: String) -> String:
	match slot:
		"head": return "Head"
		"body": return "Body"
		"arm_left": return "ArmLeft"
		"arm_right": return "ArmRight"
		"leg_left": return "LegLeft"
		"leg_right": return "LegRight"
	return ""


# Total Field Pack weight capacity in kg = base + sum of equipped frames.
static func get_field_pack_capacity() -> float:
	var capacity := GlobalData.FIELD_PACK_BASE_CAPACITY
	for slot in GlobalData.equipped_frames:
		var f = GlobalData.equipped_frames[slot]
		if f is Dictionary:
			capacity += float(f.get("carry_bonus", 0.0))
	return capacity


# Current Field Pack load weight in kg (hand weapons + carry weapons + ammo).
static func get_field_pack_weight() -> float:
	return get_loadout_weapons_total() + get_field_pack_ammo_weight()


# Weight of the ammo the player chose to carry (the "ammo" loadout).
static func get_field_pack_ammo_weight() -> float:
	var total := 0.0
	for ammo_type in GlobalData.weapon_loadout.get("ammo", {}):
		total += GlobalData.AMMO_WEIGHT_PER_UNIT.get(ammo_type, 0.01) * float(get_loadout_ammo(ammo_type))
	return total


# Returns the equipped WeaponPart for the given hand ("left"/"right").
# Reads the central weapon_loadout so the Hangar and battle share one source.
# An explicitly-unarmed hand ("") returns null; only a missing/blank slot falls
# back to the default stock weapon for that hand.
static func get_equipped_weapon(side: String) -> WeaponPart:
	var path := str(GlobalData.weapon_loadout.get("left", "") if side == "left" else GlobalData.weapon_loadout.get("right", ""))
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		path = GlobalData.DEFAULT_LEFT_WEAPON_PATH if side == "left" else GlobalData.DEFAULT_RIGHT_WEAPON_PATH
	if ResourceLoader.exists(path):
		return load(path)
	return null


# Returns the WeaponParts the mech carries on its back into battle (from loadout).
static func get_carry_weapons() -> Array[WeaponPart]:
	var result: Array[WeaponPart] = []
	var carry_paths = GlobalData.weapon_loadout.get("carry", [])
	if not (carry_paths is Array):
		return result
	for path in carry_paths:
		if path is String and path != "" and ResourceLoader.exists(path):
			result.append(load(path))
	return result


# Total weight of all loadout weapons (both hands + back).
static func get_loadout_weapons_total() -> float:
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


# Total weight of all loadout weapons (both hands + back).
static func get_loadout_weapon_weight() -> float:
	return get_loadout_weapons_total()


# A weapon model may only be equipped in ONE slot at a time (left hand, right
# hand, or back carry). Returns the slot currently holding the model, or ""
# when it isn't equipped anywhere. Enforced by set_hand_weapon/add_carry_weapon
# so a shotgun can't be in both hands (or a hand + the back) at once.
static func weapon_equipped_slot(path: String) -> String:
	if str(GlobalData.weapon_loadout.get("left", "")) == path:
		return "left"
	if str(GlobalData.weapon_loadout.get("right", "")) == path:
		return "right"
	if is_weapon_in_carry(path):
		return "carry"
	return ""


# Assigns a weapon resource path to a hand. Empty path = unarmed hand.
# Returns false (and makes no change) if that weapon model is already equipped
# in the other hand or on the back pack.
static func set_hand_weapon(side: String, path: String) -> bool:
	if path == "":
		if side == "left":
			GlobalData.weapon_loadout["left"] = ""
		else:
			GlobalData.weapon_loadout["right"] = ""
		return true
	var equipped_slot := weapon_equipped_slot(path)
	if equipped_slot != "" and equipped_slot != side:
		return false
	if side == "left":
		GlobalData.weapon_loadout["left"] = path
	else:
		GlobalData.weapon_loadout["right"] = path
	return true


static func is_weapon_in_carry(path: String) -> bool:
	var carry_paths = GlobalData.weapon_loadout.get("carry", [])
	return carry_paths is Array and path in carry_paths


static func add_carry_weapon(path: String) -> bool:
	# One physical copy per model: a weapon already in a hand or on the back
	# pack cannot be added a second time.
	if path == "" or weapon_equipped_slot(path) != "":
		return false
	var carry_paths = GlobalData.weapon_loadout.get("carry", [])
	if not (carry_paths is Array):
		carry_paths = []
	carry_paths.append(path)
	GlobalData.weapon_loadout["carry"] = carry_paths
	return true


# How many physical copies of a weapon model are currently on the back pack.
static func count_carry_weapon(path: String) -> int:
	var carry_paths = GlobalData.weapon_loadout.get("carry", [])
	if not (carry_paths is Array):
		return 0
	var count := 0
	for p in carry_paths:
		if str(p) == path:
			count += 1
	return count


static func remove_carry_weapon(path: String) -> void:
	var carry_paths = GlobalData.weapon_loadout.get("carry", [])
	if carry_paths is Array:
		carry_paths.erase(path)
	GlobalData.weapon_loadout["carry"] = carry_paths


# Returns how much ammo of the given type the player carries into the next battle.
static func get_loadout_ammo(ammo_type: String) -> int:
	var ammo = GlobalData.weapon_loadout.get("ammo", {})
	if not (ammo is Dictionary):
		return 0
	return ammo.get(ammo_type.to_lower(), 0)


# Sets how much ammo of the given type the player carries into the next battle.
static func set_loadout_ammo(ammo_type: String, amount: int) -> void:
	var ammo = GlobalData.weapon_loadout.get("ammo", {})
	if not (ammo is Dictionary):
		ammo = {}
	ammo[ammo_type.to_lower()] = max(0, amount)
	GlobalData.weapon_loadout["ammo"] = ammo


static func get_loadout_ammo_dict() -> Dictionary:
	var ammo = GlobalData.weapon_loadout.get("ammo", {})
	if not (ammo is Dictionary):
		return {}
	return ammo.duplicate()


static func get_equipped_part_id(slot: String) -> String:
	var part = GlobalData.equipped_parts.get(slot)
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
	var result: Dictionary = GlobalData.chassis_catalog.get(GlobalData.chassis_id, GlobalData.chassis_catalog.get("standard", {
		"name": "Standard", "speed": 14.0, "max_weight": 75.0, "color": Color(0.6, 0.65, 0.7)
	})).duplicate(true)
	if not result.has("attachment_capacity"):
		var capacity := float(result.get("max_weight", 75.0))
		result["attachment_capacity"] = {"head": capacity * 0.10, "body": capacity * 0.35, "arm_left": capacity * 0.14, "arm_right": capacity * 0.14, "leg_left": capacity * 0.16, "leg_right": capacity * 0.16}
	result["movement_type"] = {"standard": "biped", "titan": "heavy", "vanguard": "light", "aegis": "hover", "brawler": "brawler"}.get(GlobalData.chassis_id, "biped")
	result["water_traversal"] = result["movement_type"] == "hover"
	# Power stat gates one-hand gripping of heavy two-hand weapons (rail/minigun).
	# It comes from the chassis plus the strength of both arm frames.
	if not result.has("power"):
		result["power"] = {"standard": 12.0, "titan": 18.0, "vanguard": 8.0, "aegis": 14.0, "brawler": 13.0}.get(GlobalData.chassis_id, 12.0)
	return result


# -----------------------------------------------------------------------------
# FRAME UPGRADES — the Inner Frame research branch adds flat HP / carry bonuses.
# -----------------------------------------------------------------------------


static func get_frame_upgrade_hp_bonus() -> float:
	return float(maxi(GlobalData.frame_upgrade_level - 1, 0)) * GlobalData.FRAME_UPGRADE_HP_BONUS


static func get_frame_upgrade_weight_bonus() -> float:
	return float(maxi(GlobalData.frame_upgrade_level - 1, 0)) * GlobalData.FRAME_UPGRADE_WEIGHT_BONUS


static func get_frame_upgrade_cost() -> int:
	return GlobalData.frame_upgrade_level * GlobalData.FRAME_UPGRADE_BASE_COST


# -----------------------------------------------------------------------------
# DEPOT AMMO / WEAPON INVENTORY — permanent storage outside the field pack.
# -----------------------------------------------------------------------------


static func get_reserve_ammo(ammo_type: String) -> int:
	return GlobalData.ammo_inventory.get(ammo_type.to_lower(), 0)


static func add_reserve_ammo(ammo_type: String, amount: int) -> void:
	var type = ammo_type.to_lower()
	GlobalData.ammo_inventory[type] = GlobalData.ammo_inventory.get(type, 0) + amount


static func consume_reserve_ammo(ammo_type: String, amount: int) -> int:
	var type = ammo_type.to_lower()
	var current = get_reserve_ammo(type)
	var taken = mini(current, amount)
	GlobalData.ammo_inventory[type] = current - taken
	return taken


static func register_weapon(path: String, weapon_name: String = "") -> void:
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
	# One inventory entry per weapon MODEL (same id/path), with a count. Picking
	# up or crafting another copy of the same model increments the count instead
	# of appending duplicate rows (which made one carried weapon show "[E]" on
	# several list entries).
	for entry in GlobalData.weapon_inventory:
		if str(entry.get("path", "")) == path:
			entry["count"] = int(entry.get("count", 1)) + 1
			entry["name"] = display_name
			return
	GlobalData.weapon_inventory.append({
		"uid": GlobalData._new_uid("w"),
		"path": path,
		"name": display_name,
		"durability": 1.0,
		"upgrade_level": 1,
		"count": 1
	})
