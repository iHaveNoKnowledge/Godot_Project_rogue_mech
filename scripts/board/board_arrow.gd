class_name BoardArrow
extends Node3D

## Board ">" arrow token: a chevron built from two thin boxes meeting at a tip
## that points +X, so rotating the node around Y aims it at any heading.
## Shared by every unit on the map:
##   - player token:  blue ">"
##   - grunt fleet:   red ">"
##   - ace fleet:     red ">>" (double chevron)
##   - unknown fleet: white ">" (mercenary convoy)
##   - boss:          large purple ">"
## Configure the visuals via setup() BEFORE add_child() so _ready builds the
## right shape, then rotate to face the unit's movement direction.

const PLAYER_BLUE := Color(0.25, 0.55, 1.0)
const HOSTILE_RED := Color(0.9, 0.16, 0.12)
const UNKNOWN_WHITE := Color(0.93, 0.94, 0.97)
const BOSS_PURPLE := Color(0.72, 0.25, 0.95)

var arrow_color: Color = PLAYER_BLUE
var is_double: bool = false
var arrow_scale: float = 1.0
var bob: bool = false

var _bob_timer: float = 0.0
var _base_y: float = 0.0


func setup(c: Color, double_arrow: bool = false, scale_factor: float = 1.0, idle_bob: bool = false) -> void:
	arrow_color = c
	is_double = double_arrow
	arrow_scale = scale_factor
	bob = idle_bob


func _ready() -> void:
	_build()
	_base_y = global_position.y


func _build() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = arrow_color
	mat.emission_enabled = true
	mat.emission = arrow_color
	mat.emission_energy_multiplier = 1.5
	mat.roughness = 0.4

	_add_chevron(mat, 0.0, 1.0, 0.0)
	if is_double:
		# Ace fleets read as ">>": a second, smaller chevron stacked behind-left
		# and slightly higher so both read clearly from the isometric camera.
		_add_chevron(mat, 0.55, 0.6, -0.42)


# One ">" chevron pointing +X: two thin boxes from the back tails to the tip.
# `x_off` shifts the whole chevron back (used for the ace's second arrow).
func _add_chevron(mat: StandardMaterial3D, y_off: float, s: float, x_off: float) -> void:
	var tip := Vector2(0.55 * s, 0.0)
	var tails := [Vector2(-0.28 * s, 0.42 * s), Vector2(-0.28 * s, -0.42 * s)]
	for tail: Vector2 in tails:
		var arm_dir: Vector2 = (tip - tail).normalized()
		var arm_len: float = (tip - tail).length()
		var mid: Vector2 = (tip + tail) * 0.5
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(arm_len, 0.12 * s, 0.15 * s)
		box.mesh = mesh
		box.material_override = mat
		box.position = Vector3(mid.x + x_off, y_off + 0.06 * s, mid.y)
		box.rotation.y = atan2(-arm_dir.y, arm_dir.x)
		add_child(box)


# Faces the arrow toward a board heading (Vector2i, x = east, y = south). The
# chevron's local tip is +X, so heading (1, 0) keeps it pointing east.
func face_heading(heading: Vector2i) -> void:
	rotation.y = -atan2(float(heading.y), float(heading.x))


# Gentle idle bob so patrol/boss markers read as live units on the map.
func _process(delta: float) -> void:
	if not bob:
		return
	_bob_timer += delta * 2.0
	global_position.y = _base_y + sin(_bob_timer) * 0.1
