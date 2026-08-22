extends Area3D

## A directional retreat/breakthrough point on the battlefield edge.
## Connects combat edge egress to the tabletop board grid (Retreat -1 tile,
## Breakthrough +1 tile advance, or Flank escape). If the adjacent board tile
## is out-of-bounds, this boundary is locked as an impassable physical barrier.

const DEFAULT_ESCAPE_TIME := 10.0

@export var escape_time: float = DEFAULT_ESCAPE_TIME
@export var escape_type: String = "retreat" # "retreat", "breakthrough", "flank_left", "flank_right"
@export var delta_tile: Vector2i = Vector2i.ZERO
@export var is_locked: bool = false
@export var direction_name: String = "SOUTH"
@export var display_label: String = "TACTICAL RETREAT"

const VISIBLE_NEAR := 26.0
const VISIBLE_FAR := 55.0
var _distance_alpha := 1.0

# Hologram Indicator colors: idle → charging → almost done.
const IDLE_COLOR_RETREAT := Color(0.3, 0.75, 1.0)
const IDLE_COLOR_BREAKTHROUGH := Color(0.2, 1.0, 0.6)
const IDLE_COLOR_FLANK := Color(0.4, 0.85, 1.0)
const LOCKED_COLOR := Color(1.0, 0.22, 0.22)
const CHARGE_COLOR := Color(0.95, 0.85, 0.2)
const DANGER_COLOR := Color(1.0, 0.35, 0.2)

var _time_inside := 0.0
var _player_inside := false
var _tracked_body: Node3D = null
var _escaped := false
var _battle_over := false

var _zone_mesh: MeshInstance3D
var _zone_material: ShaderMaterial
var _beacon: OmniLight3D
var _tag_label: Label3D = null
var _locked_barrier_body: StaticBody3D = null

var wall_local: Vector3 = Vector3.ZERO
var edge_dist: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	EventBus.combat_ended.connect(_on_combat_ended)

	if _zone_material == null:
		_build_visuals()


func _process(_delta: float) -> void:
	_update_distance_visibility()


func _physics_process(delta: float) -> void:
	if _escaped or _battle_over or GameManager.is_escaping or is_locked:
		return
	if _player_inside:
		if _tracked_body == null or not is_instance_valid(_tracked_body) or not _is_player_body(_tracked_body):
			_player_inside = false
			_tracked_body = null
			_time_inside = 0.0
			_update_visual()
			return
		_time_inside += delta
		_update_visual()
		if _time_inside >= escape_time:
			_complete_escape()


func _on_body_entered(body: Node3D) -> void:
	if is_locked:
		return
	if _is_player_body(body):
		_player_inside = true
		_tracked_body = body


func _on_body_exited(body: Node3D) -> void:
	if body == _tracked_body:
		_player_inside = false
		_tracked_body = null
		_time_inside = 0.0
		_update_visual()


func _on_combat_ended(_victory: bool) -> void:
	_battle_over = true


func _is_player_body(body: Node3D) -> bool:
	if body != GameManager.get_player_mecha() and not body.is_in_group("mecha"):
		return false
	var hs = body.get_node_or_null("HealthSystem")
	if hs and hs.get("is_destroyed"):
		return false
	return true


func _complete_escape() -> void:
	if _escaped or _battle_over or GameManager.is_escaping or is_locked:
		return
	_escaped = true
	_update_visual()
	GameManager.is_escaping = true
	EventBus.combat_escaped_directional.emit(escape_type, delta_tile)
	EventBus.combat_escaped.emit()


func is_player_inside() -> bool:
	return _player_inside and _tracked_body != null and is_instance_valid(_tracked_body)


func is_escape_complete() -> bool:
	return _escaped


func get_hold_progress() -> float:
	return clampf(_time_inside / maxf(escape_time, 0.001), 0.0, 1.0)


func get_hold_remaining() -> float:
	return maxf(escape_time - _time_inside, 0.0)


func _get_base_idle_color() -> Color:
	if is_locked:
		return LOCKED_COLOR
	match escape_type:
		"breakthrough":
			return IDLE_COLOR_BREAKTHROUGH
		"flank_left", "flank_right":
			return IDLE_COLOR_FLANK
		_:
			return IDLE_COLOR_RETREAT


func _update_distance_visibility() -> void:
	if _zone_material == null:
		return
	var mecha = GameManager.get_player_mecha()
	if mecha == null:
		_distance_alpha = 1.0
		return
	var d := global_position.distance_to(mecha.global_position)
	_distance_alpha = clampf(1.0 - (d - VISIBLE_NEAR) / maxf(VISIBLE_FAR - VISIBLE_NEAR, 0.001), 0.0, 1.0)
	if _zone_mesh:
		_zone_mesh.visible = _distance_alpha > 0.02
	if _tag_label:
		_tag_label.visible = _distance_alpha > 0.15
	_update_visual()


func _update_visual() -> void:
	if _zone_material == null:
		return

	var base_idle := _get_base_idle_color()
	var t := clampf(_time_inside / maxf(escape_time, 0.001), 0.0, 1.0)
	var color: Color
	var alpha: float

	if is_locked:
		color = LOCKED_COLOR
		alpha = 0.55 * _distance_alpha
	elif _escaped:
		color = DANGER_COLOR
		alpha = 0.75
	elif _player_inside:
		if t < 0.5:
			color = base_idle.lerp(CHARGE_COLOR, t * 2.0)
		else:
			color = CHARGE_COLOR.lerp(DANGER_COLOR, (t - 0.5) * 2.0)
		alpha = (0.45 + t * 0.4) * _distance_alpha
	else:
		color = base_idle
		alpha = 0.32 * _distance_alpha

	_zone_material.set_shader_parameter("base_color", Color(color.r, color.g, color.b, alpha))
	_zone_material.set_shader_parameter("scan_color", Color(minf(color.r + 0.3, 1.0), minf(color.g + 0.3, 1.0), minf(color.b + 0.3, 1.0), alpha * 1.5))

	if _beacon:
		_beacon.light_color = color
		_beacon.light_energy = (0.5 + t * 3.5) if not is_locked else 0.8


func _build_visuals() -> void:
	var col := _find_collision_shape()
	var size := Vector3(24.0, 2.5, 24.0)
	if col and col.shape is BoxShape3D:
		var bs = col.shape as BoxShape3D
		size = Vector3(bs.size.x, 2.5, bs.size.z) # Low-height 2.5m holographic fence

	var shader_res = preload("res://shaders/hologram_boundary.gdshader")
	_zone_material = ShaderMaterial.new()
	_zone_material.shader = shader_res
	var base_idle := _get_base_idle_color()
	_zone_material.set_shader_parameter("base_color", Color(base_idle.r, base_idle.g, base_idle.b, 0.35))
	_zone_material.set_shader_parameter("scan_color", Color(1.0, 1.0, 1.0, 0.8))
	_zone_material.set_shader_parameter("scanline_count", 18.0)
	_zone_material.set_shader_parameter("scan_speed", 1.5)
	_zone_material.set_shader_parameter("grid_intensity", 1.2)

	_zone_mesh = MeshInstance3D.new()
	_zone_mesh.name = "HologramFence"
	var wall := BoxMesh.new()
	if size.z < size.x:
		wall.size = Vector3(size.x, 2.5, 0.4)
	else:
		wall.size = Vector3(0.4, 2.5, size.z)
	_zone_mesh.mesh = wall
	_zone_mesh.material_override = _zone_material
	_zone_mesh.position = wall_local + Vector3(0, 1.25, 0)
	add_child(_zone_mesh)

	# Low-profile holographic light beacon
	_beacon = OmniLight3D.new()
	_beacon.name = "Beacon"
	_beacon.light_color = base_idle
	_beacon.light_energy = 0.5
	_beacon.omni_range = 14.0
	_beacon.position = wall_local + Vector3(0, 2.6, 0)
	add_child(_beacon)

	# Holographic directional 3D billboard tag
	_tag_label = Label3D.new()
	_tag_label.name = "DirectionTag"
	_tag_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag_label.no_depth_test = false
	_tag_label.font_size = 28
	_tag_label.outline_size = 6
	_tag_label.modulate = base_idle
	_tag_label.position = wall_local + Vector3(0, 2.2, 0)
	if is_locked:
		_tag_label.text = "✖ %s: SECTOR BORDER (BLOCKED)" % direction_name
	elif escape_type == "breakthrough":
		_tag_label.text = "▲ %s: BREAKTHROUGH (+1 TILE ADVANCE)" % direction_name
	elif escape_type == "retreat":
		_tag_label.text = "▼ %s: TACTICAL RETREAT (-1 TILE)" % direction_name
	else:
		_tag_label.text = "◄► %s: FLANK ESCAPE" % direction_name
	add_child(_tag_label)

	# If locked, create an impassable static physical collider
	if is_locked:
		_locked_barrier_body = StaticBody3D.new()
		_locked_barrier_body.name = "LockedBorderBarrier"
		_locked_barrier_body.collision_layer = 2
		_locked_barrier_body.collision_mask = 0
		var c_shape := CollisionShape3D.new()
		var b_box := BoxShape3D.new()
		b_box.size = Vector3(wall.size.x, 12.0, wall.size.z)
		c_shape.shape = b_box
		c_shape.position = wall_local + Vector3(0, 6.0, 0)
		_locked_barrier_body.add_child(c_shape)
		add_child(_locked_barrier_body)


func _find_collision_shape() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null

	_update_visual()
