extends Node
## FRAME SET SYSTEM VERIFICATION (PHASE 2B-2)
## Validates the authoritative FrameSetSystem:
## 1. Empty frame configuration
## 2. One-piece set (below minimum threshold)
## 3. Two-piece threshold activation
## 4. Four-piece threshold activation
## 5. Six-piece threshold activation
## 6. Non-standard threshold support (e.g. 3 / 5)
## 7. Multiple simultaneous sets
## 8. Missing frame slots
## 9. Unknown set ID handling
## 10. No set bonus definition handling
## 11. Armor not counted as frame piece
## 12. Backpack not counted as frame piece
## 13. Generator not counted as frame piece
## 14. Modules not counted as frame piece
## 15. Weapons not counted as frame piece
## 16. Base frame stats are not mutated
## 17. Recalculating bonuses does not stack them
## 18. Save/load reconstructs set state
## 19. Highest-tier capability unlock reporting
## 20. Existing frame compatibility remains intact

var _fails: int = 0
var _checks: int = 0

const FrameSetSys = preload("res://scripts/systems/frame_set_system.gd")
const FrameSys = preload("res://scripts/systems/frame_system.gd")
const SaveGameIO = preload("res://scripts/systems/save_game_io.gd")


func _check(cond: bool, test_name: String) -> void:
	_checks += 1
	if cond:
		print("FRAME_SET_OK: " + test_name)
	else:
		_fails += 1
		printerr("FRAME_SET_FAIL: " + test_name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	print("\n=== STARTING FRAME SET SYSTEM VERIFICATION (PHASE 2B-2) ===")
	_test_empty_and_single_piece_configuration()
	_test_standard_tier_thresholds_2_4_6()
	_test_non_standard_thresholds()
	_test_multiple_simultaneous_sets()
	_test_missing_and_unknown_sets()
	_test_non_frame_equipment_exclusion()
	_test_non_mutating_and_no_stacking_bonuses()
	_test_save_load_reconstruction()
	_test_capability_unlock_and_compatibility()

	print("\n=== FRAME SET TEST SUMMARY ===")
	print("Checks: %d, Failures: %d" % [_checks, _fails])
	if _fails == 0:
		print("ALL_FRAME_SET_TESTS_PASSED")
		get_tree().quit(0)
	else:
		printerr("FRAME_SET_TESTS_FAILED")
		get_tree().quit(1)


func _clear_equipped_frames() -> void:
	GlobalData.reset_run_data()
	for slot in GlobalData.MECHA_SLOTS:
		GlobalData.weapons.equipped_frames[slot] = {}


func _test_empty_and_single_piece_configuration() -> void:
	print("\n-- [1-2] Empty Frame Configuration & 1-Piece Set --")
	_clear_equipped_frames()

	# 1. Empty frame configuration
	var counts := FrameSetSys.get_equipped_set_counts()
	_check(counts.is_empty(), "[1a] Empty equipped_frames yields empty set counts")
	_check(FrameSetSys.get_set_piece_count("valkyrion") == 0, "[1b] Valkyrion count is 0 on empty frame")
	_check(FrameSetSys.get_active_set_tiers("valkyrion").is_empty(), "[1c] No active tiers on empty frame")
	_check(FrameSetSys.get_active_set_bonuses().is_empty(), "[1d] No active bonuses on empty frame")

	# 2. One-piece set (below minimum threshold of 2)
	GlobalData.weapons.equipped_frames["body"] = {
		"id": "frame_body_valkyrion",
		"name": "Alaya-Vijnana Core",
		"frame_set_id": "valkyrion",
		"hp": 50.0,
		"weight": 6.0
	}
	counts = FrameSetSys.get_equipped_set_counts()
	_check(counts.get("valkyrion", 0) == 1, "[2a] Valkyrion count is 1 with single body piece")
	_check(FrameSetSys.get_set_piece_count("valkyrion") == 1, "[2b] get_set_piece_count returns 1")
	_check(FrameSetSys.get_active_set_tiers("valkyrion").is_empty(), "[2c] 1 piece does not trigger 2-piece threshold")
	_check(not FrameSetSys.is_set_bonus_active("valkyrion", 2), "[2d] 2-piece bonus is not active")


func _test_standard_tier_thresholds_2_4_6() -> void:
	print("\n-- [3-5] Standard Thresholds (2, 4, 6 Pieces) --")
	_clear_equipped_frames()

	# Equip 2 Valkyrion pieces (head + body)
	GlobalData.weapons.equipped_frames["head"] = {"id": "f_h", "frame_set_id": "valkyrion"}
	GlobalData.weapons.equipped_frames["body"] = {"id": "f_b", "frame_set_id": "valkyrion"}

	# 3. Two-piece threshold
	_check(FrameSetSys.get_set_piece_count("valkyrion") == 2, "[3a] Valkyrion count is 2")
	_check(FrameSetSys.is_set_bonus_active("valkyrion", 2), "[3b] 2-piece bonus is active")
	_check(not FrameSetSys.is_set_bonus_active("valkyrion", 4), "[3c] 4-piece bonus is inactive")
	var tiers_2 := FrameSetSys.get_active_set_tiers("valkyrion")
	_check(tiers_2 == [2], "[3d] Active tiers == [2]")

	# Equip 2 more Valkyrion pieces (total 4)
	GlobalData.weapons.equipped_frames["arm_left"] = {"id": "f_al", "frame_set_id": "valkyrion"}
	GlobalData.weapons.equipped_frames["arm_right"] = {"id": "f_ar", "frame_set_id": "valkyrion"}

	# 4. Four-piece threshold
	_check(FrameSetSys.get_set_piece_count("valkyrion") == 4, "[4a] Valkyrion count is 4")
	_check(FrameSetSys.is_set_bonus_active("valkyrion", 2), "[4b] 2-piece bonus remains active")
	_check(FrameSetSys.is_set_bonus_active("valkyrion", 4), "[4c] 4-piece bonus is active")
	_check(not FrameSetSys.is_set_bonus_active("valkyrion", 6), "[4d] 6-piece bonus is inactive")
	var tiers_4 := FrameSetSys.get_active_set_tiers("valkyrion")
	_check(tiers_4 == [2, 4], "[4e] Active tiers == [2, 4]")

	# Equip remaining 2 pieces (total 6)
	GlobalData.weapons.equipped_frames["leg_left"] = {"id": "f_ll", "frame_set_id": "valkyrion"}
	GlobalData.weapons.equipped_frames["leg_right"] = {"id": "f_lr", "frame_set_id": "valkyrion"}

	# 5. Six-piece threshold
	_check(FrameSetSys.get_set_piece_count("valkyrion") == 6, "[5a] Valkyrion count is 6")
	_check(FrameSetSys.is_set_bonus_active("valkyrion", 2), "[5b] 2-piece bonus is active")
	_check(FrameSetSys.is_set_bonus_active("valkyrion", 4), "[5c] 4-piece bonus is active")
	_check(FrameSetSys.is_set_bonus_active("valkyrion", 6), "[5d] 6-piece bonus is active")
	var tiers_6 := FrameSetSys.get_active_set_tiers("valkyrion")
	_check(tiers_6 == [2, 4, 6], "[5e] Active tiers == [2, 4, 6]")


func _test_non_standard_thresholds() -> void:
	print("\n-- [6] Non-Standard Thresholds (3, 5, 6) --")
	_clear_equipped_frames()

	# Register a custom test set with non-standard thresholds: 3, 5
	FrameSetSys.register_set_definition({
		"id": "experimental_assault",
		"name": "Experimental Assault",
		"bonuses": {
			3: {
				"description": "+15 Frame HP",
				"stats": {"hp_flat": 15.0}
			},
			5: {
				"description": "+20% Movement Speed",
				"stats": {"movement_speed_mult": 1.20}
			}
		}
	})

	GlobalData.weapons.equipped_frames["head"] = {"id": "e_1", "frame_set_id": "experimental_assault"}
	GlobalData.weapons.equipped_frames["body"] = {"id": "e_2", "frame_set_id": "experimental_assault"}

	# 2 pieces -> 3-piece threshold not yet reached
	_check(FrameSetSys.get_active_set_tiers("experimental_assault").is_empty(), "[6a] 2 pieces does not activate 3-piece tier")

	# Add 3rd piece
	GlobalData.weapons.equipped_frames["arm_left"] = {"id": "e_3", "frame_set_id": "experimental_assault"}
	_check(FrameSetSys.is_set_bonus_active("experimental_assault", 3), "[6b] 3 pieces activates non-standard 3-piece tier")
	_check(not FrameSetSys.is_set_bonus_active("experimental_assault", 5), "[6c] 3 pieces does not activate 5-piece tier")

	# Add 4th and 5th piece
	GlobalData.weapons.equipped_frames["arm_right"] = {"id": "e_4", "frame_set_id": "experimental_assault"}
	GlobalData.weapons.equipped_frames["leg_left"] = {"id": "e_5", "frame_set_id": "experimental_assault"}
	var tiers_5 := FrameSetSys.get_active_set_tiers("experimental_assault")
	_check(tiers_5 == [3, 5], "[6d] 5 pieces activates [3, 5] non-standard tiers")


func _test_multiple_simultaneous_sets() -> void:
	print("\n-- [7] Multiple Simultaneous Sets (4 Valkyrion + 2 Vagrant) --")
	_clear_equipped_frames()

	# 4 Valkyrion pieces + 2 Vagrant pieces
	GlobalData.weapons.equipped_frames["head"] = {"id": "f_h", "frame_set_id": "valkyrion"}
	GlobalData.weapons.equipped_frames["body"] = {"id": "f_b", "frame_set_id": "valkyrion"}
	GlobalData.weapons.equipped_frames["arm_left"] = {"id": "f_al", "frame_set_id": "valkyrion"}
	GlobalData.weapons.equipped_frames["arm_right"] = {"id": "f_ar", "frame_set_id": "valkyrion"}
	GlobalData.weapons.equipped_frames["leg_left"] = {"id": "f_ll", "frame_set_id": "vagrant"}
	GlobalData.weapons.equipped_frames["leg_right"] = {"id": "f_lr", "frame_set_id": "vagrant"}

	var counts := FrameSetSys.get_equipped_set_counts()
	_check(counts.get("valkyrion", 0) == 4, "[7a] Valkyrion count is 4")
	_check(counts.get("vagrant", 0) == 2, "[7b] Vagrant count is 2")

	_check(FrameSetSys.is_set_bonus_active("valkyrion", 2), "[7c] Valkyrion 2-piece is active")
	_check(FrameSetSys.is_set_bonus_active("valkyrion", 4), "[7d] Valkyrion 4-piece is active")
	_check(not FrameSetSys.is_set_bonus_active("valkyrion", 6), "[7e] Valkyrion 6-piece is inactive")

	_check(FrameSetSys.is_set_bonus_active("vagrant", 2), "[7f] Vagrant 2-piece is active independently")
	_check(not FrameSetSys.is_set_bonus_active("vagrant", 4), "[7g] Vagrant 4-piece is inactive")

	var active_bonuses := FrameSetSys.get_active_set_bonuses()
	_check(active_bonuses.size() == 3, "[7h] Total active bonuses == 3 (Valkyrion 2P + 4P, Vagrant 2P)")


func _test_missing_and_unknown_sets() -> void:
	print("\n-- [8-10] Missing Slots & Unknown / Empty Set IDs --")
	_clear_equipped_frames()

	# 8. Missing frame slots (e.g. some slots completely missing from dictionary)
	GlobalData.weapons.equipped_frames = {
		"body": {"id": "f_b", "frame_set_id": "valkyrion"},
		"arm_left": {"id": "f_al", "frame_set_id": "valkyrion"},
		"leg_right": {"id": "f_lr", "frame_set_id": "valkyrion"}
	}
	var counts := FrameSetSys.get_equipped_set_counts()
	_check(counts.get("valkyrion", 0) == 3, "[8a] Handles missing slots without crashing (3 Valkyrion pieces)")
	_check(FrameSetSys.is_set_bonus_active("valkyrion", 2), "[8b] 2-piece bonus active with 3 pieces")

	# 9. Unknown set ID
	_check(FrameSetSys.get_set_piece_count("non_existent_set") == 0, "[9a] Unknown set piece count is 0")
	_check(FrameSetSys.get_active_set_tiers("non_existent_set").is_empty(), "[9b] Unknown set active tiers is empty")
	_check(FrameSetSys.get_set_definition("non_existent_set").is_empty(), "[9c] Unknown set definition returns empty dict")

	# 10. Frame with no set bonus definition registered
	GlobalData.weapons.equipped_frames["head"] = {"id": "f_custom", "frame_set_id": "unregistered_prototype"}
	_check(FrameSetSys.get_set_piece_count("unregistered_prototype") == 1, "[10a] Piece count increments even without registered definition")
	_check(FrameSetSys.get_active_set_tiers("unregistered_prototype").is_empty(), "[10b] No crashes or active tiers for unregistered definition")


func _test_non_frame_equipment_exclusion() -> void:
	print("\n-- [11-15] Set Count Excludes Non-Frame Equipment --")
	_clear_equipped_frames()

	# Equip 2 real frame pieces
	GlobalData.weapons.equipped_frames["head"] = {"id": "f_h", "frame_set_id": "standard"}
	GlobalData.weapons.equipped_frames["body"] = {"id": "f_b", "frame_set_id": "standard"}

	# Add non-frame equipment with set IDs or frame matching names
	# 11. Armor
	GlobalData.weapons.equipped_parts["body"] = {"id": "armor_body", "frame_set_id": "standard", "weight": 10.0}
	GlobalData.weapons.equipped_parts["head"] = {"id": "armor_head", "frame_set_id": "standard", "weight": 5.0}

	# 12. Backpack
	GlobalData.weapons.equipped_backpack = {"id": "cargo", "frame_set_id": "standard", "weight": 8.0}

	# 13. Generator
	GlobalData.weapons.power_core_id = "combustion"

	# 14. Modules
	GlobalData.weapons.frame_modules["body"] = ["mod_standard_1", "mod_standard_2"]

	# 15. Weapons
	GlobalData.weapons.weapon_loadout["left"] = "res://resources/mech/stock/weapon_rifle.tres"

	# Verify set count strictly reflects only the 2 frame segments
	var counts := FrameSetSys.get_equipped_set_counts()
	_check(counts.get("standard", 0) == 2, "[11-15] Frame set count strictly reflects 2 frame segments, ignoring armor/backpack/core/modules/weapons")


func _test_non_mutating_and_no_stacking_bonuses() -> void:
	print("\n-- [16-17] Non-Mutating Stat Derivation & No Stacking --")
	_clear_equipped_frames()

	# Equip 4 Standard pieces (Tier 2: +10 HP, Tier 4: +5 Carry Capacity)
	var head_dict := {"id": "frame_head_01", "frame_set_id": "standard", "hp": 20.0, "weight": 2.0}
	var body_dict := {"id": "frame_body_01", "frame_set_id": "standard", "hp": 40.0, "weight": 6.0}
	var arm_l_dict := {"id": "frame_arm_left_01", "frame_set_id": "standard", "hp": 15.0, "weight": 3.0}
	var arm_r_dict := {"id": "frame_arm_right_01", "frame_set_id": "standard", "hp": 15.0, "weight": 3.0}

	GlobalData.weapons.equipped_frames["head"] = head_dict
	GlobalData.weapons.equipped_frames["body"] = body_dict
	GlobalData.weapons.equipped_frames["arm_left"] = arm_l_dict
	GlobalData.weapons.equipped_frames["arm_right"] = arm_r_dict

	# 16. Base frame stats are not mutated
	var base_hp_before: float = head_dict["hp"]
	var base_stats := {
		"hp": 90.0,
		"carry_capacity": 40.0,
		"recoil_resistance": 0.10
	}

	var derived_1 := FrameSetSys.apply_set_bonuses_to_stats(base_stats)
	_check(head_dict["hp"] == base_hp_before, "[16a] Base frame dictionary was not mutated")
	_check(base_stats["hp"] == 90.0, "[16b] Base stats dictionary was not mutated")
	_check(derived_1["hp"] == 100.0, "[16c] Derived HP has +10 HP flat bonus (90 + 10 = 100)")
	_check(derived_1["carry_capacity"] == 45.0, "[16d] Derived carry capacity has +5 kg bonus (40 + 5 = 45)")

	# 17. Recalculating bonuses does not stack them
	var derived_2 := FrameSetSys.apply_set_bonuses_to_stats(base_stats)
	var derived_3 := FrameSetSys.apply_set_bonuses_to_stats(base_stats)
	_check(derived_2["hp"] == 100.0, "[17a] 2nd calculation maintains exact 100.0 HP (no stacking)")
	_check(derived_3["hp"] == 100.0, "[17b] 3rd calculation maintains exact 100.0 HP (no stacking)")
	_check(derived_3["carry_capacity"] == 45.0, "[17c] 3rd calculation maintains exact 45.0 carry capacity")


func _test_save_load_reconstruction() -> void:
	print("\n-- [18] Save/Load Reconstructs Set State --")
	_clear_equipped_frames()

	# Equip 4 Valkyrion frames and 2 Vagrant frames
	for slot in ["head", "body", "arm_left", "arm_right"]:
		GlobalData.weapons.equipped_frames[slot] = {
			"id": "frame_" + slot + "_02",
			"name": "Alaya-Vijnana " + slot,
			"frame_set_id": "valkyrion"
		}
	for slot in ["leg_left", "leg_right"]:
		GlobalData.weapons.equipped_frames[slot] = {
			"id": "frame_" + slot + "_vagrant",
			"name": "Scrap Pilgrim " + slot,
			"frame_set_id": "vagrant"
		}

	# Serialize via SaveGameIO
	var serialized := SaveGameIO.serialize_frames()
	_check(serialized.size() == 6, "[18a] All 6 frames serialized")

	# Clear equipped frames to simulate fresh start
	_clear_equipped_frames()
	_check(FrameSetSys.get_equipped_set_counts().is_empty(), "[18b] Cleared equipped frames before restore")

	# Restore through SaveGameIO resolution
	for slot in serialized:
		GlobalData.weapons.equipped_frames[slot] = SaveGameIO.resolve_frame_value(serialized[slot])

	# Verify set state is reconstructed identically
	var restored_counts := FrameSetSys.get_equipped_set_counts()
	_check(restored_counts.get("valkyrion", 0) == 4, "[18c] Restored Valkyrion count == 4")
	_check(restored_counts.get("vagrant", 0) == 2, "[18d] Restored Vagrant count == 2")
	_check(FrameSetSys.is_set_bonus_active("valkyrion", 4), "[18e] Restored Valkyrion 4P bonus is active")
	_check(FrameSetSys.is_set_bonus_active("vagrant", 2), "[18f] Restored Vagrant 2P bonus is active")


func _test_capability_unlock_and_compatibility() -> void:
	print("\n-- [19-20] Capability Unlocks & Frame Compatibility --")
	_clear_equipped_frames()

	# 19. Highest-tier capability unlock reporting (6 pieces of Valkyrion)
	for slot in GlobalData.MECHA_SLOTS:
		GlobalData.weapons.equipped_frames[slot] = {
			"id": "frame_" + slot + "_02",
			"frame_set_id": "valkyrion"
		}

	var caps := FrameSetSys.get_active_capabilities()
	_check(caps.size() >= 1, "[19a] Active capabilities list is non-empty")
	_check("valkyrion_overdrive" in caps, "[19b] 'valkyrion_overdrive' capability unlocked and reported at 6 pieces")

	# 20. Existing frame capability queries remain intact
	var total_hp := FrameSys.get_total_frame_hp()
	_check(total_hp > 0.0, "[20a] FrameSystem get_total_frame_hp operates correctly")

	var total_wt := FrameSys.get_total_frame_weight()
	_check(total_wt > 0.0, "[20b] FrameSystem get_total_frame_weight operates correctly")

	var ui_summary := FrameSetSys.format_set_summary_bbcode()
	_check(ui_summary.contains("Valkyrion"), "[20c] UI BBCode formatting summary includes Valkyrion")
	_check(ui_summary.contains("✓ 6-Piece"), "[20d] UI BBCode summary shows active 6-Piece tier")
