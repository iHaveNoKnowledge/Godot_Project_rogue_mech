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
var cam_target_pos: Vector3 = MechaScaleSystem.HANGAR_CAM["initial_pos"]
var cam_look_target: Vector3 = MechaScaleSystem.HANGAR_CAM["initial_look"]
var current_cam_pos: Vector3 = MechaScaleSystem.HANGAR_CAM["initial_pos"]
var current_look_pos: Vector3 = MechaScaleSystem.HANGAR_CAM["initial_look"]

# Mouse-drag + tab-blink state.
var _is_dragging_3d: bool = false
var _blink_timer: float = 0.0
var _blink_interval: float = 0.45
var _blink_on: bool = true
var _blink_target_button: Button = null

# Realtime In-World Mode (War Mode)
var is_realtime_world: bool = false
var realtime_target_mecha: Node3D = null
var previous_camera: Camera3D = null
var is_built: bool = false


func build_garage() -> void:
	if is_built:
		return
	is_built = true

	if is_realtime_world:
		_build_realtime_garage()
		return

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

	# 1. Industrial Hangar Bay Architecture
	_build_hangar_bay_room()

	# 2. Turntable Node (Heavy Brushed Steel with subtle LED accent ring)
	turntable_node = Node3D.new()
	hangar_env_node.add_child(turntable_node)
	_build_turntable_platform()

	# 3. Studio WorldEnvironment (SSAO, SSR, ACES Tonemapping & Bright Showroom Ambient)
	var hangar_world_env := WorldEnvironment.new()
	var h_env := Environment.new()
	h_env.background_mode = Environment.BG_COLOR
	h_env.background_color = Color(0.12, 0.14, 0.18)
	h_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	h_env.ambient_light_color = Color(0.60, 0.68, 0.80)
	h_env.ambient_light_energy = 1.70

	h_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	h_env.tonemap_exposure = 1.08
	h_env.tonemap_white = 0.88
	h_env.adjustment_enabled = true
	h_env.adjustment_contrast = 1.06
	h_env.adjustment_saturation = 1.04
	h_env.adjustment_brightness = 1.0

	h_env.ssao_enabled = true
	h_env.ssao_radius = 1.4
	h_env.ssao_intensity = 1.85
	h_env.ssao_power = 1.45
	h_env.ssao_detail = 0.62
	h_env.ssao_horizon = 0.08
	h_env.ssil_enabled = true
	h_env.ssil_intensity = 0.35
	h_env.ssil_radius = 3.2

	h_env.ssr_enabled = false
	h_env.ssr_max_steps = 16
	h_env.ssr_fade_in = 0.30
	h_env.ssr_fade_out = 2.0

	h_env.glow_enabled = true
	h_env.glow_intensity = 0.30
	h_env.glow_bloom = 0.08
	h_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	h_env.glow_hdr_threshold = 1.40
	h_env.glow_hdr_scale = 0.85
	hangar_world_env.environment = h_env
	hangar_env_node.add_child(hangar_world_env)

	# 4. Professional High-Luminance Studio Lighting
	# Key Light (Warm Front-Right)
	var key_spot := SpotLight3D.new()
	key_spot.position = Vector3(4.5, 7.5, 6.0)
	hangar_env_node.add_child(key_spot)
	key_spot.look_at(Vector3(0, 4.2, 0), Vector3.UP)
	key_spot.light_energy = 6.2
	key_spot.spot_range = 25.0
	key_spot.spot_angle = 50.0
	key_spot.light_color = Color(1.0, 0.98, 0.94)
	key_spot.shadow_enabled = true
	key_spot.shadow_blur = 1.25

	# Fill Light (Cool Front-Left)
	var fill_spot := SpotLight3D.new()
	fill_spot.position = Vector3(-5.0, 6.0, 5.0)
	hangar_env_node.add_child(fill_spot)
	fill_spot.look_at(Vector3(0, 3.696, 0), Vector3.UP)
	fill_spot.light_energy = 3.8
	fill_spot.spot_range = 22.0
	fill_spot.spot_angle = 55.0
	fill_spot.light_color = Color(0.75, 0.88, 1.0)
	fill_spot.shadow_enabled = false

	# Overhead Softbox Downlight (Illuminates head, weapons, shoulders)
	var top_softbox := OmniLight3D.new()
	top_softbox.position = Vector3(0.0, 6.8, 1.2)
	hangar_env_node.add_child(top_softbox)
	top_softbox.light_energy = 3.2
	top_softbox.omni_range = 14.0
	top_softbox.light_color = Color(0.94, 0.97, 1.0)

	# Front Showroom Fill (Eliminates harsh shadows on chest & waist)
	var front_fill := OmniLight3D.new()
	front_fill.position = Vector3(0.0, 2.4, 4.2)
	hangar_env_node.add_child(front_fill)
	front_fill.light_energy = 2.0
	front_fill.omni_range = 10.0
	front_fill.light_color = Color(0.96, 0.96, 1.0)

	# Rim Backlight (Crisp Mecha Silhouette Highlight)
	var rim_spot := SpotLight3D.new()
	rim_spot.position = Vector3(0.0, 4.8, -4.5)
	hangar_env_node.add_child(rim_spot)
	rim_spot.look_at(Vector3(0, 3.696, 0), Vector3.UP)
	rim_spot.light_energy = 4.2
	rim_spot.spot_range = 18.0
	rim_spot.spot_angle = 60.0
	rim_spot.light_color = Color(0.40, 0.82, 1.0)
	rim_spot.shadow_enabled = true

	# Gantry Warm Amber Accent Lights (Background Atmosphere behind mecha)
	for x_pos in [-8.0, 8.0]:
		var gantry_accent := OmniLight3D.new()
		gantry_accent.position = Vector3(x_pos, 5.0, 18.0)
		hangar_env_node.add_child(gantry_accent)
		gantry_accent.light_energy = 2.2
		gantry_accent.omni_range = 14.0
		gantry_accent.light_color = Color(1.0, 0.65, 0.25)

	# 3D Mecha Model in Garage (Static Showroom Display Mannequin)
	mecha_3d_root = Node3D.new()
	turntable_node.add_child(mecha_3d_root)

	var scene_base = preload("res://scenes/mecha/mecha_base.tscn").instantiate()
	scene_base.set_script(null)
	for system_node_name in ["AnimationSystem", "MechaAnimation", "FootIKSystem", "MechaCombat", "MechaEject", "Hitbox", "AimRay"]:
		var sys = scene_base.get_node_or_null(system_node_name)
		if sys:
			sys.queue_free()
	for child in scene_base.get_children():
		child.set_process(false)
		child.set_physics_process(false)
	apply_tactical_idle_pose(scene_base)
	mecha_3d_root.add_child(scene_base)

	var pmm = scene_base.get_node_or_null("PartMeshManager")
	if pmm and pmm.has_method("_hide_all_legacy_models"):
		pmm._hide_all_legacy_models()

	# Camera with wide clipping margins to prevent backdrop clipping
	garage_cam = Camera3D.new()
	garage_cam.position = current_cam_pos
	hangar_env_node.add_child(garage_cam)
	garage_cam.look_at(current_look_pos, Vector3.UP)
	garage_cam.fov = 55.0
	garage_cam.near = 0.05
	garage_cam.far = 500.0


func _build_realtime_garage() -> void:
	if realtime_target_mecha == null and controller.has_method("get_player_mecha"):
		realtime_target_mecha = controller.get_player_mecha()
	if realtime_target_mecha == null and GameManager and GameManager.has_method("get_player_mecha"):
		realtime_target_mecha = GameManager.get_player_mecha()
	if realtime_target_mecha == null:
		var mechas := controller.get_tree().get_nodes_in_group("player") if controller.get_tree() else []
		if not mechas.is_empty():
			realtime_target_mecha = mechas[0] as Node3D

	var world_scene = realtime_target_mecha.get_tree().current_scene if (realtime_target_mecha and realtime_target_mecha.get_tree()) else (controller.get_tree().current_scene if controller.get_tree() else null)

	previous_camera = controller.get_viewport().get_camera_3d() if controller.get_viewport() else null

	garage_cam = Camera3D.new()
	garage_cam.name = "RealtimeGarageCamera"
	garage_cam.fov = 55.0
	garage_cam.near = 0.05
	garage_cam.far = 500.0

	if world_scene:
		world_scene.add_child(garage_cam)
	else:
		controller.add_child(garage_cam)

	garage_cam.current = true

	# Set initial camera focus to body/torso
	update_camera_focus("body")
	current_cam_pos = cam_target_pos
	current_look_pos = cam_look_target
	garage_cam.global_position = current_cam_pos
	garage_cam.look_at(current_look_pos, Vector3.UP)


func cleanup_realtime_camera() -> void:
	if previous_camera and is_instance_valid(previous_camera):
		previous_camera.current = true
	if garage_cam and is_instance_valid(garage_cam):
		garage_cam.queue_free()
		garage_cam = null


func _build_hangar_bay_room() -> void:
	# 1. Garage Floor - spacious 80x80 industrial concrete with oil stains
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	floor_mesh.mesh = plane
	var mat_floor := StandardMaterial3D.new()
	mat_floor.albedo_color = Color(0.18, 0.18, 0.19)
	mat_floor.metallic = 0.02
	mat_floor.metallic_specular = 0.32
	mat_floor.roughness = 0.88
	floor_mesh.material_override = mat_floor
	hangar_env_node.add_child(floor_mesh)

	# Oil stain patch under mech
	var stain := MeshInstance3D.new()
	var stain_plane := PlaneMesh.new()
	stain_plane.size = Vector2(8, 6)
	stain.mesh = stain_plane
	var mat_stain := StandardMaterial3D.new()
	mat_stain.albedo_color = Color(0.09, 0.09, 0.11, 0.55)
	mat_stain.metallic = 0.0
	mat_stain.roughness = 0.96
	mat_stain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	stain.material_override = mat_stain
	stain.position = Vector3(0, 0.02, 0.5)
	hangar_env_node.add_child(stain)

	# 2. Back Hangar Wall - placed at +Z = +22.0 (BEHIND the mecha, facing the camera)
	var back_wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(80.0, 20.0, 0.8)
	back_wall.mesh = wall_mesh
	back_wall.position = Vector3(0, 9.5, 22.0)
	var mat_wall := StandardMaterial3D.new()
	mat_wall.albedo_color = Color(0.22, 0.22, 0.24)
	mat_wall.metallic = 0.02
	mat_wall.metallic_specular = 0.32
	mat_wall.roughness = 0.92
	mat_wall.cull_mode = BaseMaterial3D.CULL_BACK
	back_wall.material_override = mat_wall
	hangar_env_node.add_child(back_wall)

	# Side Walls (Left & Right)
	var left_wall := MeshInstance3D.new()
	var side_mesh := BoxMesh.new()
	side_mesh.size = Vector3(0.8, 20.0, 80.0)
	left_wall.mesh = side_mesh
	left_wall.position = Vector3(-38.0, 9.5, 0.0)
	left_wall.material_override = mat_wall
	hangar_env_node.add_child(left_wall)

	var right_wall := MeshInstance3D.new()
	right_wall.mesh = side_mesh
	right_wall.position = Vector3(38.0, 9.5, 0.0)
	right_wall.material_override = mat_wall
	hangar_env_node.add_child(right_wall)

	# 3. Structural Industrial Pillars - positioned along the back wall (+Z = 21.0)
	var mat_pillar := StandardMaterial3D.new()
	mat_pillar.albedo_color = Color(0.26, 0.27, 0.29)
	mat_pillar.metallic = 0.35
	mat_pillar.metallic_specular = 0.35
	mat_pillar.roughness = 0.62

	var mat_hazard := StandardMaterial3D.new()
	mat_hazard.albedo_color = Color(0.82, 0.68, 0.18)
	mat_hazard.metallic = 0.06
	mat_hazard.roughness = 0.72

	for px in [-18.0, -9.0, 0.0, 9.0, 18.0]:
		var pillar := MeshInstance3D.new()
		var p_box := BoxMesh.new()
		p_box.size = Vector3(1.2, 20.0, 1.2)
		pillar.mesh = p_box
		pillar.position = Vector3(px, 9.5, 21.2)
		pillar.material_override = mat_pillar
		hangar_env_node.add_child(pillar)

		# Yellow caution band on pillar
		var band := MeshInstance3D.new()
		var b_box := BoxMesh.new()
		b_box.size = Vector3(1.25, 0.5, 1.25)
		band.mesh = b_box
		band.position = Vector3(px, 2.5, 21.2)
		band.material_override = mat_hazard
		hangar_env_node.add_child(band)

	# 4. Background Gantry / Catwalk - positioned behind mecha at +Z = 19.5
	var gantry := MeshInstance3D.new()
	var g_box := BoxMesh.new()
	g_box.size = Vector3(80.0, 0.45, 3.0)
	gantry.mesh = g_box
	gantry.position = Vector3(0, 5.0, 19.5)
	gantry.material_override = mat_pillar
	hangar_env_node.add_child(gantry)

	# Gantry Safety Railing
	var rail := MeshInstance3D.new()
	var r_box := BoxMesh.new()
	r_box.size = Vector3(80.0, 1.0, 0.10)
	rail.mesh = r_box
	rail.position = Vector3(0, 5.8, 18.1)
	var mat_rail := StandardMaterial3D.new()
	mat_rail.albedo_color = Color(0.78, 0.62, 0.18)
	mat_rail.metallic = 0.08
	mat_rail.roughness = 0.68
	rail.material_override = mat_rail
	hangar_env_node.add_child(rail)


func _build_turntable_platform() -> void:
	# 1. Beveled Outer Base Ring - dirty steel, not chrome
	var base_ring := MeshInstance3D.new()
	var base_cyl := CylinderMesh.new()
	base_cyl.top_radius = 4.2
	base_cyl.bottom_radius = 4.45
	base_cyl.height = 0.12
	base_ring.mesh = base_cyl
	var mat_base := StandardMaterial3D.new()
	mat_base.albedo_color = Color(0.20, 0.21, 0.23)
	mat_base.metallic = 0.32
	mat_base.roughness = 0.58
	mat_base.metallic_specular = 0.35
	base_ring.material_override = mat_base
	turntable_node.add_child(base_ring)

	# 2. Main Turntable Floor Disc - worn painted steel with oil, not titanium
	var top_plate := MeshInstance3D.new()
	var top_cyl := CylinderMesh.new()
	top_cyl.top_radius = 3.95
	top_cyl.bottom_radius = 4.05
	top_cyl.height = 0.16
	top_plate.mesh = top_cyl
	var mat_top := StandardMaterial3D.new()
	mat_top.albedo_color = Color(0.24, 0.24, 0.26)
	mat_top.metallic = 0.18
	mat_top.metallic_specular = 0.35
	mat_top.roughness = 0.68
	top_plate.material_override = mat_top
	turntable_node.add_child(top_plate)

	# 3. Subtle Sleek LED Perimeter Ring (Thin accent, NOT solid blinding disc!)
	var led_ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.88
	torus.outer_radius = 3.96
	torus.rings = 32
	torus.ring_segments = 8
	led_ring.mesh = torus
	led_ring.position.y = 0.085
	var mat_led := StandardMaterial3D.new()
	mat_led.albedo_color = Color(0.1, 0.5, 0.8)
	mat_led.emission_enabled = true
	mat_led.emission = Color(0.2, 0.75, 1.0)
	mat_led.emission_energy_multiplier = 0.4
	led_ring.material_override = mat_led
	turntable_node.add_child(led_ring)


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

		# Armored Core stance - now uses MechaScaleSystem.HANGAR_POSE (newest, replaces legacy 1.6*1.68 hardcodes)
	var pose: Dictionary = MechaScaleSystem.HANGAR_POSE
	if body:
		body.rotation = Vector3(-deg_to_rad(4.0), 0.0, 0.0)
		body.position = pose["body_pos"]
	if head:
		head.rotation = Vector3(-deg_to_rad(2.0), 0.0, 0.0)
		head.position = pose["head_pos"]
	if leg_left:
		leg_left.position = pose["leg_left_pos"]
		leg_left.rotation = Vector3(deg_to_rad(8.0), deg_to_rad(14.0), -deg_to_rad(14.0))
	if leg_right:
		leg_right.position = pose["leg_right_pos"]
		leg_right.rotation = Vector3(deg_to_rad(8.0), -deg_to_rad(14.0), deg_to_rad(14.0))
	if shin_left:
		shin_left.position = pose["shin_pos"]
		shin_left.rotation = Vector3(-deg_to_rad(18.0), 0.0, deg_to_rad(8.0))
	if shin_right:
		shin_right.position = pose["shin_pos"]
		shin_right.rotation = Vector3(-deg_to_rad(18.0), 0.0, -deg_to_rad(8.0))
	if arm_left:
		arm_left.position = pose["arm_left_pos"]
		arm_left.rotation = Vector3(deg_to_rad(12.0), deg_to_rad(6.0), -deg_to_rad(28.0))
	if forearm_left:
		forearm_left.position = pose["forearm_pos"]
		forearm_left.rotation = Vector3(deg_to_rad(28.0), 0.0, deg_to_rad(14.0))
	if arm_right:
		arm_right.position = pose["arm_right_pos"]
		arm_right.rotation = Vector3(deg_to_rad(14.0), -deg_to_rad(6.0), deg_to_rad(28.0))
	if forearm_right:
		forearm_right.position = pose["forearm_pos"]
		forearm_right.rotation = Vector3(deg_to_rad(30.0), 0.0, -deg_to_rad(14.0))


# --- 3D CAMERA & MOUSE DRAG PROCESS ---

# Called every frame by the controller's _process: smooth camera follow + the
# selection-tab blink pulse.
func process(delta: float) -> void:
	current_cam_pos = current_cam_pos.lerp(cam_target_pos, 5.0 * delta)
	current_look_pos = current_look_pos.lerp(cam_look_target, 5.0 * delta)
	if garage_cam and is_instance_valid(garage_cam):
		garage_cam.global_position = current_cam_pos
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
	if slot == "backpack":
		slot = "weapon_carry"
	elif slot == "legs":
		slot = "leg_left"

	# Use MechaScaleSystem.HANGAR_CAM (newest) — replaces legacy 5.8-6.4m hardcodes
	var cam: Dictionary = MechaScaleSystem.HANGAR_CAM.get(slot, {})
	if cam.is_empty() and slot.begins_with("weapon"):
		cam = MechaScaleSystem.HANGAR_CAM.get(slot.get_slice("_", 0), MechaScaleSystem.HANGAR_CAM["default"])
	if cam.is_empty():
		cam = MechaScaleSystem.HANGAR_CAM["default"]
	# Handle arm/weapon aliases
	if slot in ["arm_left", "weapon_left"] and MechaScaleSystem.HANGAR_CAM.has("arm_left"):
		cam = MechaScaleSystem.HANGAR_CAM["arm_left"]
	elif slot in ["arm_right", "weapon_right"] and MechaScaleSystem.HANGAR_CAM.has("arm_right"):
		cam = MechaScaleSystem.HANGAR_CAM["arm_right"]
	var local_pos: Vector3 = cam.get("pos", MechaScaleSystem.HANGAR_CAM["default"]["pos"])
	var local_look: Vector3 = cam.get("look", MechaScaleSystem.HANGAR_CAM["default"]["look"])

	if is_realtime_world and realtime_target_mecha != null and is_instance_valid(realtime_target_mecha):
		var m_trans: Transform3D = realtime_target_mecha.global_transform
		cam_target_pos = m_trans * local_pos
		cam_look_target = m_trans * local_look
	else:
		cam_target_pos = local_pos
		cam_look_target = local_look


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
			if body_node: body_node.scale = Vector3(1.4, 1.10, 1.35) # Y 1.25->1.10 keeps height 5.20m within 5.5 (was 5.56)
			if arm_left: arm_left.scale = Vector3(1.35, 1.15, 1.35)
			if arm_right: arm_right.scale = Vector3(1.35, 1.15, 1.35)
			if leg_left: leg_left.scale = Vector3(1.25, 1.05, 1.25)
			if leg_right: leg_right.scale = Vector3(1.25, 1.05, 1.25)
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
	if slot.begins_with("weapon") or slot.begins_with("shoulder"):
		preview_weapon_on_hand(slot, info)
		return
	var mecha = get_mecha_base()
	var pmm = get_part_mesh_manager()
	if pmm:
		var part: ArmorPart = pmm.build_part_for_slot(info)
		pmm.initialize_slot(slot, part)
		if mecha:
			update_weapon_preview(mecha)



# Returns the mech's root Node3D (MechaBase if present, else the whole scene).
func get_mecha_base() -> Node3D:
	if is_realtime_world and realtime_target_mecha != null and is_instance_valid(realtime_target_mecha):
		return realtime_target_mecha
	if mecha_3d_root == null:
		return null
	return mecha_3d_root.get_node_or_null("MechaBase") if mecha_3d_root.has_node("MechaBase") else mecha_3d_root


# Returns the PartMeshManager attached to the mech base, or null.
func get_part_mesh_manager() -> Node:
	var mecha = get_mecha_base()
	return mecha.get_node_or_null("PartMeshManager") if mecha else null


# Returns the MechaAnimation node attached to the mech base, or null.
func get_mecha_animation() -> Node:
	var mecha = get_mecha_base()
	return mecha.get_node_or_null("MechaAnimation") if mecha else null


# Shows a selected weapon on the matching hand/shoulder (or on the back for carry) as a
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
	elif slot.begins_with("shoulder"):
		var side = "left" if slot == "shoulder_left" else "right"
		WeaponVisualFactory.mount_shoulder(mecha, side, weapon, "WeaponVisual_shoulder_" + side)
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
	var active_mech: Dictionary = HangarManager.get_active_mech() if (ClassDB.class_exists("HangarManager") or ResourceLoader.exists("res://scripts/systems/hangar_manager.gd")) else {}
	var has_pilot: bool = active_mech is Dictionary and str(active_mech.get("pilot", "")) != ""
	if pmm.has_method("set_cockpit_pilot_seated"):
		pmm.set_cockpit_pilot_seated(has_pilot)
	if pmm.has_method("set_cockpit_open"):
		if not has_pilot:
			pmm.set_cockpit_open(true, false)

	var attachment_manager = mecha.get_node_or_null("AttachmentManager") if mecha else null
	if attachment_manager:
		attachment_manager.rebuild_from_global_data()

	update_weapon_preview(mecha)


# Shows the equipped weapons on the mech's hands, shoulders, and back in the 3D garage.
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

	# Shoulder weapons
	for side in ["left", "right"]:
		var sh_weapon = LoadoutSystem.get_equipped_shoulder(side)
		WeaponVisualFactory.mount_shoulder(mecha, side, sh_weapon, "WeaponVisual_shoulder_" + side)

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
	apply_armor_preview(slot, info)



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
