extends Node
## TECHNOLOGY UI EQUIPMENT GATE VERIFICATION (Phase 2E-4D)
##
## Validates the Hangar UI technology integration:
## 1. Technology locked -> equip disabled, detail panel reflects lock
## 2. Technology usable + compatible -> equip enabled
## 3. Technology usable + incompatible -> equip disabled, frame incompatible (NOT tech lock)
## 4. Legacy technology-neutral item -> existing behavior, no tech lock
## 5. Generic Jammer synthetic item -> generic UI path
## 6. Generic Satellite Cannon synthetic item -> generic UI path
## 7. Final equip request revalidates authorization (stale UI safety)
## 8. Failed equip does not mutate loadout
## 9. UI refreshes after authorization state changes
## 10. Armor and weapon follow equivalent rules

var _checks := 0
var _fails := 0

const TechSys = preload("res://scripts/systems/technology_system.gd")
const FrameSys = preload("res://scripts/systems/frame_system.gd")
const LoadoutSys = preload("res://scripts/systems/loadout_system.gd")
const ArmorSys = preload("res://scripts/systems/armor_system.gd")


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("UI_GATE_OK: " + msg)
	else:
		_fails += 1
		printerr("UI_GATE_FAIL: " + msg)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	print("=== STARTING TECHNOLOGY UI INTEGRATION & EQUIPMENT GATE VERIFY (PHASE 2E-4D) ===")

	TechSys.init_catalog_if_needed()
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	await _test_technology_locked_state()
	await _test_technology_usable_incompatible_state()
	await _test_technology_usable_compatible_state()
	await _test_legacy_item_behavior()
	await _test_synthetic_future_tech_generic()
	await _test_final_request_revalidation_and_invariance()
	await _test_armor_weapon_parity()
	await _test_save_load_ui_reflection()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _fails])
	if _fails == 0:
		print("PHASE_2E_4D_SUCCESS")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_4D_FAILURE")
		get_tree().quit(1)


func _make_hangar() -> Node:
	var hangar_scene: PackedScene = load("res://scenes/ui/hangar_scene.tscn")
	var hangar = hangar_scene.instantiate()
	add_child(hangar)
	return hangar


# -----------------------------------------------------------------------------
# 1. TECHNOLOGY LOCKED STATE
# -----------------------------------------------------------------------------
func _test_technology_locked_state() -> void:
	print("\n-- [1] Technology Locked State --")
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	var tech_id := "tech_beam_weaponry"
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.UNKNOWN, "[1a] Tech starts UNKNOWN")

	var locked_weapon_uid := "uid_locked_gun"
	var locked_inv := {
		"uid": locked_weapon_uid,
		"name": "Experimental Beam Cannon",
		"tech_id": tech_id,
		"path": "res://resources/mech/stock/weapon_beam_rifle.tres",
		"durability": 1.0,
		"type": "Weapon"
	}
	GlobalData.weapons.weapon_inventory.append(locked_inv)

	var hangar = _make_hangar()
	await get_tree().process_frame

	hangar.selected_slot = "weapon_right"
	hangar.part_list_panel.populate("weapon_right")

	var row := -1
	for i in range(hangar.part_list_panel.controller.visible_weapon_indices.size()):
		var idx: int = hangar.part_list_panel.controller.visible_weapon_indices[i]
		if str(GlobalData.weapons.weapon_inventory[idx].get("uid", "")) == locked_weapon_uid:
			row = i
			break
	_check(row >= 0, "[1b] Locked weapon row present in list")

	if row >= 0:
		var item_text: String = hangar.part_item_list.get_item_text(row)
		_check(item_text.contains("[TECH LOCKED]"), "[1c] Item row displays [TECH LOCKED] tag")

		hangar.part_list_panel.on_item_selected(row)

		var stats_text: String = hangar.stats_label.text
		_check(stats_text.contains("NOT USABLE"), "[1d] Detail panel states NOT USABLE")
		_check(stats_text.contains("Technology not authorized"), "[1e] Detail panel states Technology not authorized")

		_check(hangar.equip_button.disabled == true, "[1f] Equip button is disabled")
		_check(hangar.equip_button.text.contains("TECH LOCKED"), "[1g] Equip button text indicates TECH LOCKED")

		var loadout_before: String = str(GlobalData.weapons.weapon_loadout.get("right", ""))
		hangar.equip_panel.on_equip_pressed()
		var loadout_after: String = str(GlobalData.weapons.weapon_loadout.get("right", ""))
		_check(loadout_before == loadout_after, "[1h] Failed equip does not mutate right hand loadout")
		_check(hangar.status_message_label.text.contains("not authorized"), "[1i] Status message reports unauthorized technology")

	hangar.queue_free()


# -----------------------------------------------------------------------------
# 2. TECHNOLOGY USABLE BUT PHYSICALLY INCOMPATIBLE
# -----------------------------------------------------------------------------
func _test_technology_usable_incompatible_state() -> void:
	print("\n-- [2] Technology Usable but Incompatible State --")
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	var tech_id := "tech_beam_weaponry"
	TechSys._player_discovery[tech_id] = TechSys.DiscoveryState.USABLE
	_check(TechSys.is_technology_usable(tech_id), "[2a] Technology is authorized and USABLE")

	var incomp_weapon_uid := "uid_incomp_gun"
	var incomp_inv := {
		"uid": incomp_weapon_uid,
		"name": "Heavy Beam Cannon",
		"tech_id": tech_id,
		"path": "res://resources/mech/stock/weapon_beam_rifle.tres",
		"durability": 1.0,
		"type": "Weapon"
	}
	GlobalData.weapons.weapon_inventory.append(incomp_inv)

	var hangar = _make_hangar()
	await get_tree().process_frame

	# Gen 1 frame without energy support
	var gen1_frame: Dictionary = {
		"id": "frame_basic_arm",
		"native_generation": 1,
		"technology_lineage": "valkren",
		"supported_families": [TechSys.FAMILY_BALLISTIC]
	}
	GlobalData.weapons.equipped_frames["arm_right"] = gen1_frame

	hangar.selected_slot = "weapon_right"
	hangar.part_list_panel.populate("weapon_right")

	var row := -1
	for i in range(hangar.part_list_panel.controller.visible_weapon_indices.size()):
		var idx: int = hangar.part_list_panel.controller.visible_weapon_indices[i]
		if str(GlobalData.weapons.weapon_inventory[idx].get("uid", "")) == incomp_weapon_uid:
			row = i
			break
	_check(row >= 0, "[2b] Incompatible weapon row found")

	if row >= 0:
		var item_text: String = hangar.part_item_list.get_item_text(row)
		_check(item_text.contains("[INCOMPATIBLE]"), "[2c] Item row displays [INCOMPATIBLE] tag")

		hangar.part_list_panel.on_item_selected(row)

		var stats_text: String = hangar.stats_label.text
		_check(stats_text.contains("USABLE"), "[2d] Detail panel shows Technology is USABLE")
		_check(stats_text.contains("INCOMPATIBLE"), "[2e] Detail panel shows Frame Compatibility is INCOMPATIBLE")
		_check(not stats_text.contains("Technology not authorized"), "[2f] Detail panel does NOT display technology lock")

		_check(hangar.equip_button.disabled == true, "[2g] Equip button is disabled for incompatible frame")
		_check(hangar.equip_button.text.contains("INCOMPATIBLE"), "[2h] Equip button text indicates INCOMPATIBLE")

		var loadout_before: String = str(GlobalData.weapons.weapon_loadout.get("right", ""))
		hangar.equip_panel.on_equip_pressed()
		var loadout_after: String = str(GlobalData.weapons.weapon_loadout.get("right", ""))
		_check(loadout_before == loadout_after, "[2i] Loadout unchanged after incompatible equip attempt")
		_check(hangar.status_message_label.text.contains("cannot support this hardware") or hangar.status_message_label.text.contains("Frame does not support"), "[2j] Status message indicates frame incompatibility")

	hangar.queue_free()


# -----------------------------------------------------------------------------
# 3. TECHNOLOGY USABLE + COMPATIBLE (EQUIPABLE)
# -----------------------------------------------------------------------------
func _test_technology_usable_compatible_state() -> void:
	print("\n-- [3] Technology Usable + Compatible State --")
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	var tech_id := "tech_beam_weaponry"
	TechSys._player_discovery[tech_id] = TechSys.DiscoveryState.USABLE

	var comp_weapon_uid := "uid_comp_gun"
	var comp_inv := {
		"uid": comp_weapon_uid,
		"name": "Tuned Beam Carbine",
		"tech_id": tech_id,
		"path": "res://resources/mech/stock/weapon_beam_rifle.tres",
		"durability": 1.0,
		"type": "Weapon"
	}
	GlobalData.weapons.weapon_inventory.append(comp_inv)

	var hangar = _make_hangar()
	await get_tree().process_frame

	# Equip compatible Gen 2 energy frame
	var gen2_frame: Dictionary = {
		"id": "frame_energy_arm",
		"native_generation": 2,
		"technology_lineage": "valkren",
		"supported_families": [TechSys.FAMILY_BALLISTIC, TechSys.FAMILY_ENERGY]
	}
	GlobalData.weapons.equipped_frames["arm_right"] = gen2_frame

	# Empty right hand slot so equip operation is clean
	GlobalData.weapons.weapon_loadout["right"] = ""

	hangar.selected_slot = "weapon_right"
	hangar.part_list_panel.populate("weapon_right")

	var row := -1
	for i in range(hangar.part_list_panel.controller.visible_weapon_indices.size()):
		var idx: int = hangar.part_list_panel.controller.visible_weapon_indices[i]
		if str(GlobalData.weapons.weapon_inventory[idx].get("uid", "")) == comp_weapon_uid:
			row = i
			break
	_check(row >= 0, "[3a] Compatible weapon row found")

	if row >= 0:
		var item_text: String = hangar.part_item_list.get_item_text(row)
		_check(not item_text.contains("[TECH LOCKED]") and not item_text.contains("[INCOMPATIBLE]"), "[3b] Available item has no locked or incompatible tag")

		hangar.part_list_panel.on_item_selected(row)

		var stats_text: String = hangar.stats_label.text
		_check(stats_text.contains("AVAILABLE"), "[3c] Detail panel shows Equip Status is AVAILABLE")
		_check(stats_text.contains("COMPATIBLE"), "[3d] Detail panel shows Frame Compatibility is COMPATIBLE")

		_check(hangar.equip_button.disabled == false, "[3e] Equip button is ENABLED")
		_check(hangar.equip_button.text == "EQUIP SELECTION", "[3f] Equip button text is 'EQUIP SELECTION'")

		hangar.equip_panel.on_equip_pressed()
		_check(str(GlobalData.weapons.weapon_loadout.get("right", "")) == comp_weapon_uid, "[3g] Loadout mutated: right hand holds weapon uid")

	hangar.queue_free()


# -----------------------------------------------------------------------------
# 4. LEGACY TECHNOLOGY-NEUTRAL ITEM
# -----------------------------------------------------------------------------
func _test_legacy_item_behavior() -> void:
	print("\n-- [4] Legacy Technology-Neutral Item --")
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	# Empty right hand slot so installing spare neutral weapon is not blocked by duplicate path
	GlobalData.weapons.weapon_loadout["right"] = ""

	var neutral_uid := "uid_legacy_shotgun"
	var neutral_inv := {
		"uid": neutral_uid,
		"name": "Heavy Shotgun",
		"path": "res://resources/mech/stock/weapon_shotgun.tres",
		"durability": 1.0,
		"type": "Weapon"
	}
	GlobalData.weapons.weapon_inventory.append(neutral_inv)

	var hangar = _make_hangar()
	await get_tree().process_frame

	hangar.selected_slot = "weapon_right"
	hangar.part_list_panel.populate("weapon_right")

	var row := -1
	for i in range(hangar.part_list_panel.controller.visible_weapon_indices.size()):
		var idx: int = hangar.part_list_panel.controller.visible_weapon_indices[i]
		if str(GlobalData.weapons.weapon_inventory[idx].get("uid", "")) == neutral_uid:
			row = i
			break
	_check(row >= 0, "[4a] Legacy weapon found")

	if row >= 0:
		hangar.part_list_panel.on_item_selected(row)
		_check(hangar.equip_button.disabled == false, "[4b] Equip button is enabled for legacy neutral item")
		_check(not hangar.stats_label.text.contains("LOCKED (Technology not authorized)"), "[4c] No technology lock in detail panel")

		hangar.equip_panel.on_equip_pressed()
		_check(str(GlobalData.weapons.weapon_loadout.get("right", "")) == neutral_uid, "[4d] Legacy weapon equips normally")

	hangar.queue_free()


# -----------------------------------------------------------------------------
# 5. SYNTHETIC FUTURE TECH (JAMMER & SATELLITE CANNON) GENERIC UI PATH
# -----------------------------------------------------------------------------
func _test_synthetic_future_tech_generic() -> void:
	print("\n-- [5] Synthetic Future Tech Generic UI Path --")
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	# 1. Register synthetic generic technologies without special casing
	TechSys.register_technology({
		"tech_id": "tech_jammer",
		"name": "Electronic Warfare Jammer Architecture",
		"generation": 2,
		"technology_family": TechSys.FAMILY_INTERFACE,
		"compatibility_requirements": {"min_generation": 2, "required_families": [TechSys.FAMILY_INTERFACE]}
	})
	TechSys.register_technology({
		"tech_id": "tech_satellite_cannon",
		"name": "Orbital Relay Uplink Architecture",
		"generation": 3,
		"technology_family": TechSys.FAMILY_ENERGY,
		"compatibility_requirements": {"min_generation": 3, "required_families": [TechSys.FAMILY_ENERGY]}
	})

	var jammer_inv := {
		"uid": "uid_synth_jammer",
		"name": "ECM Jammer Pod",
		"tech_id": "tech_jammer",
		"path": "res://resources/mech/stock/weapon_beam_rifle.tres",
		"durability": 1.0,
		"type": "Weapon"
	}
	var sat_inv := {
		"uid": "uid_synth_sat_cannon",
		"name": "Orbital Uplink Cannon",
		"tech_id": "tech_satellite_cannon",
		"path": "res://resources/mech/stock/weapon_beam_rifle.tres",
		"durability": 1.0,
		"type": "Weapon"
	}
	GlobalData.weapons.weapon_inventory.append(jammer_inv)
	GlobalData.weapons.weapon_inventory.append(sat_inv)

	var hangar = _make_hangar()
	await get_tree().process_frame

	hangar.selected_slot = "weapon_right"
	hangar.part_list_panel.populate("weapon_right")

	# Validate Jammer while UNKNOWN
	var val_jammer_locked := LoadoutSys.validate_equip_request("weapon_right", jammer_inv)
	_check(not bool(val_jammer_locked.get("can_equip", false)), "[5a] Jammer locked while UNKNOWN")
	_check(val_jammer_locked.get("reason", "") == "technology_locked", "[5b] Jammer reason is technology_locked")

	# Validate Satellite Cannon while UNKNOWN
	var val_sat_locked := LoadoutSys.validate_equip_request("weapon_right", sat_inv)
	_check(not bool(val_sat_locked.get("can_equip", false)), "[5c] Satellite cannon locked while UNKNOWN")
	_check(val_sat_locked.get("reason", "") == "technology_locked", "[5d] Satellite cannon reason is technology_locked")

	# Authorize Jammer
	TechSys._player_discovery["tech_jammer"] = TechSys.DiscoveryState.USABLE

	# Incompatible frame
	GlobalData.weapons.equipped_frames["arm_right"] = {
		"id": "frame_basic_arm",
		"native_generation": 1,
		"technology_lineage": "valkren",
		"supported_families": [TechSys.FAMILY_BALLISTIC]
	}
	var val_jammer_incomp := LoadoutSys.validate_equip_request("weapon_right", jammer_inv)
	_check(not bool(val_jammer_incomp.get("can_equip", false)), "[5e] Jammer rejected on incompatible frame")
	_check(val_jammer_incomp.get("reason", "") == "physically_incompatible", "[5f] Jammer reason is physically_incompatible")

	# Compatible frame with interface support
	GlobalData.weapons.equipped_frames["arm_right"] = {
		"id": "frame_advanced_arm",
		"native_generation": 2,
		"technology_lineage": "valkren",
		"supported_families": [TechSys.FAMILY_INTERFACE]
	}
	var val_jammer_ready := LoadoutSys.validate_equip_request("weapon_right", jammer_inv)
	_check(bool(val_jammer_ready.get("can_equip", false)), "[5g] Jammer allowed once tech usable and frame compatible")

	hangar.queue_free()


# -----------------------------------------------------------------------------
# 6. FINAL REQUEST REVALIDATION AND INVARIANCE (STALE UI SAFETY)
# -----------------------------------------------------------------------------
func _test_final_request_revalidation_and_invariance() -> void:
	print("\n-- [6] Final Request Revalidation & Invariance --")
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	var tech_id := "tech_beam_weaponry"
	TechSys._player_discovery[tech_id] = TechSys.DiscoveryState.USABLE

	var test_uid := "uid_race_gun"
	var test_inv := {
		"uid": test_uid,
		"name": "Pulse Gun",
		"tech_id": tech_id,
		"path": "res://resources/mech/stock/weapon_beam_rifle.tres",
		"durability": 1.0,
		"type": "Weapon"
	}
	GlobalData.weapons.weapon_inventory.append(test_inv)

	var hangar = _make_hangar()
	await get_tree().process_frame

	# Start with compatible frame
	GlobalData.weapons.equipped_frames["arm_right"] = {
		"id": "frame_gen2_arm",
		"native_generation": 2,
		"technology_lineage": "valkren",
		"supported_families": [TechSys.FAMILY_BALLISTIC, TechSys.FAMILY_ENERGY]
	}
	GlobalData.weapons.weapon_loadout["right"] = ""

	hangar.selected_slot = "weapon_right"
	hangar.part_list_panel.populate("weapon_right")

	var row := -1
	for i in range(hangar.part_list_panel.controller.visible_weapon_indices.size()):
		var idx: int = hangar.part_list_panel.controller.visible_weapon_indices[i]
		if str(GlobalData.weapons.weapon_inventory[idx].get("uid", "")) == test_uid:
			row = i
			break
	_check(row >= 0, "[6a] Race test item found")
	if row >= 0:
		hangar.part_list_panel.on_item_selected(row)
		_check(hangar.equip_button.disabled == false, "[6b] UI initially shows equip button enabled")

		# SIMULATE STALE STATE: Underneath the UI, revoke usability back to RESEARCHED
		TechSys._player_discovery[tech_id] = TechSys.DiscoveryState.RESEARCHED

		# User clicks EQUIP
		var loadout_before: String = str(GlobalData.weapons.weapon_loadout.get("right", ""))
		hangar.equip_panel.on_equip_pressed()
		var loadout_after: String = str(GlobalData.weapons.weapon_loadout.get("right", ""))

		_check(loadout_before == loadout_after, "[6c] Stale UI click did NOT mutate loadout")
		_check(hangar.status_message_label.text.contains("not authorized"), "[6d] Rejection message displayed")

	hangar.queue_free()


# -----------------------------------------------------------------------------
# 7. ARMOR AND WEAPON PARITY
# -----------------------------------------------------------------------------
func _test_armor_weapon_parity() -> void:
	print("\n-- [7] Armor and Weapon Parity --")
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	var tech_id := "tech_high_energy_barrier"
	var armor_inst := {
		"uid": "uid_tech_armor_1",
		"name": "Deflection Barrier Plate",
		"slot": "body",
		"technology_id": tech_id,
		"durability": 1.0,
		"max_hp": 60.0,
		"armor": 25.0,
		"weight": 8.0,
		"type": "Instance"
	}
	GlobalData.weapons.armor_inventory.append(armor_inst)

	# 1. While tech UNKNOWN
	var val_armor_locked := ArmorSys.validate_equip_request("body", armor_inst)
	_check(not bool(val_armor_locked.get("can_equip", false)), "[7a] Armor locked while tech is UNKNOWN")
	_check(val_armor_locked.get("reason", "") == "technology_locked", "[7b] Armor reason is technology_locked")

	# Equip attempt must fail
	_check(not ArmorSys.equip_armor_instance("uid_tech_armor_1", "body"), "[7c] ArmorSystem.equip_armor_instance rejects locked tech")
	_check(str(GlobalData.weapons.equipped_parts.get("body", {}).get("uid", "")) != "uid_tech_armor_1", "[7d] Body armor slot remains unmutated")

	# 2. Make tech USABLE, but incompatible frame
	TechSys._player_discovery[tech_id] = TechSys.DiscoveryState.USABLE

	GlobalData.weapons.equipped_frames["body"] = {
		"id": "frame_basic_body",
		"native_generation": 1,
		"technology_lineage": "valkren",
		"supported_families": [TechSys.FAMILY_BALLISTIC]
	}
	var val_armor_incomp := ArmorSys.validate_equip_request("body", armor_inst)
	_check(not bool(val_armor_incomp.get("can_equip", false)), "[7e] Armor rejected on incompatible frame")
	_check(val_armor_incomp.get("reason", "") == "physically_incompatible", "[7f] Armor reason is physically_incompatible")
	_check(not ArmorSys.equip_armor_instance("uid_tech_armor_1", "body"), "[7g] equip_armor_instance rejects incompatible frame")

	# 3. Compatible Gen 3 frame
	GlobalData.weapons.equipped_frames["body"] = {
		"id": "frame_gen3_body",
		"native_generation": 3,
		"technology_lineage": "valkryon",
		"supported_families": [TechSys.FAMILY_ARMOR, TechSys.FAMILY_ENERGY]
	}
	var val_armor_compat := ArmorSys.validate_equip_request("body", armor_inst)
	_check(bool(val_armor_compat.get("can_equip", false)), "[7h] Armor allowed on compatible frame")
	_check(ArmorSys.equip_armor_instance("uid_tech_armor_1", "body"), "[7i] equip_armor_instance mutates state successfully")
	_check(str(GlobalData.weapons.equipped_parts["body"].get("uid", "")) == "uid_tech_armor_1", "[7j] Armor instance is now equipped on body")


# -----------------------------------------------------------------------------
# 8. SAVE / LOAD UI REFLECTION
# -----------------------------------------------------------------------------
func _test_save_load_ui_reflection() -> void:
	print("\n-- [8] Save / Load UI Reflection --")
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	var tech_id := "tech_beam_weaponry"
	TechSys._player_discovery[tech_id] = TechSys.DiscoveryState.USABLE

	# Serialize discovery state
	var saved_state := TechSys.serialize_discovery_states()

	# Reset state
	TechSys.reset_discovery_states()
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.UNKNOWN, "[8a] Reset reverts tech to UNKNOWN")

	var item := {"uid": "uid_saveload_gun", "tech_id": tech_id}
	var val_after_reset := LoadoutSys.validate_equip_request("weapon_right", item)
	_check(not bool(val_after_reset.get("can_equip", false)), "[8b] Item is locked after reset")

	# Restore state
	TechSys.deserialize_discovery_states(saved_state)
	_check(TechSys.is_technology_usable(tech_id), "[8c] Deserialized state restores USABLE")

	GlobalData.weapons.equipped_frames["arm_right"] = {
		"id": "frame_energy_arm",
		"native_generation": 2,
		"technology_lineage": "valkren",
		"supported_families": [TechSys.FAMILY_ENERGY]
	}
	var val_after_load := LoadoutSys.validate_equip_request("weapon_right", item)
	_check(bool(val_after_load.get("can_equip", false)), "[8d] Item is equipable after deserialization")
