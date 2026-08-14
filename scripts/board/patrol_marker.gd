extends Node3D

## 3D arrow marker that sits on a board tile to show a roaming enemy fleet.
## A single red arrow = grunt fleet, two stacked red arrows = ace fleet, and a
## single white arrow = unknown fleet (talk encounter: fight or recruit).
## Built procedurally (cone head + thin shaft) so no scene file is needed.

const HOSTILE_RED := Color(0.9, 0.14, 0.1)
const UNKNOWN_WHITE := Color(0.93, 0.94, 0.97)

var _bob_timer: float = 0.0
var _base_y: float = 0.0


# fleet: patrol dictionary with `aces` and `faction` ("hostile" / "unknown").
func setup(fleet: Dictionary) -> void:
	var is_unknown := str(fleet.get("faction", "hostile")) == "unknown"
	var color := UNKNOWN_WHITE if is_unknown else HOSTILE_RED
	var aces := int(fleet.get("aces", 0))

	# Unknown fleets are a single white arrow; aces stack two arrows.
	_add_arrow(color, 0.0)
	if not is_unknown and aces > 0:
		_add_arrow(color, 1.15)
	_base_y = global_position.y


func _add_arrow(color: Color, y_offset: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	mat.roughness = 0.4

	# Arrowhead: a cone pointing up.
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.55
	cone.height = 1.0
	head.mesh = cone
	head.position = Vector3(0, y_offset + 0.75, 0)
	head.material_override = mat
	add_child(head)

	# Shaft: a thin cylinder under the head.
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.13
	cyl.bottom_radius = 0.13
	cyl.height = 0.55
	shaft.mesh = cyl
	shaft.position = Vector3(0, y_offset + 0.1, 0)
	shaft.material_override = mat
	add_child(shaft)


# Gentle idle bob so the marker reads as a live fleet on the map.
func _process(delta: float) -> void:
	_bob_timer += delta * 2.0
	global_position.y = _base_y + sin(_bob_timer) * 0.1