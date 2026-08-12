extends Node

## Headless verification of the combat squad HUD + ally billboard name plate:
## fielded allies expose a pilot display name, the billboard shows it above the
## part blocks, and the SquadHUD panel lists every ally with a live HP bar that
## drops when the ally takes damage.
## Run: godot --headless --path . res://tests/squad_hud_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _verify_ally_billboard()
	await _verify_squad_panel()
	print("SQUAD_HUD_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _verify_ally_billboard() -> void:
	var scene = load("res://scenes/mecha/ally_dummy.tscn")
	var ally = scene.instantiate()
	ally.template_id = "ally_gm"  # template name = "GM-II"
	add_child(ally)
	await get_tree().process_frame

	_check(ally.display_name == "GM-II", "ally display_name resolves from template")

	var status = ally.get_node_or_null("EnemyStatus")
	_check(status != null, "ally has an EnemyStatus billboard node")
	if status:
		_check(status.name_label != null, "billboard built a name label for allies")
		if status.name_label:
			_check(status.name_label.text == "GM-II", "billboard name label shows the pilot name")
		else:
			_check(false, "billboard name label text readable")

	# Damage the ally hard enough to reach the frame, then confirm its
	# health_percent drops (the value the squad panel shows on its bar).
	var hp_before = ally.health_system.get_health_percent()
	ally.take_damage(60.0)
	await get_tree().process_frame
	_check(ally.health_system.get_health_percent() < hp_before, "ally HP drops after damage")
	await get_tree().process_frame

	ally.queue_free()
	await get_tree().process_frame


func _verify_squad_panel() -> void:
	# Spawn the panel (normally a child of game_world.tscn) and two fielded
	# allies with distinct templates.
	var squad_hud = load("res://scripts/ui/squad_hud.gd").new()
	add_child(squad_hud)
	await get_tree().process_frame

	var scene = load("res://scenes/mecha/ally_dummy.tscn")
	var gm = scene.instantiate()
	gm.template_id = "ally_gm"
	add_child(gm)
	var serra = scene.instantiate()
	serra.template_id = "ally_serra"
	serra.position = Vector3(5, 0, 0)
	add_child(serra)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(squad_hud.rows.size() == 2, "squad panel tracks both fielded allies")
	if squad_hud.rows.size() == 2:
		_check(squad_hud.rows.has("ally_gm"), "squad panel has row for ally_gm")
		_check(squad_hud.rows.has("ally_serra"), "squad panel has row for ally_serra")
		var gm_label: Label = squad_hud.rows["ally_gm"]["label"]
		var serra_label: Label = squad_hud.rows["ally_serra"]["label"]
		_check(gm_label.text == "GM-II", "squad row label shows pilot name")
		_check(serra_label.text == "Serra Voss", "squad row shows recruited pilot name")
	else:
		_check(false, "squad panel row contents inspectable")

	# Live HP: damage one ally (30 breaks body armor but leaves the frame intact,
	# so the unit survives and the signal-driven bar update is the ONLY change).
	var bar_before: float = squad_hud.rows["ally_gm"]["bar"].value
	gm.take_damage(30.0)
	# One frame for the health_changed -> ally_squad_updated signal, one more
	# for the panel's _process reconcile pass.
	await get_tree().process_frame
	await get_tree().process_frame
	var gm_bar: ProgressBar = squad_hud.rows["ally_gm"]["bar"]
	_check(gm_bar.value < bar_before, "squad bar drops when the ally takes damage")

	# Ally destroyed -> the panel's reconcile drops its row on the next pass.
	gm.health_system.set("is_destroyed", true)
	gm._emit_squad_hp()
	# Frames for the signal, the reconcile rebuild, and the row removal to
	# settle (each rebuild pass removes the row and re-frees the old UI).
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not squad_hud.rows.has("ally_gm"), "destroyed ally row removed on reconcile")
	_check(squad_hud.rows.has("ally_serra"), "surviving ally row kept")

	gm.queue_free()
	serra.queue_free()
	squad_hud.queue_free()
	await get_tree().process_frame
