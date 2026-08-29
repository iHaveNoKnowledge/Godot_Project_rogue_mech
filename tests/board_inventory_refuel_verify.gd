extends Node

func _ready() -> void:
	print("--- Running board_inventory_refuel_verify ---")
	_test_convoy_refueling_mechanic()
	_test_mecha_energy_recharging_mechanic()
	_test_pilot_medical_and_rations()
	_test_board_inventory_modal_ui()
	print("All board_inventory_refuel_verify tests passed successfully!")
	get_tree().quit(0)

func _check(condition: bool, msg: String) -> void:
	if condition:
		print("  PASS: %s" % msg)
	else:
		push_error("  FAIL: %s" % msg)
		assert(condition, msg)

func _test_convoy_refueling_mechanic() -> void:
	print("Testing Convoy Refueling via Fuel Canister item...")
	GlobalData.fuel.convoy_fuel = 100.0
	GlobalData.fuel.convoy_max_fuel = 500.0
	GlobalData.fuel_inventory["fuel_canister"] = 3

	var gained = GlobalData.use_fuel_item("fuel_canister", "convoy")
	_check(is_equal_approx(gained, 150.0), "Convoy gained 150 fuel from fuel canister")
	_check(is_equal_approx(GlobalData.fuel.convoy_fuel, 250.0), "Convoy fuel updated to 250/500")
	_check(GlobalData.get_fuel_item_count("fuel_canister") == 2, "Fuel canister count decreased from 3 to 2")

func _test_mecha_energy_recharging_mechanic() -> void:
	print("Testing Mecha Energy Recharging via Energy Cell item...")
	GlobalData.fuel.mech_energy = 300.0
	GlobalData.fuel.mech_max_energy = 1000.0
	GlobalData.fuel_inventory["energy_cell_pack"] = 2

	var gained = GlobalData.use_fuel_item("energy_cell_pack", "mecha")
	_check(is_equal_approx(gained, 200.0), "Mecha gained 200 energy from battery pack")
	_check(is_equal_approx(GlobalData.fuel.mech_energy, 500.0), "Mecha energy updated to 500/1000")
	_check(GlobalData.get_fuel_item_count("energy_cell_pack") == 1, "Energy cell pack count decreased from 2 to 1")

func _test_pilot_medical_and_rations() -> void:
	print("Testing Pilot Medical Supplies and Combat Rations...")
	GlobalData.pilot.pilot_hp = 40.0
	GlobalData.pilot.pilot_max_hp = 100.0
	GlobalData.fuel.pilot_stamina = 10.0
	GlobalData.fuel.pilot_max_stamina = 50.0

	# Test Medkit
	GlobalData.pilot.pilot_items["medkit_small"] = 1
	var healed = PilotSystem.use_heal_item("medkit_small")
	_check(is_equal_approx(healed, 30.0), "Pilot healed 30 HP via field medkit")
	_check(is_equal_approx(GlobalData.pilot.pilot_hp, 70.0), "Pilot HP updated to 70/100")
	_check(PilotSystem.get_item_count("medkit_small") == 0, "Medkit consumed")

	# Test Rations
	GlobalData.pilot.pilot_items["rations_combat"] = 1
	var modal_script = preload("res://scripts/ui/board_inventory_modal.gd")
	var modal = modal_script.new()
	add_child(modal)
	modal._use_medical_on_player({"id": "rations_combat", "name": "Combat Rations", "heal": 15, "stamina": 30})
	_check(is_equal_approx(GlobalData.pilot.pilot_hp, 85.0), "Pilot HP healed +15 HP from ration")
	_check(is_equal_approx(GlobalData.fuel.pilot_stamina, 40.0), "Pilot Stamina restored +30 from ration")
	modal.queue_free()

func _test_board_inventory_modal_ui() -> void:
	print("Testing BoardInventoryModal category tabs and layout...")
	var modal_script = preload("res://scripts/ui/board_inventory_modal.gd")
	var modal = modal_script.new()
	add_child(modal)

	modal.switch_category("fuel")
	_check(modal.item_list_container.get_child_count() > 0, "Fuel items populated in list")

	modal.switch_category("medical")
	_check(modal.item_list_container.get_child_count() > 0, "Medical items populated in list")

	modal.switch_category("ammo")
	_check(modal.item_list_container.get_child_count() == 4, "4 Ammo reserve types populated in list")

	modal.switch_category("parts")
	_check(modal.current_category == "parts", "Switched to parts category")

	modal.show_toast("Refuel test complete!", false)
	_check(modal.toast_label.text.contains("Refuel test complete!"), "Toast alert displayed message")

	modal.queue_free()
