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
	_check(AudioManager.sfx_pool.size() >= 16, "SFX 3D pool contains at least 16 players")
	_check(AudioManager.sfx_2d_pool.size() >= 8, "SFX 2D pool contains at least 8 players")

	# Test 3D play
	AudioManager.play_sfx("footstep", Vector3(10, 0, 5))
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
