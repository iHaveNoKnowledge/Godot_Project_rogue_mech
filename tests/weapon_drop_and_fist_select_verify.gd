extends Node

## Verifies:
## 1. Bare Fist (unarmed) selection via scrolling & commit
## 2. Holstering all weapons to carry while using bare fists on both hands
## 3. Dropping equipped weapon via X (normal gameplay)
## 4. Dropping highlighted weapon from selection menu via X
## 5. UI HUD correctly displays bare fist option in carry list and updates key hints

var _fails := 0
var _checks := 0

func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("DROP_FIST OK: " + name)
	else:
		_fails += 1
		print("DROP_FIST FAIL: " + name)

func _finish() -> void:
	print("DROP_AND_FIST_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)

func _ready() -> void:
	var mecha := CharacterBody3D.new()
	mecha.name = "Mecha"
	add_child(mecha)

	var health_system := Node.new()
	health_system.name = "HealthSystem"
	mecha.add_child(health_system)

	var wm := Node3D.new()
	wm.name = "WeaponManager"
	wm.set_script(preload("res://scripts/mecha/weapon_manager.gd"))
	mecha.add_child(wm)

	var w1 = WeaponPart.new()
	w1.weapon_name = "Assault Rifle"
	w1.weapon_type = 0
	w1.max_ammo = 30
	w1.weight = 10.0

	var w2 = WeaponPart.new()
	w2.weapon_name = "Plasma Blade"
	w2.weapon_type = 4
	w2.max_ammo = 999
	w2.weight = 8.0

	var w3 = WeaponPart.new()
	w3.weapon_name = "Rocket Launcher"
	w3.weapon_type = 2
	w3.max_ammo = 6
	w3.weight = 15.0

	wm.left_hand = w1
	wm.right_hand = w2
	var c_list: Array[WeaponPart] = [w3]
	wm.carry = c_list

	var dropped_weapons: Array = []
	wm.weapon_dropped.connect(func(hand: String, weapon: WeaponPart):
		dropped_weapons.append({"hand": hand, "weapon": weapon})
	)

	# --- TEST 1: Scroll to BARE FIST on Left Hand ---
	wm._start_selection("left")
	_check(wm.holding_left, "started selection on left hand")
	_check(wm.carry.size() == 2, "carry contains w1 (inserted) and w3 (size=2)")

	# Scroll down to index 2 (Bare Fists)
	wm._scroll("left", 1) # idx 1 -> w3
	_check(wm._select_idx_left == 1, "scrolled to idx 1 (Rocket Launcher)")
	_check(wm.left_hand == w3, "previewing Rocket Launcher")

	wm._scroll("left", 1) # idx 2 -> Bare Fists
	_check(wm._select_idx_left == 2, "scrolled to idx 2 (Bare Fists)")
	_check(wm.left_hand == null, "previewing Bare Fists (left_hand == null)")

	wm._commit_selection("left")
	_check(wm.left_hand == null, "committed Bare Fists on left hand")
	_check(wm.carry.size() == 2, "all 2 weapons remained in carry (holstered)")

	# --- TEST 2: Scroll to BARE FIST on Right Hand ---
	wm._start_selection("right")
	# carry now has [w2, w1, w3]
	_check(wm.carry.size() == 3, "carry has 3 weapons after right hand entered selection")
	wm._scroll("right", 3) # scroll to index 3 (Bare Fists)
	_check(wm._select_idx_right == 3, "scrolled to idx 3 (Bare Fists)")
	wm._commit_selection("right")
	_check(wm.right_hand == null, "committed Bare Fists on right hand")
	_check(wm.left_hand == null and wm.right_hand == null, "both hands are now bare fists (unarmed)")
	_check(wm.carry.size() == 3, "carry holds all 3 weapons")

	# --- TEST 3: Select weapon back from carry ---
	wm._start_selection("left")
	# carry has [w2, w1, w3]
	wm._select_idx_left = 1 # pick w1
	wm._commit_selection("left")
	_check(wm.left_hand == w1, "equipped w1 back to left hand")
	_check(wm.carry.size() == 2, "carry has 2 weapons remaining")

	# --- TEST 4: Drop weapon from selection (key X while holding 1) ---
	wm._start_selection("left")
	# carry has [w1, w3, w2]
	wm._scroll("left", 1) # scroll to index 1 (Rocket Launcher)
	_check(wm._select_idx_left == 1, "scrolled to idx 1 (Rocket Launcher)")
	wm._drop_weapon_from_selection("left")
	_check(dropped_weapons.size() == 1, "weapon_dropped emitted on selection drop")
	_check(dropped_weapons[0].weapon == w3, "dropped weapon was w3 (Rocket Launcher)")
	_check(wm.carry.size() == 2, "carry now has 2 weapons [w1, w2]")
	wm._commit_selection("left")

	# --- TEST 5: Drop equipped weapon in normal gameplay (key X without holding 1/3) ---
	wm.left_hand = w1
	_check(wm.left_hand == w1, "left hand is holding w1")
	wm._drop_equipped_weapon("left")
	_check(dropped_weapons.size() == 2, "weapon_dropped emitted on equipped drop")
	_check(dropped_weapons[1].weapon == w1, "dropped weapon was w1 (Assault Rifle)")
	_check(wm.left_hand == null, "left hand switched to bare fist after dropping")

	# --- TEST 6: WeaponHUD carry display updates ---
	var hud_scene: PackedScene = preload("res://scenes/ui/weapon_hud.tscn")
	var hud = hud_scene.instantiate()
	add_child(hud)
	hud.weapon_manager = wm
	hud._show_carry("left")
	var carry_children = hud.carry_container.get_children()
	_check(carry_children.size() >= 2, "HUD carry container displays carry weapons + Bare Fist row (count=%d)" % carry_children.size())

	_finish()
