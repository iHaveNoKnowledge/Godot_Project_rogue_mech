extends Node

## Headless verification of the enemy shield system (archetypes 4/5):
##   1. Shield archetypes spawn with an active PHYSICAL plate on their arm;
##      non-shield enemies carry no shield at all.
##   2. Damage funnels through the shield first (health system absorbs before
##      touching armor/frame), and a fully-blocked hit deals no part damage.
##   3. The plate drains at 40% against its OWN damage type and 100% against
##      the other two, and NEVER regenerates — a damaged plate stays damaged.
##   4. Draining the shield breaks it (inactive). set_shield_up toggles the
##      plate up/down.
##   5. AI: a shield gunner drops the plate around its shots and raises it
##      again; a shield melee drops it when it commits to a swing.
## Run: godot --headless --path . res://tests/enemy_shield_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await _verify_shield_stats()
	await _verify_absorption()
	await _verify_no_recharge()
	await _verify_anti_type_drain()
	await _verify_shield_toggle()
	await _verify_shield_audio()
	await _verify_ai_windows()
	print("ENEMY_SHIELD_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _spawn_enemy(archetype: int) -> Node:
	var scene = load("res://scenes/mecha/enemy_dummy.tscn")
	var enemy = scene.instantiate()
	enemy.archetype = archetype
	add_child(enemy)
	return enemy


func _verify_shield_stats() -> void:
	var knight = _spawn_enemy(4)  # SHIELD_MELEE
	var gunner = _spawn_enemy(5)  # SHIELD_RANGED
	var rusher = _spawn_enemy(0)  # RUSHER (no shield)
	await get_tree().process_frame

	_check(knight.shield_max_hp == 180.0, "shield melee carries a 180 HP shield")
	_check(knight.shield_active, "shield melee starts with the shield raised")
	_check(is_equal_approx(knight.shield_current_hp, knight.shield_max_hp), "shield starts full")
	_check(knight.shield_type == "blunt", "shield melee plate is anti-blunt")

	_check(gunner.shield_max_hp == 120.0, "shield gunner carries a 120 HP shield")
	_check(gunner.shield_active, "shield gunner starts with the shield raised")
	_check(gunner.shield_type == "pierce", "shield gunner plate is anti-pierce")

	_check(rusher.shield_max_hp == 0.0, "non-shield enemy carries no shield HP")
	_check(not rusher.is_shield_active(), "non-shield enemy shield is inactive")
	rusher.set_shield_up(true)
	_check(not rusher.is_shield_active(), "set_shield_up is a no-op for non-shield enemies")

	# The physical plate (shield model) is mounted on a hand, not a bubble.
	_check(knight.get_node_or_null("EnemyShieldMount") != null or knight._shield_hand_mount != null, "shield melee mounts a shield on a hand")
	_check(knight._shield_hand_mount != null and knight._weapon_hand_mount != null, "shield melee mounts shield + melee weapon")
	_check(gunner._shield_hand_mount != null and gunner._weapon_hand_mount != null, "shield gunner mounts shield + gun")

	knight.queue_free()
	gunner.queue_free()
	rusher.queue_free()
	await get_tree().process_frame


func _verify_absorption() -> void:
	var enemy = _spawn_enemy(4)
	await get_tree().process_frame
	var hs = enemy.health_system
	var body_armor_before: float = hs.parts["body"]["armor_hp"]
	var body_frame_before: float = hs.parts["body"]["frame_hp"]

	# A 50-damage hit while the shield is up (180 HP) is fully blocked. The
	# plate is anti-blunt, so a blunt hit drains at the 40% rate: 50 * 0.4 = 20
	# HP off the plate.
	hs.take_damage(50.0, "blunt")
	_check(is_equal_approx(enemy.shield_current_hp, 160.0), "shield absorbs 50 blunt damage at 40% drain (180 -> 160)")
	_check(is_equal_approx(hs.parts["body"]["armor_hp"], body_armor_before), "fully-blocked hit deals no armor damage")
	_check(is_equal_approx(hs.parts["body"]["frame_hp"], body_frame_before), "fully-blocked hit deals no frame damage")

	# A second blunt hit drains at 40% again (160 -> 128).
	hs.take_damage(80.0, "blunt")
	_check(is_equal_approx(enemy.shield_current_hp, 128.0), "shield absorbs the next 80 damage (160 -> 128)")
	_check(is_equal_approx(hs.parts["body"]["armor_hp"], body_armor_before), "absorbed hit still deals no armor damage")

	# Drain the last of the shield: a hit that breaks the plate is fully
	# caught by it (like the player's shield, the killing blow never leaks
	# through), so the armor stays untouched.
	hs.take_damage(400.0, "blunt")
	_check(enemy.shield_current_hp == 0.0, "final hit drains the shield to 0")
	_check(not enemy.is_shield_active(), "drained shield is no longer active")
	_check(is_equal_approx(hs.parts["body"]["armor_hp"], body_armor_before), "the breaking hit is fully caught by the plate")
	_check(is_equal_approx(hs.parts["body"]["frame_hp"], body_frame_before), "breaking hit leaves the frame untouched")

	# With the shield gone, damage lands directly on the armor.
	var armor_now: float = hs.parts["body"]["armor_hp"]
	hs.take_damage(20.0, "blunt")
	_check(hs.parts["body"]["armor_hp"] < armor_now, "broken shield no longer blocks damage")

	# Point damage (the projectile path) funnels through the shield too.
	var gunner = _spawn_enemy(5)
	await get_tree().process_frame
	var ghs = gunner.health_system
	var g_armor: float = ghs.parts["body"]["armor_hp"]
	ghs.take_damage_at_point(30.0, gunner.global_position + Vector3(0, 1.5, 0), "pierce")
	_check(is_equal_approx(gunner.shield_current_hp, 108.0), "point damage absorbed by the anti-pierce gunner plate (120 -> 108 at 40%)")

	# Same 30-damage hit, but HEAT: the anti-pierce plate cannot shed heat, so
	# it drains at 100% (108 -> 78).
	ghs.take_damage_at_point(30.0, gunner.global_position + Vector3(0, 1.5, 0), "heat")
	_check(is_equal_approx(gunner.shield_current_hp, 78.0), "heat on the anti-pierce plate drains at 100% (108 -> 78)")
	_check(is_equal_approx(ghs.parts["body"]["armor_hp"], g_armor), "point damage fully blocked by shield")

	enemy.queue_free()
	gunner.queue_free()
	await get_tree().process_frame


# Physical plates never regenerate: after taking hits the HP stays exactly
# where it was, no matter how long the enemy idles.
func _verify_no_recharge() -> void:
	var enemy = _spawn_enemy(5)
	await get_tree().process_frame

	# Take a hit that doesn't break the plate, then idle for a long time.
	enemy.health_system.take_damage(40.0, "heat")  # anti-pierce plate vs heat = 100% drain
	_check(is_equal_approx(enemy.shield_current_hp, 80.0), "heat hit drains the gunner plate at 100% (120 -> 80)")
	enemy._process(1.0)
	enemy._process(3.0)
	enemy._process(20.0)
	_check(is_equal_approx(enemy.shield_current_hp, 80.0), "shield never regenerates after long idle")
	_check(enemy.is_shield_active(), "partial plate stays raised")

	# Even lowered and re-raised, the HP does not come back.
	enemy.set_shield_up(false)
	enemy.set_shield_up(true)
	_check(is_equal_approx(enemy.shield_current_hp, 80.0), "re-raising a lowered plate does not restore HP")

	enemy.queue_free()
	await get_tree().process_frame


# The anti-type rule: a plate drains at 40% against its OWN type and 100%
# against the other two.
func _verify_anti_type_drain() -> void:
	var enemy = _spawn_enemy(4)  # anti-blunt plate, 180 HP
	await get_tree().process_frame

	# Own type (blunt) drains at 40%.
	enemy.health_system.take_damage(100.0, "blunt")
	_check(is_equal_approx(enemy.shield_current_hp, 140.0), "blunt hit on anti-blunt plate drains 40% (180 -> 140)")

	# Other types (heat / pierce) drain at 100%.
	enemy.health_system.take_damage(50.0, "heat")
	_check(is_equal_approx(enemy.shield_current_hp, 90.0), "heat hit on anti-blunt plate drains 100% (140 -> 90)")
	enemy.health_system.take_damage(30.0, "pierce")
	_check(is_equal_approx(enemy.shield_current_hp, 60.0), "pierce hit on anti-blunt plate drains 100% (90 -> 60)")

	# Legacy labels normalize onto the three types: "kinetic" is pierce, so it
	# drains at 100% against the anti-blunt plate (60 -> 10).
	enemy.health_system.take_damage(50.0, "kinetic")
	_check(is_equal_approx(enemy.shield_current_hp, 10.0), "legacy kinetic normalizes to pierce, drains 100% (60 -> 10)")

	enemy.queue_free()
	await get_tree().process_frame


func _verify_shield_toggle() -> void:
	var enemy = _spawn_enemy(4)
	await get_tree().process_frame

	enemy.set_shield_up(false)
	_check(not enemy.is_shield_active(), "set_shield_up(false) lowers the shield")
	enemy.set_shield_up(true)
	_check(enemy.is_shield_active(), "set_shield_up(true) raises the shield")
	_check(is_equal_approx(enemy.shield_current_hp, enemy.shield_max_hp), "toggling never restores plate HP")

	# The shared mecha_animation drives the guard arm: while the plate is up
	# the LEFT arm (which holds it) lifts toward the raised pose, and lowers
	# back when the plate drops.
	var anim = enemy.get_node_or_null("EnemyAnimation")
	_check(anim != null, "enemy has the shared mecha_animation node")
	if anim:
		# Raise -> wait a few frames for the blend to climb.
		for i in range(10):
			enemy.set_shield_up(true)
			await get_tree().physics_frame
		var arm_rot_up: float = anim.arm_left.rotation.x
		_check(arm_rot_up > 0.3, "shield arm lifts while the plate is up (%.2f rad)" % arm_rot_up)
		# Drop -> the arm eases back down.
		enemy.set_shield_up(false)
		for i in range(10):
			await get_tree().physics_frame
		var arm_rot_down: float = anim.arm_left.rotation.x
		_check(arm_rot_down < arm_rot_up, "shield arm lowers back when the plate drops (%.2f < %.2f)" % [arm_rot_down, arm_rot_up])

	# A broken plate cannot be raised (raise it first so the hit hits the plate).
	enemy.set_shield_up(true)
	enemy.health_system.take_damage(9999.0, "blunt")
	_check(not enemy.is_shield_active(), "broken plate is inactive")
	enemy.set_shield_up(true)
	_check(not enemy.is_shield_active(), "a broken plate cannot be raised again")

	enemy.queue_free()
	await get_tree().process_frame


# The shield has its own voices: a metallic clang when a shot is absorbed and
# a distinct shatter when the plate breaks, so blocking reads by ear.
func _verify_shield_audio() -> void:
	var am := AudioManager
	var sfx := AudioManager.sfx if AudioManager else null
	_check(am != null and sfx != null, "AudioManager & SFXManager autoload are available")
	if sfx == null:
		return

	_check(sfx._sound_cache.has("shield_block"), "cache has the shield_block voice")
	_check(sfx._sound_cache.has("shield_break"), "cache has the shield_break voice")

	# Block: three pitch-varied clang variants, all valid non-empty 16-bit WAVs.
	var block_arr: Array = sfx._sound_cache.get("shield_block", [])
	_check(block_arr is Array and block_arr.size() == 3, "shield block has 3 pitch variants")
	var blocks_ok := true
	for stream in block_arr:
		if not (stream is AudioStreamWAV and stream.data.size() > 500 and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 22050):
			blocks_ok = false
	_check(blocks_ok, "shield block variants are non-empty 16-bit 22050Hz WAVs")

	# Break: a single valid shatter.
	var break_stream: AudioStreamWAV = sfx._sound_cache.get("shield_break")
	_check(break_stream != null and break_stream.data.size() > 500 and break_stream.format == AudioStreamWAV.FORMAT_16_BITS, "shield break is a non-empty 16-bit WAV")

	# Distinct from each other and from the generic armor crack (so the player
	# can tell shield combat apart from armor damage).
	var armor_break: AudioStreamWAV = sfx._sound_cache.get("armor_break")
	var all_distinct := true
	if armor_break != null and break_stream.data == armor_break.data:
		all_distinct = false
	for stream in block_arr:
		if break_stream.data == stream.data:
			all_distinct = false
	_check(all_distinct, "shield break differs from the block clangs and the armor crack")

	# The positional wrappers route to the right streams.
	sfx.sfx_pool[0].stop()
	am.play_shield_block(Vector3.ZERO)
	_check(block_arr.has(sfx.sfx_pool[0].stream), "play_shield_block plays a block clang variant")
	_check(sfx.sfx_pool[0].pitch_scale >= 0.95 and sfx.sfx_pool[0].pitch_scale <= 1.05, "block clang jitters pitch (%.3f)" % sfx.sfx_pool[0].pitch_scale)
	sfx.sfx_pool[0].stop()
	am.play_shield_break(Vector3.ZERO)
	_check(sfx.sfx_pool[0].stream == break_stream, "play_shield_break plays the shatter voice")
	sfx.sfx_pool[0].stop()

	# End-to-end: a fully-blocked hit plays the clang, and draining the shield
	# to zero plays the shatter.
	var enemy = _spawn_enemy(5)
	await get_tree().process_frame
	sfx.sfx_pool[0].stop()
	enemy.health_system.take_damage(30.0, "heat")  # fully absorbed (100% drain)
	_check(block_arr.has(sfx.sfx_pool[0].stream), "blocked hit plays the block clang")
	sfx.sfx_pool[0].stop()
	enemy.health_system.take_damage(enemy.shield_max_hp, "heat")  # drains to 0
	_check(sfx.sfx_pool[0].stream == break_stream, "shield depletion plays the shatter")
	enemy.queue_free()
	await get_tree().process_frame


# Drives the real AI: a shield gunner must drop its plate around each shot
# (punish window) and raise it back, and a shield melee must drop it when it
# commits to a swing.
func _verify_ai_windows() -> void:
	var gunner = _spawn_enemy(5)
	var target := CharacterBody3D.new()
	target.name = "FakePlayer"
	target.add_to_group("mecha")
	target.position = Vector3(10.0, 0.0, 0.0)
	add_child(target)
	await get_tree().physics_frame
	gunner.target = target

	var saw_gunner_drop := false
	var saw_gunner_raise := false
	for i in range(300):
		await get_tree().physics_frame
		if not saw_gunner_drop and not gunner.is_shield_active():
			saw_gunner_drop = true
		if saw_gunner_drop and gunner.is_shield_active():
			saw_gunner_raise = true
			break
	_check(saw_gunner_drop, "shield gunner drops its plate around a shot")
	_check(saw_gunner_raise, "shield gunner raises the plate again after the shot")

	target.queue_free()
	gunner.queue_free()
	await get_tree().process_frame

	var knight = _spawn_enemy(4)
	var target2 := CharacterBody3D.new()
	target2.name = "FakePlayer2"
	target2.add_to_group("mecha")
	target2.position = Vector3(3.0, 0.0, 0.0)
	add_child(target2)
	await get_tree().physics_frame
	knight.target = target2

	var saw_knight_drop := false
	for i in range(300):
		await get_tree().physics_frame
		if not knight.is_shield_active():
			saw_knight_drop = true
			break
	_check(saw_knight_drop, "shield melee drops its plate when committing to a swing")

	target2.queue_free()
	knight.queue_free()
	await get_tree().process_frame
