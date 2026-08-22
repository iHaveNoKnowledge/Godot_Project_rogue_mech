extends Node3D

## Board patrol marker: chevron ">" arrows that read as enemy fleets on the
## map — red ">" for a grunt fleet, red ">>" for an ace fleet, white ">" for an
## unknown (mercenary) convoy.
## If multiple fleets are traveling together (fleet_count > 1), a camera-facing
## billboard badge ("x2", "x3", etc.) floats at the top-right of the token.

var _arrow: Node3D
var _count_badge: Label3D = null


func setup(fleet: Dictionary) -> void:
	var is_unknown := str(fleet.get("faction", "hostile")) == "unknown"
	var archetype: String = str(fleet.get("archetype", "armored"))
	var aces := int(fleet.get("aces", 0))
	var fleet_count := int(fleet.get("fleet_count", 1))

	var color := BoardArrow.UNKNOWN_WHITE
	var is_double := aces > 0 or archetype == "hunter_killer"

	if not is_unknown:
		match archetype:
			"recon":
				color = BoardArrow.RECON_ORANGE
			"armored":
				color = BoardArrow.ARMORED_RED
			"artillery":
				color = BoardArrow.ARTILLERY_AMBER
			"hunter_killer":
				color = BoardArrow.HUNTER_KILLER_PURPLE
			_:
				color = BoardArrow.HOSTILE_RED

	_arrow = Node3D.new()
	_arrow.set_script(preload("res://scripts/board/board_arrow.gd"))
	_arrow.setup(color, is_double, 1.0, true)
	add_child(_arrow)

	# dir can arrive as Vector2i, an {x, y} dict, or a JSON-flattened String
	var dir := PatrolSystem.normalize_dir(fleet.get("dir"))
	_arrow.face_heading(dir)

	# If multiple fleets travel together as one token, show billboard "xN" badge at top-right
	if fleet_count > 1:
		_count_badge = Label3D.new()
		_count_badge.name = "FleetCountBadge"
		_count_badge.text = "x%d" % fleet_count
		_count_badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_count_badge.no_depth_test = true
		_count_badge.font_size = 40
		_count_badge.outline_size = 10
		_count_badge.outline_modulate = Color.BLACK
		_count_badge.modulate = Color(1.0, 0.88, 0.2)
		_count_badge.position = Vector3(0.55, 0.85, -0.35)
		add_child(_count_badge)
