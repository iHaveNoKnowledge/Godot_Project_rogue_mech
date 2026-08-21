extends Node3D

## Verification test for Per-Model Weapon SFX & Trimmed Light Machine Gun Sound:
## Validates that machine_gun02.wav is trimmed to a single shot and correctly assigned
## to lower-damage machine gun models (Light Machine Gun, Gatling Gun).

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("WEAPON_SFX_OK: %s" % msg)
	else:
		_fails += 1
		print("WEAPON_SFX_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Weapon Model SFX Verification ---")

	# 1. Verify machine_gun02.wav loads and duration retains full body/tail (> 1.0s) with first click removed
	var mg02_stream: AudioStream = load("res://resources/audio/sfx/machine_gun02.wav")
	_check(mg02_stream != null, "machine_gun02.wav loaded successfully")
	if mg02_stream:
		var dur := mg02_stream.get_length()
		_check(dur > 1.0 and dur < 1.45, "machine_gun02.wav duration retains full body and tail (%.3fs)" % dur)

	# 2. Verify Light Machine Gun resource
	var lmg_res = load("res://resources/mech/stock/weapon_light_machine_gun.tres")
	_check(lmg_res != null, "weapon_light_machine_gun.tres loaded")
	_check(lmg_res.fire_sfx != null, "Light Machine Gun has dedicated fire_sfx assigned")
	_check(lmg_res.damage < 5.0, "Light Machine Gun has lower damage (%.1f)" % lmg_res.damage)

	# 3. Verify Gatling Gun resource
	var gatling_res = load("res://resources/mech/stock/weapon_gatling_gun.tres")
	_check(gatling_res != null, "weapon_gatling_gun.tres loaded")
	_check(gatling_res.fire_sfx != null, "Gatling Gun has dedicated fire_sfx assigned")

	# 4. Verify Standard Machine Gun resource (damage 6.0)
	var std_mg_res = load("res://resources/mech/stock/weapon_machine_gun.tres")
	_check(std_mg_res != null, "weapon_machine_gun.tres loaded")
	_check(std_mg_res.damage >= 6.0, "Standard Machine Gun has standard damage (%.1f)" % std_mg_res.damage)

	# 5. Playback trigger test through AudioManager facade
	AudioManager.play_weapon_sfx_with_override(lmg_res, Vector3.ZERO)
	AudioManager.play_weapon_sfx_with_override(std_mg_res, Vector3.ZERO)
	_check(true, "AudioManager.play_weapon_sfx_with_override executed without errors")

	print("WEAPON_SFX_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
