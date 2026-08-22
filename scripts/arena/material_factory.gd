class_name MaterialFactory
extends RefCounted

## MaterialFactory: Centralized PBR Material manager for combat maps, ground surfaces,
## structures, cover objects, and obstacles.

static var _mat_cache: Dictionary = {}

## Returns a PBR StandardMaterial3D tailored to the biome theme ground.
static func get_ground_material(theme: int, base_texture: Texture2D = null) -> StandardMaterial3D:
	var key = "ground_%d" % theme
	if _mat_cache.has(key):
		var cached: StandardMaterial3D = _mat_cache[key]
		if base_texture != null:
			cached.albedo_texture = base_texture
		return cached

	var mat = StandardMaterial3D.new()
	mat.roughness = 0.85
	mat.metallic = 0.05
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	if base_texture != null:
		mat.albedo_texture = base_texture

	var norm_path := ""
	var rough_path := ""

	match theme:
		0: # DESERT
			norm_path = "res://resources/textures/sand/normal.jpg"
			rough_path = "res://resources/textures/sand/roughness.jpg"
		1: # CITY_HIGHRISE
			norm_path = "res://resources/textures/road/normal.jpg"
			rough_path = "res://resources/textures/road/roughness.jpg"
		2: # CROSSROADS
			norm_path = "res://resources/textures/road/normal.jpg"
			rough_path = "res://resources/textures/road/roughness.jpg"
		3: # RIVER_BRIDGE
			norm_path = "res://resources/textures/bridge/normal.jpg"
			rough_path = "res://resources/textures/bridge/roughness.jpg"
		4, 5: # FOREST, FOREST_ROAD
			norm_path = "res://resources/textures/forest/normal.jpg"
			rough_path = "res://resources/textures/forest/roughness.jpg"
		_:
			norm_path = "res://resources/textures/plain/normal.jpg"
			rough_path = "res://resources/textures/plain/roughness.jpg"

	if ResourceLoader.exists(norm_path):
		var ntex: Texture2D = load(norm_path)
		if ntex:
			mat.normal_enabled = true
			mat.normal_texture = ntex
			mat.normal_scale = 0.75

	if ResourceLoader.exists(rough_path):
		var rtex: Texture2D = load(rough_path)
		if rtex:
			mat.roughness_texture = rtex

	_mat_cache[key] = mat
	return mat


## Returns a PBR StandardMaterial3D for cover objects (barriers, containers, rocks, trees, barrels).
static func get_cover_material(cover_type: String) -> StandardMaterial3D:
	if _mat_cache.has("cover_" + cover_type):
		return _mat_cache["cover_" + cover_type]

	var mat = StandardMaterial3D.new()

	match cover_type:
		"barrier", "fortress_wall": # Concrete barrier / wall
			mat.albedo_color = Color(0.48, 0.50, 0.52)
			mat.roughness = 0.8
			var path := "res://resources/textures/cracked_concrete_02_diff_4k.jpg"
			var norm_path := "res://resources/textures/road/normal.jpg"
			if ResourceLoader.exists(path):
				mat.albedo_texture = load(path)
				mat.uv1_scale = Vector3(4, 2, 4)
			if ResourceLoader.exists(norm_path):
				mat.normal_enabled = true
				mat.normal_texture = load(norm_path)
				mat.normal_scale = 0.8

		"container": # Corrugated Metal Cargo Container
			mat.albedo_color = Color(0.22, 0.35, 0.52)
			mat.metallic = 0.65
			mat.roughness = 0.35
			var norm_path := "res://resources/textures/road/normal.jpg"
			if ResourceLoader.exists(norm_path):
				mat.normal_enabled = true
				mat.normal_texture = load(norm_path)
				mat.normal_scale = 0.5

		"pillar": # Industrial Steel Pillar
			mat.albedo_color = Color(0.32, 0.35, 0.40)
			mat.metallic = 0.75
			mat.roughness = 0.3
			var path := "res://resources/textures/rock/normal.jpg"
			if ResourceLoader.exists(path):
				mat.normal_enabled = true
				mat.normal_texture = load(path)
				mat.normal_scale = 0.6

		"small_crate": # Wooden Crate Stack
			mat.albedo_color = Color(0.58, 0.42, 0.26)
			mat.roughness = 0.85
			var path := "res://resources/textures/forest/albedo.jpg"
			if ResourceLoader.exists(path):
				mat.albedo_texture = load(path)
				mat.uv1_scale = Vector3(2, 2, 2)

		"explosive_barrel": # Hazard Red Explosive Barrel
			mat.albedo_color = Color(0.92, 0.20, 0.12)
			mat.metallic = 0.4
			mat.roughness = 0.35
			mat.emission_enabled = true
			mat.emission = Color(0.85, 0.15, 0.05)
			mat.emission_energy_multiplier = 1.8

		"tree_trunk", "fallen_log": # Wood Bark
			mat.albedo_color = Color(0.35, 0.22, 0.12)
			mat.roughness = 0.9
			var path := "res://resources/textures/forest/albedo.jpg"
			var norm_path := "res://resources/textures/forest/normal.jpg"
			if ResourceLoader.exists(path):
				mat.albedo_texture = load(path)
				mat.uv1_scale = Vector3(2, 6, 2)
			if ResourceLoader.exists(norm_path):
				mat.normal_enabled = true
				mat.normal_texture = load(norm_path)
				mat.normal_scale = 0.8

		"fern": # Foliage Bush
			mat.albedo_color = Color(0.18, 0.44, 0.18)
			mat.roughness = 0.75

		_: # Default Rock / Generic
			mat.albedo_color = Color(0.45, 0.45, 0.45)
			mat.roughness = 0.85
			var norm_path := "res://resources/textures/rock/normal.jpg"
			if ResourceLoader.exists(norm_path):
				mat.normal_enabled = true
				mat.normal_texture = load(norm_path)
				mat.normal_scale = 0.8

	_mat_cache["cover_" + cover_type] = mat
	return mat
