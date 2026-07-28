extends Node

## Manages WorldEnvironment & Lighting matching the current arena BiomeTheme.

func _ready() -> void:
	await get_tree().process_frame
	_setup_atmosphere()


func _setup_atmosphere() -> void:
	var world_env = get_node_or_null("../WorldEnvironment")
	if world_env == null or world_env.environment == null:
		return

	var env = world_env.environment
	var arena_gen = get_node_or_null("../ArenaGenerator")
	var theme = arena_gen.current_theme if arena_gen else 0

	var sky_mat = ProceduralSkyMaterial.new()
	var sun = get_node_or_null("../DirectionalLight3D")

	match theme:
		1: # VOLCANIC
			sky_mat.sky_top_color = Color(0.18, 0.05, 0.05, 1)
			sky_mat.sky_horizon_color = Color(0.40, 0.12, 0.05, 1)
			env.volumetric_fog_density = 0.025
			env.volumetric_fog_albedo = Color(0.35, 0.10, 0.05, 1)
			env.ambient_light_color = Color(0.4, 0.15, 0.1, 1)
			if sun:
				sun.light_color = Color(1.0, 0.45, 0.2, 1)
				sun.light_energy = 1.0

		2: # CYBERPUNK
			sky_mat.sky_top_color = Color(0.08, 0.05, 0.22, 1)
			sky_mat.sky_horizon_color = Color(0.15, 0.25, 0.45, 1)
			env.volumetric_fog_density = 0.018
			env.volumetric_fog_albedo = Color(0.05, 0.20, 0.35, 1)
			env.ambient_light_color = Color(0.15, 0.35, 0.5, 1)
			if sun:
				sun.light_color = Color(0.4, 0.8, 1.0, 1)
				sun.light_energy = 0.7

		3: # DESERT
			sky_mat.sky_top_color = Color(0.45, 0.35, 0.25, 1)
			sky_mat.sky_horizon_color = Color(0.75, 0.60, 0.40, 1)
			env.volumetric_fog_density = 0.022
			env.volumetric_fog_albedo = Color(0.55, 0.45, 0.30, 1)
			env.ambient_light_color = Color(0.5, 0.4, 0.3, 1)
			if sun:
				sun.light_color = Color(1.0, 0.88, 0.65, 1)
				sun.light_energy = 1.4

		4: # SNOW
			sky_mat.sky_top_color = Color(0.25, 0.35, 0.45, 1)
			sky_mat.sky_horizon_color = Color(0.65, 0.75, 0.85, 1)
			env.volumetric_fog_density = 0.020
			env.volumetric_fog_albedo = Color(0.70, 0.80, 0.90, 1)
			env.ambient_light_color = Color(0.4, 0.5, 0.6, 1)
			if sun:
				sun.light_color = Color(0.85, 0.95, 1.0, 1)
				sun.light_energy = 1.1

		_: # INDUSTRIAL
			sky_mat.sky_top_color = Color(0.1, 0.1, 0.24, 1)
			sky_mat.sky_horizon_color = Color(0.23, 0.23, 0.29, 1)
			env.volumetric_fog_density = 0.015
			env.volumetric_fog_albedo = Color(0.18, 0.20, 0.25, 1)
			env.ambient_light_color = Color(0.25, 0.25, 0.35, 1)
			if sun:
				sun.light_color = Color(0.9, 0.85, 0.78, 1)
				sun.light_energy = 0.9

	var sky = Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.volumetric_fog_enabled = true
	env.tonemap_mode = 2

	_add_theme_ambient_lights(theme)
	_add_dust_particles(theme)


func _add_theme_ambient_lights(theme: int) -> void:
	var arena_size = 100.0
	var positions = [
		Vector3(-arena_size, 6, -arena_size),
		Vector3(arena_size, 6, arena_size),
		Vector3(-arena_size, 6, arena_size),
		Vector3(arena_size, 6, -arena_size),
	]

	var light_col = Color(1.0, 0.7, 0.3)
	if theme == 1: light_col = Color(1.0, 0.3, 0.1) # Red/Orange magma
	elif theme == 2: light_col = Color(0.1, 0.8, 1.0) # Cyan neon
	elif theme == 4: light_col = Color(0.6, 0.9, 1.0) # Ice cyan

	for pos in positions:
		var light = OmniLight3D.new()
		light.light_color = light_col
		light.light_energy = 0.6
		light.omni_range = 80.0
		light.omni_attenuation = 1.2
		light.position = pos
		get_parent().add_child(light)


func _add_dust_particles(theme: int) -> void:
	var particles = GPUParticles3D.new()
	particles.name = "AtmosphereParticles"
	particles.amount = 350
	particles.lifetime = 6.0
	particles.explosiveness = 0.0
	particles.randomness = 1.0

	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = 1
	mat.emission_box_extents = Vector3(110, 8, 110)
	mat.direction = Vector3(0, 0.1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.2
	mat.initial_velocity_max = 0.5
	mat.gravity = Vector3(0, -0.01, 0)
	mat.scale_min = 0.08
	mat.scale_max = 0.25
	particles.process_material = mat

	var draw_mesh = BoxMesh.new()
	draw_mesh.size = Vector3(0.12, 0.12, 0.12)
	var draw_mat = StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	if theme == 1: draw_mat.albedo_color = Color(1.0, 0.4, 0.1, 0.3) # Ash/Embers
	elif theme == 2: draw_mat.albedo_color = Color(0.2, 0.8, 1.0, 0.2) # Cyber Motes
	elif theme == 3: draw_mat.albedo_color = Color(0.8, 0.7, 0.5, 0.25) # Sand Dust
	elif theme == 4: draw_mat.albedo_color = Color(0.9, 0.95, 1.0, 0.3) # Snow flakes
	else: draw_mat.albedo_color = Color(0.8, 0.8, 0.8, 0.2) # Smog

	draw_mat.no_depth_test = true
	draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	draw_mesh.material = draw_mat
	particles.draw_pass_1 = draw_mesh

	particles.position.y = 4.0
	get_parent().add_child(particles)
