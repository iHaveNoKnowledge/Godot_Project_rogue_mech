extends Node

## Mid-Battle Injection System (GDD §7.3)
##
## Two types of mid-battle events that can trigger during combat:
## 1. Reinforcements — third-party enemies spawn after a delay
## 2. Countdown Extraction — area is being bombed, escape before timer runs out

# Reinforcement types that can spawn as third-party.
const REINFORCEMENT_TYPES: Array = [
	{"type": "rusher_simple", "archetype": 0, "count": 2},
	{"type": "ranged_simple", "archetype": 1, "count": 2},
	{"type": "heavy_full", "archetype": 2, "count": 1},
]

# Signal emitted when countdown extraction starts.
signal countdown_extraction_started(time_limit: float)
# Signal emitted when countdown reaches zero.
signal countdown_extraction_expired()


func _ready() -> void:
	EventBus.combat_ended.connect(_on_combat_ended)


func _on_combat_ended(_victory: bool) -> void:
	# Clear mid-battle state when combat ends.
	GlobalData.mid_battle_reinforcements_active = false
	GlobalData.mid_battle_reinforcements_timer = 0.0
	GlobalData.mid_battle_countdown_active = false
	GlobalData.mid_battle_countdown_timer = 0.0


func _process(delta: float) -> void:
	# Process reinforcements timer.
	if GlobalData.mid_battle_reinforcements_active:
		GlobalData.mid_battle_reinforcements_timer -= delta
		if GlobalData.mid_battle_reinforcements_timer <= 0.0:
			_spawn_reinforcements()
			GlobalData.mid_battle_reinforcements_active = false

	# Process countdown extraction timer.
	if GlobalData.mid_battle_countdown_active:
		GlobalData.mid_battle_countdown_timer -= delta
		if GlobalData.mid_battle_countdown_timer <= 0.0:
			# Time's up — player failed to escape. Deal massive damage.
			_countdown_expired()
			GlobalData.mid_battle_countdown_active = false


## Starts a reinforcement event: third-party enemies will spawn after a delay.
func trigger_reinforcements(delay: float = 20.0) -> void:
	GlobalData.mid_battle_reinforcements_active = true
	GlobalData.mid_battle_reinforcements_timer = delay
	# Announce to the player.
	EventBus.event_triggered.emit({
		"name": "⚠ REINFORCEMENTS INBOUND",
		"effect": "none",
		"amount": 0,
		"desc": "Third-party hostiles approaching! ETA %ds." % int(delay),
	})


## Starts a countdown extraction event: escape or die.
func trigger_countdown_extraction(time_limit: float = 45.0) -> void:
	GlobalData.mid_battle_countdown_active = true
	GlobalData.mid_battle_countdown_timer = time_limit
	GlobalData.mid_battle_countdown_max = time_limit
	countdown_extraction_started.emit(time_limit)
	EventBus.event_triggered.emit({
		"name": "☢ EXTRACTION COUNTDOWN",
		"effect": "none",
		"amount": 0,
		"desc": "Area bombing imminent! Reach the escape zone within %ds or be destroyed!" % int(time_limit),
	})


func _spawn_reinforcements() -> void:
	# Find the SpawnManager and add a bonus wave.
	var spawn_mgr = get_tree().current_scene.get_node_or_null("SpawnManager")
	if spawn_mgr == null or not spawn_mgr.has_method("_spawn_next_wave"):
		return

	# Pick a random reinforcement composition.
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var composition = REINFORCEMENT_TYPES[rng.randi_range(0, REINFORCEMENT_TYPES.size() - 1)]

	# Spawn the enemies using the existing spawn system.
	var scene_path = spawn_mgr.enemy_scene_paths.get(composition["type"], "")
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		return

	var scene = load(scene_path) as PackedScene
	if scene == null:
		return

	# Spawn at the ring edges.
	var spawn_points = spawn_mgr.spawn_points
	for i in range(composition["count"]):
		if spawn_points.is_empty():
			break
		var point_idx = rng.randi_range(0, spawn_points.size() - 1)
		var spawn_pos = spawn_points[point_idx].global_position

		var enemy = scene.instantiate()
		enemy.add_to_group("enemy")
		get_tree().current_scene.add_child(enemy)
		enemy.global_position = spawn_pos

		# Apply archetype stats if the enemy has the method.
		if enemy.has_method("apply_archetype"):
			enemy.apply_archetype(composition["archetype"])

	# Announce the arrival.
	EventBus.event_triggered.emit({
		"name": "🔴 REINFORCEMENTS ARRIVED",
		"effect": "none",
		"amount": 0,
		"desc": "Third-party hostiles have entered the battlefield!",
	})


func _countdown_expired() -> void:
	# Deal heavy damage to the player mech — the area is being bombarded.
	var mecha = GameManager.get_player_mecha()
	if mecha and mecha.has_method("take_damage"):
		mecha.take_damage(80.0, "explosive")
		countdown_extraction_expired.emit()
		EventBus.event_triggered.emit({
			"name": "☢ BOMBARDMENT HIT",
			"effect": "none",
			"amount": 0,
			"desc": "The bombardment struck! Critical damage sustained.",
		})
