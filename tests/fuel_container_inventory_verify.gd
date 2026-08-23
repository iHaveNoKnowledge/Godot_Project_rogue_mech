extends Node

## ---------------------------------------------------------------------------
## VERIFICATION: Fuel Container Inventory (GDD §4.1)
##
## Run: godot --headless --path . res://tests/fuel_container_inventory_verify.tscn
## ---------------------------------------------------------------------------

var _checks := 0
var _fails := 0

# FuelType constants (must match FuelContainerInventory.FuelType enum)
const FT_CRUDE := 0
const FT_REFINED := 1
const FT_BIO := 2

const FCI = preload("res://scripts/systems/fuel_container_inventory.gd")


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("  ✔ %s" % msg)
	else:
		_fails += 1
		print("  ✘ FAIL: %s" % msg)


func _ready() -> void:
	GlobalData.reset_run_data()
	print("\n=== FuelContainerInventory Verification (GDD §4.1) ===\n")

	_test_container_creation()
	_test_auto_stacking()
	_test_auto_stacking_creates_new_when_all_full()
	_test_auto_stacking_no_room()
	_test_consume_full_first()
	_test_consume_by_type()
	_test_add_container_directly()
	_test_total_fuel_by_type()
	_test_compatible_fuel_for_core()
	_test_display()
	_test_serialization()
	_test_compact_removes_empty()
	_test_fuel_manager_integration()

	print("\n--- RESULT: checks=%d  fails=%d ---\n" % [_checks, _fails])
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


# --------------------------------------------------------------------------
# 1. Container creation
# --------------------------------------------------------------------------

func _test_container_creation() -> void:
	print("[1] Container Creation")
	var c = FCI.create_container(FT_CRUDE, 10.0)
	_check(c["type"] == FT_CRUDE, "type is CRUDE_OIL")
	_check(c["capacity"] == 10.0, "capacity is 10.0")
	_check(c["current"] == 0.0, "current starts at 0")

	var filled = FCI.create_filled_container(FT_REFINED, 20.0)
	_check(filled["current"] == 20.0, "filled container starts at capacity")


# --------------------------------------------------------------------------
# 2. Auto-stacking: partial containers get filled first
# --------------------------------------------------------------------------

func _test_auto_stacking() -> void:
	print("\n[2] Auto-Stacking")
	var inv = FCI.new()

	# Add 4 fuel — creates a 6% container with 4 fuel (partial)
	var absorbed = inv.add_fuel(FT_CRUDE, 4.0)
	_check(absorbed == 4.0, "absorbed all 4 fuel")
	_check(inv.get_slot_count() == 1, "one container created")
	var c = inv.get_containers()[0]
	_check(c["current"] == 4.0, "container has 4 fuel")
	_check(c["capacity"] == 6.0, "container capacity is 6 (smallest fit)")

	# Add 2 more — should fill the partial first (4+2=6, within 6% cap)
	absorbed = inv.add_fuel(FT_CRUDE, 2.0)
	_check(absorbed == 2.0, "absorbed all 2 fuel")
	_check(inv.get_slot_count() == 1, "still one container (auto-stacked)")
	c = inv.get_containers()[0]
	_check(c["current"] == 6.0, "container now full at 6")


# --------------------------------------------------------------------------
# 3. Auto-stacking creates new container when all existing are full
# --------------------------------------------------------------------------

func _test_auto_stacking_creates_new_when_all_full() -> void:
	print("\n[3] Auto-Stack Creates New When All Full")
	var inv = FCI.new()

	# Fill a 10% container
	inv.add_fuel(FT_CRUDE, 10.0)
	_check(inv.get_containers()[0]["current"] == 10.0, "first container full at 10")

	# Add more — should create a new container
	var absorbed = inv.add_fuel(FT_CRUDE, 6.0)
	_check(absorbed == 6.0, "absorbed 6 fuel")
	_check(inv.get_slot_count() == 2, "two containers now")
	var c2 = inv.get_containers()[1]
	_check(c2["current"] == 6.0, "second container has 6 fuel")


# --------------------------------------------------------------------------
# 4. Auto-stacking respects max slots
# --------------------------------------------------------------------------

func _test_auto_stacking_no_room() -> void:
	print("\n[4] Auto-Stack Respects Max Slots")
	var inv = FCI.new()
	inv._max_slots = 2

	inv.add_fuel(FT_CRUDE, 100.0)
	inv.add_fuel(FT_CRUDE, 100.0)
	_check(inv.get_slot_count() == 2, "two slots used")

	# Third add should fail (partial or new)
	var absorbed = inv.add_fuel(FT_CRUDE, 20.0)
	_check(absorbed == 0.0, "no fuel absorbed when inventory full")
	_check(inv.get_slot_count() == 2, "still two slots")


# --------------------------------------------------------------------------
# 5. Consume drains full containers first
# --------------------------------------------------------------------------

func _test_consume_full_first() -> void:
	print("\n[5] Consume Drains Full Containers First")
	var inv = FCI.new()
	inv.add_container(FT_CRUDE, 10.0, 10.0)  # full
	inv.add_container(FT_CRUDE, 10.0, 5.0)   # partial

	var consumed = inv.consume_fuel(8.0)
	_check(consumed == 8.0, "consumed 8 fuel")
	# Full container should be drained first: 10 -> 2
	var c1 = inv.get_containers()[0]
	_check(c1["current"] == 2.0, "full container drained to 2.0")
	# Partial container untouched
	var c2 = inv.get_containers()[1]
	_check(c2["current"] == 5.0, "partial container untouched at 5.0")


# --------------------------------------------------------------------------
# 6. Consume by type
# --------------------------------------------------------------------------

func _test_consume_by_type() -> void:
	print("\n[6] Consume By Type")
	var inv = FCI.new()
	inv.add_container(FT_CRUDE, 20.0, 20.0)
	inv.add_container(FT_REFINED, 20.0, 20.0)

	var consumed = inv.consume_fuel_by_type(FT_CRUDE, 15.0)
	_check(consumed == 15.0, "consumed 15 crude oil")
	_check(inv.total_fuel_by_type(FT_CRUDE) == 5.0, "crude remaining: 5")
	_check(inv.total_fuel_by_type(FT_REFINED) == 20.0, "refined untouched: 20")


# --------------------------------------------------------------------------
# 7. Add container directly
# --------------------------------------------------------------------------

func _test_add_container_directly() -> void:
	print("\n[7] Add Container Directly")
	var inv = FCI.new()
	var added = inv.add_container(FT_BIO, 6.0, 3.0)
	_check(added, "container added")
	_check(inv.get_slot_count() == 1, "one slot used")
	_check(inv.get_containers()[0]["current"] == 3.0, "container has 3 fuel")
	_check(inv.total_fuel_by_type(FT_BIO) == 3.0, "bio fuel total: 3")


# --------------------------------------------------------------------------
# 8. Total fuel by type
# --------------------------------------------------------------------------

func _test_total_fuel_by_type() -> void:
	print("\n[8] Total Fuel By Type")
	var inv = FCI.new()
	inv.add_container(FT_CRUDE, 10.0, 10.0)
	inv.add_container(FT_REFINED, 20.0, 15.0)
	inv.add_container(FT_BIO, 6.0, 2.0)

	_check(inv.total_fuel_by_type(FT_CRUDE) == 10.0, "crude total: 10")
	_check(inv.total_fuel_by_type(FT_REFINED) == 15.0, "refined total: 15")
	_check(inv.total_fuel_by_type(FT_BIO) == 2.0, "bio total: 2")
	_check(inv.total_fuel() == 27.0, "grand total: 27")


# --------------------------------------------------------------------------
# 9. Compatible fuel for core classes
# --------------------------------------------------------------------------

func _test_compatible_fuel_for_core() -> void:
	print("\n[9] Compatible Fuel for Core Classes")
	var inv = FCI.new()
	inv.add_container(FT_CRUDE, 20.0, 20.0)
	inv.add_container(FT_REFINED, 10.0, 10.0)
	inv.add_container(FT_BIO, 6.0, 6.0)

	_check(inv.total_fuel_compatible("convoy") == 26.0, "convoy compatible: 26 (crude+bio)")
	_check(inv.total_fuel_compatible("combustion") == 26.0, "combustion compatible: 26")
	_check(inv.total_fuel_compatible("hybrid") == 16.0, "hybrid compatible: 16 (refined+bio)")
	_check(inv.total_fuel_compatible("ancient") == 10.0, "ancient compatible: 10 (refined only)")
	_check(inv.total_fuel_compatible("all") == 36.0, "all compatible: 36")


# --------------------------------------------------------------------------
# 10. Display
# --------------------------------------------------------------------------

func _test_display() -> void:
	print("\n[10] Display")
	var inv = FCI.new()
	_check(inv.inventory_display() == "EMPTY", "empty inventory shows EMPTY")

	inv.add_container(FT_CRUDE, 20.0, 20.0)
	inv.add_container(FT_REFINED, 10.0, 5.0)
	var display = inv.inventory_display()
	_check(display.contains("Crude"), "display contains Crude")
	_check(display.contains("Refined"), "display contains Refined")
	_check(display.contains("[100%]"), "full container shows 100%")


# --------------------------------------------------------------------------
# 11. Serialization round-trip
# --------------------------------------------------------------------------

func _test_serialization() -> void:
	print("\n[11] Serialization Round-Trip")
	var inv = FCI.new()
	inv.add_container(FT_CRUDE, 20.0, 15.0)
	inv.add_container(FT_REFINED, 10.0, 10.0)

	var data = inv.serialize()
	_check(data.size() == 2, "serialized has 2 entries")

	var inv2 = FCI.new()
	inv2.deserialize(data)
	_check(inv2.get_slot_count() == 2, "deserialized has 2 containers")
	_check(inv2.total_fuel_by_type(FT_CRUDE) == 15.0, "crude fuel preserved: 15")
	_check(inv2.total_fuel_by_type(FT_REFINED) == 10.0, "refined fuel preserved: 10")


# --------------------------------------------------------------------------
# 12. Compact removes empty containers
# --------------------------------------------------------------------------

func _test_compact_removes_empty() -> void:
	print("\n[12] Compact Removes Empty")
	var inv = FCI.new()
	inv.add_container(FT_CRUDE, 10.0, 10.0)
	inv.add_container(FT_CRUDE, 6.0, 0.0)

	_check(inv.get_slot_count() == 2, "starts with 2 containers")

	# Consume all from first container
	inv.consume_fuel(10.0)
	# After consuming, empty containers should be compacted away
	_check(inv.get_slot_count() <= 1, "empty containers compacted away")
	_check(inv.total_fuel() == 0.0, "all fuel consumed")


# --------------------------------------------------------------------------
# 13. FuelManager integration
# --------------------------------------------------------------------------

func _test_fuel_manager_integration() -> void:
	print("\n[13] FuelManager Integration")
	var fm = GlobalData.fuel

	# Starting inventory should have containers
	_check(fm.mech_fuel_inventory.has_any_containers(), "mech inventory has starting containers")
	_check(fm.convoy_fuel_inventory.has_any_containers(), "convoy inventory has starting containers")

	# Add fuel via facade
	var gained = fm.add_mech_fuel(FT_CRUDE, 30.0)
	_check(gained == 30.0, "add_mech_fuel returned 30")
	_check(fm.mech_fuel_inventory.total_fuel() >= 30.0, "mech inventory has >= 30 fuel")
	_check(fm.mech_energy > 0.0, "mech_energy updated")

	# Consume via facade
	var consumed = fm.consume_mech_fuel(10.0)
	_check(consumed == 10.0, "consume_mech_fuel returned 10")

	# Display
	_check(fm.mech_fuel_display() != "EMPTY", "mech fuel display not empty")
