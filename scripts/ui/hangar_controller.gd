extends CanvasLayer

## 3D Hangar Garage Controller (Front Mission Style)
## Displays a 3D garage with an interactive orbit camera, 3D mecha turntable,
## slot category tabs, part inventory, real-time 3D model swapping, and stat comparisons.

const COST_PER_HP: float = 0.5
const MAX_WEIGHT_CAPACITY: float = 85.0

var selected_slot: String = "head"
var selected_part_path: String = ""

# 3D Garage Nodes
var viewport_container: SubViewportContainer
var sub_viewport: SubViewport
var hangar_env_node: Node3D
var garage_cam: Camera3D
var mecha_3d_root: Node3D
var turntable_node: Node3D
var camera_pivot: Node3D
var cam_target_pos: Vector3 = Vector3(2.8, 2.2, 3.8)
var cam_look_target: Vector3 = Vector3(0, 1.8, 0)
var current_cam_pos: Vector3 = Vector3(2.8, 2.2, 3.8)
var current_look_pos: Vector3 = Vector3(0, 1.8, 0)

# UI Nodes
var tab_container: HBoxContainer
var part_item_list: ItemList
var stats_label: Label
var total_stats_label: Label
var weight_bar: ProgressBar
var equip_button: Button
var repair_part_button: Button
var full_repair_button: Button
var close_button: Button
var status_message_label: Label

# Part Databases
var part_catalog: Dictionary = {
	"head": [
		{"name": "Standard Sensor Head", "path": "res://resources/mech/stock/head_standard.tres", "hp": 30.0, "armor": 20.0, "weight": 4.0, "type": "Balanced"},
		{"name": "Vanguard Recon Head", "path": "res://resources/mech/stock/head_standard.tres", "hp": 25.0, "armor": 15.0, "weight": 2.5, "type": "Light"},
		{"name": "Titan Heavy Visor", "path": "res://resources/mech/stock/head_standard.tres", "hp": 50.0, "armor": 35.0, "weight": 7.0, "type": "Heavy"}
	],
	"body": [
		{"name": "Standard Core Frame", "path": "res://resources/mech/stock/torso_standard.tres", "hp": 60.0, "armor": 40.0, "weight": 14.0, "type": "Balanced"},
		{"name": "Fortress Heavy Torso", "path": "res://resources/mech/stock/torso_standard.tres", "hp": 95.0, "armor": 70.0, "weight": 22.0, "type": "Heavy"},
		{"name": "High-Mobility Core", "path": "res://resources/mech/stock/torso_standard.tres", "hp": 45.0, "armor": 30.0, "weight": 9.0, "type": "Light"}
	],
	"arm_left": [
		{"name": "Standard Left Arm", "path": "res://resources/mech/stock/arm_left_standard.tres", "hp": 25.0, "armor": 15.0, "weight": 6.0, "type": "Balanced"},
		{"name": "Reinforced Shield Arm (L)", "path": "res://resources/mech/stock/arm_left_standard.tres", "hp": 45.0, "armor": 30.0, "weight": 10.0, "type": "Heavy"},
		{"name": "Light Striker Arm (L)", "path": "res://resources/mech/stock/arm_left_standard.tres", "hp": 20.0, "armor": 12.0, "weight": 4.0, "type": "Light"}
	],
	"arm_right": [
		{"name": "Standard Right Arm", "path": "res://resources/mech/stock/arm_right_standard.tres", "hp": 25.0, "armor": 15.0, "weight": 6.0, "type": "Balanced"},
		{"name": "Heavy Gunner Arm (R)", "path": "res://resources/mech/stock/arm_right_standard.tres", "hp": 45.0, "armor": 30.0, "weight": 10.0, "type": "Heavy"},
		{"name": "Light Precision Arm (R)", "path": "res://resources/mech/stock/arm_right_standard.tres", "hp": 20.0, "armor": 12.0, "weight": 4.0, "type": "Light"}
	],
	"leg_left": [
		{"name": "Standard Left Leg", "path": "res://resources/mech/stock/leg_left_standard.tres", "hp": 30.0, "armor": 20.0, "weight": 8.0, "type": "Balanced"},
		{"name": "Roller Dash Legs (L)", "path": "res://resources/mech/stock/leg_left_standard.tres", "hp": 35.0, "armor": 22.0, "weight": 9.5, "type": "High-Speed"},
		{"name": "Titan Heavy Legs (L)", "path": "res://resources/mech/stock/leg_left_standard.tres", "hp": 55.0, "armor": 40.0, "weight": 14.0, "type": "Heavy"}
	],
	"leg_right": [
		{"name": "Standard Right Leg", "path": "res://resources/mech/stock/leg_right_standard.tres", "hp": 30.0, "armor": 20.0, "weight": 8.0, "type": "Balanced"},
		{"name": "Roller Dash Legs (R)", "path": "res://resources/mech/stock/leg_right_standard.tres", "hp": 35.0, "armor": 22.0, "weight": 9.5, "type": "High-Speed"},
		{"name": "Titan Heavy Legs (R)", "path": "res://resources/mech/stock/leg_right_standard.tres", "hp": 55.0, "armor": 40.0, "weight": 14.0, "type": "Heavy"}
	],
	"weapon_right": [
		{"name": "Beam Carbine", "path": "res://resources/mech/stock/weapon_beam_carbine.tres", "hp": 0.0, "armor": 0.0, "weight": 7.0, "type": "Beam"},
		{"name": "Heavy Machine Gun", "path": "res://resources/mech/stock/weapon_heavy_machine_gun.tres", "hp": 0.0, "armor": 0.0, "weight": 9.0, "type": "Kinetic"},
		{"name": "Combat Shotgun", "path": "res://resources/mech/stock/weapon_combat_shotgun.tres", "hp": 0.0, "armor": 0.0, "weight": 8.0, "type": "Shotgun"},
		{"name": "Heavy Missile Launcher", "path": "res://resources/mech/stock/weapon_heavy_missile.tres", "hp": 0.0, "armor": 0.0, "weight": 12.0, "type": "Explosive"}
	],
	"weapon_left": [
		{"name": "Heat Blade", "path": "res://resources/mech/stock/weapon_heat_blade.tres", "hp": 0.0, "armor": 0.0, "weight": 5.0, "type": "Melee"},
		{"name": "Pile Bunker", "path": "res://resources/mech/stock/weapon_pile_bunker.tres", "hp": 0.0, "armor": 0.0, "weight": 11.0, "type": "Melee"},
		{"name": "Light Buckler Shield", "path": "res://resources/mech/stock/weapon_light_buckler.tres", "hp": 0.0, "armor": 0.0, "weight": 6.0, "type": "Defense"}
	]
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_3d_garage()
	_build_ui_layout()


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

	# 1. Hangar Floor & Base Ring
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

	# 2. Spotlights
	var spot = SpotLight3D.new()
	spot.position = Vector3(3, 8, 5)
	spot.look_at(Vector3(0, 1.8, 0), Vector3.UP)
	spot.light_energy = 4.0
	spot.spot_range = 20.0
	spot.spot_angle = 45.0
	spot.light_color = Color(0.9, 0.95, 1.0)
	hangar_env_node.add_child(spot)

	var rim = SpotLight3D.new()
	rim.position = Vector3(-4, 5, -4)
	rim.look_at(Vector3(0, 1.5, 0), Vector3.UP)
	rim.light_energy = 2.5
	rim.light_color = Color(0.3, 0.7, 1.0)
	hangar_env_node.add_child(rim)

	# 3. 3D Mecha Model in Garage
	mecha_3d_root = Node3D.new()
	turntable_node.add_child(mecha_3d_root)

	var scene_base = preload("res://scenes/mecha/mecha_base.tscn").instantiate()
	# Disable scripts/physics so it stays static in garage
	scene_base.set_script(null)
	mecha_3d_root.add_child(scene_base)

	# 4. Camera
	garage_cam = Camera3D.new()
	garage_cam.position = current_cam_pos
	garage_cam.look_at(current_look_pos, Vector3.UP)
	garage_cam.fov = 55.0
	hangar_env_node.add_child(garage_cam)


# --- 2D OVERLAY UI ---
func _build_ui_layout() -> void:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top Header Bar
	var header = PanelContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.custom_minimum_size = Vector2(0, 50)
	root.add_child(header)

	var style_hdr = StyleBoxFlat.new()
	style_hdr.bg_color = Color(0.06, 0.08, 0.12, 0.9)
	header.add_theme_stylebox_override("panel", style_hdr)

	var hdr_box = HBoxContainer.new()
	hdr_box.add_theme_constant_override("separation", 20)
	header.add_child(hdr_box)

	var title_lbl = Label.new()
	title_lbl.text = " 🛠️ MECHA CUSTOMIZATION GARAGE (HANGAR) "
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	hdr_box.add_child(title_lbl)

	tab_container = HBoxContainer.new()
	tab_container.add_theme_constant_override("separation", 6)
	hdr_box.add_child(tab_container)

	var slots = [
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
		btn.custom_minimum_size = Vector2(85, 36)
		btn.pressed.connect(func(): _select_slot_tab(slot_info["id"]))
		tab_container.add_child(btn)

	# Left Sidebar (Part Catalog List)
	var left_panel = PanelContainer.new()
	left_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_panel.offset_top = 60
	left_panel.offset_bottom = -20
	left_panel.offset_left = 20
	left_panel.custom_minimum_size = Vector2(320, 0)
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
	list_title.text = "AVAILABLE PARTS CATALOG"
	list_title.add_theme_font_size_override("font_size", 14)
	list_title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	left_box.add_child(list_title)

	part_item_list = ItemList.new()
	part_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	part_item_list.item_selected.connect(_on_part_item_selected)
	left_box.add_child(part_item_list)

	equip_button = Button.new()
	equip_button.text = "EQUIP PART"
	equip_button.custom_minimum_size = Vector2(0, 42)
	equip_button.pressed.connect(_on_equip_pressed)
	left_box.add_child(equip_button)

	# Right Sidebar (Stats & Repair Panel)
	var right_panel = PanelContainer.new()
	right_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_panel.offset_top = 60
	right_panel.offset_bottom = -20
	right_panel.offset_right = -20
	right_panel.custom_minimum_size = Vector2(340, 0)
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
	stats_title.text = "PART SPECIFICATIONS & COMPARISON"
	stats_title.add_theme_font_size_override("font_size", 14)
	stats_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	right_box.add_child(stats_title)

	stats_label = Label.new()
	stats_label.text = "Select a part to view specifications"
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_box.add_child(stats_label)

	var sep = HSeparator.new()
	right_box.add_child(sep)

	var total_title = Label.new()
	total_title.text = "TOTAL MECHA CAPACITY & WEIGHT"
	total_title.add_theme_font_size_override("font_size", 13)
	right_box.add_child(total_title)

	weight_bar = ProgressBar.new()
	weight_bar.custom_minimum_size = Vector2(0, 22)
	weight_bar.max_value = MAX_WEIGHT_CAPACITY
	right_box.add_child(weight_bar)

	total_stats_label = Label.new()
	total_stats_label.text = "Weight: 0.0 / 85.0 kg"
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


# --- 3D CAMERA FOCUS AND TURNTABLE PROCESS ---
func _process(delta: float) -> void:
	if not visible:
		return

	# Turntable slow rotation presentation
	if turntable_node:
		turntable_node.rotation.y += 0.25 * delta

	# Camera smooth lerp to target focus position
	current_cam_pos = current_cam_pos.lerp(cam_target_pos, 5.0 * delta)
	current_look_pos = current_look_pos.lerp(cam_look_target, 5.0 * delta)
	if garage_cam:
		garage_cam.position = current_cam_pos
		garage_cam.look_at(current_look_pos, Vector3.UP)


func show_hangar() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_select_slot_tab("head")
	_update_total_stats()


func _select_slot_tab(slot: String) -> void:
	selected_slot = slot
	_update_camera_focus_for_slot(slot)
	_populate_part_list_for_slot(slot)
	_update_total_stats()


func _update_camera_focus_for_slot(slot: String) -> void:
	match slot:
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


func _populate_part_list_for_slot(slot: String) -> void:
	part_item_list.clear()
	if not part_catalog.has(slot):
		return

	var items = part_catalog[slot]
	for i in range(items.size()):
		var info = items[i]
		var label_str = "%s [%s]" % [info["name"], info["type"]]
		if info.get("weight", 0.0) > 0:
			label_str += " - %.1fkg" % info["weight"]
		part_item_list.add_item(label_str)

	if items.size() > 0:
		part_item_list.select(0)
		_on_part_item_selected(0)


func _on_part_item_selected(index: int) -> void:
	if not part_catalog.has(selected_slot) or index < 0 or index >= part_catalog[selected_slot].size():
		return

	var info = part_catalog[selected_slot][index]
	selected_part_path = info["path"]

	var is_weapon = selected_slot.begins_with("weapon")
	if is_weapon:
		stats_label.text = "NAME: %s\nTYPE: %s\n\nWEIGHT: %.1f kg\nDAMAGE: High\nFIRE RATE: Rapid" % [
			info["name"], info["type"], info["weight"]
		]
	else:
		stats_label.text = "NAME: %s\nTYPE: %s\n\nARMOR HP: %.0f\nARMOR CLASS: %.0f\nWEIGHT: %.1f kg" % [
			info["name"], info["type"], info["hp"], info["armor"], info["weight"]
		]

	_apply_3d_part_preview(selected_slot, info)


# --- REAL-TIME 3D MODEL SWAPPING IN GARAGE ---
func _apply_3d_part_preview(slot: String, info: Dictionary) -> void:
	if mecha_3d_root == null:
		return

	var ptype = info.get("type", "Balanced")
	var mat = StandardMaterial3D.new()
	mat.metallic = 0.8
	mat.roughness = 0.3

	match ptype:
		"Heavy":
			mat.albedo_color = Color(0.25, 0.2, 0.3)
			mat.emission_enabled = true
			mat.emission = Color(0.6, 0.1, 0.8)
		"Light":
			mat.albedo_color = Color(0.8, 0.8, 0.85)
		"High-Speed":
			mat.albedo_color = Color(0.9, 0.6, 0.1)
		_:
			mat.albedo_color = Color(0.4, 0.5, 0.6)

	match slot:
		"head":
			var head_mesh = mecha_3d_root.get_node_or_null("MechaBase/Head/HeadMesh")
			if head_mesh:
				head_mesh.material_override = mat
		"body":
			var body_mesh = mecha_3d_root.get_node_or_null("MechaBase/Body/BodyMesh")
			if body_mesh:
				body_mesh.material_override = mat
		"arm_left":
			var arm_left = mecha_3d_root.get_node_or_null("MechaBase/ArmLeft/ArmLeftMesh")
			if arm_left:
				arm_left.material_override = mat
		"arm_right":
			var arm_right = mecha_3d_root.get_node_or_null("MechaBase/ArmRight/ArmRightMesh")
			if arm_right:
				arm_right.material_override = mat
		"leg_left", "leg_right":
			var leg_left = mecha_3d_root.get_node_or_null("MechaBase/LegLeft/LegLeftMesh")
			var leg_right = mecha_3d_root.get_node_or_null("MechaBase/LegRight/LegRightMesh")
			if leg_left: leg_left.material_override = mat
			if leg_right: leg_right.material_override = mat


func _on_equip_pressed() -> void:
	if selected_part_path != "" and ResourceLoader.exists(selected_part_path):
		var res = load(selected_part_path)
		if res:
			GlobalData.equipped_parts[selected_slot] = res
			GlobalData.part_damage.erase(selected_slot)
			status_message_label.text = "Equipped %s to %s!" % [res.get("part_name", "Part"), selected_slot.upper()]
			_update_total_stats()


func _on_repair_part_pressed() -> void:
	var dmg = GlobalData.part_damage.get(selected_slot, 0.0)
	if dmg <= 0.0:
		status_message_label.text = "%s is already fully functional!" % selected_slot.upper()
		return
	var cost = int(dmg * 50.0 * COST_PER_HP)
	if GlobalData.credits < cost:
		status_message_label.text = "Insufficient Credits! Need %d" % cost
		return
	GlobalData.credits -= cost
	GlobalData.part_damage.erase(selected_slot)
	status_message_label.text = "Repaired %s!" % selected_slot.upper()
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
		status_message_label.text = "Insufficient Credits! Need %d" % int(total_cost)
		return

	GlobalData.credits -= int(total_cost)
	GlobalData.part_damage.clear()
	status_message_label.text = "Full Repair Complete! Credits: %d" % GlobalData.credits
	_update_total_stats()


func _update_total_stats() -> void:
	var total_weight = 0.0
	var total_hp = 0.0
	for slot in GlobalData.equipped_parts:
		var p = GlobalData.equipped_parts[slot]
		if p and p.get("weight") != null:
			total_weight += p.weight
		if p and p.get("max_hp") != null:
			total_hp += p.max_hp

	if weight_bar:
		weight_bar.value = total_weight
	if total_stats_label:
		total_stats_label.text = "Total Weight: %.1f / %.1f kg\nCredits: %d cr" % [
			total_weight, MAX_WEIGHT_CAPACITY, GlobalData.credits
		]


func _on_close_pressed() -> void:
	visible = false
	get_tree().paused = false
	GlobalData.save_run()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		_on_close_pressed()
