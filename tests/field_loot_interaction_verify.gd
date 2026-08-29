extends Node

var _fails: int = 0
var _checks: int = 0

func _check(condition: bool, name: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: " + name)
	else:
		_fails += 1
		printerr("  FAIL: " + name)

func _ready() -> void:
	print("--- Running field_loot_interaction_verify ---")
	_test_key_bindings()
	_test_field_loot_modal_layout()
	_test_ammo_unloading()
	_test_convoy_tagging()
	_test_drag_and_drop_equip_and_swap()
	_test_weight_overload_protection()

	print("FIELD_LOOT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _test_key_bindings() -> void:
	print("Testing Key Bindings: [G] Dismount, [F] Loot/Interact...")
	GameManager.current_state = GameManager.State.COMBAT

	var mecha = CharacterBody3D.new()
	mecha.name = "MechaActor"
	mecha.set_script(load("res://scripts/mecha/mecha_controller.gd"))
	add_child(mecha)

	# 1. KEY_F should NOT trigger dismount
	var f_ev := InputEventKey.new()
	f_ev.pressed = true
	f_ev.keycode = KEY_F
	mecha._unhandled_input(f_ev)
	_check(not mecha.has_meta("is_parked"), "KEY_F does NOT trigger mecha dismount")

	# 2. KEY_G triggers dismount
	var g_ev := InputEventKey.new()
	g_ev.pressed = true
	g_ev.keycode = KEY_G
	mecha._unhandled_input(g_ev)
	_check(mecha.has_meta("last_mount_toggle_time"), "KEY_G triggers mecha dismount flow")

	mecha.queue_free()


func _test_field_loot_modal_layout() -> void:
	print("Testing FieldLootModal Layout & Panels...")
	var modal_scene = preload("res://scenes/ui/field_loot_modal.tscn")
	var modal = modal_scene.instantiate()
	add_child(modal)

	_check(modal.left_panel != null, "Left Panel (Ground Salvage) exists")
	_check(modal.right_panel != null, "Right Panel (Loadout & Carrier) exists")
	_check(modal.left_hand_card != null, "Left Hand card slot exists in top row")
	_check(modal.right_hand_card != null, "Right Hand card slot exists in top row")
	_check(modal.carrier_list_container != null, "Carrier Field Pack list exists in bottom section")
	_check(modal.weight_bar != null, "Weight progress bar exists")

	modal.open_modal()
	_check(modal.is_open, "Modal marked as is_open when opened")
	_check(modal.visible, "Modal visible on screen")

	modal.close_modal()
	_check(not modal.is_open, "Modal marked as not open after close")
	_check(not modal.visible, "Modal hidden after close")

	modal.queue_free()


func _test_ammo_unloading() -> void:
	print("Testing Ammo Unloading from Ground Weapons...")
	var pickup_scene = Area3D.new()
	pickup_scene.set_script(load("res://scripts/mecha/weapon_pickup.gd"))
	var w: WeaponPart = preload("res://resources/mech/stock/weapon_assault_cannon.tres")
	pickup_scene.weapon_resource = w
	pickup_scene.current_ammo = 45
	add_child(pickup_scene)

	var init_reserve = LoadoutSystem.get_reserve_ammo("kinetic")
	var drained = pickup_scene.unload_ammo_to_player()

	_check(drained == 45, "Unloaded all 45 rounds from ground weapon")
	_check(pickup_scene.current_ammo == 0, "Ground weapon current_ammo is now 0")
	_check(LoadoutSystem.get_reserve_ammo("kinetic") >= init_reserve + 45, "Player ammo reserve received +45 rounds")

	pickup_scene.queue_free()


func _test_convoy_tagging() -> void:
	print("Testing Convoy Salvage Tagging (Sandwich Triangle Badge)...")
	var pickup = Area3D.new()
	pickup.set_script(load("res://scripts/mecha/weapon_pickup.gd"))
	var w: WeaponPart = preload("res://resources/mech/stock/weapon_beam_rifle.tres")
	pickup.weapon_resource = w
	add_child(pickup)

	_check(not pickup.is_tagged_for_convoy, "Weapon initially not tagged")
	pickup.tag_for_convoy(true)
	_check(pickup.is_tagged_for_convoy, "Weapon is now tagged for convoy salvage")
	_check(pickup.has_node("ConvoyTagBadge"), "3D ConvoyTagBadge spawned above weapon")

	# Test victory collection
	var loot_sys = Node3D.new()
	loot_sys.set_script(load("res://scripts/systems/loot_system.gd"))
	add_child(loot_sys)

	var salvaged = loot_sys.collect_convoy_tagged_loot()
	_check(salvaged.has(w.weapon_name), "LootSystem successfully salvaged tagged weapon into depot")

	loot_sys.queue_free()


func _test_drag_and_drop_equip_and_swap() -> void:
	print("Testing Drag & Drop: Equip to Hands & Weapon Swap...")
	var modal_scene = preload("res://scenes/ui/field_loot_modal.tscn")
	var modal = modal_scene.instantiate()
	add_child(modal)

	var dummy_mecha = Node3D.new()
	var wm = Node3D.new()
	wm.name = "WeaponManager"
	wm.set_script(load("res://scripts/mecha/weapon_manager.gd"))
	dummy_mecha.add_child(wm)
	add_child(dummy_mecha)

	modal.open_modal(dummy_mecha)

	var w1: WeaponPart = preload("res://resources/mech/stock/weapon_assault_cannon.tres")
	var w2: WeaponPart = preload("res://resources/mech/stock/weapon_heat_blade.tres")

	# 1. Equip w1 to left hand
	modal._equip_to_hand("left", w1, "ground")
	_check(wm.left_hand == w1, "Equipped assault rifle to Left Hand")

	# 2. Swap w2 into left hand (w1 should be returned to carrier pack)
	modal._equip_to_hand("left", w2, "ground")
	_check(wm.left_hand == w2, "Swapped heat blade into Left Hand")
	_check(wm.carry.has(w1), "Replaced weapon (assault rifle) safely stored in Carrier")

	# 3. Equip to right hand
	modal._equip_to_hand("right", w1, "carrier")
	_check(wm.right_hand == w1, "Equipped assault rifle to Right Hand")

	modal.close_modal()
	modal.queue_free()
	dummy_mecha.queue_free()


func _test_weight_overload_protection() -> void:
	print("Testing Field Pack Weight Limit & Overload Protection...")
	var modal_scene = preload("res://scenes/ui/field_loot_modal.tscn")
	var modal = modal_scene.instantiate()
	add_child(modal)

	var dummy_mecha = Node3D.new()
	var wm = Node3D.new()
	wm.name = "WeaponManager"
	wm.set_script(load("res://scripts/mecha/weapon_manager.gd"))
	dummy_mecha.add_child(wm)
	add_child(dummy_mecha)

	modal.open_modal(dummy_mecha)

	var heavy_w = WeaponPart.new()
	heavy_w.weapon_name = "Super Heavy Cannon"
	heavy_w.weight = 999.0 # Impossible weight

	var init_count = wm.carry.size()
	modal._store_to_carrier(heavy_w, "ground")
	_check(wm.carry.size() == init_count, "Overweight weapon (999kg) rejected from Field Pack")

	modal.close_modal()
	modal.queue_free()
	dummy_mecha.queue_free()
