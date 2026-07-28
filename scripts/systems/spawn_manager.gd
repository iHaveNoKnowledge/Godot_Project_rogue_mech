extends Node3D

## Manages enemy spawning in waves during combat.

var enemy_scenes: Dictionary = {
	"rusher_simple": preload("res://scenes/mecha/enemy_dummy.tscn"),
	"rusher_full": preload("res://scenes/mecha/enemy_dummy_full.tscn"),
	"ranged_simple": preload("res://scenes/mecha/enemy_dummy.tscn"),
	"ranged_full": preload("res://scenes/mecha/enemy_ranged.tscn"),
	"heavy_full": preload("res://scenes/mecha/enemy_heavy.tscn"),
	"support_simple": preload("res://scenes/mecha/enemy_dummy.tscn"),
	"support_full": preload("res://scenes/mecha/enemy_support.tscn"),
	"tank_full": preload("res://scenes/mecha/enemy_tank.tscn"),
}

var waves: Array = []
var current_wave: int = 0
var total_waves: int = 5
var enemies_alive: int = 0
var spawn_points: Array = []
var is_active: bool = false

# Wave definitions
var wave_defs = [
	# Wave 1: Tutorial - 3 rushers
	[{"type": "rusher_simple", "archetype": 0, "count": 3}],
	# Wave 2: Introduce ranged
	[{"type": "rusher_simple", "archetype": 0, "count": 2},
	 {"type": "ranged_simple", "archetype": 1, "count": 1}],
	# Wave 3: Full rusher + support
	[{"type": "rusher_full", "archetype": 0, "count": 1},
	 {"type": "ranged_simple", "archetype": 1, "count": 2},
	 {"type": "support_simple", "archetype": 3, "count": 1}],
	# Wave 4: Heavy + Tank appears
	[{"type": "rusher_full", "archetype": 0, "count": 1},
	 {"type": "tank_full", "archetype": 1, "count": 1},
	 {"type": "heavy_full", "archetype": 2, "count": 1}],
	# Wave 5: Boss wave + Tank support
	[{"type": "heavy_full", "archetype": 2, "count": 1},
	 {"type": "tank_full", "archetype": 1, "count": 1},
	 {"type": "support_full", "archetype": 3, "count": 1},
	 {"type": "ranged_full", "archetype": 1, "count": 1}],
]



func _ready() -> void:
	# Generate spawn points around arena perimeter
	_generate_spawn_points()
	# Start spawning after a brief delay
	await get_tree().create_timer(1.0).timeout
	start_waves()


func _generate_spawn_points() -> void:
	var half = 55.0  # Inside walls
	for i in range(8):
		var angle = (i / 8.0) * TAU
		var pos = Vector3(cos(angle) * half, 1.0, sin(angle) * half)
		var marker = Marker3D.new()
		marker.position = pos
		add_child(marker)
		spawn_points.append(marker)


func start_waves() -> void:
	is_active = true
	current_wave = 0
	_spawn_next_wave()


func _spawn_next_wave() -> void:
	if current_wave >= wave_defs.size():
		# All waves complete
		is_active = false
		await get_tree().create_timer(2.0).timeout
		if _get_alive_count() == 0:
			if not GlobalData.stalking_aces.is_empty():
				_trigger_stalking_ace_ambush()
				return
			EventBus.combat_ended.emit(true)
			GameManager.return_to_board()
		return

	var wave_def = wave_defs[current_wave]
	current_wave += 1

	# Apply wanted level scaling
	var wanted = GlobalData.wanted_level
	var hp_scale = 1.0 + min(wanted, 5) * 0.15
	var extra_count = mini(wanted, 3)

	for entry in wave_def:
		var count = entry["count"]
		# Add extra enemies from wanted level
		if entry["archetype"] != 2:  # Don't add extra heavies
			count += extra_count

		for j in range(count):
			var spawn_pos = _get_spawn_position()
			_spawn_enemy(entry["type"], entry["archetype"], spawn_pos, hp_scale)

	# Wait between waves
	await get_tree().create_timer(4.0).timeout
	_spawn_next_wave()


func _trigger_stalking_ace_ambush() -> void:
	var ace_data = GlobalData.stalking_aces.pop_front()
	GlobalData.ambush_probability = 0.0
	print("SIREN WARNING! STALKING ACE WARPING IN!")
	var spawn_pos = _get_spawn_position()
	_spawn_enemy("heavy_full", 2, spawn_pos, 1.8)



func _spawn_enemy(type: String, archetype: int, pos: Vector3, hp_scale: float) -> void:
	if not enemy_scenes.has(type):
		return

	var scene = enemy_scenes[type]
	var enemy = scene.instantiate()
	enemy.archetype = archetype
	enemy.position = pos

	# Apply HP scaling after ready
	add_child(enemy)
	await enemy.ready

	if enemy.health_system:
		for slot in enemy.health_system.parts:
			enemy.health_system.parts[slot]["armor_hp"] *= hp_scale
			enemy.health_system.parts[slot]["max_armor"] *= hp_scale
			enemy.health_system.parts[slot]["frame_hp"] *= hp_scale
			enemy.health_system.parts[slot]["max_frame"] *= hp_scale
		enemy.health_system._calculate_totals()

	enemies_alive += 1


func _get_spawn_position() -> Vector3:
	if spawn_points.is_empty():
		return Vector3(randf_range(-40, 40), 1.0, randf_range(-40, 40))

	# Pick a random spawn point, avoid clustering
	var available = spawn_points.duplicate()
	available.shuffle()
	return available[0].global_position


func _get_alive_count() -> int:
	var count = 0
	var enemies = get_tree().get_nodes_in_group("enemy")
	for e in enemies:
		if is_instance_valid(e) and e.health_system and not e.health_system.is_destroyed:
			count += 1
	return count


func get_current_wave() -> int:
	return current_wave


func get_total_waves() -> int:
	return wave_defs.size()
