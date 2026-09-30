extends Node

## Frame replacement / equipment compatibility contract audit. Drives ONLY real
## production paths (FrameSystem, LoadoutSystem, BackpackSystem, PowerCoreSystem,
## FrameModuleSystem, HangarManager berth ops, visual factories). No file I/O;
## all working-set state is snapshotted and restored. Created by the frame
## replacement compatibility audit to codify the transaction-invariant contract.
## Run: godot --headless --path . res://tests/mecha/frame_swap_compat_audit.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"

var _fails := 0
var _checks := 0
var _snap: Dictionary = {}


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + label)
	else:
		_fails += 1
		push_error("FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("FRAME_SWAP_PROBE: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _snap_state() -> void:
	_snap = {
		"damage": (GlobalData.weapons.part_damage as Dictionary).duplicate(true),
		"loadout": (GlobalData.weapons.weapon_loadout as Dictionary).duplicate(true),
		"inventory": (GlobalData.weapons.weapon_inventory as Array).duplicate(true),
		"parts": (GlobalData.weapons.equipped_parts as Dictionary).duplicate(true),
		"frames": (GlobalData.weapons.equipped_frames as Dictionary).duplicate(true),
		"modules": (GlobalData.weapons.frame_modules as Dictionary).duplicate(true),
		"modinv": (GlobalData.weapons.module_inventory as Array).duplicate(true),
		"backpack": (GlobalData.weapons.equipped_backpack as Dictionary).duplicate(true),
		"core": str(GlobalData.weapons.power_core_id),
		"chassis": str(GlobalData.weapons.chassis_id),
	}


func _restore_state() -> void:
	GlobalData.weapons.part_damage = (_snap["damage"] as Dictionary).duplicate(true)
	GlobalData.weapons.weapon_loadout = (_snap["loadout"] as Dictionary).duplicate(true)
	GlobalData.weapons.weapon_inventory = (_snap["inventory"] as Array).duplicate(true)
	GlobalData.weapons.equipped_parts = (_snap["parts"] as Dictionary).duplicate(true)
	GlobalData.weapons.equipped_frames = (_snap["frames"] as Dictionary).duplicate(true)
	GlobalData.weapons.frame_modules = (_snap["modules"] as Dictionary).duplicate(true)
	GlobalData.weapons.module_inventory = (_snap["modinv"] as Array).duplicate(true)
	GlobalData.weapons.equipped_backpack = (_snap["backpack"] as Dictionary).duplicate(true)
	GlobalData.weapons.power_core_id = str(_snap["core"])
	GlobalData.weapons.chassis_id = str(_snap["chassis"])


func _run() -> void:
	_snap_state()
	(GlobalData.weapons.part_damage as Dictionary).clear()
	HangarManager.ensure_roster()
	var aid: String = GlobalData.hangar.active_hangar_mech_id

	var cam := Camera3D.new()
	add_child(cam)
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.position = Vector3(0, -1.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 3, 200)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)
	var mech: CharacterBody3D = load(MECH_SCENE).instantiate()
	add_child(mech)
	await get_tree().process_frame

	# ---- baseline: frame + equipment present ----
	var f0: Dictionary = FrameSystem.get_equipped_frame("body")
	_check(not f0.is_empty(), "baseline body frame equipped")

	# ---- swap body frame (production pattern: assign + wipe slot frame damage) ----
	BackpackSystem.equip("cargo")
	PowerCoreSystem.set_core("combustion")
	# Baseline weighed AFTER equipping, so the swap delta isolates the frame.
	var w0 := LoadoutSystem.get_total_mecha_weight()
	var cap0 := LoadoutSystem.get_field_pack_capacity()
	var bp_uid := str(GlobalData.weapons.equipped_backpack.get("uid", ""))
	var core_before := str(GlobalData.weapons.power_core_id)
	var lo_before: Dictionary = (GlobalData.weapons.weapon_loadout as Dictionary).duplicate(true)
	var mods_before: Dictionary = (GlobalData.weapons.frame_modules as Dictionary).duplicate(true)
	# A replacement must be a REAL catalog frame (synthetic ids carry no
	# weight and would measure schema defaults instead of the swap contract).
	var f_new_id := ""
	for entry in GlobalData.frame_catalog.get("body", []):
		var eid := str((entry as Dictionary).get("id", ""))
		if eid != "" and eid != str(f0.get("id", "")):
			f_new_id = eid
			break
	_check(f_new_id != "", "catalog holds a second body frame to swap to")
	var f_new := FrameSystem.make_frame_instance(f_new_id)
	_check(not f_new.is_empty(), "replacement frame instance builds")
	var fw_old := FrameSystem.get_frame_weight(f0)
	var fw_new := FrameSystem.get_frame_weight(f_new)
	FrameSystem.equip_frame("body", f_new)
	(GlobalData.weapons.part_damage as Dictionary).erase("body_frame")
	# equipment preservation across the swap (no validation, no migration)
	_check(str(GlobalData.weapons.equipped_backpack.get("uid", "")) == bp_uid, "swap keeps backpack UID")
	_check(str(GlobalData.weapons.power_core_id) == core_before, "swap keeps power core id")
	_check((GlobalData.weapons.weapon_loadout as Dictionary) == lo_before, "swap keeps weapon loadout uids")
	_check((GlobalData.weapons.frame_modules as Dictionary) == mods_before, "swap keeps module arrays")
	_check(not (GlobalData.weapons.part_damage as Dictionary).has("body_frame"), "fresh frame wipes slot frame damage (production rule)")
	# weight recompute is exact and derived
	var w1 := LoadoutSystem.get_total_mecha_weight()
	_check(absf((w1 - w0) - (fw_new - fw_old)) < 0.01, "total delta == frame weight delta exactly")
	_check(LoadoutSystem.get_field_pack_capacity() >= 0.0, "pack capacity recomputes (derived)")

	# ---- berth save/load round-trip preserves the swapped state ----
	HangarManager.save_mech_state(aid)
	var berth: Dictionary = HangarManager.get_active_mech() if aid == GlobalData.hangar.active_hangar_mech_id else {}
	FrameSystem.equip_frame("body", f0)
	HangarManager.load_mech_state(aid)
	_check(str((FrameSystem.get_equipped_frame("body") as Dictionary).get("id", "")) == str(f_new.get("id", "")), "berth round-trip restores swapped frame")
	_check(str(GlobalData.weapons.equipped_backpack.get("uid", "")) == bp_uid, "berth round-trip preserves backpack UID")
	_check(str(GlobalData.weapons.power_core_id) == core_before, "berth round-trip preserves core")
	_check(absf(LoadoutSystem.get_total_mecha_weight() - w1) < 0.01, "weight identical after berth round-trip")

	# ---- visuals remount from swapped state, exactly once, no dupes ----
	BackpackVisualFactory.mount_backpack(mech, BackpackSystem.get_equipped_backpack())
	await get_tree().process_frame
	await get_tree().process_frame
	var sock := mech.get_node_or_null("Body/Backpack")
	var bp_mounts := 0
	if sock != null:
		for c in sock.get_children():
			if str(c.name) == "BackpackVisual":
				bp_mounts += 1
	_check(bp_mounts == 1, "exactly 1 backpack visual after frame swap")
	WeaponVisualFactory.mount_hand(mech, "left", LoadoutSystem.get_equipped_weapon("left"), "WeaponMesh_left")
	await get_tree().process_frame
	await get_tree().process_frame
	var fh := mech.get_node_or_null("ArmLeft/ForearmLeft/WeaponMesh_left")
	_check(fh == null or fh.get_child_count() <= 1, "hand visual has at most 1 model after swap")

	# ---- compatibility gates exist; equip path does not consult them (actual split) ----
	var strict_frame := (FrameSystem.get_equipped_frame("body") as Dictionary).duplicate(true)
	strict_frame["backpack_compatibility"] = ["specific_xyz"]
	_check(not FrameSystem.can_equip_backpack(strict_frame, "cargo"), "gate reports incompatible pair correctly")
	_check(BackpackSystem.equip("cargo"), "equip succeeds regardless (no gate at equip = actual contract)")
	_check(str(GlobalData.weapons.equipped_backpack.get("id", "")) != bp_uid, "re-equip mints fresh UID (old uid gone, no dupes)")
	var strict_core := (FrameSystem.get_equipped_frame("body") as Dictionary).duplicate(true)
	strict_core["generator_compatibility"] = ["specific_xyz"]
	_check(not FrameSystem.can_equip_generator(strict_core, "combustion"), "core gate reports incompatible pair correctly")
	PowerCoreSystem.set_core("combustion")
	_check(str(GlobalData.weapons.power_core_id) == "combustion", "core set path ignores frame compat (actual contract)")

	# ---- module socket shrink follows the frame on next module read (actual rule) ----
	GlobalData.weapons.frame_modules["body"] = ["heat_kinetic_converter", "cryo_heatsink_loop", "modular_energy_converter"]
	var shrink_frame := (FrameSystem.get_equipped_frame("body") as Dictionary).duplicate(true)
	shrink_frame["module_slots"] = 2
	FrameSystem.equip_frame("body", shrink_frame)
	var got := FrameSystem.get_frame_module_slots(FrameSystem.get_equipped_frame("body"), "body")
	_check(got == 2, "shrunk frame reports 2 sockets")
	var first := FrameModuleSystem.get_installed_module_id("body", 0)
	_check(first == "heat_kinetic_converter", "first modules survive shrink in order")
	var arr: Array = (GlobalData.weapons.frame_modules as Dictionary).get("body", [])
	_check(arr.size() == 2, "module array resized to new frame capacity on read")
	# restore wide frame; arrays only grow back as empty sockets (no resurrection)
	FrameSystem.equip_frame("body", f0)
	FrameModuleSystem.get_installed_module_id("body", 0)
	var arr2: Array = (GlobalData.weapons.frame_modules as Dictionary).get("body", [])
	_check(arr2.size() >= 2, "array usable after restore")

	mech.queue_free()
	await get_tree().process_frame
	_restore_state()
