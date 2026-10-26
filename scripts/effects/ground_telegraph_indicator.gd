class_name GroundTelegraphIndicator
extends Node3D

## =============================================================================
## GROUND TELEGRAPH INDICATOR — Action RPG Melee Attack Ground Danger Zone
## =============================================================================
## Displays a projected red rectangular warning corridor on the ground during
## the melee attack wind-up phase.
##
## Features:
##   1. Follows enemy position and aim direction during tracking phase.
##   2. Locks firmly in world space when direction commits (Direction Lock).
##   3. Changes visual intensity / pulses red when locked to cue dodge window.
##   4. Automatically cleans up when dismissed.
## =============================================================================

@export var corridor_width: float = 2.4
@export var corridor_length: float = 5.5
@export var fill_progress: float = 0.0

var _is_locked: bool = false
var _mesh_instance: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _center_line_mesh: MeshInstance3D = null
var _center_material: StandardMaterial3D = null
var _pulse_timer: float = 0.0


func _init() -> void:
	name = "GroundTelegraphIndicator"


func _ready() -> void:
	_build_indicator_meshes()


## Builds the flat danger rectangle and directional center stripe
func _build_indicator_meshes() -> void:
	if _mesh_instance != null:
		return

	# Ground Corridor Mesh (Quad lying flat on ground, slightly lifted to prevent Z-fighting)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "CorridorPlane"
	var quad := QuadMesh.new()
	quad.size = Vector2(corridor_width, corridor_length)
	_mesh_instance.mesh = quad
	# Rotate flat on ground (face up towards +Y)
	_mesh_instance.rotation_degrees = Vector3(-90, 0, 0)
	# Center the quad so the base starts near the enemy's feet and projects forward (-Z)
	_mesh_instance.position = Vector3(0, 0.04, -corridor_length * 0.5)

	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = Color(1.0, 0.15, 0.1, 0.28)
	_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)

	# High-visibility Center Line Stripe
	_center_line_mesh = MeshInstance3D.new()
	_center_line_mesh.name = "CenterStripe"
	var stripe_quad := QuadMesh.new()
	stripe_quad.size = Vector2(0.25, corridor_length)
	_center_line_mesh.mesh = stripe_quad
	_center_line_mesh.rotation_degrees = Vector3(-90, 0, 0)
	_center_line_mesh.position = Vector3(0, 0.05, -corridor_length * 0.5)

	_center_material = StandardMaterial3D.new()
	_center_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_center_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_center_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_center_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_center_material.albedo_color = Color(1.0, 0.85, 0.3, 0.55)
	_center_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_center_line_mesh.material_override = _center_material
	add_child(_center_line_mesh)


func _process(delta: float) -> void:
	if _is_locked and _material:
		_pulse_timer += delta * 14.0
		var pulse: float = 0.55 + sin(_pulse_timer) * 0.25
		_material.albedo_color = Color(1.0, 0.08, 0.05, clampf(pulse, 0.3, 0.8))
		if _center_material:
			_center_material.albedo_color = Color(1.0, 0.95, 0.6, clampf(pulse + 0.2, 0.5, 1.0))


## Configures dimensions and base color
func setup(width: float, length: float, color: Color = Color(1.0, 0.15, 0.1, 0.28)) -> void:
	corridor_width = width
	corridor_length = length
	if _mesh_instance and _mesh_instance.mesh is QuadMesh:
		(_mesh_instance.mesh as QuadMesh).size = Vector2(corridor_width, corridor_length)
		_mesh_instance.position = Vector3(0, 0.04, -corridor_length * 0.5)
	if _center_line_mesh and _center_line_mesh.mesh is QuadMesh:
		(_center_line_mesh.mesh as QuadMesh).size = Vector2(0.25, corridor_length)
		_center_line_mesh.position = Vector3(0, 0.05, -corridor_length * 0.5)
	if _material:
		_material.albedo_color = color


## Updates the ground anchor position and forward aiming orientation
func update_orientation(origin_pos: Vector3, forward_dir: Vector3) -> void:
	if _is_locked:
		return
	global_position = origin_pos
	# Keep Y slightly grounded
	forward_dir.y = 0.0
	if forward_dir.length_squared() > 0.001:
		var target_yaw := atan2(-forward_dir.x, -forward_dir.z)
		rotation.y = target_yaw


## Sets whether direction is locked (triggers bright locked warning pulse)
func set_locked(locked: bool) -> void:
	_is_locked = locked
	if _is_locked and _material:
		_material.albedo_color = Color(1.0, 0.05, 0.05, 0.65)
		if _center_material:
			_center_material.albedo_color = Color(1.0, 1.0, 0.8, 0.95)


func is_locked() -> bool:
	return _is_locked


## Updates the progress ratio [0.0..1.0] of the wind-up
func set_progress(p: float) -> void:
	fill_progress = clampf(p, 0.0, 1.0)
	if not _is_locked and _material:
		var alpha: float = lerpf(0.20, 0.45, fill_progress)
		_material.albedo_color = Color(1.0, 0.15, 0.1, alpha)


## Dismisses and frees the indicator with a fast fade-out
func dismiss() -> void:
	var tw := create_tween()
	if _material:
		tw.tween_property(_material, "albedo_color:a", 0.0, 0.08)
	tw.tween_callback(queue_free)
