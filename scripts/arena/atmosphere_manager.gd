extends Node

## Manages WorldEnvironment, Sky, Fog, and Lighting for Desert, Highrise City, Crossroads, and River Bridge themes.

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
		0: # DESERT (ทะเลทราย)
			sky_mat.sky_top_color = Color(0.48, 0.38, 0.25, 1)
			sky_mat.sky_horizon_color = Color(0.80, 0.65, 0.42, 1)
			env.volumetric_fog_density = 0.024
			env.volumetric_fog_albedo = Color(0.60, 0.48, 0.32, 1)
			env.ambient_light_color = Color(0.55, 0.45, 0.35, 1)
			if sun:
				sun.light_color = Color(1.0, 0.88, 0.65, 1)
				sun.light_energy = 1.5

		1: # CITY_HIGHRISE (เมืองตึกเยอะ)
			sky_mat.sky_top_color = Color(0.05, 0.06, 0.16, 1)
			sky_mat.sky_horizon_color = Color(0.12, 0.18, 0.35, 1)
			env.volumetric_fog_density = 0.015
			env.volumetric_fog_albedo = Color(0.08, 0.15, 0.28, 1)
			env.ambient_light_color = Color(0.20, 0.30, 0.45, 1)
			if sun:
				sun.light_color = Color(0.5, 0.7, 1.0, 1)
				sun.light_energy = 0.8

		2: # CROSSROADS (สี่แยก)
			sky_mat.sky_top_color = Color(0.12, 0.08, 0.22, 1)
			sky_mat.sky_horizon_color = Color(0.35, 0.22, 0.38, 1) # Purple twilight
			env.volumetric_fog_density = 0.018
			env.volumetric_fog_albedo = Color(0.20, 0.12, 0.25, 1)
			env.ambient_light_color = Color(0.35, 0.25, 0.40, 1)
			if sun:
				sun.light_color = Color(1.0, 0.70, 0.50, 1) # Sunset orange
				sun.light_energy = 1.1

		3: # RIVER_BRIDGE (สะพานแม่น้ำ)
			sky_mat.sky_top_color = Color(0.15, 0.25, 0.38, 1)
			sky_mat.sky_horizon_color = Color(0.40, 0.55, 0.70, 1) # Cool morning mist
			env.volumetric_fog_density = 0.022
			env.volumetric_fog_albedo = Color(0.35, 0.48, 0.60, 1)
			env.ambient_light_color = Color(0.30, 0.42, 0.55, 1)
			if sun:
				sun.light_color = Color(0.85, 0.92, 1.0, 1)
				sun.light_energy = 1.2

		4, 5: # FOREST (ป่า) / FOREST_ROAD (ถนนตัดผ่านป่า)
			sky_mat.sky_top_color = Color(0.12, 0.22, 0.10, 1)
			sky_mat.sky_horizon_color = Color(0.35, 0.52, 0.28, 1) # Sunlit forest canopy
			env.volumetric_fog_density = 0.030
			env.volumetric_fog_albedo = Color(0.22, 0.40, 0.18, 1)
			env.ambient_light_color = Color(0.30, 0.45, 0.25, 1)
			if sun:
				sun.light_color = Color(0.90, 1.0, 0.80, 1)
				sun.light_energy = 1.3

	var sky = Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.volumetric_fog_enabled = true
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.9
	env.tonemap_mode = 2

	# HDR Bloom / Glow for vibrant lasers, sparks, thruster flames and reflections
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.25
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 1.8

	if sun:
		sun.shadow_enabled = true
		sun.light_volumetric_fog_energy = 1.6

	_add_theme_ambient_lights(theme)
	_add_dust_particles(theme)
	_spawn_arena_fog_volumes(theme)


func _add_theme_ambient_lights(theme: int) -> void:
	var arena_size = 90.0
	var positions = [
		Vector3(-arena_size, 6, -arena_size),
		Vector3(arena_size, 6, arena_size),
		Vector3(-arena_size, 6, arena_size),
		Vector3(arena_size, 6, -arena_size),
		Vector3(0, 8, 0)
	]

	var light_col = Color(1.0, 0.8, 0.5)
	if theme == 1: light_col = Color(0.2, 0.8, 1.0) # Cyber blue
	elif theme == 2: light_col = Color(1.0, 0.5, 0.2) # Warm street light
	elif theme == 3: light_col = Color(0.4, 0.8, 0.9) # River cyan
	elif theme == 4 or theme == 5: light_col = Color(0.5, 0.9, 0.5) # Forest green

	for pos in positions:
		var light = OmniLight3D.new()
		light.light_color = light_col
		light.light_energy = 0.8
		light.omni_range = 90.0
		light.omni_attenuation = 1.2
		light.position = pos
		get_parent().add_child(light)


func _apply_hazard_overlay() -> void:
	var hazard := GlobalData.current_hazard
	if hazard == "":
		return
	var world_env = get_node_or_null("../WorldEnvironment")
	if world_env == null or world_env.environment == null:
		return
	var env = world_env.environment
	match hazard:
		"dust_storm":
			# Thick sandy fog, reduced visibility, yellow-orange tint.
			env.volumetric_fog_density = 0.06
			env.volumetric_fog_albedo = Color(0.80, 0.60, 0.30, 1)
			env.ambient_light_color = Color(0.70, 0.55, 0.30, 1)
			env.fog_light_color = Color(0.85, 0.65, 0.30, 1)
			env.fog_density = 0.04
			var sun = get_node_or_null("../DirectionalLight3D")
			if sun:
				sun.light_color = Color(1.0, 0.80, 0.40, 1)
				sun.light_energy = 0.9
		"tactical_smog":
			# Sickly green-gray haze, low visibility, dim lighting.
			env.volumetric_fog_density = 0.05
			env.volumetric_fog_albedo = Color(0.30, 0.45, 0.25, 1)
			env.ambient_light_color = Color(0.35, 0.50, 0.30, 1)
			env.fog_light_color = Color(0.40, 0.55, 0.30, 1)
			env.fog_density = 0.035
			var sun = get_node_or_null("../DirectionalLight3D")
			if sun:
				sun.light_color = Color(0.50, 0.70, 0.40, 1)
				sun.light_energy = 0.6
		"emp_zone":
			# Electric purple flicker, high contrast, harsh shadows.
			env.ambient_light_color = Color(0.40, 0.20, 0.70, 1)
			env.fog_light_color = Color(0.50, 0.30, 0.80, 1)
			env.fog_density = 0.015
			var sun = get_node_or_null("../DirectionalLight3D")
			if sun:
				sun.light_color = Color(0.60, 0.30, 1.0, 1)
				sun.light_energy = 1.2


func _add_dust_particles(theme: int) -> void:
	var particles = GPUParticles3D.new()
	particles.name = "AtmosphereParticles"
	particles.amount = 400
	particles.lifetime = 6.0
	particles.explosiveness = 0.0
	particles.randomness = 1.0

	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = 1
	mat.emission_box_extents = Vector3(110, 8, 110)
	mat.direction = Vector3(0, 0.1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.2
	mat.initial_velocity_max = 0.6
	mat.gravity = Vector3(0, -0.01, 0)
	mat.scale_min = 0.08
	mat.scale_max = 0.25
	particles.process_material = mat

	var draw_mesh = BoxMesh.new()
	draw_mesh.size = Vector3(0.12, 0.12, 0.12)
	var draw_mat = StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	if theme == 0: draw_mat.albedo_color = Color(0.85, 0.70, 0.45, 0.3) # Sandstorm dust
	elif theme == 1: draw_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.2) # City motes
	elif theme == 2: draw_mat.albedo_color = Color(0.9, 0.6, 0.4, 0.2) # Twilight haze
	elif theme == 3: draw_mat.albedo_color = Color(0.7, 0.85, 1.0, 0.25) # River mist droplets
	elif theme == 4 or theme == 5: draw_mat.albedo_color = Color(0.4, 0.8, 0.4, 0.2) # Forest pollen / leaf motes

	draw_mat.no_depth_test = true
	draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	draw_mesh.material = draw_mat
	particles.draw_pass_1 = draw_mesh

	particles.position.y = 4.0
	get_parent().add_child(particles)

	# Apply environmental hazard overlay after base atmosphere.
	_apply_hazard_overlay()


func _spawn_arena_fog_volumes(theme: int) -> void:
	# Add localized low-lying fog banks for dramatic battlefield atmosphere
	var fog_bank_positions = [
		Vector3(-35, 1.5, -20),
		Vector3(40, 1.5, 25),
		Vector3(0, 1.0, 0)
	]
	for pos in fog_bank_positions:
		var fv := FogVolume.new()
		fv.name = "BattlefieldFogBank"
		fv.size = Vector3(50.0, 4.0, 50.0)
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		var fmat := FogMaterial.new()
		fmat.density = 0.04
		if theme == 0:
			fmat.albedo = Color(0.70, 0.55, 0.35) # Sandy low fog
		elif theme == 1:
			fmat.albedo = Color(0.15, 0.25, 0.40) # Smoggy neon fog
		elif theme == 2:
			fmat.albedo = Color(0.30, 0.18, 0.35) # Dusk mist
		elif theme == 3:
			fmat.albedo = Color(0.40, 0.55, 0.70) # River morning fog
		else:
			fmat.albedo = Color(0.25, 0.45, 0.22) # Damp forest mist
		fv.material = fmat
		fv.position = pos
		get_parent().add_child(fv)
