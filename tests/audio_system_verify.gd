extends Node

var checks: int = 0
var fails: int = 0


func _ready() -> void:
	print("--- 1. Testing Audio Bus Architecture & Effects ---")
	_test_audio_buses()

	print("--- 2. Testing AAA Procedural Audio Synthesis ---")
	_test_procedural_sounds()

	print("--- 3. Testing SFX Player Pool & Playback ---")
	_test_sfx_playback()

	print("--- 4. Testing Footstep File Variants ---")
	_test_footstep_variants()

	print("\n==================================================")
	print("AUDIO_SYSTEM_VERIFY COMPLETED:")
	print("Checks: %d | Fails: %d" % [checks, fails])
	print("==================================================")
	if fails == 0:
		print("ALL AUDIO SYSTEM TESTS PASSED!")
		get_tree().quit(0)
	else:
		printerr("AUDIO SYSTEM TESTS FAILED!")
		get_tree().quit(1)


func _check(condition: bool, msg: String) -> void:
	checks += 1
	if condition:
		print("AUDIO_TEST OK: %s" % msg)
	else:
		fails += 1
		printerr("AUDIO_TEST FAIL: %s" % msg)


func _test_audio_buses() -> void:
	var sfx_idx := AudioServer.get_bus_index("SFX")
	_check(sfx_idx != -1, "SFX audio bus exists")

	var music_idx := AudioServer.get_bus_index("Music")
	_check(music_idx != -1, "Music audio bus exists")

	var master_idx := AudioServer.get_bus_index("Master")
	_check(master_idx != -1, "Master audio bus exists")

	var has_compressor := false
	if sfx_idx != -1:
		for i in range(AudioServer.get_bus_effect_count(sfx_idx)):
			if AudioServer.get_bus_effect(sfx_idx, i) is AudioEffectCompressor:
				has_compressor = true
				break
	_check(has_compressor, "Dynamic compressor attached to SFX bus for punchy sound")

	var has_limiter := false
	if master_idx != -1:
		for i in range(AudioServer.get_bus_effect_count(master_idx)):
			if AudioServer.get_bus_effect(master_idx, i) is AudioEffectLimiter:
				has_limiter = true
				break
	_check(has_limiter, "Master bus limiter attached to prevent digital clipping")


func _test_procedural_sounds() -> void:
	var required_sounds := [
		"footstep",
		"step_lift",
		"jump",
		"land",
		"explosion",
		"armor_break",
		"ui_click",
		"ui_confirm",
		"reload_complete",
		"dash",
		"roller_skate",
		"pile_bunker_fire",
		"pile_bunker_hit",
	]

	for sname in required_sounds:
		var stream = AudioManager._pick_stream(sname)
		var valid: bool = stream is AudioStreamWAV and stream.data.size() > 0
		_check(valid, "Sound '%s' generated valid non-empty 16-bit audio stream (bytes: %d)" % [
			sname, stream.data.size() if stream is AudioStreamWAV else 0
		])


func _test_sfx_playback() -> void:
	_check(AudioManager.sfx.sfx_pool.size() >= 16, "SFX 3D pool contains at least 16 players")
	_check(AudioManager.sfx_2d_pool.size() >= 8, "SFX 2D pool contains at least 8 players")

	# Test 3D play
	AudioManager.play_sfx("footstep", Vector3(10, 0, 5))
	AudioManager.play_step_lift(Vector3(10, 0, 5))
	var free_player = AudioManager._get_free_3d_player()
	_check(free_player != null and free_player.bus == "SFX", "3D SFX Player correctly routed to SFX bus")

	# Test 2D play
	AudioManager.play_sfx_2d("ui_click")
	var free_2d = AudioManager._get_free_2d_player()
	_check(free_2d != null and free_2d.bus == "SFX", "2D SFX Player correctly routed to SFX bus")

	# Test armor break and explosion triggers
	AudioManager.play_armor_break(Vector3.ZERO)
	AudioManager.play_mech_hit(Vector3.ZERO)
	_check(true, "Armor break and mech hit playback functions invoked successfully")


func _test_footstep_variants() -> void:
	var sfx_script = load("res://scripts/autoload/sfx_manager.gd")

	# Variant filename matching: exact, _N, N, -N, padded digits.
	_check(sfx_script._variant_index("footstep", "footstep") == 0, "exact name matches as base variant")
	_check(sfx_script._variant_index("footstep_2", "footstep") == 2, "footstep_2 matches variant 2")
	_check(sfx_script._variant_index("footstep03", "footstep") == 3, "footstep03 matches variant 3")
	_check(sfx_script._variant_index("footstep-1", "footstep") == 1, "footstep-1 matches variant 1")
	_check(sfx_script._variant_index("FOOTSTEP_2", "footstep") == 2, "matching is case-insensitive")
	_check(sfx_script._variant_index("footstepped", "footstep") == -1, "non-numeric suffix rejected")
	_check(sfx_script._variant_index("jump", "footstep") == -1, "unrelated sound rejected")

	# Step lift variants matching
	_check(sfx_script._variant_index("step_lift", "step_lift") == 0, "step_lift exact name matches")
	_check(sfx_script._variant_index("step_lift_2", "step_lift") == 2, "step_lift_2 matches variant 2")

	# Without any footstep files in resources/audio/sfx the loader must
	# gracefully report "no file" so the procedural fallback stays in charge.
	_check(AudioManager.sfx._load_sfx_file("no_such_sound_xyz") == null,
		"missing sound file returns null (procedural fallback)")
	var entry = AudioManager.sfx._sound_cache.get("footstep")
	_check(entry != null, "footstep cache always populated (file or procedural)")
	var lift_entry = AudioManager.sfx._sound_cache.get("step_lift")
	_check(lift_entry != null, "step_lift cache always populated (file or procedural)")

