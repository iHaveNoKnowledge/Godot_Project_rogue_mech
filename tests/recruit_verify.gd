extends Node

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("RECRUIT OK: " + name)
	else:
		_fails += 1
		printerr("RECRUIT FAIL: " + name)


func _unit(tid: String, name: String) -> Dictionary:
	return {"template_id": tid, "name": name, "hp": 50.0, "max_hp": 50.0, "destroyed": false, "fielded": true}


func _reset() -> void:
	# Fleet of 2 squadmates -> convoy capacity 8 berths, enough to park recruits.
	GlobalData.reset_run_data()
	GlobalData.hangar.fleet_roster = [_unit("grunt_squad", "Alpha"), _unit("ace_scout", "Bravo")]
	await get_tree().process_frame


func _event_with(character_id: String) -> Dictionary:
	return {
		"id": "encounter_%s" % character_id,
		"effect": "choice",
		"themes": [],
		"params": {
			"character_id": character_id,
			"choices": [{"effect": "duel", "params": {"combat_type": "duel"}}],
		},
	}


func _ready() -> void:
	await _reset()

	# --- Catalog + availability ---
	var serra := RecruitSystem.get_character("serra")
	_check(serra.get("id", "") == "serra", "catalog returns serra")
	_check(RecruitSystem.get_character("nobody").is_empty(), "unknown character returns empty")
	_check(not RecruitSystem.is_character_recruited("serra"), "fresh run: serra not recruited")
	_check(RecruitSystem.is_character_available("serra"), "fresh run: serra is available")
	_check(RecruitSystem.is_event_available(_event_with("serra")), "recruit event available before meeting")

	# --- Friendly talk: joins immediately, parks mech + pilot ---
	_check(RecruitSystem.recruit("serra"), "friendly recruit returns true")
	_check(RecruitSystem.is_character_recruited("serra"), "serra marked recruited after talk")
	_check(not RecruitSystem.is_character_available("serra"), "serra no longer available after recruit")
	_check(not RecruitSystem.is_event_available(_event_with("serra")), "recruit event hidden after recruit")
	_check(FleetSystem.has_ally_unit("ally_serra"), "serra fleet unit added")
	var berths := HangarManager.get_mechs()
	var found_pilot := false
	for berth in berths:
		if str(berth.get("pilot", "")) == "fleet_ally_serra":
			found_pilot = true
	_check(found_pilot, "serra's mech parked and piloted by her")
	_check(GlobalData.board.run_notice != "", "run notice describes the recruit")
	_check(not RecruitSystem.recruit("serra"), "recruiting again is a no-op")

	# --- Duel for respect: win -> joins ---
	await _reset()
	_check(RecruitSystem.start_duel("ren", "test"), "start respect duel")
	_check(RecruitSystem.has_pending_duel(), "pending duel recorded")
	_check(RecruitSystem.get_pending_character().get("id", "") == "ren", "pending character resolves to ren")
	RecruitSystem.resolve_duel(true)
	_check(not RecruitSystem.has_pending_duel(), "pending duel cleared after resolve")
	_check(RecruitSystem.is_character_recruited("ren"), "respect-duel win recruits ren")
	_check(FleetSystem.has_ally_unit("ally_ren"), "ren fleet unit added after duel win")
	_check(GlobalData.hangar.duel_result_text != "", "duel result text set for respect win")

	# --- Duel loss: nothing gained, character stays out ---
	await _reset()
	RecruitSystem.start_duel("ren", "test")
	RecruitSystem.resolve_duel(false)
	_check(GlobalData.hangar.duel_result_text != "", "duel defeat text set")
	_check(not RecruitSystem.is_character_recruited("ren"), "defeat does not recruit")
	_check(not FleetSystem.has_ally_unit("ally_ren"), "defeat adds no ally")

	# --- Kill duel: win always resolves (wreck | parts) + pilot fate, and the
	# --- character can never be met again this run.
	await _reset()
	var credits_before := GlobalData.currency.credits
	var scrap_before := GlobalData.currency.scrap
	RecruitSystem.start_duel("jax", "kill")
	RecruitSystem.resolve_duel(true)
	_check(RecruitSystem.is_character_recruited("jax"), "kill-duel win marks jax resolved")
	_check(GlobalData.hangar.duel_result_text != "", "kill-duel outcome text set")
	_check(not FleetSystem.has_ally_unit("ally_jax") or FleetSystem.get_fleet_unit("ally_jax").get("fielded", true) == false, "salvaged ally never joins fielded")
	var gained_something := GlobalData.currency.credits > credits_before or GlobalData.currency.scrap > scrap_before
	var wreck_parked := false
	for berth in HangarManager.get_mechs():
		if str(berth.get("name", "")).contains("Mudhorn"):
			wreck_parked = true
	# A kill-duel win ALWAYS yields something: the wreck parked in the hangar,
	# recovered parts (scrap/credits), OR a wounded survivor joining the fleet
	# (the pilot crawls out of the wreck — no berth, no parts). All three are
	# valid outcomes; assert the OR so a lucky survivor roll doesn't fail.
	var survivor_joined := FleetSystem.has_ally_unit("ally_jax") and bool(FleetSystem.get_fleet_unit("ally_jax").get("wounded", false))
	_check(wreck_parked or gained_something or survivor_joined, "kill duel yields a wreck, parts, or a wounded survivor")
	if wreck_parked:
		var wreck_damaged := false
		for slot in GlobalData.MECHA_SLOTS:
			if float(HangarManager.get_mechs()[HangarManager.get_mechs().size() - 1].get("damage", {}).get(slot, 0.0)) > 0.5:
				wreck_damaged = true
		_check(wreck_damaged, "salvaged wreck arrives heavily damaged")

	# --- Wounded recovery: fielded again after wound_turns elapse ---
	await _reset()
	GlobalData.hangar.fleet_roster.append({
		"template_id": "ally_jax",
		"name": "Jax",
		"hp": 10.0,
		"max_hp": 70.0,
		"destroyed": false,
		"fielded": false,
		"wounded": true,
		"wound_turns": 2,
	})
	RecruitSystem.tick_recovery()
	RecruitSystem.tick_recovery()
	RecruitSystem.tick_recovery()
	var jax_unit := FleetSystem.get_fleet_unit("ally_jax")
	_check(not bool(jax_unit.get("wounded", false)), "wounded pilot recovers after turns elapse")
	_check(bool(jax_unit.get("fielded", false)), "recovered pilot is fielded again")

	# --- On foot: the whole encounter is skipped (a duel can't be fought) ---
	GlobalData.narrative.mech_less = true
	var foot_event := {
		"id": "encounter_serra",
		"effect": "choice",
		"params": {
			"character_id": "serra",
			"choices": [
				{"effect": "recruit_ally", "params": {"character_id": "serra"}},
				{"effect": "duel", "params": {"combat_type": "duel", "intent": "test"}},
			],
		},
	}
	GlobalData.hangar.recruited_characters = []
	_check(not RecruitSystem.is_event_available(foot_event), "on foot: duel encounter hidden (cannot fight)")
	var talk_only := foot_event.duplicate(true)
	talk_only["params"]["choices"] = [{"effect": "recruit_ally", "params": {"character_id": "serra"}}]
	_check(RecruitSystem.is_event_available(talk_only), "on foot: talk-only encounter still available")

	# --- Save/load roundtrip: recruits + pending duel persist ---
	await _reset()
	RecruitSystem.recruit("serra")
	RecruitSystem.start_duel("ren", "test")
	GlobalData.save_run()
	await _reset()
	_check(GlobalData.load_run(), "save/load: run file loads")
	_check(RecruitSystem.is_character_recruited("serra"), "save/load: recruited list survives")
	_check(RecruitSystem.has_pending_duel(), "save/load: pending duel survives")
	_check(str(GlobalData.hangar.pending_duel.get("character_id", "")) == "ren", "save/load: duel character survives")

	print("RECRUIT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
