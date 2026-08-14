extends Node

## Headless verification of the board HUD / intermission interplay and the
## intermission music resume behavior:
##   - the compact MP card hides while the intermission menu is open (so it
##     never overlaps the menu buttons) and reappears when it closes
##   - the board card carries day + MP only; the sector objective text lives
##     exclusively in the intermission's top-right panel
##   - AudioManager remembers the intermission track when combat music takes
##     over and resumes the SAME track (not a fresh random song) when the
##     player returns to the board, then forgets it when leaving to the menu
## Run: godot --headless --path . res://tests/board_hud_intermission_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _verify_board_hud_hiding()
	await _verify_no_objective_in_board_hud()
	await _verify_music_resume()
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


func _verify_board_hud_hiding() -> void:
	# Mirror the board scene layout: GameBoard hosts both IntermissionUI and
	# BoardHUD as siblings, and board_hud looks up "IntermissionUI" on its parent.
	var host := Node3D.new()
	host.name = "GameBoard"
	add_child(host)

	var intermission := CanvasLayer.new()
	intermission.name = "IntermissionUI"
	host.add_child(intermission)

	var hud = load("res://scenes/ui/board_hud.tscn").instantiate()
	host.add_child(hud)
	await get_tree().process_frame

	# Intermission menu open (the default state when the board loads) -> hidden.
	_check(not hud._panel.visible, "MP card hides while the intermission menu is open")

	# Player pressed "Move on Board" -> the card reappears for map traversal.
	intermission.visible = false
	await get_tree().process_frame
	_check(hud._panel.visible, "MP card shows again once the intermission closes")

	# Reopening the intermission hides it again.
	intermission.visible = true
	await get_tree().process_frame
	_check(not hud._panel.visible, "MP card hides again when the intermission reopens")

	host.queue_free()


func _verify_no_objective_in_board_hud() -> void:
	var hud = load("res://scenes/ui/board_hud.tscn").instantiate()
	add_child(hud)
	await get_tree().process_frame

	var labels: Array = []
	_find_labels(hud._panel, labels)
	var has_objective := false
	for label in labels:
		if str(label.text).contains("OBJECTIVE"):
			has_objective = true
	_check(not has_objective, "board card shows day + MP only, no objective text")

	# MP readout still works (the whole point of the card).
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
