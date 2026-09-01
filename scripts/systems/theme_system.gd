class_name ThemeSystem
extends RefCounted

# -----------------------------------------------------------------------------
# RUN THEME + EVENTS
# The identity of the current run (see run_theme_catalogs.tres) and the event
# system that drives board encounters. Extracted from GlobalData so the run-
# state autoload stays focused on state; GlobalData keeps thin facades.
#
# - theme_id:       which story this run is (soldier / valkyrion_merc / scavenger).
# - reputation:     accrued deeds that gate high-tier choice events.
# - theme_switched: allows a theme_switch event to fire at most once per run.
# - ceasefire_turns: board moves left with no combat (political ceasefire).
# - blocked_intermission: set when a force_combat event denies the intermission
#   between battles.
# -----------------------------------------------------------------------------


static func get_run_theme() -> Dictionary:
	for theme in GlobalData.run_themes:
		if theme.get("id", "") == GlobalData.narrative.theme_id:
			return theme
	return {}


static func get_theme_event_pool() -> Array:
	var theme = get_run_theme()
	var forced: Array = theme.get("events", [])
	var result: Array = []
	for event in GlobalData.run_events:
		if not (event is Dictionary):
			continue
		# Pilot-only recovery events only appear on mech-less board tiles.
		if event.get("recovery_only", false):
			continue
		var themes = event.get("themes", [])
		if themes is Array and not themes.is_empty() and not (GlobalData.narrative.theme_id in themes):
			continue
		if int(event.get("min_reputation", 0)) > GlobalData.narrative.reputation:
			continue
		if str(event.get("id", "")) in forced:
			continue
		result.append(event)
	for event_id in forced:
		var event = get_run_event(event_id)
		if event.is_empty():
			continue
		# Theme-forced events still respect the reputation gate.
		if int(event.get("min_reputation", 0)) > GlobalData.narrative.reputation:
			continue
		result.append(event)
	return result


# Board events aimed at restoring a mech to a pilot-only convoy. Only these are
# offered when the player is on foot (mech_less).
static func get_recovery_event_pool() -> Array:
	var result: Array = []
	for event in GlobalData.run_events:
		if not (event is Dictionary):
			continue
		var params: Dictionary = event.get("params", {})
		if not params.get("recovery", false):
			continue
		var themes = event.get("themes", [])
		if themes is Array and not themes.is_empty() and not (GlobalData.narrative.theme_id in themes):
			continue
		if int(event.get("min_reputation", 0)) > GlobalData.narrative.reputation:
			continue
		result.append(event)
	return result


static func get_weighted_recovery_event() -> Dictionary:
	var pool := get_recovery_event_pool()
	if pool.is_empty():
		return {}
	var total := 0
	for event in pool:
		total += maxi(1, int(event.get("weight", 1)))
	var roll := randi() % total
	for event in pool:
		roll -= maxi(1, int(event.get("weight", 1)))
		if roll < 0:
			return event
	return pool[0]


# Transport / affiliation flavor for the current theme (used by the intermission
# and hangar to describe what happens when the convoy is on foot).
static func get_affiliation() -> Dictionary:
	var theme = get_run_theme()
	return theme.get("affiliation", {})


static func get_run_event(event_id: String) -> Dictionary:
	for event in GlobalData.run_events:
		if event.get("id", "") == event_id:
			return event
	return {}


static func get_theme_ending() -> Dictionary:
	var theme = get_run_theme()
	return theme.get("ending", {})


# Adds a run theme to the current run (used by theme_switch events).
static func switch_theme(new_theme_id: String) -> bool:
	if not GlobalData.narrative.theme_switched:
		GlobalData.narrative.theme_id = new_theme_id
		GlobalData.narrative.theme_switched = true
		return true
	return false


# Adjusts run reputation and clamps it to a sane range.
static func add_reputation(amount: int) -> void:
	GlobalData.narrative.reputation = clampi(GlobalData.narrative.reputation + amount, -20, 100)


# Applies a board event's effect immediately. Returns true when the event forced
# a scene transition (e.g. force_combat) — the caller should stop afterwards.
static func apply_event_effect(event: Dictionary) -> bool:
	var effect := str(event.get("effect", ""))
	var amount := int(event.get("amount", 0))
	var params: Dictionary = event.get("params", {})

	match effect:
		"credits":
			GlobalData.currency.credits += amount
			_apply_repair_params(params)
		"scrap":
			GlobalData.currency.scrap += amount
			_apply_repair_params(params)
		"repair":
			_apply_repair_params({"repair": amount if amount != 0 else float(params.get("repair", 0))})
		"recover_mech":
			_apply_recover_mech(params)
		"wanderer_join":
			_apply_wanderer_join(params)
		"recover_escort":
			_apply_recover_escort(params)
		"none":
			pass
		"data_cores":
			GlobalData.currency.data_cores += amount
		"damage":
			if not GlobalData.weapons.equipped_parts.is_empty():
				var keys = GlobalData.weapons.equipped_parts.keys()
				var rand_part = keys[randi() % keys.size()]
				var cur_dmg = GlobalData.weapons.part_damage.get(rand_part, 0.0)
				GlobalData.weapons.part_damage[rand_part] = minf(cur_dmg + float(amount) / 100.0, 1.0)
		"reputation":
			add_reputation(amount)
		"supply_drop":
			GlobalData.currency.credits += amount
			GlobalData.currency.scrap += int(params.get("scrap", 0))
		"ceasefire":
			GlobalData.narrative.ceasefire_turns = maxi(GlobalData.narrative.ceasefire_turns, int(params.get("turns", amount)))
		"add_ally":
			FleetSystem.add_ally_unit(str(params.get("unit_id", "")))
		"recruit_ally":
			# A named pilot joins the convoy (no combat). Resolved by RecruitSystem.
			RecruitSystem.recruit(str(params.get("character_id", "")))
		"patrol_recruit":
			# An unknown fleet's pilot joins the convoy AND the fleet itself stands
			# down, so its arrow marker is removed from the board. A fleet taken
			# off the map counts as neutralized for the patrol_hunt objective —
			# otherwise recruiting could soft-lock the sector.
			var cid := str(params.get("character_id", ""))
			if RecruitSystem.is_character_available(cid):
				RecruitSystem.recruit(cid)
				PatrolSystem.remove_patrol(GlobalData.board.board_patrol_engagement)
				if BoardSystem.get_objective().get("id", "") == "patrol_hunt":
					BoardSystem.add_progress(1)
			GlobalData.board.board_patrol_engagement = -1
		"duel":
			# The player challenged a pilot: record the 1v1 duel and force the
			# scene transition into the "duel" combat node.
			if RecruitSystem.start_duel(str(params.get("character_id", "")), str(params.get("intent", "test"))):
				return true
			return false
		"heat_bonus":
			GlobalData.board.heat = maxi(0, GlobalData.board.heat + int(params.get("heat", amount)))
		"theme_switch":
			return switch_theme(str(params.get("theme_id", "")))
		"force_combat":
			GlobalData.narrative.blocked_intermission = true
			return true
		"dead_end_clear":
			# The player pays MP up front to demolish a dead end's rubble; the
			# board manager opens the path and advances the day when the popup
			# closes (the work eats the rest of the day).
			GlobalData.board.board_mp = maxi(GlobalData.board.board_mp - amount, 0)
			var clear_pos: Dictionary = params.get("pos", {})
			GlobalData.board.pending_tile_clear = Vector2i(int(clear_pos.get("x", -1)), int(clear_pos.get("y", -1)))
		"choice":
			# Choices are resolved by the event UI; nothing to apply here.
			pass
		"reignition":
			# Pilot Siphon Protocol: reboot the mech using siphoned fuel.
			var bm = Engine.get_main_loop().current_scene if Engine.get_main_loop() else null
			if bm and bm.has_method("_do_reignition"):
				bm._do_reignition()
		"siphon_more":
			# Pilot Siphon Protocol: siphon more fuel from wreckage.
			var bm = Engine.get_main_loop().current_scene if Engine.get_main_loop() else null
			if bm and bm.has_method("_trigger_wreckage_siphon"):
				bm._trigger_wreckage_siphon()
		"add_fuel":
			# Generic fuel reward from events — adds a container of the specified type.
			var ftype: int = int(params.get("fuel_type", 0))  # 0 = FuelType.CRUDE_OIL
			var famt: float = float(params.get("amount", float(amount)))
			var target: String = str(params.get("target", "mech"))
			var fuel_names := {0: "Crude Oil", 1: "Refined Cell", 2: "Bio-Fuel"}
			if target == "convoy":
				var gained = GlobalData.fuel.add_convoy_fuel(ftype, famt)
				var type_name: String = "Fuel"
				if fuel_names.has(ftype):
					type_name = str(fuel_names[ftype])
				GlobalData.board.run_notice = "Added %.0f %s to Convoy inventory." % [gained, type_name]
			else:
				var gained = GlobalData.fuel.add_mech_fuel(ftype, famt)
				var type_name: String = "Fuel"
				if fuel_names.has(ftype):
					type_name = str(fuel_names[ftype])
				GlobalData.board.run_notice = "Added %.0f %s to Mech inventory." % [gained, type_name]
		"refine_fuel":
			# Convoy Refinery (GDD §4.2): convert Crude Oil → Refined Cell at camp.
			var crude_to_refine: float = float(params.get("amount", float(amount)))
			var result := GlobalData.fuel.refine_crude_to_refined(crude_to_refine)
			var rc := 0.0
			var rp := 0.0
			if result.has("crude_consumed"):
				rc = float(result["crude_consumed"])
			if result.has("refined_produced"):
				rp = float(result["refined_produced"])
			if rp > 0.0:
				GlobalData.board.run_notice = "Refinery ran: consumed %.0f Crude → produced %.0f Refined Cell." % [rc, rp]
			else:
				GlobalData.board.run_notice = "Refinery idle — not enough Crude Oil to refine (need %d minimum)." % int(GlobalData.fuel.REFINERY_MIN_BATCH)
		"depot_precise":
			# Fuel depot: precise approach — full fuel reward after combat.
			GlobalData.fuel.fuel_depot_approach = "precise"
			var bm = Engine.get_main_loop().current_scene if Engine.get_main_loop() else null
			if bm and bm.has_method("_request_combat"):
				bm._request_combat("fuel_depot")
		"depot_heavy":
			# Fuel depot: heavy approach — reduced fuel reward after combat.
			GlobalData.fuel.fuel_depot_approach = "heavy"
			var bm = Engine.get_main_loop().current_scene if Engine.get_main_loop() else null
			if bm and bm.has_method("_request_combat"):
				bm._request_combat("fuel_depot")
		"distress_help":
			# Distress Signal: player chose to respond. Costs energy, may gain reward.
			var cost := int(params.get("energy_cost", 30))
			GlobalData.fuel.mech_energy = maxf(GlobalData.fuel.mech_energy - float(cost), 0.0)
			# Roll for reward: 60% chance of scrap/credits/fuel, 40% nothing useful.
			var roll := randf()
			if roll < 0.30:
				var scrap_gain := randi_range(15, 30)
				GlobalData.currency.scrap += scrap_gain
				GlobalData.board.run_notice = "Responded to distress signal. Spent %d energy. Salvaged %d scrap." % [cost, scrap_gain]
			elif roll < 0.48:
				var cred_gain := randi_range(40, 80)
				GlobalData.currency.credits += cred_gain
				GlobalData.board.run_notice = "Responded to distress signal. Spent %d energy. Found %d credits." % [cost, cred_gain]
			elif roll < 0.58:
				GlobalData.currency.data_cores += 1
				GlobalData.board.run_notice = "Responded to distress signal. Spent %d energy. Recovered 1 data core." % cost
			elif roll < 0.70:
				# GDD §4.2: distress yield Refined Cell (type 1) — rare but valuable
				var refined_amount := randf_range(10.0, 30.0)
				var gained := GlobalData.fuel.add_mech_fuel(1, refined_amount)
				GlobalData.board.run_notice = "Responded to distress signal. Spent %d energy. Found Refined Energy Cell (+%.0f)." % [cost, gained]
			else:
				GlobalData.board.run_notice = "Responded to distress signal. Spent %d energy. Nothing useful found." % cost
		"distress_ignore":
			# Distress Signal: player chose to ignore. Safe, no reward.
			GlobalData.board.run_notice = "Ignored the distress signal. The convoy presses on."
		"scavenge_explore":
			# Scavenge Risk: pilot explores wreckage on foot.
			# Roll: 50% success (find loot), 30% drone ambush, 20% nothing.
			var roll := randf()
			if roll < 0.50:
				# Success: find resources.
				var loot_roll := randf()
				if loot_roll < 0.30:
					var scrap_gain := randi_range(20, 40)
					GlobalData.currency.scrap += scrap_gain
					GlobalData.board.run_notice = "Scavenged the wreckage successfully! Found %d scrap." % scrap_gain
				elif loot_roll < 0.50:
					GlobalData.currency.credits += 50
					GlobalData.board.run_notice = "Scavenged the wreckage successfully! Found 50 credits."
				elif loot_roll < 0.65:
					# Discover pilot firearm / military assault rifle cache
					var pilot_wpn := "res://resources/mech/stock/weapon_pilot_assault_rifle.tres"
					if not GlobalData.pilot.pilot_weapons.has(pilot_wpn):
						PilotSystem.add_weapon(pilot_wpn)
						PilotSystem.add_ammo("kinetic", 90)
						GlobalData.board.run_notice = "Scavenged military arms crate! Acquired [color=#44ff88]Pilot Assault Rifle[/color] + 90 Ammo!"
					else:
						PilotSystem.add_ammo("kinetic", 120)
						GlobalData.currency.data_cores += 1
						GlobalData.board.run_notice = "Scavenged ammo supply cache! +120 Pilot Ammo & 1 Data Core."
				else:
					# GDD §4.2: wreckage yields Crude Oil (type 0)
					var crude_amount := randf_range(15.0, 35.0)
					var gained := GlobalData.fuel.add_mech_fuel(0, crude_amount)
					GlobalData.board.run_notice = "Scavenged the wreckage! Extracted %.0f Crude Oil from the tank." % gained
			elif roll < 0.80:
				# Drone ambush: force combat.
				GlobalData.board.run_notice = "Scavenging triggered a drone ambush! Defend yourself!"
				GlobalData.narrative.blocked_intermission = true
				return true
			else:
				# Nothing found.
				GlobalData.board.run_notice = "Searched the wreckage but found nothing useful."
		"scavenge_leave":
			# Scavenge Risk: player chose to leave. Safe.
			GlobalData.board.run_notice = "Left the wreckage alone. Not worth the risk."
		"investigate_signal":
			# Mystery Transmission: scan beacon.
			# 50% reward: scrap/fuel/credits; 50% decoy ambush trap (3-wave breakdown defense).
			var roll := randf()
			if roll < 0.50:
				var loot_roll := randf()
				if loot_roll < 0.40:
					var scrap_gain := randi_range(60, 140)
					GlobalData.currency.scrap += scrap_gain
					GlobalData.board.run_notice = "Signal cracked! Salvaged a military cache with %d scrap." % scrap_gain
				elif loot_roll < 0.70:
						var gained := GlobalData.fuel.add_mech_fuel(0, 40.0)  # FuelType.CRUDE_OIL = 0
						GlobalData.board.run_notice = "Found an intact fuel cell container! Recharged +%.0f energy." % gained
				else:
					GlobalData.currency.credits += 120
					GlobalData.currency.data_cores += 1
					GlobalData.board.run_notice = "Recovered an encrypted black box (+120 credits, +1 Data Core)."
			else:
				# Decoy beacon trap: 3-wave defense!
				GlobalData.board.convoy_defense_waves = 3
				GlobalData.board.convoy_defense_current_wave = 0
				GlobalData.board.convoy_defense_active = true
				GlobalData.board.run_notice = "IT'S A TRAP! The beacon was an enemy decoy — defend the supply truck!"
				GlobalData.narrative.blocked_intermission = true
				return true
		"ignore_signal":
			GlobalData.board.run_notice = "Ignored the mystery signal. The convoy presses forward."
		"refuel_mecha_only":
			# GDD §3.3: Refuel mecha only — add fuel directly to mech containers.
			var ftype: int = int(params.get("fuel_type", 0))
			var famt: float = float(params.get("amount", float(amount)))
			var gained := GlobalData.fuel.add_mech_fuel(ftype, famt)
			GlobalData.board.run_notice = "Refueled mech directly: +%.0f fuel. The convoy stays parked." % gained
		"haul_fuel_back":
			# GDD §3.3: Haul fuel back — add to mech, then transfer to convoy.
			var ftype: int = int(params.get("fuel_type", 0))
			var famt: float = float(params.get("amount", float(amount)))
			var gained := GlobalData.fuel.add_mech_fuel(ftype, famt)
			# Transfer mech fuel to convoy
			var transfer: float = minf(gained, GlobalData.fuel.convoy_max_fuel - GlobalData.fuel.convoy_fuel)
			if transfer > 0.0:
				GlobalData.fuel.mech_energy = maxf(GlobalData.fuel.mech_energy - transfer, 0.0)
				GlobalData.fuel.convoy_fuel = minf(GlobalData.fuel.convoy_fuel + transfer, GlobalData.fuel.convoy_max_fuel)
			# Time trade-off: hauling costs a full day turn + raises alert.
			HeatWantedSystem.modify_heat(1)
			GlobalData.board.run_notice = "Hauled %.0f fuel back to the convoy. A full day passed and alert rose." % transfer
			var bm = Engine.get_main_loop().current_scene if Engine.get_main_loop() else null
			if bm and bm.has_method("_end_day"):
				bm._end_day()
		_:
			push_warning("apply_event_effect: unknown effect '%s'" % effect)
	return false


# Called when a battle ends: applies reputation from the outcome.
static func on_combat_ended_for_reputation(victory: bool) -> void:
	if victory:
		add_reputation(1)
		if GameManager.is_boss_combat:
			add_reputation(2)


# Repairs `repair` percentage points of damage across every damaged part.
static func _apply_repair_params(params: Dictionary) -> void:
	var repair := float(params.get("repair", 0))
	if repair <= 0.0:
		return
	for key in GlobalData.weapons.part_damage:
		var cur := float(GlobalData.weapons.part_damage[key])
		GlobalData.weapons.part_damage[key] = maxf(cur - repair / 100.0, 0.0)


# Rebuilds a walking chassis from convoy spares and ends pilot-only mode. If no
# berth is available the convoy strips the garage for scrap instead.
static func _apply_recover_mech(params: Dictionary) -> void:
	var granted := HangarManager.grant_recovery_mech()
	if granted.is_empty():
		var fallback := int(params.get("fallback_scrap", 30))
		GlobalData.currency.scrap += fallback
		GlobalData.board.run_notice = "The garage holds no usable chassis — your team strips it for %d scrap instead." % fallback
		return
	var heat := int(params.get("heat", 1))
	GlobalData.board.heat = maxi(0, GlobalData.board.heat + heat)
	GlobalData.board.run_notice = "Your mechanics rebuild a walking chassis from the convoy spares: %s is ready for combat." % str(granted.get("name", "Mech"))


# A lone wanderer brings a spare chassis (ending pilot-only mode) and, when room
# allows, rides along as an escort. Used when the sector exit is reached on foot.
static func _apply_wanderer_join(_params: Dictionary) -> void:
	var granted := HangarManager.grant_recovery_mech()
	var escort := false
	for template_id in ["ally_gm", "ally_gunner", "ally_blade"]:
		if FleetSystem.add_ally_unit(template_id):
			escort = true
			break
	if granted.is_empty():
		GlobalData.board.run_notice = "A lone wanderer offers an escort out of the sector — the convoy rides together."
	elif escort:
		GlobalData.board.run_notice = "A lone wanderer joins the convoy, piloting a spare chassis and riding along as an escort."
	else:
		GlobalData.board.run_notice = "A lone wanderer joins the convoy, piloting a spare chassis."


# A local crew offers to ride along: the first ally template the fleet does not
# already own joins the roster. Grants reputation either way.
static func _apply_recover_escort(_params: Dictionary) -> void:
	var joined := false
	for template_id in ["ally_gm", "ally_gunner", "ally_blade"]:
		if FleetSystem.add_ally_unit(template_id):
			joined = true
			break
	if joined:
		add_reputation(1)
		GlobalData.board.run_notice = "A local salvage crew rides along with the convoy. +1 reputation."
	else:
		GlobalData.board.run_notice = "The locals are already part of the convoy — they wish you luck."
