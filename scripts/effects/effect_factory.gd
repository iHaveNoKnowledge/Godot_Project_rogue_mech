class_name EffectFactory
extends RefCounted

## ---------------------------------------------------------------------------
## EFFECT FACTORY — shared VFX helpers that eliminate copy-pasted material,
## mesh, and tween boilerplate across mecha_controller, mecha_health_base,
## drop_tank_visuals, projectile, and loot_system.
##
## Every function is static — no instance needed.  Callers pass the scene tree
## (or a parent node) and a world-space position; the factory creates the
## temporary mesh, adds it to the scene, tweens it, and queue_frees it.
## ---------------------------------------------------------------------------


static var _flash_base_mat_no_depth: StandardMaterial3D = null
static var _flash_base_mat_default: StandardMaterial3D = null

static func _get_flash_base_mat(no_depth: bool) -> StandardMaterial3D:
	if no_depth and _flash_base_mat_no_depth != null:
		return _flash_base_mat_no_depth
	if not no_depth and _flash_base_mat_default != null:
		return _flash_base_mat_default
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission_energy_multiplier = 5.0
	if no_depth:
		m.no_depth_test = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if no_depth:
		_flash_base_mat_no_depth = m
	else:
		_flash_base_mat_default = m
	return m

## Simple emissive sphere that fades out and frees itself.  The workhorse for
## flash effects, spark puffs, precision-dodge glows, roller sparks, and the
## breach-warning pulse.
##
## Parameters:
##   scene        – the tree to add the node to (usually get_tree().current_scene)
##   pos          – world-space spawn position
##   color        – albedo + emission color
##   radius       – sphere radius
##   duration     – seconds before the node is freed
##   energy       – emission_energy_multiplier
##   no_depth     – disable depth testing (true for HUD-style overlays)
##   target_scale – final scale (tweened from 1×)
##   parent       – optional: if set, node is added to parent instead of scene
static func spawn_flash(scene: SceneTree, pos: Vector3, color: Color,
		radius: float = 0.5, duration: float = 0.2, energy: float = 5.0,
		no_depth: bool = true, target_scale: float = 2.0,
		parent: Node3D = null) -> void:
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	mesh_inst.mesh = sphere

	var mat: StandardMaterial3D = (_get_flash_base_mat(no_depth).duplicate() as StandardMaterial3D)
	mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mesh_inst.material_override = mat

	var container: Node = parent if parent else (scene.current_scene if scene.current_scene else scene.root)
	container.add_child(mesh_inst)
	mesh_inst.global_position = pos

	var tween := scene.create_tween().set_parallel(true)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, duration)
	if target_scale > 0.0:
		var s := Vector3(target_scale, target_scale, target_scale)
		tween.tween_property(mesh_inst, "scale", s, duration)
	tween.chain().tween_callback(mesh_inst.queue_free)


## Simple box-mesh spark that fades out.  Used for roller sparks, debris
## sparks, detonation shrapnel, and weapon-impact sparks.
static func spawn_box_spark(scene: SceneTree, pos: Vector3, size: Vector3,
		color: Color, duration: float = 0.15, energy: float = 4.0,
		parent: Node3D = null) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mesh_inst.material_override = mat

	var container: Node = parent if parent else (scene.current_scene if scene.current_scene else scene.root)
	container.add_child(mesh_inst)
	mesh_inst.global_position = pos

	var tween := scene.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.tween_callback(mesh_inst.queue_free)


## Expanding ring / shockwave that scales up and fades.  Used for landing
## impacts, explosion shockwaves, and purge rings.
static func spawn_expanding_ring(scene: SceneTree, pos: Vector3,
		color: Color, start_scale: Vector3 = Vector3(1, 1, 1),
		end_scale: Vector3 = Vector3(5.5, 1.0, 5.5),
		duration: float = 0.35, energy: float = 2.5,
		parent: Node3D = null) -> void:
	var mesh_inst := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.4
	cylinder.bottom_radius = 0.5
	cylinder.height = 0.04
	mesh_inst.mesh = cylinder

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mesh_inst.material_override = mat

	var container: Node = parent if parent else (scene.current_scene if scene.current_scene else scene.root)
	container.add_child(mesh_inst)
	mesh_inst.global_position = pos
	mesh_inst.scale = start_scale

	var tween := scene.create_tween().set_parallel(true)
	tween.tween_property(mesh_inst, "scale", end_scale, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(mesh_inst.queue_free)


## Scattered dust puffs expanding outward from a point.  Used for landing
## impacts and ground-level explosions.
static func spawn_dust_puffs(scene: SceneTree, pos: Vector3,
		count: int = 8, min_radius: float = 0.2, max_radius: float = 0.4,
		push_min: float = 2.0, push_max: float = 3.5,
		color: Color = Color(0.75, 0.70, 0.65, 0.7),
		duration: float = 0.4, parent: Node3D = null) -> void:
	var container: Node = parent if parent else (scene.current_scene if scene.current_scene else scene.root)
	for i in range(count):
		var dust := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = randf_range(min_radius, max_radius)
		sphere.height = sphere.radius * 2.0
		dust.mesh = sphere

		var d_mat := StandardMaterial3D.new()
		d_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		d_mat.albedo_color = Color(color.r, color.g, color.b, color.a)
		dust.material_override = d_mat

		container.add_child(dust)
		var angle := (float(i) / float(count)) * TAU
		var dir := Vector3(cos(angle), 0.1, sin(angle))
		dust.global_position = pos + dir * 0.3

		var dtween := scene.create_tween().set_parallel(true)
		var target := pos + dir * randf_range(push_min, push_max) \
			+ Vector3(0, randf_range(0.3, 0.7), 0)
		dtween.tween_property(dust, "global_position", target, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		dtween.tween_property(d_mat, "albedo_color:a", 0.0, duration)
		dtween.chain().tween_callback(dust.queue_free)


## Emissive trail strip (dash trails, beam tracers).  The caller supplies the
## world position and a direction Vector3; the factory creates a BoxMesh strip,
## makes it transparent, and fades it out.
static func spawn_trail_dir(scene: SceneTree, pos: Vector3, dir: Vector3,
		size: Vector3, color: Color, emission: Color,
		duration: float = 0.2, energy: float = 3.0,
		no_depth: bool = true, parent: Node3D = null) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, color.a)
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	if no_depth:
		mat.no_depth_test = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = mat

	var container: Node = parent if parent else (scene.current_scene if scene.current_scene else scene.root)
	container.add_child(mesh_inst)
	mesh_inst.global_position = pos
	if dir.length_squared() > 0.001:
		mesh_inst.look_at(pos + dir, Vector3.UP)

	var tween := scene.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.tween_callback(mesh_inst.queue_free)


## Emissive trail strip (dash trails, beam tracers).  The caller supplies the
## world position and rotation Basis; the factory creates a BoxMesh strip,
## makes it transparent, and fades it out.
static func spawn_trail(scene: SceneTree, pos: Vector3, rot: Basis,
		size: Vector3, color: Color, emission: Color,
		duration: float = 0.2, energy: float = 3.0,
		no_depth: bool = true, parent: Node3D = null) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, color.a)
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	if no_depth:
		mat.no_depth_test = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = mat

	var container: Node = parent if parent else (scene.current_scene if scene.current_scene else scene.root)
	container.add_child(mesh_inst)
	mesh_inst.global_position = pos
	mesh_inst.global_rotation = rot.get_euler()

	var tween := scene.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.tween_callback(mesh_inst.queue_free)


## Electric lightning arc / spark (EMP hazard discharge, shock status, electrified hits).
static func spawn_electric_spark(scene: SceneTree, pos: Vector3,
		color: Color = Color(0.35, 0.85, 1.0), length: float = 0.8,
		duration: float = 0.1, energy: float = 5.0,
		parent: Node3D = null) -> void:
	if scene == null:
		return
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.035
	cyl.height = length
	mesh_inst.mesh = cyl

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.95)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.no_depth_test = true
	mesh_inst.material_override = mat

	var container: Node = parent if parent else (scene.current_scene if scene.current_scene else scene.root)
	container.add_child(mesh_inst)
	mesh_inst.global_position = pos + Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), randf_range(-0.2, 0.2))
	mesh_inst.rotation = Vector3(randf_range(-PI, PI), randf_range(-PI, PI), randf_range(-PI, PI))

	var tween := scene.create_tween().set_parallel(true)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.tween_property(mesh_inst, "scale", Vector3(1.5, 0.2, 1.5), duration)
	tween.chain().tween_callback(mesh_inst.queue_free)


## Spawns a burst of multiple crackling electric sparks and a mini flash light.
static func spawn_electric_burst(scene: SceneTree, pos: Vector3,
		color: Color = Color(0.4, 0.85, 1.0), count: int = 5,
		radius: float = 1.0, parent: Node3D = null) -> void:
	if scene == null:
		return
	for i in range(count):
		var offset := Vector3(randf_range(-radius, radius), randf_range(0.2, radius * 1.5), randf_range(-radius, radius))
		spawn_electric_spark(scene, pos + offset, color, randf_range(0.4, 0.9), randf_range(0.08, 0.16), 5.5, parent)

	spawn_flash(scene, pos + Vector3(0, 0.8, 0), color, 0.4, 0.12, 4.0, true, 2.5, parent)


## Spawns a multi-layer rising fire burst with white-hot core, rolling flame puffs,
## and a dynamic flickering point light casting light onto the scene.
static func spawn_fire_burst(scene: SceneTree, pos: Vector3,
		radius: float = 0.7, duration: float = 0.45, energy: float = 6.0,
		parent: Node3D = null) -> void:
	if scene == null:
		return
	var container: Node = parent if parent else (scene.current_scene if scene.current_scene else scene.root)

	# 1. White-hot core sphere
	var core := MeshInstance3D.new()
	var c_sphere := SphereMesh.new()
	c_sphere.radius = radius * 0.45
	c_sphere.height = c_sphere.radius * 2.0
	core.mesh = c_sphere
	var c_mat := StandardMaterial3D.new()
	c_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	c_mat.albedo_color = Color(1.0, 0.95, 0.8, 0.95)
	c_mat.emission_enabled = true
	c_mat.emission = Color(1.0, 0.95, 0.7)
	c_mat.emission_energy_multiplier = energy * 1.5
	core.material_override = c_mat
	container.add_child(core)
	core.global_position = pos

	var ctween := scene.create_tween().set_parallel(true)
	ctween.tween_property(core, "scale", Vector3(2.2, 2.8, 2.2), duration * 0.6)
	ctween.tween_property(c_mat, "albedo_color:a", 0.0, duration * 0.6)
	ctween.tween_property(c_mat, "emission_energy_multiplier", 0.0, duration * 0.6)
	ctween.chain().tween_callback(core.queue_free)

	# 2. Outer flame puffs rolling upward
	for i in range(5):
		var flame := MeshInstance3D.new()
		var f_sphere := SphereMesh.new()
		f_sphere.radius = randf_range(radius * 0.35, radius * 0.65)
		f_sphere.height = f_sphere.radius * 2.2
		flame.mesh = f_sphere

		var f_mat := StandardMaterial3D.new()
		f_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		f_mat.albedo_color = Color(1.0, randf_range(0.3, 0.6), 0.05, 0.9)
		f_mat.emission_enabled = true
		f_mat.emission = Color(1.0, randf_range(0.2, 0.5), 0.0)
		f_mat.emission_energy_multiplier = energy
		flame.material_override = f_mat

		container.add_child(flame)
		var offset := Vector3(randf_range(-0.25, 0.25), randf_range(-0.1, 0.2), randf_range(-0.25, 0.25)) * radius
		flame.global_position = pos + offset

		var ftween := scene.create_tween().set_parallel(true)
		var rise_target := flame.global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.8, 1.6), randf_range(-0.3, 0.3))
		ftween.tween_property(flame, "global_position", rise_target, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ftween.tween_property(flame, "scale", Vector3(1.8, 2.2, 1.8), duration)
		ftween.tween_property(f_mat, "albedo_color:a", 0.0, duration)
		ftween.tween_property(f_mat, "emission_energy_multiplier", 0.0, duration)
		ftween.chain().tween_callback(flame.queue_free)

	# 3. Dynamic flickering illumination light
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.15)
	light.light_energy = 3.5
	light.omni_range = radius * 12.0
	light.omni_attenuation = 1.3
	container.add_child(light)
	light.global_position = pos + Vector3(0, 0.5, 0)

	var ltween := scene.create_tween()
	ltween.tween_property(light, "light_energy", 0.0, duration)
	ltween.tween_callback(light.queue_free)


## Spawns billowing dark smoke puffs that expand as they rise and slowly dissipate.
static func spawn_smoke_plume(scene: SceneTree, pos: Vector3,
		count: int = 6, min_radius: float = 0.3, max_radius: float = 0.65,
		duration: float = 0.9, color: Color = Color(0.18, 0.18, 0.20, 0.85),
		parent: Node3D = null) -> void:
	if scene == null:
		return
	var container: Node = parent if parent else (scene.current_scene if scene.current_scene else scene.root)

	for i in range(count):
		var smoke := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = randf_range(min_radius, max_radius)
		sphere.height = sphere.radius * 2.0
		smoke.mesh = sphere

		var s_mat := StandardMaterial3D.new()
		s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		s_mat.albedo_color = Color(color.r + randf_range(-0.04, 0.04), color.g + randf_range(-0.04, 0.04), color.b + randf_range(-0.04, 0.04), color.a)
		s_mat.roughness = 0.95
		smoke.material_override = s_mat

		container.add_child(smoke)
		var angle := randf_range(0, TAU)
		var spread := randf_range(0.1, 0.4)
		smoke.global_position = pos + Vector3(cos(angle) * spread, randf_range(0.0, 0.3), sin(angle) * spread)

		var stween := scene.create_tween().set_parallel(true)
		var rise_y := randf_range(1.5, 3.2)
		var drift := Vector3(randf_range(-0.6, 0.6), rise_y, randf_range(-0.6, 0.6))
		stween.tween_property(smoke, "global_position", smoke.global_position + drift, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		stween.tween_property(smoke, "scale", Vector3(2.5, 2.5, 2.5), duration)
		stween.tween_property(s_mat, "albedo_color:a", 0.0, duration)
		stween.chain().tween_callback(smoke.queue_free)


## Spawns a persistent charred scorch mark on the ground with rising flame flickers and smoke.
static func spawn_burning_ground(scene: SceneTree, pos: Vector3,
		radius: float = 1.2, duration: float = 2.5, parent: Node3D = null) -> void:
	if scene == null:
		return
	var container: Node = parent if parent else (scene.current_scene if scene.current_scene else scene.root)

	# 1. Scorch decal cylinder
	var scorch := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.02
	scorch.mesh = cyl

	var sc_mat := StandardMaterial3D.new()
	sc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sc_mat.albedo_color = Color(0.08, 0.06, 0.05, 0.85)
	scorch.material_override = sc_mat
	container.add_child(scorch)
	scorch.global_position = Vector3(pos.x, 0.02, pos.z)

	var sctween := scene.create_tween()
	sctween.tween_property(sc_mat, "albedo_color:a", 0.0, duration).set_delay(duration * 0.4)
	sctween.tween_callback(scorch.queue_free)

	# 2. Ground flame bursts over time
	for i in range(4):
		var delay := float(i) * (duration / 5.0)
		var fl_pos := pos + Vector3(randf_range(-radius * 0.5, radius * 0.5), 0.1, randf_range(-radius * 0.5, radius * 0.5))
		if is_instance_valid(container):
			var timer_tween := container.create_tween()
			timer_tween.tween_interval(delay)
			timer_tween.tween_callback(func():
				if is_instance_valid(container) and is_instance_valid(scene):
					spawn_fire_burst(scene, fl_pos, radius * 0.4, 0.4, 4.0, parent)
					spawn_smoke_plume(scene, fl_pos, 3, 0.2, 0.4, 0.7, Color(0.15, 0.15, 0.15, 0.7), parent)
			)


## Attaches a smoke & spark emitter node to a damaged mech limb.
static func spawn_damaged_smoke_emitter(parent: Node3D, local_pos: Vector3 = Vector3.ZERO) -> Node3D:
	if parent == null or not is_instance_valid(parent):
		return null
	var existing = parent.get_node_or_null("DamagedSmokeEmitter")
	if existing != null:
		return existing

	var emitter := Node3D.new()
	emitter.name = "DamagedSmokeEmitter"
	parent.add_child(emitter)
	emitter.position = local_pos

	var particles := GPUParticles3D.new()
	particles.amount = 24
	particles.lifetime = 1.2
	particles.explosiveness = 0.1
	particles.randomness = 0.8

	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pmat.emission_sphere_radius = 0.15
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 35.0
	pmat.initial_velocity_min = 0.8
	pmat.initial_velocity_max = 1.8
	pmat.gravity = Vector3(0, 0.5, 0) # Smoke rises
	pmat.scale_min = 0.15
	pmat.scale_max = 0.45
	pmat.color = Color(0.2, 0.2, 0.22, 0.7)
	particles.process_material = pmat

	var draw_mesh := SphereMesh.new()
	draw_mesh.radius = 0.15
	draw_mesh.height = 0.3
	var dmat := StandardMaterial3D.new()
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color = Color(0.18, 0.18, 0.20, 0.65)
	dmat.roughness = 0.9
	draw_mesh.material = dmat
	particles.draw_pass_1 = draw_mesh

	emitter.add_child(particles)
	return emitter


## Spawns dynamic angular armor shards and metal plating fragments that scatter outward
## with velocity and gravity, accompanied by hot spark bursts and ricochet effects.
static func spawn_armor_shatter_debris(scene: SceneTree, pos: Vector3,
		count: int = 12, piece_size: float = 0.25, base_color: Color = Color(0.65, 0.68, 0.72),
		parent: Node3D = null) -> void:
	if scene == null:
		return
	var container: Node = parent if parent else (scene.current_scene if scene.current_scene else scene.root)

	# 1. Flying armor plate shards
	for i in range(count):
		var shard := MeshInstance3D.new()
		# Alternate between triangular prism shards and angular plate boxes
		if i % 2 == 0:
			var prism := PrismMesh.new()
			prism.size = Vector3(randf_range(piece_size * 0.7, piece_size * 1.4), randf_range(piece_size * 0.6, piece_size * 1.2), 0.05)
			shard.mesh = prism
		else:
			var box := BoxMesh.new()
			box.size = Vector3(randf_range(piece_size * 0.8, piece_size * 1.3), randf_range(piece_size * 0.5, piece_size * 1.1), 0.04)
			shard.mesh = box

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(clampf(base_color.r + randf_range(-0.08, 0.08), 0.05, 1.0),
				clampf(base_color.g + randf_range(-0.08, 0.08), 0.05, 1.0),
				clampf(base_color.b + randf_range(-0.08, 0.08), 0.05, 1.0))
		mat.metallic = 0.75
		mat.roughness = 0.4
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.5, 0.1) # Glowing hot sheared metal edges
		mat.emission_energy_multiplier = randf_range(0.8, 2.5)
		shard.material_override = mat

		container.add_child(shard)
		shard.global_position = pos + Vector3(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15), randf_range(-0.15, 0.15))

		# Random outward trajectory
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.4, 1.4), randf_range(-1.0, 1.0)).normalized()
		var speed := randf_range(4.5, 9.5)
		var rot_speed := Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
		var duration := randf_range(0.7, 1.1)

		var tween := scene.create_tween().set_parallel(true)
		var end_pos := shard.global_position + dir * speed + Vector3(0, -2.5, 0)
		tween.tween_property(shard, "global_position", end_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(shard, "rotation", rot_speed, duration)
		tween.tween_property(mat, "albedo_color:a", 0.0, duration * 0.3).set_delay(duration * 0.7)
		tween.tween_property(mat, "emission_energy_multiplier", 0.0, duration * 0.6)
		tween.chain().tween_callback(shard.queue_free)

	# 2. Burst of bright ricochet sparks
	spawn_dust_puffs(scene, pos, 6, 0.15, 0.3, 1.5, 2.5, Color(0.8, 0.75, 0.7, 0.6), 0.35, parent)
	for s in range(8):
		var spark_pos := pos + Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), randf_range(-0.2, 0.2))
		spawn_box_spark(scene, spark_pos, Vector3(0.06, 0.06, 0.25), Color(1.0, 0.85, 0.3), 0.2, 6.0, parent)


## Spawns crackling electric arcs and high-voltage short-circuit sparks.
static func spawn_electrical_arc_burst(scene: SceneTree, pos: Vector3,
		count: int = 8, radius: float = 0.8, duration: float = 0.35,
		parent: Node3D = null) -> void:
	if scene == null:
		return
	var container: Node = parent if parent else (scene.current_scene if scene.current_scene else scene.root)

	for i in range(count):
		var arc := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(randf_range(0.04, 0.08), randf_range(0.2, 0.5), randf_range(0.04, 0.08))
		arc.mesh = box

		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.4, 0.85, 1.0, 0.95)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.8, 1.0)
		mat.emission_energy_multiplier = 7.0
		arc.material_override = mat

		container.add_child(arc)
		var offset := Vector3(randf_range(-radius, radius), randf_range(-radius, radius), randf_range(-radius, radius))
		arc.global_position = pos + offset
		arc.rotation = Vector3(randf_range(0, TAU), randf_range(0, TAU), randf_range(0, TAU))

		var tween := scene.create_tween().set_parallel(true)
		tween.tween_property(mat, "albedo_color:a", 0.0, duration)
		tween.tween_property(mat, "emission_energy_multiplier", 0.0, duration)
		tween.chain().tween_callback(arc.queue_free)
