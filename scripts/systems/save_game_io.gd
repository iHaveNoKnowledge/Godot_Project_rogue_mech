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
	ArmorSystem.sync_equipped_armor_durability()
	var data := {
		"chassis": GlobalData.weapons.chassis_id,
		"power_core": GlobalData.weapons.power_core_id,
		"parts": serialize_parts(),
		"frames": serialize_frames(),
		"damage": GlobalData.weapons.part_damage.duplicate(),
		"attachments": serialize_attachments(),
		"armor_inventory": serialize_armor_inventory(),
		"position": {"x": GlobalData.board.current_tile.x, "y": GlobalData.board.current_tile.y},
		"heat": GlobalData.board.heat,
		"wanted": GlobalData.board.wanted_level,
		"wanted_escalation": GlobalData.board.wanted_escalation,
		"credits": GlobalData.currency.credits,
		"data_cores": GlobalData.currency.data_cores,
		"scrap": GlobalData.currency.scrap,
		"fleet_roster": GlobalData.hangar.fleet_roster.duplicate(true),
		"recruited_characters": GlobalData.hangar.recruited_characters.duplicate(),
		"pending_duel": GlobalData.hangar.pending_duel.duplicate(true),
		"research_projects": GlobalData.hangar.research_projects.duplicate(true),
		"research_unlocked": GlobalData.hangar.research_unlocked.duplicate(),
		"sector": GlobalData.board.current_sector,
		"board_seed": GlobalData.board.board_seed,
		"board_mp": GlobalData.board.board_mp,
		"board_mp_max": GlobalData.board.board_mp_max,
		"board_day": GlobalData.board.board_day,
		"time_hour": GlobalData.board.time_hour,
		"current_hazard": GlobalData.board.current_hazard,
		"board_theme_id": GlobalData.board.board_theme_id,
		"board_objective_id": GlobalData.board.board_objective_id,
		"board_objective_progress": GlobalData.board.board_objective_progress,
		"board_objective_required": GlobalData.board.board_objective_required,
		"board_objective_intro_consumed": GlobalData.board.board_objective_intro_consumed,
		"active_contract": GlobalData.board.active_contract.duplicate(true),
		"primary_objective_done": GlobalData.board.primary_objective_done,
		"secondary_objectives_status": GlobalData.board.secondary_objectives_status.duplicate(),
		"extraction_zone_pos": {"x": GlobalData.board.extraction_zone_pos.x, "y": GlobalData.board.extraction_zone_pos.y},
		"extraction_unlocked": GlobalData.board.extraction_unlocked,
		"extraction_min_heat": GlobalData.board.extraction_min_heat,
		"extraction_max_heat": GlobalData.board.extraction_max_heat,
		"mission_step_count": GlobalData.board.mission_step_count,
		"board_patrols": _serialize_patrols(),
		"enemy_forces": GlobalData.narrative.enemy_forces.duplicate(),
		"last_combat_squad_size": GlobalData.narrative.last_combat_squad_size,
		"max_notoriety_multiplier": GlobalData.narrative.max_notoriety_multiplier,
		"stalking_aces": GlobalData.narrative.stalking_aces,
		"stalking_chance": GlobalData.narrative.stalking_chance,
		"ammo_inventory": GlobalData.weapons.ammo_inventory.duplicate(),
		"weapon_inventory": GlobalData.weapons.weapon_inventory.duplicate(),
		"weapon_loadout": GlobalData.weapons.weapon_loadout.duplicate(true),
		"theme_id": GlobalData.narrative.theme_id,
		"reputation": GlobalData.narrative.reputation,
		"theme_switched": GlobalData.narrative.theme_switched,
		"ceasefire_turns": GlobalData.narrative.ceasefire_turns,
		"blocked_intermission": GlobalData.narrative.blocked_intermission,
		"mech_less": GlobalData.narrative.mech_less,
		"enemy_tech_tier": GlobalData.narrative.enemy_tech_tier,
		"last_combat_damage_ratio": GlobalData.last_combat_damage_ratio,
		"enemy_research_progress": GlobalData.narrative.enemy_research_progress,
		"enemy_base_active": GlobalData.narrative.enemy_base_active,
		"enemy_base_progress": GlobalData.narrative.enemy_base_progress,
		"enemy_base_required": GlobalData.narrative.enemy_base_required,
		"enemy_base_tile_pos": {"x": GlobalData.narrative.enemy_base_tile_pos.x, "y": GlobalData.narrative.enemy_base_tile_pos.y},
		"enemy_grunt_upgrade_level": GlobalData.narrative.enemy_grunt_upgrade_level,
		"enemy_copy_outcome": GlobalData.narrative.enemy_copy_outcome,
		"enemy_special_units": GlobalData.narrative.enemy_special_units.duplicate(true),
		"fleet_security": GlobalData.narrative.fleet_security,
		"security_upgrade_level": GlobalData.narrative.security_upgrade_level,
		"mech_energy": GlobalData.fuel.mech_energy,
		"mech_max_energy": GlobalData.fuel.mech_max_energy,
		"mech_fuel_containers": GlobalData.fuel.mech_fuel_inventory.serialize(),
		"convoy_fuel_containers": GlobalData.fuel.convoy_fuel_inventory.serialize(),
		"last_mech_fuel_type": GlobalData.fuel.last_mech_fuel_type,
		"convoy_fuel_reserve": GlobalData.fuel.convoy_fuel_reserve,
		"convoy_fuel_max": GlobalData.fuel.convoy_fuel_max,
		"fuel_depot_seized_today": GlobalData.fuel.fuel_depot_seized_today,
		"drop_tanks_attached": GlobalData.fuel.drop_tanks_attached,
		"drop_tank_fuel": GlobalData.fuel.drop_tank_fuel,
		"engine_dirt": GlobalData.fuel.engine_dirt,
		"wreckage_tile_pos": {"x": GlobalData.fuel.wreckage_tile_pos.x, "y": GlobalData.fuel.wreckage_tile_pos.y},
		"wreckage_fuel_remaining": GlobalData.fuel.wreckage_fuel_remaining,
		"siphoned_fuel": GlobalData.fuel.siphoned_fuel,
		"driver_repair_skill": GlobalData.narrative.driver_repair_skill,
		"driver_repair_xp": GlobalData.narrative.driver_repair_xp,
		"scrap_patches": GlobalData.weapons.scrap_patches.duplicate(true),
		"frame_bindings": GlobalData.weapons.frame_bindings.duplicate(true),
		"frame_modules": GlobalData.weapons.frame_modules.duplicate(true),
		"module_inventory": GlobalData.weapons.module_inventory.duplicate(true),
		"equipped_backpack": GlobalData.weapons.equipped_backpack.duplicate(true) if GlobalData.weapons.equipped_backpack is Dictionary else GlobalData.weapons.equipped_backpack,
		"backpack_inventory": GlobalData.weapons.backpack_inventory.duplicate(true),
		"part_hit_meta": _serialize_hit_meta(),
		"thermal_cloak": GlobalData.thermal_cloak.serialize() if GlobalData.thermal_cloak else {},
		"ewar": GlobalData.ewar.serialize() if GlobalData.ewar else {},
		"weather_transition": GlobalData.weather_transition.serialize() if GlobalData.weather_transition else {},
		"hangar_mechs": GlobalData.hangar.hangar_mechs.duplicate(true),
		"active_hangar_mech_id": GlobalData.hangar.active_hangar_mech_id,
		"frame_upgrade_level": GlobalData.weapons.frame_upgrade_level,
		"pilot_hp": GlobalData.pilot.pilot_hp,
		"pilot_max_hp": GlobalData.pilot.pilot_max_hp,
		"pilot_weapons": GlobalData.pilot.pilot_weapons.duplicate(),
		"pilot_ammo": GlobalData.pilot.pilot_ammo.duplicate(),
		"pilot_items": GlobalData.pilot.pilot_items.duplicate(),
		"pilot_progression": PilotSystem.serialize_progression(),
		"technology_discovery": TechnologySystem.serialize_discovery_states(),
		"world_technology_diffusion": TechnologySystem.serialize_world_diffusion_state(),
		"era_progression": EraProgressionSystem.serialize_era_state(),
		"rival_progression": RivalProgressionSystem.serialize_rival_state(),
		"tile_wreckages": _serialize_tile_wreckages()
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
	GlobalData.weapons.chassis_id = data.get("chassis", "standard")
	GlobalData.weapons.power_core_id = data.get("power_core", "combustion")
	var frames_data = data.get("frames", {})
	if frames_data is Dictionary and not frames_data.is_empty():
		for slot in frames_data:
			GlobalData.weapons.equipped_frames[slot] = resolve_frame_value(frames_data[slot])
	GlobalData.weapons._ensure_default_frames()
	GlobalData.weapons.attachments = data.get("attachments", []).duplicate(true)
	GlobalData.board.heat = data.get("heat", 0)
	GlobalData.board.wanted_level = data.get("wanted", 0)
	GlobalData.board.wanted_escalation = int(data.get("wanted_escalation", 0))
	GlobalData.currency.credits = data.get("credits", 0) + int(data.get("spare_parts", 0))
	GlobalData.currency.data_cores = data.get("data_cores", 0)
	GlobalData.currency.scrap = data.get("scrap", 0)
	GlobalData.board.current_sector = data.get("sector", 1)
	GlobalData.board.board_seed = data.get("board_seed", randi())
	GlobalData.board.board_mp = int(data.get("board_mp", GlobalData.board.board_mp_max))
	GlobalData.board.board_mp_max = maxi(int(data.get("board_mp_max", 8)), 1)
	GlobalData.board.board_day = maxi(int(data.get("board_day", 1)), 1)
	GlobalData.board.time_hour = float(data.get("time_hour", 8.0))
	GlobalData.board.current_hazard = str(data.get("current_hazard", ""))
	GlobalData.board.board_theme_id = str(data.get("board_theme_id", "suburb"))
	GlobalData.board.board_objective_id = str(data.get("board_objective_id", ""))
	GlobalData.board.board_objective_progress = int(data.get("board_objective_progress", 0))
	GlobalData.board.board_objective_required = int(data.get("board_objective_required", 0))
	GlobalData.board.board_objective_intro_consumed = bool(data.get("board_objective_intro_consumed", false))
	# Extraction contract: only prompt mission select when no contract is active.
	# Without this, Continue always reopened the select screen instead of
	# resuming the in-progress mission.
	var loaded_contract = data.get("active_contract", {})
	GlobalData.board.active_contract = loaded_contract.duplicate(true) if loaded_contract is Dictionary else {}
	GlobalData.board.primary_objective_done = bool(data.get("primary_objective_done", false))
	var loaded_secondary = data.get("secondary_objectives_status", {})
	GlobalData.board.secondary_objectives_status = loaded_secondary.duplicate() if loaded_secondary is Dictionary else {}
	var loaded_extraction = data.get("extraction_zone_pos", {"x": -1, "y": -1})
	GlobalData.board.extraction_zone_pos = Vector2i(int(loaded_extraction.get("x", -1)), int(loaded_extraction.get("y", -1)))
	GlobalData.board.extraction_unlocked = bool(data.get("extraction_unlocked", false))
	GlobalData.board.extraction_min_heat = int(data.get("extraction_min_heat", 1))
	GlobalData.board.extraction_max_heat = int(data.get("extraction_max_heat", 5))
	GlobalData.board.mission_step_count = int(data.get("mission_step_count", 0))
	var loaded_patrols = data.get("board_patrols", [])
	GlobalData.board.board_patrols.clear()
	GlobalData.board.board_patrol_engagement = -1
	if loaded_patrols is Array:
		for p in loaded_patrols:
			if not (p is Dictionary):
				continue
			var p_copy: Dictionary = p.duplicate(true)
			if p_copy.get("pos") is Dictionary:
				var pd: Dictionary = p_copy["pos"]
				p_copy["pos"] = Vector2i(int(pd.get("x", 0)), int(pd.get("y", 0)))
			elif p_copy.get("pos") is String:
				p_copy["pos"] = _parse_vec2i(str(p_copy["pos"]))
			if p_copy.get("home") is Dictionary:
				var hd: Dictionary = p_copy["home"]
				p_copy["home"] = Vector2i(int(hd.get("x", 0)), int(hd.get("y", 0)))
			elif p_copy.get("home") is String:
				p_copy["home"] = _parse_vec2i(str(p_copy["home"]))
			if p_copy.get("prev_pos") is Dictionary:
				var ppd: Dictionary = p_copy["prev_pos"]
				p_copy["prev_pos"] = Vector2i(int(ppd.get("x", 0)), int(ppd.get("y", 0)))
			elif p_copy.get("prev_pos") is String:
				p_copy["prev_pos"] = _parse_vec2i(str(p_copy["prev_pos"]))
			# dir is the fleet's last movement heading — restore it to a real
			# Vector2i (old saves flattened it to a String, which crashed the
			# patrol arrow marker and left fleets invisible on the board).
			if p_copy.get("dir") is Dictionary:
				var dd: Dictionary = p_copy["dir"]
				p_copy["dir"] = Vector2i(int(dd.get("x", 1)), int(dd.get("y", 0)))
			elif p_copy.get("dir") is String:
				p_copy["dir"] = _parse_vec2i(str(p_copy["dir"]), Vector2i(1, 0))
			# Heal nested Colors inside pilots[].mech_loadout (saved as {r,g,b,a})
			if p_copy.get("pilots") is Array:
				for pilot in p_copy["pilots"]:
					if not (pilot is Dictionary):
						continue
					var loadout2 = pilot.get("mech_loadout", null)
					if loadout2 is Dictionary:
						for slot2 in loadout2:
							var entry2 = loadout2[slot2]
							if entry2 is Dictionary:
								for sub2 in ["frame", "armor"]:
									var part2 = entry2.get(sub2, null)
									if part2 is Dictionary and part2.get("color") is Dictionary:
										var cd2: Dictionary = part2["color"]
										part2["color"] = Color(float(cd2.get("r", 0.5)), float(cd2.get("g", 0.5)), float(cd2.get("b", 0.5)), float(cd2.get("a", 1.0)))
			if p_copy.get("commander") is Dictionary and p_copy["commander"].get("mech_loadout") is Dictionary:
				for slot2 in p_copy["commander"]["mech_loadout"]:
					var entry2 = p_copy["commander"]["mech_loadout"][slot2]
					if entry2 is Dictionary:
						for sub2 in ["frame", "armor"]:
							var part2 = entry2.get(sub2, null)
							if part2 is Dictionary and part2.get("color") is Dictionary:
								var cd2: Dictionary = part2["color"]
								part2["color"] = Color(float(cd2.get("r", 0.5)), float(cd2.get("g", 0.5)), float(cd2.get("b", 0.5)), float(cd2.get("a", 1.0)))
			GlobalData.board.board_patrols.append(p_copy)

	# Run theme fields (fallbacks keep older saves working).
	GlobalData.narrative.theme_id = str(data.get("theme_id", "soldier"))
	GlobalData.narrative.reputation = int(data.get("reputation", 0))
	GlobalData.narrative.theme_switched = bool(data.get("theme_switched", false))
	GlobalData.narrative.ceasefire_turns = int(data.get("ceasefire_turns", 0))
	GlobalData.narrative.blocked_intermission = bool(data.get("blocked_intermission", false))
	GlobalData.narrative.mech_less = bool(data.get("mech_less", false))
	GlobalData.narrative.enemy_tech_tier = int(data.get("enemy_tech_tier", 1))
	GlobalData.last_combat_damage_ratio = float(data.get("last_combat_damage_ratio", 0.0))
	GlobalData.narrative.enemy_research_progress = float(data.get("enemy_research_progress", 0.0))
	GlobalData.narrative.enemy_base_active = bool(data.get("enemy_base_active", false))
	GlobalData.narrative.enemy_base_progress = float(data.get("enemy_base_progress", 0.0))
	GlobalData.narrative.enemy_base_required = float(data.get("enemy_base_required", 8.0))
	var base_tile = data.get("enemy_base_tile_pos", {})
	GlobalData.narrative.enemy_base_tile_pos = Vector2i(int(base_tile.get("x", -1)), int(base_tile.get("y", -1)))
	GlobalData.narrative.enemy_grunt_upgrade_level = int(data.get("enemy_grunt_upgrade_level", 0))
	GlobalData.narrative.enemy_copy_outcome = str(data.get("enemy_copy_outcome", ""))
	var special_units = data.get("enemy_special_units", [])
	if special_units is Array:
		GlobalData.narrative.enemy_special_units = special_units.duplicate(true)
	GlobalData.narrative.fleet_security = float(data.get("fleet_security", 25.0))
	GlobalData.narrative.security_upgrade_level = int(data.get("security_upgrade_level", 1))
	GlobalData.fuel.mech_energy = float(data.get("mech_energy", 100.0))
	GlobalData.fuel.mech_max_energy = float(data.get("mech_max_energy", 100.0))
	var mech_fc = data.get("mech_fuel_containers", [])
	if mech_fc is Array and not mech_fc.is_empty():
		GlobalData.fuel.mech_fuel_inventory.deserialize(mech_fc)
	var convoy_fc = data.get("convoy_fuel_containers", [])
	if convoy_fc is Array and not convoy_fc.is_empty():
		GlobalData.fuel.convoy_fuel_inventory.deserialize(convoy_fc)
	GlobalData.fuel.last_mech_fuel_type = int(data.get("last_mech_fuel_type", -1))
	GlobalData.fuel.convoy_fuel_reserve = float(data.get("convoy_fuel_reserve", 100.0))
	GlobalData.fuel.convoy_fuel_max = float(data.get("convoy_fuel_max", 200.0))
	GlobalData.fuel.fuel_depot_seized_today = bool(data.get("fuel_depot_seized_today", false))
	GlobalData.fuel.drop_tanks_attached = int(data.get("drop_tanks_attached", 0))
	GlobalData.fuel.drop_tank_fuel = float(data.get("drop_tank_fuel", 0.0))
	GlobalData.fuel.engine_dirt = float(data.get("engine_dirt", 0.0))
	var wreck_pos = data.get("wreckage_tile_pos", {})
	GlobalData.fuel.wreckage_tile_pos = Vector2i(int(wreck_pos.get("x", -1)), int(wreck_pos.get("y", -1)))
	GlobalData.fuel.wreckage_fuel_remaining = float(data.get("wreckage_fuel_remaining", 80.0))
	GlobalData.fuel.siphoned_fuel = float(data.get("siphoned_fuel", 0.0))
	GlobalData.narrative.driver_repair_skill = int(data.get("driver_repair_skill", 1))
	GlobalData.narrative.driver_repair_xp = int(data.get("driver_repair_xp", 0))
	var loaded_patches = data.get("scrap_patches", {})
	if loaded_patches is Dictionary:
		GlobalData.weapons.scrap_patches = loaded_patches.duplicate(true)
	var loaded_bindings = data.get("frame_bindings", {})
	if loaded_bindings is Dictionary:
		GlobalData.weapons.frame_bindings = loaded_bindings.duplicate(true)
	var loaded_modules = data.get("frame_modules", {})
	if loaded_modules is Dictionary:
		GlobalData.weapons.frame_modules = loaded_modules.duplicate(true)
	var loaded_mod_inv = data.get("module_inventory", [])
	if loaded_mod_inv is Array:
		GlobalData.weapons.module_inventory = loaded_mod_inv.duplicate(true)
	var raw_bp = data.get("equipped_backpack", {})
	if raw_bp is Dictionary:
		GlobalData.weapons.equipped_backpack = raw_bp.duplicate(true)
	elif raw_bp is String and raw_bp != "":
		BackpackSystem.equip(raw_bp)
	else:
		GlobalData.weapons.equipped_backpack = {}
	var loaded_backpack_inv = data.get("backpack_inventory", [])
	if loaded_backpack_inv is Array:
		GlobalData.weapons.backpack_inventory = loaded_backpack_inv.duplicate(true)
	var loaded_hit = data.get("part_hit_meta", {})
	if loaded_hit is Dictionary:
		GlobalData.weapons.part_hit_meta = _deserialize_hit_meta(loaded_hit)
	var loaded_cloak = data.get("thermal_cloak", {})
	if loaded_cloak is Dictionary and GlobalData.thermal_cloak:
		GlobalData.thermal_cloak.deserialize(loaded_cloak)
	var loaded_ewar = data.get("ewar", {})
	if loaded_ewar is Dictionary and GlobalData.ewar:
		GlobalData.ewar.deserialize(loaded_ewar)
	var loaded_weather = data.get("weather_transition", {})
	if loaded_weather is Dictionary and GlobalData.weather_transition:
		GlobalData.weather_transition.deserialize(loaded_weather)
	var loaded_hangar = data.get("hangar_mechs", [])
	if loaded_hangar is Array:
		GlobalData.hangar.hangar_mechs = loaded_hangar.duplicate(true)
	GlobalData.hangar.active_hangar_mech_id = str(data.get("active_hangar_mech_id", ""))
	# Clamp to >= 1 so a null/corrupt value can't produce a negative upgrade level.
	GlobalData.weapons.frame_upgrade_level = maxi(int(data.get("frame_upgrade_level", 1)), 1)

	# Pilot state (fallbacks keep older saves working).
	GlobalData.pilot.pilot_max_hp = maxf(float(data.get("pilot_max_hp", PilotSystem.PILOT_MAX_HP_DEFAULT)), 1.0)
	GlobalData.pilot.pilot_hp = clampf(float(data.get("pilot_hp", GlobalData.pilot.pilot_max_hp)), 0.0, GlobalData.pilot.pilot_max_hp)
	var loaded_pilot_weapons = data.get("pilot_weapons", ["res://resources/mech/stock/weapon_beam_rifle.tres"])
	GlobalData.pilot.pilot_weapons = []
	if loaded_pilot_weapons is Array:
		for path in loaded_pilot_weapons:
			if str(path) != "":
				GlobalData.pilot.pilot_weapons.append(str(path))
	var loaded_pilot_ammo = data.get("pilot_ammo", {})
	GlobalData.pilot.pilot_ammo = {}
	if loaded_pilot_ammo is Dictionary:
		# Pilot pools are human-scale — legacy shared keys convert over.
		GlobalData.pilot.pilot_ammo = AmmoSystem.migrate_pilot_dict(loaded_pilot_ammo.duplicate())
	var loaded_pilot_items = data.get("pilot_items", {})
	GlobalData.pilot.pilot_items = {}
	if loaded_pilot_items is Dictionary:
		GlobalData.pilot.pilot_items = loaded_pilot_items.duplicate()

	var loaded_pilot_progression = data.get("pilot_progression", {})
	PilotSystem.deserialize_progression(loaded_pilot_progression)

	var loaded_roster = data.get("fleet_roster", [])
	if loaded_roster is Array:
		GlobalData.hangar.fleet_roster = loaded_roster.duplicate(true)
	var loaded_recruits = data.get("recruited_characters", [])
	if loaded_recruits is Array:
		GlobalData.hangar.recruited_characters = loaded_recruits.duplicate()
	var loaded_duel = data.get("pending_duel", {})
	if loaded_duel is Dictionary:
		GlobalData.hangar.pending_duel = loaded_duel.duplicate(true)
	var loaded_research = data.get("research_projects", {})
	if loaded_research is Dictionary:
		GlobalData.hangar.research_projects = loaded_research.duplicate(true)
	var loaded_unlocked = data.get("research_unlocked", [])
	if loaded_unlocked is Array:
		GlobalData.hangar.research_unlocked = loaded_unlocked.duplicate()
	var loaded_tech_discovery = data.get("technology_discovery", {})
	TechnologySystem.deserialize_discovery_states(loaded_tech_discovery)
	var loaded_world_diffusion = data.get("world_technology_diffusion", {})
	TechnologySystem.deserialize_world_diffusion_state(loaded_world_diffusion)
	var loaded_era_progression = data.get("era_progression", {})
	EraProgressionSystem.deserialize_era_state(loaded_era_progression)
	var loaded_rival_progression = data.get("rival_progression", {})
	RivalProgressionSystem.deserialize_rival_state(loaded_rival_progression)
	_deserialize_tile_wreckages(data.get("tile_wreckages", {}))

	var pos = data.get("position", {"x": 0, "y": 0})
	GlobalData.board.current_tile = Vector2i(pos.x, pos.y)

	# --- Armor instance inventory (new schema) ---
	GlobalData.weapons.armor_inventory = []
	var loaded_armor = data.get("armor_inventory", [])
	if loaded_armor is Array:
		for raw in loaded_armor:
			if raw is Dictionary:
				GlobalData.weapons.armor_inventory.append(restore_armor_instance(raw))
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
				GlobalData.weapons.armor_inventory.append(inst)

	var parts_dict: Dictionary = data.get("parts", {})
	GlobalData.weapons.equipped_parts.clear()
	for slot in parts_dict:
		GlobalData.weapons.equipped_parts[slot] = resolve_equipped_part(parts_dict[slot])
	ensure_equipped_parts_are_instances()
	# Restore the saved damage AFTER migration — equip_armor_instance() rewrites
	# part_damage from the fresh instance durability (1.0), which would otherwise
	# wipe the wear that was already restored above.
	GlobalData.weapons.part_damage = data.get("damage", {})
	ArmorSystem.sync_equipped_armor_durability()
	HangarManager.ensure_roster()

	GlobalData.narrative.enemy_forces = data.get("enemy_forces", {
		"boss_current": 1, "boss_max": 1,
		"ace_current": 1, "ace_max": 2,
		"grunt_current": 10, "grunt_max": 20
	}).duplicate()
	GlobalData.narrative.last_combat_squad_size = data.get("last_combat_squad_size", 1)
	GlobalData.narrative.max_notoriety_multiplier = data.get("max_notoriety_multiplier", 1.0)

	GlobalData.narrative.stalking_aces.clear()
	var loaded_aces = data.get("stalking_aces", [])
	if loaded_aces is Array:
		GlobalData.narrative.stalking_aces.assign(loaded_aces)

	GlobalData.narrative.stalking_chance = data.get("stalking_chance", 0.0)

	var loaded_ammo = data.get("ammo_inventory", {})
	if loaded_ammo is Dictionary and not loaded_ammo.is_empty():
		GlobalData.weapons.ammo_inventory = AmmoSystem.migrate_dict(loaded_ammo.duplicate())

	var loaded_weapons = data.get("weapon_inventory", [])
	GlobalData.weapons.weapon_inventory = []
	if loaded_weapons is Array:
		for entry in loaded_weapons:
			if entry is Dictionary and entry.has("uid"):
				GlobalData.weapons.weapon_inventory.append(entry.duplicate())
			elif entry is Dictionary:
				# Legacy count-based stash: expand each copy into its own instance.
				var count = int(entry.get("count", 1))
				for i in range(maxi(count, 1)):
					var inst: Dictionary = entry.duplicate(true)
					inst.erase("count")
					inst["uid"] = GlobalData._new_uid("w")
					inst["durability"] = 1.0
					inst["upgrade_level"] = 1
					GlobalData.weapons.weapon_inventory.append(inst)

	var loaded_loadout = data.get("weapon_loadout", null)
	if loaded_loadout is Dictionary and not loaded_loadout.is_empty():
		GlobalData.weapons.weapon_loadout = loaded_loadout.duplicate(true)
		# Older saves predate the "ammo" loadout key — default to the stash.
		if not GlobalData.weapons.weapon_loadout.has("ammo"):
			var fallback_ammo := {}
			for ammo_id in AmmoSystem.ORDER:
				fallback_ammo[ammo_id] = LoadoutSystem.get_reserve_ammo(ammo_id)
			GlobalData.weapons.weapon_loadout["ammo"] = fallback_ammo
		else:
			# Older saves use the legacy 4-type ammo keys — migrate to the
			# 8-type catalog (kinetic -> bullet/heavy_round/shell/spike, ...).
			var loadout_ammo = GlobalData.weapons.weapon_loadout.get("ammo", {})
			if loadout_ammo is Dictionary:
				GlobalData.weapons.weapon_loadout["ammo"] = AmmoSystem.migrate_dict(loadout_ammo)
		# Older saves stored resource PATHS in the loadout; current saves store
		# instance uids so the [E] badge stays per-instance. Migrate any path
		# refs to the matching stash instance's uid when one exists.
		for key in ["left", "right", "shoulder_left", "shoulder_right"]:
			GlobalData.weapons.weapon_loadout[key] = LoadoutSystem.migrate_ref_to_uid(GlobalData.weapons.weapon_loadout.get(key, ""))
		var migrated_carry: Array = []
		var carry = GlobalData.weapons.weapon_loadout.get("carry", [])
		if carry is Array:
			for ref in carry:
				migrated_carry.append(LoadoutSystem.migrate_ref_to_uid(ref))
			GlobalData.weapons.weapon_loadout["carry"] = migrated_carry
	GlobalData.migrate_legacy_attachments()


static func serialize_parts() -> Dictionary:
	var result := {}
	for slot in GlobalData.weapons.equipped_parts:
		var item = GlobalData.weapons.equipped_parts[slot]
		if item == null:
			result[slot] = null
		elif item is Dictionary and item.has("uid"):
			# Owned instance: persist the uid reference and db_id for robust catalog recovery
			result[slot] = {
				"uid": item["uid"],
				"db_id": item.get("db_id", item.get("id", "")),
				"equipped": item.get("equipped", true)
			}
		elif item is Resource and "resource_path" in item and item.resource_path != "":
			# Resource file: save path string for reload
			result[slot] = item.resource_path
		elif item is Dictionary:
			var pid = item.get("id", item.get("db_id", ""))
			if pid != "" and ArmorSystem.is_catalog_armor_id(pid):
				# Legacy catalog part: persist only the id reference + equipped state.
				# Static stats always come from the catalog (single source of truth).
				result[slot] = {"id": pid, "db_id": pid, "equipped": item.get("equipped", true)}
			else:
				# Legacy instance part (non-catalog): persist the full dict.
				result[slot] = item.duplicate(true)
		else:
			result[slot] = str(item)
	return result


static func serialize_armor_inventory() -> Array:
	var result: Array = []
	for inst in GlobalData.weapons.armor_inventory:
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
	# Ensure name exists if db_id is present
	var db_id = str(inst.get("db_id", inst.get("id", "")))
	if not inst.has("name") and db_id != "" and ArmorSystem.is_catalog_armor_id(db_id):
		var cat = ArmorSystem.get_armor_catalog_entry(db_id)
		if not cat.is_empty():
			for k in cat:
				if not inst.has(k):
					inst[k] = cat[k]
	return inst


static func serialize_frames() -> Dictionary:
	var result := {}
	for slot in GlobalData.weapons.equipped_frames:
		var f = GlobalData.weapons.equipped_frames[slot]
		if f is Dictionary and f.get("id", "") != "" and ArmorSystem.is_catalog_frame_id(f["id"]):
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
			entry = ArmorSystem.get_frame_catalog_entry(fid)
		if entry.is_empty():
			entry = ArmorSystem.get_frame_catalog_entry_by_name(v.get("name", ""))
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
		var pid = v.get("id", v.get("db_id", ""))
		var entry: Dictionary = {}
		if pid != "":
			entry = ArmorSystem.get_armor_catalog_entry(pid)
		if not entry.is_empty():
			var resolved = entry.duplicate()
			resolved["equipped"] = v.get("equipped", true)
			if v.has("uid"):
				resolved["uid"] = v["uid"]
			return resolved
		return v.duplicate(true)
	return v


# Resolves a saved equipped-part value. Owned instances resolve to the instance
# stored in armor_inventory (shared reference); everything else falls back to the
# legacy resolver.
static func resolve_equipped_part(v: Variant) -> Variant:
	if v is Dictionary and v.has("uid"):
		var inst := ArmorSystem.get_armor_instance(str(v["uid"]))
		if not inst.is_empty() and inst.has("name"):
			inst["equipped"] = v.get("equipped", true)
			return inst
		# If instance was missing from armor_inventory, recover from catalog via db_id/id
		var pid = str(v.get("db_id", v.get("id", "")))
		if pid != "" and ArmorSystem.is_catalog_armor_id(pid):
			var recovered := ArmorSystem.make_armor_instance_from_catalog(pid)
			if not recovered.is_empty():
				recovered["uid"] = str(v["uid"])
				recovered["equipped"] = v.get("equipped", true)
				return recovered
	return resolve_armor_value(v)


# Migrates any legacy or hollow equipped part into a proper instance so the whole
# loadout is instance-based with real names and stats after loading old saves.
static func ensure_equipped_parts_are_instances() -> void:
	for slot in GlobalData.MECHA_SLOTS:
		var part = GlobalData.weapons.equipped_parts.get(slot)
		if part is Resource:
			continue
		var is_valid_instance := false
		if part is Dictionary and part.has("uid") and part.has("name") and (part.has("hp") or part.has("max_hp")):
			is_valid_instance = true
			if ArmorSystem.get_armor_instance(str(part["uid"])).is_empty():
				GlobalData.weapons.armor_inventory.append(part)

		if not is_valid_instance:
			var pid = part.get("id", part.get("db_id", "")) if part is Dictionary else ""
			var inst: Dictionary = {}
			if pid != "" and ArmorSystem.is_catalog_armor_id(pid):
				inst = ArmorSystem.make_armor_instance_from_catalog(pid)
			else:
				if GlobalData.armor_catalog.has(slot) and GlobalData.armor_catalog[slot].size() > 0:
					var def_pid = str(GlobalData.armor_catalog[slot][0].get("id", ""))
					if def_pid != "":
						inst = ArmorSystem.make_armor_instance_from_catalog(def_pid)
			if not inst.is_empty():
				ArmorSystem.equip_armor_instance(inst["uid"], slot)


static func serialize_attachments() -> Array:
	var result: Array = []
	for attachment in GlobalData.weapons.attachments:
		var copy: Dictionary = attachment.duplicate(true)
		for key in ["position", "rotation", "scale", "size"]:
			if copy.get(key) is Vector3:
				var value: Vector3 = copy[key]
				copy[key] = {"x": value.x, "y": value.y, "z": value.z}
		result.append(copy)
	return result


# Patrol fleets carry their positions as Vector2i, which JSON.stringify() would
# flatten into a String like "(3, 7)" (losing the int pair). Serialize as plain
# {x, y} dicts so loading round-trips them back to Vector2i cleanly.
# Also converts nested Colors inside pilots[].mech_loadout (armor color) to {r,g,b,a}.
static func _serialize_patrols() -> Array:
	var result: Array = []
	for p in GlobalData.board.board_patrols:
		if not (p is Dictionary):
			continue
		var copy: Dictionary = p.duplicate(true)
		if copy.get("pos") is Vector2i:
			var pos: Vector2i = copy["pos"]
			copy["pos"] = {"x": pos.x, "y": pos.y}
		if copy.get("home") is Vector2i:
			var home: Vector2i = copy["home"]
			copy["home"] = {"x": home.x, "y": home.y}
		if copy.get("prev_pos") is Vector2i:
			var prev_pos: Vector2i = copy["prev_pos"]
			copy["prev_pos"] = {"x": prev_pos.x, "y": prev_pos.y}
		if copy.get("dir") is Vector2i:
			var dir: Vector2i = copy["dir"]
			copy["dir"] = {"x": dir.x, "y": dir.y}
		# Deep-convert Colors inside pilots[].mech_loadout
		if copy.get("pilots") is Array:
			for pilot in copy["pilots"]:
				if not (pilot is Dictionary):
					continue
				var loadout = pilot.get("mech_loadout", null)
				if loadout is Dictionary:
					for slot in loadout:
						var entry = loadout[slot]
						if entry is Dictionary:
							for sub in ["frame", "armor"]:
								var part = entry.get(sub, null)
								if part is Dictionary and part.get("color") is Color:
									var c: Color = part["color"]
									part["color"] = {"r": c.r, "g": c.g, "b": c.b, "a": c.a}
				# faction_paint inside pilot if present
				if pilot.get("faction_paint") is Dictionary:
					var fp: Dictionary = pilot["faction_paint"]
					for k in fp.keys():
						if fp[k] is Color:
							var c: Color = fp[k]
							fp[k] = {"r": c.r, "g": c.g, "b": c.b, "a": c.a}
		# Top-level commander color
		if copy.get("commander") is Dictionary:
			var cmd: Dictionary = copy["commander"]
			if cmd.get("mech_loadout") is Dictionary:
				for slot in cmd["mech_loadout"]:
					var entry2 = cmd["mech_loadout"][slot]
					if entry2 is Dictionary:
						for sub in ["frame", "armor"]:
							var part2 = entry2.get(sub, null)
							if part2 is Dictionary and part2.get("color") is Color:
								var c2: Color = part2["color"]
								part2["color"] = {"r": c2.r, "g": c2.g, "b": c2.b, "a": c2.a}
		result.append(copy)
	return result


static func _serialize_hit_meta() -> Dictionary:
	var out := {}
	for slot in GlobalData.weapons.part_hit_meta:
		var v = GlobalData.weapons.part_hit_meta[slot]
		if v is Dictionary and v.get("pos") is Vector3:
			var p: Vector3 = v["pos"]
			out[slot] = {"pos": {"x": p.x, "y": p.y, "z": p.z}, "radius": float(v.get("radius", 0.0)), "layer": str(v.get("layer", "armor"))}
	return out


static func _deserialize_hit_meta(raw: Dictionary) -> Dictionary:
	var out := {}
	for slot in raw:
		var entry = raw[slot]
		if entry is Dictionary:
			var pos_d = entry.get("pos", {})
			var pos := Vector3.ZERO
			if pos_d is Dictionary:
				pos = Vector3(float(pos_d.get("x", 0.0)), float(pos_d.get("y", 0.0)), float(pos_d.get("z", 0.0)))
			elif pos_d is Vector3:
				pos = pos_d
			out[slot] = {"pos": pos, "radius": float(entry.get("radius", 0.7)), "layer": str(entry.get("layer", "armor"))}
	return out


# Parses a Vector2i stored as a String (JSON-flattened Vector2i or "(x, y)").
static func _parse_vec2i(raw: String, fallback: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	var clean := raw.replace("(", "").replace(")", "").replace("Vector2i", "").strip_edges()
	var parts := clean.split(",")
	if parts.size() >= 2:
		return Vector2i(int(parts[0]), int(parts[1]))
	return fallback


# Builds the per-slot frame + armor loadout dict for a HANGAR MECH SNAPSHOT,
# resolving each stored ref into a full entry the PartMeshManager can render
# (same catalog path the hangar garage, ally bodies, enemy bodies and reserve
# mechs use). `loadout` maps slot name to {"frame": {...}, "armor": {...}}.
# This is the single source for dressing a mech body from a berth snapshot —
# previously duplicated in ally_dummy.gd and backup_mech_spawner.gd.
static func build_mech_catalog_loadout(mech: Dictionary, fallback_color: Color = Color(0.4, 0.6, 0.9)) -> Dictionary:
	var loadout: Dictionary = {}
	var mech_frames: Dictionary = mech.get("frames", {})
	var mech_parts: Dictionary = mech.get("parts", {})
	for slot in GlobalData.MECHA_SLOTS:
		var frame_entry: Dictionary = {}
		if mech_frames.has(slot):
			var f = resolve_frame_value(mech_frames[slot])
			if f is Dictionary:
				frame_entry = (f as Dictionary).duplicate(true)
		var armor_entry: Dictionary = {}
		if mech_parts.has(slot):
			var p = resolve_equipped_part(mech_parts[slot])
			if p != null:
				if p is Dictionary:
					armor_entry["name"] = str(p.get("name", p.get("part_name", "Armor")))
					armor_entry["hp"] = float(GlobalData.part_stat(p, "max_hp", 100.0))
					armor_entry["color"] = _resolve_armor_paint(p, fallback_color)
					# Carry the part identity so the visual builder can resolve the
					# authored model for this exact part id.
					armor_entry["id"] = str(p.get("db_id", p.get("id", "")))
					armor_entry["path"] = str(p.get("path", ""))
					if p.has("defense_type"):
						armor_entry["defense_type"] = p["defense_type"]
					if p.has("resistance") and p["resistance"] is Dictionary:
						armor_entry["resistance"] = (p["resistance"] as Dictionary).duplicate(true)
				elif p is ArmorPart:
					armor_entry["name"] = (p as ArmorPart).part_name
					armor_entry["hp"] = (p as ArmorPart).max_hp
					armor_entry["color"] = (p as ArmorPart).part_color
					armor_entry["path"] = (p as ArmorPart).resource_path
					armor_entry["defense_type"] = (p as ArmorPart).defense_type
					if not (p as ArmorPart).resistance.is_empty():
						armor_entry["resistance"] = (p as ArmorPart).resistance.duplicate(true)
				armor_entry["equipped"] = true
		loadout[slot] = {"frame": frame_entry, "armor": armor_entry}
	return loadout


# The paint color of a resolved armor instance: the instance's own color (what
# the player chose in the hangar), then its catalog entry, falling back to the
# caller's fallback (friendly blue for allies / generic steel otherwise).
static func _resolve_armor_paint(p: Dictionary, fallback: Color) -> Color:
	if p.has("color") and p["color"] is Color:
		return p["color"]
	if p.has("part_color") and p["part_color"] is Color:
		return p["part_color"]
	var db_id := str(p.get("db_id", ""))
	if db_id != "":
		var cat_entry := ArmorSystem.get_armor_catalog_entry(db_id)
		if not cat_entry.is_empty() and cat_entry.has("color"):
			return cat_entry["color"]
	return fallback


static func _serialize_tile_wreckages() -> Dictionary:
	var raw: Dictionary = ScavengerSystem.get_tile_wreckages()
	var out: Dictionary = {}
	for key in raw:
		var w_entry = raw[key]
		if not (w_entry is Dictionary):
			continue
		var s_items: Array = []
		for item in w_entry.get("items", []):
			if item is Dictionary:
				var it_copy: Dictionary = item.duplicate(true)
				if it_copy.get("weapon") is Resource:
					var res: Resource = it_copy["weapon"]
					it_copy["weapon_path"] = res.resource_path
					it_copy["weapon_name"] = res.get("weapon_name") if "weapon_name" in res else ""
					it_copy.erase("weapon")
				s_items.append(it_copy)
		out[key] = {
			"pos_x": int(w_entry.get("pos_x", 0)),
			"pos_y": int(w_entry.get("pos_y", 0)),
			"scrap": int(w_entry.get("scrap", 0)),
			"items": s_items
		}
	return out


static func _deserialize_tile_wreckages(data: Variant) -> void:
	if not (data is Dictionary):
		ScavengerSystem.set_tile_wreckages({})
		return
	var out: Dictionary = {}
	for key in data:
		var entry = data[key]
		if not (entry is Dictionary):
			continue
		var items: Array = []
		for item in entry.get("items", []):
			if item is Dictionary:
				var it: Dictionary = item.duplicate(true)
				if it.has("weapon_path") and not str(it["weapon_path"]).is_empty():
					var path: String = str(it["weapon_path"])
					if ResourceLoader.exists(path):
						it["weapon"] = load(path)
				items.append(it)
		out[key] = {
			"pos_x": int(entry.get("pos_x", 0)),
			"pos_y": int(entry.get("pos_y", 0)),
			"scrap": int(entry.get("scrap", 0)),
			"items": items
		}
	ScavengerSystem.set_tile_wreckages(out)
