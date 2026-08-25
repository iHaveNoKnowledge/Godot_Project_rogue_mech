class_name EffectManager
extends Node3D

static var instance: EffectManager = null


func _ready() -> void:
	instance = self
	# Pre-warm expensive shader variants so the first explosion does not compile
	# 5 new StandardMaterial shaders at the exact frame the turret dies (which
	# caused `shader_rd.cpp:516 f.is_null()` cache-write races when 5 tanks
	# burst at once). Creating the templates now compiles the variant once, and
	# later bursts just duplicate it.
	_get_cached_explosion_ring_mat()
	_get_cached_explosion_core_mat()
	_get_cached_explosion_particle_mat()
	_get_cached_explosion_smoke_mat()
	_get_cached_hit_material(Color(1.0, 0.95, 0.6))
	_get_cached_spark_material(Color(1.0, 0.88, 0.4))


static var _muzzle_mesh_cache: Dictionary = {}


static func _get_muzzle_star_mesh() -> ArrayMesh:
	if _muzzle_mesh_cache.has("star"):
		return _muzzle_mesh_cache["star"]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var center := Vector3.ZERO
	var white := Color(1.0, 1.0, 1.0, 1.0)
	var edge := Color(1.0, 0.85, 0.4, 0.0)

	# 1. Main Forward Flame Spike (pointed tongue along +Z, length 1.25m)
	var fwd_tip := Vector3(0, 0, 1.25)
	var fwd_l := Vector3(-0.12, 0, 0.12)
	var fwd_r := Vector3(0.12, 0, 0.12)
	var fwd_u := Vector3(0, 0.12, 0.12)
	var fwd_d := Vector3(0, -0.12, 0.12)

	# Horizontal flame fin
	st.set_color(white); st.add_vertex(center)
	st.set_color(edge); st.add_vertex(fwd_l)
	st.set_color(white); st.add_vertex(fwd_tip)

	st.set_color(white); st.add_vertex(center)
	st.set_color(white); st.add_vertex(fwd_tip)
	st.set_color(edge); st.add_vertex(fwd_r)

	# Vertical flame fin
	st.set_color(white); st.add_vertex(center)
	st.set_color(edge); st.add_vertex(fwd_u)
	st.set_color(white); st.add_vertex(fwd_tip)

	st.set_color(white); st.add_vertex(center)
	st.set_color(white); st.add_vertex(fwd_tip)
	st.set_color(edge); st.add_vertex(fwd_d)

	# 2. Four Diagonal Muzzle Brake Vent Spikes (4-point Starburst Flare)
	var ray_count := 4
	var ray_len := 0.65
	var ray_width := 0.09
	for i in range(ray_count):
		var angle := i * (TAU / ray_count) + (PI / 4.0)
		var dir := Vector3(cos(angle), sin(angle), 0.25).normalized()
		var perp := Vector3(-sin(angle), cos(angle), 0) * ray_width
		var tip := dir * ray_len

		st.set_color(white); st.add_vertex(center)
		st.set_color(edge); st.add_vertex(center - perp)
		st.set_color(white); st.add_vertex(tip)

		st.set_color(white); st.add_vertex(center)
		st.set_color(white); st.add_vertex(tip)
		st.set_color(edge); st.add_vertex(center + perp)

	# 3. Brilliant Center Core Card (Star Diamond)
	var core_rad := 0.25
	st.set_color(white); st.add_vertex(center)
	st.set_color(white); st.add_vertex(Vector3(-core_rad, 0, 0.05))
	st.set_color(white); st.add_vertex(Vector3(0, core_rad, 0.05))

	st.set_color(white); st.add_vertex(center)
	st.set_color(white); st.add_vertex(Vector3(0, core_rad, 0.05))
	st.set_color(white); st.add_vertex(Vector3(core_rad, 0, 0.05))

	st.set_color(white); st.add_vertex(center)
	st.set_color(white); st.add_vertex(Vector3(core_rad, 0, 0.05))
	st.set_color(white); st.add_vertex(Vector3(0, -core_rad, 0.05))

	st.set_color(white); st.add_vertex(center)
	st.set_color(white); st.add_vertex(Vector3(0, -core_rad, 0.05))
	st.set_color(white); st.add_vertex(Vector3(-core_rad, 0, 0.05))

	var mesh := st.commit()
	_muzzle_mesh_cache["star"] = mesh
	return mesh


static func spawn_muzzle_flash(position: Vector3, direction: Vector3, color: Color = Color(1.0, 0.85, 0.4)) -> void:
	var target_parent: Node = instance if instance != null and is_instance_valid(instance) and instance.is_inside_tree() else Engine.get_main_loop().root
	if target_parent == null:
		return

	# 1. Dynamic Flash OmniLight3D (illuminates mecha, weapon barrel, and surroundings)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 8.0
	light.omni_range = 14.0
	light.omni_attenuation = 1.8
	target_parent.add_child(light)
	light.global_position = position

	var light_tween := target_parent.create_tween()
	light_tween.tween_property(light, "light_energy", 0.0, 0.08)
	light_tween.tween_callback(light.queue_free)

	# 2. 3D Starburst Spike Flash Mesh
	var flash_mesh := MeshInstance3D.new()
	flash_mesh.mesh = _get_muzzle_star_mesh()
	var flash_mat := StandardMaterial3D.new()
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash_mat.vertex_color_use_as_albedo = true
	flash_mat.albedo_color = Color(color.r, color.g, color.b, 1.0)
	flash_mat.emission_enabled = true
	flash_mat.emission = color
	flash_mat.emission_energy_multiplier = 6.0
	flash_mesh.material_override = flash_mat

	target_parent.add_child(flash_mesh)
	flash_mesh.global_position = position
	if direction.length_squared() > 0.001:
		flash_mesh.look_at(position + direction, Vector3.UP)
	# Random roll angle + scale jitter per shot for organic explosive variance
	flash_mesh.rotate_object_local(Vector3.FORWARD, randf_range(0.0, TAU))
	var rand_scale := randf_range(0.95, 1.35)
	flash_mesh.scale = Vector3.ONE * (rand_scale * 0.5)

	var mesh_tween := target_parent.create_tween()
	mesh_tween.tween_property(flash_mesh, "scale", Vector3.ONE * rand_scale, 0.02).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	mesh_tween.tween_interval(0.03)
	mesh_tween.tween_property(flash_mat, "albedo_color:a", 0.0, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	mesh_tween.tween_callback(flash_mesh.queue_free)

	# 3. High-Velocity Needle Spark Vents
	var flash_particles = GPUParticles3D.new()
	var mat = ParticleProcessMaterial.new()
	mat.direction = direction
	mat.spread = 35.0
	mat.initial_velocity_min = 20.0
	mat.initial_velocity_max = 40.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.2
	mat.scale_max = 0.5

	flash_particles.process_material = mat
	flash_particles.amount = 8
	flash_particles.lifetime = 0.10
	flash_particles.one_shot = true
	flash_particles.explosiveness = 1.0
	flash_particles.emitting = true

	var spark_mesh_inst = MeshInstance3D.new()
	var spark_box = BoxMesh.new()
	spark_box.size = Vector3(0.025, 0.025, 0.25)
	spark_mesh_inst.mesh = spark_box
	var spark_mat = StandardMaterial3D.new()
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	spark_mat.albedo_color = Color(1.0, 0.95, 0.7, 0.95)
	spark_mat.emission_enabled = true
	spark_mat.emission = color
	spark_mat.emission_energy_multiplier = 5.0
	spark_mesh_inst.material_override = spark_mat
	flash_particles.add_child(spark_mesh_inst)

	target_parent.add_child(flash_particles)
	flash_particles.global_position = position
	if direction.length_squared() > 0.001:
		flash_particles.look_at(position + direction, Vector3.UP)

	var p_tween := target_parent.create_tween()
	p_tween.tween_interval(0.14)
	p_tween.tween_callback(flash_particles.queue_free)


static var _active_hit_lights: int = 0
static var _cached_quad_mesh: QuadMesh = null
static var _cached_spark_mesh: BoxMesh = null
static var _cached_needle_mesh: BoxMesh = null
static var _cached_micro_arc_mesh: BoxMesh = null
static var _cached_starburst_mesh: ArrayMesh = null
static var _cached_hit_mats: Dictionary = {}
static var _cached_spark_mats: Dictionary = {}
# Cached explosion materials — shared templates duplicated per burst so the
# emission shader variant is compiled once instead of N times concurrently.
static var _cached_explosion_ring_mat: StandardMaterial3D = null
static var _cached_explosion_core_mat: StandardMaterial3D = null
static var _cached_explosion_particle_mat: StandardMaterial3D = null
static var _cached_explosion_smoke_mat: StandardMaterial3D = null

static func _get_cached_quad() -> QuadMesh:
	if _cached_quad_mesh == null:
		_cached_quad_mesh = QuadMesh.new()
		_cached_quad_mesh.size = Vector2(0.4, 0.4)
	return _cached_quad_mesh

static func _get_cached_spark_box() -> BoxMesh:
	if _cached_spark_mesh == null:
		_cached_spark_mesh = BoxMesh.new()
		_cached_spark_mesh.size = Vector3(0.03, 0.03, 0.25)
	return _cached_spark_mesh

static func _get_cached_needle_spark_box() -> BoxMesh:
	if _cached_needle_mesh == null:
		_cached_needle_mesh = BoxMesh.new()
		_cached_needle_mesh.size = Vector3(0.016, 0.016, 0.45)
	return _cached_needle_mesh

static func _get_cached_micro_arc_box() -> BoxMesh:
	if _cached_micro_arc_mesh == null:
		_cached_micro_arc_mesh = BoxMesh.new()
		_cached_micro_arc_mesh.size = Vector3(0.03, 0.03, 0.09)
	return _cached_micro_arc_mesh

static func _get_cached_impact_starburst() -> ArrayMesh:
	if _cached_starburst_mesh != null:
		return _cached_starburst_mesh

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3.ZERO
	var white := Color(1.0, 1.0, 1.0, 1.0)
	var edge := Color(1.0, 0.9, 0.5, 0.0)

	var ray_count := 8
	var ray_len := 0.75
	var ray_width := 0.06
	for i in range(ray_count):
		var angle := i * (TAU / ray_count)
		var dir := Vector3(cos(angle), sin(angle), 0.1).normalized()
		var perp := Vector3(-sin(angle), cos(angle), 0) * ray_width
		var tip := dir * ray_len

		st.set_color(white); st.add_vertex(center)
		st.set_color(edge); st.add_vertex(center - perp)
		st.set_color(white); st.add_vertex(tip)

		st.set_color(white); st.add_vertex(center)
		st.set_color(white); st.add_vertex(tip)
		st.set_color(edge); st.add_vertex(center + perp)

	var core_rad := 0.22
	st.set_color(white); st.add_vertex(center)
	st.set_color(white); st.add_vertex(Vector3(-core_rad, 0, 0.05))
	st.set_color(white); st.add_vertex(Vector3(0, core_rad, 0.05))

	st.set_color(white); st.add_vertex(center)
	st.set_color(white); st.add_vertex(Vector3(0, core_rad, 0.05))
	st.set_color(white); st.add_vertex(Vector3(core_rad, 0, 0.05))

	st.set_color(white); st.add_vertex(center)
	st.set_color(white); st.add_vertex(Vector3(core_rad, 0, 0.05))
	st.set_color(white); st.add_vertex(Vector3(0, -core_rad, 0.05))

	st.set_color(white); st.add_vertex(center)
	st.set_color(white); st.add_vertex(Vector3(0, -core_rad, 0.05))
	st.set_color(white); st.add_vertex(Vector3(-core_rad, 0, 0.05))

	_cached_starburst_mesh = st.commit()
	return _cached_starburst_mesh

static func _get_cached_hit_material(flash_color: Color) -> StandardMaterial3D:
	var key := flash_color.to_rgba32()
	if _cached_hit_mats.has(key):
		return _cached_hit_mats[key]
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.98)
	mat.emission_enabled = true
	mat.emission = flash_color
	mat.emission_energy_multiplier = 8.0
	_cached_hit_mats[key] = mat
	return mat

static func _get_cached_spark_material(color: Color) -> StandardMaterial3D:
	var key := color.to_rgba32()
	if _cached_spark_mats.has(key):
		return _cached_spark_mats[key]
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.95)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 7.0
	_cached_spark_mats[key] = mat
	return mat


static func _get_cached_explosion_ring_mat() -> StandardMaterial3D:
	if _cached_explosion_ring_mat != null:
		return _cached_explosion_ring_mat
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.6, 0.15, 0.9)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.1)
	m.emission_energy_multiplier = 4.0
	_cached_explosion_ring_mat = m
	return m


static func _get_cached_explosion_core_mat() -> StandardMaterial3D:
	if _cached_explosion_core_mat != null:
		return _cached_explosion_core_mat
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.8, 0.3, 0.95)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.7, 0.2)
	m.emission_energy_multiplier = 4.5
	_cached_explosion_core_mat = m
	return m


static func _get_cached_explosion_particle_mat() -> StandardMaterial3D:
	if _cached_explosion_particle_mat != null:
		return _cached_explosion_particle_mat
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.55, 0.15, 1.0)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.1)
	m.emission_energy_multiplier = 4.0
	_cached_explosion_particle_mat = m
	return m


static func _get_cached_explosion_smoke_mat() -> StandardMaterial3D:
	if _cached_explosion_smoke_mat != null:
		return _cached_explosion_smoke_mat
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.2, 0.2, 0.22, 0.6)
	_cached_explosion_smoke_mat = m
	return m


## Spawns dynamic, brilliant directional hit sparks, ricochet ember streaks, and a micro-flash light
## at the point of impact.
static func spawn_hit_spark(position: Vector3, normal: Vector3 = Vector3.UP, damage_type: String = "kinetic") -> void:
	if instance == null:
		return

	var norm := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	var dmg_type := damage_type.to_lower()
	var spark_color := Color(1.0, 0.88, 0.4) # Bright golden electric spark
	var flash_color := Color(1.0, 0.95, 0.6)

	if dmg_type == "heat" or dmg_type == "explosive":
		spark_color = Color(1.0, 0.5, 0.15) # Fire orange
		flash_color = Color(1.0, 0.7, 0.3)
	elif dmg_type == "emp" or dmg_type == "electric":
		spark_color = Color(0.35, 0.85, 1.0) # Plasma cyan
		flash_color = Color(0.65, 0.95, 1.0)
	elif dmg_type == "pierce":
		spark_color = Color(1.0, 0.98, 0.85) # White-hot piercing spark
		flash_color = Color(1.0, 1.0, 0.9)

	# 1. Micro Point Light Flash at impact (Throttled to max 4 concurrent lights)
	if _active_hit_lights < 4:
		_active_hit_lights += 1
		var light := OmniLight3D.new()
		light.light_color = flash_color
		light.light_energy = 8.5
		light.omni_range = 6.5
		light.omni_attenuation = 2.0
		instance.add_child(light)
		light.global_position = position + norm * 0.15

		var lt := instance.create_tween()
		lt.tween_property(light, "light_energy", 0.0, 0.06)
		lt.tween_callback(func():
			_active_hit_lights = maxi(0, _active_hit_lights - 1)
			light.queue_free()
		)

	# 2. Expanding High-Intensity 8-Point Starburst Flash Mesh
	var starburst := MeshInstance3D.new()
	starburst.mesh = _get_cached_impact_starburst()
	starburst.material_override = _get_cached_hit_material(flash_color)
	instance.add_child(starburst)
	starburst.global_position = position + norm * 0.06
	if norm.length_squared() > 0.001:
		starburst.look_at(position + norm, Vector3.UP if absf(norm.y) < 0.9 else Vector3.FORWARD)
	starburst.rotate_object_local(Vector3.FORWARD, randf_range(0.0, TAU))
	var base_scale := randf_range(1.1, 1.6)
	starburst.scale = Vector3.ONE * (base_scale * 0.4)

	var ct := instance.create_tween().set_parallel(true)
	ct.tween_property(starburst, "scale", Vector3.ONE * base_scale, 0.02).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	ct.tween_property(starburst, "scale", Vector3.ZERO, 0.05).set_delay(0.02)
	ct.chain().tween_callback(starburst.queue_free)

	# 3. High-Velocity Needle Streak Sparks (Long thin glowing sparks spraying outward)
	var needle_sparks := CPUParticles3D.new()
	needle_sparks.direction = norm
	needle_sparks.spread = 70.0
	needle_sparks.initial_velocity_min = 20.0
	needle_sparks.initial_velocity_max = 45.0
	needle_sparks.gravity = Vector3(0, -12.0, 0)
	needle_sparks.damping_min = 6.0
	needle_sparks.damping_max = 14.0
	needle_sparks.scale_amount_min = 0.5
	needle_sparks.scale_amount_max = 1.3
	needle_sparks.amount = 22
	needle_sparks.lifetime = 0.22
	needle_sparks.one_shot = true
	needle_sparks.explosiveness = 0.98
	needle_sparks.mesh = _get_cached_needle_spark_box()
	needle_sparks.material_override = _get_cached_spark_material(spark_color)
	needle_sparks.emitting = true

	instance.add_child(needle_sparks)
	needle_sparks.global_position = position
	if norm.length_squared() > 0.001:
		needle_sparks.look_at(position + norm, Vector3.UP if absf(norm.y) < 0.9 else Vector3.FORWARD)

	var n_tween := needle_sparks.create_tween()
	n_tween.tween_interval(0.28)
	n_tween.tween_callback(needle_sparks.queue_free)

	# 4. Snapping Armor Micro-Arcs & Molten Debris (Secondary bouncy sparks)
	var arc_sparks := CPUParticles3D.new()
	arc_sparks.direction = norm + Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.4), randf_range(-0.4, 0.4))
	arc_sparks.spread = 85.0
	arc_sparks.initial_velocity_min = 6.0
	arc_sparks.initial_velocity_max = 16.0
	arc_sparks.gravity = Vector3(0, -16.0, 0)
	arc_sparks.scale_amount_min = 0.4
	arc_sparks.scale_amount_max = 1.0
	arc_sparks.amount = 12
	arc_sparks.lifetime = 0.32
	arc_sparks.one_shot = true
	arc_sparks.explosiveness = 0.92
	arc_sparks.mesh = _get_cached_micro_arc_box()
	arc_sparks.material_override = _get_cached_spark_material(Color(1.0, 0.95, 0.7))
	arc_sparks.emitting = true

	instance.add_child(arc_sparks)
	arc_sparks.global_position = position
	var a_tween := arc_sparks.create_tween()
	a_tween.tween_interval(0.38)
	a_tween.tween_callback(arc_sparks.queue_free)


static func spawn_impact(position: Vector3, normal: Vector3) -> void:
	spawn_hit_spark(position, normal, "kinetic")


static func spawn_damage_number(position: Vector3, damage: float, color: Color = Color.WHITE) -> void:
	if instance == null:
		return

	var label = Label3D.new()
	label.text = str(int(damage))
	label.font_size = 32
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = color

	instance.add_child(label)
	label.global_position = position + Vector3(randf_range(-0.5, 0.5), 1.0, 0)

	var tween = instance.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", position.y + 2.5, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


static func spawn_explosion(position: Vector3, radius: float = 8.0) -> void:
	if instance == null:
		return

	# 1. High-intensity Dynamic Light Flash
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.2)
	light.light_energy = 14.0
	light.omni_range = maxf(radius * 3.0, 22.0)
	light.omni_attenuation = 1.6
	instance.add_child(light)
	light.global_position = position

	var lt := instance.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.22)
	lt.tween_callback(light.queue_free)

	# 2. Expanding Fiery Shockwave Ring (cached template duplicated so each ring can fade independently)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.0
	ring.mesh = torus
	var ring_mat: StandardMaterial3D = _get_cached_explosion_ring_mat().duplicate() as StandardMaterial3D
	ring.material_override = ring_mat
	instance.add_child(ring)
	ring.global_position = position + Vector3(0, 0.1, 0)
	ring.scale = Vector3(0.3, 0.1, 0.3)

	var ring_tween := instance.create_tween().set_parallel(true)
	ring_tween.tween_property(ring, "scale", Vector3(radius * 1.5, 0.1, radius * 1.5), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ring_tween.tween_property(ring_mat, "albedo_color:a", 0.0, 0.25)
	ring_tween.chain().tween_callback(ring.queue_free)

	# 3. Fiery Core Fireball Mesh (cached template duplicated so each core can fade independently)
	var core_mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	core_mesh.mesh = sphere
	var core_mat: StandardMaterial3D = _get_cached_explosion_core_mat().duplicate() as StandardMaterial3D
	core_mesh.material_override = core_mat
	instance.add_child(core_mesh)
	core_mesh.global_position = position
	core_mesh.scale = Vector3(0.2, 0.2, 0.2)

	var core_tween := instance.create_tween().set_parallel(true)
	core_tween.tween_property(core_mesh, "scale", Vector3(2.5, 2.5, 2.5), 0.1).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	core_tween.chain().tween_property(core_mesh, "scale", Vector3(0.1, 0.1, 0.1), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	core_tween.parallel().tween_property(core_mat, "albedo_color:a", 0.0, 0.18)
	core_tween.chain().tween_callback(core_mesh.queue_free)

	# 4. Explosion Screen Shake
	var rigs = instance.get_tree().get_nodes_in_group("camera_rig")
	if not rigs.is_empty() and rigs[0].has_method("add_shake"):
		var shake_str: float = clampf(radius * 0.05, 0.35, 0.65)
		rigs[0].add_shake(shake_str)

	# 5. Sound
	if AudioManager:
		AudioManager.play_explosion(position)

	# 6. Flying Fiery Sparks Particle Burst
	var explosion = GPUParticles3D.new()
	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 10.0
	mat.initial_velocity_max = 22.0
	mat.gravity = Vector3(0, -9.8, 0)
	mat.scale_min = 0.25
	mat.scale_max = 0.7

	explosion.process_material = mat
	explosion.amount = 36
	explosion.lifetime = 0.55
	explosion.one_shot = true
	explosion.explosiveness = 0.95
	explosion.emitting = true

	var spark_inst = MeshInstance3D.new()
	var spark_sphere = SphereMesh.new()
	spark_sphere.radius = 0.15
	spark_inst.mesh = spark_sphere
	var particle_mat: StandardMaterial3D = _get_cached_explosion_particle_mat().duplicate() as StandardMaterial3D
	spark_inst.material_override = particle_mat
	explosion.add_child(spark_inst)

	instance.add_child(explosion)
	explosion.global_position = position

	# 7. Billowing Smoke Puff
	var smoke = GPUParticles3D.new()
	var smoke_mat = ParticleProcessMaterial.new()
	smoke_mat.direction = Vector3(0, 1, 0)
	smoke_mat.spread = 80.0
	smoke_mat.initial_velocity_min = 3.0
	smoke_mat.initial_velocity_max = 7.0
	smoke_mat.gravity = Vector3(0, 2.5, 0)
	smoke_mat.scale_min = 0.5
	smoke_mat.scale_max = 1.4

	smoke.process_material = smoke_mat
	smoke.amount = 20
	smoke.lifetime = 0.9
	smoke.one_shot = true
	smoke.explosiveness = 0.8
	smoke.emitting = true

	var smoke_inst = MeshInstance3D.new()
	var smoke_sphere = SphereMesh.new()
	smoke_sphere.radius = 0.3
	smoke_inst.mesh = smoke_sphere
	var sm_mat: StandardMaterial3D = _get_cached_explosion_smoke_mat().duplicate() as StandardMaterial3D
	smoke_inst.material_override = sm_mat
	smoke.add_child(smoke_inst)

	instance.add_child(smoke)
	smoke.global_position = position

	var cleanup_tween := explosion.create_tween()
	cleanup_tween.tween_interval(1.1)
	cleanup_tween.tween_callback(explosion.queue_free)
	cleanup_tween.tween_callback(smoke.queue_free)


## Deals area of effect explosion damage.
## - Pilots on foot (unarmored humans) take DEVASTATING damage (2.2x multiplier, lethal).
## - Armored Mechas with composite steel plating take moderated damage (0.75x multiplier, chipped armor).
static func apply_area_explosion_damage(
	blast_pos: Vector3,
	base_damage: float,
	radius: float = 8.0,
	fired_by_enemy: bool = false,
	damage_type: String = "explosive",
	exclude_node: Node = null
) -> void:
	if instance == null or not instance.is_inside_tree():
		return

	var candidates: Array = []
	var tree := instance.get_tree()

	if fired_by_enemy:
		candidates.append_array(tree.get_nodes_in_group("mecha"))
		candidates.append_array(tree.get_nodes_in_group("pilot"))
		candidates.append_array(tree.get_nodes_in_group("ally"))
	else:
		candidates.append_array(tree.get_nodes_in_group("enemy"))
		candidates.append_array(tree.get_nodes_in_group("enemy_pilot"))

	for target in candidates:
		if not is_instance_valid(target) or target == exclude_node:
			continue

		var target_pos: Vector3 = target.global_position
		if target.is_in_group("mecha") or target.is_in_group("enemy") or target.is_in_group("ally"):
			target_pos += Vector3(0, 1.5, 0)
		else:
			target_pos += Vector3(0, 0.8, 0)

		var dist: float = blast_pos.distance_to(target_pos)
		if dist > radius:
			continue

		# Linear distance falloff: 100% at center down to 35% at the edge
		var falloff: float = clampf(1.0 - 0.65 * (dist / radius), 0.35, 1.0)
		var is_pilot: bool = target.is_in_group("pilot") or target.is_in_group("enemy_pilot")

		# Multiplier: Pilots (flesh/infantry) take 2.2x lethal explosion damage;
		# Mechas (heavy composite plating) absorb/deflect blast pressure, taking 0.75x chip damage.
		var type_mult: float = 2.2 if is_pilot else 0.75
		var final_dmg: float = base_damage * falloff * type_mult

		if target.has_method("take_damage_at_point"):
			target.take_damage_at_point(final_dmg, blast_pos, damage_type)
		elif target.has_method("take_damage"):
			target.take_damage(final_dmg, damage_type)

		# Knockback / impact push from blast center
		var push_dir: Vector3 = (target.global_position - blast_pos)
		push_dir.y = 0.0
		if push_dir.length_squared() > 0.01:
			push_dir = push_dir.normalized()
			if target.has_method("apply_impact"):
				target.apply_impact(15.0 * falloff, push_dir)
			elif target is CharacterBody3D:
				target.velocity += push_dir * (20.0 * falloff if is_pilot else 5.0 * falloff)

		var num_color := Color(1.0, 0.3, 0.2) if is_pilot else Color(1.0, 0.65, 0.15)
		spawn_damage_number(target.global_position + Vector3(0, 1.8 if is_pilot else 2.5, 0), final_dmg, num_color)


## Spawns a fading arc of box meshes tracing a melee swing. The arc sweeps from
## -30° to +30° around the swing direction (flipped by sweep_dir for alternating
## combo swings); each segment spawns progressively further out and fades over
## 0.3s. Shared by the player's melee weapons and enemy/ally RUSHER swings.
static func spawn_melee_trail(
	from_pos: Vector3,
	direction: Vector3,
	color: Color,
	emission: Color = Color(1.0, 0.35, 0.2),
	forward_start: float = 1.2,
	forward_step: float = 1.2,
	sweep_dir: float = 1.0,
) -> void:
	if instance == null:
		return

	var trail_count := 5
	var sweep_width := 5.0
	for i in range(trail_count):
		var t := float(i) / float(trail_count - 1)
		var trail := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(sweep_width, 0.08, 0.2)
		trail.mesh = box

		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(color.r, color.g, color.b, 1.0 - t * 0.6)
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = 5.0 - t * 3.0
		mat.no_depth_test = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		trail.material_override = mat

		instance.get_tree().current_scene.add_child(trail)

		var height_offset := lerpf(1.8, 0.8, t)
		trail.global_position = from_pos + Vector3(0, height_offset, 0) + direction * (forward_start + t * forward_step)
		trail.look_at(trail.global_position + direction, Vector3.UP)
		trail.rotate_object_local(Vector3.FORWARD, deg_to_rad(90))
		trail.rotate_object_local(Vector3.UP, deg_to_rad((-30.0 + t * 60.0) * sweep_dir))

		var delay := t * 0.04
		var tween := instance.get_tree().create_tween()
		tween.tween_interval(delay)
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.3)
		tween.tween_callback(trail.queue_free)


## Collision-based melee hit check: casts a ray from the attacker (~chest
## height) along the swing. Whiffs when the ray stops on environment geometry
## (collision_layer bit 2) first, and only damages the first body that exposes
## take_damage(). Damage is applied directly and never depends on an EffectManager
## instance being live (only the damage-number visual does). Returns true when
## something took damage.
static func melee_hit_ray(
	attacker: Node3D,
	direction: Vector3,
	range: float,
	collision_mask: int,
	damage: float,
	damage_type: String = "blunt",
) -> bool:
	if attacker == null or attacker.get_viewport() == null:
		return false

	var space_state = attacker.get_viewport().get_world_3d().direct_space_state
	var start := attacker.global_position + Vector3(0, 1.5, 0)
	var end := start + direction * range
	var query = PhysicsRayQueryParameters3D.create(start, end)
	query.collision_mask = collision_mask
	var result = space_state.intersect_ray(query)
	if not result:
		return false

	var collider: CollisionObject3D = result["collider"]
	# If the ray stopped on a wall/cover first, the swing whiffs.
	if collider.collision_layer & 2 != 0:
		return false

	var victim: Node = collider
	while victim and not victim.has_method("take_damage"):
		victim = victim.get_parent()
	if victim == null or not victim.has_method("take_damage"):
		return false

	# Melee hits carry their attack type (heat/pierce/blunt) so armor plates
	# and shields match on it just like bullets and beams.
	victim.take_damage(damage, damage_type)
	spawn_damage_number(result["position"] + Vector3(0, 1, 0), damage, Color(1, 0.5, 0))
	return true


# Small burst of orange sparks + puff of grey smoke at a weapon barrel,
# used for reload-fail / jam feedback. Much lighter than a muzzle flash.
static func spawn_jam_sparks(position: Vector3) -> void:
	if instance == null:
		return

	# 1. Tiny spark burst (orange sparks shooting outward)
	var sparks := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 90.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 7.0
	mat.gravity = Vector3(0, -8, 0)
	mat.scale_min = 0.02
	mat.scale_max = 0.06
	sparks.process_material = mat
	sparks.amount = 10
	sparks.lifetime = 0.3
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.emitting = true
	var spark_mesh := MeshInstance3D.new()
	var spark_sphere := SphereMesh.new()
	spark_sphere.radius = 0.03
	spark_mesh.mesh = spark_sphere
	var spark_mat := StandardMaterial3D.new()
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(1.0, 0.7, 0.2, 0.95)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.6, 0.1)
	spark_mat.emission_energy_multiplier = 5.0
	spark_mesh.material_override = spark_mat
	sparks.add_child(spark_mesh)
	instance.add_child(sparks)
	sparks.global_position = position

	var spark_tween := sparks.create_tween()
	spark_tween.tween_interval(0.35)
	spark_tween.tween_callback(sparks.queue_free)

	# 2. Small grey smoke puff
	var smoke := GPUParticles3D.new()
	var smoke_mat := ParticleProcessMaterial.new()
	smoke_mat.direction = Vector3(0, 1, 0)
	smoke_mat.spread = 60.0
	smoke_mat.initial_velocity_min = 1.0
	smoke_mat.initial_velocity_max = 2.5
	smoke_mat.gravity = Vector3(0, 0.5, 0)
	smoke_mat.scale_min = 0.08
	smoke_mat.scale_max = 0.18
	smoke.process_material = smoke_mat
	smoke.amount = 6
	smoke.lifetime = 0.6
	smoke.one_shot = true
	smoke.explosiveness = 0.8
	smoke.emitting = true
	var smoke_mesh := MeshInstance3D.new()
	var smoke_sphere := SphereMesh.new()
	smoke_sphere.radius = 0.08
	smoke_mesh.mesh = smoke_sphere
	var smoke_std := StandardMaterial3D.new()
	smoke_std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_std.albedo_color = Color(0.5, 0.5, 0.5, 0.6)
	smoke_mesh.material_override = smoke_std
	smoke.add_child(smoke_mesh)
	instance.add_child(smoke)
	smoke.global_position = position + Vector3(0, 0.1, 0)

	var smoke_tween := smoke.create_tween()
	smoke_tween.tween_interval(0.7)
	smoke_tween.tween_callback(smoke.queue_free)

	# 3. Tiny flash light (warm orange, short-lived)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.1)
	light.light_energy = 2.0
	light.omni_range = 3.0
	light.omni_attenuation = 2.0
	instance.add_child(light)
	light.global_position = position
	var light_tween := instance.create_tween()
	light_tween.tween_property(light, "light_energy", 0.0, 0.15)
	light_tween.tween_callback(light.queue_free)


static func spawn_ground_dust(position: Vector3, direction: Vector3 = Vector3.UP, color: Color = Color(0.7, 0.65, 0.55, 0.55)) -> void:
	var target_parent: Node = instance if instance != null and is_instance_valid(instance) and instance.is_inside_tree() else Engine.get_main_loop().root
	if target_parent == null:
		return

	var dust := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = direction + Vector3(randf_range(-0.4, 0.4), 0.2, randf_range(-0.4, 0.4))
	mat.spread = 45.0
	mat.initial_velocity_min = 2.5
	mat.initial_velocity_max = 6.0
	mat.gravity = Vector3(0, 1.2, 0)
	mat.scale_min = 0.25
	mat.scale_max = 0.65
	dust.process_material = mat
	dust.amount = 10
	dust.lifetime = 0.45
	dust.one_shot = true
	dust.explosiveness = 0.85
	dust.emitting = true

	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	mesh_inst.mesh = sphere
	var std_mat := StandardMaterial3D.new()
	std_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std_mat.albedo_color = color
	mesh_inst.material_override = std_mat
	dust.add_child(mesh_inst)

	target_parent.add_child(dust)
	dust.global_position = position

	var tween := target_parent.create_tween()
	tween.tween_interval(0.5)
	tween.tween_callback(dust.queue_free)


static func spawn_thruster_burst(position: Vector3, direction: Vector3 = Vector3.BACK, color: Color = Color(0.3, 0.75, 1.0)) -> void:
	var target_parent: Node = instance if instance != null and is_instance_valid(instance) and instance.is_inside_tree() else Engine.get_main_loop().root
	if target_parent == null:
		return

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 5.0
	light.omni_range = 8.0
	target_parent.add_child(light)
	light.global_position = position

	var tween := target_parent.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(light.queue_free)
