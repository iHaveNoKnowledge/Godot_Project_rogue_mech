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

# Fan-out offsets for squad fire-team members around their commander (center).
const SQUAD_FORMATION: Array[Vector3] = [
	Vector3(-3.5, 0, 1.5),
	Vector3(3.5, 0, 1.5),
	Vector3(-6.5, 0, 3.0),
	Vector3(6.5, 0, 3.0),
	Vector3(-9.5, 0, 4.5),
	Vector3(9.5, 0, 4.5),
	Vector3(0, 0, 3.0),
]

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

# Per-theme grunt (standard node) wave defs. Military themes field organized
# squad fire teams (1 commander + squad-size members); scavengers stay ragtag.
var theme_grunt_wave_defs: Dictionary = {
	"soldier": [
		[{"type": "rusher_simple", "archetype": 0, "count": 5}],
		[{"type": "ranged_simple", "archetype": 1, "count": 3},
		 {"type": "rusher_simple", "archetype": 0, "count": 2}],
	],
	"gundam_merc": [
		[{"type": "ranged_simple", "archetype": 1, "count": 4},
		 {"type": "support_simple", "archetype": 3, "count": 1}],
		[{"type": "rusher_simple", "archetype": 0, "count": 2},
		 {"type": "ranged_simple", "archetype": 1, "count": 3}],
	],
	"scavenger": [
		[{"type": "rusher_simple", "archetype": 0, "count": 3}],
		[{"type": "rusher_simple", "archetype": 0, "count": 2},
		 {"type": "ranged_simple", "archetype": 1, "count": 2}],
	],
}

var theme_ace_wave_defs: Dictionary = {
	"soldier": [
		[{"type": "rusher_full", "archetype": 0, "count": 3},
		 {"type": "support_simple", "archetype": 3, "count": 2}],
		[{"type": "heavy_full", "archetype": 2, "count": 2},
		 {"type": "ranged_full", "archetype": 1, "count": 3}],
	],
	"gundam_merc": [
		[{"type": "ranged_full", "archetype": 1, "count": 4},
		 {"type": "heavy_full", "archetype": 2, "count": 1}],
		[{"type": "heavy_full", "archetype": 2, "count": 3},
		 {"type": "ranged_full", "archetype": 1, "count": 2}],
	],
	"scavenger": [
		[{"type": "rusher_full", "archetype": 0, "count": 2},
		 {"type": "support_simple", "archetype": 3, "count": 1}],
		[{"type": "heavy_full", "archetype": 2, "count": 1},
		 {"type": "ranged_full", "archetype": 1, "count": 2}],
	],
}


func _get_active_defs() -> Array:
	match GameManager.combat_node_type:
		"boss":
			return theme_boss_wave_defs.get(GlobalData.theme_id, boss_wave_defs)
		"ace":
			return theme_ace_wave_defs.get(GlobalData.theme_id, ace_wave_defs)
		_:
			return theme_grunt_wave_defs.get(GlobalData.theme_id, grunt_wave_defs)


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
	var arena_gen = get_node_or_null("../ArenaGenerator")
	var is_river_bridge: bool = arena_gen != null and arena_gen.current_theme == 3
	for i in range(12):
		var angle = (i / 12.0) * TAU
		var pos = Vector3(cos(angle) * half, 0.05, sin(angle) * half)
		# On RIVER_BRIDGE the riverbanks are raised (top ~ +0.5) and the water
		# trench (|z| < 22) is below the banks, so keep spawns on dry land and
		# lift them onto the bank surface.
		if is_river_bridge:
			if absf(pos.z) < 22.0:
				continue
			pos.y = 0.55
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
	var mecha = GameManager.get_player_mecha()
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
	hp_scale *= GlobalData.get_enemy_grunt_multiplier()
	var extra_count = mini(wanted, 2)
	var org: Dictionary = _get_org_config()
	var style := str(org.get("style", "ragtag"))

	for entry in wave_def:
		var count = entry["count"]
		if entry["archetype"] != 2 and entry["type"] != "boss_overlord":
			count += extra_count

		var final_hp_scale = hp_scale * (3.5 if entry["type"] == "boss_overlord" else 1.0)

		if style == "squad":
			# Military themes field each entry as one fire team: a full-rig
			# commander (accent shoulders) + the rest as standard members around it.
			_spawn_squad(entry, count, final_hp_scale, org)
		else:
			# Ragtag factions scatter and every unit gets its own worn paint job.
			for j in range(count):
				_spawn_enemy(
					entry["type"], entry["archetype"], _get_spawn_position(),
					final_hp_scale, "", _paint_for_enemy(org, "member")
				)


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
	var ace_kind = GlobalData.stalking_aces.pop_front()
	GlobalData.stalking_chance = 0.0
	_consume_enemy_special_unit(str(ace_kind))
	print("SIREN WARNING! STALKING ACE WARPING IN!")
	AudioManager.play_combat_music("ace")
	var spawn_pos = _get_spawn_position()

	# Give each counter-unit a distinct battlefield identity instead of both
	# being plain heavy units: a special ace is a brutal melee stalker, while a
	# gundam copy is a slower, armored threat that mirrors heavier mech tech.
	var scene_type := "heavy_full"
	var archetype := 2
	var hp_scale := 2.2
	if ace_kind == "gundam_copy":
		scene_type = "tank_full"
		archetype = 1
		hp_scale = 2.6
	_spawn_enemy(scene_type, archetype, spawn_pos, hp_scale)


# A completed research node records its deployed counter-unit in
# enemy_special_units. Once it actually fights (and is defeated), clear that
# record so it is not re-fielded later.
func _consume_enemy_special_unit(kind: String) -> void:
	if kind == "":
		return
	for i in range(GlobalData.enemy_special_units.size()):
		var unit = GlobalData.enemy_special_units[i]
		if unit is Dictionary and unit.get("kind", "") == kind:
			GlobalData.enemy_special_units.remove_at(i)
			return


func _spawn_enemy(type: String, archetype: int, pos: Vector3, hp_scale: float, squad_role: String = "", paint: Dictionary = {}) -> void:
	var scene = _get_enemy_scene(type)
	if scene == null:
		return

	var enemy = scene.instantiate()
	enemy.archetype = archetype
	enemy.position = pos
	# Only squads/full-rig enemies declare these — tanks (enemy_tank.gd) don't,
	# so guard the assignment or Godot prints "Invalid set index" on every tank spawn.
	# enemy.get() returns null only when the property does not exist.
	if enemy.get("squad_role") != null:
		enemy.squad_role = squad_role
	if enemy.get("faction_paint") != null:
		enemy.faction_paint = paint

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


# The run theme's enemy organization config (style/paint/variance), see
# run_theme_catalogs.tres -> enemy_org. Defaults to a ragtag scatter.
func _get_org_config() -> Dictionary:
	return ThemeSystem.get_run_theme().get("enemy_org", {})


# Returns the paint dictionary to hand an enemy. Squad members keep the faction
# colors; ragtag units (paint_variance > 0) get a hue-shifted, worn paint job so
# no two look alike.
func _paint_for_enemy(org: Dictionary, role: String) -> Dictionary:
	var paint: Dictionary = (org.get("paint", {}) as Dictionary).duplicate(true)
	var variance := float(org.get("paint_variance", 0.0))
	if variance > 0.0 and paint.has("base"):
		var base: Color = paint["base"]
		var shift := randf_range(-variance, variance)
		paint["base"] = Color.from_hsv(
			fposmod(base.h + shift, 1.0),
			clampf(base.s, 0.15, 1.0),
			base.v
		)
		paint["trim"] = Color.from_hsv(
			fposmod(base.h + shift * 0.5, 1.0),
			base.s,
			base.v * 0.35
		)
	return paint


# Spawns one squad fire team for military themes: the leader (full-rig variant
# so it reads as a commander) stands at the center with the other members fanned
# out behind it. `count` covers the whole team (leader + members).
func _spawn_squad(entry: Dictionary, count: int, hp_scale: float, org: Dictionary) -> void:
	if count <= 0:
		return
	var center: Vector3 = _get_spawn_position()
	var leader_type: String = _squad_leader_type(entry["type"])
	_spawn_enemy(leader_type, entry["archetype"], center, hp_scale, "commander", _paint_for_enemy(org, "commander"))
	for i in range(1, count):
		var offset: Vector3 = SQUAD_FORMATION[(i - 1) % SQUAD_FORMATION.size()]
		_spawn_enemy(entry["type"], entry["archetype"], center + offset, hp_scale, "member", _paint_for_enemy(org, "member"))


# The squad commander fields the full-rig variant of its archetype (more part
# slots, tankier) so it stands out from the simple grunts around it.
func _squad_leader_type(entry_type: String) -> String:
	match entry_type:
		"rusher_simple":
			return "rusher_full"
		"ranged_simple":
			return "ranged_full"
		"support_simple":
			return "support_full"
		_:
			return entry_type


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
