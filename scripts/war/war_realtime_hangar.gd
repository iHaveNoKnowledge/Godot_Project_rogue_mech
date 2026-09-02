extends Area3D
class_name WarRealtimeHangar

## Realtime Hangar at Main Base / ForwardBase / Carrier — overlay, no scene cut (per PLAN.md 7.5)
## Godot 4.6: uses CanvasLayer overlay, DayNight modulates light + hand brightness

var _overlay: CanvasLayer = null
var _daynight: Node = null


var _inside_bodies: Array[Node] = []

func _ready() -> void:
	add_to_group("war_hangar")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(7.5, 6.0, 9.5)
	col.shape = shape
	col.position = Vector3(0, 3.0, 0)
	add_child(col)
	var lbl = Label3D.new()
	lbl.text = "HANGAR GATE\n[F] CUSTOMIZE (Realtime) — Walk Valkren In"
	lbl.font_size = 20
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0, 4.2, 4.8)
	add_child(lbl)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("mecha") or body.is_in_group("pilot"):
		if not _inside_bodies.has(body):
			_inside_bodies.append(body)
		_update_prompt(true)

func _on_body_exited(body: Node) -> void:
	_inside_bodies.erase(body)
	if _inside_bodies.is_empty():
		_update_prompt(false)

func _update_prompt(inside: bool) -> void:
	if inside:
		EventBus.interaction_prompt_updated.emit("[F] CUSTOMIZE — Hangar", true)
	else:
		EventBus.interaction_prompt_updated.emit("", false)

func _process(_delta: float) -> void:
	if _inside_bodies.is_empty():
		return
	# Poll F while inside — body_entered alone misses the press timing
	if Input.is_action_just_pressed("interact"):
		var opener: Node = null
		for b in _inside_bodies:
			if is_instance_valid(b):
				opener = b
				break
		if opener:
			_open_hangar(opener)


func _open_hangar(opener: Node) -> void:
	if _overlay and is_instance_valid(_overlay):
		return

	# If opener is a pilot, find their current vehicle if boarded
	var target_mech: Node = opener
	if opener is CharacterBody3D and "current_vehicle" in opener and opener.current_vehicle != null:
		target_mech = opener.current_vehicle

	var hangar_scene = load("res://scenes/ui/hangar_ui.tscn")
	if hangar_scene:
		var hangar_ui = hangar_scene.instantiate()
		if hangar_ui.has_method("setup_realtime_mode"):
			hangar_ui.setup_realtime_mode(target_mech)
		_overlay = hangar_ui
		add_child(hangar_ui)
		hangar_ui.tree_exited.connect(func():
			_overlay = null
			_update_prompt(not _inside_bodies.is_empty())
		)
	_apply_daynight()

func _close_hangar() -> void:
	if _overlay and is_instance_valid(_overlay):
		if _overlay.has_method("close_realtime_hangar"):
			_overlay.close_realtime_hangar()
		else:
			_overlay.queue_free()
		_overlay = null
	EventBus.interaction_prompt_updated.emit("", false)
	# Restore mouse capture for battlefield combat
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		_close_hangar()


func _apply_daynight() -> void:
	var env = get_tree().get_first_node_in_group("war_world")
	if env == null:
		return
	# Placeholder: lerp DirectionalLight energy 0.6 (night) to 1.2 (day) via DayNightSystem time_hour
	var hour = 12.0
	if GlobalData.board and "time_hour" in GlobalData.board:
		hour = float(GlobalData.board.time_hour)
	var is_day = hour >= 6.0 and hour < 18.0
	var light = get_tree().get_first_node_in_group("war_sun")
	if light is DirectionalLight3D:
		(light as DirectionalLight3D).light_energy = 1.2 if is_day else 0.45
