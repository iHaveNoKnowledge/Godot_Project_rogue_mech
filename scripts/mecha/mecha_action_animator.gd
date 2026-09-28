class_name MechaActionAnimator
extends Node

## ---------------------------------------------------------------------------
## MECHA ACTION ANIMATOR
##
## Manages keyframed 3D animation clips from Mech_00_Anim.fbx (Melee attack combos,
## shooting recoils, shoulder missile artillery, hit reactions, and death collapses)
## plus ActionForge one-handed sword clips (sword_attack single slash,
## sword_regular_combo 3-hit combo) for MELEE weapons and enemy wind-up strikes.
## Evaluates bone transforms in real-time and blends them smoothly over the base
## procedural locomotion and terrain Foot IK.
## ---------------------------------------------------------------------------

const ANIM_FBX_PATH := "res://download/Mech_00/Char_Anim/Mech_00_Anim.fbx"

# ActionForge one-handed sword clips (in-place, godot-ready GLB).
# sword_attack = single slash (46f @30fps ~1.53s), sword_regular_combo = 3-hit combo (90f @30fps ~3.0s).
const AF_SWORD_ATTACK_PATH := "res://assets/animations/actionforge/sword_attack-inplace-anim-only.glb"
const AF_SWORD_COMBO_PATH := "res://assets/animations/actionforge/sword_regular_combo-inplace-anim-only.glb"
const AF_SWORD_ATTACK := "AF_SwordAttack"
const AF_SWORD_COMBO := "AF_SwordCombo"

# Shared Animation Library cache across all mechas
static var _cached_anim_library: Dictionary = {}
static var _cached_track_maps: Dictionary = {}
static var _initialized_library: bool = false
static var _af_clips_loaded: bool = false

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
		# AF clips load lazily on top of the base library so a retry after a
		# failed first import still picks them up without rebuilding Mech_00.
		if not _af_clips_loaded:
			_load_af_clips()
		return
	_initialized_library = true
	if not ResourceLoader.exists(ANIM_FBX_PATH):
		push_warning("MechaActionAnimator: Anim FBX not found at " + ANIM_FBX_PATH)
	else:
		var loaded_res = load(ANIM_FBX_PATH)
		if loaded_res == null:
			push_warning("MechaActionAnimator: Failed to load anim resource from " + ANIM_FBX_PATH)
		elif loaded_res is AnimationLibrary:
			var lib := loaded_res as AnimationLibrary
			for anim_name in lib.get_animation_list():
				var anim := lib.get_animation(anim_name)
				_cached_anim_library[anim_name] = anim
				_cached_track_maps[anim_name] = _build_track_map(anim)
		elif loaded_res is PackedScene:
			var inst = (loaded_res as PackedScene).instantiate()
			var ap: AnimationPlayer = _find_player_recursive(inst)
			if ap != null:
				var anim_list := ap.get_animation_list()
				for anim_name in anim_list:
					var anim: Animation = ap.get_animation(anim_name)
					_cached_anim_library[anim_name] = anim
					_cached_track_maps[anim_name] = _build_track_map(anim)
			inst.queue_free()
	_load_af_clips()


static func _find_player_recursive(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := _find_player_recursive(c)
		if found != null:
			return found
	return null


## Loads the ActionForge sword clips (GLB PackedScene with a nested
## AnimationPlayer) into the shared library under AF_SWORD_* names.
static func _load_af_clips() -> void:
	if _af_clips_loaded:
		return
	_af_clips_loaded = true
	_load_af_clip(AF_SWORD_ATTACK_PATH, "sword_attack", AF_SWORD_ATTACK)
	_load_af_clip(AF_SWORD_COMBO_PATH, "sword_regular_combo", AF_SWORD_COMBO)


static func _load_af_clip(path: String, src_anim_name: String, cache_name: String) -> void:
	if _cached_anim_library.has(cache_name):
		return
	if not ResourceLoader.exists(path):
		push_warning("MechaActionAnimator: AF clip not found at " + path)
		return
	var res = load(path)
	if res == null or not (res is PackedScene):
		push_warning("MechaActionAnimator: Failed to load AF clip from " + path)
		return
	var inst = (res as PackedScene).instantiate()
	var ap: AnimationPlayer = _find_player_recursive(inst)
	if ap == null:
		push_warning("MechaActionAnimator: No AnimationPlayer in " + path)
		inst.queue_free()
		return
	if not ap.has_animation(src_anim_name):
		# Fall back to the first animation when the GLB was re-exported with a
		# different take name instead of failing silently.
		var anim_list := ap.get_animation_list()
		if anim_list.is_empty():
			inst.queue_free()
			return
		src_anim_name = anim_list[0]
	var anim: Animation = ap.get_animation(src_anim_name)
	_cached_anim_library[cache_name] = anim
	_cached_track_maps[cache_name] = _build_track_map(anim)
	inst.queue_free()


## True when both ActionForge sword clips are cached and drivable.
static func has_af_clips() -> bool:
	_ensure_library_cached()
	return _cached_anim_library.has(AF_SWORD_ATTACK) and _cached_anim_library.has(AF_SWORD_COMBO)


static func _build_track_map(anim: Animation) -> Dictionary:
	var tmap: Dictionary = {}
	for t in range(anim.get_track_count()):
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var path := str(anim.track_get_path(t)).to_lower()
		# --- Mech_00 (Rigify-style) ---
		if "arm_stretch.l" in path or ("shoulder.l" in path and not tmap.has("arm_left")):
			tmap["arm_left"] = t
		elif "forearm_stretch.l" in path or ("arm_twist.l" in path and not tmap.has("forearm_left")):
			tmap["forearm_left"] = t
		elif "arm_stretch.r" in path or ("shoulder.r" in path and not tmap.has("arm_right")):
			tmap["arm_right"] = t
		elif "forearm_stretch.r" in path or ("arm_twist.r" in path and not tmap.has("forearm_right")):
			tmap["forearm_right"] = t
		elif "spine_01" in path and not tmap.has("body"):
			tmap["body"] = t
		elif "thigh_stretch.l" in path:
			tmap["leg_left"] = t
		elif "leg_stretch.l" in path:
			tmap["shin_left"] = t
		elif "thigh_stretch.r" in path:
			tmap["leg_right"] = t
		elif "leg_stretch.r" in path:
			tmap["shin_right"] = t
		# --- ActionForge (UE mannequin-style: upperarm_l, lowerarm_r, thigh_l, calf_r) ---
		elif "upperarm_l" in path and not tmap.has("arm_left"):
			tmap["arm_left"] = t
		elif "lowerarm_l" in path and not tmap.has("forearm_left"):
			tmap["forearm_left"] = t
		elif "upperarm_r" in path and not tmap.has("arm_right"):
			tmap["arm_right"] = t
		elif "lowerarm_r" in path and not tmap.has("forearm_right"):
			tmap["forearm_right"] = t
		elif ("spine_02" in path or "spine_03" in path) and not tmap.has("body"):
			tmap["body"] = t
		elif "thigh_l" in path and not tmap.has("leg_left"):
			tmap["leg_left"] = t
		elif ("calf_l" in path) and not tmap.has("shin_left"):
			tmap["shin_left"] = t
		elif "thigh_r" in path and not tmap.has("leg_right"):
			tmap["leg_right"] = t
		elif ("calf_r" in path) and not tmap.has("shin_right"):
			tmap["shin_right"] = t
		# Head last: "head" also matches nothing else ("hand" has no "head"),
		# neck_01 is the fallback when the Head bone track is missing.
		elif (path.ends_with(":head") or (":head" in path) or path.ends_with("head")) and not tmap.has("head"):
			tmap["head"] = t
		elif "neck_01" in path and not tmap.has("head"):
			tmap["head"] = t
		elif "head" in path and "hand" not in path and not tmap.has("head"):
			tmap["head"] = t
	return tmap


# Custom dynamic pacing for enemy melee wind-up vs strike acceleration
var is_custom_pacing: bool = false
var windup_fraction: float = 0.35
var windup_speed: float = 0.60
var strike_speed: float = 2.40


class ShootChannel:
	var anim_name: String = ""
	var anim_time: float = 0.0
	var anim_length: float = 0.0
	var anim_speed: float = 2.2
	var blend_weight: float = 0.0
	var fade_in_time: float = 0.02
	var fade_out_time: float = 0.12
	var is_active: bool = false
	var hand: String = "right"


var shoot_channel_left: ShootChannel = ShootChannel.new()
var shoot_channel_right: ShootChannel = ShootChannel.new()


## Plays an action clip by name (full-body or primary channel)
func play_action(anim_name: String, speed: float = 1.0, fade_in: float = 0.08, fade_out: float = 0.15) -> bool:
	_ensure_library_cached()
	var anim: Animation = _cached_anim_library.get(anim_name, null)
	if anim == null:
		return false

	current_anim_name = anim_name
	anim_time = 0.0
	anim_length = anim.length
	anim_speed = speed
	is_custom_pacing = false
	fade_in_time = maxf(fade_in, 0.01)
	fade_out_time = maxf(fade_out, 0.01)
	blend_weight = 0.0
	is_active = true
	return true


## Plays Enemy Melee Attack 1 with deliberate wind-up (ง้าง) accelerating into a fast forward slash
func play_enemy_melee(hand: String = "right", telegraph_dur: float = 0.5) -> bool:
	var side_suffix := "_L" if hand == "left" else "_R"
	var clip_name := "Mech_Attack1%s" % side_suffix

	_ensure_library_cached()
	var anim: Animation = _cached_anim_library.get(clip_name, null)
	if anim == null:
		clip_name = "Mech_Attack1_R"
		anim = _cached_anim_library.get(clip_name, null)
		if anim == null:
			return false

	current_anim_name = clip_name
	anim_time = 0.0
	anim_length = anim.length
	is_custom_pacing = true
	windup_fraction = 0.35

	# Scale windup speed so the windup pose spans the telegraph window cleanly
	var windup_clip_time := anim_length * windup_fraction
	if telegraph_dur > 0.05:
		windup_speed = windup_clip_time / telegraph_dur
	else:
		windup_speed = 0.65
	strike_speed = 2.40

	fade_in_time = 0.06
	fade_out_time = 0.15
	blend_weight = 0.0
	is_active = true
	return true


## Plays the ActionForge one-handed sword combo (มือเดียว):
## step 1 = single slash (sword_attack), step 2-3 = full 3-hit combo clip.
## Returns false when the AF clips are missing so callers can fall back to Mech_00.
func play_af_melee(hand: String = "right", forced_combo_step: int = 0) -> bool:
	_ensure_library_cached()
	var now := Time.get_ticks_msec()
	if forced_combo_step > 0:
		combo_index = clampi(forced_combo_step, 1, 3)
	elif now - last_attack_time_ms < COMBO_WINDOW_MS:
		combo_index = (combo_index % 3) + 1
	else:
		combo_index = 1
	last_attack_time_ms = now
	# AF clips are authored right-handed; the same take drives either hand.
	var clip_name := AF_SWORD_ATTACK if combo_index == 1 else AF_SWORD_COMBO
	if not _cached_anim_library.has(clip_name):
		return false
	# Single slash is snappy, the full combo plays at authored speed.
	var play_speed := 1.15 if combo_index == 1 else 1.0
	return play_action(clip_name, play_speed, 0.06, 0.14)


## Plays the ActionForge single slash with deliberate wind-up (ง้าง) for enemies:
## the wind-up pose spans the telegraph window, then accelerates into the strike.
## Returns false when the AF clip is missing so callers can fall back to Mech_00.
func play_enemy_af_melee(hand: String = "right", telegraph_dur: float = 0.5) -> bool:
	_ensure_library_cached()
	var anim: Animation = _cached_anim_library.get(AF_SWORD_ATTACK, null)
	if anim == null:
		return false
	current_anim_name = AF_SWORD_ATTACK
	anim_time = 0.0
	anim_length = anim.length
	is_custom_pacing = true
	# sword_attack: first ~40% raises the blade (wind-up), rest is the slash.
	windup_fraction = 0.40
	var windup_clip_time := anim_length * windup_fraction
	if telegraph_dur > 0.05:
		windup_speed = windup_clip_time / telegraph_dur
	else:
		windup_speed = 0.65
	strike_speed = 2.40
	fade_in_time = 0.06
	fade_out_time = 0.15
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


## Plays Shooting Recoil on the isolated firing arm without affecting the other arm
func play_shoot(hand: String, is_heavy: bool = false) -> void:
	_ensure_library_cached()
	var channel := shoot_channel_left if hand == "left" else shoot_channel_right
	var side_suffix := "_L" if hand == "left" else "_R"
	var clip_name := "Mech_Shoot2%s" % side_suffix if is_heavy else "Mech_Shoot%s" % side_suffix

	var anim: Animation = _cached_anim_library.get(clip_name, null)
	if anim == null:
		clip_name = "Mech_Shoot%s" % side_suffix
		anim = _cached_anim_library.get(clip_name, null)
		if anim == null:
			return

	channel.anim_name = clip_name
	channel.anim_time = 0.0
	channel.anim_length = anim.length
	channel.anim_speed = 2.4 if not is_heavy else 1.8
	channel.fade_in_time = 0.02
	channel.fade_out_time = 0.12 if not is_heavy else 0.18
	channel.blend_weight = 0.0
	channel.is_active = true
	channel.hand = hand


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
	return (is_active and blend_weight > 0.001) or shoot_channel_left.is_active or shoot_channel_right.is_active


## Advances playback timelines and calculates crossfade envelopes
func update(delta: float) -> void:
	# 1. Main Action Channel
	if is_active:
		if is_custom_pacing:
			var norm_pos := anim_time / maxf(anim_length, 0.001)
			var current_step_speed := windup_speed if norm_pos < windup_fraction else strike_speed
			anim_time += delta * current_step_speed
		else:
			anim_time += delta * anim_speed

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
	else:
		blend_weight = move_toward(blend_weight, 0.0, delta / 0.15)

	# 2. Per-Hand Shoot Channels
	_update_shoot_channel(shoot_channel_left, delta)
	_update_shoot_channel(shoot_channel_right, delta)


func _update_shoot_channel(channel: ShootChannel, delta: float) -> void:
	if not channel.is_active:
		channel.blend_weight = move_toward(channel.blend_weight, 0.0, delta / 0.10)
		return

	channel.anim_time += delta * channel.anim_speed

	if channel.anim_time < channel.fade_in_time:
		channel.blend_weight = clampf(channel.anim_time / channel.fade_in_time, 0.0, 1.0)
	elif channel.anim_time >= channel.anim_length - channel.fade_out_time:
		var remaining := maxf(channel.anim_length - channel.anim_time, 0.0)
		channel.blend_weight = clampf(remaining / channel.fade_out_time, 0.0, 1.0)
	else:
		channel.blend_weight = 1.0

	if channel.anim_time >= channel.anim_length:
		channel.is_active = false
		channel.blend_weight = 0.0


## Blends keyframe rotations onto the mech's joints dictionary
func apply_to_joints(joints: Dictionary, master_weight: float = 1.0) -> void:
	# 1. Main action animation (Melee, Die, GetHit, Shoulder)
	var effective_main := blend_weight * master_weight
	if effective_main > 0.001:
		var anim: Animation = _cached_anim_library.get(current_anim_name, null)
		var tmap: Dictionary = _cached_track_maps.get(current_anim_name, {})
		if anim != null and not tmap.is_empty():
			var sample_t := clampf(anim_time, 0.0, anim_length)
			for joint_key in tmap:
				var track_idx: int = tmap[joint_key]
				var node: Node3D = joints.get(joint_key + "_mesh", null)
				if node == null:
					node = joints.get(joint_key, null)
				if node == null or not is_instance_valid(node):
					continue

				var q: Quaternion = anim.rotation_track_interpolate(track_idx, sample_t)
				var target_euler: Vector3 = q.get_euler()
				var blend := effective_main
				node.rotation.x = lerp_angle(node.rotation.x, target_euler.x, blend)
				if joint_key in ["arm_left", "arm_right", "forearm_left", "forearm_right", "body"]:
					node.rotation.y = lerp_angle(node.rotation.y, target_euler.y, blend)
					node.rotation.z = lerp_angle(node.rotation.z, target_euler.z, blend)

	# 2. Left Shoot Recoil (Isolated to left arm + torso kick)
	_apply_shoot_channel_to_joints(shoot_channel_left, joints, master_weight)

	# 3. Right Shoot Recoil (Isolated to right arm + torso kick)
	_apply_shoot_channel_to_joints(shoot_channel_right, joints, master_weight)


func _apply_shoot_channel_to_joints(channel: ShootChannel, joints: Dictionary, master_weight: float) -> void:
	var effective_weight := channel.blend_weight * master_weight
	if effective_weight <= 0.001:
		return

	var anim: Animation = _cached_anim_library.get(channel.anim_name, null)
	var tmap: Dictionary = _cached_track_maps.get(channel.anim_name, {})
	if anim == null or tmap.is_empty():
		return

	var sample_t := clampf(channel.anim_time, 0.0, channel.anim_length)
	var is_left := (channel.hand == "left")

	# Recoil kickback angle computed from keyframe curve
	# Only affect the specific shooting arm joints + subtle body kick
	var arm_key := "arm_left" if is_left else "arm_right"
	var forearm_key := "forearm_left" if is_left else "forearm_right"

	if tmap.has(arm_key):
		var node: Node3D = joints.get(arm_key + "_mesh", null)
		if node == null:
			node = joints.get(arm_key, null)
		if node != null and is_instance_valid(node):
			var q: Quaternion = anim.rotation_track_interpolate(tmap[arm_key], sample_t)
			var target_euler: Vector3 = q.get_euler()
			# Additive recoil pitch layered over current aim angle
			node.rotation.x = lerp_angle(node.rotation.x, node.rotation.x + target_euler.x * 0.45, effective_weight)
			node.rotation.y = lerp_angle(node.rotation.y, 0.0, effective_weight)
			node.rotation.z = lerp_angle(node.rotation.z, 0.0, effective_weight)

	if tmap.has(forearm_key):
		var node: Node3D = joints.get(forearm_key + "_mesh", null)
		if node == null:
			node = joints.get(forearm_key, null)
		if node != null and is_instance_valid(node):
			var q: Quaternion = anim.rotation_track_interpolate(tmap[forearm_key], sample_t)
			var target_euler: Vector3 = q.get_euler()
			node.rotation.x = lerp_angle(node.rotation.x, node.rotation.x + target_euler.x * 0.35, effective_weight)
			node.rotation.y = lerp_angle(node.rotation.y, 0.0, effective_weight)
			node.rotation.z = lerp_angle(node.rotation.z, 0.0, effective_weight)

	# Subtle chest/torso recoil kick
	if tmap.has("body"):
		var body_node: Node3D = joints.get("body_mesh", null)
		if body_node == null:
			body_node = joints.get("body", null)
		if body_node != null and is_instance_valid(body_node):
			var q_body: Quaternion = anim.rotation_track_interpolate(tmap["body"], sample_t)
			var body_euler: Vector3 = q_body.get_euler()
			body_node.rotation.x = lerp_angle(body_node.rotation.x, body_node.rotation.x + body_euler.x * 0.25, effective_weight)
