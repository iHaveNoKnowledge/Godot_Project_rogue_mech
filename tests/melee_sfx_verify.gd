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

	print("SFX_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)
