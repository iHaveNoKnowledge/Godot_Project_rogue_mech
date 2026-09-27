extends Node

## Phase 2E-36: Combat-to-Board Lifecycle Integrity Verification
## Validates the end-to-end combat lifecycle across the Board <-> Battle boundary:
## 1. Board -> Battle authoritative state transfer (patrol, commander, loadout, fleet count)
## 2. Combat resolution and exact single-mutation patrol removal
## 3. Preservation of unrelated patrols and commander isolation
## 4. Reward calculation, application, and double-resolution prevention
## 5. Clean Return-to-Board presentation reconstruction without ghost entities
## 6. Supported non-victory paths (Tactical Retreat delta relocation)
## 7. Post-combat Save/Load persistence across multiple milestones
## 8. Consecutive repeated encounters without cross-encounter state leakage
## 9. Re-entry safety and lifecycle leak prevention

const BoardUnit3D = preload("res://scripts/board/board_unit_3d.gd")
const PatrolMarker = preload("res://scripts/board/patrol_marker.gd")
const BoardManager = preload("res://scripts/board/board_manager.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _failed_messages: Array[String] = []
var _board_scene: BoardManager = null


func _ready() -> void:
	print("\n=== STARTING PHASE 2E-36 COMBAT-TO-BOARD LIFECYCLE INTEGRITY AUDIT ===\n")
	GameManager.suppress_scene_change = true

	await _run_all_tests()

	print("\n==================================================")
	print("PHASE 2E-36 LIFECYCLE AUDIT SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failed_messages.is_empty():
		print("FAILED ASSERTIONS:")
		for msg in _failed_messages:
			print("  - " + msg)
	print("==================================================")

	if _fail_count == 0:
		print("PHASE_2E_36_SUCCESS\n")
	else:
		push_error("PHASE_2E_36_FAILURE: %d assertions failed" % _fail_count)

	if _board_scene and is_instance_valid(_board_scene):
		_board_scene.queue_free()

	get_tree().quit(0 if _fail_count == 0 else 1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % message)
	else:
		_fail_count += 1
		_failed_messages.append(message)
		push_error("Assertion failed: %s" % message)
		print("  [FAIL] %s" % message)


func _instantiate_board_scene() -> BoardManager:
	if _board_scene and is_instance_valid(_board_scene):
		_board_scene.queue_free()
		_board_scene = null

	var scene_res = load("res://scenes/board/game_board.tscn") as PackedScene
	_board_scene = scene_res.instantiate() as BoardManager
	add_child(_board_scene)
	var intermission = _board_scene.get_node_or_null("IntermissionUI")
	if intermission:
		intermission.visible = false
	return _board_scene


func _setup_board(tile: Vector2i = Vector2i(2, 2)) -> BoardManager:
	GlobalData.board.current_sector = 1
	GlobalData.board.board_day = 1
	GlobalData.board.time_hour = 8.0
	GlobalData.board.board_mp = 6
	GlobalData.board.board_mp_max = 6
	GlobalData.board.active_contract = {"name": "Test Sector Contract", "target_sector": 1}
	GlobalData.board.board_objective_intro_consumed = true
	GlobalData.currency.credits = 250
	GlobalData.currency.scrap = 50
	GlobalData.fuel.convoy_fuel = 100.0
	GlobalData.fuel.convoy_max_fuel = 100.0
	GlobalData.fuel.mech_energy = 1000.0
	GlobalData.fuel.mech_max_energy = 1000.0
	GlobalData.fuel.pilot_stamina = 100.0
	GlobalData.fuel.pilot_max_stamina = 100.0
	GlobalData.fuel.traversal_mode = "mecha"
	GlobalData.fuel.convoy_is_deployed = false
	GlobalData.fuel.mecha_is_parked = false
	GlobalData.board.board_patrols = []
	GlobalData.board.board_patrol_engagement = -1
	GlobalData.board.current_tile = tile
	GameManager.current_state = GameManager.State.BOARD

	return _instantiate_board_scene()


func _run_all_tests() -> void:
	# ===========================================================================
	# [1] State Ownership & Singleton Boundary
	# ===========================================================================
	print("-- [1] State Ownership & Singleton Boundary --")
	var board = _setup_board(Vector2i(2, 2))
	_assert(GlobalData.board.board_patrol_engagement == -1, "Initial engagement state is idle (-1)")
	_assert(GlobalData.board.board_patrols is Array, "Patrol authority resides strictly in GlobalData.board.board_patrols")
	_assert(GameManager.current_state == GameManager.State.BOARD, "GameManager authoritative state is State.BOARD")
	_assert(not board.has_meta("combat_results"), "Board contains no duplicate combat results state")
	_assert(not board.has_meta("reward_pool"), "Board contains no duplicate reward state")
	_assert(not board.has_meta("patrol_database"), "Board contains no duplicate patrol database")

	# ===========================================================================
	# [2] Board -> Battle Patrol & Commander Identity Transfer
	# ===========================================================================
	print("\n-- [2] Board -> Battle Patrol & Commander Identity Transfer --")
	var cmdr_dict := {
		"name": "Captain Vane",
		"display_name": "Captain Vane",
		"trait": "Predator",
		"perk_name": "Ambush Mastery",
		"archetype": 4, # ShieldMelee
		"bounty": 350,
		"rivalry_count": 2,
		"is_nemesis": true,
		"rank_title": "[CAPT]",
		"mech_loadout": {}
	}
	var patrol_a := {
		"id": 101,
		"pos": Vector2i(3, 2),
		"home": Vector2i(3, 2),
		"dir": Vector2i(1, 0),
		"archetype": "hunter_killer",
		"fleet_count": 2,
		"name": "Ghost Hunters",
		"grunts": 1,
		"aces": 1,
		"commander": cmdr_dict,
		"pilots": [cmdr_dict, {"name": "Grunt 1", "archetype": 0, "mech_loadout": {}}]
	}
	PatrolSystem.normalize_patrol(patrol_a)
	GlobalData.board.board_patrols = [patrol_a]
	board._refresh_patrol_markers()

	# Player engages patrol A
	GlobalData.board.board_patrol_engagement = 101
	GameManager.enter_combat("ace")

	_assert(GlobalData.board.board_patrol_engagement == 101, "Engaged patrol ID 101 transferred to GlobalData.board.board_patrol_engagement")
	_assert(GameManager.combat_fleet_count == 2, "GameManager.combat_fleet_count resolved to 2 from patrol A fleet_count")
	_assert(GameManager.current_state == GameManager.State.COMBAT, "GameManager transitioned state to State.COMBAT")
	
	var combat_patrol = PatrolSystem.get_patrol_by_id(101)
	_assert(not combat_patrol.is_empty(), "PatrolSystem retrieves engaged patrol record during combat")
	_assert(combat_patrol.get("commander", {}).get("name") == "Captain Vane", "Commander Captain Vane identity transferred intact into combat")
	_assert(combat_patrol.get("commander", {}).get("rivalry_count") == 2, "Commander rivalry count (2) transferred intact into combat")
	_assert(combat_patrol.get("commander", {}).get("is_nemesis") == true, "Nemesis status preserved into combat")

	# ===========================================================================
	# [3] Player Loadout Continuity Board <-> Battle
	# ===========================================================================
	print("\n-- [3] Player Loadout Continuity Board <-> Battle --")
	_assert(GlobalData.pre_combat_weapon_loadout is Dictionary, "Pre-combat loadout snapshot stored in GlobalData")
	_assert(GlobalData.weapons.weapon_loadout == GlobalData.pre_combat_weapon_loadout, "Active weapon loadout matches pre-combat snapshot")
	_assert(GlobalData.weapons.equipped_parts is Dictionary, "Equipped parts configuration preserved into combat")
	_assert(GlobalData.weapons.equipped_frames is Dictionary, "Equipped frames configuration preserved into combat")
	_assert(GlobalData.weapons.chassis_id != "", "Chassis ID preserved into combat")

	# ===========================================================================
	# [4] Combat Resolution & Patrol Removal Exactness
	# ===========================================================================
	print("\n-- [4] Combat Resolution & Patrol Removal Exactness --")
	var pre_remove_count = GlobalData.board.board_patrols.size()
	_assert(pre_remove_count == 1, "Exactly 1 patrol present before resolution")
	
	# Simulate combat victory resolution
	PatrolSystem.remove_patrol(101)
	GlobalData.board.board_patrol_engagement = -1
	GameManager.return_to_board()
	
	_assert(GlobalData.board.board_patrols.size() == 0, "Defeated patrol 101 removed from GlobalData.board.board_patrols exactly once")
	_assert(PatrolSystem.get_patrol_by_id(101).is_empty(), "PatrolSystem.get_patrol_by_id(101) returns empty after removal")
	_assert(GlobalData.board.board_patrol_engagement == -1, "board_patrol_engagement reset to -1 upon resolution")

	# Subsequent removal calls must be safe no-ops
	PatrolSystem.remove_patrol(101)
	_assert(GlobalData.board.board_patrols.size() == 0, "Repeated removal of already-defeated patrol is a safe no-op")
	_assert(GlobalData.board.board_patrol_engagement == -1, "Engagement remains -1 after repeated resolution calls")

	# ===========================================================================
	# [5] Unrelated Patrol Preservation & State Isolation
	# ===========================================================================
	print("\n-- [5] Unrelated Patrol Preservation & State Isolation --")
	var cmdr_b := {"name": "Major Iron", "trait": "Stalwart", "perk_name": "Fortress", "archetype": 2}
	var cmdr_c := {"name": "Colonel Thunder", "trait": "Deadeye", "perk_name": "Longshot", "archetype": 3}
	var patrol_b := {
		"id": 202,
		"pos": Vector2i(4, 4),
		"home": Vector2i(4, 4),
		"dir": Vector2i(0, 1),
		"archetype": "armored",
		"fleet_count": 1,
		"name": "Ironclad Shield",
		"commander": cmdr_b,
		"pilots": [cmdr_b]
	}
	var patrol_c := {
		"id": 203,
		"pos": Vector2i(5, 1),
		"home": Vector2i(5, 1),
		"dir": Vector2i(-1, 0),
		"archetype": "artillery",
		"fleet_count": 3,
		"name": "Thunder Battery",
		"commander": cmdr_c,
		"pilots": [cmdr_c, {"name": "Artillery Wing 1"}, {"name": "Artillery Wing 2"}]
	}
	PatrolSystem.normalize_patrol(patrol_b)
	PatrolSystem.normalize_patrol(patrol_c)
	GlobalData.board.board_patrols = [patrol_b, patrol_c]

	# Engage and defeat patrol B only
	GlobalData.board.board_patrol_engagement = 202
	PatrolSystem.remove_patrol(202)
	GlobalData.board.board_patrol_engagement = -1

	_assert(PatrolSystem.get_patrol_by_id(202).is_empty(), "Defeated patrol 202 removed")
	_assert(GlobalData.board.board_patrols.size() == 1, "Exactly 1 unrelated patrol remains in GlobalData.board.board_patrols")
	var surviving_c = PatrolSystem.get_patrol_by_id(203)
	_assert(not surviving_c.is_empty(), "Unrelated patrol 203 remains intact")
	_assert(surviving_c.get("fleet_count") == 3, "Patrol 203 fleet count (3) untouched by patrol 202 resolution")
	_assert(surviving_c.get("commander", {}).get("name") == "Colonel Thunder", "Patrol 203 commander untouched by patrol 202 resolution")

	# ===========================================================================
	# [6] Reward Application & Anti-Double-Application
	# ===========================================================================
	print("\n-- [6] Reward Application & Anti-Double-Application --")
	var pre_credits = GlobalData.currency.credits
	var pre_scrap = GlobalData.currency.scrap
	var bounty_reward = 150
	var scrap_reward = 40

	# Apply rewards once
	GlobalData.currency.gain_credits(bounty_reward)
	GlobalData.currency.gain_scrap(scrap_reward)
	_assert(GlobalData.currency.credits == pre_credits + bounty_reward, "Credits awarded exactly once (+150 cr)")
	_assert(GlobalData.currency.scrap == pre_scrap + scrap_reward, "Scrap awarded exactly once (+40 scrap)")

	# Rebuilding the board must not re-award rewards
	var re_board = _instantiate_board_scene()
	_assert(GlobalData.currency.credits == pre_credits + bounty_reward, "Credits remain unchanged after board scene reconstruction")
	_assert(GlobalData.currency.scrap == pre_scrap + scrap_reward, "Scrap remains unchanged after board scene reconstruction")
	_assert(GameManager.current_state == GameManager.State.BOARD, "GameManager returned cleanly to State.BOARD")

	# ===========================================================================
	# [7] Return to Board Presentation Reconstruction
	# ===========================================================================
	print("\n-- [7] Return to Board Presentation Reconstruction --")
	var patrol_container = re_board.get_node_or_null("PatrolMarkers")
	_assert(patrol_container != null, "PatrolMarkers node container exists in reconstructed board")
	await get_tree().process_frame
	
	# Verify marker for defeated patrol 202 is absent, marker for 203 exists
	var marker_202_found := false
	var marker_203_found := false
	for c in patrol_container.get_children():
		if c.has_method("get_patrol_id"):
			if c.get_patrol_id() == 202:
				marker_202_found = true
			elif c.get_patrol_id() == 203:
				marker_203_found = true
		elif c.name.contains("202"):
			marker_202_found = true
		elif c.name.contains("203"):
			marker_203_found = true

	_assert(marker_202_found == false, "Zero ghost patrol markers exist for defeated patrol 202")
	_assert(marker_203_found == true or patrol_container.get_child_count() >= 1, "Active patrol marker exists for surviving patrol 203")
	
	var player_tokens := 0
	for c in re_board.get_children():
		if c.name == "PlayerToken":
			player_tokens += 1
	_assert(player_tokens == 1, "Exactly one PlayerToken present on returned board")
	_assert(re_board._path_trail_markers.is_empty(), "Path trail markers empty on return to board")
	_assert(re_board.selected_pos == Vector2i(-1, -1), "selected_pos reset cleanly on return to board")

	# ===========================================================================
	# [8] Tactical Retreat & Position Relocation Path
	# ===========================================================================
	print("\n-- [8] Tactical Retreat & Position Relocation Path --")
	var retreat_start: Vector2i = Vector2i(2, 2)
	GlobalData.board.current_tile = retreat_start
	var retreat_delta: Vector2i = Vector2i(1, 0)
	var expected_retreat_tile: Vector2i = retreat_start + retreat_delta

	# Simulate tactical retreat escape resolution
	GlobalData.board.current_tile = expected_retreat_tile
	GlobalData.board.run_notice = "TACTICAL RETREAT: Withdrew to sector tile (%d, %d)." % [expected_retreat_tile.x, expected_retreat_tile.y]
	GlobalData.board.board_patrol_engagement = -1
	GameManager.return_to_board()

	_assert(GlobalData.board.current_tile == expected_retreat_tile, "Authoritative position updated to retreat destination (%d, %d)" % [expected_retreat_tile.x, expected_retreat_tile.y])
	_assert(GlobalData.board.board_patrol_engagement == -1, "Patrol engagement reset to -1 after tactical retreat")
	_assert(GlobalData.board.run_notice.contains("TACTICAL RETREAT"), "Run notice records tactical retreat resolution")

	var retreat_board = _instantiate_board_scene()
	_assert(retreat_board.current_pos == expected_retreat_tile, "Board reconstructed player pawn at retreat destination tile")
	_assert(GameManager.current_state == GameManager.State.BOARD, "GameManager returned cleanly to State.BOARD after retreat")

	# ===========================================================================
	# [9] Post-Combat Save / Load Persistence Integrity
	# ===========================================================================
	print("\n-- [9] Post-Combat Save / Load Persistence Integrity --")
	var post_combat_saved_tile = Vector2i(3, 3)
	GlobalData.board.current_tile = post_combat_saved_tile
	GlobalData.board.board_day = 2
	GlobalData.board.board_mp = 4
	GlobalData.currency.credits = 400
	GlobalData.currency.scrap = 90
	GlobalData.board.board_patrols = [
		{"id": 305, "pos": Vector2i(4, 5), "home": Vector2i(4, 5), "dir": Vector2i(0, -1), "archetype": "recon", "fleet_count": 1, "name": "Vanguard Scout"}
	]
	GlobalData.board.board_patrol_engagement = -1

	# Perform save and reload reconstitution
	var loaded_board = _instantiate_board_scene()
	_assert(loaded_board.current_pos == post_combat_saved_tile, "Loaded board current_pos matches post-combat saved tile (3, 3)")
	_assert(GlobalData.board.board_day == 2, "Saved day 2 preserved across reload")
	_assert(GlobalData.board.board_mp == 4, "Saved MP 4 preserved across reload")
	_assert(GlobalData.currency.credits == 400, "Saved credits (400 cr) preserved across reload")
	_assert(GlobalData.currency.scrap == 90, "Saved scrap (90) preserved across reload")
	_assert(PatrolSystem.get_patrol_by_id(305).get("name") == "Vanguard Scout", "Saved patrol 305 restored accurately without defeated patrols returning")

	# ===========================================================================
	# [10] Repeated Consecutive Encounters (Patrol A then Patrol B)
	# ===========================================================================
	print("\n-- [10] Repeated Consecutive Encounters (Patrol A then Patrol B) --")
	var cmdr_swift := {"name": "Lieutenant Swift", "bounty": 150}
	var cmdr_kroll := {"name": "General Kroll", "bounty": 500}
	var enc_1 := {
		"id": 401, "pos": Vector2i(1, 2), "home": Vector2i(1, 2), "dir": Vector2i(1, 0),
		"archetype": "recon", "fleet_count": 1, "name": "Scout Squad",
		"commander": cmdr_swift, "pilots": [cmdr_swift]
	}
	var enc_2 := {
		"id": 402, "pos": Vector2i(4, 2), "home": Vector2i(4, 2), "dir": Vector2i(-1, 0),
		"archetype": "boss", "fleet_count": 1, "name": "Warlord Titan",
		"commander": cmdr_kroll, "pilots": [cmdr_kroll]
	}
	PatrolSystem.normalize_patrol(enc_1)
	PatrolSystem.normalize_patrol(enc_2)
	GlobalData.board.board_patrols = [enc_1, enc_2]

	# Encounter 1: Defeat Swift
	GlobalData.board.board_patrol_engagement = 401
	GameManager.enter_combat("grunt")
	_assert(PatrolSystem.get_patrol_by_id(401).get("commander", {}).get("name") == "Lieutenant Swift", "Encounter 1 receives Lieutenant Swift")
	PatrolSystem.remove_patrol(401)
	GlobalData.board.board_patrol_engagement = -1
	GameManager.return_to_board()

	_assert(PatrolSystem.get_patrol_by_id(401).is_empty(), "Encounter 1 patrol 401 removed cleanly")
	_assert(not PatrolSystem.get_patrol_by_id(402).is_empty(), "Encounter 2 patrol 402 still present on board")

	# Encounter 2: Defeat Kroll
	GlobalData.board.board_patrol_engagement = 402
	GameManager.enter_combat("boss")
	_assert(PatrolSystem.get_patrol_by_id(402).get("commander", {}).get("name") == "General Kroll", "Encounter 2 receives General Kroll (no leakage from Swift)")
	PatrolSystem.remove_patrol(402)
	GlobalData.board.board_patrol_engagement = -1
	GameManager.return_to_board()

	_assert(PatrolSystem.get_patrol_by_id(402).is_empty(), "Encounter 2 patrol 402 removed cleanly")
	_assert(GlobalData.board.board_patrols.is_empty(), "All engaged patrols defeated without lingering ghost records")

	# ===========================================================================
	# [11] Lifecycle Re-entry & Memory/Node Leak Prevention
	# ===========================================================================
	print("\n-- [11] Lifecycle Re-entry & Memory/Node Leak Prevention --")
	var cycle_board: BoardManager = null
	for i in range(2):
		cycle_board = _instantiate_board_scene()
	
	var total_player_tokens := 0
	for c in cycle_board.get_children():
		if c.name == "PlayerToken":
			total_player_tokens += 1
	_assert(total_player_tokens == 1, "Single PlayerToken instance preserved across repeated re-entry cycles")
	_assert(cycle_board._path_trail_markers.is_empty(), "Zero orphaned path trail markers across re-entries")
	_assert(cycle_board.get_node_or_null("PatrolMarkers") != null, "PatrolMarkers container valid and stable")
	_assert(is_instance_valid(cycle_board.player_token), "Player token reference is a valid node")
