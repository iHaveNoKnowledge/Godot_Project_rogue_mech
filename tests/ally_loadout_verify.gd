extends Node

## Headless verification that a fielded ally fights with its hangar mech's ACTUAL
## loadout instead of the generic template stats: the armor/frame HP written into
## the health system comes from the berth's equipped plates, and the attack
## stats + WeaponCore come from the equipped weapon.
## Run: godot --headless --path . res://tests/ally_loadout_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _verify_armor_loadout()
	await _verify_weapon_loadout()
	await _verify_empty_loadout_falls_back()
	print("ALLY_LOADOUT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


# A berth snapshot with a heavy chest plate (hp 110, armor 75) on a reinforced
# composite torso frame (hp 75). After apply_mech_loadout the ally's body slot
# must carry those exact values.
func _verify_armor_loadout() -> void:
	var ally = _spawn_ally()
	var mech := {
		"id": "mech_test",
		"parts": {"body": {"id": "body_002"}},
		"frames": {"body": {"id": "frame_body_03"}},
		"damage": {},
		"scrap_patches": {},
		"weapon_loadout": {"left": "", "right": "", "carry": []},
	}
	ally.apply_mech_loadout(mech)
	var body: Dictionary = ally.health_system.parts["body"]
	var frame_hp: float = 75.0 + GlobalData.get_frame_upgrade_hp_bonus()
	_check(is_equal_approx(body["max_armor"], 110.0), "ally body armor HP comes from the equipped plate")
	_check(is_equal_approx(body["armor_hp"], 110.0), "ally body armor starts full")
	_check(is_equal_approx(body["max_frame"], frame_hp), "ally body frame HP comes from the equipped inner frame")
	_check(is_equal_approx(body["armor_class"], 7.5), "ally body armor_class derives from the plate armor value")
	# Total HP reflects the real plates, not the template's frame_hp budget.
	# FULL-layout defaults sum to 260 armor; the body plate override (80 -> 110)
	# pushes the total to 290, proving the mech plates were applied.
	_check(is_equal_approx(ally.health_system.max_total_armor, 290.0), "ally total armor HP uses the mech plates")
	ally.queue_free()
	await get_tree().process_frame


# A RANGED berth carrying a Beam Rifle (damage 25, range 55, mag 40): the ally's
# attack stats and fire core must match the gun, and a weapon model gets mounted.
func _verify_weapon_loadout() -> void:
	var ally = _spawn_ally()
	ally.apply_mech_override(1, "Test Pilot")  # RANGED archetype
	var mech := {
		"id": "mech_test",
		"parts": {},
		"frames": {},
		"damage": {},
		"scrap_patches": {},
		"weapon_loadout": {
			"left": "",
			"right": "res://resources/mech/stock/weapon_beam_rifle.tres",
			"carry": [],
		},
	}
	ally.apply_mech_loadout(mech)
	_check(is_equal_approx(ally.attack_damage, 25.0), "ally attack damage comes from the equipped weapon")
	_check(is_equal_approx(ally.attack_range, 55.0), "ally attack range comes from the weapon range")
	_check(ally.fire_core != null and ally.fire_core.max_ammo == 40, "ally fire core carries the weapon magazine")
	_check(ally.fire_core != null and is_equal_approx(ally.fire_core.damage, 25.0), "ally fire core damage matches the weapon")
	_check(ally.get_node_or_null("AllyWeaponVisual") != null, "ally mounts the equipped weapon model")
	ally.queue_free()
	await get_tree().process_frame


# A berth with no weapons keeps the template combat stats instead of zeroing out.
func _verify_empty_loadout_falls_back() -> void:
	var ally = _spawn_ally()
	ally.apply_mech_override(1, "Empty Pilot")
	var mech := {
		"id": "mech_test",
		"parts": {},
		"frames": {},
		"damage": {},
		"scrap_patches": {},
		"weapon_loadout": {"left": "", "right": "", "carry": []},
	}
	ally.apply_mech_loadout(mech)
	_check(ally.attack_damage > 0.0, "empty loadout keeps template attack damage")
	_check(ally.fire_core != null and ally.fire_core.damage == ally.attack_damage, "empty loadout keeps template fire core")
	ally.queue_free()
	await get_tree().process_frame


func _spawn_ally() -> Node:
	var scene = load("res://scenes/mecha/ally_dummy.tscn")
	var ally = scene.instantiate()
	ally.template_id = "ally_gm"
	add_child(ally)
	return ally
