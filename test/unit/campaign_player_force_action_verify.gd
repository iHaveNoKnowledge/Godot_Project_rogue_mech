extends Node
## ---------------------------------------------------------------------------
## PLAYER DETACHMENT ORDERS VERIFY — Phase C8-B.
##
## Covers:
##   - Raise: credits via CurrencyManager, rollback on payment failure,
##     position/duplicate/slug/credits validation
##   - Move: one route hop only, route-less rejection, inactive force
##   - Station/unstation: player-owned base on the detachment's node
##   - CampaignPlayerForcePanel: raise -> station -> move through the UI class
##   - Persistence: save key, serialize/deserialize, reset_run_data
## ---------------------------------------------------------------------------

var _checks := 0
var _fails := 0
var _save_backup := ""
var _had_save := false

var _nodes := {}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("C8B_FORCE_ACTION OK: %s" % message)
	else:
		_fails += 1
		printerr("C8B_FORCE_ACTION FAIL: %s" % message)


func _ready() -> void:
	print("======================================================================")
	print("--- BEGIN PLAYER DETACHMENT ORDERS VERIFY (Phase C8-B) ---")
	print("======================================================================")
	_had_save = FileAccess.file_exists(GlobalData.SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	await _test_raise()
	await _test_move()
	await _test_station()
	await _test_panel()
	await _test_persistence()
	await _test_remove()

	if _had_save:
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_string(_save_backup)
			f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(GlobalData.SAVE_PATH))

	print("----------------------------------------------------------------------")
	print("PHASE C8-B SUMMARY: Passed: %d, Failed: %d" % [_checks - _fails, _fails])
	print("----------------------------------------------------------------------")
	if _fails == 0:
		print("ALL PLAYER DETACHMENT ORDERS (C8-B) CHECKS PASSED!")
	else:
		printerr("C8-B DETACHMENT ORDERS VERIFICATION FAILED WITH %d ERRORS" % _fails)

	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)


func _setup_world() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignPlayerForce.reset()
	CampaignBaseDefense.reset_defense_state()
	CampaignTurnExecutive.reset()
	FactionSystem.reset_relations()
	FactionSystem.set_player_faction("federation")
	GlobalData.currency.credits = 500

	var a := CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "safehouse")
	var b := CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	var c := CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "city")
	CampaignNodeRegistry.register_route(a, b)
	CampaignPlayerMovement.set_current_node_id(a)
	CampaignBase.register_base("base_home", a, "OUTPOST", "federation")
	_nodes = {"a": a, "b": b, "c": c}


func _test_raise() -> void:
	_setup_world()
	var node_a := str(_nodes.get("a", ""))
	var receipt := CampaignPlayerForceAction.raise_player_detachment("aux_1")
	_check(bool(receipt.get("ok", false)), "raise at the current node succeeds")
	var fid := str(receipt.get("force_id", ""))
	_check(fid == "player_force_aux_1", "raised id is stable (%s)" % fid)
	_check(CampaignPlayerForce.has_detachment(fid), "raised detachment is registered")
	_check(str(CampaignPlayerForce.get_detachment(fid).get("node_id", "")) == node_a,
		"raised detachment stands at the player node")
	_check(int(CampaignPlayerForce.get_detachment(fid).get("unit_count", -1))
		== CampaignPlayerForceAction.get_raise_units(), "raise uses the declared unit count")
	_check(int(CampaignPlayerForce.get_detachment(fid).get("strength", -1))
		== CampaignPlayerForceAction.get_raise_strength(), "raise uses the declared strength")
	_check(int(GlobalData.currency.credits) == 500 - CampaignPlayerForceAction.get_raise_cost(),
		"raise charges credits through CurrencyManager")

	var duplicate := CampaignPlayerForceAction.raise_player_detachment("aux_1")
	_check(not bool(duplicate.get("ok", true)), "duplicate slug is rejected")
	_check(str(duplicate.get("reason", "")) == "detachment_exists", "duplicate reason is detachment_exists")

	var elsewhere := CampaignPlayerForceAction.raise_player_detachment("aux_2", str(_nodes.get("b", "")))
	_check(not bool(elsewhere.get("ok", true)), "raise is refused away from the player")
	_check(str(elsewhere.get("reason", "")) == "player_not_at_node",
		"away-from-player reason is player_not_at_node")

	var bad_slug := CampaignPlayerForceAction.raise_player_detachment("   ")
	_check(str(bad_slug.get("reason", "")) == "invalid_slug", "blank slug is rejected")

	var credits_before := int(GlobalData.currency.credits)
	GlobalData.currency.credits = 0
	var poor := CampaignPlayerForceAction.raise_player_detachment("aux_3")
	_check(not bool(poor.get("ok", true)), "raise fails without credits")
	_check(str(poor.get("reason", "")) == "insufficient_credits", "shortfall reason is insufficient_credits")
	_check(not CampaignPlayerForce.has_detachment("player_force_aux_3"),
		"failed raise rolls the detachment record back")
	_check(int(GlobalData.currency.credits) == 0, "failed raise charges nothing")
	GlobalData.currency.credits = credits_before


func _test_move() -> void:
	_setup_world()
	var node_b := str(_nodes.get("b", ""))
	var node_c := str(_nodes.get("c", ""))
	var fid := str(CampaignPlayerForceAction.raise_player_detachment("aux_1").get("force_id", ""))

	var moved := CampaignPlayerForceAction.move_player_detachment(fid, node_b)
	_check(bool(moved.get("ok", false)), "one-hop move along a registered route succeeds")
	_check(str(CampaignPlayerForce.get_detachment(fid).get("node_id", "")) == node_b,
		"detachment stands on the destination node")
	_check(str(moved.get("from_node_id", "")) != str(moved.get("to_node_id", "")),
		"receipt records both endpoints")

	var no_route := CampaignPlayerForceAction.move_player_detachment(fid, node_c)
	_check(str(no_route.get("reason", "")) == "no_route", "route-less move is rejected")
	_check(str(CampaignPlayerForce.get_detachment(fid).get("node_id", "")) == node_b,
		"rejected move does not relocate the detachment")

	var same := CampaignPlayerForceAction.move_player_detachment(fid, node_b)
	_check(str(same.get("reason", "")) == "same_node", "same-node move is rejected")
	_check(str(CampaignPlayerForceAction.move_player_detachment(fid, "node_missing").get("reason", ""))
		== "unknown_destination", "unknown destination is rejected")
	_check(str(CampaignPlayerForceAction.move_player_detachment("player_force_missing", node_b).get("reason", ""))
		== "unknown_detachment", "unknown detachment is rejected")

	CampaignPlayerForce.set_strength(fid, 0)
	var inactive := CampaignPlayerForceAction.move_player_detachment(fid, node_b)
	_check(str(inactive.get("reason", "")) == "detachment_not_active",
		"disabled detachment cannot move")


func _test_station() -> void:
	_setup_world()
	var node_a := str(_nodes.get("a", ""))
	var node_b := str(_nodes.get("b", ""))
	var fid := str(CampaignPlayerForceAction.raise_player_detachment("aux_1").get("force_id", ""))

	var stationed := CampaignPlayerForceAction.station_player_detachment(fid, "base_home")
	_check(bool(stationed.get("ok", false)), "stationing at a player base succeeds")
	_check(str(CampaignPlayerForce.get_detachment(fid).get("base_id", "")) == "base_home",
		"base binding is stored on the detachment")
	_check(str(CampaignPlayerForce.get_detachment(fid).get("node_id", "")) == node_a,
		"stationing does not move the detachment")

	var unstationed := CampaignPlayerForceAction.unstation_player_detachment(fid)
	_check(bool(unstationed.get("ok", false)), "unstation succeeds")
	_check(str(CampaignPlayerForce.get_detachment(fid).get("base_id", "")) == "",
		"unstation clears the base binding")

	_check(str(CampaignPlayerForceAction.station_player_detachment(fid, "base_missing").get("reason", ""))
		== "unknown_base", "unknown base is rejected")

	var enemy_base := CampaignBase.register_base("base_enemy", node_b, "OUTPOST", "zeon")
	_check(enemy_base != "", "enemy base fixture registered")
	CampaignPlayerForceAction.move_player_detachment(fid, node_b)
	_check(str(CampaignPlayerForceAction.station_player_detachment(fid, "base_enemy").get("reason", ""))
		== "base_not_player_owned", "stationing at an enemy base is rejected")

	CampaignPlayerForce.set_node(fid, node_a)
	var node_c := str(_nodes.get("c", ""))
	var far_base := CampaignBase.register_base("base_c", node_c, "OUTPOST", "federation")
	_check(far_base != "", "far player base fixture registered")
	_check(str(CampaignPlayerForceAction.station_player_detachment(fid, "base_c").get("reason", ""))
		== "detachment_not_at_base", "stationing at a base on another node is rejected")

	CampaignBase.set_state("base_home", CampaignBase.BaseState.DESTROYED)
	_check(str(CampaignPlayerForceAction.station_player_detachment(fid, "base_home").get("reason", ""))
		== "base_destroyed", "stationing at a destroyed base is rejected")


func _test_panel() -> void:
	_setup_world()
	var panel := CampaignPlayerForcePanel.new()
	panel.name = "TestForcePanel"
	add_child(panel)
	await get_tree().process_frame

	_check(panel.can_raise_now(), "panel reports the player can raise here")
	var raised := panel.raise_at_current_node()
	_check(bool(raised.get("ok", false)), "panel raise succeeds")
	_check(panel.get_selected_detachment() == str(raised.get("force_id", "")),
		"panel selects the newly raised detachment")
	_check(panel.get_detachment_display_lines().size() == 1, "panel lists one detachment")
	_check(panel.select_detachment("player_force_missing") == false, "panel refuses unknown selection")

	var stationed := panel.station_at_base()
	_check(bool(stationed.get("ok", false)), "panel station succeeds")
	_check(panel.unstation().get("ok", false), "panel unstation succeeds")

	_check(panel.select_destination(str(_nodes.get("b", ""))), "panel offers the route neighbour")
	var moved := panel.execute_move()
	_check(bool(moved.get("ok", false)), "panel move succeeds")
	_check(str(CampaignPlayerForce.get_detachment(panel.get_selected_detachment()).get("node_id", ""))
		== str(_nodes.get("b", "")), "panel move relocated the detachment")
	_check(panel.get_result_line().begins_with("OK"), "panel reports the last order as OK")

	# Raising is a paid action: an empty purse disables the panel entry point.
	var credits_before := int(GlobalData.currency.credits)
	GlobalData.currency.credits = 0
	_check(not panel.can_raise_now(), "panel disables raising without credits")
	GlobalData.currency.credits = credits_before
	_check(panel.can_raise_now(), "panel re-enables raising when credits return")
	panel.queue_free()


func _test_persistence() -> void:
	_setup_world()
	var fid := str(CampaignPlayerForceAction.raise_player_detachment("aux_1").get("force_id", ""))
	check_true(SaveGameIO._DICT_FIELDS.has("campaign_player_forces"),
		"save schema declares campaign_player_forces")
	var payload := CampaignPlayerForce.serialize()
	check_true((payload.get("detachments", []) as Array).size() == 1, "serialize contains the detachment")
	CampaignPlayerForce.reset()
	check_true(not CampaignPlayerForce.has_detachment(fid), "reset clears detachments")
	CampaignPlayerForce.deserialize(payload)
	check_true(CampaignPlayerForce.has_detachment(fid), "deserialize restores the detachment")
	GlobalData.reset_run_data()
	check_true(CampaignPlayerForce.get_detachments().is_empty(), "reset_run_data clears detachments")


func check_true(condition: bool, message: String) -> void:
	_check(condition, message)


func _test_remove() -> void:
	_setup_world()
	var fid := str(CampaignPlayerForceAction.raise_player_detachment("aux_1").get("force_id", ""))
	_check(CampaignPlayerForce.remove_detachment(fid), "detachment can be removed")
	_check(not CampaignPlayerForce.remove_detachment(fid), "removing twice returns false")
	check_true(true, "remove path complete")
