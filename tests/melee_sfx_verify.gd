extends Node

## Verifies the per-weapon melee SFX:
##   - all six voices (fist swing/thud, knife swing/hit, blade swing/ring) are
##     generated into the sound cache as valid non-empty 16-bit WAVs,
##   - the dispatch helper maps fist / knife / blade weapons to their correct
##     swing and hit voices, with an unknown melee weapon falling back to the
##     generic "melee" cache.
## Run: godot --headless --path . res://tests/melee_sfx_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("SFX OK: " + name)
	else:
		_fails += 1
		print("SFX FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame

	var am := AudioManager
	_check(am != null, "AudioManager autoload is available")

	# 1. All six per-weapon voices exist in the cache.
	var keys := ["fist_swing", "fist_thud", "knife_swing", "knife_hit", "blade_swing", "blade_ring"]
	for key in keys:
		_check(am._sound_cache.has(key), "cache has the %s voice" % key)

	# 2. Each voice is a valid non-empty 16-bit WAV.
	for key in keys:
		var stream: AudioStreamWAV = am._sound_cache[key]
		var ok := stream != null and stream.data.size() > 500 and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 22050
		_check(ok, "%s is a non-empty 16-bit 22050Hz WAV" % key)

	# 3. Dispatch: each weapon family maps to its own swing + hit voice.
	var fist := WeaponPart.new()
	fist.weapon_name = "Bare Fist"
	_check(am._melee_sfx_name(fist, false) == "fist_swing", "fist swing maps to fist_swing")
	_check(am._melee_sfx_name(fist, true) == "fist_thud", "fist hit maps to fist_thud")

	var knife := WeaponPart.new()
	knife.weapon_name = "Combat Knife"
	_check(am._melee_sfx_name(knife, false) == "knife_swing", "knife swing maps to knife_swing")
	_check(am._melee_sfx_name(knife, true) == "knife_hit", "knife hit maps to knife_hit")

	var blade := WeaponPart.new()
	blade.weapon_name = "Heat Blade"
	_check(am._melee_sfx_name(blade, false) == "blade_swing", "blade swing maps to blade_swing")
	_check(am._melee_sfx_name(blade, true) == "blade_ring", "blade hit maps to blade_ring")

	var unknown := WeaponPart.new()
	unknown.weapon_name = "Mystery Cutter"
	_check(am._melee_sfx_name(unknown, false) == "melee", "unknown melee falls back to the generic melee swing")
	_check(am._melee_sfx_name(unknown, true) == "melee", "unknown melee falls back to the generic melee hit")

	# 4. The voices are actually distinct (different sample data), so the
	#    per-weapon tuning is real, not six copies of the same sound.
	var distinct := true
	for i in range(1, keys.size()):
		if am._sound_cache[keys[0]].data == am._sound_cache[keys[i]].data:
			distinct = false
	_check(distinct, "the six voices are distinct audio streams")

	# 5. Pile bunker: its fire/hit voices exist, are valid, and are distinct
	#    from the whole melee set (reworked deeper so they don't collide with
	#    the blade's bright 1750Hz ring).
	var pile_fire: AudioStreamWAV = am._sound_cache["pile_bunker_fire"]
	var pile_hit: AudioStreamWAV = am._sound_cache["pile_bunker_hit"]
	_check(pile_fire != null and pile_fire.data.size() > 500, "pile bunker fire voice exists")
	_check(pile_hit != null and pile_hit.data.size() > 500, "pile bunker hit voice exists")
	var all_melee := keys.duplicate()
	all_melee.append("pile_bunker_fire")
	all_melee.append("pile_bunker_hit")
	var all_distinct := true
	for i in range(all_melee.size()):
		for j in range(i + 1, all_melee.size()):
			if am._sound_cache[all_melee[i]].data == am._sound_cache[all_melee[j]].data:
				all_distinct = false
	_check(all_distinct, "pile voices are distinct from every melee voice and each other")

	# 6. The pile hit rings DEEPER than the blade ring: over the decay tail the
	#    blade's 1750/3500Hz ring crosses zero far more often than the pile's
	#    sub-boom + 520/1040Hz clang. (Noise has decayed away in both tails.)
	var pile_tail := _zero_crossings(pile_hit, 0.7, 1.0)
	var blade_tail := _zero_crossings(am._sound_cache["blade_ring"], 0.7, 1.0)
	_check(pile_tail < blade_tail * 0.6, "pile hit rings deeper than the blade ring (%d vs %d crossings)" % [pile_tail, blade_tail])

	# 7. Pitch jitter: melee plays randomize the pitch in a small band so
	#    repeated swings don't sound identical, and a plain play_sfx call
	#    resets the pooled player back to 1.0 (the pool is shared/reused).
	am.play_melee_swing(fist, Vector3.ZERO)
	var swing_pitch: float = am.sfx_pool[0].pitch_scale
	_check(swing_pitch >= 0.94 and swing_pitch <= 1.06 and not is_equal_approx(swing_pitch, 1.0),
		"melee swing plays with slight pitch jitter (%.3f)" % swing_pitch)
	am.sfx_pool[0].stop()
	am.play_sfx("beam_rifle", Vector3.ZERO)
	_check(am.sfx_pool[0].pitch_scale == 1.0, "non-jittered sfx resets the pooled player pitch to 1.0")

	print("SFX_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


# Counts zero crossings of a 16-bit WAV stream between two fractions of its
# length — a rough spectral proxy (fewer crossings = lower-frequency content).
func _zero_crossings(stream: AudioStreamWAV, from_frac: float, to_frac: float) -> int:
	var data := stream.data
	var from := int(from_frac * data.size() / 2)
	var to := int(to_frac * data.size() / 2)
	var crossings := 0
	var prev := 0
	for i in range(from, to):
		var v: int = data[i * 2] | (data[i * 2 + 1] << 8)
		if v >= 32768:
			v -= 65536
		if i > from and ((prev < 0 and v >= 0) or (prev >= 0 and v < 0)):
			crossings += 1
		prev = v
	return crossings
