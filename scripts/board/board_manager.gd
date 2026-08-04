extends Node3D

@onready var tile_container: Node3D = $TileContainer
@onready var player_token: MeshInstance3D = $PlayerToken

var current_pos: Vector2i = Vector2i.ZERO
var nodes_dict: Dictionary = {}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var generator = get_node_or_null("BoardGenerator")
	if generator:
		var data = generator.generate_board()
		nodes_dict = data["nodes"]
		
		# Add tiles to container
		for key in nodes_dict:
			tile_container.add_child(nodes_dict[key])

		# Generate 3D visual path bridges between connected nodes
		for key in nodes_dict:
			var tile = nodes_dict[key]
			if tile.has_method("create_path_visuals"):
				tile.create_path_visuals(nodes_dict)

	current_pos = GlobalData.current_tile
	if not nodes_dict.has(current_pos):
		current_pos = Vector2i(0, 0)
		GlobalData.current_tile = current_pos

	_update_token_position()
	_highlight_adjacent()


func move_to_tile(target: Vector2i) -> bool:
	if not _is_connected_path(current_pos, target):
		print("Invalid path! Must follow connected branching node paths.")
		return false

	current_pos = target
	GlobalData.current_tile = target
	_update_token_position()
	_clear_highlights()
	_highlight_adjacent()

	var tile_data = nodes_dict[target]
	var tile_type = tile_data.get_meta("tile_type", "empty")

	# Turn Mobilization & Stalking Ace Interception
	process_turn_mobilization()
	accumulate_stalker_chance()

	EventBus.tile_entered.emit(target, tile_data)
	_process_tile_effect(tile_type)

	if tile_type not in ["combat", "exit"]:
		var intermission = get_node_or_null("IntermissionUI")
		if intermission:
			intermission.visible = true
			intermission.status_label.text = intermission._get_status_text()
	return true


func _is_connected_path(from_key: Vector2i, to_key: Vector2i) -> bool:
	if not nodes_dict.has(from_key):
		return false
	var from_tile = nodes_dict[from_key]
	var connects = from_tile.get_meta("connections", [])
	return to_key in connects


func _highlight_adjacent() -> void:
	if not nodes_dict.has(current_pos):
		return
	var current_tile = nodes_dict[current_pos]
	var connects = current_tile.get_meta("connections", [])
	for target_key in connects:
		if nodes_dict.has(target_key):
			nodes_dict[target_key].highlight(true)


func _clear_highlights() -> void:
	for key in nodes_dict:
		nodes_dict[key].highlight(false)


func _update_token_position() -> void:
	if nodes_dict.has(current_pos):
		var tile = nodes_dict[current_pos]
		player_token.global_position = tile.global_position + Vector3(0, 0.5, 0)


# Turn mobilization refilling (Low Heat Grace Period: suppressed when Heat < 3)
func process_turn_mobilization() -> void:
	if GlobalData.heat < 3:
		# Low Heat Grace Period: Mobilization suppressed to keep early-game accessible
		return

	var grunt_recruit = int(GlobalData.enemy_forces["grunt_max"] * randf_range(0.10, 0.20))
	GlobalData.enemy_forces["grunt_current"] = clampi(
		GlobalData.enemy_forces["grunt_current"] + grunt_recruit, 
		0, GlobalData.enemy_forces["grunt_max"]
	)

	if randf() < 0.30:
		GlobalData.enemy_forces["ace_current"] = clampi(
			GlobalData.enemy_forces["ace_current"] + 1, 
			0, GlobalData.enemy_forces["ace_max"]
		)


func accumulate_stalker_chance() -> void:
	if not GlobalData.stalking_aces.is_empty():
		GlobalData.stalking_chance = minf(GlobalData.stalking_chance + 0.20, 1.0)


func _process_tile_effect(tile_type: String) -> void:
	match tile_type:
		"combat":
			if not GlobalData.stalking_aces.is_empty() and randf() < GlobalData.stalking_chance:
				_trigger_stalker_surprise_ambush()
			else:
				GameManager.enter_combat("grunt")
		"event":
			_trigger_random_event()
		"safehouse":
			HeatWantedSystem.modify_heat(-4)
			var safehouse = get_node_or_null("../SafehouseUI")
			if safehouse:
				safehouse.visible = true
				get_tree().paused = true
		"data_node":
			_trigger_data_node_event()
		"dead_end":
			_trigger_dead_end_event()
		"start":
			print("Entering Hangar Practice Ground.")
		"exit":
			_trigger_exit_event()
		_:
			pass


func _trigger_data_node_event() -> void:
	GlobalData.data_cores += 2
	var event = {
		"name": "Data Terminal Extraction",
		"effect": "data_cores",
		"amount": 2,
		"desc": "Extracted blueprint data core! +2 Data Cores."
	}
	EventBus.event_triggered.emit(event)


func _trigger_dead_end_event() -> void:
	var event = {
		"name": "Hidden Dead End",
		"effect": "dead_end",
		"amount": 0,
		"desc": "Approached a hidden wall/obstacle! Reroute path required."
	}
	EventBus.event_triggered.emit(event)


func _trigger_exit_event() -> void:
	print("Entering Extraction Zone / Final Boss Battle!")
	GameManager.enter_combat("boss")


func _trigger_stalker_surprise_ambush() -> void:
	var active_stalker = GlobalData.stalking_aces[0]
	GlobalData.stalking_chance = 0.0

	var safehouse_ui = get_node_or_null("../SafehouseUI")
	if safehouse_ui:
		safehouse_ui.status_label.text = "SIREN WARNING! Stalking Ace: " + active_stalker + " Ambushed!"

	GameManager.enter_combat("ace")


func _trigger_random_event() -> void:
	var events = [
		{"name": "Abandoned Cache", "effect": "credits", "amount": 50, "desc": "Found abandoned cache! +50 credits"},
		{"name": "Salvage Cache", "effect": "scrap", "amount": 15, "desc": "Salvaged scrap cache! +15 scrap"},
		{"name": "Ambush", "effect": "damage", "amount": 20, "desc": "Ambushed by partisans! Took 20 damage"},
		{"name": "Friendly Trader", "effect": "credits", "amount": 30, "desc": "Friendly trader caravan! +30 credits"},
		{"name": "Data Terminal", "effect": "data_cores", "amount": 1, "desc": "Hacked old terminal! +1 data core"},
	]
	var event = events[randi() % events.size()]
	EventBus.event_triggered.emit(event)

	match event["effect"]:
		"credits":
			GlobalData.credits += event["amount"]
		"data_cores":
			GlobalData.data_cores += event["amount"]
		"scrap":
			GlobalData.scrap += event["amount"]
		"damage":
			if not GlobalData.equipped_parts.is_empty():
				var keys = GlobalData.equipped_parts.keys()
				var rand_part = keys[randi() % keys.size()]
				var cur_dmg = GlobalData.part_damage.get(rand_part, 0.0)
				GlobalData.part_damage[rand_part] = minf(cur_dmg + 0.25, 1.0)


func get_tile_type(pos: Vector2i) -> String:
	if nodes_dict.has(pos):
		return nodes_dict[pos].get_meta("tile_type", "empty")
	return "empty"
