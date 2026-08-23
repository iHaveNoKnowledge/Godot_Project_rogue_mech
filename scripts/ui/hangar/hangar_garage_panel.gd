class_name HangarGaragePanel
extends RefCounted

## Live 3D garage preview + attachment load math, extracted from
## hangar_controller.gd.
##
## Owns the SubViewport 3D scene (floor, turntable, mech, camera), the slot
## previews (chassis / frame / armor / weapon / salvage materials), the
## selection-highlight + camera-focus + tab-blink state, the mouse-drag
## turntable/attachment input, and the pure attachment load helpers used by the
## equip UI. `controller` is the hangar node the 3D viewport is added to.

var controller: Node

# 3D Garage Nodes
var viewport_container: SubViewportContainer
var sub_viewport: SubViewport
var hangar_env_node: Node3D
var garage_cam: Camera3D
var mecha_3d_root: Node3D
var turntable_node: Node3D
var selection_highlight: MeshInstance3D
var cam_target_pos: Vector3 = Vector3(6.2, 1.6, 8.8)
var cam_look_target: Vector3 = Vector3(0, 3.2, 0)
var current_cam_pos: Vector3 = Vector3(6.2, 1.6, 8.8)
var current_look_pos: Vector3 = Vector3(0, 3.2, 0)

# Mouse-drag + tab-blink state.
var _is_dragging_3d: bool = false
var _blink_timer: float = 0.0
var _blink_interval: float = 0.45
var _blink_on: bool = true
var _blink_target_button: Button = null


func build_garage() -> void:
	viewport_container = SubViewportContainer.new()
	viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	controller.add_child(viewport_container)

	sub_viewport = SubViewport.new()
	sub_viewport.size = Vector2i(1280, 720)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Own physics world: SubViewports share the parent world by default. The
	# garage mech's collision capsule must never interact with the main world
	# (or the emergency repair editor's mech, which would climb on top of it).
	sub_viewport.own_world_3d = true
	viewport_container.add_child(sub_viewport)

	hangar_env_node = Node3D.new()
	sub_viewport.add_child(hangar_env_node)

	# Floor & Base Ring
	var floor_mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	var mat_floor = StandardMaterial3D.new()
	mat_floor.albedo_color = Color(0.12, 0.14, 0.18)
	mat_floor.metallic = 0.8
	mat_floor.roughness = 0.4
	floor_mesh.material_override = mat_floor
	hangar_env_node.add_child(floor_mesh)

	turntable_node = Node3D.new()
	hangar_env_node.add_child(turntable_node)

	var ring = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 4.0
	cyl.bottom_radius = 4.3
	cyl.height = 0.15
	ring.mesh = cyl
	var mat_ring = StandardMaterial3D.new()
	mat_ring.albedo_color = Color(0.2, 0.25, 0.35)
	mat_ring.emission_enabled = true
	mat_ring.emission = Color(0.2, 0.6, 0.9)
	mat_ring.emission_energy_multiplier = 1.2
	ring.material_override = mat_ring
	turntable_node.add_child(ring)

	# Spotlights
	var spot = SpotLight3D.new()
	spot.position = Vector3(3, 8, 5)
	hangar_env_node.add_child(spot)
	spot.look_at(Vector3(0, 2.9, 0), Vector3.UP)
	spot.light_energy = 4.0
	spot.spot_range = 20.0
	spot.spot_angle = 45.0
	spot.light_color = Color(0.9, 0.95, 1.0)

	var rim = SpotLight3D.new()
	rim.position = Vector3(-4, 5, -4)
	hangar_env_node.add_child(rim)
	rim.look_at(Vector3(0, 2.5, 0), Vector3.UP)
	rim.light_energy = 2.5
	rim.light_color = Color(0.3, 0.7, 1.0)

	# 3D Mecha Model in Garage
	mecha_3d_root = Node3D.new()
	turntable_node.add_child(mecha_3d_root)

	var scene_base = preload("res://scenes/mecha/mecha_base.tscn").instantiate()
	scene_base.set_script(null)
	for child in scene_base.get_children():
		child.set_process(false)
		child.set_physics_process(false)
	apply_tactical_idle_pose(scene_base)
	mecha_3d_root.add_child(scene_base)

	var pmm = scene_base.get_node_or_null("PartMeshManager")
	if pmm and pmm.has_method("_hide_all_legacy_models"):
		pmm._hide_all_legacy_models()

	# Camera
	garage_cam = Camera3D.new()
	garage_cam.position = current_cam_pos
	hangar_env_node.add_child(garage_cam)
	garage_cam.look_at(current_look_pos, Vector3.UP)
	garage_cam.fov = 55.0


# --- ARMORED CORE / 30MM TACTICAL COMBAT IDLE POSE ---
func apply_tactical_idle_pose(mecha_node: Node3D) -> void:
	if not mecha_node:
		return

	var head = mecha_node.get_node_or_null("Head")
	var body = mecha_node.get_node_or_null("Body")
	var arm_left = mecha_node.get_node_or_null("ArmLeft")
	var arm_right = mecha_node.get_node_or_null("ArmRight")
	var forearm_left = mecha_node.get_node_or_null("ArmLeft/ForearmLeft")
	var forearm_right = mecha_node.get_node_or_null("ArmRight/ForearmRight")
	var leg_left = mecha_node.get_node_or_null("LegLeft")
	var leg_right = mecha_node.get_node_or_null("LegRight")
	var shin_left = mecha_node.get_node_or_null("LegLeft/ShinLeft")
	var shin_right = mecha_node.get_node_or_null("LegRight/ShinRight")

	# Clean Upright Neutral Standing Stance (Zero Joint Rotations)
	if body:
		body.rotation = Vector3.ZERO
		body.position.y = 1.75

	if head:
		head.rotation = Vector3.ZERO
		head.position.y = 2.45

	if leg_left:
		leg_left.rotation = Vector3.ZERO
	if leg_right:
		leg_right.rotation = Vector3.ZERO

	if shin_left:
		shin_left.rotation = Vector3.ZERO
	if shin_right:
		shin_right.rotation = Vector3.ZERO

	if arm_left:
		arm_left.rotation = Vector3.ZERO
	if forearm_left:
		forearm_left.rotation = Vector3.ZERO

	if arm_right:
		arm_right.rotation = Vector3.ZERO
	if forearm_right:
		forearm_right.rotation = Vector3.ZERO


# --- 3D CAMERA & MOUSE DRAG PROCESS ---

# Called every frame by the controller's _process: smooth camera follow + the
# selection-tab blink pulse.
func process(delta: float) -> void:
	current_cam_pos = current_cam_pos.lerp(cam_target_pos, 5.0 * delta)
	current_look_pos = current_look_pos.lerp(cam_look_target, 5.0 * delta)
	if garage_cam:
		garage_cam.position = current_cam_pos
		garage_cam.look_at(current_look_pos, Vector3.UP)

	if _blink_target_button and is_instance_valid(_blink_target_button):
		_blink_timer += delta
		if _blink_timer >= _blink_interval:
			_blink_timer = 0.0
			_blink_on = not _blink_on
			apply_tab_blink(_blink_on)


# Mouse drag: rotate the turntable, or drag the selected attachment on the mech
# when the attachment page is active. The controller gates this behind its own
# visibility + scrap-editor checks before calling in.
func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging_3d = event.pressed
	elif event is InputEventMouseMotion and _is_dragging_3d:
		if controller.current_mode == "attachment" and not controller.selected_attachment_info.is_empty():
			move_selected_attachment(event.relative)
		elif turntable_node:
			turntable_node.rotate_y(event.relative.x * 0.008)


func clear_selection_blink() -> void:
	_blink_target_button = null


func update_selection_highlight(slot: String) -> void:
	var label: Label = null
	if controller.root_control:
		label = controller.root_control.find_child("SelectionLabel", true, false) as Label
	if label:
		label.text = "EDITING: %s" % slot.to_upper()

	# Highlight & blink the matching UI slot tab instead of the 3D model.
	remove_3d_selection_highlight()
	_blink_target_button = null
	for key in controller.slot_tab_buttons:
		apply_tab_unselected(controller.slot_tab_buttons[key])
	if controller.slot_tab_buttons.has(slot):
		_blink_target_button = controller.slot_tab_buttons[slot]
		_blink_timer = 0.0
		_blink_on = true
		apply_tab_blink(true)


func apply_tab_unselected(btn: Button) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	# Unselected slot tabs are dimmed/grayed out entirely.
	btn.modulate = Color(0.5, 0.5, 0.56)
	btn.remove_theme_color_override("font_color")
	btn.remove_theme_color_override("font_hover_color")
	btn.remove_theme_color_override("font_pressed_color")
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.remove_theme_stylebox_override(state)


func remove_3d_selection_highlight() -> void:
	if selection_highlight and is_instance_valid(selection_highlight):
		selection_highlight.queue_free()
	selection_highlight = null


func apply_tab_blink(on: bool) -> void:
	if _blink_target_button == null or not is_instance_valid(_blink_target_button):
		return
	var btn: Button = _blink_target_button
	# Blink the ENTIRE tab rectangle (background), not just the text: a filled
	# accent stylebox that pulses between bright and dim.
	btn.modulate = Color.WHITE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.55, 1.0, 0.95 if on else 0.35)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1.0, 0.9, 0.4, 1.0)
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, style)
	btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))


func update_camera_focus(slot: String) -> void:
	match slot:
		"head":
			cam_target_pos = Vector3(2.6, 3.0, 3.2)
			cam_look_target = Vector3(0, 3.0, 0)
		"body":
			cam_target_pos = Vector3(3.4, 2.5, 4.0)
			cam_look_target = Vector3(0, 2.5, 0)
		"arm_left", "arm_right", "weapon_left", "weapon_right", "weapon_carry":
			cam_target_pos = Vector3(3.4, 2.3, 3.2)
			cam_look_target = Vector3(0, 2.3, 0)
		"leg_left", "leg_right":
			cam_target_pos = Vector3(3.8, 1.6, 3.8)
			cam_look_target = Vector3(0, 1.2, 0)
		_:
			cam_target_pos = Vector3(4.2, 2.4, 5.0)
			cam_look_target = Vector3(0, 2.2, 0)


# --- REAL-TIME 3D PREVIEWS IN GARAGE ---

func apply_chassis_preview(info: Dictionary) -> void:
	if mecha_3d_root == null: return
	var color = info.get("color", Color(0.6, 0.65, 0.7))
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.85
	mat.roughness = 0.35

	var mat_dark = StandardMaterial3D.new()
	mat_dark.albedo_color = Color(0.18, 0.20, 0.25)
	mat_dark.metallic = 0.9
	mat_dark.roughness = 0.2

	var mat_visor = StandardMaterial3D.new()
	mat_visor.emission_enabled = true
	mat_visor.emission_energy_multiplier = 3.5

	var head_node = mecha_3d_root.get_node_or_null("MechaBase/Head")
	var body_node = mecha_3d_root.get_node_or_null("MechaBase/Body")
	var arm_left = mecha_3d_root.get_node_or_null("MechaBase/ArmLeft")
	var arm_right = mecha_3d_root.get_node_or_null("MechaBase/ArmRight")
	var leg_left = mecha_3d_root.get_node_or_null("MechaBase/LegLeft")
	var leg_right = mecha_3d_root.get_node_or_null("MechaBase/LegRight")

	match controller.selected_chassis_key:
		"standard":
			mat.albedo_color = Color(0.7, 0.72, 0.78)
			mat_visor.emission = Color(0.0, 0.9, 1.0) # Cyan Visor
			if body_node: body_node.scale = Vector3(1.0, 1.0, 1.0)
			if arm_left: arm_left.scale = Vector3(1.0, 1.0, 1.0)
			if arm_right: arm_right.scale = Vector3(1.0, 1.0, 1.0)
			if leg_left: leg_left.scale = Vector3(1.0, 1.0, 1.0)
			if leg_right: leg_right.scale = Vector3(1.0, 1.0, 1.0)
		"titan":
			mat.albedo_color = Color(0.3, 0.15, 0.35) # Dark Purple
			mat.metallic = 0.95
			mat_visor.emission = Color(1.0, 0.1, 0.2) # Red Visor
			if body_node: body_node.scale = Vector3(1.4, 1.25, 1.35)
			if arm_left: arm_left.scale = Vector3(1.35, 1.2, 1.35)
			if arm_right: arm_right.scale = Vector3(1.35, 1.2, 1.35)
			if leg_left: leg_left.scale = Vector3(1.25, 1.1, 1.25)
			if leg_right: leg_right.scale = Vector3(1.25, 1.1, 1.25)
		"vanguard":
			mat.albedo_color = Color(0.85, 0.88, 0.95) # Sleek White/Cyan
			mat.metallic = 0.75
			mat_visor.emission = Color(0.1, 1.0, 0.5) # Emerald Visor
			if body_node: body_node.scale = Vector3(0.88, 1.15, 0.85)
			if arm_left: arm_left.scale = Vector3(0.9, 1.05, 0.9)
			if arm_right: arm_right.scale = Vector3(0.9, 1.05, 0.9)
			if leg_left: leg_left.scale = Vector3(0.9, 1.1, 0.9)
			if leg_right: leg_right.scale = Vector3(0.9, 1.1, 0.9)
		"aegis":
			mat.albedo_color = Color(0.2, 0.4, 0.55) # Navy Blue Chobham
			mat.metallic = 0.9
			mat_visor.emission = Color(1.0, 0.8, 0.0) # Amber Gold Visor
			if body_node: body_node.scale = Vector3(1.35, 1.0, 1.45)
			if arm_left: arm_left.scale = Vector3(1.25, 1.0, 1.25)
			if arm_right: arm_right.scale = Vector3(1.25, 1.0, 1.25)
			if leg_left: leg_left.scale = Vector3(1.3, 1.0, 1.3)
			if leg_right: leg_right.scale = Vector3(1.3, 1.0, 1.3)
		"brawler":
			mat.albedo_color = Color(0.35, 0.40, 0.28) # Military Olive Green
			mat.metallic = 0.9
			mat.roughness = 0.25
			mat_visor.emission = Color(1.0, 0.5, 0.0) # Industrial Orange Visor
			if body_node: body_node.scale = Vector3(1.25, 0.95, 1.2)
			if arm_left: arm_left.scale = Vector3(1.4, 1.15, 1.4)
			if arm_right: arm_right.scale = Vector3(1.4, 1.15, 1.4)
			if leg_left: leg_left.scale = Vector3(1.3, 0.95, 1.3)
			if leg_right: leg_right.scale = Vector3(1.3, 0.95, 1.3)

	var mecha = mecha_3d_root.get_node_or_null("MechaBase")
	if mecha:
		var pmm = mecha.get_node_or_null("PartMeshManager")
		if pmm and pmm.has_method("set_slot_material"):
			for s in GlobalData.MECHA_SLOTS:
				pmm.set_slot_material(s, mat)


func apply_frame_preview(slot: String, info: Dictionary) -> void:
	if mecha_3d_root == null: return
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.18)
	mat.metallic = 0.95
	mat.roughness = 0.15
	set_slot_material(slot, mat)


func apply_armor_preview(slot: String, info: Dictionary) -> void:
	if mecha_3d_root == null: return
	if slot.begins_with("weapon"):
		preview_weapon_on_hand(slot, info)
		return
	var mecha = get_mecha_base()
	var pmm = get_part_mesh_manager()
	if pmm:
		var part = ArmorPart.new()
		part.part_name = info.get("name", "Spiky Armor")
		part.max_hp = info.get("durability", info.get("max_hp", 100.0))
		if info.has("color"):
			part.part_color = info.get("color")
		pmm.initialize_slot(slot, part)
		if mecha:
			update_weapon_preview(mecha)


# Returns the mech's root Node3D (MechaBase if present, else the whole scene).
func get_mecha_base() -> Node3D:
	if mecha_3d_root == null:
		return null
	return mecha_3d_root.get_node_or_null("MechaBase") if mecha_3d_root.has_node("MechaBase") else mecha_3d_root


# Returns the PartMeshManager attached to the mech base, or null.
func get_part_mesh_manager() -> Node:
	var mecha = get_mecha_base()
	return mecha.get_node_or_null("PartMeshManager") if mecha else null


# Shows a selected weapon on the matching hand (or on the back for carry) as a
# live preview (not yet equipped).
func preview_weapon_on_hand(slot: String, info: Dictionary) -> void:
	var mecha = get_mecha_base()
	if mecha == null:
		return
	var weapon_path = info.get("path", "")
	if weapon_path == "" or not ResourceLoader.exists(weapon_path):
		return
	var weapon = load(weapon_path)
	if weapon == null:
		return
	if slot == "weapon_carry":
		WeaponVisualFactory.mount_carry(mecha, [weapon], "WeaponVisual_carry")
	else:
		var hand = "left" if slot == "weapon_left" else "right"
		WeaponVisualFactory.mount_hand(mecha, hand, weapon, "WeaponVisual_" + hand)


func update_all_slots_preview() -> void:
	var mecha = get_mecha_base()
	var pmm = get_part_mesh_manager()
	if not pmm: return

	# While a REGISTER assembly is armed the working set is a blank slate, so
	# slots without an inner frame render a faint ghost skeleton instead of
	# vanishing — the player can see exactly where each frame goes.
	var rp = controller.roster_panel_ui if controller else null
	pmm.set_ghost_mode(rp != null and rp.has_method("is_pending_register_active") and rp.is_pending_register_active())
	pmm.refresh_slots()

	var attachment_manager = mecha.get_node_or_null("AttachmentManager") if mecha else null
	if attachment_manager:
		attachment_manager.rebuild_from_global_data()

	update_weapon_preview(mecha)


# Shows the equipped weapons on the mech's hands and back in the 3D garage.
# Uses the SAME shared factory (WeaponVisualFactory) as battle so the model
# shown in the hangar is exactly what appears in combat.
func update_weapon_preview(mecha: Node3D) -> void:
	if mecha == null:
		return
	for hand in ["left", "right"]:
		var weapon = LoadoutSystem.get_equipped_weapon(hand)
		# If the arm frame holding this hand's weapon is destroyed, the weapon
		# is no longer mounted on the mech (it was dropped in battle).
		var arm_slot = "arm_left" if hand == "left" else "arm_right"
		if weapon == null or GlobalData.weapons.part_damage.get(arm_slot + "_frame", 0.0) >= 1.0:
			weapon = null
		WeaponVisualFactory.mount_hand(mecha, hand, weapon, "WeaponVisual_" + hand)

	# Back carry weapons (spread horizontally across the back pack).
	WeaponVisualFactory.mount_carry(mecha, LoadoutSystem.get_carry_weapons(), "WeaponVisual_carry")


func get_attachment_capacity(slot: String) -> float:
	var info = LoadoutSystem.get_chassis_stats()
	var capacities: Dictionary = info.get("attachment_capacity", {})
	return float(capacities.get(slot, 0.0))


func get_attachment_weight(slot: String, excluding_id: String = "") -> float:
	var total := 0.0
	for attachment in GlobalData.weapons.attachments:
		if attachment.get("slot", "") == slot and attachment.get("id", "") != excluding_id:
			total += float(attachment.get("weight", 0.0))
	return total


func get_total_load(excluding_attachment_id: String = "", excluding_slot: String = "") -> float:
	var total := 0.0
	for frame in GlobalData.weapons.equipped_frames.values():
		total += float(frame.get("weight", 0.0))
	for slot in GlobalData.weapons.equipped_parts:
		var part = GlobalData.weapons.equipped_parts[slot]
		if part is Dictionary:
			total += float(part.get("weight", 0.0))
	for attachment in GlobalData.weapons.attachments:
		if attachment.get("id", "") != excluding_attachment_id or attachment.get("slot", "") != excluding_slot:
			total += float(attachment.get("weight", 0.0))
	total += LoadoutSystem.get_loadout_weapon_weight()
	return total


# Returns true if adding `new_weight_path` to the loadout (optionally replacing
# `replaced_path`) would push the total frame load over the chassis max weight.
# Field Pack capacity check (hand weapons + carry weapons + ammo <= frame-based cap).
# `freed_path` is a weapon that stops being carried when this equip is a MOVE of
# an already-equipped model (it is leaving the other hand or the back pack), so
# its weight no longer counts against the pack.
func would_exceed_field_pack(new_weight_path: String, replaced_path: String = "", freed_path: String = "") -> bool:
	var current_weapons := LoadoutSystem.get_loadout_weapons_total()
	for subtract_path in [replaced_path, freed_path]:
		if subtract_path != "" and ResourceLoader.exists(subtract_path):
			var old = load(subtract_path)
			if old:
				current_weapons -= float(old.weight)
	var new_w = load(new_weight_path)
	var new_wt = float(new_w.weight) if new_w else 0.0
	return current_weapons + new_wt + LoadoutSystem.get_field_pack_ammo_weight() > LoadoutSystem.get_field_pack_capacity()


func has_attachment(attachment_id: String, slot: String) -> bool:
	for attachment in GlobalData.weapons.attachments:
		if attachment.get("id", "") == attachment_id and attachment.get("slot", "") == slot:
			return true
	return false


func get_default_attachment_position(slot: String) -> Vector3:
	match slot:
		"head": return Vector3(0.0, 0.15, -0.35)
		"body": return Vector3(0.0, 0.2, -0.45)
		"arm_left": return Vector3(-0.05, -0.2, -0.25)
		"arm_right": return Vector3(0.05, -0.2, -0.25)
		"leg_left": return Vector3(0.0, -0.45, -0.2)
		"leg_right": return Vector3(0.0, -0.45, -0.2)
	return Vector3.ZERO


func move_selected_attachment(mouse_delta: Vector2) -> void:
	var id := str(controller.selected_attachment_info.get("id", ""))
	if id.is_empty(): return
	for attachment in GlobalData.weapons.attachments:
		if attachment.get("id", "") == id and attachment.get("slot", "") == controller.selected_slot:
			var raw_position = attachment.get("position", Vector3.ZERO)
			var position: Vector3 = raw_position if raw_position is Vector3 else Vector3(raw_position.get("x", 0.0), raw_position.get("y", 0.0), raw_position.get("z", 0.0))
			position.x = clampf(position.x + mouse_delta.x * 0.004, -1.5, 1.5)
			position.y = clampf(position.y - mouse_delta.y * 0.004, -1.5, 1.5)
			attachment["position"] = position
			var mecha = get_mecha_base()
			var manager = mecha.get_node_or_null("AttachmentManager") if mecha else null
			if manager:
				manager.update_attachment_transform(id, position, attachment.get("rotation", Vector3.ZERO))
			GlobalData.save_run()
			return


func apply_salvage_preview(slot: String, info: Dictionary) -> void:
	if mecha_3d_root == null: return
	var mat = StandardMaterial3D.new()
	mat.albedo_color = info.get("color", Color(0.2, 0.45, 0.25))
	mat.metallic = 0.75
	mat.roughness = 0.4
	set_slot_material(slot, mat)


func set_slot_material(slot: String, mat: Material) -> void:
	var mecha = get_mecha_base()
	if mecha == null:
		return
	var section := LoadoutSystem.get_slot_node_path(slot)
	if slot == "leg_left" or slot == "leg_right":
		for leg in ["LegLeft", "LegRight"]:
			var node = mecha.get_node_or_null(leg + "/" + leg + "Mesh")
			if node: node.material_override = mat
		return
	if section == "":
		return
	var node = mecha.get_node_or_null(section + "/" + section + "Mesh")
	if node: node.material_override = mat
