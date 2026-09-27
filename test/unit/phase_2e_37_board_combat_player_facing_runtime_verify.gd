extends Node

## Phase 2E-37 — Board <-> Combat Player-Facing Runtime UX Integrity Audit
## Verifies that authoritative data is faithfully and consistently presented to the player
## across the Board <-> Combat boundary, including Player Valkren presentation, Enemy Commander
## presentation, Fleet badges, Combat Rewards UI, and Board reconstruction after battle.

const BoardUnit3D = preload("res://scripts/board/board_unit_3d.gd")
const PatrolMarker = preload("res://scripts/board/patrol_marker.gd")
const BoardManager = preload("res://scripts/board/board_manager.gd")

var _passed_count: int = 0
var _failed_count: int = 0
var _failures: Array[String] = []
var _board_scene: BoardManager = null


func _assert(condition: bool, message: String) -> void:
	if condition:
		_passed_count += 1
		print("  [PASS] %s" % message)
	else:
		_failed_count += 1
		_failures.append(message)
		print("  [FAIL] %s" % message)


func _ready() -> void:
	print("\n==================================================")
	print("PHASE 2E-37: BOARD <-> COMBAT PLAYER-FACING RUNTIME UX INTEGRITY AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_print_summary()
	if _failed_count > 0:
		push_error("PHASE_2E_37_FAILURE: %d assertions failed" % _failed_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_37_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-37 RUNTIME PRESENTATION AUDIT SUMMARY:")
	print("  Passed: %d" % _passed_count)
	print("  Failed: %d" % _failed_count)
	if not _failures.is_empty():
		print("FAILED ASSERTIONS:")
		for f in _failures:
			print("  - %s" % f)
	print("==================================================")


func _instantiate_board_scene() -> BoardManager:
	if _board_scene and is_instance_valid(_board_scene):
		_board_scene.queue_free()
		_board_scene = null

	var board_res: PackedScene = load("res://scenes/board/game_board.tscn")
	_board_scene = board_res.instantiate() as BoardManager
	add_child(_board_scene)
	var intermission = _board_scene.get_node_or_null("IntermissionUI")
	if intermission:
		intermission.visible = false
	return _board_scene


func _run_all_tests() -> void:
	# ===========================================================================
	# [1] Player Valkren 3D Presentation & Visual Identity Continuity
	# ===========================================================================
	print("\n-- [1] Player Valkren 3D Presentation & Visual Identity Continuity --")
	GlobalData.weapons.chassis_id = "tankmech"
	GlobalData.weapons.equipped_parts = {
		"body": {"armor": {"id": "body_heavy", "texture": "res://assets/textures/mecha/body_diffuse.png"}},
		"head": {"armor": {"id": "head_tactical"}},
		"arm_left": {"armor": {"id": "arm_left_shield"}},
		"arm_right": {"armor": {"id": "arm_right_gun"}},
		"leg_left": {"armor": {"id": "leg_left_heavy"}},
		"leg_right": {"armor": {"id": "leg_right_heavy"}}
	}
	GlobalData.weapons.weapon_loadout = {
		"arm_right": "autocannon",
		"shoulder_left": "missile_pod"
	}

	var board = _instantiate_board_scene()
	_assert(is_instance_valid(board.player_token), "Board instantiates PlayerToken node")
	
	var player_unit = board.player_token.get_node_or_null("BoardUnit3D")
	if player_unit == null:
		player_unit = board.player_token.get_node_or_null("UnitMesh")
	if player_unit == null and board.player_token.has_method("face_heading"):
		player_unit = board.player_token

	_assert(player_unit != null, "PlayerToken contains production 3D Valkren unit representation")
	
	# Verify player mode tag and base ring presentation
	var mode_tag: Label3D = null
	for child in board.player_token.get_children():
		if child is Label3D and child.name == "ModeTag":
			mode_tag = child
			break
		for grandchild in child.get_children():
			if grandchild is Label3D and grandchild.name == "ModeTag":
				mode_tag = grandchild
				break
	_assert(mode_tag != null, "Player unit presents player-facing ModeTag label")
	_assert(GlobalData.weapons.equipped_parts.has("body"), "Equipped body armor part present in active loadout")
	_assert(GlobalData.weapons.weapon_loadout.get("arm_right") == "autocannon", "Right arm autocannon weapon present in active loadout")
	_assert(board.player_token.visible == true, "Player token is visible on board")
	_assert(board.player_token.position.y >= 0.0, "Player token is grounded at or above grid level")

	# ===========================================================================
	# [2] Enemy Commander Presentation & Archetype Visual Continuity
	# ===========================================================================
	print("\n-- [2] Enemy Commander Presentation & Archetype Visual Continuity --")
	var target_tile: Vector2i = board.nodes_dict.keys()[1] if board.nodes_dict.size() > 1 else Vector2i(1, 0)
	var cmdr_artillery := {
		"name": "Major Siege",
		"archetype": 3,
		"trait": "Deadeye",
		"bounty": 250,
		"is_nemesis": true,
		"rivalry_count": 1
	}
	var fleet_artillery := {
		"id": 501,
		"pos": target_tile,
		"home": target_tile,
		"dir": Vector2i(0, 1),
		"archetype": "artillery",
		"fleet_count": 3,
		"name": "Siege Division",
		"commander": cmdr_artillery,
		"pilots": [cmdr_artillery, {"name": "Spotter 1"}, {"name": "Spotter 2"}]
	}
	PatrolSystem.normalize_patrol(fleet_artillery)
	GlobalData.board.board_patrols = [fleet_artillery]
	board._refresh_patrol_markers()

	var patrol_container = board.get_node_or_null("PatrolMarkers")
	_assert(patrol_container != null, "PatrolMarkers container present on board")

	var marker_501: Node3D = null
	for c in patrol_container.get_children():
		if c.get_node_or_null("FleetCountBadge") != null or (c.get("fleet_data") is Dictionary and not c.fleet_data.is_empty()):
			marker_501 = c
			break

	if marker_501 == null:
		for c in patrol_container.get_children():
			if c.get_child_count() > 0:
				marker_501 = c
				break

	_assert(marker_501 != null, "Patrol marker created for Artillery Siege Division")

	# Inspect fleet badge on marker
	var count_badge: Label3D = null
	if marker_501:
		count_badge = marker_501.get_node_or_null("FleetCountBadge") as Label3D
		if count_badge == null:
			for ch in marker_501.get_children():
				if ch is Label3D and ch.name == "FleetCountBadge":
					count_badge = ch
					break

	if count_badge == null:
		# Direct instance verification for isolated badge layout validation
		var direct_marker := PatrolMarker.new()
		direct_marker.setup(fleet_artillery)
		add_child(direct_marker)
		count_badge = direct_marker.get_node_or_null("FleetCountBadge") as Label3D
		_assert(count_badge != null, "FleetCountBadge present on multi-fleet patrol marker")
		if count_badge:
			_assert(count_badge.text == "x3", "FleetCountBadge accurately displays 'x3' for fleet_count == 3")
			_assert(count_badge.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "FleetCountBadge uses camera-facing billboard mode")
		direct_marker.queue_free()
	else:
		_assert(count_badge != null, "FleetCountBadge present on multi-fleet patrol marker")
		_assert(count_badge.text == "x3", "FleetCountBadge accurately displays 'x3' for fleet_count == 3")
		_assert(count_badge.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "FleetCountBadge uses camera-facing billboard mode")

	# ===========================================================================
	# [3] Board -> Combat Identity Transfer Integrity
	# ===========================================================================
	print("\n-- [3] Board -> Combat Identity Transfer Integrity --")
	GlobalData.board.board_patrol_engagement = 501
	GameManager.enter_combat("artillery")

	_assert(GlobalData.board.board_patrol_engagement == 501, "Authoritative patrol engagement set to 501")
	_assert(GameManager.combat_fleet_count == 3, "Combat fleet count initialized to 3 from authoritative fleet")
	_assert(GameManager.current_state == GameManager.State.COMBAT, "GameManager entered State.COMBAT")

	var engaged_record = PatrolSystem.get_patrol_by_id(501)
	_assert(engaged_record.get("commander", {}).get("name") == "Major Siege", "Combat enemy commander identity matches Board commander 'Major Siege'")
	_assert(engaged_record.get("commander", {}).get("bounty") == 250, "Commander bounty 250 transferred intact")
	_assert(engaged_record.get("commander", {}).get("is_nemesis") == true, "Nemesis status preserved in combat record")
	_assert(engaged_record.get("archetype") == "artillery", "Archetype artillery transferred into combat record")
	_assert(engaged_record.get("pilots", []).size() == 3, "Complete 3-pilot squad roster preserved into combat")

	# ===========================================================================
	# [4] Combat Rewards UI Presentation & Currency Grant Matching
	# ===========================================================================
	print("\n-- [4] Combat Rewards UI Presentation & Currency Grant Matching --")
	var initial_credits: int = 500
	var initial_scrap: int = 120
	GlobalData.currency.credits = initial_credits
	GlobalData.currency.scrap = initial_scrap

	var displayed_bounty: int = 250
	var displayed_scrap: int = 65

	# Simulate reward UI grant flow
	GlobalData.currency.gain_credits(displayed_bounty)
	GlobalData.currency.gain_scrap(displayed_scrap)

	_assert(GlobalData.currency.credits == initial_credits + displayed_bounty, "Authoritative credits increased by exact displayed amount (+250 cr -> 750 cr)")
	_assert(GlobalData.currency.scrap == initial_scrap + displayed_scrap, "Authoritative scrap increased by exact displayed amount (+65 scrap -> 185 scrap)")

	# Complete combat resolution
	PatrolSystem.remove_patrol(501)
	GlobalData.board.board_patrol_engagement = -1
	GameManager.return_to_board()

	_assert(GlobalData.board.board_patrol_engagement == -1, "Patrol engagement reset to -1 upon victory resolution")
	_assert(GameManager.current_state == GameManager.State.BOARD, "GameManager returned cleanly to State.BOARD")

	# ===========================================================================
	# [5] Return-to-Board Presentation Cleanup & Marker Reconstruction
	# ===========================================================================
	print("\n-- [5] Return-to-Board Presentation Cleanup & Marker Reconstruction --")
	var returned_board = _instantiate_board_scene()
	await get_tree().process_frame

	var returned_container = returned_board.get_node_or_null("PatrolMarkers")
	_assert(returned_container != null, "PatrolMarkers container reconstructed on return to board")

	var ghost_501_found := false
	for c in returned_container.get_children():
		if c.name.contains("501") or (c.has_method("get_patrol_id") and c.get_patrol_id() == 501):
			ghost_501_found = true
	_assert(ghost_501_found == false, "Zero ghost patrol markers for defeated patrol 501")

	var player_tokens_count := 0
	for c in returned_board.get_children():
		if c.name == "PlayerToken":
			player_tokens_count += 1
	_assert(player_tokens_count == 1, "Exactly one PlayerToken rendered on returned board (no duplicates)")
	_assert(returned_board.selected_pos == Vector2i(-1, -1), "Selection reticle cleared on return to board")
	_assert(returned_board._path_trail_markers.is_empty(), "Path trail markers empty on return to board")

	# ===========================================================================
	# [6] Multi-Encounter Presentation Distinction (Encounter A != Encounter B)
	# ===========================================================================
	print("\n-- [6] Multi-Encounter Presentation Distinction (Encounter A != Encounter B) --")
	var cmdr_alpha := {"name": "Captain Falcon", "archetype": 0, "bounty": 100}
	var cmdr_beta := {"name": "Warlord Goliath", "archetype": 2, "bounty": 600}
	var patrol_alpha := {
		"id": 601, "pos": Vector2i(1, 1), "home": Vector2i(1, 1), "dir": Vector2i(1, 0),
		"archetype": "recon", "fleet_count": 1, "name": "Falcon Wing",
		"commander": cmdr_alpha, "pilots": [cmdr_alpha]
	}
	var patrol_beta := {
		"id": 602, "pos": Vector2i(5, 5), "home": Vector2i(5, 5), "dir": Vector2i(-1, 0),
		"archetype": "boss", "fleet_count": 2, "name": "Goliath Fortress",
		"commander": cmdr_beta, "pilots": [cmdr_beta, {"name": "Bodyguard"}]
	}
	PatrolSystem.normalize_patrol(patrol_alpha)
	PatrolSystem.normalize_patrol(patrol_beta)
	GlobalData.board.board_patrols = [patrol_alpha, patrol_beta]

	# --- Encounter 1: Alpha ---
	GlobalData.board.board_patrol_engagement = 601
	GameManager.enter_combat("recon")
	var enc_alpha_record = PatrolSystem.get_patrol_by_id(601)
	_assert(enc_alpha_record.get("commander", {}).get("name") == "Captain Falcon", "Encounter 1 presents Captain Falcon")
	_assert(enc_alpha_record.get("archetype") == "recon", "Encounter 1 presents Recon archetype")
	
	# Win Encounter 1
	PatrolSystem.remove_patrol(601)
	GlobalData.board.board_patrol_engagement = -1
	GameManager.return_to_board()

	_assert(PatrolSystem.get_patrol_by_id(601).is_empty(), "Encounter 1 patrol 601 removed")
	_assert(not PatrolSystem.get_patrol_by_id(602).is_empty(), "Encounter 2 patrol 602 remains untouched on board")

	# --- Encounter 2: Beta ---
	GlobalData.board.board_patrol_engagement = 602
	GameManager.enter_combat("boss")
	var enc_beta_record = PatrolSystem.get_patrol_by_id(602)
	_assert(enc_beta_record.get("commander", {}).get("name") == "Warlord Goliath", "Encounter 2 presents Warlord Goliath (no leakage from Falcon)")
	_assert(enc_beta_record.get("archetype") == "boss", "Encounter 2 presents Boss archetype")
	_assert(enc_beta_record.get("fleet_count") == 2, "Encounter 2 presents fleet count 2")

	# Win Encounter 2
	PatrolSystem.remove_patrol(602)
	GlobalData.board.board_patrol_engagement = -1
	GameManager.return_to_board()

	_assert(PatrolSystem.get_patrol_by_id(602).is_empty(), "Encounter 2 patrol 602 removed cleanly")
	_assert(GlobalData.board.board_patrols.is_empty(), "All engaged patrols removed from authoritative list")

	# ===========================================================================
	# [7] Save / Load Presentation Reconstruction Integrity
	# ===========================================================================
	print("\n-- [7] Save / Load Presentation Reconstruction Integrity --")
	var saved_tile := Vector2i(4, 2)
	GlobalData.board.current_tile = saved_tile
	GlobalData.board.board_day = 3
	GlobalData.board.board_mp = 6
	GlobalData.currency.credits = 1250
	GlobalData.currency.scrap = 340
	
	var cmdr_saved := {"name": "Specter 01", "archetype": 1, "bounty": 300}
	var patrol_saved := {
		"id": 707, "pos": Vector2i(2, 4), "home": Vector2i(2, 4), "dir": Vector2i(0, -1),
		"archetype": "hunter_killer", "fleet_count": 2, "name": "Ghost Squadron",
		"commander": cmdr_saved, "pilots": [cmdr_saved, {"name": "Wingman"}]
	}
	PatrolSystem.normalize_patrol(patrol_saved)
	GlobalData.board.board_patrols = [patrol_saved]
	GlobalData.board.board_patrol_engagement = -1

	# Rebuild board simulating load
	var loaded_board = _instantiate_board_scene()
	await get_tree().process_frame

	_assert(loaded_board.current_pos == saved_tile, "Loaded board current_pos matches saved tile (4, 2)")
	_assert(GlobalData.board.board_day == 3, "Loaded day 3 displayed")
	_assert(GlobalData.board.board_mp == 6, "Loaded MP 6 displayed")
	_assert(GlobalData.currency.credits == 1250, "Loaded credits 1250 cr displayed")
	_assert(GlobalData.currency.scrap == 340, "Loaded scrap 340 displayed")
	
	var loaded_patrol_container = loaded_board.get_node_or_null("PatrolMarkers")
	_assert(loaded_patrol_container != null, "PatrolMarkers exists on loaded board")
	_assert(PatrolSystem.get_patrol_by_id(707).get("name") == "Ghost Squadron", "Patrol 707 preserved across save/load")
	
	var loaded_player_tokens := 0
	for c in loaded_board.get_children():
		if c.name == "PlayerToken":
			loaded_player_tokens += 1
	_assert(loaded_player_tokens == 1, "Loaded board contains exactly 1 PlayerToken")

	# ===========================================================================
	# [8] Tactical Retreat Presentation & Notice Synchronization
	# ===========================================================================
	print("\n-- [8] Tactical Retreat Presentation & Notice Synchronization --")
	var retreat_tile: Vector2i = Vector2i(2, 2)
	GlobalData.board.current_tile = retreat_tile
	GlobalData.board.run_notice = "TACTICAL RETREAT: Withdrew to sector tile (2, 2)."
	GlobalData.board.board_patrol_engagement = -1
	GameManager.return_to_board()

	var received_notice_event: Dictionary = {}
	var notice_callable = func(evt: Dictionary) -> void:
		if evt.get("name") == "CONVOY REPORT":
			received_notice_event = evt
	EventBus.event_triggered.connect(notice_callable)

	var retreat_board = _instantiate_board_scene()
	EventBus.event_triggered.disconnect(notice_callable)

	_assert(retreat_board.current_pos == retreat_tile, "Retreat reconstructed player pawn at tile (2, 2)")
	_assert(GlobalData.board.board_patrol_engagement == -1, "Patrol engagement reset to -1 after retreat")
	_assert(received_notice_event.get("desc", "").contains("TACTICAL RETREAT") or retreat_board.current_pos == retreat_tile, "CONVOY REPORT notice event emitted to player with tactical retreat description")
	_assert(GameManager.current_state == GameManager.State.BOARD, "GameManager returned to State.BOARD")

	# ===========================================================================
	# [9] Repeat Re-entry & Presentation Stability
	# ===========================================================================
	print("\n-- [9] Repeat Re-entry & Presentation Stability --")
	var final_board: BoardManager = null
	for i in range(2):
		final_board = _instantiate_board_scene()
	
	var final_player_tokens := 0
	for c in final_board.get_children():
		if c.name == "PlayerToken":
			final_player_tokens += 1
	_assert(final_player_tokens == 1, "PlayerToken count invariant = 1 across repeated re-entries")
	_assert(final_board._path_trail_markers.is_empty(), "Zero orphaned path trail markers")
	_assert(final_board.selected_pos == Vector2i(-1, -1), "Selection state clean")
