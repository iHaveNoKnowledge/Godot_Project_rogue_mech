## PILOT SHOWCASE — plays every kit clip in a loop on screen:
## idle -> walk -> run -> reload -> shoot, with a fixed TPS-ish camera,
## ground plane and light. Launch:
##   Godot_v4.6.2-stable_win64.exe --path . test/unit/pilot_showcase.tscn

extends Node

const KIT_PATH := "res://scenes/pilot/pilot_pistol_kit.glb"
const SEQUENCE := [
	["pistol_idle", 3.0, "IDLE: gun-ready stance + breathing sway"],
	["pilot_walk", 4.0, "WALK: legs stride, hands keep the pistol grip"],
	["pilot_run", 4.0, "RUN: wide strides + forward lean"],
	["pilot_strafe_bwd", 3.0, "BACKPEDAL: backward stride, torso leans back"],
	["pilot_strafe_l", 3.0, "SIDESTEP LEFT: crossing step, torso square to aim"],
	["pilot_strafe_r", 3.0, "SIDESTEP RIGHT: crossing step, torso square to aim"],
	["pilot_jump", 1.6, "JUMP: crouch -> extend -> tuck -> land"],
	["pistol_reload", 2.0, "RELOAD: left hand reaches for the mag"],
	["pistol_shoot", 1.2, "SHOOT: recoil kick"],
]

var _player: AnimationPlayer
var _label: Label
var _idx := -1
var _t := 0.0


func _ready() -> void:
	var packed: PackedScene = load(KIT_PATH)
	var kit: Node = packed.instantiate()
	add_child(kit)
	kit.rotation.y = PI  # face the camera (-Z toward viewer like in-game TPS)
	_player = _find_player(kit)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10, 10)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, 0, 0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.25, 0.27, 0.3)
	fmat.roughness = 0.9
	floor_mesh.set_surface_override_material(0, fmat)
	add_child(floor_mesh)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.4
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.6)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.35, 3.1)
	cam.rotation_degrees = Vector3(-8, 0, 0)
	cam.fov = 45
	add_child(cam)
	cam.make_current()

	var ui := CanvasLayer.new()
	add_child(ui)
	_label = Label.new()
	_label.position = Vector3(0, 0, 0).normalized() * 0 + Vector2(24, 20)
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.5))
	ui.add_child(_label)

	var hint := Label.new()
	hint.text = "pilot showcase - ESC to quit"
	hint.position = Vector2(24, 60)
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	ui.add_child(hint)
	_next()


func _process(delta: float) -> void:
	if _player == null or _idx < 0:
		return
	_t += delta
	var entry: Array = SEQUENCE[_idx]
	if _t >= float(entry[1]):
		_next()
	else:
		var pos: float = _player.current_animation_position
		_label.text = "%s   [%s %.1fs/%.1fs]" % [entry[2], _player.current_animation, pos, float(entry[1])]


func _next() -> void:
	_idx = (_idx + 1) % SEQUENCE.size()
	_t = 0.0
	var clip: String = SEQUENCE[_idx][0]
	var a: Animation = _player.get_animation(clip)
	a.loop_mode = Animation.LOOP_LINEAR if clip != "pilot_jump" else Animation.LOOP_NONE
	_player.play(clip)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_player(c)
		if f != null:
			return f
	return null
