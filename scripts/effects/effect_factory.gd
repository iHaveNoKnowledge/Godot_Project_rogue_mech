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

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	if no_depth:
		mat.no_depth_test = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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
