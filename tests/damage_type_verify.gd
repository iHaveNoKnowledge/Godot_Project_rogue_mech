extends Node

## Headless verification of the damage-type system (heat / pierce / blunt):
##   1. Every stock weapon resolves to one of the three types (and the special
##      cases: beam sniper/knife/pile bunker = pierce, heat blade = heat).
##   2. Armor plates only shed damage of their OWN defense type — matching hits
##      are reduced by armor_class, mismatched hits land at full strength.
##   3. Player shields: raised plate fully blocks, drains at 40% vs its own
##      anti-type and 100% vs the others, and never regenerates.
##   4. Legacy damage labels (kinetic/beam/explosive/melee) normalize onto the
##      three types so old callers keep working.
## Run: godot --headless --path . res://tests/damage_type_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await _verify_weapon_types()
	await _verify_normalize()
	await _verify_armor_defense()
	await _verify_player_shield()
	print("DAMAGE_TYPE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _wtype(path: String) -> String:
	var w: WeaponPart = load(path)
	return w.get_damage_type() if w != null else "?"


func _verify_weapon_types() -> void:
	# Heat weapons
	_check(_wtype("res://resources/mech/stock/weapon_beam_rifle.tres") == "heat", "beam rifle = heat")
	_check(_wtype("res://resources/mech/stock/weapon_beam_carbine.tres") == "heat", "beam carbine = heat")
	_check(_wtype("res://resources/mech/stock/weapon_beam_rifle_mk2.tres") == "heat", "beam rifle mk2 = heat")
	_check(_wtype("res://resources/mech/stock/weapon_missile.tres") == "heat", "missile = heat")
	_check(_wtype("res://resources/mech/stock/weapon_heavy_missile.tres") == "heat", "heavy missile = heat")
	_check(_wtype("res://resources/mech/stock/weapon_micro_missile.tres") == "heat", "micro missile = heat")
	_check(_wtype("res://resources/mech/stock/weapon_swarm_missile.tres") == "heat", "swarm missile = heat")
	_check(_wtype("res://resources/mech/stock/weapon_heat_blade.tres") == "heat", "heat blade = heat")
	_check(_wtype("res://resources/mech/stock/weapon_pilot_bazooka.tres") == "heat", "pilot bazooka = heat")

	# Pierce weapons
	_check(_wtype("res://resources/mech/stock/weapon_machine_gun.tres") == "pierce", "machine gun = pierce")
	_check(_wtype("res://resources/mech/stock/weapon_light_machine_gun.tres") == "pierce", "light machine gun = pierce")
	_check(_wtype("res://resources/mech/stock/weapon_heavy_machine_gun.tres") == "pierce", "heavy machine gun = pierce")
	_check(_wtype("res://resources/mech/stock/weapon_minigun.tres") == "pierce", "minigun = pierce")
	_check(_wtype("res://resources/mech/stock/weapon_railgun.tres") == "pierce", "railgun = pierce")
	_check(_wtype("res://resources/mech/stock/weapon_beam_sniper.tres") == "pierce", "beam sniper = pierce (special)")
	_check(_wtype("res://resources/mech/stock/weapon_combat_knife.tres") == "pierce", "combat knife = pierce")
	_check(_wtype("res://resources/mech/stock/weapon_pile_bunker.tres") == "pierce", "pile bunker = pierce")
	_check(_wtype("res://resources/mech/stock/weapon_pilot_pistol.tres") == "pierce", "pilot pistol = pierce")
	_check(_wtype("res://resources/mech/stock/weapon_pilot_assault_rifle.tres") == "pierce", "pilot assault rifle = pierce")
	_check(_wtype("res://resources/mech/stock/weapon_pilot_anti_tank_rifle.tres") == "pierce", "pilot anti-tank rifle = pierce")

	# Blunt weapons
	_check(_wtype("res://resources/mech/stock/weapon_shotgun.tres") == "blunt", "shotgun = blunt")
	_check(_wtype("res://resources/mech/stock/weapon_combat_shotgun.tres") == "blunt", "combat shotgun = blunt")
	_check(_wtype("res://resources/mech/stock/weapon_sawed_off.tres") == "blunt", "sawed-off = blunt")
	_check(_wtype("res://resources/mech/stock/weapon_assault_cannon.tres") == "explosive", "assault cannon = explosive")
	_check(_wtype("res://resources/mech/stock/weapon_gatling_gun.tres") == "blunt", "gatling gun = blunt")
	_check(_wtype("res://resources/mech/stock/weapon_mace.tres") == "blunt", "mace = blunt")

	# Shield plates report their anti-type, not a damage type.
	var shield: WeaponPart = load("res://resources/mech/stock/weapon_shield.tres")
	_check(shield.get_shield_type() in ["heat", "pierce", "blunt"], "shield reports an anti-type")
	_check(shield.shield_hp > 0.0, "shield has plate HP")


func _verify_normalize() -> void:
	_check(MechaHealthBase.normalize_damage_type("heat") == "heat", "heat passes through")
	_check(MechaHealthBase.normalize_damage_type("pierce") == "pierce", "pierce passes through")
	_check(MechaHealthBase.normalize_damage_type("blunt") == "blunt", "blunt passes through")
	_check(MechaHealthBase.normalize_damage_type("kinetic") == "pierce", "kinetic -> pierce")
	_check(MechaHealthBase.normalize_damage_type("beam") == "heat", "beam -> heat")
	_check(MechaHealthBase.normalize_damage_type("explosive") == "heat", "explosive -> heat")
	_check(MechaHealthBase.normalize_damage_type("melee") == "blunt", "melee -> blunt")
	_check(MechaHealthBase.normalize_damage_type("rail") == "pierce", "rail -> pierce")


# Builds a bare MechaHealthBase with one controlled body part, so the armor
# defense-matching rule is tested in isolation.
func _make_part_health(defense: String, armor_class: float) -> Node:
	var hs = MechaHealthBase.new()
	hs.name = "HealthSystem"
	hs.is_player = false
	add_child(hs)
	hs.parts = {
		"body": {
			"armor_hp": 100.0, "max_armor": 100.0, "frame_hp": 100.0, "max_frame": 100.0,
			"armor_class": armor_class, "defense_type": defense,
			"armor_broken": false, "destroyed": false, "mesh": null,
		}
	}
	hs._calculate_totals()
	await get_tree().process_frame
	return hs


func _verify_armor_defense() -> void:
	# Anti-pierce plate with armor_class 2.0: a matching pierce hit is halved,
	# a mismatched heat/blunt hit lands at full strength.
	var hs = await _make_part_health("pierce", 2.0)
	hs.take_damage_to_part("body", 100.0, "pierce", "armor")
	_check(is_equal_approx(hs.parts["body"]["armor_hp"], 50.0), "matching pierce hit reduced by armor_class (100 -> 50)")
	hs.take_damage_to_part("body", 50.0, "heat", "armor")
	_check(is_equal_approx(hs.parts["body"]["armor_hp"], 0.0), "mismatched heat ignores armor_class (50 -> 0)")
	_check(hs.parts["body"]["armor_broken"], "armor breaks at 0 HP")
	# Frame takes over at full strength regardless of type.
	hs.take_damage_to_part("body", 30.0, "heat", "frame")
	_check(is_equal_approx(hs.parts["body"]["frame_hp"], 70.0), "frame damage ignores defense type (100 -> 70)")
	hs.queue_free()
	await get_tree().process_frame

	# Balanced plate (no defense_type): armor_class applies to ALL types.
	var bal = await _make_part_health("", 2.0)
	bal.take_damage_to_part("body", 100.0, "heat", "armor")
	_check(is_equal_approx(bal.parts["body"]["armor_hp"], 50.0), "balanced plate resists every type at armor_class (100 -> 50)")
	bal.take_damage_to_part("body", 100.0, "pierce", "armor")
	_check(is_equal_approx(bal.parts["body"]["armor_hp"], 0.0), "balanced plate resists pierce too (50 -> 0)")
	bal.queue_free()
	await get_tree().process_frame


# Player shield: build a WeaponManager on a bare mecha with an anti-pierce
# shield equipped in the left hand, then hit the health path.
func _verify_player_shield() -> void:
	var mecha := CharacterBody3D.new()
	mecha.name = "Mecha"
	add_child(mecha)
	var wm := Node3D.new()
	wm.name = "WeaponManager"
	wm.set_script(preload("res://scripts/mecha/weapon_manager.gd"))
	mecha.add_child(wm)
	await get_tree().process_frame

	# Equip an anti-pierce shield (the light buckler) in the left hand and raise
	# it.
	var shield: WeaponPart = load("res://resources/mech/stock/weapon_light_buckler.tres")
	_check(shield.get_shield_type() == "pierce", "light buckler is anti-pierce")
	wm.left_hand = shield
	wm._update_weapon_visuals()
	wm._toggle_shield("left")
	_check(wm.is_shield_active(), "player shield raises")
	_check(wm.get_shield_hand() == "left", "get_shield_hand reports the left hand")
	var full_hp: float = wm.shield_current_hp
	_check(full_hp > 0.0, "player shield starts full")

	# Pierce (the plate's own anti-type) drains at 40%: 50 * 0.4 = 20 HP off.
	wm.absorb_damage_with_shield(50.0, "pierce")
	_check(is_equal_approx(wm.shield_current_hp, full_hp - 20.0), "anti-pierce plate drains 40% vs pierce")
	# Heat drains at 100%: 50 HP off.
	wm.absorb_damage_with_shield(50.0, "heat")
	_check(is_equal_approx(wm.shield_current_hp, full_hp - 70.0), "anti-pierce plate drains 100% vs heat")
	# Legacy kinetic = pierce -> 40% (another 20 off).
	wm.absorb_damage_with_shield(50.0, "kinetic")
	_check(is_equal_approx(wm.shield_current_hp, full_hp - 90.0), "kinetic normalizes to pierce for the plate (40% drain)")

	# No regen: time passing never restores the plate (no tick hook exists).
	var now_hp: float = wm.shield_current_hp
	await get_tree().process_frame
	_check(is_equal_approx(wm.shield_current_hp, now_hp), "player shield never regenerates")

	# Drain to zero: the plate breaks and stays broken — re-raising does not
	# bring it back (physical plates stay damaged for the battle).
	wm.absorb_damage_with_shield(9999.0, "heat")
	_check(not wm.is_shield_active(), "drained player shield breaks")
	wm._toggle_shield("left")
	_check(not wm.is_shield_active(), "a broken plate cannot be raised again")
	_check(wm.shield_current_hp == 0.0, "broken plate stays at 0 HP")

	# A FRESH shield (never armed this battle) still raises at full HP.
	var shield2: WeaponPart = load("res://resources/mech/stock/weapon_heavy_shield.tres")
	_check(shield2.get_shield_type() == "heat", "heavy shield is anti-heat")
	wm.left_hand = shield2
	wm._toggle_shield("left")
	_check(wm.is_shield_active(), "a fresh plate raises")
	_check(is_equal_approx(wm.shield_current_hp, shield2.shield_hp), "fresh plate arms at full HP")

	mecha.queue_free()
	await get_tree().process_frame
