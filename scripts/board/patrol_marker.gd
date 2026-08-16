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

	# dir can arrive as Vector2i, an {x, y} dict, or a JSON-flattened String
	# from an older save — normalize before aiming the arrow, otherwise a
	# broken dir would crash setup() and the fleet never got its marker.
	var dir := PatrolSystem.normalize_dir(fleet.get("dir"))
	_arrow.face_heading(dir)
