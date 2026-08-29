class_name MechaActionAnimator
extends Node

## ---------------------------------------------------------------------------
## MECHA ACTION ANIMATOR
##
## Manages keyframed 3D animation clips from Mech_00_Anim.fbx (Melee attack combos,
## shooting recoils, shoulder missile artillery, hit reactions, and death collapses).
## Evaluates bone transforms in real-time and blends them smoothly over the base
## procedural locomotion and terrain Foot IK.
## ---------------------------------------------------------------------------

const ANIM_FBX_PATH := "res://download/Mech_00/Char_Anim/Mech_00_Anim.fbx"

# Shared Animation Library cache across all mechas
static var _cached_anim_library: Dictionary = {}
static var _cached_track_maps: Dictionary = {}
static var _initialized_library: bool = false

# Current action playback state
var current_anim_name: String = ""
var anim_time: float = 0.0
var anim_length: float = 0.0
var anim_speed: float = 1.0
var blend_weight: float = 0.0
var fade_in_time: float = 0.10
var fade_out_time: float = 0.15
var is_active: bool = false

# Combo tracking for melee
var combo_index: int = 1
var last_attack_time_ms: int = 0
const COMBO_WINDOW_MS: int = 1400


func _ready() -> void:
	_ensure_library_cached()


static func _ensure_library_cached() -> void:
	if _initialized_library:
		return
	_initialized_library = true
	if not ResourceLoader.exists(ANIM_FBX_PATH):
		push_warning("MechaActionAnimator: Anim FBX not found at " + ANIM_FBX_PATH)
		return

	var anim_scene = load(ANIM_FBX_PATH)
	if anim_scene == null:
		push_warning("MechaActionAnimator: Failed to load anim scene from " + ANIM_FBX_PATH)
		return

	var inst = anim_scene.instantiate()
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap == null:
		inst.queue_free()
		return

	var anim_list := ap.get_animation_list()
	for anim_name in anim_list:
		var anim: Animation = ap.get_animation(anim_name)
		_cached_anim_library[anim_name] = anim
		_cached_track_maps[anim_name] = _build_track_map(anim)

	inst.queue_free()


static func _build_track_map(anim: Animation) -> Dictionary:
	var tmap: Dictionary = {}
	for t in range(anim.get_track_count()):
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var path := str(anim.track_get_path(t)).to_lower()
		if "arm_stretch.l" in path or ("shoulder.l" in path and not tmap.has("arm_left")):
			tmap["arm_left"] = t
		elif "forearm_stretch.l" in path or ("arm_twist.l" in path and not tmap.has("forearm_left")):
			tmap["forearm_left"] = t
		elif "arm_stretch.r" in path or ("shoulder.r" in path and not tmap.has("arm_right")):
			tmap["arm_right"] = t
		elif "forearm_stretch.r" in path or ("arm_twist.r" in path and not tmap.has("forearm_right")):
			tmap["forearm_right"] = t
		elif "spine_01" in path:
			tmap["body"] = t
		elif "head" in path:
			tmap["head"] = t
		elif "thigh_stretch.l" in path:
			tmap["leg_left"] = t
		elif "leg_stretch.l" in path:
			tmap["shin_left"] = t
		elif "thigh_stretch.r" in path:
			tmap["leg_right"] = t
		elif "leg_stretch.r" in path:
			tmap["shin_right"] = t
	return tmap


## Plays an action clip by name
func play_action(anim_name: String, speed: float = 1.0, fade_in: float = 0.08, fade_out: float = 0.15) -> bool:
	_ensure_library_cached()
	var anim: Animation = _cached_anim_library.get(anim_name, null)
	if anim == null:
		return false

	current_anim_name = anim_name
	anim_time = 0.0
	anim_length = anim.length
	anim_speed = speed
	fade_in_time = maxf(fade_in, 0.01)
	fade_out_time = maxf(fade_out, 0.01)
	blend_weight = 0.0
	is_active = true
	return true


## Plays Melee Combo Attack 1 -> 2 -> 3 based on hand and timing
func play_melee(hand: String, forced_combo_step: int = 0) -> void:
	var now := Time.get_ticks_msec()
	if forced_combo_step > 0:
		combo_index = clampi(forced_combo_step, 1, 3)
	elif now - last_attack_time_ms < COMBO_WINDOW_MS:
		combo_index = (combo_index % 3) + 1
	else:
		combo_index = 1
	last_attack_time_ms = now

	var side_suffix := "_L" if hand == "left" else "_R"
	var clip_name := "Mech_Attack%d%s" % [combo_index, side_suffix]
	
	# Attack 1 & 2 are fast fluid strikes; Attack 3 is a heavy smash
	var play_speed := 1.75 if combo_index < 3 else 1.35
	play_action(clip_name, play_speed, 0.06, 0.14)


## Plays Shooting Recoil and Weapon Bracing
func play_shoot(hand: String, is_heavy: bool = false) -> void:
	var side_suffix := "_L" if hand == "left" else "_R"
	var clip_name := "Mech_Shoot2%s" % side_suffix if is_heavy else "Mech_Shoot%s" % side_suffix
	var speed := 2.2 if not is_heavy else 1.6
	play_action(clip_name, speed, 0.04, 0.12)


## Plays Shoulder Cannon / Missile Pod Barrage Launch
func play_shoulder_shoot(variant: int = 1) -> void:
	var clip_name := "Mech_ShoulderShoot%d" % clampi(variant, 1, 2)
	play_action(clip_name, 1.6, 0.08, 0.15)


## Plays Heavy Hit Flinch
func play_get_hit() -> void:
	play_action("Mech_GetHit", 1.8, 0.04, 0.12)


## Plays Core Breach Death Collapse
func play_die() -> void:
	play_action("Mech_Die", 1.0, 0.12, 0.30)


func is_playing() -> bool:
	return is_active and blend_weight > 0.001


## Advances playback timeline and calculates crossfade envelope
func update(delta: float) -> void:
	if not is_active:
		blend_weight = move_toward(blend_weight, 0.0, delta / 0.15)
		return

	anim_time += delta * anim_speed

	# Calculate fade-in and fade-out envelope
	if anim_time < fade_in_time:
		blend_weight = clampf(anim_time / fade_in_time, 0.0, 1.0)
	elif anim_time >= anim_length - fade_out_time:
		var remaining := maxf(anim_length - anim_time, 0.0)
		blend_weight = clampf(remaining / fade_out_time, 0.0, 1.0)
	else:
		blend_weight = 1.0

	if anim_time >= anim_length:
		is_active = false
		blend_weight = 0.0


## Blends keyframe rotations onto the mech's joints dictionary
func apply_to_joints(joints: Dictionary, master_weight: float = 1.0) -> void:
	var effective_weight := blend_weight * master_weight
	if effective_weight <= 0.001:
		return

	var anim: Animation = _cached_anim_library.get(current_anim_name, null)
	var tmap: Dictionary = _cached_track_maps.get(current_anim_name, {})
	if anim == null or tmap.is_empty():
		return

	var sample_t := clampf(anim_time, 0.0, anim_length)

	# Joint mapping dictionary
	for joint_key in tmap:
		var track_idx: int = tmap[joint_key]
		var node: Node3D = joints.get(joint_key + "_mesh", null)
		if node == null:
			node = joints.get(joint_key, null)
		if node == null or not is_instance_valid(node):
			continue

		var q: Quaternion = anim.rotation_track_interpolate(track_idx, sample_t)
		var target_euler: Vector3 = q.get_euler()

		# Upper-body actions blend naturally; clamp extremes for stability
		var blend := effective_weight
		node.rotation.x = lerp_angle(node.rotation.x, target_euler.x, blend)
		if joint_key in ["arm_left", "arm_right", "forearm_left", "forearm_right", "body"]:
			node.rotation.y = lerp_angle(node.rotation.y, target_euler.y, blend)
			node.rotation.z = lerp_angle(node.rotation.z, target_euler.z, blend)
