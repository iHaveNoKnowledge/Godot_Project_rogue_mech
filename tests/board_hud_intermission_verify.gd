extends Node

## Headless verification of the board HUD / intermission interplay and the
## intermission music resume behavior:
##   - the top-center MP card is ALWAYS visible on the board — even while the
##     intermission menu is open (it never overlaps the left menu buttons)
##   - the board HUD's right column carries the sector objective, a ceasefire
##     countdown slot and a reserved empty slot (the intermission no longer
##     draws its own objective panel)
##   - AudioManager remembers the intermission track when combat music takes
##     over and resumes the SAME track (not a fresh random song) when the
##     player returns to the board, then forgets it when leaving to the menu
## Run: godot --headless --path . res://tests/board_hud_intermission_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _verify_board_hud_always_visible()
	await _verify_right_column()
	await _verify_music_resume()
	await _verify_hangar_return_stops_music()
	print("BOARD_HUD_INTERMISSION_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _find_labels(node: Node, found: Array) -> void:
	if node is Label:
		found.append(node)
	for child in node.get_children():
		_find_labels(child, found)


func _verify_board_hud_always_visible() -> void:
	# Mirror the board scene layout: GameBoard hosts both IntermissionUI and
	# BoardHUD as siblings.
	var host := Node3D.new()
	host.name = "GameBoard"
	add_child(host)

	var intermission := CanvasLayer.new()
	intermission.name = "IntermissionUI"
	host.add_child(intermission)

	var hud = load("res://scenes/ui/board_hud.tscn").instantiate()
	host.add_child(hud)
	await get_tree().process_frame

	# Intermission menu open (the default state when the board loads) -> the
	# MP card stays visible at top-center.
	_check(hud._panel.visible, "MP card is visible while the intermission menu is open")

	# Player pressed "Move on Board" -> still visible.
	intermission.visible = false
	await get_tree().process_frame
	_check(hud._panel.visible, "MP card stays visible once the intermission closes")

	# Reopening the intermission keeps it visible.
	intermission.visible = true
	await get_tree().process_frame
	_check(hud._panel.visible, "MP card stays visible when the intermission reopens")

	host.queue_free()


func _verify_right_column() -> void:
	var hud = load("res://scenes/ui/board_hud.tscn").instantiate()
	add_child(hud)
	await get_tree().process_frame

	# The right column is a 3-slot stack: objective / countdown / reserved.
	_check(hud._objective_label != null and str(hud._objective_label.text).begins_with("OBJECTIVE"),
		"right column shows the sector objective")
	_check(hud._ceasefire_panel != null and hud._reserved_panel != null,
		"right column has a ceasefire countdown slot + reserved slot")

	# The slots STACK in a VBox: the ceasefire card sits BELOW the objective
	# card, never overlapping it, even after a long objective text reflows.
	# Force a tall objective (long autowrapped text) so the cards must reflow,
	# then verify the ceasefire's top edge stays below the objective's bottom.
	hud._objective_label.text = "OBJECTIVE\n" + ("SECTOR PRIORITY TARGET WITH A VERY LONG NAME ".repeat(6))
	hud._objective_label.reset_size()
	hud._ceasefire_panel.reset_size()
	hud._objective_panel.reset_size()
	await get_tree().process_frame
	var obj_bottom: float = float(hud._objective_panel.global_position.y) + float(hud._objective_panel.size.y)
	var cf_top: float = float(hud._ceasefire_panel.global_position.y)
	_check(cf_top >= obj_bottom, "ceasefire slot sits below the objective card (no overlap)")
	_check(float(hud._objective_panel.size.y) > 0.0 and float(hud._ceasefire_panel.size.y) > 0.0,
		"objective and ceasefire cards both have size")

	# No ceasefire -> the countdown slot stays an empty reserved cell.
	GlobalData.ceasefire_turns = 0
	hud._refresh()
	_check(str(hud._ceasefire_label.text) == "", "ceasefire slot empty when no ceasefire is active")

	# Active ceasefire -> the slot shows how many turns remain.
	GlobalData.ceasefire_turns = 3
	hud._refresh()
	_check(str(hud._ceasefire_label.text).contains("3 TURNS LEFT"), "ceasefire slot shows remaining turns when active")
	GlobalData.ceasefire_turns = 0

	# MP readout still works (the whole point of the card).
	var labels: Array = []
	_find_labels(hud._panel, labels)
	var mp_found := false
	for label in labels:
		if str(label.text).begins_with("MP "):
			mp_found = true
	_check(mp_found, "MP readout is still present on the board card")

	hud.queue_free()


func _verify_music_resume() -> void:
	# Fresh board session: nothing to resume yet.
	AudioManager._saved_intermission_track = null
	AudioManager._saved_intermission_pos = 0.0
	AudioManager.play_intermission_music(0.1)
	await get_tree().process_frame
	_check(AudioManager.current_music_category == "intermission",
		"board session starts intermission music")
	var board_track: AudioStream = AudioManager.current_track
	_check(board_track != null, "an intermission track is playing")

	# Entering combat takes over the music and remembers where the board song was.
	AudioManager.play_combat_music("grunt", 0.1)
	await get_tree().process_frame
	_check(AudioManager.current_music_category == "grunt", "combat music takes over")
	_check(AudioManager._saved_intermission_track == board_track,
		"the intermission track is remembered when combat starts")

	# Returning to the board resumes the SAME track, and the memory is consumed.
	AudioManager.play_intermission_music(0.1)
	await get_tree().process_frame
	_check(AudioManager.current_track == board_track,
		"returning to the board resumes the same intermission track")
	_check(AudioManager._saved_intermission_track == null,
		"the saved track is consumed after resuming")

	# Leaving for the menu clears the memory so the next run starts fresh.
	AudioManager.play_menu_music(0.1)
	await get_tree().process_frame
	_check(AudioManager._saved_intermission_track == null,
		"leaving to the menu forgets the saved intermission track")


func _verify_hangar_return_stops_music() -> void:
	# Reproduces the hangar -> board bug: the hangar BGM followed the player back
	# into the intermission and never ended. return_to_board() calls
	# stop_music() and then play_intermission_music() back-to-back; the second
	# call's _crossfade_to_stream() used to kill stop_music()'s fade tween
	# (shared _music_tween), aborting the fade-to-stop of the hangar player.
	AudioManager.play_intermission_music(0.1)
	await get_tree().process_frame
	_check(AudioManager.current_music_category == "intermission",
		"hangar flow starts from intermission music")

	AudioManager.play_hangar_music(0.1)
	await get_tree().process_frame
	_check(AudioManager.current_music_category == "hangar",
		"entering the hangar switches to hangar BGM")
	var hangar_player: AudioStreamPlayer = AudioManager.current_music
	_check(hangar_player != null and hangar_player.playing,
		"the hangar track is the one playing")

	# Leaving the hangar: stop_music() then the board re-enters intermission
	# music — the exact back-to-back sequence that used to strand the track.
	AudioManager.stop_music(0.2)
	AudioManager.play_intermission_music(0.1)
	await get_tree().process_frame
	_check(AudioManager.current_music_category == "intermission",
		"returning to the board plays intermission music")

	# Let the stop fade (0.2s) + callback run to completion.
	for i in range(10):
		await get_tree().create_timer(0.1).timeout
	_check(hangar_player != null and not hangar_player.playing,
		"the hangar track fades out and STOPS (does not follow into intermission)")
