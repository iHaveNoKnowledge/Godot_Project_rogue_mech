extends Node

## Headless verification of the enemy shield system (archetypes 4/5):
##   1. Shield archetypes spawn with an active shield + HP; non-shield enemies
##      carry no shield at all.
##   2. Damage funnels through the shield first (health system absorbs before
##      touching armor/frame), and a fully-blocked hit deals no part damage.
##   3. Draining the shield breaks it (inactive + visual hidden), and it
##      recharges after the delay once dropped.
##   4. set_shield_up toggles the barrier + its visual on/off.
##   5. AI: a shield gunner drops the barrier around its shots and raises it
##      again; a shield melee drops it when it commits to a swing.
## Run: godot --headless --path . res://tests/enemy_shield_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await _verify_shield_stats()
	await _verify_absorption()
	await _verify_break_and_recharge()
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
	_check(knight.get_node_or_null("EnemyShieldBubble") != null, "shield melee shows the barrier bubble")
	if knight.get_node_or_null("EnemyShieldBubble"):
		_check(knight.get_node("EnemyShieldBubble").visible, "barrier bubble is visible while raised")

	_check(gunner.shield_max_hp == 120.0, "shield gunner carries a 120 HP shield")
	_check(gunner.shield_active, "shield gunner starts with the shield raised")
	_check(gunner.get_node_or_null("EnemyShieldBubble") != null, "shield gunner shows the barrier bubble")

	_check(rusher.shield_max_hp == 0.0, "non-shield enemy carries no shield HP")
	_check(not rusher.is_shield_active(), "non-shield enemy shield is inactive")
	rusher.set_shield_up(true)
	_check(not rusher.is_shield_active(), "set_shield_up is a no-op for non-shield enemies")

	# The loadout models (shield plate + weapon) are mounted on the hands.
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

	# A 50-damage hit while the shield is up (180 HP) is fully blocked.
	hs.take_damage(50.0, "kinetic")
	_check(is_equal_approx(enemy.shield_current_hp, 130.0), "shield absorbs 50 damage (180 -> 130)")
	_check(is_equal_approx(hs.parts["body"]["armor_hp"], body_armor_before), "fully-blocked hit deals no armor damage")
	_check(is_equal_approx(hs.parts["body"]["frame_hp"], body_frame_before), "fully-blocked hit deals no frame damage")

	# A hit bigger than the shield leaks the remainder into the mech (the
	# armor HP comes from the catalog loadout, so only the direction is
	# asserted — leak drops armor, never frame).
	hs.take_damage(80.0, "kinetic")
	_check(is_equal_approx(enemy.shield_current_hp, 50.0), "shield absorbs the next 80 damage (130 -> 50)")
	_check(is_equal_approx(hs.parts["body"]["armor_hp"], body_armor_before), "absorbed hit still deals no armor damage")

	# Drain the last of the shield: the small overflow finally reaches armor.
	hs.take_damage(60.0, "kinetic")
	_check(enemy.shield_current_hp == 0.0, "final hit drains the shield to 0")
	_check(not enemy.is_shield_active(), "drained shield is no longer active")
	_check(hs.parts["body"]["armor_hp"] < body_armor_before, "overflow damage reaches the armor")
	_check(hs.parts["body"]["frame_hp"] == body_frame_before, "overflow hits armor first, not frame")

	# With the shield gone, damage lands directly on the armor.
	var armor_now: float = hs.parts["body"]["armor_hp"]
	hs.take_damage(20.0, "kinetic")
	_check(hs.parts["body"]["armor_hp"] < armor_now, "broken shield no longer blocks damage")

	# Point damage (the projectile path) funnels through the shield too.
	var gunner = _spawn_enemy(5)
	await get_tree().process_frame
	var ghs = gunner.health_system
	var g_armor: float = ghs.parts["body"]["armor_hp"]
	ghs.take_damage_at_point(30.0, gunner.global_position + Vector3(0, 1.5, 0), "kinetic")
	_check(is_equal_approx(gunner.shield_current_hp, 90.0), "projectile-style damage absorbed by the gunner shield (120 -> 90)")
	_check(is_equal_approx(ghs.parts["body"]["armor_hp"], g_armor), "point damage fully blocked by shield")

	enemy.queue_free()
	gunner.queue_free()
	await get_tree().process_frame


func _verify_break_and_recharge() -> void:
	var enemy = _spawn_enemy(5)
	await get_tree().process_frame

	# Drain the shield completely: breaks and hides the bubble. A leak big
	# enough to break the armor would destroy the mech, so use a bare drain.
	enemy.health_system.take_damage(enemy.shield_max_hp, "kinetic")
	_check(not enemy.is_shield_active(), "drained shield breaks (inactive)")
	if enemy.get_node_or_null("EnemyShieldBubble"):
		_check(not enemy.get_node("EnemyShieldBubble").visible, "barrier bubble hidden after break")

	# Recharge: while broken, the delay must elapse before regen starts.
	var regen_rate: float = enemy.shield_recharge_rate
	enemy._process(1.0)  # inside the 3s delay -> no regen yet
	_check(is_equal_approx(enemy.shield_current_hp, 0.0), "no regen during the recharge delay")
	enemy._process(3.0)  # delay elapsed, then a full 3s of regen ticks
	_check(is_equal_approx(enemy.shield_current_hp, regen_rate * 3.0), "shield regenerates after the delay at its rate")
	enemy._process(20.0)  # long idle -> capped at max
	_check(is_equal_approx(enemy.shield_current_hp, enemy.shield_max_hp), "shield regen caps at max HP")

	# The AI re-raises the barrier once it has recharged (set_shield_up), and
	# while it is UP the shield never recharges in combat.
	enemy.set_shield_up(true)
	enemy.health_system.take_damage(40.0, "kinetic")
	_check(enemy.shield_active, "shield raised again after recharge")
	_check(is_equal_approx(enemy.shield_current_hp, enemy.shield_max_hp - 40.0), "re-raised shield absorbs again")
	enemy.shield_current_hp = enemy.shield_max_hp - 40.0
	enemy._process(5.0)
	_check(is_equal_approx(enemy.shield_current_hp, enemy.shield_max_hp - 40.0), "raised shield does not recharge in combat")

	enemy.queue_free()
	await get_tree().process_frame


func _verify_shield_toggle() -> void:
	var enemy = _spawn_enemy(4)
	await get_tree().process_frame

	enemy.set_shield_up(false)
	_check(not enemy.is_shield_active(), "set_shield_up(false) lowers the shield")
	if enemy.get_node_or_null("EnemyShieldBubble"):
		_check(not enemy.get_node("EnemyShieldBubble").visible, "bubble hidden when lowered")
	enemy.set_shield_up(true)
	_check(enemy.is_shield_active(), "set_shield_up(true) raises the shield")
	if enemy.get_node_or_null("EnemyShieldBubble"):
		_check(enemy.get_node("EnemyShieldBubble").visible, "bubble shown when raised")

	enemy.queue_free()
	await get_tree().process_frame


# The shield has its own voices: a metallic clang when a shot is absorbed and
# a distinct shatter when the barrier breaks, so blocking reads by ear.
func _verify_shield_audio() -> void:
	var am := AudioManager
	_check(am != null, "AudioManager autoload is available")

	_check(am._sound_cache.has("shield_block"), "cache has the shield_block voice")
	_check(am._sound_cache.has("shield_break"), "cache has the shield_break voice")

	# Block: three pitch-varied clang variants, all valid non-empty 16-bit WAVs.
	var block_arr: Array = am._sound_cache["shield_block"]
	_check(block_arr is Array and block_arr.size() == 3, "shield block has 3 pitch variants")
	var blocks_ok := true
	for stream in block_arr:
		if not (stream is AudioStreamWAV and stream.data.size() > 500 and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 22050):
			blocks_ok = false
	_check(blocks_ok, "shield block variants are non-empty 16-bit 22050Hz WAVs")

	# Break: a single valid shatter.
	var break_stream: AudioStreamWAV = am._sound_cache["shield_break"]
	_check(break_stream != null and break_stream.data.size() > 500 and break_stream.format == AudioStreamWAV.FORMAT_16_BITS, "shield break is a non-empty 16-bit WAV")

	# Distinct from each other and from the generic armor crack (so the player
	# can tell shield combat apart from armor damage).
	var armor_break: AudioStreamWAV = am._sound_cache["armor_break"]
	var all_distinct := true
	if armor_break != null and break_stream.data == armor_break.data:
		all_distinct = false
	for stream in block_arr:
		if break_stream.data == stream.data:
			all_distinct = false
	_check(all_distinct, "shield break differs from the block clangs and the armor crack")

	# The positional wrappers route to the right streams.
	am.sfx_pool[0].stop()
	am.play_shield_block(Vector3.ZERO)
	_check(block_arr.has(am.sfx_pool[0].stream), "play_shield_block plays a block clang variant")
	_check(am.sfx_pool[0].pitch_scale >= 0.95 and am.sfx_pool[0].pitch_scale <= 1.05, "block clang jitters pitch (%.3f)" % am.sfx_pool[0].pitch_scale)
	am.sfx_pool[0].stop()
	am.play_shield_break(Vector3.ZERO)
	_check(am.sfx_pool[0].stream == break_stream, "play_shield_break plays the shatter voice")
	am.sfx_pool[0].stop()

	# End-to-end: a fully-blocked hit plays the clang, and draining the shield
	# to zero plays the shatter.
	var enemy = _spawn_enemy(5)
	await get_tree().process_frame
	am.sfx_pool[0].stop()
	enemy.health_system.take_damage(30.0, "kinetic")  # fully absorbed
	_check(block_arr.has(am.sfx_pool[0].stream), "blocked hit plays the block clang")
	am.sfx_pool[0].stop()
	enemy.health_system.take_damage(enemy.shield_max_hp, "kinetic")  # drains to 0
	_check(am.sfx_pool[0].stream == break_stream, "shield depletion plays the shatter")
	enemy.queue_free()
	await get_tree().process_frame


# Drives the real AI: a shield gunner must drop its barrier around each shot
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
	_check(saw_gunner_drop, "shield gunner drops its barrier around a shot")
	_check(saw_gunner_raise, "shield gunner raises the barrier again after the shot")

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
	_check(saw_knight_drop, "shield melee drops its barrier when committing to a swing")

	target2.queue_free()
	knight.queue_free()
	await get_tree().process_frame
