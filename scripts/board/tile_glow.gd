class_name TileGlow
extends Node3D

## Event-tile beacon: an upright, transparent, glowing cylinder that pulses
## softly, so interactable tiles (event / data-node) read as clickable models
## on the map instead of colored floor plates. Built procedurally so no scene
## file is needed; call setup() before add_child() to pick the glow color.

var glow_color: Color = Color(0.35, 0.85, 1.0)

var _mat: StandardMaterial3D
var _t: float = 0.0


func setup(c: Color) -> void:
	glow_color = c


func _ready() -> void:
	_build()


func _build() -> void:
	var cyl := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 1.6
	cyl.mesh = mesh
	cyl.position.y = 0.8

	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(glow_color.r, glow_color.g, glow_color.b, 0.28)
	_mat.emission_enabled = true
	_mat.emission = glow_color
	_mat.emission_energy_multiplier = 1.4
	cyl.material_override = _mat
	add_child(cyl)


# Slow alpha + glow pulse so the beacon draws the eye without drowning the map.
func _process(delta: float) -> void:
	if _mat == null:
		return
	_t += delta * 1.6
	var pulse := 0.72 + 0.28 * sin(_t)
	_mat.albedo_color.a = 0.28 * pulse
	_mat.emission_energy_multiplier = 1.2 + 0.5 * pulse
