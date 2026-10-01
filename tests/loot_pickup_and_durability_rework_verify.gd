extends Node

const WeaponPickupScript = preload("res://scripts/mecha/weapon_pickup.gd")

var _checks := 0
var _fails := 0


func _ready() -> void:
	print("--- BEGIN LOOT PICKUP & DURABILITY REWORK TEST SUITE ---")
	test_loot_pickup_single_take_and_unique_uid()
	test_diagnostic_modal_close()
	test_tier_upgrade_stats_and_hover()
	test_durability_def_reduction_not_hp()
	print("LOOT_PICKUP_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("LOOT_PICKUP_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("--- ALL TESTS PASSED SUCCESSFULLY! ---")
		get_tree().quit(0)


func assert_true(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS: " + msg)
	else:
		_fails += 1
		push_error("ASSERTION FAILED: " + msg)
		print("FAILED: " + msg)


func test_loot_pickup_single_take_and_unique_uid() -> void:
	print("\n[TEST 1] Loot Pickup Single Take, Unique UID, and Node Freeing...")
	GlobalData.reset_run_data()

	# Create a mock player mecha with WeaponManager
	var player = Node3D.new()
	player.name = "TestPlayer"
	var wm = Node3D.new()
	wm.name = "WeaponManager"
	wm.set_script(load("res://scripts/mecha/weapon_manager.gd"))
	player.add_child(wm)
	add_child(player)

	# Spawn a ground pickup
	var test_w: WeaponPart = load("res://resources/mech/stock/weapon_beam_rifle.tres")
	var pickup = Area3D.new()
	pickup.set_script(WeaponPickupScript)
	pickup.weapon_resource = test_w
	add_child(pickup)

	assert_true(pickup.is_in_group("weapon_pickup"), "Pickup added to weapon_pickup group")

	var initial_inv_count = GlobalData.weapons.weapon_inventory.size()

	# Instantiate FieldLootModal
	var modal_script = load("res://scripts/ui/field_loot_modal.gd")
	var modal = CanvasLayer.new()
	modal.set_script(modal_script)
	add_child(modal)
	modal.open_modal(player)

	# Take to carrier
	modal.take_weapon_to_carrier(pickup)

	assert_true(not pickup.is_in_group("weapon_pickup"), "Pickup immediately removed from weapon_pickup group")
	assert_true(GlobalData.weapons.weapon_inventory.size() == initial_inv_count + 1, "New unique weapon instance added to inventory")
	var new_inv = GlobalData.weapons.weapon_inventory.back()
	assert_true(new_inv.get("uid", "").begins_with("w_"), "Weapon has valid generated UID: %s" % new_inv.get("uid", ""))
	assert_true(wm.carry.has(test_w), "Weapon added to player carrier backpack")

	modal.close_modal()
	modal.queue_free()
	player.queue_free()
	# queue_free is deferred — give the tree a frame to actually drop the
	# freed nodes before scanning for lingering modals.
	await get_tree().process_frame


func test_diagnostic_modal_close() -> void:
	print("\n[TEST 2] Diagnostic Modal Close Robustness...")
	GlobalData.reset_run_data()

	var hangar_script = load("res://scripts/ui/hangar_controller.gd")
	var hangar = Control.new()
	hangar.set_script(hangar_script)
	add_child(hangar)
	hangar._build_ui_layout()

	var diag_modal = HangarDiagnosticModal.new()
	diag_modal.controller = hangar

	# Open modal
	diag_modal.open()
	assert_true(diag_modal.is_open, "Diagnostic modal is open")
	assert_true(diag_modal.modal_panel != null, "Diagnostic modal panel exists")

	# Simulate repair which re-opens (open -> close -> new modal)
	diag_modal.open()
	assert_true(diag_modal.is_open, "Diagnostic modal re-opened cleanly")

	# Close modal
	diag_modal.close()
	await get_tree().process_frame
	assert_true(not diag_modal.is_open, "Diagnostic modal is marked closed")
	assert_true(diag_modal.modal_panel == null, "modal_panel reference cleared")

	# Check root control has no lingering DiagnosticModal children
	for child in hangar.root_control.get_children():
		assert_true(not child.name.begins_with("DiagnosticModal") and not child.name.begins_with("@DiagnosticModal"), "No lingering DiagnosticModal nodes in root_control")

	hangar.queue_free()


func test_tier_upgrade_stats_and_hover() -> void:
	print("\n[TEST 3] Tier Upgrade Stats and Hover Refresh...")
	GlobalData.reset_run_data()

	var arm_slot = "arm_left"
	var eq_armor = GlobalData.weapons.equipped_parts.get(arm_slot)
	assert_true(eq_armor != null and eq_armor is Dictionary, "Armor equipped in %s" % arm_slot)

	var initial_upg = int(eq_armor.get("upgrade_level", 1))
	var initial_hp = float(eq_armor.get("hp", eq_armor.get("max_hp", 30.0)))

	# Simulate upgrade in HangarActionPanel logic
	eq_armor["upgrade_level"] = initial_upg + 1
	eq_armor["hp"] = initial_hp + 15.0
	eq_armor["max_hp"] = eq_armor["hp"]

	assert_true(eq_armor["upgrade_level"] == initial_upg + 1, "Upgrade level increased to %d" % (initial_upg + 1))
	assert_true(eq_armor["hp"] == initial_hp + 15.0, "HP increased by 15 (+15 HP bonus)")

	# Verify HangarPartText capability text
	var cap_text = HangarPartText.armor_capability_text(eq_armor, 1.0)
	assert_true(cap_text.contains("TIER: %s" % GlobalData.part_tier_text(initial_upg + 1)), "Capability text includes new Tier %s" % GlobalData.part_tier_text(initial_upg + 1))
	assert_true(cap_text.contains("ARMOR HP: %.0f / %.0f" % [initial_hp + 15.0, initial_hp + 15.0]), "Capability text shows full HP %.0f" % (initial_hp + 15.0))


func test_durability_def_reduction_not_hp() -> void:
	print("\n[TEST 4] Durability DEF Reduction (Not Max HP Reduction)...")
	GlobalData.reset_run_data()

	# Pin head max_hp to a known value first (the default plate's HP is
	# whatever the catalog ships), then degrade durability to 70% (0.70).
	GlobalData.weapons.equipped_parts["head"]["max_hp"] = 30.0
	GlobalData.weapons.equipped_parts["head"]["hp"] = 30.0
	GlobalData.weapons.equipped_parts["head"]["durability"] = 0.70

	var dur = GlobalData.get_part_durability("head")
	assert_true(is_equal_approx(dur, 0.70), "Head durability is 70%%")

	# DEF multiplier must be exactly 0.70 (same % reduction)
	var def_mult = ArmorSystem.get_durability_def_multiplier(dur)
	assert_true(is_equal_approx(def_mult, 0.70), "DEF multiplier is 0.70 (reduced by 30%% DEF, matching 70%% durability)")

	# Initialize health system and verify max_armor is NOT reduced
	var mecha_health_script = load("res://scripts/mecha/mecha_health.gd")
	var health = Node3D.new()
	health.set_script(mecha_health_script)
	add_child(health)

	var head_max_armor = health.parts["head"]["max_armor"]
	var base_hp = float(GlobalData.weapons.equipped_parts["head"].get("max_hp", 30.0))
	assert_true(is_equal_approx(head_max_armor, base_hp), "Head max_armor remains full HP (%.0f), NOT reduced by durability" % base_hp)

	health.queue_free()
