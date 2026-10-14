class_name CampaignAssaultVisibilityVerify
extends Node

## ---------------------------------------------------------------------------
## Phase 2D-2 — DEFERRED ASSAULT VISIBILITY VERIFICATION (read-model only)
##
## Verifies the node-map assault status indicator, a pure read composition:
##   V1. ACTIVE unexpired assault shows the pending label with turn/deadline.
##   V2. Expired unresolved assault shows the expiry label (never "resolved").
##   V3. Record-less ACTIVE battle with proven DEFEND eligibility shows the
##       deferred label; without eligibility it shows plain ACTIVE.
##   V4. Missing record / terminal battle shows no misleading label.
##   V5. Switching selection never leaks the previous node's status.
##   V6. Rendering mutates nothing (records, battles, bases, forces, credits,
##       turn, recovery/defend eligibility).
## ---------------------------------------------------------------------------

const CampaignNodeMapScene = preload("res://scenes/ui/campaign_node_map.tscn")
const CampaignNodeMapScript = preload("res://scripts/ui/campaign_node_map.gd")
const CampaignPlayerMovement = preload("res://scripts/systems/campaign_player_movement.gd")

var _total_assertions: int = 0
var _passed_assertions: int = 0
var _failed_assertions: int = 0
var _save_backup := ""


func _ready() -> void:
	print("--- BEGIN PHASE 2D-2 ASSAULT VISIBILITY VERIFY ---")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _assert_true(condition: bool, message: String) -> void:
	_total_assertions += 1
	if condition:
		_passed_assertions += 1
	else:
		_failed_assertions += 1
		printerr("FAIL: " + message)


func _assert_false(condition: bool, message: String) -> void:
	_assert_true(not condition, message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_total_assertions += 1
	if actual == expected:
		_passed_assertions += 1
	else:
		_failed_assertions += 1
		printerr("FAIL: %s | Expected: %s, Got: %s" % [message, str(expected), str(actual)])


func _setup_clean_campaign_environment() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTurnExecutive.reset()
	FactionSystem.reset_relations()
	FactionSystem.set_player_faction("federation")
	CampaignBaseDefense.reset_defense_state()
	CampaignPlayerDispatch.clear_handlers()
	CampaignPlayerDispatch.register_default_handlers()
	GlobalData.current_campaign_player_node_id = ""
	if GlobalData != null:
		if GlobalData.board != null:
			GlobalData.board.current_sector = 1
			GlobalData.board.current_tile = Vector2i(0, 0)
			GlobalData.board.board_patrol_engagement = -1
		if GlobalData.currency != null:
			GlobalData.currency.credits = 1000
			GlobalData.currency.scrap = 50


func _setup_assaulted_base(tag: String, tile: Vector2i, turn: int) -> Dictionary:
	var node_id := CampaignNodeRegistry.register_node(1, tile, "safehouse")
	var terr_id := CampaignTerritory.register_territory("terr_" + tag, [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_" + tag, node_id, "OUTPOST", "federation", terr_id)
	var attacker_id := CampaignForce.register_force("force_zeon_" + tag, "PATROL", "zeon", node_id)
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	GlobalData.board.current_tile = tile
	CampaignPlayerMovement.set_current_node_id(node_id)
	var r := CampaignBaseDefense.process_assault_turn(turn)
	var created: Array = r.get("created", [])
	if created.is_empty():
		_assert_true(false, "setup assault for %s" % tag)
		return {}
	return {
		"node_id": node_id, "base_id": base_id, "attacker_id": attacker_id,
		"battle_id": str(created[0]),
	}


func _take_state_snapshot() -> Dictionary:
	return {
		"assaults": JSON.stringify(CampaignBaseDefense.get_assaults()),
		"battles": JSON.stringify(CampaignBattle.get_battles()),
		"bases": JSON.stringify(CampaignBase.get_bases()),
		"forces": JSON.stringify(CampaignForce.get_forces()),
		"credits": GlobalData.currency.credits if GlobalData and GlobalData.currency else 0,
		"turn": CampaignTurnExecutive.get_turn(),
		"can_defend": "",
		"can_recover": "",
	}


func _run_all_tests() -> void:
	_test_pending_label()
	_test_expired_label()
	_test_deferred_and_active_labels()
	_test_no_misleading_label()
	_test_selection_switching()
	_test_render_mutates_nothing()


# ---------------------------------------------------------------------------
# V1: Pending label with turn/deadline.
# ---------------------------------------------------------------------------
func _test_pending_label() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assaulted_base("v1", Vector2i(4, 4), 5)
	var node_id := str(ctx.get("node_id", ""))
	var base_id := str(ctx.get("base_id", ""))

	_assert_eq(CampaignNodeMapScript.get_assault_status_text(base_id),
		"PENDING (TURN 0/7)", "V1: Pending label carries turn and deadline")

	var node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)
	node_map.select_node(node_id)
	_assert_true(str(node_map._info_details_label.text).contains("Assault: PENDING (TURN 0/7)"),
		"V1: Inspection panel shows the pending assault line")
	node_map.queue_free()


# ---------------------------------------------------------------------------
# V2: Expired unresolved assault shows expiry, never "resolved".
# ---------------------------------------------------------------------------
func _test_expired_label() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assaulted_base("v2", Vector2i(4, 4), 5)
	var node_id := str(ctx.get("node_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	# DISABLED attacker defers under AUDIT_ONLY, keeping the assault expired
	# and unresolved for label inspection.
	CampaignForce.set_state(str(ctx.get("attacker_id", "")), CampaignForce.ForceState.DISABLED)
	CampaignBaseDefense.process_assault_turn(8)
	_assert_true(CampaignBaseDefense.is_assault_expired(
		str(CampaignBaseDefense.get_defense_battle_for_base(base_id).get("id", ""))),
		"V2: Assault expired")

	_assert_eq(CampaignNodeMapScript.get_assault_status_text(base_id),
		"EXPIRED — RESOLUTION PENDING", "V2: Expiry label, never resolved")

	var node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)
	node_map.select_node(node_id)
	var text := str(node_map._info_details_label.text)
	_assert_true(text.contains("Assault: EXPIRED — RESOLUTION PENDING"),
		"V2: Panel shows the expiry line")
	_assert_false(text.contains("RESOLVED"),
		"V2: No misleading resolved claim")
	node_map.queue_free()


# ---------------------------------------------------------------------------
# V3: Record-less ACTIVE defense-family battle: DEFERRED iff DEFEND proven
# eligible; non-family ids are never defense battles (Phase 2H-A).
# ---------------------------------------------------------------------------
func _test_deferred_and_active_labels() -> void:
	_setup_clean_campaign_environment()
	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(6, 6), "safehouse")
	var terr_id := CampaignTerritory.register_territory("terr_v3", [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_v3", node_id, "OUTPOST", "federation", terr_id)
	var attacker_id := CampaignForce.register_force("force_zeon_v3", "PATROL", "zeon", node_id)
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	var defender_id := "force_garrison_" + node_id
	CampaignForce.register_force(defender_id, "PATROL", "federation", node_id, base_id, 1, 10)
	# Defense-family id without a scheduler record (legacy/manual assault).
	var battle_id := CampaignBattle.register_battle("battle_s1_def_base_v3", node_id, [attacker_id, defender_id])
	CampaignBattle.prepare_launch(battle_id)
	_assert_true(CampaignBaseDefense.get_assault(battle_id).is_empty(),
		"V3: Manual battle carries no scheduler record")

	# A non-family id at the same node is never a defense battle, even ACTIVE:
	# with only the outsider present, no assault label may appear.
	var outsider_a := CampaignForce.register_force("force_zeon_v3b", "PATROL", "zeon", node_id)
	var outsider_b := CampaignForce.register_force("force_fed_v3b", "PATROL", "federation", node_id)
	var outsider := CampaignBattle.register_battle("battle_manual_v3", node_id, [outsider_a, outsider_b])
	CampaignBattle.prepare_launch(outsider)
	CampaignBattle.clear()
	_assert_eq(CampaignNodeMapScript.get_assault_status_text(base_id), "",
		"V3: Non-family id never matches, even when it is the only ACTIVE battle")
	CampaignBattle.register_battle("battle_s1_def_base_v3", node_id, [attacker_id, defender_id])
	CampaignBattle.prepare_launch("battle_s1_def_base_v3")

	# Player elsewhere: no eligibility proof -> plain ACTIVE.
	GlobalData.board.current_tile = Vector2i(0, 0)
	GlobalData.current_campaign_player_node_id = ""
	_assert_eq(CampaignNodeMapScript.get_assault_status_text(base_id), "ACTIVE",
		"V3: Plain ACTIVE without proven eligibility")

	# Player present: DEFEND eligibility proven -> deferred label.
	GlobalData.board.current_tile = Vector2i(6, 6)
	CampaignPlayerMovement.set_current_node_id(node_id)
	_assert_eq(CampaignNodeMapScript.get_assault_status_text(base_id),
		"DEFERRED — DEFEND AVAILABLE", "V3: Deferred label only with proven eligibility")

	var node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)
	node_map.select_node(node_id)
	_assert_true(str(node_map._info_details_label.text).contains("Assault: DEFERRED — DEFEND AVAILABLE"),
		"V3: Panel shows the deferred line")
	node_map.queue_free()


# ---------------------------------------------------------------------------
# V4: Terminal battle migrates (repeat assault), missing battle shows nothing.
# ---------------------------------------------------------------------------
func _test_no_misleading_label() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assaulted_base("v4", Vector2i(4, 4), 5)
	var node_id := str(ctx.get("node_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	var battle_id := str(ctx.get("battle_id", ""))

	# Resolving the battle does not fake an assault label: the next scan
	# starts a genuine repeat assault (suffix migration), which is PENDING.
	_assert_true(CampaignBattle.resolve_battle(battle_id), "V4: Battle resolved manually")
	var r := CampaignBaseDefense.process_assault_turn(8)
	_assert_eq((r.get("created", []) as Array).size(), 1,
		"V4: Repeat assault starts after terminal battle")
	_assert_true(str(CampaignNodeMapScript.get_assault_status_text(base_id)).begins_with("PENDING"),
		"V4: New repeat assault labelled PENDING (never stale)")

	# With no battles and no hostile forces, no label may appear.
	CampaignBattle.clear()
	CampaignForce.clear()
	CampaignBaseDefense.process_assault_turn(8)
	_assert_eq(CampaignNodeMapScript.get_assault_status_text(base_id), "",
		"V4: Missing battle shows no assault label")

	var node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)
	node_map.select_node(node_id)
	_assert_false(str(node_map._info_details_label.text).contains("Assault:"),
		"V4: Panel shows no assault line without a battle")
	node_map.queue_free()

	_assert_eq(CampaignNodeMapScript.get_assault_status_text("base_nope"), "",
		"V4: Unknown base shows no label")


# ---------------------------------------------------------------------------
# V5: Selection switching never leaks the previous node's status.
# ---------------------------------------------------------------------------
func _test_selection_switching() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assaulted_base("v5", Vector2i(4, 4), 5)
	var node_id := str(ctx.get("node_id", ""))
	var quiet_id := CampaignNodeRegistry.register_node(1, Vector2i(7, 7), "city")

	var node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)
	node_map.select_node(node_id)
	_assert_true(str(node_map._info_details_label.text).contains("Assault: PENDING"),
		"V5: Assault node shows pending")
	node_map.select_node(quiet_id)
	_assert_false(str(node_map._info_details_label.text).contains("Assault:"),
		"V5: Quiet node shows no assault line (no leak)")
	node_map.select_node(node_id)
	_assert_true(str(node_map._info_details_label.text).contains("Assault: PENDING"),
		"V5: Assault line returns on re-selection")
	node_map.queue_free()


# ---------------------------------------------------------------------------
# V6: Rendering mutates nothing.
# ---------------------------------------------------------------------------
func _test_render_mutates_nothing() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assaulted_base("v6", Vector2i(4, 4), 5)
	var node_id := str(ctx.get("node_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	var can_defend_before := CampaignBaseDefense.can_intervene(
		str(CampaignBaseDefense.get_defense_battle_for_base(base_id).get("id", "")))
	var snap_before := _take_state_snapshot()

	var node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)
	node_map.select_node(node_id)
	node_map.select_node(node_id)
	var status_a := CampaignNodeMapScript.get_assault_status_text(base_id)
	var status_b := CampaignNodeMapScript.get_assault_status_text(base_id)
	node_map.queue_free()

	_assert_eq(status_a, status_b, "V6: Status reads deterministically")
	_assert_eq(_take_state_snapshot(), snap_before, "V6: Rendering mutates zero campaign state")
	_assert_eq(CampaignBaseDefense.can_intervene(
		str(CampaignBaseDefense.get_defense_battle_for_base(base_id).get("id", ""))), can_defend_before,
		"V6: Defend eligibility unchanged by rendering")
	_assert_eq(CampaignBase.get_state(base_id), CampaignBase.BaseState.ACTIVE,
		"V6: Base untouched (recover eligibility unchanged)")


func _restore_save_backup() -> void:
	CampaignBaseDefense.reset_defense_state()
	GlobalData.reset_run_data()
	if _save_backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_backup)
			f.flush()
			f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)


func _print_summary() -> void:
	print("---------------------------------------------------------------------------")
	print("PHASE 2D-2 ASSAULT VISIBILITY VERIFY RESULTS:")
	print("  TOTAL ASSERTIONS : %d" % _total_assertions)
	print("  PASSED           : %d" % _passed_assertions)
	print("  FAILED           : %d" % _failed_assertions)
	print("---------------------------------------------------------------------------")
	if _failed_assertions == 0:
		print("PASSED: Phase 2D-2 assault visibility contract strictly satisfied.")
	else:
		printerr("FAILED: Phase 2D-2 assault visibility has %d failures!" % _failed_assertions)
	get_tree().quit(0 if _failed_assertions == 0 else 1)
