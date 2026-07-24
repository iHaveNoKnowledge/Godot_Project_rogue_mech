extends Node

## Manages WorldEnvironment settings for arena atmosphere.

@export var fog_density: float = 0.02
@export var fog_color: Color = Color(0.15, 0.18, 0.25, 1)
@export var sun_energy: float = 0.8
@export var sun_color: Color = Color(0.91, 0.86, 0.78, 1)


func _ready() -> void:
	# Wait for arena to generate
	await get_tree().process_frame
	_setup_atmosphere()


func _setup_atmosphere() -> void:
	var world_env = get_node_or_null("../WorldEnvironment")
	if world_env == null:
		return

	var env = world_env.environment
	if env == null:
		return

	# Sky - dark moody palette
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.1, 0.1, 0.24, 1)
	sky_mat.sky_horizon_color = Color(0.23, 0.23, 0.29, 1)
	sky_mat.ground_bottom_color = Color(0.04, 0.04, 0.06, 1)
	sky_mat.ground_horizon_color = Color(0.16, 0.16, 0.22, 1)
	var sky = Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky

	# Fog
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = fog_density
	env.volumetric_fog_albedo = fog_color
	env.volumetric_fog_emission = Color(0.05, 0.05, 0.08, 1)
	env.volumetric_fog_emission_energy = 0.3

	# Ambient light
	env.ambient_light_source = 2
	env.ambient_light_color = Color(0.2, 0.2, 0.3, 1)
	env.ambient_light_energy = 0.5

	# Tonemap
	env.tonemap_mode = 2  # ACES

	# Adjust sun
	var sun = get_node_or_null("../DirectionalLight3D")
	if sun:
		sun.light_energy = sun_energy
		sun.light_color = sun_color

	# Add ambient point lights
	_add_ambient_lights()

	# Add dust particles
	_add_dust_particles()


func _add_ambient_lights() -> void:
	var arena_size = 60.0
	var positions = [
		Vector3(-arena_size, 4, -arena_size),
		Vector3(arena_size, 4, arena_size),
	]

	for pos in positions:
		var light = OmniLight3D.new()
		light.light_color = Color(1.0, 0.85, 0.6, 1)
		light.light_energy = 0.4
		light.omni_range = 60.0
		light.omni_attenuation = 1.5
		light.position = pos
		get_parent().add_child(light)


func _add_dust_particles() -> void:
	var particles = GPUParticles3D.new()
	particles.name = "DustParticles"
	particles.amount = 200
	particles.lifetime = 5.0
	particles.explosiveness = 0.0
	particles.randomness = 1.0

	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = 1  # BOX
	mat.emission_box_extents = Vector3(60, 5, 60)
	mat.direction = Vector3(0, 0.1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.1
	mat.initial_velocity_max = 0.3
	mat.gravity = Vector3(0, -0.02, 0)
	mat.scale_min = 0.05
	mat.scale_max = 0.15
	particles.process_material = mat

	# Tiny white mesh for each particle
	var draw_mesh = BoxMesh.new()
	draw_mesh.size = Vector3(0.1, 0.1, 0.1)
	var draw_mat = StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.albedo_color = Color(0.8, 0.8, 0.8, 0.15)
	draw_mat.no_depth_test = true
	draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	draw_mesh.material = draw_mat
	particles.draw_pass_1 = draw_mesh

	particles.position.y = 3.0
	get_parent().add_child(particles)
