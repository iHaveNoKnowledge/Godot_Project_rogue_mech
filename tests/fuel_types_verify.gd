extends Node

var _checks := 0
var _fails := 0

const FT_CRUDE := 0
const FT_REFINED := 1
const FT_BIO := 2

const FCI = preload("res://scripts/systems/fuel_container_inventory.gd")
const PCS = preload("res://scripts/systems/power_core_system.gd")
const FM_SCRIPT = preload("res://scripts/systems/fuel_manager.gd")


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("  ✔ %s" % msg)
	else:
		_fails += 1
		print("  ✘ FAIL: %s" % msg)


func _ready() -> void:
	print("")
	print("=== FUEL TYPES SYSTEM VERIFICATION (GDD §4.2) ===")
	print("")

	test_fuel_type_constants()
	test_core_fuel_compatibility()
	test_refinery_basic()
	test_refinery_not_enough_crude()
	test_refinery_empty_inventory()
	test_bio_fuel_heat_penalty_tracking()
	test_fuel_type_display()
	test_consume_by_type()
	test_refinery_serialization()
	test_mech_fuel_typed_consume()

	print("")
	print("=== RESULT: %d checks, %d failures ===" % [_checks, _fails])
	print("")
	if _fails == 0:
		print("ALL TESTS PASSED ✅")
	else:
		print("SOME TESTS FAILED ❌")
	get_tree().quit(1 if _fails > 0 else 0)


func test_fuel_type_constants() -> void:
	print("[1] Fuel Type Constants")
	_check(FCI.FuelType.CRUDE_OIL == 0, "CRUDE_OIL == 0")
	_check(FCI.FuelType.REFINED_CELL == 1, "REFINED_CELL == 1")
	_check(FCI.FuelType.BIO_FUEL == 2, "BIO_FUEL == 2")
	_check(FCI.CONTAINER_SIZES.size() == 5, "5 container sizes defined")
	_check(FCI.CONTAINER_SIZES[0] == 1.0, "smallest size is 1%")
	_check(FCI.CONTAINER_SIZES[4] == 100.0, "largest size is 100%")


func test_core_fuel_compatibility() -> void:
	print("[2] Core Fuel Compatibility")
	_check(PCS.is_fuel_compatible("combustion", FT_CRUDE), "combustion accepts crude")
	_check(PCS.is_fuel_compatible("combustion", FT_BIO), "combustion accepts bio")
	_check(not PCS.is_fuel_compatible("combustion", FT_REFINED), "combustion rejects refined")
	_check(PCS.is_fuel_compatible("hybrid", FT_REFINED), "hybrid accepts refined")
	_check(PCS.is_fuel_compatible("hybrid", FT_BIO), "hybrid accepts bio")
	_check(not PCS.is_fuel_compatible("hybrid", FT_CRUDE), "hybrid rejects crude")
	_check(PCS.is_fuel_compatible("ancient", FT_REFINED), "ancient accepts refined")
	_check(not PCS.is_fuel_compatible("ancient", FT_CRUDE), "ancient rejects crude")
	_check(not PCS.is_fuel_compatible("ancient", FT_BIO), "ancient rejects bio")


func test_refinery_basic() -> void:
	print("[3] Convoy Refinery — Basic Conversion")
	var fm = FM_SCRIPT.new()
	fm.convoy_fuel_inventory.reset([
		FCI.create_filled_container(FT_CRUDE, 100.0),
		FCI.create_filled_container(FT_CRUDE, 20.0),
	])
	var crude_before: float = fm.convoy_fuel_inventory.total_fuel_by_type(FT_CRUDE)
	_check(crude_before >= 50.0, "convoy has >= 50 crude before refining")
	_check(fm.can_refine(), "can_refine() returns true with enough crude")

	var result := fm.refine_crude_to_refined(50.0)
	var consumed: float = float(result["crude_consumed"])
	var produced: float = float(result["refined_produced"])
	_check(consumed == 50.0, "refinery consumed 50 crude")
	_check(produced > 0.0, "refinery produced refined")
	_check(absf(produced - consumed * 0.6) < 0.01, "refined = crude * 0.6")

	var crude_after: float = fm.convoy_fuel_inventory.total_fuel_by_type(FT_CRUDE)
	var refined_after: float = fm.convoy_fuel_inventory.total_fuel_by_type(FT_REFINED)
	_check(crude_after < crude_before, "crude decreased after refining")
	_check(refined_after > 0.0, "refined appeared after refining")


func test_refinery_not_enough_crude() -> void:
	print("[4] Convoy Refinery — Not Enough Crude")
	var fm = FM_SCRIPT.new()
	# Put crude in a 6% container — total 6 fuel, below 10 minimum
	fm.convoy_fuel_inventory.reset([
		FCI.create_filled_container(FT_CRUDE, 6.0),
	])
	var before: float = fm.convoy_fuel_inventory.total_fuel_by_type(FT_CRUDE)
	_check(before < 10.0, "only 6 crude (below minimum)")
	_check(not fm.can_refine(), "can_refine() returns false")

	# Try to refine 10 — should fail and refund
	var result := fm.refine_crude_to_refined(10.0)
	var consumed: float = float(result["crude_consumed"])
	var produced: float = float(result["refined_produced"])
	_check(consumed == 0.0, "refinery consumed 0 when not enough")
	_check(produced == 0.0, "refinery produced 0 when not enough")

	# Crude should be refunded
	var after: float = fm.convoy_fuel_inventory.total_fuel_by_type(FT_CRUDE)
	_check(absf(after - before) < 0.01, "crude refunded after failed refine")


func test_refinery_empty_inventory() -> void:
	print("[5] Convoy Refinery — Empty Inventory")
	var fm = FM_SCRIPT.new()
	fm.convoy_fuel_inventory.reset([])
	_check(not fm.can_refine(), "can_refine() returns false with empty inventory")
	var result := fm.refine_crude_to_refined(30.0)
	var consumed: float = float(result["crude_consumed"])
	var produced: float = float(result["refined_produced"])
	_check(consumed == 0.0, "empty: consumed 0")
	_check(produced == 0.0, "empty: produced 0")


func test_bio_fuel_heat_penalty_tracking() -> void:
	print("[6] Bio-Fuel Heat Penalty Tracking")
	var fm = FM_SCRIPT.new()
	fm.last_mech_fuel_type = -1
	_check(not fm.is_mech_using_bio_fuel(), "no bio fuel initially")

	fm.last_mech_fuel_type = FT_CRUDE
	_check(not fm.is_mech_using_bio_fuel(), "crude: not bio")

	fm.last_mech_fuel_type = FT_REFINED
	_check(not fm.is_mech_using_bio_fuel(), "refined: not bio")

	fm.last_mech_fuel_type = FT_BIO
	_check(fm.is_mech_using_bio_fuel(), "bio: detected as bio")

	var heat_mult_no_bio: float = PCS.heat_accumulation_multiplier("hybrid", false)
	var heat_mult_bio: float = PCS.heat_accumulation_multiplier("hybrid", true)
	_check(absf(heat_mult_no_bio - 1.5) < 0.01, "hybrid heat mult without bio = 1.5")
	_check(absf(heat_mult_bio - 1.95) < 0.01, "hybrid heat mult with bio = 1.95")
	_check(heat_mult_bio > heat_mult_no_bio, "bio fuel increases heat for hybrid")


func test_fuel_type_display() -> void:
	print("[7] Fuel Type Display")
	var fm = FM_SCRIPT.new()
	fm.mech_fuel_inventory.reset([
		FCI.create_filled_container(FT_CRUDE, 20.0),
		FCI.create_filled_container(FT_REFINED, 10.0),
	])
	var display: String = fm.mech_fuel_display()
	_check(display.contains("Crude"), "display contains 'Crude'")
	_check(display.contains("Refined"), "display contains 'Refined'")
	_check(not display.contains("EMPTY"), "display is not EMPTY")

	fm.mech_fuel_inventory.reset([])
	_check(fm.mech_fuel_display() == "EMPTY", "empty inventory displays EMPTY")


func test_consume_by_type() -> void:
	print("[8] Consume Fuel By Type")
	var fm = FM_SCRIPT.new()
	fm.mech_fuel_inventory.reset([
		FCI.create_filled_container(FT_CRUDE, 20.0),
		FCI.create_filled_container(FT_REFINED, 10.0),
	])

	var consumed: float = fm.consume_mech_fuel_typed(FT_CRUDE, 5.0)
	_check(consumed == 5.0, "consumed 5 crude")
	var crude_after: float = fm.mech_fuel_inventory.total_fuel_by_type(FT_CRUDE)
	_check(absf(crude_after - 15.0) < 0.01, "crude remaining = 15")
	var refined_after: float = fm.mech_fuel_inventory.total_fuel_by_type(FT_REFINED)
	_check(absf(refined_after - 10.0) < 0.01, "refined unchanged = 10")
	_check(fm.last_mech_fuel_type == FT_CRUDE, "last_fuel_type set to CRUDE")


func test_refinery_serialization() -> void:
	print("[9] Refinery Serialization Roundtrip")
	var fm = FM_SCRIPT.new()
	fm.convoy_fuel_inventory.reset([
		FCI.create_filled_container(FT_CRUDE, 100.0),
		FCI.create_filled_container(FT_CRUDE, 20.0),
	])
	fm.refine_crude_to_refined(50.0)

	var data: Array = fm.convoy_fuel_inventory.serialize()
	_check(data.size() > 0, "serialized convoy inventory has entries")

	var fresh = FCI.new()
	fresh.deserialize(data)
	var fresh_refined: float = fresh.total_fuel_by_type(FT_REFINED)
	_check(fresh_refined > 0.0, "deserialized has refined fuel")
	var orig_crude: float = fm.convoy_fuel_inventory.total_fuel_by_type(FT_CRUDE)
	var fresh_crude: float = fresh.total_fuel_by_type(FT_CRUDE)
	_check(absf(fresh_crude - orig_crude) < 0.01, "deserialized crude matches")


func test_mech_fuel_typed_consume() -> void:
	print("[10] Mech Fuel Typed Consume")
	var fm = FM_SCRIPT.new()
	fm.mech_fuel_inventory.reset([
		FCI.create_filled_container(FT_BIO, 20.0),
		FCI.create_filled_container(FT_REFINED, 10.0),
	])

	var consumed: float = fm.consume_mech_fuel_typed(FT_BIO, 8.0)
	_check(consumed == 8.0, "consume bio: consumed 8")
	_check(fm.last_mech_fuel_type == FT_BIO, "last_fuel_type = BIO")
	_check(fm.is_mech_using_bio_fuel(), "is_mech_using_bio_fuel() true")
	_check(fm.mech_energy > 0.0, "mech_energy decreased")
