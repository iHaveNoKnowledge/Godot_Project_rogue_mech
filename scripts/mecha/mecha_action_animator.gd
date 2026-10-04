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

# ── Authoritative melee lifecycle ──────────────────────────────────────────
# One attack input = one attack_id. Damage is NEVER dealt by the play call;
# it fires only via poll_strike(), which crosses strike_times measured from
# the clip's own weapon-arm motion (peak forward angular velocity = visual
# contact). Restarting a swing (combo chain) retires the previous attack_id
# and its pending hit can never fire afterwards: 1 swing = strikes of THIS
# swing only, 1 completion exactly once.
var attack_id: int = 0
var strike_times: Array = []
var _strike_idx: int = 0
var _pending_strikes: int = 0
var _completed_pending: bool = false

# ── Melee retarget mode ────────────────────────────────────────────────────
# Source clips (UE-mannequin AF takes, Rigify Mech_00 takes) rest in a
# different pose than the game pivots (AF upperarm_r rests at (-62,1,1)deg,
# thigh_r at (-46,18,-20)deg — measured on the GLB). Copying clip eulers
# absolutely therefore snaps limbs into alien poses (writhe + stray leg
# lifts). Melee plays instead apply REST-RELATIVE deltas, and touch only
# the upper body: legs stay on base locomotion per the weapon-layer
# architecture. Non-melee actions (die/gethit/shoot) keep legacy behavior.
var melee_mode: bool = false
var _rest_euler: Dictionary = {}
var _rest_quat: Dictionary = {}
const MELEE_UPPER_KEYS: Array = [
	"arm_left", "arm_right", "forearm_left", "forearm_right", "body", "head",
]

# Clips that count as melee attacks (everything else = action/recoil/death).
const MELEE_CLIP_PREFIXES: Array = ["Mech_Attack"]


func _is_melee_clip(clip_name: String) -> bool:
	if clip_name == AF_SWORD_ATTACK or clip_name == AF_SWORD_COMBO:
		return true
	for prefix in MELEE_CLIP_PREFIXES:
		if clip_name.begins_with(prefix):
			return true
	return false


## True while a melee swing owns the attack lifecycle (windup through
## recovery, until the clip finishes). Base locomotion keeps driving legs;
## the swing blend (see apply_to_joints) owns the attack bones meanwhile.
func is_melee_active() -> bool:
	return is_active and _is_melee_clip(current_anim_name)


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
		# Wrist snap: hand tracks merge into their forearm (below) — the game
		# rig has no hand pivots, and the snap is the most visible part of a
		# slash. Matched before the head rules ("hand" never matches "head").
		elif ("hand_r" in path or "hand.r" in path) and not tmap.has("hand_right"):
			tmap["hand_right"] = t
		elif ("hand_l" in path or "hand.l" in path) and not tmap.has("hand_left"):
			tmap["hand_left"] = t
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
	melee_mode = false
	_begin_attack_lifecycle(anim_name)
	return true


## (Re)starts lifecycle bookkeeping for a newly played action. Called by
## play_action so every start — including combo-chain restarts — retires the
## previous attack: pending strikes/completions of the old swing vanish.
func _begin_attack_lifecycle(anim_name: String) -> void:
	_strike_idx = 0
	_pending_strikes = 0
	_completed_pending = false
	strike_times = _compute_strike_times(anim_name)
	# Rest pose per mapped joint (track value at clip start): melee deltas
	# are measured against this so foreign-rested takes retarget cleanly.
	_rest_euler.clear()
	_rest_quat.clear()
	var anim: Animation = _cached_anim_library.get(anim_name, null)
	var tmap: Dictionary = _cached_track_maps.get(anim_name, {})
	if anim != null:
		for joint_key in tmap:
			var q: Quaternion = anim.rotation_track_interpolate(int(tmap[joint_key]), 0.0)
			_rest_euler[joint_key] = q.get_euler()
			_rest_quat[joint_key] = q


## Strike moments (clip seconds) from the weapon arm's own motion: peak
## forward angular velocity of the arm track = the visual contact instant.
## Multi-peak clips (3-hit combo) yield one strike per hit. Falls back to
## mid-clip when the clip has no usable arm track. Cached per start.
func _compute_strike_times(anim_name: String) -> Array:
	var anim: Animation = _cached_anim_library.get(anim_name, null)
	var tmap: Dictionary = _cached_track_maps.get(anim_name, {})
	if anim == null:
		return []
	var track_idx: int = tmap.get("arm_right", tmap.get("arm_left", -1))
	if track_idx < 0:
		return [anim.length * 0.5]
	var n := 64
	var vel: Array = []
	var prev := 0.0
	for i in range(n + 1):
		var t: float = anim.length * float(i) / float(n)
		var q: Quaternion = anim.rotation_track_interpolate(track_idx, t)
		var x: float = q.get_euler().x
		if i > 0:
			vel.append((x - prev) / (anim.length / float(n)))
		prev = x
	var peak := 0.0
	for v in vel:
		peak = maxf(peak, float(v))
	if peak <= 0.001:
		return [anim.length * 0.5]
	var strikes: Array = []
	var last_hit := -100
	for i in range(vel.size()):
		var v: float = vel[i]
		var left_ok := i == 0 or float(vel[i - 1]) <= v
		var right_ok := i == vel.size() - 1 or float(vel[i + 1]) <= v
		if left_ok and right_ok and v > peak * 0.4 and i - last_hit >= n / 12:
			strikes.append(anim.length * float(i + 1) / float(n))
			last_hit = i
	if strikes.is_empty():
		return [anim.length * 0.5]
	return strikes


## Fires once per crossed strike moment. Drives the single gameplay hit per
## visual contact (combo clips: one per hit).
func poll_strike() -> bool:
	if _pending_strikes > 0:
		_pending_strikes -= 1
		return true
	return false


## Fires exactly once when the active swing finishes (recovery done,
## ownership returns to locomotion/hold).
func poll_attack_complete() -> bool:
	if _completed_pending:
		_completed_pending = false
		return true
	return false


## Read-only lifecycle snapshot for telemetry/debugging:
## {attack_id, anim, active, time, strikes_total, strikes_fired}.
func telemetry_snapshot() -> Dictionary:
	return {
		"attack_id": attack_id,
		"anim": current_anim_name,
		"active": is_melee_active(),
		"time": anim_time,
		"strikes_total": strike_times.size(),
		"strikes_fired": _strike_idx,
	}


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
	attack_id += 1
	melee_mode = true
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
	var started := play_action(clip_name, play_speed, 0.06, 0.14)
	if started:
		attack_id += 1
		melee_mode = true
	return started


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
	attack_id += 1
	melee_mode = true
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
	if play_action(clip_name, play_speed, 0.06, 0.14):
		attack_id += 1
		melee_mode = true


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

		# Strike edges: every crossed strike moment queues exactly one hit.
		while _strike_idx < strike_times.size() and anim_time >= float(strike_times[_strike_idx]):
			_strike_idx += 1
			_pending_strikes += 1

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
			_completed_pending = true
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
func apply_to_joints(joints: Dictionary, master_weight: float = 1.0, apply_legs: bool = false) -> void:
	# 1. Main action animation (Melee, Die, GetHit, Shoulder)
	var effective_main := blend_weight * master_weight
	if effective_main > 0.001:
		var anim: Animation = _cached_anim_library.get(current_anim_name, null)
		var tmap: Dictionary = _cached_track_maps.get(current_anim_name, {})
		if anim != null and not tmap.is_empty():
			var sample_t := clampf(anim_time, 0.0, anim_length)
			for joint_key in tmap:
				# Melee owns the upper body only; legs/shins stay on base
				# locomotion (weapon-layer architecture). Everything else
				# (die/gethit/shoot) keeps legacy full-body behavior.
				if melee_mode and not apply_legs and not (str(joint_key) in MELEE_UPPER_KEYS):
					continue
				var track_idx: int = tmap[joint_key]
				var node: Node3D = joints.get(joint_key + "_mesh", null)
				if node == null:
					node = joints.get(joint_key, null)
				if node == null or not is_instance_valid(node):
					continue

				var q: Quaternion = anim.rotation_track_interpolate(track_idx, sample_t)
				var target_euler: Vector3 = q.get_euler()
				if melee_mode and _rest_quat.has(joint_key):
					# Rest-relative delta: the authored motion minus the source
					# rest pose, so a foreign-rested take drives our pivots
					# through the same relative trajectory instead of snapping
					# limbs into the source's rest pose.
					var q_rest: Quaternion = _rest_quat[joint_key]
					var delta_q: Quaternion = q * q_rest.inverse()





					if joint_key == "forearm_left" or joint_key == "forearm_right":
					# Wrist snap folds into the forearm: the rig has no hand
					# pivots, and the snap carries the visible slash snap.
					# Composed as quaternions (euler-vector addition explodes
					# near gimbal regions, e.g. the hand's ~100 deg Y component).
						var hand_key := "hand_left" if joint_key == "forearm_left" else "hand_right"
						if tmap.has(hand_key) and _rest_quat.has(hand_key):
							var hq: Quaternion = anim.rotation_track_interpolate(int(tmap[hand_key]), sample_t)
							var h_rest: Quaternion = _rest_quat[hand_key]
							var hand_delta_q: Quaternion = hq * h_rest.inverse()
							delta_q = delta_q * hand_delta_q
					target_euler = delta_q.get_euler()






				var blend := effective_main
				node.rotation.x = lerp_angle(node.rotation.x, target_euler.x, blend)
				if joint_key in ["arm_left", "arm_right", "forearm_left", "forearm_right", "body", "leg_left", "leg_right", "shin_left", "shin_right"]:
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
