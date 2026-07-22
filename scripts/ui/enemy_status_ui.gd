extends Node3D

@export var viewport_offset: Vector2 = Vector2(0, -80)

var target: Node3D = null
var health_system: Node = null
var label_3d: Label3D = null
var status_meshes: Dictionary = {}

var _color_green: Color = Color(0.2, 0.8, 0.2, 1)
var _color_yellow: Color = Color(0.9, 0.9, 0.2, 1)
var _color_red: Color = Color(0.9, 0.2, 0.2, 1)
var _color_black: Color = Color(0.1, 0.1, 0.1, 1)


func _ready() -> void:
	label_3d = Label3D.new()
	label_3d.font_size = 20
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.no_depth_test = true
	add_child(label_3d)

	_create_status_dots()


func _create_status_dots() -> void:
	var parts = ["body"]
	var spacing = 0.4
	var start_x = -(parts.size() - 1) * spacing / 2.0

	for i in range(parts.size()):
		var part_name = parts[i]
		var dot = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.15
		sphere.height = 0.3
		dot.mesh = sphere

		var mat = StandardMaterial3D.new()
		mat.albedo_color = _color_green
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.no_depth_test = true
		dot.material_override = mat

		dot.position.x = start_x + i * spacing
		dot.position.y = 0.5
		add_child(dot)
		status_meshes[part_name] = dot


func setup_target(enemy: Node3D) -> void:
	target = enemy
	health_system = enemy.get_node_or_null("HealthSystem")


func _process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return

	global_position = target.global_position + Vector3(0, 4.5, 0)
	_update_status()


func _update_status() -> void:
	if health_system == null:
		return

	var total_text = ""
	for part in health_system.parts:
		var part_data = health_system.parts[part]
		var hp_percent = part_data["armor_hp"] / part_data["max_armor"]

		if part in status_meshes:
			var color = _get_hp_color(hp_percent)
			status_meshes[part].material_override.albedo_color = color

		total_text += "%s:%d  " % [part.to_upper(), int(part_data["armor_hp"])]

	label_3d.text = total_text


func _get_hp_color(percent: float) -> Color:
	if percent <= 0.0:
		return _color_black
	elif percent < 0.3:
		return _color_red
	elif percent < 0.7:
		return _color_yellow
	else:
		return _color_green
