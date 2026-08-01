extends Node3D

## 3D Hangar Garage Controller (Gundam Barbatos / Vidar Style)
## - Core Power comes from the Inner Frame (Alaya-Vijnana Skeleton) which can be upgraded with Reactor Levels.
## - Outer Armor Plating allows visual freedom & scavenged enemy armor patching (Zaku Green, Tank Grey, Crimson Ace).
## - Live 3D Viewport Turntable renders mix-and-matched scavenger armor colors over the dark Gundam Inner Frame!

const COST_PER_HP: float = 0.5

var root_control: Control
var _bg_color: Color = Color(0.08, 0.08, 0.12, 0.85)
var _accent_color: Color = Color(0.3, 0.6, 1.0, 1.0)
var _highlight_color: Color = Color(1.0, 0.9, 0.3, 1.0)
var _dim_color: Color = Color(0.5, 0.5, 0.5, 1.0)
var current_mode: String = "armor" # "armor", "frame", "chassis", "upgrade"
var selected_slot: String = "head"
var selected_part_path: String = ""
var selected_salvage_info: Dictionary = {}
var selected_frame_info: Dictionary = {}
var selected_chassis_key: String = "standard"
var _last_selected_item_index: int = -1
var _is_dragging_3d: bool = false

# 3D Garage Nodes
var viewport_container: SubViewportContainer
var sub_viewport: SubViewport
var hangar_env_node: Node3D
var garage_cam: Camera3D
var mecha_3d_root: Node3D
var turntable_node: Node3D
var cam_target_pos: Vector3 = Vector3(2.8, 2.2, 3.8)
var cam_look_target: Vector3 = Vector3(0, 1.8, 0)
var current_cam_pos: Vector3 = Vector3(2.8, 2.2, 3.8)
var current_look_pos: Vector3 = Vector3(0, 1.8, 0)

# UI Nodes
var tab_container: HBoxContainer
var sub_toggle_container: HBoxContainer
var part_item_list: ItemList
var stats_label: Label
var total_stats_label: Label
var weight_bar: ProgressBar
var equip_button: Button
var frame_upgrade_button: Button
var repair_part_button: Button
var full_repair_button: Button
var close_button: Button
var status_message_label: Label

# Inner Frame Catalog
var frame_catalog: Dictionary = {
	"head": [
		{"name": "Alaya-Vijnana Head Skeleton", "hp": 25.0, "weight": 2.0, "type": "Gundam Frame"},
		{"name": "Reinforced Sensor Joint Frame", "hp": 35.0, "weight": 3.5, "type": "Medium Frame"},
		{"name": "Titan Heavy Structure Head Frame", "hp": 50.0, "weight": 5.5, "type": "Heavy Frame"}
	],
	"body": [
		{"name": "Alaya-Vijnana Core Spine", "hp": 50.0, "weight": 6.0, "type": "Gundam Frame"},
		{"name": "Reinforced Composite Torso Frame", "hp": 75.0, "weight": 10.0, "type": "Medium Frame"},
		{"name": "Fortress Heavy Structural Spine", "hp": 110.0, "weight": 16.0, "type": "Heavy Frame"}
	],
	"arm_left": [
		{"name": "Alaya-Vijnana Arm Joint (L)", "hp": 20.0, "weight": 3.0, "type": "Gundam Frame"},
		{"name": "High-Torque Hydraulic Arm Frame (L)", "hp": 32.0, "weight": 5.0, "type": "Medium Frame"},
		{"name": "Heavy Reinforced Siege Arm Frame (L)", "hp": 48.0, "weight": 8.0, "type": "Heavy Frame"}
	],
	"arm_right": [
		{"name": "Alaya-Vijnana Arm Joint (R)", "hp": 20.0, "weight": 3.0, "type": "Gundam Frame"},
		{"name": "High-Torque Hydraulic Arm Frame (R)", "hp": 32.0, "weight": 5.0, "type": "Medium Frame"},
		{"name": "Heavy Reinforced Siege Arm Frame (R)", "hp": 48.0, "weight": 8.0, "type": "Heavy Frame"}
	],
	"leg_left": [
		{"name": "Alaya-Vijnana Leg Actuator (L)", "hp": 25.0, "weight": 4.0, "type": "Gundam Frame"},
		{"name": "Roller Suspension Leg Frame (L)", "hp": 40.0, "weight": 6.5, "type": "High-Mobility"},
		{"name": "Heavy Hydraulic Titan Leg Frame (L)", "hp": 60.0, "weight": 10.0, "type": "Heavy Frame"}
	],
	"leg_right": [
		{"name": "Alaya-Vijnana Leg Actuator (R)", "hp": 25.0, "weight": 4.0, "type": "Gundam Frame"},
		{"name": "Roller Suspension Leg Frame (R)", "hp": 40.0, "weight": 6.5, "type": "High-Mobility"},
		{"name": "Heavy Hydraulic Titan Leg Frame (R)", "hp": 60.0, "weight": 10.0, "type": "Heavy Frame"}
	]
}

# Outer Armor Catalog
var armor_catalog: Dictionary = {
	"head": [
		{"name": "Barbatos White Visor Plating", "path": "res://resources/mech/stock/head_standard.tres", "hp": 30.0, "armor": 20.0, "weight": 4.0, "color": Color(0.9, 0.9, 0.95), "type": "Standard Armor"},
		{"name": "Vanguard Light Recon Helmet", "path": "res://resources/mech/stock/head_standard.tres", "hp": 20.0, "armor": 12.0, "weight": 2.0, "color": Color(0.8, 0.85, 0.9), "type": "Light Plating"}
	],
	"body": [
		{"name": "Barbatos Chest Armor Plate", "path": "res://resources/mech/stock/torso_standard.tres", "hp": 60.0, "armor": 40.0, "weight": 14.0, "color": Color(0.9, 0.9, 0.95), "type": "Standard Armor"},
		{"name": "Fortress Heavy Reactive Chestplate", "path": "res://resources/mech/stock/torso_standard.tres", "hp": 110.0, "armor": 75.0, "weight": 24.0, "color": Color(0.25, 0.2, 0.35), "type": "Heavy Armor"}
	],
	"arm_left": [
		{"name": "Barbatos Left Shoulder Guard", "path": "res://resources/mech/stock/arm_left_standard.tres", "hp": 25.0, "armor": 15.0, "weight": 6.0, "color": Color(0.9, 0.9, 0.95), "type": "Standard Armor"}
	],
	"arm_right": [
		{"name": "Barbatos Right Shoulder Guard", "path": "res://resources/mech/stock/arm_right_standard.tres", "hp": 25.0, "armor": 15.0, "weight": 6.0, "color": Color(0.9, 0.9, 0.95), "type": "Standard Armor"}
	],
	"leg_left": [
		{"name": "Barbatos Left Leg Armor", "path": "res://resources/mech/stock/leg_left_standard.tres", "hp": 30.0, "armor": 20.0, "weight": 8.0, "color": Color(0.9, 0.9, 0.95), "type": "Standard Armor"}
	],
	"leg_right": [
		{"name": "Barbatos Right Leg Armor", "path": "res://resources/mech/stock/leg_right_standard.tres", "hp": 30.0, "armor": 20.0, "weight": 8.0, "color": Color(0.9, 0.9, 0.95), "type": "Standard Armor"}
	],
	"weapon_right": [
		{"name": "Beam Carbine", "path": "res://resources/mech/stock/weapon_beam_carbine.tres", "hp": 0.0, "armor": 0.0, "weight": 7.0, "type": "Beam Weapon"},
		{"name": "Heavy Machine Gun", "path": "res://resources/mech/stock/weapon_heavy_machine_gun.tres", "hp": 0.0, "armor": 0.0, "weight": 9.0, "type": "Kinetic Weapon"},
		{"name": "Combat Shotgun", "path": "res://resources/mech/stock/weapon_combat_shotgun.tres", "hp": 0.0, "armor": 0.0, "weight": 8.0, "type": "Shotgun"}
	],
	"weapon_left": [
		{"name": "Heat Blade", "path": "res://resources/mech/stock/weapon_heat_blade.tres", "hp": 0.0, "armor": 0.0, "weight": 5.0, "type": "Melee Weapon"},
		{"name": "Pile Bunker", "path": "res://resources/mech/stock/weapon_pile_bunker.tres", "hp": 0.0, "armor": 0.0, "weight": 11.0, "type": "Melee Weapon"}
	]
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_3d_garage()
	_build_ui_layout()
	show_hangar()
	if has_node("/root/AudioManager"):
		AudioManager.play_hangar_music()


# --- 3D GARAGE ENVIRONMENT ---
func _build_3d_garage() -> void:
	viewport_container = SubViewportContainer.new()
	viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	add_child(viewport_container)

	sub_viewport = SubViewport.new()
	sub_viewport.size = Vector2i(1280, 720)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
	cyl.top_radius = 3.2
	cyl.bottom_radius = 3.5
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
	spot.look_at(Vector3(0, 1.8, 0), Vector3.UP)
	spot.light_energy = 4.0
	spot.spot_range = 20.0
	spot.spot_angle = 45.0
	spot.light_color = Color(0.9, 0.95, 1.0)

	var rim = SpotLight3D.new()
	rim.position = Vector3(-4, 5, -4)
	hangar_env_node.add_child(rim)
	rim.look_at(Vector3(0, 1.5, 0), Vector3.UP)
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
	_apply_tactical_idle_pose(scene_base)
	mecha_3d_root.add_child(scene_base)

	# Camera
	garage_cam = Camera3D.new()
	garage_cam.position = current_cam_pos
	hangar_env_node.add_child(garage_cam)
	garage_cam.look_at(current_look_pos, Vector3.UP)
	garage_cam.fov = 55.0


# --- 2D OVERLAY UI ---
func _build_ui_layout() -> void:
	var root = Control.new()
	root.name = "RootControl"
	root_control = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top Header Bar
	var header = PanelContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.custom_minimum_size = Vector2(0, 52)
	root.add_child(header)

	var style_hdr = StyleBoxFlat.new()
	style_hdr.bg_color = Color(0.06, 0.08, 0.12, 0.92)
	header.add_theme_stylebox_override("panel", style_hdr)

	var hdr_box = HBoxContainer.new()
	hdr_box.add_theme_constant_override("separation", 15)
	header.add_child(hdr_box)

	var title_lbl = Label.new()
	title_lbl.text = " 🛠️ 3D MECHA GARAGE "
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	hdr_box.add_child(title_lbl)

	tab_container = HBoxContainer.new()
	tab_container.add_theme_constant_override("separation", 4)
	hdr_box.add_child(tab_container)

	var slots = [
		{"id": "chassis", "label": "🤖 CHASSIS"},
		{"id": "head", "label": "HEAD"},
		{"id": "body", "label": "BODY"},
		{"id": "arm_left", "label": "L.ARM"},
		{"id": "arm_right", "label": "R.ARM"},
		{"id": "leg_left", "label": "L.LEGS"},
		{"id": "leg_right", "label": "R.LEGS"},
		{"id": "weapon_right", "label": "R.WEAPON"},
		{"id": "weapon_left", "label": "L.WEAPON"}
	]

	for slot_info in slots:
		var btn = Button.new()
		btn.text = slot_info["label"]
		btn.custom_minimum_size = Vector2(80, 36)
		btn.pressed.connect(func(): _select_slot_tab(slot_info["id"]))
		tab_container.add_child(btn)

	# Sub-Toggle Bar for Armor Plating vs Inner Skeleton Frame vs Power Upgrade
	sub_toggle_container = HBoxContainer.new()
	sub_toggle_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub_toggle_container.offset_top = 58
	sub_toggle_container.add_theme_constant_override("separation", 8)
	root.add_child(sub_toggle_container)

	var btn_armor = Button.new()
	btn_armor.text = "🛡️ OUTER ARMOR (SCAVENGER)"
	btn_armor.custom_minimum_size = Vector2(170, 32)
	btn_armor.pressed.connect(func(): _switch_custom_mode("armor"))
	sub_toggle_container.add_child(btn_armor)

	var btn_frame = Button.new()
	btn_frame.text = "⚙️ INNER SKELETON FRAME"
	btn_frame.custom_minimum_size = Vector2(170, 32)
	btn_frame.pressed.connect(func(): _switch_custom_mode("frame"))
	sub_toggle_container.add_child(btn_frame)

	frame_upgrade_button = Button.new()
	frame_upgrade_button.text = "⚡ REACTOR POWER UPGRADE"
	frame_upgrade_button.custom_minimum_size = Vector2(180, 32)
	frame_upgrade_button.pressed.connect(func(): _switch_custom_mode("upgrade"))
	sub_toggle_container.add_child(frame_upgrade_button)

	# Left Sidebar (Part Catalog List & Salvaged Drops)
	var left_panel = PanelContainer.new()
	left_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_panel.offset_top = 96
	left_panel.offset_bottom = -20
	left_panel.offset_left = 20
	left_panel.custom_minimum_size = Vector2(330, 0)
	root.add_child(left_panel)

	var style_left = StyleBoxFlat.new()
	style_left.bg_color = Color(0.08, 0.1, 0.15, 0.88)
	style_left.corner_radius_top_left = 8
	style_left.corner_radius_bottom_left = 8
	style_left.content_margin_left = 12
	style_left.content_margin_right = 12
	style_left.content_margin_top = 12
	style_left.content_margin_bottom = 12
	left_panel.add_theme_stylebox_override("panel", style_left)

	var left_box = VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 10)
	left_panel.add_child(left_box)

	var list_title = Label.new()
	list_title.text = "SCAVENGER INVENTORY & CATALOG"
	list_title.add_theme_font_size_override("font_size", 14)
	list_title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	left_box.add_child(list_title)

	part_item_list = ItemList.new()
	part_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	part_item_list.item_selected.connect(_on_part_item_selected)
	part_item_list.item_clicked.connect(_on_part_item_clicked)
	left_box.add_child(part_item_list)

	equip_button = Button.new()
	equip_button.text = "EQUIP SELECTION"
	equip_button.custom_minimum_size = Vector2(0, 42)
	equip_button.pressed.connect(_on_equip_pressed)
	left_box.add_child(equip_button)

	# Right Sidebar (Stats & Gundam Frame Core Power Panel)
	var right_panel = PanelContainer.new()
	right_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_panel.offset_top = 96
	right_panel.offset_bottom = -20
	right_panel.offset_right = -20
	right_panel.custom_minimum_size = Vector2(350, 0)
	root.add_child(right_panel)

	var style_right = StyleBoxFlat.new()
	style_right.bg_color = Color(0.08, 0.1, 0.15, 0.88)
	style_right.corner_radius_top_right = 8
	style_right.corner_radius_bottom_right = 8
	style_right.content_margin_left = 14
	style_right.content_margin_right = 14
	style_right.content_margin_top = 14
	style_right.content_margin_bottom = 14
	right_panel.add_theme_stylebox_override("panel", style_right)

	var right_box = VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 10)
	right_panel.add_child(right_box)

	var stats_title = Label.new()
	stats_title.text = "GUNDAM FRAME CORE SPECIFICATIONS"
	stats_title.add_theme_font_size_override("font_size", 14)
	stats_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	right_box.add_child(stats_title)

	stats_label = Label.new()
	stats_label.text = "Select a chassis, frame, or armor to view specifications"
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_box.add_child(stats_label)

	var sep = HSeparator.new()
	right_box.add_child(sep)

	var total_title = Label.new()
	total_title.text = "FRAME VS. ARMOR DUAL CAPACITY"
	total_title.add_theme_font_size_override("font_size", 13)
	right_box.add_child(total_title)

	weight_bar = ProgressBar.new()
	weight_bar.custom_minimum_size = Vector2(0, 22)
	weight_bar.max_value = 85.0
	right_box.add_child(weight_bar)

	total_stats_label = Label.new()
	total_stats_label.text = "FRAME HP: 150 | ARMOR HP: 210\nTOTAL WEIGHT: 42.0 / 75.0 kg"
	right_box.add_child(total_stats_label)

	var sep2 = HSeparator.new()
	right_box.add_child(sep2)

	repair_part_button = Button.new()
	repair_part_button.text = "Repair Selected Slot"
	repair_part_button.pressed.connect(_on_repair_part_pressed)
	right_box.add_child(repair_part_button)

	full_repair_button = Button.new()
	full_repair_button.text = "Full Field Repair"
	full_repair_button.pressed.connect(_on_full_repair_pressed)
	right_box.add_child(full_repair_button)

	status_message_label = Label.new()
	status_message_label.text = ""
	status_message_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	right_box.add_child(status_message_label)

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_child(spacer)

	close_button = Button.new()
	close_button.text = "EXIT HANGAR"
	close_button.custom_minimum_size = Vector2(0, 44)
	close_button.pressed.connect(_on_close_pressed)
	right_box.add_child(close_button)


# --- 3D CAMERA & MOUSE DRAG PROCESS ---
func _process(delta: float) -> void:
	if not visible:
		return

	current_cam_pos = current_cam_pos.lerp(cam_target_pos, 5.0 * delta)
	current_look_pos = current_look_pos.lerp(cam_look_target, 5.0 * delta)
	if garage_cam:
		garage_cam.position = current_cam_pos
		garage_cam.look_at(current_look_pos, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging_3d = event.pressed
	elif event is InputEventMouseMotion and _is_dragging_3d:
		if turntable_node:
			turntable_node.rotate_y(event.relative.x * 0.008)


# --- ARMORED CORE / 30MM TACTICAL COMBAT IDLE POSE ---
func _apply_tactical_idle_pose(mecha_node: Node3D) -> void:
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

	# Armored Core / 30MM Low-Slung Tactical Combat Idle Stance
	if body:
		body.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
		body.position.y = 1.72

	if head:
		head.rotation_degrees = Vector3(4.0, 0.0, 0.0)
		head.position.y = 2.45

	if leg_left:
		leg_left.rotation_degrees = Vector3(14.0, -12.0, 6.0)
	if leg_right:
		leg_right.rotation_degrees = Vector3(14.0, 12.0, -6.0)

	if shin_left:
		shin_left.rotation_degrees = Vector3(-28.0, 0.0, 0.0)
	if shin_right:
		shin_right.rotation_degrees = Vector3(-28.0, 0.0, 0.0)

	if arm_left:
		arm_left.rotation_degrees = Vector3(10.0, 8.0, -6.0)
	if forearm_left:
		forearm_left.rotation_degrees = Vector3(42.0, 0.0, 0.0)

	if arm_right:
		arm_right.rotation_degrees = Vector3(12.0, -8.0, 6.0)
	if forearm_right:
		forearm_right.rotation_degrees = Vector3(45.0, 0.0, 0.0)


func _on_close_pressed() -> void:
	_check_combat_readiness_warning(func():
		visible = false
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		GlobalData.save_run()
		if GameManager and GameManager.has_method("return_to_board"):
			GameManager.return_to_board()
		else:
			EventBus.game_state_changed.emit("HANGAR", "INTERMISSION")
	)


func _check_combat_readiness_warning(on_confirm: Callable) -> void:
	var has_legs = GlobalData.equipped_parts.has("leg_left") or GlobalData.equipped_parts.has("leg_right")
	var has_body = GlobalData.equipped_parts.has("body")
	
	if has_legs and has_body:
		on_confirm.call()
		return
		
	var old = get_node_or_null("CombatWarningModal")
	if old: old.queue_free()
	
	var modal = PanelContainer.new()
	modal.name = "CombatWarningModal"
	modal.anchor_left = 0.5
	modal.anchor_right = 0.5
	modal.anchor_top = 0.5
	modal.anchor_bottom = 0.5
	modal.offset_left = -240
	modal.offset_right = 240
	modal.offset_top = -140
	modal.offset_bottom = 140

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.08, 0.08, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 0.4, 0.2)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	modal.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	modal.add_child(vbox)

	var title = Label.new()
	title.text = "⚠️ WARNING: INCOMPLETE MECH ASSEMBLY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
	vbox.add_child(title)

	var msg = Label.new()
	msg.text = "คำเตือน: หุ่นของคุณประกอบไม่ครบชุด (ไม่มีขา/เกราะไม่ครบ)!\nอาจทำให้เคลื่อนที่และต่อสู้ในด่านได้ยากลำบาก\n\n(คุณยังคงเข้าเล่นด่านได้ แล้วแต่ศรัทธา - รองรับ Hover ในอนาคต)"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(msg)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 15)
	vbox.add_child(hbox)

	var launch_btn = Button.new()
	launch_btn.text = "LAUNCH ANYWAY (ลุยเลย)"
	launch_btn.custom_minimum_size = Vector2(140, 36)
	launch_btn.pressed.connect(func():
		modal.queue_free()
		on_confirm.call()
	)
	hbox.add_child(launch_btn)

	var back_btn = Button.new()
	back_btn.text = "BACK TO HANGAR (แต่งหุ่นต่อ)"
	back_btn.custom_minimum_size = Vector2(150, 36)
	back_btn.pressed.connect(func(): modal.queue_free())
	hbox.add_child(back_btn)

	root_control.add_child(modal)


func show_hangar() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_total_stats()
	_populate_part_list_for_slot(selected_slot)
	AudioManager.play_hangar_music()
	call_deferred("_update_all_3d_slots_preview")
	_select_slot_tab("chassis")
	_update_total_stats()


func _switch_custom_mode(mode: String) -> void:
	current_mode = mode
	if selected_slot == "chassis":
		return
	_populate_part_list_for_slot(selected_slot)


func _select_slot_tab(slot: String) -> void:
	selected_slot = slot
	sub_toggle_container.visible = (slot != "chassis" and not slot.begins_with("weapon"))
	_update_camera_focus_for_slot(slot)
	_populate_part_list_for_slot(slot)
	_update_total_stats()


func _update_camera_focus_for_slot(slot: String) -> void:
	match slot:
		"chassis":
			cam_target_pos = Vector3(3.5, 2.2, 4.5)
			cam_look_target = Vector3(0, 1.8, 0)
		"head":
			cam_target_pos = Vector3(1.4, 2.6, 2.0)
			cam_look_target = Vector3(0, 2.5, 0)
		"body":
			cam_target_pos = Vector3(2.2, 2.0, 2.8)
			cam_look_target = Vector3(0, 2.0, 0)
		"arm_left", "arm_right", "weapon_left", "weapon_right":
			cam_target_pos = Vector3(2.5, 1.8, 2.2)
			cam_look_target = Vector3(0, 1.8, 0)
		"leg_left", "leg_right":
			cam_target_pos = Vector3(2.8, 1.0, 2.8)
			cam_look_target = Vector3(0, 0.8, 0)
		_:
			cam_target_pos = Vector3(3.2, 2.0, 4.0)
			cam_look_target = Vector3(0, 1.8, 0)


func _is_item_equipped(slot: String, info: Dictionary) -> bool:
	if info.is_empty():
		return false

	GlobalData.ensure_default_equipped_parts()

	if current_mode == "frame":
		var cur_frame = GlobalData.equipped_frames.get(slot, {})
		if cur_frame is Dictionary and not cur_frame.is_empty():
			var name_a = cur_frame.get("name", cur_frame.get("part_name", "")).to_lower()
			var name_b = info.get("name", info.get("part_name", "")).to_lower()
			if name_a != "" and name_b != "":
				return name_a == name_b or name_a.contains(name_b) or name_b.contains(name_a)
		return false
	else:
		var cur_armor = GlobalData.equipped_parts.get(slot)
		if cur_armor == null:
			return false

		var info_name = info.get("name", info.get("part_name", "")).to_lower()
		var info_path = info.get("path", "")

		if cur_armor is Resource:
			if info_path != "" and "resource_path" in cur_armor and cur_armor.resource_path == info_path:
				return true
			if "part_name" in cur_armor:
				var p_name = cur_armor.part_name.to_lower()
				if p_name != "" and info_name != "":
					if p_name == info_name or info_name.contains(p_name) or p_name.contains(info_name):
						return true
		elif cur_armor is Dictionary:
			var cur_name = cur_armor.get("name", cur_armor.get("part_name", "")).to_lower()
			var cur_path = cur_armor.get("path", "")
			if info_path != "" and cur_path != "" and cur_path == info_path:
				return true
			if cur_name != "" and info_name != "":
				if cur_name == info_name or info_name.contains(cur_name) or cur_name.contains(info_name):
					return true
			return cur_armor == info
		return false


func _populate_part_list_for_slot(slot: String) -> void:
	_close_part_action_modal()
	part_item_list.clear()
	_last_selected_item_index = -1

	if current_mode == "upgrade":
		var cost_cr = GlobalData.frame_upgrade_level * 150
		var cost_cores = GlobalData.frame_upgrade_level
		part_item_list.add_item("Upgrade Inner Frame to Level %d (%d cr, %d cores)" % [
			GlobalData.frame_upgrade_level + 1, cost_cr, cost_cores
		])
		if part_item_list.item_count > 0:
			part_item_list.select(0)
			_last_selected_item_index = 0
			_on_part_item_selected(0)
		return

	if slot == "chassis":
		for key in GlobalData.chassis_catalog:
			var info = GlobalData.chassis_catalog[key]
			var label_str = "%s [Limit: %.0fkg]" % [info["name"], info["max_weight"]]
			part_item_list.add_item(label_str)
		if GlobalData.chassis_catalog.size() > 0:
			part_item_list.select(0)
			_last_selected_item_index = 0
			_on_part_item_selected(0)
		return

	if current_mode == "frame" and frame_catalog.has(slot):
		var items = frame_catalog[slot]
		for info in items:
			var is_eq = _is_item_equipped(slot, info)
			var prefix = "[E] " if is_eq else "     "
			var fname = info.get("name", "Frame Part")
			var fhp = info.get("hp", 20.0)
			var fwt = info.get("weight", 3.0)
			var label_str = "%s%s (HP: %.0f, %.1fkg)" % [prefix, fname, fhp, fwt]
			part_item_list.add_item(label_str)
		if items.size() > 0:
			part_item_list.select(0)
			_last_selected_item_index = 0
			_on_part_item_selected(0)
	elif armor_catalog.has(slot):
		# Show stock armor
		var items = armor_catalog[slot]
		for info in items:
			var is_eq = _is_item_equipped(slot, info)
			var prefix = "[E] " if is_eq else "     "
			var label_str = "%s%s [%s]" % [prefix, info["name"], info["type"]]
			if info.get("weight", 0.0) > 0:
				label_str += " - %.1fkg" % info["weight"]
			part_item_list.add_item(label_str)

		# Show salvaged enemy drops
		for salvaged in GlobalData.salvaged_armor_inventory:
			if salvaged.get("slot", "") == slot:
				var is_eq = _is_item_equipped(slot, salvaged)
				var prefix = "[E] " if is_eq else "     "
				var drop_label = "%sSALVAGED: %s [%s]" % [prefix, salvaged["name"], salvaged.get("type", "Enemy")]
				part_item_list.add_item(drop_label)

		if part_item_list.item_count > 0:
			part_item_list.select(0)
			_last_selected_item_index = 0
			_on_part_item_selected(0)


func _on_part_item_selected(index: int) -> void:
	if current_mode == "upgrade":
		var cost_cr = GlobalData.frame_upgrade_level * 150
		var cost_cores = GlobalData.frame_upgrade_level
		stats_label.text = "INNER FRAME REACTOR LEVEL: %d -> %d\n\nEFFECTS:\n+25 FRAME HP per slot\n+15.0 kg MAX WEIGHT CAPACITY\n+1.5 m/s DASH THRUST SPEED\n\nUPGRADE COST: %d Credits, %d Data Cores" % [
			GlobalData.frame_upgrade_level, GlobalData.frame_upgrade_level + 1, cost_cr, cost_cores
		]
		selected_salvage_info.clear()
		return

	if current_mode == "chassis":
		var keys = GlobalData.chassis_catalog.keys()
		if index < 0 or index >= keys.size(): return
		selected_chassis_key = keys[index]
		var info = GlobalData.chassis_catalog[selected_chassis_key]
		stats_label.text = "MODEL: %s\n\nSPEED BOOST: %.1f m/s\nMAX LOAD CAPACITY: %.1f kg\nSTRUCTURE RATING: Military Grade" % [
			info.get("name", "Chassis"), info.get("speed", 10.0), info.get("max_weight", 100.0)
		]
		_apply_3d_chassis_preview(info)
		return

	if current_mode == "frame" and frame_catalog.has(selected_slot):
		var frame_items = frame_catalog[selected_slot]
		if index >= 0 and index < frame_items.size():
			selected_frame_info = frame_items[index]
			selected_part_path = ""
			selected_salvage_info.clear()

			var fname = selected_frame_info.get("name", selected_frame_info.get("part_name", "Inner Frame"))
			var fhp = selected_frame_info.get("hp", selected_frame_info.get("max_hp", 25.0))
			var fwt = selected_frame_info.get("weight", 3.0)
			stats_label.text = "INNER FRAME PART: %s\n\nFRAME HP: %.0f\nFRAME WEIGHT: %.1f kg" % [
				fname, fhp, fwt
			]
			_apply_3d_frame_preview(selected_slot, selected_frame_info)
		_update_total_stats()
		return

	if armor_catalog.has(selected_slot):
		var stock_items = armor_catalog[selected_slot]
		var selected_info: Dictionary = {}
		if index >= 0 and index < stock_items.size():
			selected_info = stock_items[index]
			selected_part_path = selected_info.get("path", "")
			selected_frame_info.clear()
			selected_salvage_info.clear()

			var item_name = selected_info.get("name", selected_info.get("part_name", "Armor Part"))
			var item_type = selected_info.get("type", "Standard")
			var item_hp = selected_info.get("hp", selected_info.get("durability", selected_info.get("max_hp", 30.0)))
			var item_armor = selected_info.get("armor", selected_info.get("armor_class", 15.0))
			var item_weight = selected_info.get("weight", 4.0)

			if selected_slot.begins_with("weapon"):
				stats_label.text = "WEAPON: %s\nTYPE: %s\n\nWEIGHT: %.1f kg\nPOWER OUTPUT: Heavy" % [
					item_name, item_type, item_weight
				]
			else:
				stats_label.text = "OUTER ARMOR: %s\nTYPE: %s\n\nARMOR HP: %.0f\nARMOR CLASS: %.0f\nARMOR WEIGHT: %.1f kg" % [
					item_name, item_type, item_hp, item_armor, item_weight
				]
			_apply_3d_armor_preview(selected_slot, selected_info)
		elif index - stock_items.size() >= 0 and index - stock_items.size() < GlobalData.salvaged_armor_inventory.size():
			var salvaged_idx = index - stock_items.size()
			selected_salvage_info = GlobalData.salvaged_armor_inventory[salvaged_idx]
			selected_part_path = ""
			selected_frame_info.clear()

			var item_name = selected_salvage_info.get("name", selected_salvage_info.get("part_name", "Salvaged Armor"))
			var item_type = selected_salvage_info.get("type", "Enemy")
			var item_hp = selected_salvage_info.get("hp", selected_salvage_info.get("max_hp", 30.0))
			var item_armor = selected_salvage_info.get("armor", 15.0)
			var item_weight = selected_salvage_info.get("weight", 4.0)

			stats_label.text = "SALVAGED ENEMY ARMOR: %s\nTYPE: %s\n\nARMOR HP: %.0f\nARMOR CLASS: %.0f\nARMOR WEIGHT: %.1f kg" % [
				item_name, item_type, item_hp, item_armor, item_weight
			]
			_apply_3d_salvage_preview(selected_slot, selected_salvage_info)
	_update_total_stats()


func _on_part_item_clicked(index: int, _at_position: Vector2 = Vector2.ZERO, _mouse_button_index: int = 1) -> void:
	if index != _last_selected_item_index:
		# FIRST CLICK ON ITEM: Highlight item, update 3D preview & stats text real-time!
		_last_selected_item_index = index
		_on_part_item_selected(index)
		_close_part_action_modal()
	else:
		# SECOND CLICK (CLICK AGAIN ON HIGHLIGHTED ITEM): Open Action Popup Modal!
		var info_to_show: Dictionary = {}
		if not selected_salvage_info.is_empty():
			info_to_show = selected_salvage_info
		elif not selected_frame_info.is_empty():
			info_to_show = selected_frame_info
		elif current_mode == "frame" and frame_catalog.has(selected_slot):
			var items = frame_catalog[selected_slot]
			if index >= 0 and index < items.size():
				info_to_show = items[index]
		elif armor_catalog.has(selected_slot):
			var stock_items = armor_catalog[selected_slot]
			if index >= 0 and index < stock_items.size():
				info_to_show = stock_items[index]
		if not info_to_show.is_empty():
			_show_part_action_modal(info_to_show)


func _close_part_action_modal() -> void:
	if root_control:
		var old = root_control.get_node_or_null("PartActionModal")
		if old: old.queue_free()
	var local_old = get_node_or_null("PartActionModal")
	if local_old: local_old.queue_free()


func _show_part_action_modal(info: Dictionary) -> void:
	if info.is_empty():
		return
	_close_part_action_modal()

	var modal_panel = PanelContainer.new()
	modal_panel.name = "PartActionModal"
	modal_panel.anchor_left = 0.0
	modal_panel.anchor_right = 0.0
	modal_panel.anchor_top = 0.5
	modal_panel.anchor_bottom = 0.5
	modal_panel.offset_left = 340
	modal_panel.offset_right = 730
	modal_panel.offset_top = -140
	modal_panel.offset_bottom = 140

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = _accent_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	modal_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	modal_panel.add_child(vbox)

	var item_name = info.get("name", info.get("part_name", "PART OPTIONS"))
	var title = Label.new()
	title.text = "ACTION MENU: %s" % item_name.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", _highlight_color)
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	var hp_val = info.get("durability", info.get("hp", info.get("max_hp", 100.0)))
	var max_hp_val = info.get("max_hp", 100.0)
	var wt_val = info.get("weight", 10.0)
	var details = Label.new()
	details.text = "DURABILITY: %.0f / %.0f HP  |  WEIGHT: %.1f kg" % [hp_val, max_hp_val, wt_val]
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	vbox.add_child(details)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	# 1. EQUIP / REMOVE TOGGLE BUTTON
	var is_eq = _is_item_equipped(selected_slot, info)
	var toggle_btn = Button.new()
	if is_eq:
		toggle_btn.text = "[ REMOVE / UNEQUIP ]"
		toggle_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	else:
		toggle_btn.text = "[ EQUIP PART ]"
		toggle_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))

	toggle_btn.custom_minimum_size = Vector2(180, 36)
	toggle_btn.pressed.connect(func():
		if is_eq:
			_unequip_part_from_slot(selected_slot)
		else:
			_equip_part_to_slot(selected_slot, info)
		_close_part_action_modal()
		_populate_part_list_for_slot(selected_slot)
	)
	grid.add_child(toggle_btn)

	# 2. REPAIR
	var repair_btn = Button.new()
	repair_btn.text = "REPAIR (10 cr)"
	repair_btn.custom_minimum_size = Vector2(180, 36)
	repair_btn.pressed.connect(func():
		if GlobalData.credits >= 10:
			GlobalData.credits -= 10
			info["hp"] = info.get("max_hp", 100.0)
			info["durability"] = info.get("max_hp", 100.0)
			GlobalData.part_damage.erase(selected_slot)
			status_message_label.text = "Part Repaired to 100% HP!"
			GlobalData.save_run()
			_update_total_stats()
			_apply_3d_armor_preview(selected_slot, info)
		else:
			status_message_label.text = "Insufficient Credits for repair!"
		_close_part_action_modal()
	)
	grid.add_child(repair_btn)

	# 3. UPGRADE
	var upgrade_btn = Button.new()
	upgrade_btn.text = "UPGRADE (+15 HP)"
	upgrade_btn.custom_minimum_size = Vector2(180, 36)
	upgrade_btn.pressed.connect(func():
		if GlobalData.credits >= 50:
			GlobalData.credits -= 50
			var old_hp = info.get("max_hp", info.get("hp", 30.0))
			info["max_hp"] = old_hp + 15.0
			info["hp"] = info.get("max_hp", 45.0)
			status_message_label.text = "Part Upgraded! Max HP increased to %.0f" % info["max_hp"]
			GlobalData.save_run()
			_update_total_stats()
		else:
			status_message_label.text = "Insufficient Credits for upgrade (50 cr needed)!"
		_close_part_action_modal()
	)
	grid.add_child(upgrade_btn)

	# 4. PAINT
	var paint_btn = Button.new()
	paint_btn.text = "PAINT COLOR"
	paint_btn.custom_minimum_size = Vector2(180, 36)
	paint_btn.pressed.connect(func():
		var palette = [
			Color(0.25, 0.40, 0.60), # Mecha Navy Blue
			Color(0.80, 0.20, 0.20), # Crimson Ace Red
			Color(0.90, 0.90, 0.95), # Gundam White
			Color(0.20, 0.65, 0.35), # Zaku Green
			Color(0.85, 0.70, 0.20), # Gold Trim
			Color(0.20, 0.22, 0.26)  # Dark Steel Frame
		]
		var cur_col = info.get("color", Color(0.25, 0.40, 0.60))
		var next_idx = 0
		for i in range(palette.size()):
			if palette[i].is_equal_approx(cur_col):
				next_idx = (i + 1) % palette.size()
				break
		var new_color = palette[next_idx]
		info["color"] = new_color
		info["part_color"] = new_color
		status_message_label.text = "Armor paint updated!"
		_apply_3d_armor_preview(selected_slot, info)
		if GlobalData.equipped_parts.get(selected_slot) == info or GlobalData.equipped_parts.has(selected_slot):
			GlobalData.equipped_parts[selected_slot]["color"] = new_color
		GlobalData.save_run()
	)
	grid.add_child(paint_btn)

	# 5. CANCEL
	var cancel_btn = Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(370, 32)
	cancel_btn.pressed.connect(func(): _close_part_action_modal())
	vbox.add_child(cancel_btn)

	if root_control:
		root_control.add_child(modal_panel)
	else:
		add_child(modal_panel)


func _equip_part_to_slot(slot: String, info: Dictionary) -> void:
	GlobalData.equipped_parts[slot] = info.duplicate()
	GlobalData.save_run()
	_apply_3d_armor_preview(slot, info)
	_update_total_stats()
	AudioManager.play_ui_confirm()


func _unequip_part_from_slot(slot: String) -> void:
	GlobalData.equipped_parts.erase(slot)
	GlobalData.save_run()
	if mecha_3d_root:
		var mecha = mecha_3d_root.get_node_or_null("MechaBase") if mecha_3d_root.has_node("MechaBase") else mecha_3d_root
		var pmm = mecha.get_node_or_null("PartMeshManager") if mecha else null
		if pmm:
			pmm._show_inner_frame(slot)
	_update_total_stats()
	AudioManager.play_ui_click()

# --- REAL-TIME 3D PREVIEWS IN GARAGE ---
func _apply_3d_chassis_preview(info: Dictionary) -> void:
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

	match selected_chassis_key:
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

	var armor_paths = [
		"MechaBase/Head/HeadMesh", "MechaBase/Body/ChestPlate",
		"MechaBase/ArmLeft/ShoulderLeft", "MechaBase/ArmRight/ShoulderRight",
		"MechaBase/LegLeft/KneeLeft", "MechaBase/LegLeft/FootLeft",
		"MechaBase/LegRight/KneeRight", "MechaBase/LegRight/FootRight"
	]
	for mesh_path in armor_paths:
		var node = mecha_3d_root.get_node_or_null(mesh_path)
		if node:
			node.material_override = mat

	var dark_paths = [
		"MechaBase/Body/BodyMesh", "MechaBase/Body/Backpack",
		"MechaBase/ArmLeft/ArmLeftMesh", "MechaBase/ArmRight/ArmRightMesh",
		"MechaBase/LegLeft/LegLeftMesh", "MechaBase/LegRight/LegRightMesh"
	]
	for mesh_path in dark_paths:
		var node = mecha_3d_root.get_node_or_null(mesh_path)
		if node:
			node.material_override = mat_dark

	var visor_node = mecha_3d_root.get_node_or_null("MechaBase/Head/Visor")
	if visor_node:
		visor_node.material_override = mat_visor


func _apply_3d_frame_preview(slot: String, info: Dictionary) -> void:
	if mecha_3d_root == null: return
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.18)
	mat.metallic = 0.95
	mat.roughness = 0.15
	_set_slot_material(slot, mat)


func _apply_3d_armor_preview(slot: String, info: Dictionary) -> void:
	if mecha_3d_root == null: return
	var mecha = mecha_3d_root.get_node_or_null("MechaBase") if mecha_3d_root.has_node("MechaBase") else mecha_3d_root
	var pmm = mecha.get_node_or_null("PartMeshManager") if mecha else null
	if pmm:
		var part = ArmorPart.new()
		part.part_name = info.get("name", "Spiky Armor")
		part.max_hp = info.get("durability", info.get("max_hp", 100.0))
		if info.has("color"):
			part.part_color = info.get("color")
		pmm.initialize_slot(slot, part)


func _update_all_3d_slots_preview() -> void:
	if mecha_3d_root == null: return
	var mecha = mecha_3d_root.get_node_or_null("MechaBase") if mecha_3d_root.has_node("MechaBase") else mecha_3d_root
	var pmm = mecha.get_node_or_null("PartMeshManager") if mecha else null
	if not pmm: return

	var slots = ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]
	for slot in slots:
		var armor_data = GlobalData.equipped_parts.get(slot, {})
		var part = ArmorPart.new()
		part.part_name = armor_data.get("name", "Spiky Tactical Armor")
		part.max_hp = armor_data.get("durability", armor_data.get("max_hp", 100.0))
		if armor_data.has("color"):
			part.part_color = armor_data.get("color")
		pmm.initialize_slot(slot, part)


func _apply_3d_salvage_preview(slot: String, info: Dictionary) -> void:
	if mecha_3d_root == null: return
	var mat = StandardMaterial3D.new()
	mat.albedo_color = info.get("color", Color(0.2, 0.45, 0.25))
	mat.metallic = 0.75
	mat.roughness = 0.4
	_set_slot_material(slot, mat)


func _set_slot_material(slot: String, mat: Material) -> void:
	match slot:
		"head":
			var node = mecha_3d_root.get_node_or_null("MechaBase/Head/HeadMesh")
			if node: node.material_override = mat
		"body":
			var node = mecha_3d_root.get_node_or_null("MechaBase/Body/BodyMesh")
			if node: node.material_override = mat
		"arm_left":
			var node = mecha_3d_root.get_node_or_null("MechaBase/ArmLeft/ArmLeftMesh")
			if node: node.material_override = mat
		"arm_right":
			var node = mecha_3d_root.get_node_or_null("MechaBase/ArmRight/ArmRightMesh")
			if node: node.material_override = mat
		"leg_left", "leg_right":
			var n1 = mecha_3d_root.get_node_or_null("MechaBase/LegLeft/LegLeftMesh")
			var n2 = mecha_3d_root.get_node_or_null("MechaBase/LegRight/LegRightMesh")
			if n1: n1.material_override = mat
			if n2: n2.material_override = mat


func _on_equip_pressed() -> void:
	if current_mode == "upgrade":
		var cost_cr = GlobalData.frame_upgrade_level * 150
		var cost_cores = GlobalData.frame_upgrade_level
		if GlobalData.credits >= cost_cr and GlobalData.data_cores >= cost_cores:
			GlobalData.credits -= cost_cr
			GlobalData.data_cores -= cost_cores
			GlobalData.frame_upgrade_level += 1
			status_message_label.text = "✅ Frame Reactor Upgraded to Level %d!" % GlobalData.frame_upgrade_level
			GlobalData.save_run()
			_update_total_stats()
		else:
			status_message_label.text = "❌ Insufficient Credits or Data Cores!"
		return

	if selected_slot == "chassis":
		GlobalData.chassis_id = selected_chassis_key
		var name_str = GlobalData.chassis_catalog[selected_chassis_key].get("name", "Chassis")
		status_message_label.text = "✅ Chassis Model Set & Applied: %s!" % name_str
		GlobalData.save_run()
		_update_total_stats()
		return

	if not selected_salvage_info.is_empty():
		var res = ArmorPart.new()
		res.part_name = selected_salvage_info.get("name", "Salvaged Plate")
		res.max_hp = selected_salvage_info.get("hp", 40.0)
		res.armor_class = selected_salvage_info.get("armor", 25.0)
		res.weight = selected_salvage_info.get("weight", 6.0)
		GlobalData.equipped_parts[selected_slot] = res
		GlobalData.part_damage.erase(selected_slot)
		status_message_label.text = "✅ Equipped & Saved: %s!" % res.part_name
		GlobalData.save_run()
		_update_total_stats()
		return

	if current_mode == "frame" and not selected_frame_info.is_empty():
		GlobalData.equipped_frames[selected_slot] = selected_frame_info.duplicate()
		var fname = selected_frame_info.get("name", "Frame")
		status_message_label.text = "✅ Equipped Inner Frame: %s!" % fname
		GlobalData.save_run()
		_update_total_stats()
	elif selected_part_path != "" and ResourceLoader.exists(selected_part_path):
		var res = load(selected_part_path)
		if res:
			GlobalData.equipped_parts[selected_slot] = res
			GlobalData.part_damage.erase(selected_slot)
			var pname = res.get("part_name") if res.get("part_name") != null else "Part"
			status_message_label.text = "✅ Equipped & Saved Armor: %s!" % pname
			GlobalData.save_run()
			_update_total_stats()


func _on_repair_part_pressed() -> void:
	var dmg = GlobalData.part_damage.get(selected_slot, 0.0)
	if dmg <= 0.0:
		status_message_label.text = "%s is fully functional!" % selected_slot.to_upper()
		return
	var cost = int(dmg * 50.0 * COST_PER_HP)
	if GlobalData.credits < cost:
		status_message_label.text = "Need %d credits!" % cost
		return
	GlobalData.credits -= cost
	GlobalData.part_damage.erase(selected_slot)
	status_message_label.text = "Repaired %s!" % selected_slot.to_upper()
	_update_total_stats()


func _on_full_repair_pressed() -> void:
	var total_cost = 0.0
	for slot in GlobalData.equipped_parts:
		var dmg = GlobalData.part_damage.get(slot, 0.0)
		total_cost += dmg * 50.0 * COST_PER_HP

	if total_cost <= 0:
		status_message_label.text = "All parts OK!"
		return

	if GlobalData.credits < int(total_cost):
		status_message_label.text = "Need %d credits!" % int(total_cost)
		return

	GlobalData.credits -= int(total_cost)
	GlobalData.part_damage.clear()
	status_message_label.text = "Full Repair Complete!"
	_update_total_stats()


func _update_total_stats() -> void:
	var chassis_info = GlobalData.chassis_catalog.get(GlobalData.chassis_id, GlobalData.chassis_catalog["standard"])
	var max_weight = chassis_info["max_weight"] + ((GlobalData.frame_upgrade_level - 1) * 15.0)

	var total_frame_weight = 0.0
	var total_armor_weight = 0.0
	var total_frame_hp = 0.0
	var total_armor_hp = 0.0

	for slot in GlobalData.equipped_frames:
		var f = GlobalData.equipped_frames[slot]
		total_frame_weight += f.get("weight", 0.0)
		total_frame_hp += f.get("hp", 0.0) + ((GlobalData.frame_upgrade_level - 1) * 25.0)

	for slot in GlobalData.equipped_parts:
		var p = GlobalData.equipped_parts[slot]
		if p and p.get("weight") != null:
			total_armor_weight += p.weight
		if p and p.get("max_hp") != null:
			total_armor_hp += p.max_hp

	var total_weight = total_frame_weight + total_armor_weight

	if weight_bar:
		weight_bar.max_value = max_weight
		weight_bar.value = total_weight

	if total_stats_label:
		total_stats_label.text = "FRAME LVL: %d | FRAME HP: %.0f | ARMOR HP: %.0f\nFRAME W: %.1fkg | ARMOR W: %.1fkg\nTOTAL WEIGHT: %.1f / %.1f kg\nCREDITS: %d cr | CORES: %d" % [
			GlobalData.frame_upgrade_level, total_frame_hp, total_armor_hp,
			total_frame_weight, total_armor_weight,
			total_weight, max_weight,
			GlobalData.credits, GlobalData.data_cores
		]


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		_on_close_pressed()
