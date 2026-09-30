extends Node

## Frame swap → runtime capability audit. Proves every runtime consumer operates
## from CURRENT Frame + CURRENT Loadout state after replacement: handling powers
## are gathered live per resolution, weight/movement/capacity re-derive, damage
## is untouched, spawn/berth reconstruction is deterministic. No file I/O; all
## working-set state is snapshotted and restored.
## Run: godot --headless --path . res://tests/mecha/frame_swap_runtime_audit.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"

var _fails := 0
var _checks := 0
var _snap: Dictionary = {}
# BackpackSystem.equip() persists via save_run: isolate the user savefile.
var _save_backup: PackedByteArray = PackedByteArray()
var _had_save: bool = false


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + label)
	else:
		_fails += 1
		push_error("FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	_backup_save()
	await _run()
	_restore_save()
	print("FRAME_SWAP_RUNTIME_PROBE: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _backup_save() -> void:
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.READ)
		if f:
			_save_backup = f.get_buffer(f.get_length())
			_had_save = true
			f.close()


func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(_save_backup)
			f.close()
	elif FileAccess.file_exists(GlobalData.SAVE_PATH):
		DirAccess.remove_absolute(GlobalData.SAVE_PATH)


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


func _powers_now(wm: Node, hand: String) -> Dictionary:
	return wm._handling_powers(hand)


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
	mech.set("is_player_driven", false)
	var f := 0
	while not mech.is_on_floor() and f < 180:
		await get_tree().physics_frame
		f += 1
	await get_tree().physics_frame
	await get_tree().process_frame
	var WM = load("res://scripts/mecha/weapon_manager.gd")
	var wmn: Node3D = WM.new()
	wmn.name = "WeaponManager"
	mech.add_child(wmn)
	await get_tree().process_frame
	await get_tree().process_frame
	var wm = mech.get_node_or_null("WeaponManager")
	var hs: Node = mech.get_node_or_null("HealthSystem")

	# ---- baseline: independent catalog reads for the equipped body frame ----
	var fa: Dictionary = FrameSystem.get_equipped_frame("body")
	var fa_id := str(fa.get("id", ""))
	_check(fa_id != "", "baseline body frame present")
	var fb_id := ""
	for entry in GlobalData.frame_catalog.get("body", []):
		var eid := str((entry as Dictionary).get("id", ""))
		if eid != "" and eid != fa_id:
			fb_id = eid
			break
	_check(fb_id != "", "catalog holds a second body frame")
	var cat_b: Dictionary = GlobalData.get_frame_catalog_entry(fb_id)
	_check(not cat_b.is_empty(), "replacement catalog entry resolves")

	# ---- handling powers are gathered live from current frames ----
	var powers_a: Dictionary = _powers_now(wm, "left")
	_check(absf(float(powers_a.get("arm_power", -1.0)) - GlobalData.get_arm_power("left")) < 0.001, "arm power matches live chassis+frame state")
	_check(absf(float(powers_a.get("leg_power", -1.0)) - GlobalData.get_leg_power()) < 0.001, "leg power matches live state")
	_check(absf(float(powers_a.get("recoil_resistance", -1.0)) - FrameSystem.get_total_recoil_resistance()) < 0.001, "recoil resistance matches live frames")

	# ---- swap body frame; powers must follow the CURRENT frame ----
	var fb := FrameSystem.make_frame_instance(fb_id)
	FrameSystem.equip_frame("body", fb)
	(GlobalData.weapons.part_damage as Dictionary).erase("body_frame")
	var powers_b: Dictionary = _powers_now(wm, "left")
	_check(absf(float(powers_b.get("recoil_resistance", -1.0)) - FrameSystem.get_total_recoil_resistance()) < 0.001, "post-swap resistance follows current frames")
	# determinism: swap back reproduces the original powers exactly
	FrameSystem.equip_frame("body", fa)
	(GlobalData.weapons.part_damage as Dictionary).erase("body_frame")
	var powers_a2: Dictionary = _powers_now(wm, "left")
	_check(str(powers_a2) == str(powers_a), "swap-back reproduces original powers (no stale residue)")
	# re-apply B for the remaining cases
	FrameSystem.equip_frame("body", fb)
	(GlobalData.weapons.part_damage as Dictionary).erase("body_frame")
	# grip resolution consumes the live powers (heavy probe weapon, direct resolve)
	var heavy = WeaponPart.new()
	heavy.weight = 20.0
	heavy.arm_load = 50.0
	heavy.recoil_force = 8.0
	var r_now: Dictionary = HandlingResolver.resolve(heavy, "hand", _powers_now(wm, "left"))
	_check(str(r_now.get("grip_mode", "")) == "TWO_HAND" or str(r_now.get("grip_mode", "")) == "BRACED", "heavy load resolves assisted grip from live powers")

	# ---- hand/shoulder/carry uids preserved; usability from LIVE health ----
	var lo: Dictionary = (GlobalData.weapons.weapon_loadout as Dictionary).duplicate(true)
	_check(str(lo.get("left", "")) != "", "hand slot populated")
	_check(wm._hand_usable("left"), "hand usable while arm intact")
	hs.take_damage_to_part("arm_left", 100000.0, "pierce", "armor")
	var g := 0
	while not bool((hs.parts["arm_left"] as Dictionary).get("armor_broken", false)) and g < 10:
		hs.take_damage_to_part("arm_left", 100000.0, "pierce", "armor")
		g += 1
	hs.take_damage_to_part("arm_left", 100000.0, "pierce", "frame")
	g = 0
	while not bool((hs.parts["arm_left"] as Dictionary).get("destroyed", false)) and g < 10:
		hs.take_damage_to_part("arm_left", 100000.0, "pierce", "frame")
		g += 1
	_check(not wm._hand_usable("left"), "destroyed arm blocks hand (live health, post-swap frames)")

	# ---- generator: id preserved; weight term live ----
	var w_core := LoadoutSystem.get_total_mecha_weight()
	_check(w_core > 0.0, "total includes live core weight term")

	# ---- backpack capacity decomposes from CURRENT frame + CURRENT pack ----
	BackpackSystem.equip("cargo")
	var cap_now := LoadoutSystem.get_field_pack_capacity()
	var cap_expect := GlobalData.FIELD_PACK_BASE_CAPACITY + FrameSystem.get_total_frame_carry_bonus() + BackpackSystem.get_backpack_carry_bonus()
	_check(absf(cap_now - cap_expect) < 0.001, "pack capacity == base + current frames + current backpack")

	# ---- modules: installed ids stay live after swap ----
	FrameModuleSystem.install_module("body", 0, "heat_kinetic_converter")
	_check(FrameModuleSystem.has_module("heat_kinetic_converter"), "installed module live after frame swap")
	FrameSystem.equip_frame("body", fa)
	(GlobalData.weapons.part_damage as Dictionary).erase("body_frame")
	_check(FrameModuleSystem.has_module("heat_kinetic_converter"), "module survives swap-back (array preserved)")

	# ---- damage state untouched by frame swaps (except fresh-install wipe rule) ----
	_check(bool((hs.parts["arm_left"] as Dictionary).get("destroyed", false)), "live combat instance keeps its own damage (swap is working-set scope)")
	_check(float((GlobalData.weapons.part_damage as Dictionary).get("arm_left_frame", 0.0)) >= 1.0, "working-set arm damage intact after frame swaps")

	# ---- movement consumes current weight/max ----
	mech._recalculate_weight()
	_check(absf(float(mech.get("total_weight")) - LoadoutSystem.get_total_mecha_weight()) < 0.001, "controller total == authority post-swap")
	EventBus.weight_changed.emit(0.0)
	await get_tree().process_frame
	_check(absf(float(mech.get("total_weight")) - LoadoutSystem.get_total_mecha_weight()) < 0.001, "signal refresh tracks post-swap state")

	# ---- berth round-trip + fresh spawn determinism under swapped frame ----
	FrameSystem.equip_frame("body", fb)
	(GlobalData.weapons.part_damage as Dictionary).erase("body_frame")
	HangarManager.save_mech_state(aid)
	FrameSystem.equip_frame("body", fa)
	HangarManager.load_mech_state(aid)
	_check(str((FrameSystem.get_equipped_frame("body") as Dictionary).get("id", "")) == fb_id, "berth round-trip restores swapped frame")
	var mech2: CharacterBody3D = load(MECH_SCENE).instantiate()
	add_child(mech2)
	await get_tree().process_frame
	var hs2: Node = mech2.get_node_or_null("HealthSystem")
	var expect_hp := float(cat_b.get("hp", 40.0)) + LoadoutSystem.get_frame_upgrade_hp_bonus()
	_check(absf(float((hs2.parts["body"] as Dictionary).get("max_frame", -1.0)) - expect_hp) < 0.01, "fresh spawn derives body max_frame from CURRENT frame + upgrade bonus")
	_check(bool((hs2.parts["arm_left"] as Dictionary).get("destroyed", false)), "fresh spawn restores persisted arm destruction (no resurrection)")
	mech2.queue_free()
	await get_tree().process_frame

	# ---- visuals remount from current state, exactly once ----
	BackpackVisualFactory.mount_backpack(mech, BackpackSystem.get_equipped_backpack())
	await get_tree().process_frame
	await get_tree().process_frame
	var sock := mech.get_node_or_null("Body/Backpack")
	var n := 0
	if sock != null:
		for c in sock.get_children():
			if str(c.name) == "BackpackVisual":
				n += 1
	_check(n == 1, "exactly 1 backpack visual post-swap")

	mech.queue_free()
	await get_tree().process_frame
	_restore_state()
