extends Node3D

## ---------------------------------------------------------------------------
## WEATHER PARTICLE EFFECTS — visual particles on the 3D board.
##
## Spawns and manages rain drops, sand particles, and fog wisps that
## correspond to the current weather state from WeatherTransitionSystem.
## Particles are GPU-accelerated and follow the camera for optimal coverage.
## ---------------------------------------------------------------------------

# --- Particle configs ---
const RAIN_COUNT := 600
const RAIN_LIFETIME := 1.8
const RAIN_EXTENT := Vector3(90, 30, 90)

const SAND_COUNT := 500
const SAND_LIFETIME := 4.0
const SAND_EXTENT := Vector3(100, 15, 100)

const FOG_COUNT := 200
const FOG_LIFETIME := 8.0
const FOG_EXTENT := Vector3(120, 8, 120)

const DUST_COUNT := 300
const DUST_LIFETIME := 3.5
const DUST_EXTENT := Vector3(80, 20, 80)

# --- Internal state ---
var _rain_particles: GPUParticles3D = null
var _sand_particles: GPUParticles3D = null
var _fog_particles: GPUParticles3D = null
var _dust_particles: GPUParticles3D = null

var _current_weather: String = ""
var _transition_progress: float = 0.0


func _ready() -> void:
	# Create all particle emitters (start hidden, show when weather activates)
	_rain_particles = _create_rain_particles()
	_sand_particles = _create_sand_particles()
	_fog_particles = _create_fog_particles()
	_dust_particles = _create_dust_particles()

	add_child(_rain_particles)
	add_child(_sand_particles)
	add_child(_fog_particles)
	add_child(_dust_particles)

	# All start invisible
	_rain_particles.emitting = false
	_sand_particles.emitting = false
	_fog_particles.emitting = false
	_dust_particles.emitting = false


func _process(_delta: float) -> void:
	if GlobalData.weather_transition == null:
		return

	var new_weather: String = GlobalData.weather_transition.current_weather
	var new_progress: float = GlobalData.weather_transition.transition_progress

	# Update visibility based on weather state
	_update_particle_visibility(new_weather, new_progress)

	_current_weather = new_weather
	_transition_progress = new_progress

	# Keep particles centered on camera for seamless coverage
	_follow_camera()


func _update_particle_visibility(weather: String, progress: float) -> void:
	# Rain particles
	var show_rain: bool = (weather == "rain" and progress > 0.05)
	_rain_particles.emitting = show_rain
	if show_rain:
		_rain_particles.amount_ratio = progress
		_set_rain_color(weather)

	# Sand particles
	var show_sand: bool = (weather == "sandstorm" and progress > 0.05)
	_sand_particles.emitting = show_sand
	if show_sand:
		_sand_particles.amount_ratio = progress

	# Fog wisps
	var show_fog: bool = (weather == "fog" and progress > 0.05)
	_fog_particles.emitting = show_fog
	if show_fog:
		_fog_particles.amount_ratio = progress

	# Dust particles (dust_storm)
	var show_dust: bool = (weather == "dust_storm" and progress > 0.05)
	_dust_particles.emitting = show_dust
	if show_dust:
		_dust_particles.amount_ratio = progress


func _set_rain_color(_weather: String) -> void:
	# Rain color is always blue-white (set in creation)
	pass


func _follow_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	# Center particle emitters around the camera position (XZ only)
	var cam_pos: Vector3 = camera.global_position
	global_position = Vector3(cam_pos.x, 0.0, cam_pos.z)


# ===========================================================================
# PARTICLE CREATION
# ===========================================================================

func _create_rain_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "RainParticles"
	p.amount = RAIN_COUNT
	p.lifetime = RAIN_LIFETIME
	p.explosiveness = 0.0
	p.randomness = 1.0
	p.fixed_fps = 60

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = RAIN_EXTENT

	# Rain falls down and slightly forward
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 8.0
	mat.initial_velocity_min = 12.0
	mat.initial_velocity_max = 18.0
	mat.gravity = Vector3(0, -15.0, 0)

	# Thin droplet scale
	mat.scale_min = 0.03
	mat.scale_max = 0.08
	mat.scale_over_velocity = 0.0

	# Blue-white rain drops
	mat.color = Color(0.6, 0.75, 0.95, 0.55)
	mat.color_ramp = _create_fade_gradient(Color(0.6, 0.75, 0.95, 0.55), Color(0.6, 0.75, 0.95, 0.0))

	p.process_material = mat

	# Use elongated box mesh for rain streaks
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.35, 0.02)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.albedo_color = Color(0.65, 0.8, 1.0, 0.45)
	mesh_mat.emission_enabled = true
	mesh_mat.emission = Color(0.4, 0.6, 1.0)
	mesh_mat.emission_energy_multiplier = 0.3
	mesh_mat.no_depth_test = true
	mesh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mesh_mat
	p.draw_pass_1 = mesh

	p.amount = RAIN_COUNT
	p.visibility_aabb = AABB(Vector3(-100, -5, -100), Vector3(200, 40, 200))
	p.local_coords = false

	return p


func _create_sand_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "SandParticles"
	p.amount = SAND_COUNT
	p.lifetime = SAND_LIFETIME
	p.explosiveness = 0.0
	p.randomness = 1.0

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = SAND_EXTENT

	# Sand blows horizontally with slight upward turbulence
	mat.direction = Vector3(1, 0.15, 0.3)
	mat.spread = 40.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 7.0
	mat.gravity = Vector3(0, -0.5, 0)

	# Turbulent orbital motion for swirling sand
	mat.orbit_velocity_min = 0.2
	mat.orbit_velocity_max = 0.8

	# Amber/golden sand particles
	mat.scale_min = 0.04
	mat.scale_max = 0.15
	mat.color = Color(0.9, 0.75, 0.4, 0.5)
	mat.color_ramp = _create_fade_gradient(Color(0.9, 0.75, 0.4, 0.5), Color(0.85, 0.65, 0.3, 0.0))

	p.process_material = mat

	# Small rough particle mesh
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, 0.08)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.albedo_color = Color(0.9, 0.75, 0.4, 0.6)
	mesh_mat.roughness = 1.0
	mesh_mat.no_depth_test = true
	mesh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mesh_mat
	p.draw_pass_1 = mesh

	p.amount = SAND_COUNT
	p.visibility_aabb = AABB(Vector3(-120, -5, -120), Vector3(240, 25, 240))
	p.local_coords = false

	return p


func _create_fog_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "FogParticles"
	p.amount = FOG_COUNT
	p.lifetime = FOG_LIFETIME
	p.explosiveness = 0.0
	p.randomness = 1.0

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = FOG_EXTENT

	# Fog drifts slowly with no dominant direction
	mat.direction = Vector3(0.3, 0, 0.1)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.1
	mat.initial_velocity_max = 0.4
	mat.gravity = Vector3(0, 0.005, 0)  # Very slight upward drift

	# Large, slow-fading translucent wisps
	mat.scale_min = 1.5
	mat.scale_max = 4.0

	# Translucent white/grey fog
	mat.color = Color(0.8, 0.85, 0.9, 0.12)
	mat.color_ramp = _create_fade_gradient(Color(0.8, 0.85, 0.9, 0.12), Color(0.75, 0.8, 0.85, 0.0))

	p.process_material = mat

	# Use a flat billboard quad for fog wisps
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(3.0, 3.0)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.albedo_color = Color(0.8, 0.85, 0.9, 0.08)
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.no_depth_test = true
	mesh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh_mat.billboard_keep_scale = true
	mesh.material = mesh_mat
	p.draw_pass_1 = mesh

	p.amount = FOG_COUNT
	p.visibility_aabb = AABB(Vector3(-140, -5, -140), Vector3(280, 15, 280))
	p.local_coords = false

	return p


func _create_dust_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "DustParticles"
	p.amount = DUST_COUNT
	p.lifetime = DUST_LIFETIME
	p.explosiveness = 0.0
	p.randomness = 1.0

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = DUST_EXTENT

	# Dust swirls upward with turbulence
	mat.direction = Vector3(0.5, 0.4, 0.2)
	mat.spread = 60.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0, -0.3, 0)

	mat.orbit_velocity_min = 0.1
	mat.orbit_velocity_max = 0.5

	# Brownish dust
	mat.scale_min = 0.06
	mat.scale_max = 0.2
	mat.color = Color(0.7, 0.6, 0.4, 0.35)
	mat.color_ramp = _create_fade_gradient(Color(0.7, 0.6, 0.4, 0.35), Color(0.65, 0.55, 0.35, 0.0))

	p.process_material = mat

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.1, 0.1, 0.1)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.albedo_color = Color(0.7, 0.6, 0.4, 0.4)
	mesh_mat.no_depth_test = true
	mesh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mesh_mat
	p.draw_pass_1 = mesh

	p.amount = DUST_COUNT
	p.visibility_aabb = AABB(Vector3(-100, -5, -100), Vector3(200, 30, 200))
	p.local_coords = false

	return p


# ===========================================================================
# HELPERS
# ===========================================================================

## Creates a GradientTexture1D for particle color fade-in/out.
func _create_fade_gradient(start_color: Color, end_color: Color) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.set_color(0, start_color)
	grad.set_color(1, end_color)
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex


## Returns true if any weather particles are currently visible.
func has_active_weather() -> bool:
	return _current_weather != "" and _transition_progress > 0.05


## Returns the current weather particle type for debugging.
func get_active_weather_type() -> String:
	return _current_weather
