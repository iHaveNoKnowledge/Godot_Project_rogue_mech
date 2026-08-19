class_name ThemeSystem
extends RefCounted

# -----------------------------------------------------------------------------
# RUN THEME + EVENTS
# The identity of the current run (see run_theme_catalogs.tres) and the event
# system that drives board encounters. Extracted from GlobalData so the run-
# state autoload stays focused on state; GlobalData keeps thin facades.
#
# - theme_id:       which story this run is (soldier / gundam_merc / scavenger).
# - reputation:     accrued deeds that gate high-tier choice events.
# - theme_switched: allows a theme_switch event to fire at most once per run.
# - ceasefire_turns: board moves left with no combat (political ceasefire).
# - blocked_intermission: set when a force_combat event denies the intermission
#   between battles.
# -----------------------------------------------------------------------------


static func get_run_theme() -> Dictionary:
	for theme in GlobalData.run_themes:
		if theme.get("id", "") == GlobalData.theme_id:
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
		if themes is Array and not themes.is_empty() and not (GlobalData.theme_id in themes):
			continue
		if int(event.get("min_reputation", 0)) > GlobalData.reputation:
			continue
		if str(event.get("id", "")) in forced:
			continue
		result.append(event)
	for event_id in forced:
		var event = get_run_event(event_id)
		if event.is_empty():
			continue
		# Theme-forced events still respect the reputation gate.
		if int(event.get("min_reputation", 0)) > GlobalData.reputation:
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
		if themes is Array and not themes.is_empty() and not (GlobalData.theme_id in themes):
			continue
		if int(event.get("min_reputation", 0)) > GlobalData.reputation:
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
	if not GlobalData.theme_switched:
		GlobalData.theme_id = new_theme_id
		GlobalData.theme_switched = true
		return true
	return false


# Adjusts run reputation and clamps it to a sane range.
static func add_reputation(amount: int) -> void:
	GlobalData.reputation = clampi(GlobalData.reputation + amount, -20, 100)


# Applies a board event's effect immediately. Returns true when the event forced
# a scene transition (e.g. force_combat) — the caller should stop afterwards.
static func apply_event_effect(event: Dictionary) -> bool:
	var effect := str(event.get("effect", ""))
	var amount := int(event.get("amount", 0))
	var params: Dictionary = event.get("params", {})

	match effect:
		"credits":
			GlobalData.credits += amount
			_apply_repair_params(params)
		"scrap":
			GlobalData.scrap += amount
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
			GlobalData.data_cores += amount
		"damage":
			if not GlobalData.equipped_parts.is_empty():
				var keys = GlobalData.equipped_parts.keys()
				var rand_part = keys[randi() % keys.size()]
				var cur_dmg = GlobalData.part_damage.get(rand_part, 0.0)
				GlobalData.part_damage[rand_part] = minf(cur_dmg + float(amount) / 100.0, 1.0)
		"reputation":
			add_reputation(amount)
		"supply_drop":
			GlobalData.credits += amount
			GlobalData.scrap += int(params.get("scrap", 0))
		"ceasefire":
			GlobalData.ceasefire_turns = maxi(GlobalData.ceasefire_turns, int(params.get("turns", amount)))
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
				PatrolSystem.remove_patrol(GlobalData.board_patrol_engagement)
				if BoardSystem.get_objective().get("id", "") == "patrol_hunt":
					BoardSystem.add_progress(1)
			GlobalData.board_patrol_engagement = -1
		"duel":
			# The player challenged a pilot: record the 1v1 duel and force the
			# scene transition into the "duel" combat node.
			if RecruitSystem.start_duel(str(params.get("character_id", "")), str(params.get("intent", "test"))):
				return true
			return false
		"heat_bonus":
			GlobalData.heat = maxi(0, GlobalData.heat + int(params.get("heat", amount)))
		"theme_switch":
			return switch_theme(str(params.get("theme_id", "")))
		"force_combat":
			GlobalData.blocked_intermission = true
			return true
		"dead_end_clear":
			# The player pays MP up front to demolish a dead end's rubble; the
			# board manager opens the path and advances the day when the popup
			# closes (the work eats the rest of the day).
			GlobalData.board_mp = maxi(GlobalData.board_mp - amount, 0)
			var clear_pos: Dictionary = params.get("pos", {})
			GlobalData.pending_tile_clear = Vector2i(int(clear_pos.get("x", -1)), int(clear_pos.get("y", -1)))
		"choice":
			# Choices are resolved by the event UI; nothing to apply here.
			pass
		"reignition":
			# Pilot Siphon Protocol: reboot the mech using siphoned fuel.
			BoardManager._do_reignition()
		"siphon_more":
			# Pilot Siphon Protocol: siphon more fuel from wreckage.
			BoardManager._trigger_wreckage_siphon()
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
	for key in GlobalData.part_damage:
		var cur := float(GlobalData.part_damage[key])
		GlobalData.part_damage[key] = maxf(cur - repair / 100.0, 0.0)


# Rebuilds a walking chassis from convoy spares and ends pilot-only mode. If no
# berth is available the convoy strips the garage for scrap instead.
static func _apply_recover_mech(params: Dictionary) -> void:
	var granted := HangarManager.grant_recovery_mech()
	if granted.is_empty():
		var fallback := int(params.get("fallback_scrap", 30))
		GlobalData.scrap += fallback
		GlobalData.run_notice = "The garage holds no usable chassis — your team strips it for %d scrap instead." % fallback
		return
	var heat := int(params.get("heat", 1))
	GlobalData.heat = maxi(0, GlobalData.heat + heat)
	GlobalData.run_notice = "Your mechanics rebuild a walking chassis from the convoy spares: %s is ready for combat." % str(granted.get("name", "Mech"))


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
		GlobalData.run_notice = "A lone wanderer offers an escort out of the sector — the convoy rides together."
	elif escort:
		GlobalData.run_notice = "A lone wanderer joins the convoy, piloting a spare chassis and riding along as an escort."
	else:
		GlobalData.run_notice = "A lone wanderer joins the convoy, piloting a spare chassis."


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
		GlobalData.run_notice = "A local salvage crew rides along with the convoy. +1 reputation."
	else:
		GlobalData.run_notice = "The locals are already part of the convoy — they wish you luck."
