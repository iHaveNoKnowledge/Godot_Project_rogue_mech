extends Node
## DESERT BGM VERIFY — Iron March on the Dunes is a desert-exclusive battle pick.
## 1. The track file is inside res:// and loads as an AudioStream.
## 2. MusicManager scans it into desert_tracks.
## 3. grunt/ace + desert biome rolls the exclusive track sometimes (chance), never on other biomes.
## 4. boss keeps its identity even on desert; empty desert_tracks falls back to normal.

var _fails := 0
var _checks := 0

const DESERT_MP3 := "res://resources/audio/music/desert/Iron_March_on_the_Dunes.mp3"


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("DESERT-BGM OK: " + name)
	else:
		_fails += 1
		printerr("DESERT-BGM FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	_check(ResourceLoader.exists(DESERT_MP3), "Iron March mp3 is inside res://")
	var stream: AudioStream = load(DESERT_MP3) as AudioStream
	_check(stream != null, "Iron March mp3 loads as AudioStream")

	var mgr: MusicManager = load("res://scripts/autoload/music_manager.gd").new()
	add_child(mgr)
	mgr.setup()
	_check(not mgr.desert_tracks.is_empty(), "desert playlist scanned (non-empty)")
	var has_iron := false
	for t in mgr.desert_tracks:
		if t != null and t.resource_path == DESERT_MP3:
			has_iron = true
	_check(has_iron, "desert playlist contains Iron March on the Dunes")

	# Desert + grunt: exclusive shows up sometimes, normal tracks still show up sometimes.
	var saw_desert := false
	var saw_normal := false
	for i in range(60):
		var pick: AudioStream = mgr._pick_combat_stream("grunt", "desert")
		_check(pick != null, "desert grunt pick never null")
		if pick in mgr.desert_tracks:
			saw_desert = true
		else:
			saw_normal = true
		if saw_desert and saw_normal:
			break
	_check(saw_desert, "desert grunt sometimes rolls the exclusive track")
	_check(saw_normal, "desert grunt sometimes keeps the normal playlist")

	# Other biomes never get the exclusive track.
	var leaked := false
	for i in range(20):
		for biome in ["forest", "suburb", "urban", ""]:
			var pick: AudioStream = mgr._pick_combat_stream("grunt", biome)
			if pick in mgr.desert_tracks:
				leaked = true
	_check(not leaked, "non-desert biomes never roll the exclusive track")

	# Boss keeps its identity on desert.
	var boss_leaked := false
	for i in range(20):
		if mgr._pick_combat_stream("boss", "desert") in mgr.desert_tracks:
			boss_leaked = true
	_check(not boss_leaked, "boss on desert still uses the boss playlist")

	# Empty desert folder falls back gracefully.
	var backup: Array[AudioStream] = mgr.desert_tracks.duplicate()
	mgr.desert_tracks.clear()
	var fallback: AudioStream = mgr._pick_combat_stream("grunt", "desert")
	_check(fallback != null, "empty desert playlist falls back to a playable track")
	mgr.desert_tracks = backup

	mgr.queue_free()
	print("DESERT_BGM_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
