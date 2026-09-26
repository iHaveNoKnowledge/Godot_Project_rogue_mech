class_name BoardUnit3D
extends Node3D

## BoardUnit3D: Lightweight 3D unit visual representation for the tactical board.
## Serves as the visual presentation layer for both the Player's Valkren mecha
## and Enemy Fleet Commanders.
##
## State and gameplay authority remain in GlobalData / BoardManager.
## This unit ONLY presents visual mesh, rotation, idle/run animation, and smooth
## board-space movement.

enum UnitType { PLAYER, COMMANDER, BOSS, MERCENARY }

# Archetype Color Palettes
const PLAYER_COLOR_BASE := Color(0.22, 0.48, 0.92)
const PLAYER_COLOR_TRIM := Color(0.16, 0.20, 0.28)
const PLAYER_COLOR_VISOR := Color(0.20, 0.85, 1.0)
const PLAYER_COLOR_GLOW := Color(1.0, 0.55, 0.15)

const COLOR_ARMORED_BASE := Color(0.80, 0.14, 0.12)
const COLOR_ARMORED_TRIM := Color(0.25, 0.15, 0.15)

const COLOR_RECON_BASE := Color(0.95, 0.45, 0.10)
const COLOR_RECON_TRIM := Color(0.30, 0.22, 0.15)

const COLOR_ARTILLERY_BASE := Color(0.92, 0.75, 0.15)
const COLOR_ARTILLERY_TRIM := Color(0.28, 0.25, 0.15)

const COLOR_HK_BASE := Color(0.85, 0.10, 0.45)
const COLOR_HK_TRIM := Color(0.25, 0.10, 0.20)

const COLOR_BOSS_BASE := Color(0.65, 0.18, 0.90)
const COLOR_BOSS_TRIM := Color(0.20, 0.08, 0.30)
const COLOR_BOSS_ACCENT := Color(0.95, 0.20, 0.20)

const COLOR_MERC_BASE := Color(0.90, 0.92, 0.96)
const COLOR_MERC_TRIM := Color(0.25, 0.28, 0.32)

@export var unit_type: UnitType = UnitType.PLAYER
@export var unit_scale: Vector3 = Vector3(0.38, 0.38, 0.38)
@export var ground_offset_y: float = 0.0

var archetype: String = "valkren"
var is_moving: bool = false
var anim_state: String = "idle" # "idle" or "run"
var anim_timer: float = 0.0
var run_speed: float = 12.0
var idle_speed: float = 2.5

# Visual node hierarchy
var ground_anchor: Node3D
var model_root: Node3D

var torso_node: Node3D
var head_node: Node3D
var backpack_node: Node3D
var arm_left_node: Node3D
var forearm_left_node: Node3D
var arm_right_node: Node3D
var forearm_right_node: Node3D
var leg_left_node: Node3D
var shin_left_node: Node3D
var foot_left_node: Node3D
var leg_right_node: Node3D
var shin_right_node: Node3D
var foot_right_node: Node3D

var anim_player: AnimationPlayer
var _base_y: float = 0.0
var _current_heading: Vector2i = Vector2i(1, 0)


func _ready() -> void:
	if ground_anchor == null:
		_build_hierarchy()
	_base_y = global_position.y
	play_idle()


## Builds the clean 3D mecha visual hierarchy and animation components.
func _build_hierarchy() -> void:
	# Clear old children if rebuilding
	for child in get_children():
		if child.name != "ModeTag" and child.name != "FleetCountBadge":
			child.queue_free()

	ground_anchor = Node3D.new()
	ground_anchor.name = "GroundAnchor"
	add_child(ground_anchor)

	model_root = Node3D.new()
	model_root.name = "ModelRoot"
	model_root.scale = unit_scale
	ground_anchor.add_child(model_root)

	# Build Materials
	var base_col := PLAYER_COLOR_BASE
	var trim_col := PLAYER_COLOR_TRIM
	var visor_col := PLAYER_COLOR_VISOR
	var glow_col := PLAYER_COLOR_GLOW

	match unit_type:
		UnitType.COMMANDER:
			match archetype:
				"recon":
					base_col = COLOR_RECON_BASE
					trim_col = COLOR_RECON_TRIM
					visor_col = Color(1.0, 0.7, 0.2)
				"armored":
					base_col = COLOR_ARMORED_BASE
					trim_col = COLOR_ARMORED_TRIM
					visor_col = Color(1.0, 0.2, 0.2)
				"artillery":
					base_col = COLOR_ARTILLERY_BASE
					trim_col = COLOR_ARTILLERY_TRIM
					visor_col = Color(1.0, 0.85, 0.1)
				"hunter_killer":
					base_col = COLOR_HK_BASE
					trim_col = COLOR_HK_TRIM
					visor_col = Color(1.0, 0.1, 0.5)
				_:
					if archetype == "unknown":
						base_col = COLOR_MERC_BASE
						trim_col = COLOR_MERC_TRIM
						visor_col = Color(0.7, 0.9, 1.0)
					else:
						base_col = COLOR_ARMORED_BASE
						trim_col = COLOR_ARMORED_TRIM
						visor_col = Color(1.0, 0.2, 0.2)
		UnitType.BOSS:
			base_col = COLOR_BOSS_BASE
			trim_col = COLOR_BOSS_TRIM
			visor_col = COLOR_BOSS_ACCENT
			glow_col = COLOR_BOSS_ACCENT
		UnitType.MERCENARY:
			base_col = COLOR_MERC_BASE
			trim_col = COLOR_MERC_TRIM
			visor_col = Color(0.7, 0.9, 1.0)
		_:
			base_col = PLAYER_COLOR_BASE
			trim_col = PLAYER_COLOR_TRIM
			visor_col = PLAYER_COLOR_VISOR

	var mat_base := StandardMaterial3D.new()
	mat_base.albedo_color = base_col
	mat_base.metallic = 0.5
	mat_base.roughness = 0.35

	var mat_trim := StandardMaterial3D.new()
	mat_trim.albedo_color = trim_col
	mat_trim.metallic = 0.7
	mat_trim.roughness = 0.4

	var mat_visor := StandardMaterial3D.new()
	mat_visor.albedo_color = visor_col
	mat_visor.emission_enabled = true
	mat_visor.emission = visor_col
	mat_visor.emission_energy_multiplier = 2.5

	var mat_glow := StandardMaterial3D.new()
	mat_glow.albedo_color = glow_col
	mat_glow.emission_enabled = true
	mat_glow.emission = glow_col
	mat_glow.emission_energy_multiplier = 2.0

	# 1. Torso / Chassis
	torso_node = Node3D.new()
	torso_node.name = "Torso"
	torso_node.position = Vector3(0, 1.6, 0)
	model_root.add_child(torso_node)

	var chest_mesh := MeshInstance3D.new()
	var chest_box := BoxMesh.new()
	chest_box.size = Vector3(1.1, 1.1, 0.8)
	chest_mesh.mesh = chest_box
	chest_mesh.material_override = mat_base
	torso_node.add_child(chest_mesh)

	var cockpit_hatch := MeshInstance3D.new()
	var hatch_box := BoxMesh.new()
	hatch_box.size = Vector3(0.65, 0.55, 0.35)
	cockpit_hatch.mesh = hatch_box
	cockpit_hatch.material_override = mat_trim
	cockpit_hatch.position = Vector3(0, 0.05, -0.32)
	torso_node.add_child(cockpit_hatch)

	# 2. Head
	head_node = Node3D.new()
	head_node.name = "Head"
	head_node.position = Vector3(0, 0.8, -0.05)
	torso_node.add_child(head_node)

	var head_mesh := MeshInstance3D.new()
	var head_box := BoxMesh.new()
	head_box.size = Vector3(0.55, 0.45, 0.55)
	head_mesh.mesh = head_box
	head_mesh.material_override = mat_trim
	head_node.add_child(head_mesh)

	var visor_mesh := MeshInstance3D.new()
	var visor_box := BoxMesh.new()
	visor_box.size = Vector3(0.45, 0.15, 0.1)
	visor_mesh.mesh = visor_box
	visor_mesh.material_override = mat_visor
	visor_mesh.position = Vector3(0, 0.02, -0.28)
	head_node.add_child(visor_mesh)

	# Archetype Crests
	if unit_type == UnitType.BOSS or archetype == "hunter_killer":
		var crest := MeshInstance3D.new()
		var crest_prism := PrismMesh.new()
		crest_prism.size = Vector3(0.6, 0.5, 0.15)
		crest.mesh = crest_prism
		crest.material_override = mat_glow
		crest.position = Vector3(0, 0.35, 0)
		head_node.add_child(crest)

	# 3. Backpack & Thrusters
	backpack_node = Node3D.new()
	backpack_node.name = "Backpack"
	backpack_node.position = Vector3(0, 0.15, 0.5)
	torso_node.add_child(backpack_node)

	var pack_mesh := MeshInstance3D.new()
	var pack_box := BoxMesh.new()
	pack_box.size = Vector3(0.85, 0.85, 0.4)
	pack_mesh.mesh = pack_box
	pack_mesh.material_override = mat_trim
	backpack_node.add_child(pack_mesh)

	for side in [-0.28, 0.28]:
		var thruster := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.10
		cyl.bottom_radius = 0.16
		cyl.height = 0.35
		thruster.mesh = cyl
		thruster.material_override = mat_glow
		thruster.position = Vector3(side, -0.35, 0.1)
		thruster.rotation.x = deg_to_rad(-25.0)
		backpack_node.add_child(thruster)

	# 4. Arms (Left & Right)
	arm_left_node = _build_arm(mat_base, mat_trim, mat_glow, -0.85, true)
	torso_node.add_child(arm_left_node)

	arm_right_node = _build_arm(mat_base, mat_trim, mat_glow, 0.85, false)
	torso_node.add_child(arm_right_node)

	# 5. Legs (Left & Right)
	leg_left_node = _build_leg(mat_base, mat_trim, -0.42)
	ground_anchor.get_node("ModelRoot").add_child(leg_left_node)

	leg_right_node = _build_leg(mat_base, mat_trim, 0.42)
	ground_anchor.get_node("ModelRoot").add_child(leg_right_node)

	# Ground Shadow Contact Disc
	var shadow := MeshInstance3D.new()
	var s_cyl := CylinderMesh.new()
	s_cyl.top_radius = 0.75
	s_cyl.bottom_radius = 0.75
	s_cyl.height = 0.01
	shadow.mesh = s_cyl
	var s_mat := StandardMaterial3D.new()
	s_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.5)
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = s_mat
	shadow.position = Vector3(0, 0.02, 0)
	model_root.add_child(shadow)

	# Animation Player
	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	add_child(anim_player)
	_setup_animation_tracks()


func _build_arm(mat_base: Material, mat_trim: Material, mat_glow: Material, offset_x: float, is_left: bool) -> Node3D:
	var arm := Node3D.new()
	arm.name = "ArmLeft" if is_left else "ArmRight"
	arm.position = Vector3(offset_x, 0.35, 0.0)

	var shoulder := MeshInstance3D.new()
	var s_box := BoxMesh.new()
	s_box.size = Vector3(0.45, 0.45, 0.5)
	if unit_type == UnitType.BOSS or archetype == "armored":
		s_box.size = Vector3(0.65, 0.55, 0.65)
	shoulder.mesh = s_box
	shoulder.material_override = mat_base
	arm.add_child(shoulder)

	var upper_arm := MeshInstance3D.new()
	var u_box := BoxMesh.new()
	u_box.size = Vector3(0.28, 0.6, 0.3)
	upper_arm.mesh = u_box
	upper_arm.material_override = mat_trim
	upper_arm.position = Vector3(0, -0.4, 0)
	arm.add_child(upper_arm)

	var forearm := Node3D.new()
	forearm.name = "Forearm"
	forearm.position = Vector3(0, -0.7, 0)
	arm.add_child(forearm)
	if is_left:
		forearm_left_node = forearm
	else:
		forearm_right_node = forearm

	var f_mesh := MeshInstance3D.new()
	var f_box := BoxMesh.new()
	f_box.size = Vector3(0.32, 0.6, 0.35)
	f_mesh.mesh = f_box
	f_mesh.material_override = mat_base
	f_mesh.position = Vector3(0, -0.3, -0.05)
	forearm.add_child(f_mesh)

	var gun_pod := MeshInstance3D.new()
	var g_box := BoxMesh.new()
	g_box.size = Vector3(0.15, 0.2, 0.7)
	gun_pod.mesh = g_box
	gun_pod.material_override = mat_trim
	gun_pod.position = Vector3(0, -0.3, -0.4)
	forearm.add_child(gun_pod)

	return arm


func _build_leg(mat_base: Material, mat_trim: Material, offset_x: float) -> Node3D:
	var leg := Node3D.new()
	leg.name = "LegLeft" if offset_x < 0 else "LegRight"
	leg.position = Vector3(offset_x, 1.2, 0.0)

	var thigh := MeshInstance3D.new()
	var t_box := BoxMesh.new()
	t_box.size = Vector3(0.35, 0.65, 0.4)
	thigh.mesh = t_box
	thigh.material_override = mat_trim
	thigh.position = Vector3(0, -0.32, 0)
	leg.add_child(thigh)

	var shin := Node3D.new()
	shin.name = "Shin"
	shin.position = Vector3(0, -0.65, 0)
	leg.add_child(shin)

	var s_mesh := MeshInstance3D.new()
	var s_box := BoxMesh.new()
	s_box.size = Vector3(0.38, 0.65, 0.45)
	s_mesh.mesh = s_box
	s_mesh.material_override = mat_base
	s_mesh.position = Vector3(0, -0.32, 0.02)
	shin.add_child(s_mesh)

	var foot := Node3D.new()
	foot.name = "Foot"
	foot.position = Vector3(0, -0.65, 0)
	shin.add_child(foot)

	var f_mesh := MeshInstance3D.new()
	var f_box := BoxMesh.new()
	f_box.size = Vector3(0.42, 0.2, 0.65)
	f_mesh.mesh = f_box
	f_mesh.material_override = mat_trim
	f_mesh.position = Vector3(0, 0.1, -0.1)
	foot.add_child(f_mesh)

	if offset_x < 0:
		shin_left_node = shin
		foot_left_node = foot
	else:
		shin_right_node = shin
		foot_right_node = foot

	return leg


func _setup_animation_tracks() -> void:
	var anim_lib := AnimationLibrary.new()

	# Idle Animation
	var anim_idle := Animation.new()
	anim_idle.length = 2.0
	anim_idle.loop_mode = Animation.LOOP_LINEAR
	anim_lib.add_animation("idle", anim_idle)

	# Run Animation
	var anim_run := Animation.new()
	anim_run.length = 0.6
	anim_run.loop_mode = Animation.LOOP_LINEAR
	anim_lib.add_animation("run", anim_run)

	anim_player.add_animation_library("", anim_lib)


## Configures unit as player Valkren
func setup_player(_loadout_data: Dictionary = {}) -> void:
	unit_type = UnitType.PLAYER
	archetype = "valkren"
	unit_scale = Vector3(0.38, 0.38, 0.38)
	_build_hierarchy()


## Configures unit as Enemy Fleet Commander matching authoritative fleet dictionary
func setup_commander(fleet_data: Dictionary) -> void:
	unit_type = UnitType.COMMANDER
	var is_unknown := str(fleet_data.get("faction", "hostile")) == "unknown"
	archetype = str(fleet_data.get("archetype", "armored"))
	if is_unknown:
		archetype = "unknown"
	var aces := int(fleet_data.get("aces", 0))
	if aces > 0 and archetype != "unknown":
		archetype = "hunter_killer"

	unit_scale = Vector3(0.36, 0.36, 0.36)
	_build_hierarchy()

	var dir := PatrolSystem.normalize_dir(fleet_data.get("dir"))
	face_heading(dir, true)


## Configures unit as Sector Boss Overlord
func setup_boss() -> void:
	unit_type = UnitType.BOSS
	archetype = "boss"
	unit_scale = Vector3(0.50, 0.50, 0.50)
	_build_hierarchy()


## Rotates the unit to face a board grid heading (X = east, Y = south)
func face_heading(heading: Vector2i, immediate: bool = false) -> void:
	_current_heading = heading
	# Heading to 3D rotation yaw: North(0,-1) -> 0, South(0,1) -> PI, East(1,0) -> -PI/2, West(-1,0) -> PI/2
	var target_yaw := atan2(-float(heading.x), -float(heading.y))
	if immediate or not is_inside_tree():
		rotation.y = target_yaw
	else:
		var current_yaw := rotation.y
		var diff := wrapf(target_yaw - current_yaw, -PI, PI)
		var tween := create_tween()
		tween.tween_property(self, "rotation:y", current_yaw + diff, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func face_direction(heading: Vector2i, immediate: bool = false) -> void:
	face_heading(heading, immediate)


func play_idle() -> void:
	anim_state = "idle"
	is_moving = false
	if anim_player and anim_player.has_animation("idle"):
		anim_player.play("idle")


func play_run() -> void:
	anim_state = "run"
	is_moving = true
	if anim_player and anim_player.has_animation("run"):
		anim_player.play("run")


func play_move() -> void:
	play_run()


func stop_move() -> void:
	play_idle()


func set_world_position(pos: Vector3) -> void:
	global_position = pos + Vector3(0, ground_offset_y, 0)
	_base_y = global_position.y


func set_grid_pos(_tile_pos: Vector2i, world_pos: Vector3) -> void:
	set_world_position(world_pos)


## Drives runtime procedural animation for limbs and breathing
func _process(delta: float) -> void:
	anim_timer += delta

	if anim_state == "run" or is_moving:
		var t := anim_timer * run_speed
		var stride := sin(t)
		var counter_stride := -stride

		if leg_left_node:
			leg_left_node.rotation.x = stride * deg_to_rad(32.0)
		if leg_right_node:
			leg_right_node.rotation.x = counter_stride * deg_to_rad(32.0)
		if shin_left_node:
			shin_left_node.rotation.x = maxf(0.0, -stride) * deg_to_rad(35.0)
		if shin_right_node:
			shin_right_node.rotation.x = maxf(0.0, stride) * deg_to_rad(35.0)

		if arm_left_node:
			arm_left_node.rotation.x = counter_stride * deg_to_rad(28.0)
		if arm_right_node:
			arm_right_node.rotation.x = stride * deg_to_rad(28.0)

		if torso_node:
			torso_node.position.y = 1.6 + absf(sin(t * 2.0)) * 0.12
			torso_node.rotation.z = sin(t) * deg_to_rad(3.0)
	else:
		var t := anim_timer * idle_speed
		# Gentle breathing stance
		if torso_node:
			torso_node.position.y = 1.6 + sin(t) * 0.03
			torso_node.rotation.z = 0.0
		if arm_left_node:
			arm_left_node.rotation.x = deg_to_rad(6.0) + sin(t) * deg_to_rad(2.0)
		if arm_right_node:
			arm_right_node.rotation.x = deg_to_rad(6.0) + sin(t) * deg_to_rad(2.0)
		if leg_left_node:
			leg_left_node.rotation.x = 0.0
		if leg_right_node:
			leg_right_node.rotation.x = 0.0
		if shin_left_node:
			shin_left_node.rotation.x = 0.0
		if shin_right_node:
			shin_right_node.rotation.x = 0.0
