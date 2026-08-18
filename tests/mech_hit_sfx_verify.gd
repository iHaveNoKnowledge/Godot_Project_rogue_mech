extends Node

## Headless verification of the "mech hit by bullets" armor-clank SFX:
##   1. AudioManager generates a mech_armor_hit cache with multiple variants.
##   2. play_mech_hit() routes a sound onto a pooled 3D player.
##   3. Rapid re-triggers are rate-limited (burst of fire = staccato pings).
##   4. A mech taking damage in the real scene fires the clank at its position.
## Run: godot --headless --path . res://tests/mech_hit_sfx_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("MECHHIT_OK: " + name)
	else:
		_fails += 1
		printerr("MECHHIT_FAIL: " + name)


# Counts pooled 3D SFX players currently playing one of the mech_armor_hit
# variants (so rate-limiting is measurable without audio hardware).
func _count_mech_hit_players() -> int:
	var variants: Array = AudioManager._sound_cache.get("mech_armor_hit", [])
	var count := 0
	for player in AudioManager.sfx_pool:
		if player.playing:
			for v in variants:
				if player.stream == v:
					count += 1
					break
	return count


func _ready() -> void:
	await get_tree().process_frame

	var cache_entry: Variant = AudioManager._sound_cache.get("mech_armor_hit")
	_check(cache_entry is Array and cache_entry.size() >= 3,
		"mech_armor_hit cache holds %d variants" % (cache_entry.size() if cache_entry is Array else 0))
	var variants: Array = cache_entry if cache_entry is Array else []
	for v in variants:
		_check(v != null and v is AudioStream, "each mech_armor_hit variant is a real AudioStream")
	_check(AudioManager.has_method("play_mech_hit"), "AudioManager exposes play_mech_hit()")

	# Fresh cooldown so the first call always fires.
	AudioManager._last_mech_hit_time = -1.0
	AudioManager.play_mech_hit(Vector3.ZERO)
	var playing_after_one := _count_mech_hit_players()
	_check(playing_after_one >= 1, "play_mech_hit routes onto a pooled 3D player (%d)" % playing_after_one)

	# Same-frame re-trigger must be dropped by the rate limiter.
	AudioManager.play_mech_hit(Vector3.ZERO)
	AudioManager.play_mech_hit(Vector3.ZERO)
	var playing_after_burst := _count_mech_hit_players()
	_check(playing_after_burst == playing_after_one,
		"rapid re-triggers are rate-limited (%d -> %d)" % [playing_after_one, playing_after_burst])

	# Let the cooldown expire, then a new hit fires again.
	await get_tree().create_timer(0.12).timeout
	AudioManager._last_mech_hit_time = -1.0
	AudioManager.play_mech_hit(Vector3.ZERO, 0.0)
	_check(_count_mech_hit_players() > 0, "a fresh hit after the cooldown fires again")

	# Integration: a real player mech taking damage plays the clank.
	await _verify_mech_damage_hook()

	print("MECH_HIT_SFX_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _verify_mech_damage_hook() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var mech = load("res://scenes/mecha/mecha_base.tscn").instantiate()
	mech.position = Vector3(0, 8, 0)
	add_child(mech)
	await get_tree().process_frame
	await get_tree().process_frame

	var health: Node = mech.get_node_or_null("HealthSystem")
	_check(health != null, "mecha_base exposes a HealthSystem")
	if health == null:
		return
	_check(health.has_method("take_damage"), "HealthSystem exposes take_damage()")

	# Wipe the cooldown so the hit is not swallowed by the rate limiter.
	AudioManager._last_mech_hit_time = -1.0
	health.take_damage(15.0, "kinetic")
	await get_tree().process_frame
	_check(_count_mech_hit_players() >= 1, "a damaged mech fires the armor-clank SFX")