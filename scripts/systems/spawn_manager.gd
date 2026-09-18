class_name SpawnManager
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
	"shieldmelee_full": "res://scenes/mecha/enemy_shield_melee.tscn",
	"shieldranged_full": "res://scenes/mecha/enemy_shield_ranged.tscn",
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

# Ring markers already handed out this wave, so multiple enemies never stack
# on the same spawn point (adjacent markers are ~57m apart, so a distinct
# marker per enemy is all the separation they need). Reset every wave.
var _used_spawn_indices: Array = []

# Minimum clearance kept between an enemy spawn and any cover object.
const SPAWN_COVER_MARGIN := 2.5

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
	[{"type": "shieldmelee_full", "archetype": 4, "count": 1},
	 {"type": "shieldranged_full", "archetype": 5, "count": 1},
	 {"type": "ranged_full", "archetype": 1, "count": 1}],
]

var boss_wave_defs = [
	[{"type": "tank_full", "archetype": 1, "count": 2},
	 {"type": "support_full", "archetype": 3, "count": 1}],
	[{"type": "heavy_full", "archetype": 2, "count": 2},
	 {"type": "ranged_full", "archetype": 1, "count": 2}],
	[{"type": "shieldmelee_full", "archetype": 4, "count": 2},
	 {"type": "shieldranged_full", "archetype": 5, "count": 1}],
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
		[{"type": "shieldmelee_full", "archetype": 4, "count": 2},
		 {"type": "shieldranged_full", "archetype": 5, "count": 1}],
		[{"type": "boss_overlord", "archetype": 2, "count": 1},
		 {"type": "heavy_full", "archetype": 2, "count": 2},
		 {"type": "support_full", "archetype": 3, "count": 1}],
	],
	"valkyrion_merc": [
		[{"type": "ranged_full", "archetype": 1, "count": 3},
		 {"type": "heavy_full", "archetype": 2, "count": 1}],
		[{"type": "heavy_full", "archetype": 2, "count": 2},
		 {"type": "ranged_full", "archetype": 1, "count": 3}],
		[{"type": "shieldmelee_full", "archetype": 4, "count": 1},
		 {"type": "shieldranged_full", "archetype": 5, "count": 2}],
		[{"type": "boss_overlord", "archetype": 2, "count": 1},
		 {"type": "heavy_full", "archetype": 2, "count": 2}],
	],
	"scavenger": [
		[{"type": "tank_full", "archetype": 1, "count": 2},
		 {"type": "support_full", "archetype": 3, "count": 2}],
		[{"type": "heavy_full", "archetype": 2, "count": 2},
		 {"type": "ranged_full", "archetype": 1, "count": 2}],
		[{"type": "shieldranged_full", "archetype": 5, "count": 2},
		 {"type": "rusher_full", "archetype": 0, "count": 1}],
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
	"valkyrion_merc": [
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
	"valkyrion_merc": [
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
	# Patrol engagement with canonical roster is always a single wave that mirrors the board fleet.
	if GlobalData.board.board_patrol_engagement >= 0:
		var patrol: Dictionary = PatrolSystem.get_patrol_by_id(GlobalData.board.board_patrol_engagement)
		if not patrol.is_empty() and patrol.get("pilots") is Array and not (patrol["pilots"] as Array).is_empty():
			return [[{"type": "patrol_roster", "count": int((patrol["pilots"] as Array).size())}]]
	match GameManager.combat_node_type:
		"boss":
			return theme_boss_wave_defs.get(GlobalData.narrative.theme_id, boss_wave_defs)
		"ace":
			return _get_fleet_scaled_wave_defs("ace")
		"duel":
			return _duel_wave_defs()
		_:
			return _get_fleet_scaled_wave_defs("grunt")


func _get_fleet_scaled_wave_defs(combat_type: String) -> Array:
	var fleet_count := GameManager.combat_fleet_count
	if GlobalData.board.board_patrol_engagement >= 0:
		var p: Dictionary = PatrolSystem.get_patrol_by_id(GlobalData.board.board_patrol_engagement)
		if not p.is_empty():
			fleet_count = maxi(int(p.get("fleet_count", 1)), 1)
	fleet_count = maxi(fleet_count, 1)

	var pool: Array = []
	if combat_type == "ace":
		pool = theme_ace_wave_defs.get(GlobalData.narrative.theme_id, ace_wave_defs)
	else:
		pool = theme_grunt_wave_defs.get(GlobalData.narrative.theme_id, grunt_wave_defs)

	if pool.is_empty():
		pool = grunt_wave_defs

	var active_waves: Array = []
	for i in range(fleet_count):
		var template: Array = pool[i % pool.size()]
		active_waves.append(template.duplicate(true))

	return active_waves


# A duel battle fields exactly one full-rig enemy — the pending character's
# signature mech (equivalent to a strong ace-scale threat).
func _duel_wave_defs() -> Array:
	var character := RecruitSystem.get_pending_character()
	var scene_type := str(character.get("duel_scene", "heavy_full"))
	var archetype := int(character.get("duel_archetype", 2))
	return [[{"type": scene_type, "archetype": archetype, "count": 1}]]


func _ready() -> void:
	# WAR battlefield: no token-based waves — uses WarAIJumpSystem / battlefield spawns instead
	if GameManager.current_state == GameManager.State.WAR:
		_generate_spawn_points()
		# Still snapshot stats but don't start token waves
		CombatStatsSystem.begin_combat_stats()
		return
	_generate_spawn_points()
	_spawn_fielded_allies()
	_spawn_convoy_trucks_if_needed()
	_spawn_forward_base_if_needed()
	# Snapshot friendly combat HP after the player mech + allies are in the scene,
	# so the decisive-victory check knows the combined HP of our fielded side.
	CombatStatsSystem.begin_combat_stats()
	await get_tree().create_timer(1.0).timeout
	start_waves()

func _spawn_convoy_trucks_if_needed() -> void:
	# Wait until StaticBodies are registered in the physics server — a frame-0
	# snap raycast always misses and leaves trucks floating or buried.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var is_defense := GlobalData.board.convoy_defense_active or GameManager.combat_node_type in ["defense", "convoy_ambush", "convoy_breakdown"]
	if not is_defense:
		# Also check if board_tile type was convoy breakdown/ambush
		if not (str(GlobalData.board.combat_tile_terrain) in ["plain", "road"] and GlobalData.board.convoy_defense_waves > 0):
			# Fallback: check if any defense wave active
			if GlobalData.board.convoy_defense_waves == 0:
				return
			if not GlobalData.board.convoy_defense_active:
				return
	var mecha = GameManager.get_player_mecha()
	var anchor: Vector3 = mecha.global_position if mecha and is_instance_valid(mecha) and mecha.is_inside_tree() else Vector3.ZERO
	# Truck count scales with fleet capacity: ceil(fleet/2) trucks (matches HangarManager.get_capacity)
	var truck_count: int = 1
	if HangarManager:
		var fleet := HangarManager.get_fleet_size()
		truck_count = clampi(int(ceil(float(fleet) / 2.0)), 1, 3)
	else:
		var mechs := GlobalData.hangar.hangar_mechs.size() if GlobalData.hangar else 1
		truck_count = clampi(int(ceil(float(maxi(mechs,1)) / 2.0)), 1, 3)
	var is_breakdown := GameManager.combat_node_type == "convoy_breakdown" or GlobalData.board.convoy_defense_waves == 3
	for i in range(truck_count):
		var truck := preload("res://scripts/arena/convoy_truck.gd").new()
		# Use StaticBody instantiation via script on Node3D; need to create StaticBody3D with script
		var truck_node := StaticBody3D.new()
		truck_node.set_script(load("res://scripts/arena/convoy_truck.gd"))
		truck_node.truck_index = i
		truck_node.is_breakdown = is_breakdown
		# Position convoy line behind player (south)
		var offset := Vector3((i - (truck_count-1)*0.5) * 3.2, 0, -6.0 - float(i)*0.3)
		var pos: Vector3 = anchor + offset
		pos = snap_to_ground(pos, get_world_3d().direct_space_state) if get_world_3d() else pos
		truck_node.position = pos
		# Slight yaw to look convoy-like
		truck_node.rotation.y = deg_to_rad(randf_range(-6, 6))
		add_child(truck_node)

func _spawn_forward_base_if_needed() -> void:
	# Same frame-0 physics reason as trucks/allies: settle the base + player
	# only after the ground collision exists.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var is_base := GameManager.combat_node_type in ["enemy_base", "camp", "forward_base"]
	if not is_base:
		# Also check if enemy_base_active and combat is boss-like
		if not GlobalData.narrative.enemy_base_active:
			return
		if GameManager.combat_node_type not in ["boss", "ace", "grunt"]:
			return
		# Only spawn base for enemy_base fights; skip random
		if GameManager.combat_node_type != "enemy_base":
			return
	var kind := "camp"
	if GlobalData.narrative.enemy_base_progress / maxf(GlobalData.narrative.enemy_base_required,1.0) >= 0.5:
		kind = "fortified"
	var base := Node3D.new()
	base.set_script(load("res://scripts/arena/forward_base.gd"))
	add_child(base)
	(base as ForwardBase).spawn_base(kind, Vector3(0, 0, 28))
	# Move player start a bit south to face base
	var mecha = GameManager.get_player_mecha()
	if mecha and is_instance_valid(mecha) and mecha.is_inside_tree():
		var ppos: Vector3 = Vector3(0, 0, -32)
		ppos = snap_to_ground(ppos, get_world_3d().direct_space_state) if get_world_3d() else ppos
		mecha.position = ppos
	# Hook base destruction to victory
	if base.has_signal("base_destroyed"):
		base.base_destroyed.connect(_on_forward_base_destroyed)

func _on_forward_base_destroyed() -> void:
	await get_tree().create_timer(0.6).timeout
	if is_inside_tree() and is_instance_valid(self):
		EventBus.combat_ended.emit(true)


func _generate_spawn_points() -> void:
	var arena_gen = get_node_or_null("../ArenaGenerator")
	var half: float = 110.0  # Inside 240m walls (scaled up for larger fields)
	if arena_gen != null and arena_gen.get("arena_size") != null:
		half = float(arena_gen.arena_size) * 0.46
	var is_river_bridge: bool = arena_gen != null and arena_gen.current_theme == 3
	# A chokepoint/bait ambush closes in from two opposing arcs (a pincer)
	# instead of the full ring, so the player is caught between flanks.
	var is_pincer := GlobalData.board.ambush_pincer
	GlobalData.board.ambush_pincer = false

	# On an irregular footprint the ring follows the real battlefield outline
	# instead of a circular ring (a plain circle would land enemies in the void).
	if arena_gen != null and arena_gen.get("footprint") != null:
		_add_footprint_spawn_points(arena_gen.footprint, is_pincer)
		return

	for i in range(12):
		var angle := (i / 12.0) * TAU
		if is_pincer:
			# Two arcs: front (east) and rear (west), each ~90 degrees wide, so
			# enemies surround the player from the front and behind in a pincer.
			if i < 6:
				angle = deg_to_rad(-45.0 + (i / 5.0) * 90.0)
			else:
				angle = deg_to_rad(135.0 + ((i - 6) / 5.0) * 90.0)
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


# Enemy spawn ring for an irregular footprint: 12 points sampled along the
# outline (by arc-length, so they hug the real shape), ordered by angle around
# the centroid so pincer ambushes still come from two opposing sides.
func _add_footprint_spawn_points(fp: ArenaFootprint, is_pincer: bool) -> void:
	var ring := fp.ring_points(24, 10.0)
	var by_angle: Array = []
	for p in ring:
		var ang := atan2(p.z - fp.centroid.y, p.x - fp.centroid.x)
		by_angle.append({"angle": ang, "point": p})
	by_angle.sort_custom(func(x, y): return x["angle"] < y["angle"])

	var chosen: Array = []
	if is_pincer:
		chosen = _nearest_arc_points(by_angle, 0.0, 6)
		chosen.append_array(_nearest_arc_points(by_angle, PI, 6))
	else:
		for i in range(12):
			chosen.append(by_angle[(i * 2) % by_angle.size()]["point"])

	for i in range(chosen.size()):
		var marker = Marker3D.new()
		marker.position = chosen[i]
		add_child(marker)
		spawn_points.append(marker)


func _nearest_arc_points(by_angle: Array, target: float, count: int) -> Array:
	var sorted := by_angle.duplicate()
	sorted.sort_custom(func(x, y):
		var dx := fposmod(x["angle"] - target + PI, TAU) - PI
		var dy := fposmod(y["angle"] - target + PI, TAU) - PI
		return absf(dx) < absf(dy))
	var out := []
	for i in range(mini(count, sorted.size())):
		out.append(sorted[i]["point"])
	return out


# Spawn all fielded allied units so they fight alongside the player (GM vs Zaku
# — our side tags into battle).
#
# Feature 7 rule: combat allies come ONLY from piloted hangar mechs. A fleet
# unit's `fielded` flag is still the source of truth for whether the pilot tags
# into this battle, but a template-only unit (researched blueprint with no
# seated driver) is no longer fielded by itself — a pilot must drive a berth.
# The shared FleetSystem.get_sortie_units() helper is the single source (also
# used by the hangar SORTIE page + intermission fleet panel).
func _spawn_fielded_allies() -> void:
	# Frame-0 snap rays miss (ground not in the physics server yet) and drop
	# allies under sculpted terrain — wait for registration first.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var mecha = GameManager.get_player_mecha()
	var anchor = mecha.global_position if mecha else Vector3.ZERO
	var i := 0
	for entry in FleetSystem.get_sortie_units():
		var mech: Dictionary = entry.get("mech", {})
		var unit: Dictionary = entry.get("unit", {})
		var template_id := str(unit.get("template_id", ""))
		var template = FleetSystem.get_ally_template(template_id)
		if template.is_empty():
			continue
		var scene_path = str(template.get("scene_path", "res://scenes/mecha/ally_dummy.tscn"))
		if not ResourceLoader.exists(scene_path):
			continue
		var ally_scene = load(scene_path) as PackedScene
		if ally_scene == null:
			continue
		var ally_unit = ally_scene.instantiate()
		ally_unit.template_id = template_id
		i += 1
		# Fan allies out behind/around the player.
		var angle = (PI / 2.0) + (i - 1) * -(0.5)
		var offset = Vector3(cos(angle) * 6.0, 0.0, sin(angle) * 6.0)
		if mecha == null:
			offset = Vector3(4.0 * i, 0.0, -2.0)
		# Positioned near the player and snapped onto the terrain surface (same
		# as enemies) so allies never spawn half-buried or hovering on dunes.
		var ally_pos: Vector3 = (anchor + offset) if mecha else offset
		ally_pos = snap_to_ground(ally_pos, get_world_3d().direct_space_state)
		ally_pos.y -= body_bottom_offset(ally_unit)
		ally_unit.position = ally_pos
		add_child(ally_unit)
		# The berth's combat role + the pilot's name win over the template
		# defaults once the template stats land in _ready, then the mech's ACTUAL
		# loadout (armor plates + equipped weapons) replaces the template stats
		# so the ally fights with the gear on its berth.
		ally_unit.apply_mech_override(
			HangarManager.get_archetype(str(mech.get("id", ""))),
			str(unit.get("name", template.get("name", "ALLY"))),
		)
		ally_unit.apply_mech_loadout(mech)


func start_waves() -> void:
	is_active = true
	current_wave = 0
	_spawn_next_wave()
	# Schedule mid-battle injection events (GDD §7.3).
	_schedule_mid_battle_events()


func _spawn_patrol_roster(hp_scale: float, org: Dictionary) -> bool:
	# Single source of truth: spawn the EXACT pilots stored on the board fleet.
	# Returns true if roster was used (caller should return).
	if GlobalData.board.board_patrol_engagement < 0:
		return false
	var patrol: Dictionary = PatrolSystem.get_patrol_by_id(GlobalData.board.board_patrol_engagement)
	if patrol.is_empty():
		return false
	var pilots: Array = patrol.get("pilots", [])
	if pilots.is_empty():
		return false
	# Fleet stored on board — use its squad_id / name / formation.
	var squad_id: String = str(patrol.get("squad_id", patrol.get("name", "fleet")))
	var squad_name: String = str(patrol.get("squad_name", patrol.get("name", "Fleet")))
	var coordinator := EnemySquadCoordinator.new()
	coordinator.name = "SquadCoordinator_%s" % squad_id
	coordinator.setup_squad(squad_id, squad_name)
	add_child(coordinator)
	var center: Vector3 = _get_spawn_position()
	# Commander at center, wingmen fanned around via SQUAD_FORMATION.
	for i in range(pilots.size()):
		var pilot: Dictionary = pilots[i] as Dictionary
		var archetype: int = int(pilot.get("archetype", 0))
		var scene_type: String = str(pilot.get("scene_type", PilotGenerator._scene_type_for_archetype(archetype, i == 0)))
		var role: String = str(pilot.get("squad_role", "member" if i > 0 else "commander"))
		var pos: Vector3 = center
		if i > 0:
			var slot: int = (i - 1) % SQUAD_FORMATION.size()
			var offset: Vector3 = SQUAD_FORMATION[slot]
			var guard := 0
			while guard < SQUAD_FORMATION.size() and _spawn_blocked_by_cover(center + offset):
				slot = (slot + 1) % SQUAD_FORMATION.size()
				offset = SQUAD_FORMATION[slot]
				guard += 1
			pos = center + offset
		var final_hp: float = hp_scale
		if scene_type == "boss_overlord":
			final_hp *= 3.5
		_spawn_enemy_with_pilot(scene_type, archetype, pos, final_hp, pilot, coordinator, _paint_for_enemy(org, role))
	return true

func _spawn_next_wave() -> void:
	_used_spawn_indices.clear()
	var active_defs = _get_active_defs()
	if current_wave >= active_defs.size():
		is_active = false
		_check_combat_ended()
		return

	var wave_def = active_defs[current_wave]
	current_wave += 1

	if current_wave == active_defs.size():
		AudioManager.play_combat_music(GameManager.combat_node_type)

	var wanted = GlobalData.board.wanted_level
	var hp_scale = 1.0 + min(wanted, 5) * 0.15
	hp_scale *= EnemyFactionSystem.get_enemy_grunt_multiplier()
	var extra_count = mini(wanted, 2)
	var org: Dictionary = _get_org_config()
	var style := str(org.get("style", "ragtag"))

	# A duel fields exactly one signature enemy — the pending character's own
	# mech. It never gains squadmates or extra spawns, and it scales up like an
	# ace so the fight reads as a proper 1v1 challenge.
	if GameManager.combat_node_type == "duel":
		var character := RecruitSystem.get_pending_character()
		var duel_scale := float(character.get("duel_hp_scale", 2.0))
		_spawn_enemy(
			str(character.get("duel_scene", "heavy_full")),
			int(character.get("duel_archetype", 2)),
			_get_spawn_position(),
			hp_scale * duel_scale,
			"commander",
			_paint_for_enemy(org, "commander")
		)
		return

	# Patrol engagement with canonical roster overrides wave defs — single wave spawns whole fleet.
	if _spawn_patrol_roster(hp_scale, org):
		return

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
	var alive := _get_alive_count()
	var active_defs = _get_active_defs()
	print("SPAWN_MGR: notify_enemy_killed — alive=%d wave=%d/%d stalking=%d" % [alive, current_wave, active_defs.size(), GlobalData.narrative.stalking_aces.size()])
	if alive == 0:
		if current_wave < active_defs.size():
			_spawn_next_wave()
		else:
			_check_combat_ended()


# Shared fallback for enemy dummies that die OUTSIDE the normal SpawnManager
# flow (e.g. SpawnManager node missing): when no enemy is left alive, declare
# victory. Kept static so every enemy type uses the same rule (previously
# duplicated in enemy_dummy.gd and enemy_tank.gd).
static func check_all_enemies_defeated() -> void:
	var enemies = Engine.get_main_loop().root.get_tree().get_nodes_in_group("enemy")
	var alive := 0
	for e in enemies:
		# Ejected enemy pilots should not block victory.
		if e.is_in_group("enemy_pilot"):
			continue
		if is_instance_valid(e) and e.get("health_system") != null:
			var hs = e.health_system
			if not hs.get("is_destroyed"):
				alive += 1
	print("SPAWN_MGR: check_all_enemies_defeated (static) — alive=%d" % alive)
	if alive == 0:
		EventBus.combat_ended.emit(true)


func _check_combat_ended() -> void:
	if _get_alive_count() == 0:
		if not GlobalData.narrative.stalking_aces.is_empty():
			print("SPAWN_MGR: _check_combat_ended — stalking aces remain, spawning one")
			_trigger_stalking_ace_ambush()
		else:
			print("SPAWN_MGR: _check_combat_ended — emitting combat_ended(true)")
			EventBus.combat_ended.emit(true)
	else:
		print("SPAWN_MGR: _check_combat_ended — alive=%d, not ending" % _get_alive_count())


# --- Mid-Battle Injection Events (GDD §7.3) ---------------------------------
# Randomly triggers Reinforcements or Countdown Extraction during combat to
# add tactical variety and pressure.
func _schedule_mid_battle_events() -> void:
	# Don't trigger on duel or fuel_depot battles.
	if GameManager.combat_node_type in ["duel", "fuel_depot"]:
		return
	# Only trigger on ace or boss battles (more dramatic encounters).
	if GameManager.combat_node_type not in ["ace", "boss"]:
		return
	var mid = get_node_or_null("../MidBattleInjection")
	if mid == null:
		return
	# Roll for event type: 50% reinforcements, 30% countdown, 20% none.
	var roll = randf()
	if roll < 0.50:
		# Reinforcements after 15-25 seconds.
		var delay = randf_range(15.0, 25.0)
		mid.trigger_reinforcements(delay)
	elif roll < 0.80:
		# Countdown extraction: 45 second timer.
		mid.trigger_countdown_extraction(45.0)


func _trigger_stalking_ace_ambush() -> void:
	var ace_kind = GlobalData.narrative.stalking_aces.pop_front()
	GlobalData.narrative.stalking_chance = 0.0
	_consume_enemy_special_unit(str(ace_kind))
	print("SIREN WARNING! STALKING ACE WARPING IN!")
	AudioManager.play_combat_music("ace")
	var spawn_pos = _get_spawn_position()

	# Give each counter-unit a distinct battlefield identity instead of both
	# being plain heavy units: a special ace is a brutal melee stalker, while a
	# valkyrion copy is a slower, armored threat that mirrors heavier mech tech.
	var scene_type := "heavy_full"
	var archetype := 2
	var hp_scale := 2.2
	if ace_kind == "valkyrion_copy":
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
	for i in range(GlobalData.narrative.enemy_special_units.size()):
		var unit = GlobalData.narrative.enemy_special_units[i]
		if unit is Dictionary and unit.get("kind", "") == kind:
			GlobalData.narrative.enemy_special_units.remove_at(i)
			return


func _spawn_enemy(type: String, archetype: int, pos: Vector3, hp_scale: float, squad_role: String = "", paint: Dictionary = {}, tech_id: String = "") -> void:
	var pilot: Dictionary = PilotGenerator.generate_pilot({
		"archetype": archetype,
		"level": GlobalData.board.wanted_level
	})
	if squad_role != "":
		pilot["squad_role"] = squad_role
		pilot["rank_title"] = "[CMDR]" if squad_role == "commander" else "[PVT]"
		pilot["display_name"] = "%s %s" % [pilot["rank_title"], pilot["name"]]

	_spawn_enemy_with_pilot(type, archetype, pos, hp_scale, pilot, null, paint, tech_id)


func _spawn_enemy_with_pilot(type: String, archetype: int, pos: Vector3, hp_scale: float, pilot: Dictionary, coordinator: Node = null, paint: Dictionary = {}, tech_id: String = "") -> Node3D:
	var scene = _get_enemy_scene(type)
	if scene == null:
		return null

	var enemy = scene.instantiate()
	enemy.archetype = archetype
	var spawn_pos := snap_to_ground(pos, get_world_3d().direct_space_state)
	if is_equal_approx(spawn_pos.y, pos.y):
		# Ray missed (outside the mesh / physics not ready): spawn high and
		# let gravity settle instead of burying the mech under the terrain.
		spawn_pos.y = pos.y + 12.0
	# Lift the root by the body's ground-contact offset so the whole mech rests
	# ON the surface immediately (no half-buried spawn, no pop-up).
	spawn_pos.y -= body_bottom_offset(enemy)

	if enemy.get("pilot_data") != null:
		enemy.pilot_data = pilot
	if enemy.get("squad_role") != null:
		enemy.squad_role = str(pilot.get("squad_role", ""))
	if enemy.get("tactical_role") != null:
		enemy.tactical_role = str(pilot.get("tactical_role", ""))
	if enemy.get("squad_coordinator") != null:
		enemy.squad_coordinator = coordinator
	if enemy.get("faction_paint") != null:
		enemy.faction_paint = paint

	var target_tech := tech_id
	if target_tech == "" and pilot.has("tech_id"):
		target_tech = str(pilot.get("tech_id", ""))
	if target_tech != "" and enemy.get("observed_tech_id") != null:
		enemy.observed_tech_id = target_tech


	var is_interactive := not DisplayServer.get_name().to_lower().contains("headless")
	if is_interactive and is_inside_tree():
		# Slide-in from arena boundary / high-speed thruster rush
		var spawn_dir := spawn_pos.normalized()
		if spawn_dir.length_squared() < 0.01:
			spawn_dir = Vector3.FORWARD
		var entry_origin := spawn_pos + spawn_dir * randf_range(16.0, 24.0)
		entry_origin.y = spawn_pos.y + 0.8
		enemy.position = entry_origin

		add_child(enemy)
		await enemy.ready

		_animate_combat_slide_in(enemy, entry_origin, spawn_pos)
	else:
		enemy.position = spawn_pos
		add_child(enemy)
		await enemy.ready

	# Pass supply posture down to AI Brain
	var ai = enemy.get_node_or_null("MechaAIController")
	if ai:
		ai.is_starved = bool(pilot.get("is_starved", false))
		if ai.is_starved:
			ai.posture = "gak"

	if coordinator != null:
		coordinator.register_member(enemy, pilot)

	if enemy.get("health_system") != null:
		for slot in enemy.health_system.parts:
			enemy.health_system.parts[slot]["armor_hp"] *= hp_scale
			enemy.health_system.parts[slot]["max_armor"] *= hp_scale
			enemy.health_system.parts[slot]["frame_hp"] *= hp_scale
			enemy.health_system.parts[slot]["max_frame"] *= hp_scale
		if enemy.health_system.has_method("_calculate_totals"):
			enemy.health_system._calculate_totals()

	# Attach pilot behavior tree if available
	if enemy.has_method("setup_beehave_tree"):
		var p_trait: String = str(pilot.get("trait", "Balanced"))
		enemy.setup_beehave_tree(p_trait)

	enemies_alive += 1
	return enemy


func _animate_combat_slide_in(enemy: Node3D, start_pos: Vector3, end_pos: Vector3) -> void:
	if not is_instance_valid(enemy):
		return
	var duration := randf_range(0.42, 0.60)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(enemy, "position:x", end_pos.x, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(enemy, "position:z", end_pos.z, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(enemy, "position:y", end_pos.y, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Spawn smoke/dust trail along entrance vector
	var eff_fact = load("res://scripts/effects/effect_factory.gd")
	if eff_fact and eff_fact.has_method("spawn_smoke_plume"):
		eff_fact.spawn_smoke_plume(get_tree(), (start_pos + end_pos) * 0.5, 4, 0.25, 0.7, 1.4)

	await tw.finished
	if is_instance_valid(enemy) and eff_fact and eff_fact.has_method("spawn_dust_puffs"):
		eff_fact.spawn_dust_puffs(get_tree(), end_pos)


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


# Snaps a spawn point down onto the arena's Environment collision surface
# (ground tiles, dunes, rocks, riverbanks, bridges) so enemies never spawn
# half-buried inside terrain. The hardcoded y in _generate_spawn_points is only
# a rough hint: desert dunes/rocks rise several meters above the flat ground
# (and flat themes sit at -0.4, river banks at +0.5), so a fixed y leaves some
# spawns embedded in the ground.
static func snap_to_ground(pos: Vector3, space_state: PhysicsDirectSpaceState3D) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		pos + Vector3(0, 60.0, 0),
		pos + Vector3(0, -60.0, 0),
		2  # Environment physics layer: ground, dunes, rocks, bridges, banks.
	)
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return pos
	return Vector3(pos.x, hit.position.y + 0.05, pos.z)


# The collision body's lowest point in WORLD units relative to the root
# (negative when the body hangs below the root). Enemy scenes place their
# ground-contact shape at different heights, so the root must be lifted by this
# much for the body to rest on the terrain instead of being half-buried.
# Scaled roots (e.g. the boss's 1.5x rig) scale the local offset too, so the
# shape's LOCAL bottom is multiplied by the root scale to get the world lift.
static func body_bottom_offset(enemy: Node) -> float:
	var scale_y := 1.0
	if enemy is Node3D:
		scale_y = (enemy as Node3D).scale.y
	for child in enemy.get_children():
		if child is CollisionShape3D and child.shape != null:
			var y0: float = child.position.y
			var s: Shape3D = child.shape
			if s is SphereShape3D:
				return (y0 - s.radius) * scale_y
			if s is CapsuleShape3D:
				return (y0 - s.height * 0.5) * scale_y
			if s is BoxShape3D:
				return (y0 - s.size.y * 0.5) * scale_y
			if s is CylinderShape3D:
				return (y0 - s.height * 0.5) * scale_y
	return 0.0


# Spawns one squad fire team for military themes: the leader (full-rig variant
# so it reads as a commander) stands at the center with the other members fanned
# out behind it. `count` covers the whole team (leader + members).
func _spawn_squad(entry: Dictionary, count: int, hp_scale: float, org: Dictionary) -> void:
	if count <= 0:
		return

	var faction_id: String = ""
	var faction_name: String = str(org.get("name", ""))
	var faction_paint: Dictionary = {}
	if ResourceLoader.exists("res://scripts/systems/faction_system.gd"):
		var FS = load("res://scripts/systems/faction_system.gd")
		faction_id = FS.pick_next_faction()
		faction_name = FS.get_faction_def(faction_id).get("name_en", faction_name)
		faction_paint = FS.get_faction_paint(faction_id)
		# Outland wanderers already have random tier inside generator
		var fs_fleet: Dictionary = PilotGenerator.generate_enemy_fleet(count, faction_name, GlobalData.board.wanted_level, faction_paint, faction_id)
		var fs_coord := EnemySquadCoordinator.new()
		fs_coord.name = "SquadCoordinator_%s" % fs_fleet["squad_id"]
		fs_coord.setup_squad(fs_fleet["squad_id"], fs_fleet["squad_name"])
		add_child(fs_coord)

		var fs_center: Vector3 = _get_spawn_position()
		var fs_leader: String = _squad_leader_type(entry["type"])
		var fs_commander: Dictionary = fs_fleet["commander"]

		_spawn_enemy_with_pilot(
			fs_leader, entry["archetype"], fs_center, hp_scale,
			fs_commander, fs_coord, _paint_for_enemy(org, "commander") if faction_id == "" else faction_paint
		)

		var fs_slot := 0
		for i in range(1, count):
			var fs_offset: Vector3 = SQUAD_FORMATION[fs_slot % SQUAD_FORMATION.size()]
			var fs_guard := 0
			while fs_guard < SQUAD_FORMATION.size() and _spawn_blocked_by_cover(fs_center + fs_offset):
				fs_slot += 1
				fs_offset = SQUAD_FORMATION[fs_slot % SQUAD_FORMATION.size()]
			fs_slot += 1
			var fs_wingman: Dictionary = fs_fleet["pilots"][i] if i < fs_fleet["pilots"].size() else fs_commander
			_spawn_enemy_with_pilot(entry["type"], entry["archetype"], fs_center + fs_offset, hp_scale, fs_wingman, fs_coord, faction_paint)
		return
	# Fallback legacy (should not reach here when FactionSystem exists)
	var fleet_data: Dictionary = PilotGenerator.generate_enemy_fleet(count, faction_name, GlobalData.board.wanted_level)
	var coordinator := EnemySquadCoordinator.new()
	coordinator.name = "SquadCoordinator_%s" % fleet_data["squad_id"]
	coordinator.setup_squad(fleet_data["squad_id"], fleet_data["squad_name"])
	add_child(coordinator)

	var center: Vector3 = _get_spawn_position()
	var leader_type: String = _squad_leader_type(entry["type"])
	var commander_pilot: Dictionary = fleet_data["commander"]

	_spawn_enemy_with_pilot(
		leader_type, entry["archetype"], center, hp_scale,
		commander_pilot, coordinator, _paint_for_enemy(org, "commander")
	)

	var slot := 0
	for i in range(1, count):
		var offset: Vector3 = SQUAD_FORMATION[slot % SQUAD_FORMATION.size()]
		var guard := 0
		while guard < SQUAD_FORMATION.size() and _spawn_blocked_by_cover(center + offset):
			slot += 1
			offset = SQUAD_FORMATION[slot % SQUAD_FORMATION.size()]
			guard += 1

		var wingman_pilot: Dictionary = fleet_data["pilots"][i]
		var wingman_arch: int = int(wingman_pilot.get("archetype", entry["archetype"]))
		_spawn_enemy_with_pilot(
			entry["type"], wingman_arch, center + offset, hp_scale,
			wingman_pilot, coordinator, _paint_for_enemy(org, "member")
		)
		slot += 1


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

	var candidates := spawn_points.duplicate()
	candidates.shuffle()

	# Prefer a marker this wave hasn't used yet and that sits clear of cover
	# objects. Reusing a marker is what stacks enemies on top of each other.
	for marker in candidates:
		if not is_instance_valid(marker) or not (marker is Node3D) or not (marker as Node3D).is_inside_tree():
			continue
		if _used_spawn_indices.has(marker.get_instance_id()):
			continue
		if _spawn_blocked_by_cover((marker as Node3D).global_position):
			continue
		_used_spawn_indices.append(marker.get_instance_id())
		return (marker as Node3D).global_position

	# Every marker used (oversized wave): still avoid cover and pick the
	# least-crowded marker (farthest from living enemies).
	var best: Marker3D = candidates[0]
	var best_dist := -1.0
	for marker in candidates:
		if not is_instance_valid(marker) or not (marker is Node3D) or not (marker as Node3D).is_inside_tree():
			continue
		if _spawn_blocked_by_cover((marker as Node3D).global_position):
			continue
		var d := _distance_to_nearest_enemy((marker as Node3D).global_position)
		if d > best_dist:
			best_dist = d
			best = marker
	return (best as Node3D).global_position if is_instance_valid(best) and best is Node3D and (best as Node3D).is_inside_tree() else Vector3.ZERO


# True when a spawn position sits inside a cover object's footprint (plus a
# small margin) — enemies must never spawn embedded in barricades/containers.
func _spawn_blocked_by_cover(pos: Vector3) -> bool:
	return is_pos_blocked_by_covers(pos, get_tree().get_nodes_in_group("cover"))


static func is_pos_blocked_by_covers(pos: Vector3, covers: Array) -> bool:
	for c in covers:
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var aabb := _cover_world_aabb(c as Node3D)
		if aabb.size == Vector3.ZERO:
			continue
		if aabb.grow(SPAWN_COVER_MARGIN).has_point(pos):
			return true
	return false


# World-space AABB of a cover's collision shape (box or cylinder), so rotated
# covers are still detected via their true footprint.
static func _cover_world_aabb(cover: Node3D) -> AABB:
	if not is_instance_valid(cover) or not cover.is_inside_tree():
		return AABB()
	for child in cover.get_children():
		if child is CollisionShape3D and child.shape != null:
			if not child.is_inside_tree():
				continue
			var s: Shape3D = child.shape
			var half: Vector3
			if s is BoxShape3D:
				half = (s as BoxShape3D).size * 0.5
			elif s is CylinderShape3D:
				var cyl := s as CylinderShape3D
				half = Vector3(cyl.radius, cyl.height * 0.5, cyl.radius)
			else:
				continue
			# World AABB of the rotated box: project the half-extents through the
			# shape's global basis and center the box on its world origin.
			var t: Transform3D = (child as CollisionShape3D).global_transform
			var half_world: Vector3 = (t.basis * half).abs()
			return AABB(t.origin - half_world, half_world * 2.0)
	return AABB()


# Horizontal distance from pos to the nearest living enemy (INF when none).
func _distance_to_nearest_enemy(pos: Vector3) -> float:
	var nearest := INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not e is Node3D or not (e as Node3D).is_inside_tree():
			continue
		var hs = e.get("health_system")
		if hs == null or hs.get("is_destroyed"):
			continue
		nearest = minf(nearest, Vector2((e as Node3D).global_position.x - pos.x, (e as Node3D).global_position.z - pos.z).length())
	return nearest


func _get_alive_count() -> int:
	var count = 0
	var enemies = get_tree().get_nodes_in_group("enemy")
	for e in enemies:
		# Ejected enemy pilots are in the "enemy" group but should not
		# block victory — only actual mechs count toward the alive total.
		if e.is_in_group("enemy_pilot"):
			continue
		if is_instance_valid(e) and e.get("health_system") != null:
			var hs = e.health_system
			if not hs.get("is_destroyed"):
				count += 1
	return count


func get_current_wave() -> int:
	return current_wave


func get_total_waves() -> int:
	return _get_active_defs().size()
