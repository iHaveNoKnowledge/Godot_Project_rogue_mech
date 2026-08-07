extends CanvasLayer

## Emergency Repair Editor (Mass Builder style).
##
## When no fleet mechanic is around, the driver patches a damaged slot with
## scrap: basic primitives (box / sphere / wedge / cylinder) are placed on the
## mech, stretched and rotated like a Mass Builder frame editor. On apply the
## editor calls GlobalData.apply_emergency_repair(slot, primitives), which spends
## scrap, records a weaker scrap patch, and grants repair-skill XP.
##
## The live scene is a SubViewport with the real mecha_base so the driver sees
## exactly what the patched slot will look like in combat.

var root_control: Control
var slot_container: VBoxContainer
var primitives_label: Label
var hint_label: Label
var status_label: Label
var apply_button: Button
var slot_info_label: Label

var viewport_container: SubViewportContainer
var sub_viewport: SubViewport
var turntable_node: Node3D
var mecha_node: Node3D
var pmm: Node

var selected_slot: String = ""
var editing_primitives: Dictionary = {}
var selected_primitive_index: int = -1

var _dragging: bool = false

const MOVE_STEP := 0.15
const ROT_STEP := 15.0 * PI / 180.0
const SCALE_FACTOR := 1.1
const SCRAP_COLOR := [0.55, 0.55, 0.62, 1.0]

const SLOT_DISPLAY := {
	"head": "Head",
	"body": "Body",
	"arm_left": "Arm Left",
	"arm_right": "Arm Right",
	"leg_left": "Leg Left",
	"leg_right": "Leg Right",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_build_garage()
	visible = false


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func open(initial_slot: String = "") -> void:
	if pmm == null:
		_build_garage()
	visible = true
	if pmm and pmm.has_method("refresh_slots"):
		pmm.refresh_slots()
	_refresh_slot_list()
	if initial_slot != "" and GlobalData.get_emergency_repair_scrap_cost(initial_slot) > 0:
		_select_slot(initial_slot)
	else:
		var first_slot := _first_slot_button_name()
		if first_slot != "":
			_select_slot(first_slot)
		else:
			selected_slot = ""
			_clear_live_primitives()
	_update_status()


func close() -> void:
	_clear_live_primitives()
	visible = false


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(dim)

	# Center 3D viewport.
	viewport_container = SubViewportContainer.new()
	viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(viewport_container)

	sub_viewport = SubViewport.new()
	sub_viewport.size = Vector2i(1280, 720)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(sub_viewport)

	# Left panel: damaged slot list.
	var left_panel := PanelContainer.new()
	left_panel.offset_left = 15
	left_panel.offset_top = 15
	left_panel.offset_bottom = -120
	left_panel.custom_minimum_size = Vector2(240, 0)
	root_control.add_child(left_panel)
	var left_style := _make_panel_style(Color(0.1, 0.12, 0.16, 0.95))
	left_panel.add_theme_stylebox_override("panel", left_style)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 6)
	left_panel.add_child(left_vbox)

	var title := Label.new()
	title.text = "EMERGENCY REPAIR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	left_vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Patch damaged slots with scrap.\nTier %d scrap (%d%% of real stats)" % [
		GlobalData.get_scrap_armor_tier(),
		int(GlobalData.get_scrap_armor_stat_scale() * 100.0),
	]
	sub.add_theme_font_size_override("font_size", 12)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_vbox.add_child(sub)

	var sep := HSeparator.new()
	left_vbox.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(scroll)

	slot_container = VBoxContainer.new()
	slot_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_container.add_theme_constant_override("separation", 4)
	scroll.add_child(slot_container)

	slot_info_label = Label.new()
	slot_info_label.add_theme_font_size_override("font_size", 12)
	slot_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_vbox.add_child(slot_info_label)

	# Right panel: tools.
	var right_panel := PanelContainer.new()
	right_panel.offset_right = -15
	right_panel.offset_top = 15
	right_panel.offset_bottom = -120
	right_panel.custom_minimum_size = Vector2(300, 0)
	right_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_panel.offset_left = -315
	root_control.add_child(right_panel)
	var right_style := _make_panel_style(Color(0.1, 0.12, 0.16, 0.95))
	right_panel.add_theme_stylebox_override("panel", right_style)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 6)
	right_panel.add_child(right_vbox)

	var tools_title := Label.new()
	tools_title.text = "SCRAP PARTS"
	tools_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tools_title.add_theme_font_size_override("font_size", 16)
	right_vbox.add_child(tools_title)

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 4)
	right_vbox.add_child(add_row)
	add_row.add_child(_make_tool_button("Box", _add_primitive.bind("box")))
	add_row.add_child(_make_tool_button("Sphere", _add_primitive.bind("sphere")))
	add_row.add_child(_make_tool_button("Wedge", _add_primitive.bind("wedge")))
	add_row.add_child(_make_tool_button("Cylinder", _add_primitive.bind("cylinder")))

	var prim_scroll := ScrollContainer.new()
	prim_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	prim_scroll.custom_minimum_size = Vector2(0, 120)
	right_vbox.add_child(prim_scroll)

	primitives_label = Label.new()
	primitives_label.add_theme_font_size_override("font_size", 12)
	primitives_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prim_scroll.add_child(primitives_label)

	var del_row := HBoxContainer.new()
	del_row.add_theme_constant_override("separation", 4)
	right_vbox.add_child(del_row)
	var delete_btn := _make_tool_button("Delete", _on_delete_primitive_pressed)
	del_row.add_child(delete_btn)
	var clear_btn := _make_tool_button("Clear", _on_clear_pressed)
	del_row.add_child(clear_btn)

	hint_label = Label.new()
	hint_label.text = (
		"Move: Arrow keys (X/Z), PgUp/PgDn (Y)\n"
		+ "Rotate: Q / E      Scale: - / =\n"
		+ "Select part: Tab / Shift+Tab\n"
		+ "Delete: Backspace    Drag: rotate view\n"
		+ "Arrow + Shift moves in smaller steps."
	)
	hint_label.add_theme_font_size_override("font_size", 11)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_vbox.add_child(hint_label)

	apply_button = Button.new()
	apply_button.custom_minimum_size = Vector2(0, 36)
	apply_button.pressed.connect(_on_apply_pressed)
	right_vbox.add_child(apply_button)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(0, 32)
	cancel_btn.pressed.connect(close)
	right_vbox.add_child(cancel_btn)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_vbox.add_child(status_label)


func _make_panel_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _make_tool_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(64, 28)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(callback)
	return btn


func _build_garage() -> void:
	if pmm != null:
		return
	var env := Node3D.new()
	env.name = "ScrapEditorEnv"
	sub_viewport.add_child(env)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24, 24)
	floor_mesh.mesh = plane
	var mat_floor := StandardMaterial3D.new()
	mat_floor.albedo_color = Color(0.1, 0.11, 0.14)
	mat_floor.metallic = 0.8
	mat_floor.roughness = 0.5
	floor_mesh.material_override = mat_floor
	env.add_child(floor_mesh)

	turntable_node = Node3D.new()
	env.add_child(turntable_node)

	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.5
	cyl.bottom_radius = 3.8
	cyl.height = 0.12
	ring.mesh = cyl
	var mat_ring := StandardMaterial3D.new()
	mat_ring.albedo_color = Color(0.25, 0.3, 0.4)
	mat_ring.emission_enabled = true
	mat_ring.emission = Color(0.6, 0.4, 0.15)
	mat_ring.emission_energy_multiplier = 1.0
	ring.material_override = mat_ring
	turntable_node.add_child(ring)

	var spot := SpotLight3D.new()
	spot.position = Vector3(3, 8, 5)
	env.add_child(spot)
	spot.look_at(Vector3(0, 2.9, 0), Vector3.UP)
	spot.light_energy = 4.0
	spot.spot_range = 20.0
	spot.spot_angle = 45.0

	var rim := SpotLight3D.new()
	rim.position = Vector3(-4, 5, -4)
	env.add_child(rim)
	rim.look_at(Vector3(0, 2.5, 0), Vector3.UP)
	rim.light_energy = 2.5
	rim.light_color = Color(1.0, 0.8, 0.5)

	var scene_base = preload("res://scenes/mecha/mecha_base.tscn").instantiate()
	# Disable the living mech (controller, animations, health) so it can't react to
	# battle keybinds in this editor viewport — otherwise it skates off the display
	# (the battle move actions are read directly via Input, not per-event, so marking
	# editor key events as handled is not enough).
	scene_base.set_process(false)
	scene_base.set_physics_process(false)
	scene_base.set_process_input(false)
	for child in scene_base.get_children():
		child.set_process(false)
		child.set_physics_process(false)
	_apply_neutral_pose(scene_base)
	turntable_node.add_child(scene_base)
	mecha_node = scene_base

	pmm = scene_base.get_node_or_null("PartMeshManager")

	var cam := Camera3D.new()
	cam.position = Vector3(4.8, 3.8, 6.7)
	env.add_child(cam)
	cam.look_at(Vector3(0, 2.9, 0), Vector3.UP)
	cam.fov = 55.0


func _apply_neutral_pose(mecha_node: Node3D) -> void:
	var body = mecha_node.get_node_or_null("Body")
	var head = mecha_node.get_node_or_null("Head")
	var leg_left = mecha_node.get_node_or_null("LegLeft")
	var leg_right = mecha_node.get_node_or_null("LegRight")
	var shin_left = mecha_node.get_node_or_null("LegLeft/ShinLeft")
	var shin_right = mecha_node.get_node_or_null("LegRight/ShinRight")
	var arm_left = mecha_node.get_node_or_null("ArmLeft")
	var arm_right = mecha_node.get_node_or_null("ArmRight")
	var forearm_left = mecha_node.get_node_or_null("ArmLeft/ForearmLeft")
	var forearm_right = mecha_node.get_node_or_null("ArmRight/ForearmRight")

	if body:
		body.rotation = Vector3.ZERO
		body.position.y = 1.75
	if head:
		head.rotation = Vector3.ZERO
		head.position.y = 2.45
	for limb in [leg_left, leg_right, shin_left, shin_right, arm_left, arm_right, forearm_left, forearm_right]:
		if limb:
			limb.rotation = Vector3.ZERO


# ---------------------------------------------------------------------------
# Slot selection & slot list
# ---------------------------------------------------------------------------
func _first_slot_button_name() -> String:
	for child in slot_container.get_children():
		if child is Button:
			return str(child.get_meta("slot_name", ""))
	return ""


func _refresh_slot_list() -> void:
	for child in slot_container.get_children():
		child.queue_free()

	var any := false
	for slot in GlobalData.MECHA_SLOTS:
		var cost := GlobalData.get_emergency_repair_scrap_cost(slot)
		if cost <= 0:
			continue
		any = true
		var name := str(SLOT_DISPLAY.get(slot, slot))
		if GlobalData.has_scrap_patch(slot):
			name += " [patched]"
		var btn := Button.new()
		btn.text = "%s  (scrap: %d)" % [name, cost]
		btn.custom_minimum_size = Vector2(200, 30)
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_meta("slot_name", slot)
		btn.pressed.connect(_on_slot_button_pressed.bind(slot))
		slot_container.add_child(btn)

	if not any:
		var lbl := Label.new()
		lbl.text = "All slots are in good condition."
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		slot_container.add_child(lbl)


func _on_slot_button_pressed(slot: String) -> void:
	_select_slot(slot)


func _select_slot(slot: String) -> void:
	selected_slot = slot
	_clear_live_primitives()
	var patch: Dictionary = GlobalData.scrap_patches.get(slot, {})
	if not patch.is_empty():
		var existing: Array = patch.get("primitives", [])
		if existing is Array:
			editing_primitives[slot] = existing.duplicate(true)
	if not editing_primitives.has(slot):
		editing_primitives[slot] = []
	selected_primitive_index = 0 if not editing_primitives[slot].is_empty() else -1
	_refresh_editor_view()
	_update_status()


# ---------------------------------------------------------------------------
# Primitive editing
# ---------------------------------------------------------------------------
func _add_primitive(shape: String) -> void:
	if selected_slot == "":
		_update_status("Select a damaged slot first.")
		return
	var primitives: Array = editing_primitives[selected_slot]
	primitives.append({
		"shape": shape,
		"pos": [0.0, 0.0, 0.0],
		"rot": [0.0, 0.0, 0.0],
		"scale": [0.5, 0.5, 0.5],
		"color": SCRAP_COLOR.duplicate(),
	})
	selected_primitive_index = primitives.size() - 1
	_refresh_editor_view()


func _get_selected_primitive() -> Dictionary:
	if selected_slot == "" or not editing_primitives.has(selected_slot):
		return {}
	var primitives: Array = editing_primitives[selected_slot]
	if selected_primitive_index < 0 or selected_primitive_index >= primitives.size():
		return {}
	return primitives[selected_primitive_index]


func _on_delete_primitive_pressed() -> void:
	if selected_slot == "" or not editing_primitives.has(selected_slot):
		return
	var primitives: Array = editing_primitives[selected_slot]
	if selected_primitive_index < 0 or selected_primitive_index >= primitives.size():
		return
	primitives.remove_at(selected_primitive_index)
	selected_primitive_index = mini(selected_primitive_index, primitives.size() - 1)
	_refresh_editor_view()


func _on_clear_pressed() -> void:
	if selected_slot == "":
		return
	editing_primitives[selected_slot] = []
	selected_primitive_index = -1
	_refresh_editor_view()


func _move_selected(delta: Vector3) -> void:
	var prim: Dictionary = _get_selected_primitive()
	if prim.is_empty():
		return
	var pos: Array = (prim.get("pos") as Array).duplicate()
	pos[0] = float(pos[0]) + delta.x
	pos[1] = float(pos[1]) + delta.y
	pos[2] = float(pos[2]) + delta.z
	prim["pos"] = pos
	_refresh_editor_view()


func _rotate_selected(angle: float) -> void:
	var prim: Dictionary = _get_selected_primitive()
	if prim.is_empty():
		return
	var rot: Array = (prim.get("rot") as Array).duplicate()
	rot[1] = float(rot[1]) + angle
	prim["rot"] = rot
	_refresh_editor_view()


func _scale_selected(factor: float) -> void:
	var prim: Dictionary = _get_selected_primitive()
	if prim.is_empty():
		return
	var scale: Array = (prim.get("scale") as Array).duplicate()
	for i in range(scale.size()):
		scale[i] = clampf(float(scale[i]) * factor, 0.05, 8.0)
	prim["scale"] = scale
	_refresh_editor_view()


func _cycle_primitive(forward: bool) -> void:
	if selected_slot == "" or not editing_primitives.has(selected_slot):
		return
	var primitives: Array = editing_primitives[selected_slot]
	if primitives.is_empty():
		return
	if forward:
		selected_primitive_index = (selected_primitive_index + 1) % primitives.size()
	else:
		selected_primitive_index = posmod(selected_primitive_index - 1, primitives.size())
	_refresh_editor_view()


# ---------------------------------------------------------------------------
# Live viewport rendering
# ---------------------------------------------------------------------------
func _refresh_editor_view() -> void:
	_render_live_primitives()
	_rebuild_primitive_label()
	_update_status()


func _clear_live_primitives() -> void:
	if mecha_node == null:
		return
	for slot in GlobalData.MECHA_SLOTS:
		var parent = _get_slot_node(slot)
		if parent == null:
			continue
		var container = parent.get_node_or_null("EditorScrapPatch")
		if container:
			container.queue_free()


func _render_live_primitives() -> void:
	if mecha_node == null or selected_slot == "":
		return
	var parent = _get_slot_node(selected_slot)
	if parent == null:
		return
	var container: Node3D = parent.get_node_or_null("EditorScrapPatch")
	if container == null:
		container = Node3D.new()
		container.name = "EditorScrapPatch"
		parent.add_child(container)
	for child in container.get_children():
		child.queue_free()

	var primitives: Array = editing_primitives.get(selected_slot, [])
	var idx := 0
	for primitive in primitives:
		if not (primitive is Dictionary):
			continue
		var mi := MeshInstance3D.new()
		mi.position = GlobalData.scrap_primitive_pos(primitive)
		mi.rotation = GlobalData.scrap_primitive_rot(primitive)
		mi.scale = GlobalData.scrap_primitive_scale(primitive)
		mi.mesh = _build_primitive_mesh(str(primitive.get("shape", "box")))
		var mat := StandardMaterial3D.new()
		var color: Color = GlobalData.scrap_primitive_color(primitive)
		if idx == selected_primitive_index:
			color = color.lerp(Color(1.0, 0.9, 0.3, 1.0), 0.35)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.8, 0.2)
			mat.emission_energy_multiplier = 0.6
		mat.albedo_color = color
		mat.metallic = 0.15
		mat.roughness = 0.8
		mi.material_override = mat
		container.add_child(mi)
		idx += 1


func _build_primitive_mesh(shape: String) -> Mesh:
	match shape.to_lower():
		"sphere":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			return s
		"wedge":
			var w := PrismMesh.new()
			w.size = Vector3.ONE
			return w
		"cylinder":
			var c := CylinderMesh.new()
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 1.0
			return c
		_:
			var b := BoxMesh.new()
			b.size = Vector3.ONE
			return b


func _get_slot_node(slot: String) -> Node3D:
	if mecha_node == null:
		return null
	var path: String = GlobalData.get_slot_node_path(slot)
	if path == "":
		return null
	return mecha_node.get_node_or_null(path)


func _rebuild_primitive_label() -> void:
	if selected_slot == "" or not editing_primitives.has(selected_slot):
		primitives_label.text = "Select a damaged slot to start patching."
		return
	var primitives: Array = editing_primitives[selected_slot]
	if primitives.is_empty():
		primitives_label.text = "No scrap parts yet. Add a shape to build armor."
		return
	var text := "Parts on %s:\n" % str(SLOT_DISPLAY.get(selected_slot, selected_slot))
	for i in range(primitives.size()):
		var p: Dictionary = primitives[i]
		var marker := "  " if i != selected_primitive_index else "->"
		text += "%s %d. %s  p:%s  s:%s\n" % [
			marker, i + 1,
			str(p.get("shape", "box")),
			_short_vec(p.get("pos", [0, 0, 0])),
			_short_vec(p.get("scale", [1, 1, 1])),
		]
	primitives_label.text = text


func _short_vec(value) -> String:
	if value is Array and value.size() >= 3:
		return "(%0.1f,%0.1f,%0.1f)" % [value[0], value[1], value[2]]
	return "(0,0,0)"


# ---------------------------------------------------------------------------
# Apply / status
# ---------------------------------------------------------------------------
func _on_apply_pressed() -> void:
	if selected_slot == "":
		_update_status("Select a damaged slot first.")
		return
	var primitives: Array = editing_primitives.get(selected_slot, [])
	var patch := GlobalData.apply_emergency_repair(selected_slot, primitives)
	if patch.is_empty():
		_update_status("Not enough scrap, or the slot is already fine.")
		return
	if pmm and pmm.has_method("refresh_slots"):
		pmm.refresh_slots()
	_clear_live_primitives()
	_update_status("%s patched! (tier %d scrap, %d%% stats)" % [
		str(SLOT_DISPLAY.get(selected_slot, selected_slot)),
		int(patch.get("tier", 1)),
		int(float(patch.get("stat_scale", 0.4)) * 100.0),
	])
	_refresh_slot_list()
	if selected_slot != "" and GlobalData.has_scrap_patch(selected_slot):
		var patch_data: Dictionary = GlobalData.scrap_patches.get(selected_slot, {})
		editing_primitives[selected_slot] = patch_data.get("primitives", [])
		selected_primitive_index = 0 if not editing_primitives[selected_slot].is_empty() else -1
	_rebuild_primitive_label()


func _update_status(message: String = "") -> void:
	if message != "":
		status_label.text = message
		return
	if selected_slot == "":
		status_label.text = "Scrap: %d | Repair skill: %d (XP %d)" % [
			GlobalData.scrap, GlobalData.driver_repair_skill, GlobalData.driver_repair_xp,
		]
		apply_button.text = "Apply Repair"
		apply_button.disabled = true
		return
	var cost := GlobalData.get_emergency_repair_scrap_cost(selected_slot)
	var name := str(SLOT_DISPLAY.get(selected_slot, selected_slot))
	if GlobalData.has_scrap_patch(selected_slot):
		name += " (patched)"
	slot_info_label.text = "%s: %d scrap to patch" % [name, cost]
	var primitives: Array = editing_primitives.get(selected_slot, [])
	apply_button.text = "Apply Repair (%d scrap)" % cost
	apply_button.disabled = GlobalData.scrap < cost or primitives.is_empty()
	status_label.text = "Scrap: %d | Repair skill: %d (XP %d)" % [
		GlobalData.scrap, GlobalData.driver_repair_skill, GlobalData.driver_repair_xp,
	]


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var shift = event.shift_pressed
		var step := 0.03 if shift else MOVE_STEP
		var consumed := true
		match event.keycode:
			KEY_LEFT:
				_move_selected(Vector3(-step, 0, 0))
			KEY_RIGHT:
				_move_selected(Vector3(step, 0, 0))
			KEY_UP:
				_move_selected(Vector3(0, 0, -step))
			KEY_DOWN:
				_move_selected(Vector3(0, 0, step))
			KEY_PAGEUP:
				_move_selected(Vector3(0, step, 0))
			KEY_PAGEDOWN:
				_move_selected(Vector3(0, -step, 0))
			KEY_Q:
				_rotate_selected(-ROT_STEP if shift else ROT_STEP)
			KEY_E:
				_rotate_selected(ROT_STEP if shift else -ROT_STEP)
			KEY_MINUS:
				_scale_selected(1.0 / SCALE_FACTOR)
			KEY_EQUAL:
				_scale_selected(SCALE_FACTOR)
			KEY_TAB:
				_cycle_primitive(not shift)
			KEY_BACKSPACE:
				_on_delete_primitive_pressed()
			_:
				consumed = false
		if consumed:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed and _is_over_viewport(event.position)
	elif event is InputEventMouseMotion and _dragging:
		turntable_node.rotate_y(-event.relative.x * 0.008)


func _is_over_viewport(mouse_pos: Vector2) -> bool:
	if viewport_container == null:
		return false
	var rect := viewport_container.get_global_rect()
	rect = rect.grow(-40)
	return rect.has_point(mouse_pos)
