extends Node
## WEAPON DROP SIDE EFFECTS VERIFY (Gate R2-E, test-only).
##
## Pins the committed `drop_weapon_from_destroyed_arm(hand)` contract without
## touching production code:
##  1. Invalid hand identifier: returns null, mutates nothing, emits nothing.
##  2. Valid destroyed-arm drop: returns the armed instance (identity), clears
##     the slot, releases hold/reload/trigger state, clears the hand visual,
##     re-syncs the loadout slot, and emits weapon_switched BEFORE
##     weapon_dropped (exact sequence).
## Fixture: full production mech (mecha_base.tscn) + real WeaponManager.
## Run: godot --headless --path . res://test/unit/weapon_drop_side_effects_verify.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"
const RIFLE_PATH := "res://resources/mech/stock/weapon_beam_rifle.tres"

var _fails := 0
var _checks := 0
var _signals: Array = []


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("DROP-SIDE-EFFECT OK: " + name)
	else:
		_fails += 1
		printerr("DROP-SIDE-EFFECT FAIL: " + name)


func _on_switched(_hand: String, _weapon_name: String) -> void:
	_signals.append("switched")


func _on_dropped(_hand: String, _weapon) -> void:
	_signals.append("dropped")


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await _test_invalid_hand()
	await _test_valid_drop_side_effects()
	print("WEAPON_DROP_SIDE_EFFECTS_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("WEAPON_DROP_SIDE_EFFECTS_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_WEAPON_DROP_SIDE_EFFECT_TESTS_PASSED")
		get_tree().quit(0)


func _spawn_rig() -> Array:
	var mecha: CharacterBody3D = (load(MECH_SCENE) as PackedScene).instantiate()
	add_child(mecha)
	var wm: Node3D = load("res://scripts/mecha/weapon_manager.gd").new()
	wm.name = "WeaponManager"
	mecha.add_child(wm)
	await get_tree().process_frame
	await get_tree().process_frame
	return [mecha, wm]


func _test_invalid_hand() -> void:
	var rig := await _spawn_rig()
	var mecha: CharacterBody3D = rig[0]
	var wm: Node3D = rig[1]
	var rifle: WeaponPart = load(RIFLE_PATH)
	wm.left_hand = rifle
	wm.right_hand = rifle
	var loadout_before: Dictionary = (GlobalData.weapons.weapon_loadout as Dictionary).duplicate(true)
	var mount_before := _mount_child_count(mecha, "left")
	_signals.clear()
	wm.weapon_switched.connect(_on_switched)
	wm.weapon_dropped.connect(_on_dropped)
	var res = wm.drop_weapon_from_destroyed_arm("elbow")
	_check(res == null, "invalid hand returns null")
	_check(wm.left_hand == rifle and wm.right_hand == rifle, "invalid hand leaves both slots untouched")
	_check(_signals.is_empty(), "invalid hand emits no signals")
	_check((GlobalData.weapons.weapon_loadout as Dictionary) == loadout_before, "invalid hand leaves loadout untouched")
	_check(_mount_child_count(mecha, "left") == mount_before, "invalid hand leaves hand visual untouched")
	wm.weapon_switched.disconnect(_on_switched)
	wm.weapon_dropped.disconnect(_on_dropped)
	mecha.queue_free()


func _test_valid_drop_side_effects() -> void:
	var rig := await _spawn_rig()
	var mecha: CharacterBody3D = rig[0]
	var wm: Node3D = rig[1]
	var rifle: WeaponPart = load(RIFLE_PATH)
	var knife: WeaponPart = load("res://resources/mech/stock/weapon_combat_knife.tres")
	wm.left_hand = rifle
	wm.right_hand = knife
	# Mount a real visual so clearing is observable (production mount path).
	wm._update_hand_weapon_visual(mecha, "left", rifle)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_mount_child_count(mecha, "left") > 0, "fixture has a mounted left-hand visual")
	# Arm the states the retained implementation must release.
	wm.fire_left_holding = true
	wm.reloading_left = true
	wm.trigger_left.burst_left = 1
	GlobalData.weapons.weapon_loadout["left"] = "SENTINEL_UID"
	_signals.clear()
	wm.weapon_switched.connect(_on_switched)
	wm.weapon_dropped.connect(_on_dropped)
	var res = wm.drop_weapon_from_destroyed_arm("left")
	_check(res == rifle, "drop returns the exact armed instance")
	_check(wm.left_hand == null, "drop clears the hand slot")
	_check(wm.fire_left_holding == false, "drop releases fire-hold state")
	_check(wm.reloading_left == false, "drop releases reload state")
	_check(wm.trigger_left.burst_left == 0, "drop releases trigger burst state")
	_check(str(GlobalData.weapons.weapon_loadout.get("left", "SENTINEL_UID")) != "SENTINEL_UID", "drop re-syncs the loadout slot")
	_check(_signals == ["switched", "dropped"], "signal order is switched-then-dropped (got %s)" % str(_signals))
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_mount_child_count(mecha, "left") == 0, "drop clears the hand visual mount")
	_check(wm.right_hand == knife, "right hand untouched by left drop")
	wm.weapon_switched.disconnect(_on_switched)
	wm.weapon_dropped.disconnect(_on_dropped)
	mecha.queue_free()


func _mount_child_count(mecha: Node3D, hand: String) -> int:
	var side := "Left" if hand == "left" else "Right"
	var forearm := mecha.get_node_or_null("Arm" + side + "/Forearm" + side) as Node3D
	if forearm == null:
		return -1
	var node_name := "WeaponMesh_" + hand
	var mount := forearm.get_node_or_null(node_name) as Node3D
	if mount == null:
		mount = mecha.get_node_or_null(node_name) as Node3D
	if mount == null:
		return 0
	var live := 0
	for c in mount.get_children():
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			live += 1
	return live
