extends Node3D

## Board patrol marker: chevron ">" arrows that read as enemy fleets on the
## map — red ">" for a grunt fleet, red ">>" for an ace fleet, white ">" for an
## unknown (mercenary) convoy. The arrow rotates to face the fleet's last
## movement heading so patrols visibly track where they're going.

var _arrow: Node3D


# fleet: patrol dictionary with `aces`, `faction` ("hostile" / "unknown") and
# `dir` (Vector2i heading, x = east, y = south). The arrow bobs on its own.
func setup(fleet: Dictionary) -> void:
	var is_unknown := str(fleet.get("faction", "hostile")) == "unknown"
	var color := BoardArrow.UNKNOWN_WHITE if is_unknown else BoardArrow.HOSTILE_RED
	var aces := int(fleet.get("aces", 0))

	_arrow = Node3D.new()
	_arrow.set_script(preload("res://scripts/board/board_arrow.gd"))
	_arrow.setup(color, aces > 0, 1.0, true)
	add_child(_arrow)

	var dir: Vector2i = fleet.get("dir", Vector2i(1, 0))
	_arrow.face_heading(dir)
