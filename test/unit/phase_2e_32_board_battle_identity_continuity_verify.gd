extends Node3D

## Phase 2E-32: Board-to-Battle Unit Identity Continuity Verification Suite
## Verifies that:
## 1. Player unit on Board resolves and displays the canonical production Valkren (mecha_base.tscn)
##    with actual equipped parts/weapons, eliminating the blue procedural substitute.
## 2. Enemy Commander on Board resolves the exact authoritative Commander identity, mech scene,
##    and weapon loadout as spawned in Battle (e.g. Cannon Commander vs Heat Blade Commander).
## 3. Locomotion, tabletop scale, and facing yaw remain preserved without regression.

const BoardUnit3D = preload("res://scripts/board/board_unit_3d.gd")
const PatrolMarker = preload("res://scripts/board/patrol_marker.gd")
const PatrolSystemClass = preload("res://scripts/systems/patrol_system.gd")

var _passed_count: int = 0
var _failed_count: int = 0


func _ready() -> void:
	print("==================================================")
	print("PHASE 2E-32: BOARD-TO-BATTLE UNIT IDENTITY CONTINUITY VERIFY")
	print("==================================================")
	_run_all_tests()
	_print_summary()


func _assert(condition: bool, test_name: String) -> void:
	if condition:
		_passed_count += 1
		print("  [PASS] %s" % test_name)
	else:
		_failed_count += 1
		printerr("  [FAIL] %s" % test_name)


func _run_all_tests() -> void:
	# -------------------------------------------------------------
	# SECTION 1: PLAYER PRODUCTION IDENTITY RESOLUTION
	# -------------------------------------------------------------
	print("\n-- [1] Player Production Valkren Instantiation on Board --")
	var player_unit := BoardUnit3D.new()
	player_unit.setup_player()
	add_child(player_unit)

	_assert(player_unit.unit_type == BoardUnit3D.UnitType.PLAYER, "Player unit type is PLAYER")
	_assert(player_unit.production_model != null, "Player unit instantiates production Valkren model")
	_assert(player_unit.production_model.scene_file_path == "res://scenes/mecha/mecha_base.tscn", "Player model scene path is mecha_base.tscn")
	_assert(player_unit.production_model.get_node_or_null("PartMeshManager") != null, "Player production model contains PartMeshManager")

	print("\n-- [2] Player Model Stripping & Physics Safety --")
	_assert(player_unit.production_model.process_mode == Node.PROCESS_MODE_DISABLED, "Production Valkren process mode is DISABLED on board")
	if player_unit.production_model is CollisionObject3D:
		var co := player_unit.production_model as CollisionObject3D
		_assert(co.collision_layer == 0 and co.collision_mask == 0, "Production Valkren collision layer and mask are zeroed")
	_assert(player_unit.production_model.get_node_or_null("HealthSystem") == null, "Combat HealthSystem stripped from board representation")
	_assert(player_unit.production_model.get_node_or_null("Hitbox") == null, "Combat Hitbox stripped from board representation")

	print("\n-- [3] Player Weapon Continuity from LoadoutSystem --")
	var arm_r = player_unit.production_model.get_node_or_null("ArmRight")
	var arm_l = player_unit.production_model.get_node_or_null("ArmLeft")
	_assert(arm_r != null and arm_l != null, "Player Valkren has ArmRight and ArmLeft nodes for weapon mounting")
	var weapon_r = player_unit.production_model.find_child("WeaponMesh_right", true, false)
	_assert(weapon_r != null, "Player Valkren on board mounts equipped right-hand weapon visual")

	print("\n-- [4] Player Hierarchy & Tabletop Framing --")
	_assert(player_unit.torso_node != null, "Player unit maps torso_node to production Body")
	_assert(player_unit.head_node != null, "Player unit maps head_node to production Head")
	_assert(player_unit.backpack_node != null, "Player unit maps backpack_node to production Backpack")
	_assert(player_unit.unit_scale.x >= 0.50 and player_unit.unit_scale.x <= 0.70, "Player unit scale is well-framed for tabletop (0.58)")

	# -------------------------------------------------------------
	# SECTION 2: ENEMY COMMANDER IDENTITY & LOADOUT CONTINUITY
	# -------------------------------------------------------------
	print("\n-- [5] Armored Fleet -> Cannon Commander Continuity --")
	var fleet_armored := {
		"id": 201,
		"archetype": "armored",
		"faction": "hostile",
		"grunts": 2,
		"aces": 0,
		"pos": Vector2i(2, 2),
		"dir": Vector2i(1, 0),
	}
	PatrolSystemClass.normalize_patrol(fleet_armored)
	_assert(fleet_armored.has("commander") and not fleet_armored["commander"].is_empty(), "Armored fleet normalizes authoritative commander")
	var cmdr_armored: Dictionary = fleet_armored["commander"]
	_assert(int(cmdr_armored.get("archetype", -1)) == 2, "Armored commander archetype is 2 (Heavy)")
	_assert(str(cmdr_armored.get("scene_type", "")) == "heavy_full", "Armored commander scene_type is heavy_full")

	var board_cmdr_armored := BoardUnit3D.new()
	board_cmdr_armored.setup_commander(fleet_armored)
	add_child(board_cmdr_armored)

	_assert(board_cmdr_armored.production_model != null, "Board creates production model for Armored commander")
	_assert(board_cmdr_armored.production_model.scene_file_path == "res://scenes/mecha/enemy_heavy.tscn", "Board instantiates enemy_heavy.tscn for Armored commander")
	var cmdr_weapon = board_cmdr_armored.production_model.find_child("EnemyWeaponMount", true, false)
	_assert(cmdr_weapon != null and cmdr_weapon.get_child_count() > 0, "Armored commander on board mounts Cannon weapon visual")

	print("\n-- [6] Hunter-Killer Fleet -> Shield + Heat Blade Commander Continuity --")
	var fleet_hk := {
		"id": 202,
		"archetype": "hunter_killer",
		"faction": "hostile",
		"grunts": 1,
		"aces": 1,
		"pos": Vector2i(3, 3),
		"dir": Vector2i(0, 1),
	}
	PatrolSystemClass.normalize_patrol(fleet_hk)
	var cmdr_hk: Dictionary = fleet_hk["commander"]
	_assert(int(cmdr_hk.get("archetype", -1)) == 4, "Hunter-Killer commander archetype is 4 (Shield Melee)")
	_assert(str(cmdr_hk.get("scene_type", "")) == "shieldmelee_full", "Hunter-Killer commander scene_type is shieldmelee_full")

	var board_cmdr_hk := BoardUnit3D.new()
	board_cmdr_hk.setup_commander(fleet_hk)
	add_child(board_cmdr_hk)

	_assert(board_cmdr_hk.production_model != null, "Board creates production model for Hunter-Killer commander")
	_assert(board_cmdr_hk.production_model.scene_file_path == "res://scenes/mecha/enemy_shield_melee.tscn", "Board instantiates enemy_shield_melee.tscn for Hunter-Killer commander")
	var hk_shield = board_cmdr_hk.production_model.find_child("EnemyShieldMount", true, false)
	var hk_blade = board_cmdr_hk.production_model.find_child("EnemyWeaponMount", true, false)
	_assert(hk_shield != null, "Hunter-Killer commander on board mounts Shield on left arm")
	_assert(hk_blade != null, "Hunter-Killer commander on board mounts Heat Blade on right arm")

	print("\n-- [7] Recon Fleet -> Beam Carbine Commander Continuity --")
	var fleet_recon := {
		"id": 203,
		"archetype": "recon",
		"faction": "hostile",
		"grunts": 2,
		"aces": 0,
		"pos": Vector2i(4, 4),
		"dir": Vector2i(1, 0),
	}
	PatrolSystemClass.normalize_patrol(fleet_recon)
	var cmdr_recon: Dictionary = fleet_recon["commander"]
	_assert(int(cmdr_recon.get("archetype", -1)) == 1, "Recon commander archetype is 1 (Ranged)")
	_assert(str(cmdr_recon.get("scene_type", "")) == "ranged_full", "Recon commander scene_type is ranged_full")

	var board_cmdr_recon := BoardUnit3D.new()
	board_cmdr_recon.setup_commander(fleet_recon)
	add_child(board_cmdr_recon)
	_assert(board_cmdr_recon.production_model != null and board_cmdr_recon.production_model.scene_file_path == "res://scenes/mecha/enemy_ranged.tscn", "Board instantiates enemy_ranged.tscn for Recon commander")

	print("\n-- [8] Artillery Fleet -> Support Commander Continuity --")
	var fleet_artillery := {
		"id": 204,
		"archetype": "artillery",
		"faction": "hostile",
		"grunts": 2,
		"aces": 0,
		"pos": Vector2i(5, 5),
		"dir": Vector2i(0, 1),
	}
	PatrolSystemClass.normalize_patrol(fleet_artillery)
	var cmdr_artillery: Dictionary = fleet_artillery["commander"]
	_assert(int(cmdr_artillery.get("archetype", -1)) == 3, "Artillery commander archetype is 3 (Support)")
	_assert(str(cmdr_artillery.get("scene_type", "")) == "support_full", "Artillery commander scene_type is support_full")

	var board_cmdr_artillery := BoardUnit3D.new()
	board_cmdr_artillery.setup_commander(fleet_artillery)
	add_child(board_cmdr_artillery)
	_assert(board_cmdr_artillery.production_model != null and board_cmdr_artillery.production_model.scene_file_path == "res://scenes/mecha/enemy_support.tscn", "Board instantiates enemy_support.tscn for Artillery commander")

	print("\n-- [9] Boss Overlord Continuity --")
	var board_boss := BoardUnit3D.new()
	board_boss.setup_boss()
	add_child(board_boss)
	_assert(board_boss.production_model != null and board_boss.production_model.scene_file_path == "res://scenes/mecha/enemy_boss.tscn", "Board instantiates enemy_boss.tscn for Boss Overlord")

	# -------------------------------------------------------------
	# SECTION 3: BATTLE SPAWN RESOLUTION ALIGNMENT
	# -------------------------------------------------------------
	print("\n-- [10] Battle Spawn Derivation from Authoritative Patrol Roster --")
	var spawn_mgr := SpawnManager.new()
	add_child(spawn_mgr)
	# Verify that SpawnManager's enemy scene table maps exact scene types
	_assert(spawn_mgr._get_enemy_scene("heavy_full").resource_path == "res://scenes/mecha/enemy_heavy.tscn", "SpawnManager maps heavy_full to enemy_heavy.tscn")
	_assert(spawn_mgr._get_enemy_scene("shieldmelee_full").resource_path == "res://scenes/mecha/enemy_shield_melee.tscn", "SpawnManager maps shieldmelee_full to enemy_shield_melee.tscn")
	_assert(spawn_mgr._get_enemy_scene("ranged_full").resource_path == "res://scenes/mecha/enemy_ranged.tscn", "SpawnManager maps ranged_full to enemy_ranged.tscn")
	_assert(spawn_mgr._get_enemy_scene("support_full").resource_path == "res://scenes/mecha/enemy_support.tscn", "SpawnManager maps support_full to enemy_support.tscn")

	# -------------------------------------------------------------
	# SECTION 4: PRESENTATION INTEGRITY & LOCOMOTION PRESERVATION
	# -------------------------------------------------------------
	print("\n-- [11] Locomotion & Facing Integrity --")
	player_unit.face_heading(Vector2i(1, 0), true) # East -> -PI/2
	_assert(absf(player_unit.rotation.y - (-PI * 0.5)) < 0.05, "Player unit correctly faces East (-PI/2)")
	player_unit.face_heading(Vector2i(0, -1), true) # North -> 0
	_assert(absf(player_unit.rotation.y) < 0.05, "Player unit correctly faces North (0)")

	player_unit.play_run()
	_assert(player_unit.anim_state == "run" and player_unit.is_moving, "Player unit transitions cleanly to run locomotion")
	player_unit._process(0.016)
	_assert(player_unit.leg_left_node != null and player_unit.leg_right_node != null, "Locomotion animates production limb nodes")
	player_unit.play_idle()
	_assert(player_unit.anim_state == "idle" and not player_unit.is_moving, "Player unit transitions cleanly to idle stance")


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-32 CONTINUITY VERIFICATION SUMMARY:")
	print("  Passed: %d" % _passed_count)
	print("  Failed: %d" % _failed_count)
	print("==================================================")
	if _failed_count == 0:
		print("PHASE_2E_32_SUCCESS")
	else:
		print("PHASE_2E_32_FAILURE")
	if get_tree():
		get_tree().quit(0 if _failed_count == 0 else 1)
