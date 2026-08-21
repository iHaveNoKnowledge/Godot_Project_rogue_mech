extends Node

const EffectFactory = preload("res://scripts/effects/effect_factory.gd")

## Verifies all new VFX and Atmospheric lighting systems:
## 1. Fire Bursts with dynamic lighting
## 2. Billowing Smoke Plumes
## 3. Ground Scorch & Burning Ground Patches
## 4. Damaged Mech Smoke Emitters
## 5. Atmosphere Manager Volumetric Fog, God Rays, and Fog Volumes

var _checks := 0
var _fails := 0

func _check(cond: bool, test_name: String) -> void:
	_checks += 1
	if cond:
		print("VFX_TEST OK: " + test_name)
	else:
		_fails += 1
		printerr("VFX_TEST FAIL: " + test_name)


func _ready() -> void:
	print("--- 1. Testing EffectFactory Fire, Smoke, and Scorch Systems ---")
	var root_node := Node3D.new()
	add_child(root_node)

	# 1. Fire Burst
	var pre_child_count := root_node.get_child_count()
	EffectFactory.spawn_fire_burst(get_tree(), Vector3(0, 1, 0), 0.8, 0.5, 6.0, root_node)
	var post_fire_count := root_node.get_child_count()
	_check(post_fire_count > pre_child_count, "Fire burst spawned visual and light nodes")

	var has_light := false
	for child in root_node.get_children():
		if child is OmniLight3D:
			has_light = true
			break
	_check(has_light, "Fire burst spawned dynamic illumination light")

	# 2. Smoke Plume
	var pre_smoke_count := root_node.get_child_count()
	EffectFactory.spawn_smoke_plume(get_tree(), Vector3(2, 0, 0), 5, 0.3, 0.6, 0.8, Color(0.2, 0.2, 0.2, 0.8), root_node)
	var post_smoke_count := root_node.get_child_count()
	_check(post_smoke_count > pre_smoke_count, "Smoke plume spawned billboard/mesh smoke particles")

	# 3. Burning Ground Scorch
	var pre_scorch_count := root_node.get_child_count()
	EffectFactory.spawn_burning_ground(get_tree(), Vector3(0, 0, 2), 1.5, 2.0, root_node)
	var post_scorch_count := root_node.get_child_count()
	_check(post_scorch_count > pre_scorch_count, "Burning ground scorch mark and fire patch spawned")

	# 4. Damaged Smoke Emitter
	var limb_node := Node3D.new()
	limb_node.name = "ArmLeft"
	root_node.add_child(limb_node)
	var emitter = EffectFactory.spawn_damaged_smoke_emitter(limb_node, Vector3.ZERO)
	_check(emitter != null, "Damaged smoke emitter created successfully")
	_check(limb_node.get_node_or_null("DamagedSmokeEmitter") != null, "Damaged smoke emitter attached to limb node")

	# Ensure idempotent attaching (no duplicate emitters on the same limb)
	var emitter2 = EffectFactory.spawn_damaged_smoke_emitter(limb_node, Vector3.ZERO)
	_check(emitter == emitter2, "Re-attaching smoke emitter returns existing instance without duplicating")

	print("--- 2. Testing AtmosphereManager Volumetric Fog & Fog Volumes ---")
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	world_env.environment = env
	root_node.add_child(world_env)

	var dir_light := DirectionalLight3D.new()
	dir_light.name = "DirectionalLight3D"
	root_node.add_child(dir_light)

	var atmos_script = load("res://scripts/arena/atmosphere_manager.gd")
	var atmos = Node.new()
	atmos.set_script(atmos_script)
	root_node.add_child(atmos)

	atmos._setup_atmosphere()

	_check(env.volumetric_fog_enabled == true, "Volumetric Fog is enabled in environment")
	_check(env.volumetric_fog_anisotropy > 0.0, "Volumetric Fog forward scattering (anisotropy) configured for God Rays")
	_check(env.glow_enabled == true, "HDR Bloom / Glow is enabled for vibrant visual effects")
	_check(dir_light.light_volumetric_fog_energy > 1.0, "Directional Light configured for high volumetric fog energy (God Rays)")

	var has_fog_volume := false
	for child in root_node.get_children():
		if child is FogVolume or child.name.contains("FogBank"):
			has_fog_volume = true
			break
	_check(has_fog_volume, "Localized FogVolumes spawned for battlefield atmosphere")

	print("\n==================================================")
	print("VFX_ATMOSPHERE_VERIFY COMPLETED:")
	print("Checks: %d | Fails: %d" % [_checks, _fails])
	print("==================================================")

	if _fails == 0:
		print("ALL VFX AND ATMOSPHERE TESTS PASSED!")
	else:
		printerr("SOME VFX TESTS FAILED!")

	await get_tree().create_timer(0.1).timeout
	get_tree().quit(0 if _fails == 0 else 1)
