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
		"scrap":
			GlobalData.scrap += amount
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
		"heat_bonus":
			GlobalData.heat = maxi(0, GlobalData.heat + int(params.get("heat", amount)))
		"theme_switch":
			return switch_theme(str(params.get("theme_id", "")))
		"force_combat":
			GlobalData.blocked_intermission = true
			return true
		"choice":
			# Choices are resolved by the event UI; nothing to apply here.
			pass
		_:
			push_warning("apply_event_effect: unknown effect '%s'" % effect)
	return false


# Called when a battle ends: applies reputation from the outcome.
static func on_combat_ended_for_reputation(victory: bool) -> void:
	if victory:
		add_reputation(1)
		if GameManager.is_boss_combat:
			add_reputation(2)
