extends Node
## ---------------------------------------------------------------------------
## PLAYER DETACHMENT STRATEGIC ASSAULT VERIFY — Phase C8-C.
##
## Covers:
##   - Hostile target listing (HOSTILE only; neutral/allied excluded)
##   - can_attack validation matrix (unknown/inactive/no-strength/node/hostile)
##   - Win path: enemy force destroyed, detachment survives with casualties
##   - Loss path: detachment disabled, enemy survives with casualties
##   - Determinism (same inputs -> same receipt) and zero RNG
##   - Firewalls: no base/territory ownership mutation, no battle record faked
##   - Panel: target list, select, attack, result line
## ---------------------------------------------------------------------------

var _checks := 0
var _fails := 0
var _save_backup := ""
var _had_save := false
var _nodes := {}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("C8C_ASSAULT OK: %s" % message)
	else:
		_fails += 1
		printerr("C8C_ASSAULT FAIL: %s" % message)


func _ready() -> void:
	print("======================================================================")
	print("--- BEGIN PLAYER DETACHMENT STRATEGIC ASSAULT VERIFY (Phase C8-C) ---")
	print("======================================================================")
	_had_save = FileAccess.file_exists(GlobalData.SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	_test_target_listing()
	_test_validation()
	_test_player_wins()
	_test_player_loses()
	_test_determinism_and_firewalls()
	await _test_panel()

	if _had_save:
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_string(_save_backup)
			f.close()

	print("----------------------------------------------------------------------")
	print("PHASE C8-C SUMMARY: Passed: %d, Failed: %d" % [_checks - _fails, _fails])
	print("----------------------------------------------------------------------")
	if _fails == 0:
		print("ALL STRATEGIC ASSAULT (C8-C) CHECKS PASSED!")
	else:
		printerr("C8-C STRATEGIC ASSAULT VERIFICATION FAILED WITH %d ERRORS" % _fails)

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
	CampaignNodeRegistry.register_route(a, b)
	CampaignPlayerMovement.set_current_node_id(a)
	CampaignBase.register_base("base_home", a, "OUTPOST", "federation")
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	FactionSystem.set_relation("federation", "outland", FactionSystem.Relation.NEUTRAL)
	_nodes = {"a": a, "b": b}


func _register_enemy(tag: String, node_id: String, strength: int, faction: String = "zeon") -> String:
	return CampaignForce.register_force(
		"force_enemy_" + tag, "PATROL", faction, node_id, "", 3, strength)


func _register_garrison(strength: int) -> String:
	return CampaignPlayerForce.register_detachment(
		"player_force_strike", str(_nodes.get("a", "")), "base_home", 2, strength)


func _test_target_listing() -> void:
	_setup_world()
	var node_a := str(_nodes.get("a", ""))
	var hostile := _register_enemy("hostile", node_a, 20, "zeon")
	var neutral := _register_enemy("neutral", node_a, 20, "outland")
	var friendly := CampaignForce.register_force(
		"force_enemy_friendly", "PATROL", "federation", node_a, "", 2, 15)
	_register_garrison(30)
	var targets := CampaignPlayerForceAssault.get_hostile_targets_at(node_a)
	_check(targets.has(hostile), "HOSTILE force is listed as a target")
	_check(not targets.has(neutral), "NEUTRAL force is not a target")
	_check(not targets.has(friendly), "same-faction force is not a target")
	_check(CampaignPlayerForceAssault.get_hostile_targets_at("").is_empty(),
		"empty node lists no targets")


func _test_validation() -> void:
	_setup_world()
	var node_a := str(_nodes.get("a", ""))
	var node_b := str(_nodes.get("b", ""))
	var garrison := _register_garrison(30)
	var enemy := _register_enemy("main", node_a, 20)
	var neutral := _register_enemy("neutral2", node_a, 20, "outland")
	var elsewhere := _register_enemy("far", node_b, 20)

	_check(not bool(CampaignPlayerForceAssault.can_attack("missing", enemy).get("ok", true)),
		"unknown detachment is refused")
	_check(str(CampaignPlayerForceAssault.can_attack("missing", enemy).get("reason", ""))
		== "unknown_detachment", "unknown detachment reason")
	_check(str(CampaignPlayerForceAssault.can_attack(garrison, "missing").get("reason", ""))
		== "unknown_target", "unknown target is refused")
	_check(str(CampaignPlayerForceAssault.can_attack(garrison, elsewhere).get("reason", ""))
		== "target_not_at_node", "distant target is refused")
	_check(str(CampaignPlayerForceAssault.can_attack(garrison, neutral).get("reason", ""))
		== "target_not_hostile", "neutral target is refused")
	_check(not bool(CampaignPlayerForceAssault.can_attack(garrison, enemy).get("ok", false)) == false,
		"valid engagement is accepted")

	var inactive := _register_enemy("inactive", node_a, 20)
	CampaignForce.set_state(inactive, CampaignForce.ForceState.DISABLED)
	_check(str(CampaignPlayerForceAssault.can_attack(garrison, inactive).get("reason", ""))
		== "target_not_active", "disabled target is refused")

	CampaignPlayerForce.set_strength(garrison, 0)
	_check(str(CampaignPlayerForceAssault.can_attack(garrison, enemy).get("reason", ""))
		== "detachment_not_active", "disabled detachment cannot attack")


func _test_player_wins() -> void:
	_setup_world()
	var garrison := _register_garrison(40)
	var enemy := _register_enemy("weak", str(_nodes.get("a", "")), 15)
	var receipt := CampaignPlayerForceAssault.attack(garrison, enemy)
	_check(bool(receipt.get("ok", false)), "engagement resolves")
	_check(str(receipt.get("winner", "")) == "player", "stronger detachment wins")
	_check(bool(receipt.get("enemy_destroyed", false)), "defeated force is destroyed")
	_check(CampaignForce.get_state(enemy) == CampaignForce.ForceState.DESTROYED,
		"enemy force state is DESTROYED")
	_check(int(CampaignForce.get_force(enemy).get("strength", -1)) == 0,
		"enemy strength is zero")
	_check(int(receipt.get("player_remaining", -1)) > 0, "winning detachment keeps strength")
	_check(CampaignPlayerForce.is_active(garrison), "winning detachment stays active")
	_check(int(receipt.get("rounds", 0)) >= 1, "at least one attrition round ran")
	_check(CampaignPlayerForceAssault.get_hostile_targets_at(str(_nodes.get("a", ""))).is_empty(),
		"destroyed force leaves the target list")


func _test_player_loses() -> void:
	_setup_world()
	var garrison := _register_garrison(10)
	var enemy := _register_enemy("strong", str(_nodes.get("a", "")), 60)
	var receipt := CampaignPlayerForceAssault.attack(garrison, enemy)
	_check(str(receipt.get("winner", "")) == "enemy", "weaker detachment loses")
	_check(int(receipt.get("player_remaining", -1)) == 0, "losing detachment is wiped out")
	_check(CampaignPlayerForce.get_state(garrison) == CampaignPlayerForce.ForceState.DISABLED,
		"losing detachment is disabled, not deleted")
	_check(CampaignForce.get_state(enemy) == CampaignForce.ForceState.ACTIVE,
		"enemy survives the engagement")
	_check(int(CampaignForce.get_force(enemy).get("strength", -1)) < 60,
		"surviving enemy took casualties")


func _test_determinism_and_firewalls() -> void:
	_setup_world()
	var garrison := _register_garrison(35)
	var enemy := _register_enemy("mirror", str(_nodes.get("a", "")), 33)
	var base_before := CampaignBase.get_base("base_home").duplicate(true)
	var battles_before := CampaignBattle.get_battles().size()
	var first := CampaignPlayerForceAssault.attack(garrison, enemy)
	_check(str(first.get("winner", "")) != "", "deterministic run produces a winner")
	_check(int(first.get("rounds", 0)) <= CampaignBaseDefense.AUTO_BATTLE_MAX_ROUNDS,
		"round count respects the shared maximum")
	_check(CampaignBattle.get_battles().size() == battles_before,
		"no combat battle record is fabricated for a field engagement")
	_check(CampaignBase.get_base("base_home") == base_before,
		"base record is untouched by a field engagement")
	_check(int(first.get("enemy_remaining", -1))
		== int(CampaignForce.get_force(enemy).get("strength", -2)),
		"receipt matches the authoritative enemy strength")

	# Same inputs again (fresh world) produce the same combat outcome.
	_setup_world()
	var garrison2 := _register_garrison(35)
	var enemy2 := _register_enemy("mirror", str(_nodes.get("a", "")), 33)
	var second := CampaignPlayerForceAssault.attack(garrison2, enemy2)
	_check(str(second.get("winner", "")) == str(first.get("winner", "")),
		"identical inputs produce an identical winner (no RNG)")
	_check(int(second.get("player_remaining", -1)) == int(first.get("player_remaining", -2)),
		"identical inputs produce identical casualties")


func _test_panel() -> void:
	_setup_world()
	var garrison := _register_garrison(40)
	var enemy := _register_enemy("panel", str(_nodes.get("a", "")), 20)
	var panel := CampaignPlayerForcePanel.new()
	panel.name = "TestAssaultPanel"
	add_child(panel)
	await get_tree().process_frame
	panel.refresh()
	_check(panel.select_detachment(garrison), "panel selects the strike detachment")
	_check(panel.get_attack_targets() == [enemy], "panel lists the hostile target")
	_check(not panel.select_attack_target("force_missing"), "panel refuses unknown targets")
	_check(panel.select_attack_target(enemy), "panel selects the hostile target")
	var receipt := panel.attack_selected()
	_check(bool(receipt.get("ok", false)), "panel attack resolves")
	_check(str(receipt.get("winner", "")) == "player", "panel attack wins with the stronger force")
	_check(panel.get_selected_attack_target() == "", "panel clears the target after the attack")
	_check(panel.get_result_line().begins_with("OK"), "panel reports the assault result")
	_check(panel.get_attack_targets().is_empty(), "destroyed target leaves the panel list")
	panel.queue_free()
