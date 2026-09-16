extends Node
## FIELD LOOT WEIGHT VERIFY — battle pickup gate must use the same numbers as
## the displayed weight (live battle hands + carrier, no hangar ammo).
## Reproduces: 5kg ground weapon rejected + red blink while the display shows
## ~30kg free (the gate silently added ~29kg of allocated hangar ammo).
## Also covers: HD desert terrain falls back instead of leaving no ground when
## its baked texture is missing.

var _fails := 0
var _checks := 0


class MockBattleWM extends Node:
	var carry: Array = []
	var left_hand: WeaponPart = null
	var right_hand: WeaponPart = null

	func get_battle_field_pack_weight() -> float:
		var total := 0.0
		for w in carry:
			if w:
				total += float(w.weight)
		if left_hand:
			total += float(left_hand.weight)
		if right_hand:
			total += float(right_hand.weight)
		return total

	func get_battle_reserve(_ammo_type: String) -> int:
		return 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("LOOTWT OK: " + name)
	else:
		_fails += 1
		printerr("LOOTWT FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	GlobalData.reset_run_data()
	await _test_modal_gate_matches_display()
	_test_arena_hd_fallback()
	print("FIELD_LOOT_WEIGHT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("FIELD_LOOT_WEIGHT_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FIELD_LOOT_WEIGHT_TESTS_PASSED")
		get_tree().quit(0)


func _make_modal_and_rig() -> Dictionary:
	var mecha := Node3D.new()
	mecha.name = "TestMecha"
	add_child(mecha)
	var wm := MockBattleWM.new()
	wm.name = "WeaponManager"
	mecha.add_child(wm)
	wm.left_hand = load("res://resources/mech/stock/weapon_beam_rifle.tres")
	wm.right_hand = load("res://resources/mech/stock/weapon_heat_blade.tres")
	wm.carry = [load("res://resources/mech/stock/weapon_combat_shotgun.tres")]
	var modal = load("res://scripts/ui/field_loot_modal.gd").new()
	add_child(modal)
	await get_tree().process_frame
	modal.player_entity = mecha
	return {"modal": modal, "mecha": mecha, "wm": wm}


func _make_pickup(path: String) -> Area3D:
	var pickup := Area3D.new()
	pickup.set_script(load("res://scripts/mecha/weapon_pickup.gd"))
	pickup.set("weapon_resource", load(path))
	add_child(pickup)
	await get_tree().process_frame
	return pickup


func _test_modal_gate_matches_display() -> void:
	print("-- modal gate uses displayed battle weight --")
	var rig := await _make_modal_and_rig()
	var modal = rig["modal"]
	var wm = rig["wm"]

	# Hangar pack is ammo-loaded (~51kg): the OLD gate rejected everything the
	# battle display (hands + carrier = 22kg) said should fit.
	var hangar_pack := LoadoutSystem.get_field_pack_weight()
	_check(hangar_pack > 40.0, "hangar pack is ammo-heavy (%.1f kg)" % hangar_pack)
	_check(is_equal_approx(wm.get_battle_field_pack_weight(), 22.0), "battle rig weighs 22kg (8+4+10)")
	_check(is_equal_approx(modal._current_battle_pack_weight(), 22.0), "modal gate number matches the displayed battle number")

	# 5kg beam carbine must fit into 22/64 — rejected before the fix.
	var pickup := await _make_pickup("res://resources/mech/stock/weapon_beam_carbine.tres")
	var carry_before: int = wm.carry.size()
	modal.take_weapon_to_carrier(pickup)
	await get_tree().process_frame
	_check(wm.carry.size() == carry_before + 1, "5kg carbine accepted into carrier (display said it fits)")
	_check(not is_instance_valid(pickup) or pickup.is_queued_for_deletion(), "accepted pickup removed from ground")
	_check(not str(modal.weight_label.text).contains("OVERLOAD"), "no OVERLOAD shown for a fitting pickup (was: '%s')" % modal.weight_label.text)

	# Genuine overload still rejected AND explained with numbers.
	var cannon = load("res://resources/mech/stock/weapon_assault_cannon.tres")
	wm.carry.append(cannon)
	wm.carry.append(cannon)
	wm.carry.append(cannon)
	var heavy := await _make_pickup("res://resources/mech/stock/weapon_combat_knife.tres")
	var carry_before2: int = wm.carry.size()
	modal.take_weapon_to_carrier(heavy)
	await get_tree().process_frame
	_check(wm.carry.size() == carry_before2, "overweight pickup still rejected")
	_check(is_instance_valid(heavy) and not heavy.is_queued_for_deletion(), "rejected pickup stays on the ground")
	_check(str(modal.weight_label.text).contains("OVERLOAD"), "rejection explains OVERLOAD with numbers (was: '%s')" % modal.weight_label.text)

	rig["mecha"].queue_free()
	modal.queue_free()


func _test_arena_hd_fallback() -> void:
	print("-- HD desert falls back when baked texture is missing --")
	var gen = load("res://scripts/arena/arena_generator.gd").new()
	_check(gen._add_hd_desert_model("does_not_exist_xyz.glb", "Nope") == false, "missing HD file returns false (fallback runs)")
	gen.desert_variant = "mountain"
	_check(gen._try_add_hd_desert_terrain() == false, "mountain variant has no HD file (falls back)")
	gen.desert_variant = "canyon"
	# The shipped canyon HD glb references a temp texture that was never saved
	# (terrain_desert_canyon_hd_tmp*.jpg): loader must report false so the
	# arena falls back to legacy/procedural ground instead of no ground.
	if ResourceLoader.exists("res://assets/models/terrain_desert_canyon_hd.glb"):
		_check(gen._try_add_hd_desert_terrain() == false, "canyon HD with missing baked texture falls back instead of empty ground")
	else:
		_check(true, "canyon HD glb absent (fallback path trivially taken)")
	gen.free()
