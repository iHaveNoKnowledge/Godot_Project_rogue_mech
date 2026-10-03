extends Node

## War Mode Phase 3B: Runtime UI / Visual Polish Verification Suite
## Verifies modular UI component instantiation, layer hierarchies, input routing,
## reactive state binding, and lifecycle safety across War Mode HUD/Inventory/Launch.

const WarResourceHUD = preload("res://scripts/war/war_resource_hud.gd")
const WarInventoryUI = preload("res://scripts/war/war_inventory_ui.gd")
const WarLaunchSetupUI = preload("res://scripts/war/war_launch_setup_ui.gd")
const WarDeploymentManager = preload("res://scripts/war/war_deployment_manager.gd")
const WarBalance = preload("res://scripts/war/war_balance.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % message)
	else:
		_fail_count += 1
		_failures.append(message)
		push_error("Assertion failed: %s" % message)
		print("  [FAIL] %s" % message)


func _ready() -> void:
	print("\n==================================================")
	print("WAR MODE PHASE 3B: RUNTIME UI & VISUAL POLISH VERIFY")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("WAR_PHASE_3B_UI_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nWAR_PHASE_3B_UI_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("WAR MODE PHASE 3B TEST SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failures.is_empty():
		print("FAILED ASSERTIONS:")
		for f in _failures:
			print("  - %s" % f)
	print("==================================================")


func _run_all_tests() -> void:
	await _test_resource_hud_lifecycle()
	await _test_inventory_ui_lifecycle()
	await _test_launch_setup_ui_and_ace_timer()
	await _test_ui_layer_hierarchy_and_modality()


func _test_resource_hud_lifecycle() -> void:
	print("\n-- [1] Resource HUD (Tab Overlay) Lifecycle & State Binding --")
	var hud_scene = load("res://scenes/war/war_resource_hud.tscn")
	_assert(hud_scene != null, "1.1: war_resource_hud.tscn loaded successfully")
	var hud: CanvasLayer = hud_scene.instantiate()
	add_child(hud)
	_assert(hud.layer == 10, "1.2: Resource HUD layer configured to 10")
	_assert(hud._overlay == null, "1.3: Overlay initially hidden (null)")

	# Set known currency and fuel
	GlobalData.currency.credits = 1250
	GlobalData.currency.scrap = 340
	GlobalData.fuel.mech_energy = 85.0

	# Show overlay
	hud._show()
	_assert(hud._overlay != null and is_instance_valid(hud._overlay), "1.4: Overlay created on _show()")
	_assert(hud._overlay.get_parent() == hud, "1.5: Overlay parent is ResourceHUD CanvasLayer")

	# Check duplicate show guard
	var initial_overlay = hud._overlay
	hud._show()
	_assert(hud._overlay == initial_overlay, "1.6: Repeated _show() does not duplicate overlay panel")

	# Hide overlay
	hud._hide()
	await get_tree().process_frame
	_assert(hud._overlay == null, "1.7: Overlay cleared on _hide()")

	hud.queue_free()
	await get_tree().process_frame


func _test_inventory_ui_lifecycle() -> void:
	print("\n-- [2] Inventory UI (I Overlay) Lifecycle & Toggle Idempotency --")
	var inv_scene = load("res://scenes/war/war_inventory.tscn")
	_assert(inv_scene != null, "2.1: war_inventory.tscn loaded successfully")
	var inv: CanvasLayer = inv_scene.instantiate()
	add_child(inv)
	_assert(inv.layer == 10, "2.2: Inventory UI layer configured to 10")
	_assert(inv._overlay == null, "2.3: Inventory initially closed")

	# Toggle Open
	inv._toggle()
	_assert(inv._overlay != null and is_instance_valid(inv._overlay), "2.4: Inventory overlay created on toggle open")
	_assert(inv._overlay.custom_minimum_size == Vector2(600, 400), "2.5: Inventory overlay min size == 600x400")

	# Toggle Close
	inv._toggle()
	await get_tree().process_frame
	_assert(inv._overlay == null, "2.6: Inventory overlay cleanly destroyed on toggle close")

	# Repeated 3x toggle cycles
	for i in range(3):
		inv._toggle()
		_assert(inv._overlay != null, "2.7.%d: Reopened cycle %d" % [i + 1, i + 1])
		inv._toggle()
		await get_tree().process_frame
		_assert(inv._overlay == null, "2.8.%d: Closed cycle %d" % [i + 1, i + 1])

	inv.queue_free()
	await get_tree().process_frame


func _test_launch_setup_ui_and_ace_timer() -> void:
	print("\n-- [3] Launch Setup UI & Ace Right Reservation Timer --")
	var launch_scene = load("res://scenes/war/war_launch_setup_ui.tscn")
	_assert(launch_scene != null, "3.1: war_launch_setup_ui.tscn loaded successfully")
	var launch: CanvasLayer = launch_scene.instantiate()
	add_child(launch)
	_assert(launch.layer == 20, "3.2: Launch setup UI layer == 20 (above HUD)")
	_assert(launch.visible == false, "3.3: Launch setup initially invisible")

	# Open setup with Ace Right holder
	launch.open_setup("AcePilot_01")
	_assert(launch.visible == true, "3.4: Launch setup visible on open_setup")
	_assert(launch._is_ace_phase == true, "3.5: Ace phase activated")
	_assert(launch._ace_remaining == WarBalance.ACE_RIGHT_TIMEOUT, "3.6: Ace remaining matches 30s timeout")
	_assert(launch._ace_timer.is_stopped() == false, "3.7: Ace countdown timer running")

	# Simulate 10 ticks (10s elapsed)
	for i in range(10):
		launch._on_ace_tick()
	_assert(launch._ace_remaining == 20.0, "3.8: Ace remaining == 20.0s after 10 ticks")
	_assert(launch._is_ace_phase == true, "3.9: Ace phase remains active at 20s")

	# Simulate remaining 20 ticks (timeout)
	for i in range(20):
		launch._on_ace_tick()
	_assert(launch._ace_remaining <= 0.0, "3.10: Ace countdown reached 0")
	_assert(launch._is_ace_phase == false, "3.11: Ace phase deactivated on timeout")
	_assert(launch._ace_timer.is_stopped() == true, "3.12: Ace timer stopped on timeout")

	# Close setup
	launch._on_close()
	_assert(launch.visible == false, "3.13: Launch setup hidden on close")
	_assert(launch._ace_timer.is_stopped() == true, "3.14: Timer stopped after close")

	launch.queue_free()
	await get_tree().process_frame


func _test_ui_layer_hierarchy_and_modality() -> void:
	print("\n-- [4] UI Layer Hierarchy & Z-Index Ordering --")
	var res_hud = WarResourceHUD.new()
	var inv_ui = WarInventoryUI.new()
	var launch_ui = WarLaunchSetupUI.new()

	add_child(res_hud)
	add_child(inv_ui)
	add_child(launch_ui)

	_assert(res_hud.layer == 10, "4.1: Resource HUD Layer == 10")
	_assert(inv_ui.layer == 10, "4.2: Inventory UI Layer == 10")
	_assert(launch_ui.layer == 20, "4.3: Launch Setup Layer == 20 (renders above HUD)")
	_assert(launch_ui.layer > res_hud.layer, "4.4: Launch modal renders strictly above Resource HUD")

	res_hud.queue_free()
	inv_ui.queue_free()
	launch_ui.queue_free()
	await get_tree().process_frame
