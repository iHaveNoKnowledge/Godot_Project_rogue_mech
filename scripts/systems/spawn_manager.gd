extends Node3D

## Manages enemy spawning in waves during combat.

var enemy_scene_paths: Dictionary = {
	"rusher_simple": "res://scenes/mecha/enemy_dummy.tscn",
	"rusher_full": "res://scenes/mecha/enemy_dummy_full.tscn",
	"ranged_simple": "res://scenes/mecha/enemy_dummy.tscn",
	"ranged_full": "res://scenes/mecha/enemy_ranged.tscn",
	"heavy_full": "res://scenes/mecha/enemy_heavy.tscn",
	"support_simple": "res://scenes/mecha/enemy_dummy.tscn",
	"support_full": "res://scenes/mecha/enemy_support.tscn",
	"tank_full": "res://scenes/mecha/enemy_tank.tscn",
	"boss_overlord": "res://scenes/mecha/enemy_boss.tscn",
}

var _loaded_enemy_scenes: Dictionary = {}


func _get_enemy_scene(type: String) -> PackedScene:
	if _loaded_enemy_scenes.has(type):
		return _loaded_enemy_scenes[type]

	if enemy_scene_paths.has(type):
		var path = enemy_scene_paths[type]
		if ResourceLoader.exists(path):
			var scene = load(path) as PackedScene
			if scene:
				_loaded_enemy_scenes[type] = scene
				return scene

	if type == "boss_overlord":
		return load("res://scenes/mecha/enemy_heavy.tscn") as PackedScene
	return null

var waves: Array = []
var current_wave: int = 0
var total_waves: int = 5
var enemies_alive: int = 0
var spawn_points: Array = []
var is_active: bool = false

# Node-Specific Wave Definitions
var grunt_wave_defs = [
	[{"type": "rusher_simple", "archetype": 0, "count": 3}],
	[{"type": "rusher_simple", "archetype": 0, "count": 2},
	 {"type": "ranged_simple", "archetype": 1, "count": 2}],
]

var ace_wave_defs = [
	[{"type": "rusher_simple", "archetype": 0, "count": 3},
	 {"type": "ranged_simple", "archetype": 1, "count": 1}],
	[{"type": "rusher_full", "archetype": 0, "count": 2},
	 {"type": "support_simple", "archetype": 3, "count": 1}],
	[{"type": "heavy_full", "archetype": 2, "count": 1},
	 {"type": "ranged_full", "archetype": 1, "count": 2}],
]

var boss_wave_defs = [
	[{"type": "tank_full", "archetype": 1, "count": 2},
	 {"type": "support_full", "archetype": 3, "count": 1}],
	[{"type": "heavy_full", "archetype": 2, "count": 2},
	 {"type": "ranged_full", "archetype": 1, "count": 2}],
	[{"type": "boss_overlord", "archetype": 2, "count": 1},
	 {"type": "support_full", "archetype": 3, "count": 2}],
]

# Per-theme boss compositions. Keyed by theme_id; falls back to boss_wave_defs.
var theme_boss_wave_defs: Dictionary = {
	"soldier": [
		[{"type": "tank_full", "archetype": 1, "count": 3},
		 {"type": "ranged_full", "archetype": 1, "count": 2}],
		[{"type": "heavy_full", "archetype": 2, "count": 3},
		 {"type": "support_full", "archetype": 3, "count": 2}],
		[{"type": "boss_overlord", "archetype": 2, "count": 1},
		 {"type": "heavy_full", "archetype": 2, "count": 2},
		 {"type": "support_full", "archetype": 3, "count": 1}],
	],
	"gundam_merc": [
		[{"type": "ranged_full", "archetype": 1, "count": 3},
		 {"type": "heavy_full", "archetype": 2, "count": 1}],
		[{"type": "heavy_full", "archetype": 2, "count": 2},
		 {"type": "ranged_full", "archetype": 1, "count": 3}],
		[{"type": "boss_overlord", "archetype": 2, "count": 1},
		 {"type": "heavy_full", "archetype": 2, "count": 2}],
	],
	"scavenger": [
		[{"type": "tank_full", "archetype": 1, "count": 2},
		 {"type": "support_full", "archetype": 3, "count": 2}],
		[{"type": "heavy_full", "archetype": 2, "count": 2},
		 {"type": "ranged_full", "archetype": 1, "count": 2}],
		[{"type": "boss_overlord", "archetype": 2, "count": 1},
		 {"type": "support_full", "archetype": 3, "count": 2}],
	],
}


func _get_active_defs() -> Array:
	match GameManager.combat_node_type:
		"boss":
			return theme_boss_wave_defs.get(GlobalData.theme_id, boss_wave_defs)
		"ace":
			return ace_wave_defs
		_:
			return grunt_wave_defs


func _ready() -> void:
	_generate_spawn_points()
	_spawn_fielded_allies()
	# Snapshot friendly combat HP after the player mech + allies are in the scene,
	# so the decisive-victory check knows the combined HP of our fielded side.
	GlobalData.begin_combat_stats()
	await get_tree().create_timer(1.0).timeout
	start_waves()


func _generate_spawn_points() -> void:
	var half = 110.0  # Inside 240m walls
	for i in range(12):
		var angle = (i / 12.0) * TAU
		var pos = Vector3(cos(angle) * half, 0.05, sin(angle) * half)
		var marker = Marker3D.new()
		marker.position = pos
		add_child(marker)
		spawn_points.append(marker)


# Spawn all fielded allied units from the fleet so they fight alongside the
# player (GM vs Zaku — our side tags into battle).
func _spawn_fielded_allies() -> void:
	var fielded = GlobalData.get_fielded_units()
	if fielded.is_empty():
		return
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	var anchor = mecha.global_position if mecha else Vector3.ZERO
	var i := 0
	for unit in fielded:
		var template = GlobalData.get_ally_template(unit.get("template_id", ""))
		if template.is_empty():
			continue
		var scene_path = str(template.get("scene_path", "res://scenes/mecha/ally_dummy.tscn"))
		if not ResourceLoader.exists(scene_path):
			continue
		var ally_scene = load(scene_path) as PackedScene
		if ally_scene == null:
			continue
		var ally_unit = ally_scene.instantiate()
		ally_unit.template_id = unit.get("template_id", "")
		i += 1
		# Fan allies out behind/around the player.
		var angle = (PI / 2.0) + (i - 1) * -(0.5)
		var offset = Vector3(cos(angle) * 6.0, 0.0, sin(angle) * 6.0)
		if mecha == null:
			offset = Vector3(4.0 * i, 0.0, -2.0)
		ally_unit.position = (anchor + offset) if mecha else offset
		# Positioned near the player, aligned to ground.
		ally_unit.position.y = 0.1
		add_child(ally_unit)


func start_waves() -> void:
	is_active = true
	current_wave = 0
	_spawn_next_wave()


func _spawn_next_wave() -> void:
	var active_defs = _get_active_defs()
	if current_wave >= active_defs.size():
		is_active = false
		_check_combat_ended()
		return

	var wave_def = active_defs[current_wave]
	current_wave += 1

	if current_wave == active_defs.size():
		AudioManager.play_combat_music(GameManager.combat_node_type)

	var wanted = GlobalData.wanted_level
	var hp_scale = 1.0 + min(wanted, 5) * 0.15
	hp_scale *= GlobalData.get_enemy_tech_multiplier()
	var extra_count = mini(wanted, 2)

	for entry in wave_def:
		var count = entry["count"]
		if entry["archetype"] != 2 and entry["type"] != "boss_overlord":
			count += extra_count

		for j in range(count):
			var spawn_pos = _get_spawn_position()
			var final_hp_scale = hp_scale * (3.5 if entry["type"] == "boss_overlord" else 1.0)
			_spawn_enemy(entry["type"], entry["archetype"], spawn_pos, final_hp_scale)


func notify_enemy_killed() -> void:
	await get_tree().create_timer(0.4).timeout
	var active_defs = _get_active_defs()
	if _get_alive_count() == 0:
		if current_wave < active_defs.size():
			_spawn_next_wave()
		else:
			_check_combat_ended()


func _check_combat_ended() -> void:
	if _get_alive_count() == 0:
		if not GlobalData.stalking_aces.is_empty():
			_trigger_stalking_ace_ambush()
		else:
			EventBus.combat_ended.emit(true)


func _trigger_stalking_ace_ambush() -> void:
	var ace_data = GlobalData.stalking_aces.pop_front()
	GlobalData.ambush_probability = 0.0
	print("SIREN WARNING! STALKING ACE WARPING IN!")
	AudioManager.play_combat_music("ace")
	var spawn_pos = _get_spawn_position()
	_spawn_enemy("heavy_full", 2, spawn_pos, 1.8)


func _spawn_enemy(type: String, archetype: int, pos: Vector3, hp_scale: float) -> void:
	var scene = _get_enemy_scene(type)
	if scene == null:
		return

	var enemy = scene.instantiate()
	enemy.archetype = archetype
	enemy.position = pos

	add_child(enemy)
	await enemy.ready

	if enemy.get("health_system") != null:
		for slot in enemy.health_system.parts:
			enemy.health_system.parts[slot]["armor_hp"] *= hp_scale
			enemy.health_system.parts[slot]["max_armor"] *= hp_scale
			enemy.health_system.parts[slot]["frame_hp"] *= hp_scale
			enemy.health_system.parts[slot]["max_frame"] *= hp_scale
		if enemy.health_system.has_method("_calculate_totals"):
			enemy.health_system._calculate_totals()

	enemies_alive += 1


func _get_spawn_position() -> Vector3:
	if spawn_points.is_empty():
		return Vector3(randf_range(-40, 40), 1.0, randf_range(-40, 40))

	var available = spawn_points.duplicate()
	available.shuffle()
	return available[0].global_position


func _get_alive_count() -> int:
	var count = 0
	var enemies = get_tree().get_nodes_in_group("enemy")
	for e in enemies:
		if is_instance_valid(e) and e.get("health_system") != null:
			var hs = e.health_system
			if not hs.get("is_destroyed"):
				count += 1
	return count


func get_current_wave() -> int:
	return current_wave


func get_total_waves() -> int:
	return _get_active_defs().size()
