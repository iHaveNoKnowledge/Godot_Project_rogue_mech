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
	# Matte PBR post-processing — low bloom, stronger AO for gritty realism
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 0.88
	env.glow_enabled = true
	env.glow_bloom = 0.08
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.35
	env.glow_hdr_scale = 0.85
	env.glow_intensity = 0.28
	env.ssao_enabled = true
	env.ssao_radius = 1.15
	env.ssao_intensity = 1.75
	env.ssao_power = 1.45
	env.ssao_detail = 0.68
	env.ssil_intensity = 0.35
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.02
	env.adjustment_brightness = 1.0

	var arena_gen = get_node_or_null("../ArenaGenerator")
	var theme = arena_gen.current_theme if arena_gen else 0

	var sky_mat = ProceduralSkyMaterial.new()
	var sun = get_node_or_null("../DirectionalLight3D")

	var hour: float = 12.0
	if "board" in GlobalData and "time_hour" in GlobalData.board:
		hour = float(GlobalData.board.time_hour)

	# --- TIME-OF-DAY ATMOSPHERE LIGHTING ---
	# Phase breakdown:
	#   05:00 - 07:30 : DAWN (Morning glow, low peach sun, soft horizon mist)
	#   07:30 - 16:30 : DAY (Brilliant high sun, clear azure/golden sky, full daylight)
	#   16:30 - 19:30 : DUSK (Amber-red sunset, long dramatic shadows, twilight horizon)
	#   19:30 - 05:00 : NIGHT (Cool moonlight, cosmic indigo sky, nocturnal atmosphere)

	var is_dawn := (hour >= 5.0 and hour < 7.5)
	var is_day := (hour >= 7.5 and hour < 16.5)
	var is_dusk := (hour >= 16.5 and hour < 19.5)

	# Dynamic Sun / Moon position & trajectory based on game hour (angles kept steep enough to prevent flat terrain self-shadowing)
	if sun:
		if is_dawn:
			var t := (hour - 5.0) / 2.5
			sun.rotation_degrees = Vector3(lerpf(-28.0, -45.0, t), lerpf(75.0, 45.0, t), 0.0)
		elif is_day:
			var t := (hour - 7.5) / 9.0
			sun.rotation_degrees = Vector3(lerpf(-45.0, -72.0, sin(t * PI)), lerpf(45.0, -60.0, t), 0.0)
		elif is_dusk:
			var t := (hour - 16.5) / 3.0
			sun.rotation_degrees = Vector3(lerpf(-45.0, -28.0, t), lerpf(-60.0, -110.0, t), 0.0)
		else: # Night Moon
			sun.rotation_degrees = Vector3(-52.0, 135.0, 0.0)

	# Base Lighting Colors tailored per Time-of-Day phase and themed by biome
	if is_dawn:
		sky_mat.sky_top_color = Color(0.20, 0.28, 0.50, 1)
		sky_mat.sky_horizon_color = Color(0.96, 0.72, 0.52, 1)
		sky_mat.ground_bottom_color = Color(0.40, 0.30, 0.22, 1)
		sky_mat.ground_horizon_color = Color(0.75, 0.55, 0.40, 1)
		env.volumetric_fog_density = 0.012
		env.volumetric_fog_albedo = Color(0.90, 0.75, 0.58, 1)
		env.ambient_light_color = Color(0.65, 0.55, 0.45, 1)
		env.ambient_light_energy = 0.85
		if sun:
			sun.light_color = Color(1.0, 0.85, 0.68, 1)
			sun.light_energy = 1.45
	elif is_day:
		match theme:
			0: # DESERT (ทะเลทราย)
				sky_mat.sky_top_color = Color(0.28, 0.52, 0.88, 1)
				sky_mat.sky_horizon_color = Color(0.95, 0.82, 0.60, 1)
				sky_mat.ground_bottom_color = Color(0.68, 0.55, 0.38, 1)
				sky_mat.ground_horizon_color = Color(0.88, 0.75, 0.52, 1)
				env.volumetric_fog_density = 0.008
				env.volumetric_fog_albedo = Color(0.88, 0.78, 0.60, 1)
				env.ambient_light_color = Color(0.80, 0.70, 0.55, 1)
				env.ambient_light_energy = 0.5
				if sun:
					sun.light_color = Color(1.0, 0.95, 0.85, 1)
					sun.light_energy = 1.0
			1: # CITY_HIGHRISE
				sky_mat.sky_top_color = Color(0.18, 0.32, 0.58, 1)
				sky_mat.sky_horizon_color = Color(0.60, 0.72, 0.85, 1)
				env.volumetric_fog_density = 0.012
				env.volumetric_fog_albedo = Color(0.40, 0.50, 0.65, 1)
				env.ambient_light_color = Color(0.45, 0.55, 0.65, 1)
				if sun:
					sun.light_color = Color(0.95, 0.95, 1.0, 1)
					sun.light_energy = 1.6
			2: # CROSSROADS
				sky_mat.sky_top_color = Color(0.22, 0.40, 0.70, 1)
				sky_mat.sky_horizon_color = Color(0.75, 0.80, 0.85, 1)
				env.volumetric_fog_density = 0.010
				env.volumetric_fog_albedo = Color(0.55, 0.60, 0.70, 1)
				env.ambient_light_color = Color(0.50, 0.55, 0.60, 1)
				if sun:
					sun.light_color = Color(1.0, 0.92, 0.80, 1)
					sun.light_energy = 1.8
			3: # RIVER_BRIDGE
				sky_mat.sky_top_color = Color(0.20, 0.45, 0.75, 1)
				sky_mat.sky_horizon_color = Color(0.65, 0.80, 0.90, 1)
				env.volumetric_fog_density = 0.014
				env.volumetric_fog_albedo = Color(0.50, 0.68, 0.80, 1)
				env.ambient_light_color = Color(0.45, 0.60, 0.70, 1)
				if sun:
					sun.light_color = Color(0.90, 0.96, 1.0, 1)
					sun.light_energy = 1.7
			_: # FOREST / FOREST_ROAD
				sky_mat.sky_top_color = Color(0.22, 0.48, 0.78, 1)
				sky_mat.sky_horizon_color = Color(0.65, 0.85, 0.60, 1)
				env.volumetric_fog_density = 0.016
				env.volumetric_fog_albedo = Color(0.40, 0.65, 0.38, 1)
				env.ambient_light_color = Color(0.40, 0.58, 0.38, 1)
				if sun:
					sun.light_color = Color(0.95, 1.0, 0.88, 1)
					sun.light_energy = 1.85
	elif is_dusk:
		sky_mat.sky_top_color = Color(0.14, 0.10, 0.30, 1)
		sky_mat.sky_horizon_color = Color(0.96, 0.48, 0.22, 1)
		sky_mat.ground_bottom_color = Color(0.35, 0.20, 0.15, 1)
		sky_mat.ground_horizon_color = Color(0.70, 0.35, 0.20, 1)
		env.volumetric_fog_density = 0.014
		env.volumetric_fog_albedo = Color(0.85, 0.40, 0.25, 1)
		env.ambient_light_color = Color(0.55, 0.35, 0.30, 1)
		env.ambient_light_energy = 0.80
		if sun:
			sun.light_color = Color(1.0, 0.55, 0.28, 1)
			sun.light_energy = 1.4
	else: # NIGHT
		sky_mat.sky_top_color = Color(0.02, 0.03, 0.08, 1)
		sky_mat.sky_horizon_color = Color(0.08, 0.12, 0.22, 1)
		sky_mat.ground_bottom_color = Color(0.04, 0.05, 0.09, 1)
		sky_mat.ground_horizon_color = Color(0.07, 0.10, 0.18, 1)
		env.volumetric_fog_density = 0.010
		env.volumetric_fog_albedo = Color(0.12, 0.18, 0.32, 1)
		env.ambient_light_color = Color(0.22, 0.28, 0.42, 1)
		env.ambient_light_energy = 0.65
		if sun:
			sun.light_color = Color(0.50, 0.70, 0.98, 1) # Moonlight
			sun.light_energy = 0.45

	var sky = Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	
	# Distance Horizon Fog — softly blends distant outer skirt & backdrops into sky horizon
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0022
	env.fog_light_color = sky_mat.sky_horizon_color
	env.fog_sun_scatter = 0.30
	env.fog_aerial_perspective = 0.65
	env.fog_sky_affect = 0.40

	# Volumetric atmospheric fog with high-fidelity temporal reprojection
	env.volumetric_fog_enabled = true
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.92

	# Matte, grounded ACES Tonemapping — lower saturation/exposure so clay plastic doesn't pop
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.02
	env.tonemap_white = 0.88
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.02
	env.adjustment_brightness = 1.0

	# HDR Bloom / Glow — CUT 60% so only lasers/thrusters glow, not whole ground (fixes plastic bloom)
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_bloom = 0.10
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.45
	env.glow_hdr_scale = 0.85

	# SSAO — stronger, more detailed for contact grit (matte crevices, not soft plastic)
	env.ssao_enabled = true
	env.ssao_radius = 1.15
	env.ssao_intensity = 1.75
	env.ssao_power = 1.45
	env.ssao_detail = 0.68
	env.ssao_horizon = 0.08
	env.ssao_sharpness = 0.90
	env.ssao_light_affect = 0.38

	# SSIL — cut bounce so ground doesn't look waxy from indirect light
	env.ssil_enabled = true
	env.ssil_radius = 3.2
	env.ssil_intensity = 0.35
	env.ssil_sharpness = 0.82
	env.ssil_normal_rejection = 1.2

	# SDFGI – lower energy so indirect is matte, not plastic fill
	env.sdfgi_enabled = true
	env.sdfgi_energy = 0.42
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.30
	env.sdfgi_max_distance = 140.0
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_100_PERCENT
	env.sdfgi_use_occlusion = false

	# SSR — OFF for matte ground (only metals should reflect). Keeps ground from looking wet plastic
	env.ssr_enabled = false
	env.ssr_max_steps = 16
	env.ssr_fade_in = 0.30
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.40

	if sun:
		sun.shadow_enabled = true
		sun.shadow_blur = 1.35
		sun.shadow_bias = 0.06
		sun.shadow_normal_bias = 2.0
		sun.shadow_opacity = 0.85
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_blend_splits = true
		sun.directional_shadow_max_distance = 160.0
		sun.directional_shadow_split_1 = 0.10
		sun.directional_shadow_split_2 = 0.25
		sun.directional_shadow_split_3 = 0.55
		sun.light_volumetric_fog_energy = 1.0

	env.ambient_light_sky_contribution = 0.80

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
	var hazard := GlobalData.board.current_hazard
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
	# Soft low-lying mist at the far perimeters — ellipsoids already feathered,
	# but keep them high (y 3.5) and light (density 0.0028) so they never
	# project a hard square shadow directly under the player at the arena center.
	var fog_bank_positions = [
		Vector3(-68, 3.5, -58),
		Vector3(68, 3.5, 58)
	]
	for pos in fog_bank_positions:
		var fv := FogVolume.new()
		fv.name = "BattlefieldFogBank"
		fv.size = Vector3(72.0, 7.5, 72.0)
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		var fmat := FogMaterial.new()
		fmat.density = 0.0028
		fmat.emission = Color(0.0, 0.0, 0.0)
		fmat.height_falloff = 0.22
		if theme == 0:
			fmat.albedo = Color(0.85, 0.72, 0.50) # Sandy low mist
		elif theme == 1:
			fmat.albedo = Color(0.20, 0.35, 0.55) # City ambient mist
		elif theme == 2:
			fmat.albedo = Color(0.40, 0.28, 0.45) # Dusk mist
		elif theme == 3:
			fmat.albedo = Color(0.50, 0.65, 0.80) # River morning mist
		else:
			fmat.albedo = Color(0.35, 0.55, 0.30) # Forest mist
		fv.material = fmat
		fv.position = pos
		get_parent().add_child(fv)
