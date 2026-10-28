extends Node3D
## PREVIEW RUN CYCLE HARNESS — R20-I16
##
## Dedicated, isolated visual preview for canonical MechaRig.CLIP_RUN
## (innerframe_run_cycle_clean.glb) on the production MechaBase hierarchy.
##
## Architectural invariants:
##  1. MechaBase controller and MechaAnimation physics processes are silenced
##     so production animation state machines do not override joint rotations.
##  2. FootIK is disabled to prevent inverse kinematics fighting the baked stride.
##  3. Driven pivots are resolved directly via scene node references.
##  4. MechaClipRetarget is explicitly commanded to play MechaRig.CLIP_RUN,
##     bypassing the live sprint_kimodo selection branch.
##  5. Single animation owner: advance_and_apply() is called strictly once per
##     frame in _process().
##  6. Interactive controls: [Space] Pause/Play, [+/-] Speed, [R] Reset, [Esc] Exit.

const DEFAULT_LOADOUT := {
	"head": {"frame": {"id": "frame_head_01", "equipped": true}, "armor": {"id": "line_head", "equipped": true, "path": "res://resources/mech/parts/head/line_head.tres", "slot": "head"}},
	"body": {"frame": {"id": "frame_body_01", "equipped": true}, "armor": {"id": "line_body", "equipped": true, "path": "res://resources/mech/parts/body/line_body.tres", "slot": "body"}},
	"arm_left": {"frame": {"id": "frame_arm_left_01", "equipped": true}, "armor": {"id": "line_arm_left", "equipped": true, "path": "res://resources/mech/parts/arm_left/line_arm_left.tres", "slot": "arm_left"}},
	"arm_right": {"frame": {"id": "frame_arm_right_01", "equipped": true}, "armor": {"id": "line_arm_right", "equipped": true, "path": "res://resources/mech/parts/arm_right/line_arm_right.tres", "slot": "arm_right"}},
	"leg_left": {"frame": {"id": "frame_leg_left_01", "equipped": true}, "armor": {"id": "line_leg_left", "equipped": true, "path": "res://resources/mech/parts/leg_left/line_leg_left.tres", "slot": "leg_left"}},
	"leg_right": {"frame": {"id": "frame_leg_right_01", "equipped": true}, "armor": {"id": "line_leg_right", "equipped": true, "path": "res://resources/mech/parts/leg_right/line_leg_right.tres", "slot": "leg_right"}},
}

var _mecha: CharacterBody3D = null
var _retarget: MechaClipRetarget = null
var _joints: Dictionary = {}
var _orig_body_y: float = 3.841
var _status_label: Label = null

var playback_speed: float = 1.0
var is_paused: bool = false
var elapsed_time: float = 0.0


func _ready() -> void:
	_status_label = get_node_or_null("UI/MarginContainer/Panel/VBoxContainer/StatusLabel")
	_mecha = get_node_or_null("MechaBase")
	if _mecha == null:
		push_error("PreviewRunCycle: MechaBase node not found")
		return

	# 1. Equip modular armor parts via PartMeshManager
	var pmm = _mecha.get_node_or_null("PartMeshManager")
	if pmm and pmm.has_method("refresh_from_loadout"):
		pmm.refresh_from_loadout(DEFAULT_LOADOUT)

	# 2. Silence MechaController physics so it does not apply gravity or velocity
	_mecha.set_physics_process(false)
	_mecha.set_process(false)

	# 3. Silence MechaAnimation physics process to prevent competing procedural idle
	var anim = _mecha.get_node_or_null("MechaAnimation")
	if anim:
		anim.set_physics_process(false)
		anim.set_process(false)

	# 4. Disable FootIKSystem so IK raycasts do not fight the run stride
	var foot_ik = _mecha.get_node_or_null("FootIKSystem")
	if foot_ik and "enabled" in foot_ik:
		foot_ik.enabled = false

	# 5. Build joints dictionary directly from MechaBase pivots
	_joints = _build_preview_joints()
	var body_node: Node3D = _joints.get("body")
	if body_node:
		_orig_body_y = body_node.position.y

	# 6. Resolve MechaClipRetarget and select canonical CLIP_RUN
	if anim and "clip_retarget" in anim and anim.clip_retarget != null:
		_retarget = anim.clip_retarget
	else:
		_retarget = MechaClipRetarget.new()
		add_child(_retarget)

	_retarget.play_clip(MechaRig.CLIP_RUN)
	_update_hud()


func _process(delta: float) -> void:
	if not is_paused and _retarget != null:
		elapsed_time += delta * playback_speed
		_retarget.advance_and_apply(delta * playback_speed, _joints, _orig_body_y)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif event.keycode == KEY_SPACE:
			is_paused = not is_paused
		elif event.keycode == KEY_EQUAL or event.keycode == KEY_PLUS or event.keycode == KEY_KP_ADD:
			playback_speed = minf(playback_speed + 0.25, 3.0)
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			playback_speed = maxf(playback_speed - 0.25, 0.25)
		elif event.keycode == KEY_R:
			playback_speed = 1.0
			is_paused = false


func _build_preview_joints() -> Dictionary:
	var j: Dictionary = {}
	if _mecha == null:
		return j
	j["head"] = _mecha.get_node_or_null("Head")
	j["body"] = _mecha.get_node_or_null("Body")
	j["arm_left"] = _mecha.get_node_or_null("ArmLeft")
	j["arm_right"] = _mecha.get_node_or_null("ArmRight")
	j["forearm_left"] = _mecha.get_node_or_null("ArmLeft/ForearmLeft")
	j["forearm_right"] = _mecha.get_node_or_null("ArmRight/ForearmRight")
	j["leg_left"] = _mecha.get_node_or_null("LegLeft")
	j["leg_right"] = _mecha.get_node_or_null("LegRight")
	j["shin_left"] = _mecha.get_node_or_null("LegLeft/ShinLeft")
	j["shin_right"] = _mecha.get_node_or_null("LegRight/ShinRight")
	j["foot_left"] = _mecha.get_node_or_null("LegLeft/ShinLeft/FootLeft")
	j["foot_right"] = _mecha.get_node_or_null("LegRight/ShinRight/FootRight")
	return j


func _update_hud() -> void:
	if _status_label == null:
		return
	var state_str := "PAUSED" if is_paused else "PLAYING"
	var clip_str := _retarget.get_source_animation_name(MechaRig.CLIP_RUN) if _retarget else "unknown"
	_status_label.text = "Status: %s (%.2fx) | Source Track: \"%s\" | Time: %.1fs" % [state_str, playback_speed, clip_str, elapsed_time]
