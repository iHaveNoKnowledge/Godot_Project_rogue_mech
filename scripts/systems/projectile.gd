extends CharacterBody3D

var speed: float = 50.0
var damage: float = 25.0
var damage_type: String = "kinetic"
var impact: float = 0.0
var lifetime: float = 5.0
var timer: float = 0.0
var trail_timer: float = 0.0
## Trail streak colors, set per shot by WeaponCore (brass for bullets, ion
## cyan for beams, pale vapor blue for railgun slugs).
var trail_head: Color = Color(1, 0.8, 0.3, 0.9)
var trail_fade: Color = Color(1, 0.7, 0.2)
var direction: Vector3 = Vector3.FORWARD
var fired_by_enemy: bool = false
# Railgun rounds leave a shrinking sonic-boom ring along their flight path.
var sonic_boom: bool = false
# Beam bolts soak into whatever they hit (glowing heat scar, never ricochet).
var is_beam: bool = false
var ricochet_chance: float = 0.15
var prev_position: Vector3
var explosion_radius: float = 3.0
# Gravity pull (m/s^2) applied to the projectile (default 0.0 for straight direct-fire;
# non-zero only for dedicated arcing weapons like mortars / grenade launchers).
var drop_gravity: float = 0.0
# Close-range shots stay laser-flat: gravity only starts pulling once the shot
# has travelled this far, so point-blank hits never sag below the crosshair.
var drop_start_distance: float = 15.0
var _traveled: float = 0.0
var _drop_speed: float = 0.0
# Missile-style visuals: the model node gets re-aimed every physics frame to
# the LIVE flight vector (launch direction plus gravity sag), and impacts
# always detonate with fire/smoke even when damage_type isn't "explosive".
var visual_node: Node3D = null
var explosive_visual: bool = false
var target_node: Node3D = null
var homing_turn_speed: float = 6.8
var initial_boost_timer: float = 0.2
var _smoke_timer: float = 0.0


func _ready() -> void:
	add_to_group("projectile")
	prev_position = global_position


func get_damage() -> float:
	return damage


static var _cached_targets_enemy_shots: Array = []
static var _cached_targets_player_shots: Array = []
static var _last_target_cache_frame: int = -1

static func _refresh_target_cache(tree: SceneTree) -> void:
	var cur_frame := Engine.get_physics_frames()
	if cur_frame == _last_target_cache_frame:
		return
	_last_target_cache_frame = cur_frame

	_cached_targets_enemy_shots.clear()
	_cached_targets_enemy_shots.append_array(tree.get_nodes_in_group("mecha"))
	_cached_targets_enemy_shots.append_array(tree.get_nodes_in_group("ally"))
	_cached_targets_enemy_shots.append_array(tree.get_nodes_in_group("pilot"))

	_cached_targets_player_shots.clear()
	_cached_targets_player_shots.append_array(tree.get_nodes_in_group("enemy"))


# Distance from point to line segment (prev→cur) — prevents tunneling at high speed
static func _segment_distance_to_point(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab: Vector3 = b - a
	var ap: Vector3 = p - a
	var ab_len2: float = ab.length_squared()
	if ab_len2 < 0.0001:
		return ap.length()
	var t: float = clampf(ap.dot(ab) / ab_len2, 0.0, 1.0)
	var closest: Vector3 = a + ab * t
	return p.distance_to(closest)


func _physics_process(delta: float) -> void:
	timer += delta
	if timer >= lifetime:
		queue_free()
		return

	prev_position = global_position

	# --- Homing Guidance (Macross / AC Swarm Trajectory) ---
	if target_node != null:
		if not is_instance_valid(target_node) or ("is_destroyed" in target_node and target_node.is_destroyed):
			target_node = null
		elif timer >= initial_boost_timer:
			var target_pos: Vector3 = target_node.global_position + Vector3(0.0, 1.2, 0.0)
			var desired_dir: Vector3 = (target_pos - global_position).normalized()
			if desired_dir.length_squared() > 0.001:
				var turn_amount: float = homing_turn_speed * delta
				direction = direction.slerp(desired_dir, clampf(turn_amount, 0.0, 1.0)).normalized()

	var step := speed * delta
	position += direction * step
	_traveled += step

	# Smoke trail behind missiles
	if explosive_visual or visual_node != null or target_node != null:
		_smoke_timer += delta
		if _smoke_timer >= 0.04:
			_smoke_timer = 0.0
			var tree := get_tree()
			if tree:
				EffectFactory.spawn_smoke_plume(tree, global_position, 1, 0.12, 0.22, 0.35)

	# Bullet drop: only active when weapon explicitly specifies drop_gravity > 0.0 (e.g. Mortars/Grenades).
	if drop_gravity > 0.0 and _traveled > drop_start_distance:
		_drop_speed += drop_gravity * delta
		position.y -= _drop_speed * delta

	# Keep missile-style models pointed along the ACTUAL velocity (launch dir
	# + gravity sag), so arcing rounds visibly pitch their nose downward.
	if visual_node != null and is_instance_valid(visual_node):
		var vel := direction * speed
		if drop_gravity > 0.0 and _traveled > drop_start_distance:
			vel.y -= _drop_speed
		if vel.length_squared() > 0.01:
			var vdir := vel.normalized()
			var up := Vector3.UP
			if absf(vdir.dot(up)) > 0.99:
				up = Vector3.RIGHT
			visual_node.look_at(global_position + vdir, up)

	# Check for obstacle (cover) collision using raycast between frames
	_check_obstacle_collision()

	var tree := get_tree()
	if tree == null:
		return
	_refresh_target_cache(tree)

	if fired_by_enemy:
		for mecha in _cached_targets_enemy_shots:
			if not is_instance_valid(mecha):
				continue
			var target_pos: Vector3 = mecha.global_position + Vector3(0, 1.5, 0)
			# Use segment distance (prev→cur) so fast projectiles don't tunnel
			if _segment_distance_to_point(prev_position, global_position, target_pos) < 2.2:
				_hit_target(mecha)
				return
	else:
		for enemy in _cached_targets_player_shots:
			if not is_instance_valid(enemy):
				continue
			var target_pos: Vector3 = enemy.global_position + Vector3(0, 1.5, 0)
			if _segment_distance_to_point(prev_position, global_position, target_pos) < 2.4:
				_hit_target(enemy)
				return

	# Fallback: explode below the lowest possible terrain (global safety net at
	# top ~ -2.5). Real terrain (banks, bridges, riverbed) is already caught by
	# the raycast above.
	if global_position.y <= -2.5:
		if explosive_visual and damage_type.to_lower() != "explosive":
			_spawn_missile_impact_fx(global_position)
			queue_free()
			return
		if damage_type.to_lower() == "explosive":
			_explode(global_position)
		else:
			EffectManager.spawn_hit_spark(global_position, Vector3.UP, damage_type)
			if is_beam:
				EffectManager.spawn_heat_scar(global_position, Vector3.UP)
		queue_free()
		return

	trail_timer += delta
	if trail_timer >= 0.07:
		trail_timer = 0.0
		_spawn_trail()
		if sonic_boom:
			_spawn_sonic_boom_ring()


func _check_obstacle_collision() -> void:
	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(prev_position, global_position)
	# Layer 2 = Environment (cover objects, walls)
	query.collision_mask = 2
	var result = space_state.intersect_ray(query)

	if result:
		var collider = result["collider"]
		var hit_pos = result["position"]
		var hit_normal = result["normal"]

		# Deal damage to cover / entity
		if collider.has_method("take_damage_at_point"):
			collider.take_damage_at_point(damage, hit_pos, damage_type)
		elif collider.has_method("take_damage"):
			collider.take_damage(damage, damage_type)

		if damage_type.to_lower() == "explosive":
			_explode(hit_pos)
			queue_free()
			return

		if is_beam:
			# Energy soaks in: white-hot scar that cools to black, no bounce.
			EffectManager.spawn_heat_scar(hit_pos, hit_normal)
			queue_free()
			return

		if explosive_visual:
			# Missiles detonate against cover even though their damage type
			# is heat — fireball + smoke, no gameplay area damage.
			_spawn_missile_impact_fx(hit_pos)
		else:
			EffectManager.spawn_hit_spark(hit_pos, hit_normal, damage_type)

		# Ricochet check: some bullets bounce off
		if randf() < ricochet_chance:
			_ricochet(hit_pos, hit_normal)
		else:
			queue_free()


func _ricochet(hit_pos: Vector3, normal: Vector3) -> void:
	# Reflect direction off the surface normal
	direction = direction.bounce(normal).normalized()
	_drop_speed = 0.0
	_traveled = 0.0
	prev_position = hit_pos
	global_position = hit_pos + normal * 0.1
	# Reduce damage on ricochet
	damage *= 0.5
	ricochet_chance *= 0.5  # Less likely to ricochet again


func _hit_target(target: Node3D) -> void:
	var final_damage = damage
	if damage_type.to_lower() == "melee" and GlobalData.weapons.chassis_id == "brawler":
		final_damage *= 1.4

	if damage_type.to_lower() == "explosive":
		_explode(position)
		return

	if explosive_visual:
		# Missiles always go out with a bang: fireball + smoke on the hit even
		# though their damage type is heat (gameplay numbers unchanged).
		_spawn_missile_impact_fx(position)

	EffectManager.spawn_hit_spark(position, -direction if direction.length_squared() > 0.001 else Vector3.UP, damage_type)
	if is_beam:
		var back := -direction if direction.length_squared() > 0.001 else Vector3.UP
		EffectManager.spawn_heat_scar(position, back)
	if AudioManager:
		AudioManager.play_impact_by_type(damage_type, position)

	if target.has_method("take_damage_at_point"):
		target.take_damage_at_point(final_damage, position, damage_type)
	elif target.has_method("take_damage"):
		target.take_damage(final_damage, damage_type)

	if target.has_method("apply_impact") and impact > 0.0:
		target.apply_impact(impact, direction)

	EffectManager.spawn_damage_number(position + Vector3(0, 1.5, 0), final_damage, Color.WHITE)
	queue_free()


func _explode(blast_pos: Vector3) -> void:
	if AudioManager:
		AudioManager.play_explosion(blast_pos)
	EffectManager.spawn_explosion(blast_pos, explosion_radius)
	if get_tree():
		EffectFactory.spawn_fire_burst(get_tree(), blast_pos, maxf(explosion_radius * 0.7, 0.8), 0.45, 6.0)
		EffectFactory.spawn_smoke_plume(get_tree(), blast_pos, 6, 0.3, 0.6, 0.9)
		EffectFactory.spawn_burning_ground(get_tree(), blast_pos, maxf(explosion_radius * 0.8, 1.0), 2.5)
	EffectManager.apply_area_explosion_damage(blast_pos, damage, explosion_radius, fired_by_enemy, damage_type)
	queue_free()


# Missile-style detonation visuals for impacts whose damage_type is NOT
# "explosive" (missiles ship as heat): a compact fireball + smoke puff and the
# explosion voice. Gameplay numbers stay exactly as tuned.
func _spawn_missile_impact_fx(pos: Vector3) -> void:
	var tree := get_tree()
	if tree != null:
		EffectFactory.spawn_fire_burst(tree, pos, 0.9, 0.35, 5.0)
		EffectFactory.spawn_smoke_plume(tree, pos, 4, 0.22, 0.4, 0.65)
	if AudioManager:
		AudioManager.play_missile_explosion(pos)


func _spawn_trail() -> void:
	EffectFactory.spawn_trail_dir(get_tree(), global_position, direction,
		Vector3(0.02, 0.02, 0.15), trail_head,
		trail_fade, 0.2, 3.0)


# A railgun round tears the air as it passes: a bright expanding shockwave ring
# (torus) that swells out from the flight line and fades, reading as the sonic
# boom cutting through the air along the projectile's path.
func _spawn_sonic_boom_ring() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.35
	torus.outer_radius = 0.5
	torus.rings = 24
	torus.ring_segments = 12
	ring.mesh = torus

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.6, 0.9, 1.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.85, 1.0)
	mat.emission_energy_multiplier = 4.0
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat

	# Ring lies in the plane perpendicular to the flight line.
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position
	ring.look_at(global_position + direction, Vector3.UP)
	ring.rotate_object_local(Vector3.FORWARD, deg_to_rad(90.0))

	var tween := get_tree().create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(3.2, 3.2, 1.0), 0.28) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.28)
	tween.chain().tween_callback(ring.queue_free)
