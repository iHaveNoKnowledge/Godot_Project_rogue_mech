class_name SaveGameIO
extends RefCounted

# -----------------------------------------------------------------------------
# SAVE / LOAD I/O
# Pure persistence logic extracted from GlobalData so the run-state autoload
# stays focused on game state instead of file/schema handling. Every function
# reads/writes state through the GlobalData singleton, and GlobalData keeps thin
# save_run()/load_run() facades for its existing callers.
# -----------------------------------------------------------------------------


static func save_run() -> void:
	GlobalData.sync_equipped_armor_durability()
	var data := {
		"chassis": GlobalData.chassis_id,
		"parts": serialize_parts(),
		"frames": serialize_frames(),
		"damage": GlobalData.part_damage.duplicate(),
		"attachments": serialize_attachments(),
		"armor_inventory": serialize_armor_inventory(),
		"position": {"x": GlobalData.current_tile.x, "y": GlobalData.current_tile.y},
		"heat": GlobalData.heat,
		"wanted": GlobalData.wanted_level,
		"credits": GlobalData.credits,
		"data_cores": GlobalData.data_cores,
		"scrap": GlobalData.scrap,
		"fleet_roster": GlobalData.fleet_roster.duplicate(true),
		"research_projects": GlobalData.research_projects.duplicate(true),
		"research_unlocked": GlobalData.research_unlocked.duplicate(),
		"sector": GlobalData.current_sector,
		"board_seed": GlobalData.board_seed,
		"enemy_forces": GlobalData.enemy_forces.duplicate(),
		"last_combat_squad_size": GlobalData.last_combat_squad_size,
		"max_notoriety_multiplier": GlobalData.max_notoriety_multiplier,
		"stalking_aces": GlobalData.stalking_aces,
		"stalking_chance": GlobalData.stalking_chance,
		"ammo_inventory": GlobalData.ammo_inventory.duplicate(),
		"weapon_inventory": GlobalData.weapon_inventory.duplicate(),
		"weapon_loadout": GlobalData.weapon_loadout.duplicate(true),
		"theme_id": GlobalData.theme_id,
		"reputation": GlobalData.reputation,
		"theme_switched": GlobalData.theme_switched,
		"ceasefire_turns": GlobalData.ceasefire_turns,
		"blocked_intermission": GlobalData.blocked_intermission,
		"enemy_tech_tier": GlobalData.enemy_tech_tier,
		"last_combat_damage_ratio": GlobalData.last_combat_damage_ratio,
		"enemy_research_progress": GlobalData.enemy_research_progress,
		"enemy_base_active": GlobalData.enemy_base_active,
		"enemy_base_progress": GlobalData.enemy_base_progress,
		"enemy_base_required": GlobalData.enemy_base_required,
		"enemy_base_tile_pos": {"x": GlobalData.enemy_base_tile_pos.x, "y": GlobalData.enemy_base_tile_pos.y},
		"enemy_grunt_upgrade_level": GlobalData.enemy_grunt_upgrade_level,
		"enemy_copy_outcome": GlobalData.enemy_copy_outcome,
		"enemy_special_units": GlobalData.enemy_special_units.duplicate(true),
		"fleet_security": GlobalData.fleet_security,
		"security_upgrade_level": GlobalData.security_upgrade_level,
		"driver_repair_skill": GlobalData.driver_repair_skill,
		"driver_repair_xp": GlobalData.driver_repair_xp,
		"scrap_patches": GlobalData.scrap_patches.duplicate(true),
		"hangar_mechs": GlobalData.hangar_mechs.duplicate(true),
		"active_hangar_mech_id": GlobalData.active_hangar_mech_id
	}
	var file := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


static func load_run() -> bool:
	if not FileAccess.file_exists(GlobalData.SAVE_PATH):
		return false
	var file := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	var data = JSON.parse_string(file.get_as_text())
	if data == null:
		return false
	restore_from_dict(data)
	return true


static func restore_from_dict(data: Dictionary) -> void:
	GlobalData.chassis_id = data.get("chassis", "standard")
	var frames_data = data.get("frames", {})
	if frames_data is Dictionary and not frames_data.is_empty():
		for slot in frames_data:
			GlobalData.equipped_frames[slot] = resolve_frame_value(frames_data[slot])
	GlobalData._ensure_default_frames()
	GlobalData.part_damage = data.get("damage", {})
	GlobalData.attachments = data.get("attachments", []).duplicate(true)
	GlobalData.heat = data.get("heat", 0)
	GlobalData.wanted_level = data.get("wanted", 0)
	GlobalData.credits = data.get("credits", 0) + int(data.get("spare_parts", 0))
	GlobalData.data_cores = data.get("data_cores", 0)
	GlobalData.scrap = data.get("scrap", 0)
	GlobalData.current_sector = data.get("sector", 1)
	GlobalData.board_seed = data.get("board_seed", randi())

	# Run theme fields (fallbacks keep older saves working).
	GlobalData.theme_id = str(data.get("theme_id", "soldier"))
	GlobalData.reputation = int(data.get("reputation", 0))
	GlobalData.theme_switched = bool(data.get("theme_switched", false))
	GlobalData.ceasefire_turns = int(data.get("ceasefire_turns", 0))
	GlobalData.blocked_intermission = bool(data.get("blocked_intermission", false))
	GlobalData.enemy_tech_tier = int(data.get("enemy_tech_tier", 1))
	GlobalData.last_combat_damage_ratio = float(data.get("last_combat_damage_ratio", 0.0))
	GlobalData.enemy_research_progress = float(data.get("enemy_research_progress", 0.0))
	GlobalData.enemy_base_active = bool(data.get("enemy_base_active", false))
	GlobalData.enemy_base_progress = float(data.get("enemy_base_progress", 0.0))
	GlobalData.enemy_base_required = float(data.get("enemy_base_required", 8.0))
	var base_tile = data.get("enemy_base_tile_pos", {})
	GlobalData.enemy_base_tile_pos = Vector2i(int(base_tile.get("x", -1)), int(base_tile.get("y", -1)))
	GlobalData.enemy_grunt_upgrade_level = int(data.get("enemy_grunt_upgrade_level", 0))
	GlobalData.enemy_copy_outcome = str(data.get("enemy_copy_outcome", ""))
	var special_units = data.get("enemy_special_units", [])
	if special_units is Array:
		GlobalData.enemy_special_units = special_units.duplicate(true)
	GlobalData.fleet_security = float(data.get("fleet_security", 25.0))
	GlobalData.security_upgrade_level = int(data.get("security_upgrade_level", 1))
	GlobalData.driver_repair_skill = int(data.get("driver_repair_skill", 1))
	GlobalData.driver_repair_xp = int(data.get("driver_repair_xp", 0))
	var loaded_patches = data.get("scrap_patches", {})
	if loaded_patches is Dictionary:
		GlobalData.scrap_patches = loaded_patches.duplicate(true)
	var loaded_hangar = data.get("hangar_mechs", [])
	if loaded_hangar is Array:
		GlobalData.hangar_mechs = loaded_hangar.duplicate(true)
	GlobalData.active_hangar_mech_id = str(data.get("active_hangar_mech_id", ""))

	var loaded_roster = data.get("fleet_roster", [])
	if loaded_roster is Array:
		GlobalData.fleet_roster = loaded_roster.duplicate(true)
	var loaded_research = data.get("research_projects", {})
	if loaded_research is Dictionary:
		GlobalData.research_projects = loaded_research.duplicate(true)
	var loaded_unlocked = data.get("research_unlocked", [])
	if loaded_unlocked is Array:
		GlobalData.research_unlocked = loaded_unlocked.duplicate()

	var pos = data.get("position", {"x": 0, "y": 0})
	GlobalData.current_tile = Vector2i(pos.x, pos.y)

	# --- Armor instance inventory (new schema) ---
	GlobalData.armor_inventory = []
	var loaded_armor = data.get("armor_inventory", [])
	if loaded_armor is Array:
		for raw in loaded_armor:
			if raw is Dictionary:
				GlobalData.armor_inventory.append(restore_armor_instance(raw))
	# Legacy migration: old "salvaged armor" drops become regular instances.
	var legacy_salvage = data.get("salvaged_armor_inventory", [])
	if legacy_salvage is Array:
		for item in legacy_salvage:
			if item is Dictionary:
				var inst: Dictionary = item.duplicate(true)
				inst["uid"] = GlobalData._new_uid("a")
				inst["db_id"] = ""
				inst["durability"] = clampf(float(inst.get("durability", 1.0)), 0.0, 1.0)
				inst["upgrade_level"] = 1
				inst["equipped"] = false
				GlobalData.armor_inventory.append(inst)

	var parts_dict: Dictionary = data.get("parts", {})
	GlobalData.equipped_parts.clear()
	for slot in parts_dict:
		GlobalData.equipped_parts[slot] = resolve_equipped_part(parts_dict[slot])
	ensure_equipped_parts_are_instances()
	GlobalData.sync_equipped_armor_durability()
	GlobalData.ensure_hangar_roster()

	GlobalData.enemy_forces = data.get("enemy_forces", {
		"boss_current": 1, "boss_max": 1,
		"ace_current": 1, "ace_max": 2,
		"grunt_current": 10, "grunt_max": 20
	}).duplicate()
	GlobalData.last_combat_squad_size = data.get("last_combat_squad_size", 1)
	GlobalData.max_notoriety_multiplier = data.get("max_notoriety_multiplier", 1.0)

	GlobalData.stalking_aces.clear()
	var loaded_aces = data.get("stalking_aces", [])
	if loaded_aces is Array:
		GlobalData.stalking_aces.assign(loaded_aces)

	GlobalData.stalking_chance = data.get("stalking_chance", 0.0)

	var loaded_ammo = data.get("ammo_inventory", {})
	if loaded_ammo is Dictionary and not loaded_ammo.is_empty():
		GlobalData.ammo_inventory = loaded_ammo.duplicate()

	var loaded_weapons = data.get("weapon_inventory", [])
	GlobalData.weapon_inventory = []
	if loaded_weapons is Array:
		for entry in loaded_weapons:
			if entry is Dictionary and entry.has("uid"):
				GlobalData.weapon_inventory.append(entry.duplicate())
			elif entry is Dictionary:
				# Legacy count-based stash: expand each copy into its own instance.
				var count = int(entry.get("count", 1))
				for i in range(maxi(count, 1)):
					var inst: Dictionary = entry.duplicate(true)
					inst.erase("count")
					inst["uid"] = GlobalData._new_uid("w")
					inst["durability"] = 1.0
					inst["upgrade_level"] = 1
					GlobalData.weapon_inventory.append(inst)

	var loaded_loadout = data.get("weapon_loadout", null)
	if loaded_loadout is Dictionary and not loaded_loadout.is_empty():
		GlobalData.weapon_loadout = loaded_loadout.duplicate(true)
		# Older saves predate the "ammo" loadout key — default to the stash.
		if not GlobalData.weapon_loadout.has("ammo"):
			GlobalData.weapon_loadout["ammo"] = {
				"kinetic": GlobalData.get_reserve_ammo("kinetic"),
				"energy": GlobalData.get_reserve_ammo("energy"),
				"explosive": GlobalData.get_reserve_ammo("explosive"),
				"missile": GlobalData.get_reserve_ammo("missile")
			}


static func serialize_parts() -> Dictionary:
	var result := {}
	for slot in GlobalData.equipped_parts:
		var item = GlobalData.equipped_parts[slot]
		if item == null:
			result[slot] = null
		elif item is Dictionary and item.has("uid"):
			# Owned instance: persist the uid reference (armor_inventory has the rest).
			result[slot] = {"uid": item["uid"], "equipped": item.get("equipped", true)}
		elif item is Resource and "resource_path" in item and item.resource_path != "":
			# Resource file: save path string for reload
			result[slot] = item.resource_path
		elif item is Dictionary:
			var pid = item.get("id", "")
			if pid != "" and GlobalData.is_catalog_armor_id(pid):
				# Legacy catalog part: persist only the id reference + equipped state.
				# Static stats always come from the catalog (single source of truth).
				result[slot] = {"id": pid, "equipped": item.get("equipped", true)}
			else:
				# Legacy instance part (non-catalog): persist the full dict.
				result[slot] = item.duplicate(true)
		else:
			result[slot] = str(item)
	return result


static func serialize_armor_inventory() -> Array:
	var result: Array = []
	for inst in GlobalData.armor_inventory:
		var copy: Dictionary = inst.duplicate(true)
		if copy.get("color") is Color:
			var c: Color = copy["color"]
			copy["color"] = {"r": c.r, "g": c.g, "b": c.b, "a": c.a}
		result.append(copy)
	return result


static func restore_armor_instance(raw: Dictionary) -> Dictionary:
	var inst := raw.duplicate(true)
	if inst.get("color") is Dictionary:
		var cd: Dictionary = inst["color"]
		inst["color"] = Color(
			float(cd.get("r", 0.5)), float(cd.get("g", 0.5)),
			float(cd.get("b", 0.5)), float(cd.get("a", 1.0))
		)
	inst["durability"] = clampf(float(inst.get("durability", 1.0)), 0.0, 1.0)
	inst["upgrade_level"] = int(inst.get("upgrade_level", 1))
	return inst


static func serialize_frames() -> Dictionary:
	var result := {}
	for slot in GlobalData.equipped_frames:
		var f = GlobalData.equipped_frames[slot]
		if f is Dictionary and f.get("id", "") != "" and GlobalData.is_catalog_frame_id(f["id"]):
			# Catalog frame: persist only the id reference.
			result[slot] = {"id": f["id"]}
		else:
			result[slot] = f.duplicate(true)
	return result


# Older saves predate frame ids. Resolve a saved frame value into a full catalog
# entry so the Field Pack capacity and stats stay consistent across old save files.
static func resolve_frame_value(v: Variant) -> Variant:
	if v is Dictionary:
		var entry: Dictionary = {}
		var fid = v.get("id", "")
		if fid != "":
			entry = GlobalData.get_frame_catalog_entry(fid)
		if entry.is_empty():
			entry = GlobalData.get_frame_catalog_entry_by_name(v.get("name", ""))
		if not entry.is_empty():
			return entry.duplicate(true)
		return v.duplicate(true)
	return v


# Resolves a saved equipped-part value into a usable runtime part.
#   - Resource path string -> loads the Resource
#   - Catalog id reference -> resolved fresh from armor_catalog (with instance flags)
#   - Full legacy/salvaged dict -> returned as-is (instance data, not in catalog)
static func resolve_armor_value(v: Variant) -> Variant:
	if v is String and ResourceLoader.exists(v):
		return load(v)
	if v is Dictionary:
		var pid = v.get("id", "")
		var entry: Dictionary = {}
		if pid != "":
			entry = GlobalData.get_armor_catalog_entry(pid)
		if not entry.is_empty():
			var resolved = entry.duplicate()
			resolved["equipped"] = v.get("equipped", true)
			return resolved
		return v.duplicate(true)
	return v


# Resolves a saved equipped-part value. Owned instances resolve to the instance
# stored in armor_inventory (shared reference); everything else falls back to the
# legacy resolver.
static func resolve_equipped_part(v: Variant) -> Variant:
	if v is Dictionary and v.has("uid"):
		var inst := GlobalData.get_armor_instance(str(v["uid"]))
		if not inst.is_empty():
			inst["equipped"] = v.get("equipped", true)
			return inst
	return resolve_armor_value(v)


# Migrates any legacy equipped part (catalog id / full dict without a uid) into a
# proper instance so the whole loadout is instance-based after loading old saves.
static func ensure_equipped_parts_are_instances() -> void:
	for slot in GlobalData.equipped_parts.keys():
		var part = GlobalData.equipped_parts[slot]
		if part == null or part is Resource:
			continue
		if part is Dictionary and part.has("uid"):
			continue
		var inst: Dictionary = {}
		var pid = part.get("id", "") if part is Dictionary else ""
		if pid != "" and GlobalData.is_catalog_armor_id(pid):
			var created := GlobalData.make_armor_instance_from_catalog(pid)
			if not created.is_empty():
				inst = created
		else:
			inst = (part.duplicate(true) if part is Dictionary else {})
			inst["uid"] = GlobalData._new_uid("a")
			inst["db_id"] = ""
			inst["slot"] = str(part.get("slot", slot)) if part is Dictionary else slot
			inst["durability"] = 1.0
			inst["upgrade_level"] = 1
		if not inst.is_empty():
			GlobalData.equip_armor_instance(inst["uid"], slot)


static func serialize_attachments() -> Array:
	var result: Array = []
	for attachment in GlobalData.attachments:
		var copy: Dictionary = attachment.duplicate(true)
		for key in ["position", "rotation", "scale", "size"]:
			if copy.get(key) is Vector3:
				var value: Vector3 = copy[key]
				copy[key] = {"x": value.x, "y": value.y, "z": value.z}
		result.append(copy)
	return result
