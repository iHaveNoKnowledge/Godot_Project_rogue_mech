extends Node3D

## Board patrol marker: 3D Fleet Commander model that represents enemy fleets
## on the tactical board grid, styled to match the fleet's archetype
## (Armored, Recon, Artillery, Hunter-Killer, Mercenary).
##
## If multiple fleets are traveling together (fleet_count > 1), a camera-facing
## billboard badge ("x2", "x3", etc.) floats at the top-right of the token.

const BoardUnit3D = preload("res://scripts/board/board_unit_3d.gd")

var _unit: Node3D
var _count_badge: Label3D = null
var fleet_data: Dictionary = {}


func setup(fleet: Dictionary) -> void:
	fleet_data = fleet
	var fleet_count := int(fleet.get("fleet_count", 1))

	_unit = BoardUnit3D.new()
	_unit.name = "CommanderUnit3D"
	_unit.setup_commander(fleet)
	add_child(_unit)

	# dir can arrive as Vector2i, an {x, y} dict, or a JSON-flattened String
	var dir := PatrolSystem.normalize_dir(fleet.get("dir"))
	_unit.face_heading(dir, true)

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
		_count_badge.position = Vector3(0.70, 2.3, 0.0)
		add_child(_count_badge)


func face_heading(heading: Vector2i, immediate: bool = false) -> void:
	if _unit:
		_unit.face_heading(heading, immediate)


func play_idle() -> void:
	if _unit:
		_unit.play_idle()


func play_run() -> void:
	if _unit:
		_unit.play_run()


func play_move() -> void:
	if _unit:
		_unit.play_move()


func stop_move() -> void:
	if _unit:
		_unit.stop_move()
