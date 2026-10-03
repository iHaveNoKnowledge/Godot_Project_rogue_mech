extends Node

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	print("=== Starting War Mode Realtime Hangar Original UI Verification ===")
	_test_realtime_hangar_setup_and_camera_focus()
	_test_realtime_hangar_ui_pages_and_filters()
	_test_realtime_hangar_live_part_fitting()
	_test_realtime_hangar_exit_transition()

	print("=== Realtime Hangar Original UI Finished: %d passed, %d failed ===" % [_passed, _failed])
	if _failed == 0:
		print("ALL_REALTIME_HANGAR_TESTS_PASSED")
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("HANGAR_REALTIME_OK: %s" % label)
	else:
		_failed += 1
		push_error("HANGAR_REALTIME_FAIL: %s" % label)


func _test_realtime_hangar_setup_and_camera_focus() -> void:
	# Create a dummy 3D world with a player mecha placed at (10, 0, -780)
	var world = Node3D.new()
	world.name = "TestWarWorld"
	add_child(world)

	var mecha_scene = load("res://scenes/mecha/mecha_base.tscn")
	_assert(mecha_scene != null, "mecha_base.tscn loaded")
	var mecha = mecha_scene.instantiate() as CharacterBody3D
	mecha.position = Vector3(10, 0, -780)
	world.add_child(mecha)

	# Combat camera
	var combat_cam = Camera3D.new()
	combat_cam.name = "CombatCamera"
	world.add_child(combat_cam)
	combat_cam.current = true

	# Instantiate original Hangar UI in Realtime Mode
	var hangar_scene = load("res://scenes/ui/hangar_ui.tscn")
	_assert(hangar_scene != null, "hangar_ui.tscn loaded")
	var hangar = hangar_scene.instantiate()
	hangar.setup_realtime_mode(mecha)
	world.add_child(hangar)

	_assert(hangar.is_realtime_war_mode, "Hangar marked as is_realtime_war_mode")
	_assert(hangar.garage_panel != null, "Hangar has garage_panel")
	_assert(hangar.garage_panel.is_realtime_world, "garage_panel configured with is_realtime_world")
	_assert(hangar.garage_panel.viewport_container == null, "Realtime mode skips SubViewportContainer (renders directly in world)")
	_assert(hangar.garage_panel.garage_cam != null, "In-world garage_cam created")
	_assert(hangar.garage_panel.garage_cam.current, "garage_cam became the active viewport camera")

	# Test Camera In-World Slot Focusing
	var gp = hangar.garage_panel

	# 1. Head focus (upper framing)
	gp.update_camera_focus("head")
	_assert(gp.cam_target_pos.y > mecha.position.y + 3.0, "Head focus aims camera higher up (target Y = %.2f)" % gp.cam_target_pos.y)

	# 2. Arm Left focus (camera angles towards mecha's left arm at -X)
	gp.update_camera_focus("arm_left")
	_assert(gp.cam_target_pos.x < mecha.position.x, "Arm left focus offsets camera to frame left side (target X = %.2f < %.2f)" % [gp.cam_target_pos.x, mecha.position.x])

	# 3. Arm Right focus (camera angles towards mecha's right arm at +X)
	gp.update_camera_focus("arm_right")
	_assert(gp.cam_target_pos.x > mecha.position.x, "Arm right focus offsets camera to frame right side (target X = %.2f > %.2f)" % [gp.cam_target_pos.x, mecha.position.x])

	# 4. Legs focus (lower angle)
	gp.update_camera_focus("legs")
	_assert(gp.cam_target_pos.y < mecha.position.y + 4.0, "Legs focus drops camera to lower height (target Y = %.2f)" % gp.cam_target_pos.y)

	# 5. Backpack focus (rear angle: in Godot +Z is behind mecha which faces -Z)
	gp.update_camera_focus("backpack")
	_assert(gp.cam_target_pos.z > mecha.position.z, "Backpack focus positions camera behind mecha (target Z = %.2f > %.2f)" % [gp.cam_target_pos.z, mecha.position.z])

	# Clean up
	hangar.close_realtime_hangar()
	world.queue_free()


func _test_realtime_hangar_ui_pages_and_filters() -> void:
	var mecha = Node3D.new()
	mecha.name = "DummyMecha"
	add_child(mecha)

	var hangar_scene = load("res://scenes/ui/hangar_ui.tscn")
	var hangar = hangar_scene.instantiate()
	hangar.setup_realtime_mode(mecha)
	add_child(hangar)

	_assert(hangar.nav_panel != null, "Hangar has nav_panel")
	_assert(hangar.nav_panel.current_submenu == "customize", "War mode opens directly into CUSTOMIZE page")
	_assert(hangar.left_panel != null and hangar.left_panel.visible, "Customize left panel is visible immediately")
	_assert(hangar.right_panel != null and hangar.right_panel.visible, "Customize right panel is visible immediately")

	# Check filtered submenu rail (landing rail)
	hangar.nav_panel.build_landing_rail(hangar.root_control)
	var rail_box = hangar.submenu_rail.get_child(0) as VBoxContainer
	var button_texts: Array[String] = []
	for child in rail_box.get_children():
		if child is Button:
			button_texts.append((child as Button).text)

	_assert(not button_texts.has("Roster"), "Campaign tab 'Roster' is excluded in War Mode")
	_assert(not button_texts.has("Pilots"), "Campaign tab 'Pilots' is excluded in War Mode")
	_assert(not button_texts.has("Sortie"), "Campaign tab 'Sortie' is excluded in War Mode")
	_assert(button_texts.has("Customize"), "Hangar menu retains 'Customize'")
	_assert(button_texts.has("Upgrade"), "Hangar menu retains 'Upgrade'")
	_assert(button_texts.has("Emergency Repair"), "Hangar menu retains 'Emergency Repair'")
	_assert(button_texts.has("Craft"), "Hangar menu retains 'Craft'")
	_assert(button_texts.has("Catalog"), "Hangar menu retains 'Catalog'")

	hangar.close_realtime_hangar()
	mecha.queue_free()


func _test_realtime_hangar_live_part_fitting() -> void:
	var mecha_scene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha = mecha_scene.instantiate() as CharacterBody3D
	add_child(mecha)

	var hangar_scene = load("res://scenes/ui/hangar_ui.tscn")
	var hangar = hangar_scene.instantiate()
	hangar.setup_realtime_mode(mecha)
	add_child(hangar)

	_assert(int(hangar.get("layer")) >= 50, "HangarUI layer is set to >= 50 (got %d) ensuring it renders and receives clicks above WarHUD" % int(hangar.get("layer")))
	if DisplayServer.get_name() != "headless":
		_assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Mouse mode set to MOUSE_MODE_VISIBLE so buttons are interactive and clickable")
	else:
		_assert(true, "Headless test skips windowed mouse mode check")

	_assert(hangar.garage_panel.get_mecha_base() == mecha, "garage_panel.get_mecha_base() returns the in-world player mecha directly")
	var pmm = hangar.garage_panel.get_part_mesh_manager()
	_assert(pmm != null, "garage_panel.get_part_mesh_manager() resolves player mecha's PartMeshManager")

	# Test Button Clickability
	# 1. Click Slot Tab 'head'
	if hangar.slot_tab_buttons.has("head"):
		var head_btn: Button = hangar.slot_tab_buttons["head"]
		_assert(head_btn != null and is_instance_valid(head_btn), "Head slot tab button exists")
		_assert(head_btn.mouse_filter == Control.MOUSE_FILTER_STOP, "Head slot button has MOUSE_FILTER_STOP to capture mouse clicks")
		head_btn.pressed.emit()
		_assert(hangar.selected_slot == "head", "Clicking Head tab switches selected_slot to 'head'")

	# 2. Click Slot Tab 'arm_left'
	if hangar.slot_tab_buttons.has("arm_left"):
		var arm_btn: Button = hangar.slot_tab_buttons["arm_left"]
		arm_btn.pressed.emit()
		_assert(hangar.selected_slot == "arm_left", "Clicking L.Arm tab switches selected_slot to 'arm_left'")

	# 3. Verify ItemList is interactive
	_assert(hangar.part_item_list != null and is_instance_valid(hangar.part_item_list), "part_item_list exists")
	_assert(hangar.part_item_list.mouse_filter == Control.MOUSE_FILTER_STOP, "part_item_list can receive mouse clicks")

	hangar.close_realtime_hangar()
	mecha.queue_free()


func _test_realtime_hangar_exit_transition() -> void:
	var world = Node3D.new()
	add_child(world)

	var combat_cam = Camera3D.new()
	combat_cam.name = "CombatCam"
	world.add_child(combat_cam)
	combat_cam.current = true

	var mecha = Node3D.new()
	world.add_child(mecha)

	var hangar = load("res://scenes/ui/hangar_ui.tscn").instantiate()
	hangar.setup_realtime_mode(mecha)
	world.add_child(hangar)

	var closed_signal_fired = [false]
	hangar.realtime_closed.connect(func(): closed_signal_fired[0] = true)

	# Execute close
	hangar.close_realtime_hangar()

	_assert(closed_signal_fired[0], "realtime_closed signal emitted on exit")
	if DisplayServer.get_name() != "headless":
		_assert(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Mouse mode restored to MOUSE_MODE_CAPTURED for battlefield combat")
	else:
		_assert(true, "Headless test skips windowed mouse capture check")
	_assert(combat_cam.current, "Combat camera restored as the active camera")

	world.queue_free()
