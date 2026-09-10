extends Node

const FrameModuleSystem = preload("res://scripts/systems/frame_module_system.gd")

## ---------------------------------------------------------------------------
## VERIFICATION: Frame Module Socket System ("Sleeper Build Engine")
##
## Tests:
##   1. Module Catalog Integrity (12 modules, all archetypes & effects)
##   2. Socket Layout (Torso 3, Arms 1 each, Legs 1 each = 7 total)
##   3. Installation & Category Compatibility (Universal, Torso, Arm, Leg)
##   4. Synergy Multiplier Calculations:
##      - V8 Twin-Turbo dash stacking
##      - Heat-to-Kinetic Converter fire rate & proj speed scaling
##      - Exposed Frame Berserk speed & melee scaling
##   5. Cargo Inventory Management & Module Swapping
##   6. Save/Load Persistence of Installed Modules and Cargo
##
## Run: godot --headless --path . res://tests/frame_module_system_verify.tscn
## ---------------------------------------------------------------------------

var _checks := 0
var _fails := 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("  ✔ %s" % msg)
	else:
		_fails += 1
		print("  ✘ FAIL: %s" % msg)


func _ready() -> void:
	print("")
	print("=== FRAME MODULE SOCKET SYSTEM VERIFICATION (SLEEPER BUILD ENGINE) ===")
	print("")

	test_catalog_integrity()
	test_socket_layout()
	test_installation_and_compatibility()
	test_synergy_calculations()
	test_cargo_and_swapping()
	test_save_load_persistence()

	print("")
	print("=== RESULT: %d checks, %d failures ===" % [_checks, _fails])
	if _fails == 0:
		print("\nALL TESTS PASSED ✅")
		get_tree().quit(0)
	else:
		print("\nTESTS FAILED ❌")
		get_tree().quit(1)


func test_catalog_integrity() -> void:
	print("[1] Module Catalog Integrity")
	var catalog = FrameModuleSystem.MODULE_CATALOG
	_check(catalog.size() >= 12, "Catalog defines at least 12 modules (found %d)" % catalog.size())

	var expected_ids := [
		"v8_twin_turbo",
		"heat_kinetic_converter",
		"nitrous_scorch",
		"synaptic_reflex",
		"predictive_matrix",
		"phantom_decoy",
		"exposed_frame_berserk",
		"dynamo_siphon",
		"scrap_cannibalizer",
		"seismic_piston",
		"gatling_governor",
		"nanite_frame_mesh",
	]

	var all_present := true
	for id in expected_ids:
		if not catalog.has(id):
			all_present = false
			print("  Missing module id: %s" % id)
	_check(all_present, "All 12 core prototype & overclock modules are present")

	var valid_fields := true
	for id in catalog:
		var mod = catalog[id]
		if not mod.has("id") or not mod.has("name") or not mod.has("category") or not mod.has("tier") or not mod.has("effects"):
			valid_fields = false
			break
	_check(valid_fields, "All modules have required metadata (id, name, category, tier, effects)")


func test_socket_layout() -> void:
	print("[2] Socket Layout & Capacity")
	FrameModuleSystem.init_slots_if_needed()
	_check(FrameModuleSystem.get_socket_count("torso") == 3, "Torso has 3 core sockets")
	_check(FrameModuleSystem.get_socket_count("arm_left") == 1, "Arm Left has 1 socket")
	_check(FrameModuleSystem.get_socket_count("arm_right") == 1, "Arm Right has 1 socket")
	_check(FrameModuleSystem.get_socket_count("leg_left") == 1, "Leg Left has 1 socket")
	_check(FrameModuleSystem.get_socket_count("leg_right") == 1, "Leg Right has 1 socket")

	var total_sockets := 0
	for slot in FrameModuleSystem.SOCKET_COUNTS:
		total_sockets += FrameModuleSystem.get_socket_count(slot)
	_check(total_sockets == 7, "Total Inner Frame capacity is 7 sockets")


func test_installation_and_compatibility() -> void:
	print("[3] Installation & Category Compatibility")
	GlobalData.weapons.reset()
	FrameModuleSystem.init_slots_if_needed()

	# Leg module into Leg slot -> Success
	var res_leg := FrameModuleSystem.install_module("leg_left", 0, "v8_twin_turbo")
	_check(res_leg == true, "Installing leg module into leg_left succeeds")
	_check(FrameModuleSystem.has_module("v8_twin_turbo") == true, "has_module('v8_twin_turbo') returns true")
	_check(FrameModuleSystem.get_installed_module_id("leg_left", 0) == "v8_twin_turbo", "Installed module ID matches")

	# Incompatible category: Leg module into Torso slot -> Should fail
	var res_incompat := FrameModuleSystem.install_module("torso", 0, "v8_twin_turbo")
	_check(res_incompat == false, "Installing leg module into torso socket rejected by compatibility check")

	# Torso module into Torso slot -> Success
	var res_torso := FrameModuleSystem.install_module("torso", 0, "heat_kinetic_converter")
	_check(res_torso == true, "Installing torso module into torso socket succeeds")
	_check(FrameModuleSystem.has_module("heat_kinetic_converter") == true, "has_module('heat_kinetic_converter') returns true")

	# Uninstall module
	var uninstalled_id := FrameModuleSystem.uninstall_module("leg_left", 0)
	_check(uninstalled_id == "v8_twin_turbo", "Uninstalling returns the uninstalled module ID")
	_check(FrameModuleSystem.has_module("v8_twin_turbo") == false, "Module is no longer active after uninstall")
	_check(GlobalData.weapons.module_inventory.has("v8_twin_turbo"), "Uninstalled module returned to cargo inventory")


func test_synergy_calculations() -> void:
	print("[4] Synergy Multiplier Calculations")
	GlobalData.weapons.reset()
	FrameModuleSystem.init_slots_if_needed()

	# 1. V8 Twin-Turbo Dash Stacking
	_check(is_equal_approx(FrameModuleSystem.calculate_dash_stack_multiplier(0), 1.0), "V8 without module active returns 1.0")
	FrameModuleSystem.install_module("leg_right", 0, "v8_twin_turbo")
	_check(is_equal_approx(FrameModuleSystem.calculate_dash_stack_multiplier(0), 1.0), "V8 at 0 stacks returns 1.0")
	_check(is_equal_approx(FrameModuleSystem.calculate_dash_stack_multiplier(1), 1.20), "V8 at 1 stack returns 1.20 (+20% speed)")
	_check(is_equal_approx(FrameModuleSystem.calculate_dash_stack_multiplier(2), 1.40), "V8 at 2 stacks returns 1.40 (+40% speed)")
	_check(is_equal_approx(FrameModuleSystem.calculate_dash_stack_multiplier(3), 1.60), "V8 at 3 stacks returns 1.60 (+60% max cap)")
	_check(is_equal_approx(FrameModuleSystem.calculate_dash_stack_multiplier(5), 1.60), "V8 clamps properly at max 3 stacks")

	# 2. Heat-to-Kinetic Converter
	_check(is_equal_approx(FrameModuleSystem.calculate_heat_fire_rate_multiplier(0.9), 1.0), "Heat converter inactive returns 1.0")
	FrameModuleSystem.install_module("torso", 1, "heat_kinetic_converter")
	_check(is_equal_approx(FrameModuleSystem.calculate_heat_fire_rate_multiplier(0.2), 1.0), "Heat below 40% threshold returns 1.0")
	_check(is_equal_approx(FrameModuleSystem.calculate_heat_fire_rate_multiplier(1.0), 1.50), "Heat at 100% returns 1.50 (+50% fire rate)")
	_check(is_equal_approx(FrameModuleSystem.calculate_heat_proj_speed_multiplier(1.0), 1.35), "Heat at 100% returns 1.35 (+35% bullet speed)")

	# 3. Exposed Frame Berserk
	_check(is_equal_approx(FrameModuleSystem.calculate_berserk_speed_multiplier(), 1.0), "Berserk inactive returns 1.0")
	FrameModuleSystem.install_module("torso", 2, "exposed_frame_berserk")
	# Simulate 2 broken slots
	GlobalData.weapons.part_damage["arm_left"] = 1.0
	GlobalData.weapons.part_damage["leg_right"] = 1.0
	var speed_mult := FrameModuleSystem.calculate_berserk_speed_multiplier()
	var melee_mult := FrameModuleSystem.calculate_berserk_melee_multiplier()
	_check(is_equal_approx(speed_mult, 1.30), "Berserk with 2 broken plates yields +30% speed (1.30)")
	_check(is_equal_approx(melee_mult, 1.50), "Berserk with 2 broken plates yields +50% melee (1.50)")


func test_cargo_and_swapping() -> void:
	print("[5] Cargo & Swapping")
	GlobalData.weapons.reset()
	FrameModuleSystem.init_slots_if_needed()

	# Give player a module in cargo
	GlobalData.weapons.module_inventory.append("predictive_matrix")
	_check(GlobalData.weapons.module_inventory.has("predictive_matrix"), "Cargo contains predictive_matrix")

	# Install from cargo
	var ok := FrameModuleSystem.install_module("arm_left", 0, "predictive_matrix")
	_check(ok == true, "Installed predictive_matrix into arm_left from cargo")
	_check(not GlobalData.weapons.module_inventory.has("predictive_matrix"), "predictive_matrix consumed from cargo")

	# Swap with another arm module
	GlobalData.weapons.module_inventory.append("scrap_cannibalizer")
	var swap_ok := FrameModuleSystem.install_module("arm_left", 0, "scrap_cannibalizer")
	_check(swap_ok == true, "Swapped scrap_cannibalizer into arm_left")
	_check(FrameModuleSystem.get_installed_module_id("arm_left", 0) == "scrap_cannibalizer", "Active module is scrap_cannibalizer")
	_check(GlobalData.weapons.module_inventory.has("predictive_matrix"), "Previous predictive_matrix returned to cargo")


func test_save_load_persistence() -> void:
	print("[6] Save/Load Persistence")
	GlobalData.weapons.reset()
	FrameModuleSystem.init_slots_if_needed()

	FrameModuleSystem.install_module("torso", 0, "phantom_decoy")
	FrameModuleSystem.install_module("leg_left", 0, "v8_twin_turbo")
	GlobalData.weapons.module_inventory.append("nanite_frame_mesh")

	SaveGameIO.save_run()
	_check(FileAccess.file_exists(GlobalData.SAVE_PATH), "save_run() completed and file exists")

	# Clear live state
	GlobalData.weapons.reset()
	_check(FrameModuleSystem.has_module("phantom_decoy") == false, "State cleared before load")

	# Load state back
	var load_success := SaveGameIO.load_run()
	_check(load_success == true, "load_run() succeeded")
	_check(FrameModuleSystem.has_module("phantom_decoy") == true, "Installed torso module phantom_decoy restored")
	_check(FrameModuleSystem.has_module("v8_twin_turbo") == true, "Installed leg module v8_twin_turbo restored")
	_check(GlobalData.weapons.module_inventory.has("nanite_frame_mesh"), "Cargo inventory module nanite_frame_mesh restored")
