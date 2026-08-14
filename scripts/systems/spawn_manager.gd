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
		"duel":
			return _duel_wave_defs()
		_:
			return theme_grunt_wave_defs.get(GlobalData.theme_id, grunt_wave_defs)


# A duel battle fields exactly one full-rig enemy — the pending character's
# signature mech (equivalent to a strong ace-scale threat).
func _duel_wave_defs() -> Array:
	var character := RecruitSystem.get_pending_character()
	var scene_type := str(character.get("duel_scene", "heavy_full"))
	var archetype := int(character.get("duel_archetype", 2))
	return [[{"type": scene_type, "archetype": archetype, "count": 1}]]


func _ready() -> void:
	_generate_spawn_points()
	_spawn_fielded_allies()
	# Snapshot friendly combat HP after the player mech + allies are in the scene,
	# so the decisive-victory check knows the combined HP of our fielded side.
	GlobalData.begin_combat_stats()
	await get_tree().create_timer(1.0).timeout
	start_waves()


func _generate_spawn_points() -> void:
	var arena_gen = get_node_or_null("../ArenaGenerator")
	var half: float = 110.0  # Inside 240m walls (scaled up for larger fields)
	if arena_gen != null and arena_gen.get("arena_size") != null:
		half = float(arena_gen.arena_size) * 0.46
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
	var mecha = GameManager.get_player_mecha()
	var anchor = mecha.global_position if mecha else Vector3.ZERO
	var i := 0
	for entry in FleetSystem.get_sortie_units():
		var mech: Dictionary = entry.get("mech", {})
		var unit: Dictionary = entry.get("unit", {})
		var template_id := str(unit.get("template_id", ""))
		var template = GlobalData.get_ally_template(template_id)
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
			GlobalData.get_hangar_archetype(str(mech.get("id", ""))),
			str(unit.get("name", template.get("name", "ALLY"))),
		)
		ally_unit.apply_mech_loadout(mech)


func start_waves() -> void:
	is_active = true
	current_wave = 0
	_spawn_next_wave()


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

	var wanted = GlobalData.wanted_level
	var hp_scale = 1.0 + min(wanted, 5) * 0.15
	hp_scale *= GlobalData.get_enemy_grunt_multiplier()
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
	var spawn_pos := snap_to_ground(pos, get_world_3d().direct_space_state)
	# Lift the root by the body's ground-contact offset so the whole mech rests
	# ON the surface immediately (no half-buried spawn, no pop-up).
	spawn_pos.y -= body_bottom_offset(enemy)
	enemy.position = spawn_pos
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


# The collision body's lowest point relative to the root (negative when the
# body hangs below the root). Enemy scenes place their ground-contact shape at
# different heights, so the root must be lifted by this much for the body to
# rest on the terrain instead of being half-buried.
static func body_bottom_offset(enemy: Node) -> float:
	for child in enemy.get_children():
		if child is CollisionShape3D and child.shape != null:
			var y0: float = child.position.y
			var s: Shape3D = child.shape
			if s is SphereShape3D:
				return y0 - s.radius
			if s is CapsuleShape3D:
				return y0 - s.height * 0.5
			if s is BoxShape3D:
				return y0 - s.size.y * 0.5
			if s is CylinderShape3D:
				return y0 - s.height * 0.5
	return 0.0


# Spawns one squad fire team for military themes: the leader (full-rig variant
# so it reads as a commander) stands at the center with the other members fanned
# out behind it. `count` covers the whole team (leader + members).
func _spawn_squad(entry: Dictionary, count: int, hp_scale: float, org: Dictionary) -> void:
	if count <= 0:
		return
	var center: Vector3 = _get_spawn_position()
	var leader_type: String = _squad_leader_type(entry["type"])
	_spawn_enemy(leader_type, entry["archetype"], center, hp_scale, "commander", _paint_for_enemy(org, "commander"))
	var slot := 0
	for i in range(1, count):
		# Step through formation slots, skipping any that land inside cover so
		# squad members don't spawn embedded in obstacles.
		var offset: Vector3 = SQUAD_FORMATION[slot % SQUAD_FORMATION.size()]
		var guard := 0
		while guard < SQUAD_FORMATION.size() and _spawn_blocked_by_cover(center + offset):
			slot += 1
			offset = SQUAD_FORMATION[slot % SQUAD_FORMATION.size()]
			guard += 1
		_spawn_enemy(entry["type"], entry["archetype"], center + offset, hp_scale, "member", _paint_for_enemy(org, "member"))
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
		if _used_spawn_indices.has(marker.get_instance_id()):
			continue
		if _spawn_blocked_by_cover(marker.global_position):
			continue
		_used_spawn_indices.append(marker.get_instance_id())
		return marker.global_position

	# Every marker used (oversized wave): still avoid cover and pick the
	# least-crowded marker (farthest from living enemies).
	var best: Marker3D = candidates[0]
	var best_dist := -1.0
	for marker in candidates:
		if _spawn_blocked_by_cover(marker.global_position):
			continue
		var d := _distance_to_nearest_enemy(marker.global_position)
		if d > best_dist:
			best_dist = d
			best = marker
	return best.global_position


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
	for child in cover.get_children():
		if child is CollisionShape3D and child.shape != null:
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
		if not is_instance_valid(e):
			continue
		var hs = e.get("health_system")
		if hs == null or hs.get("is_destroyed"):
			continue
		nearest = minf(nearest, Vector2(e.global_position.x - pos.x, e.global_position.z - pos.z).length())
	return nearest


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
