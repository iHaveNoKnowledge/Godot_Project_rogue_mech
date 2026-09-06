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
		if base_texture != null and theme != 0:
			cached.albedo_texture = base_texture
		# DESERT keeps ComfyUI albedo (see creation branch), ignore procedural base_texture.
		if theme == 0:
			var comfy_path := "res://resources/textures/sand/comfy_desert_albedo.png"
			if ResourceLoader.exists(comfy_path):
				cached.albedo_texture = load(comfy_path)
		return cached

	var mat = StandardMaterial3D.new()
	mat.roughness = 0.85
	mat.metallic = 0.05
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	if base_texture != null and theme != 0:
		mat.albedo_texture = base_texture

	var norm_path := ""
	var rough_path := ""

	match theme:
		0: # DESERT — Dry, diffuse golden sand with high roughness and zero mirror reflections (matte, powdery)
			mat.roughness = 0.96
			mat.metallic = 0.0
			mat.metallic_specular = 0.35
			mat.albedo_color = Color(0.97, 0.92, 0.84)
			# ComfyUI-generated tileable sand albedo (Z-Image-Turbo). Falls back
			# to procedural base_texture when the file is missing.
			var comfy_albedo := "res://resources/textures/sand/comfy_desert_albedo.png"
			if ResourceLoader.exists(comfy_albedo):
				mat.albedo_texture = load(comfy_albedo)
				mat.uv1_scale = Vector3(24, 24, 24)
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			norm_path = "res://resources/textures/sand/normal.jpg"
			rough_path = "" # Do not use dark glossy roughness map on sand
		1: # CITY_HIGHRISE — weathered concrete, not glossy road
			mat.roughness = 0.88
			mat.metallic = 0.02
			mat.metallic_specular = 0.35
			norm_path = "res://resources/textures/road/normal.jpg"
			rough_path = "res://resources/textures/road/roughness.jpg"
		2: # CROSSROADS — same weathered asphalt
			mat.roughness = 0.90
			mat.metallic = 0.02
			mat.metallic_specular = 0.35
			norm_path = "res://resources/textures/road/normal.jpg"
			rough_path = "res://resources/textures/road/roughness.jpg"
		3: # RIVER_BRIDGE — damp concrete but still matte
			mat.roughness = 0.86
			mat.metallic = 0.02
			mat.metallic_specular = 0.35
			norm_path = "res://resources/textures/bridge/normal.jpg"
			rough_path = "res://resources/textures/bridge/roughness.jpg"
		4, 5: # FOREST, FOREST_ROAD — mossy humus, very matte
			mat.roughness = 0.94
			mat.metallic = 0.0
			mat.metallic_specular = 0.35
			norm_path = "res://resources/textures/forest/normal.jpg"
			rough_path = "res://resources/textures/forest/roughness.jpg"
		_:
			mat.roughness = 0.90
			mat.metallic = 0.02
			mat.metallic_specular = 0.35
			norm_path = "res://resources/textures/plain/normal.jpg"
			rough_path = "res://resources/textures/plain/roughness.jpg"

	if norm_path != "" and ResourceLoader.exists(norm_path):
		var ntex: Texture2D = load(norm_path)
		if ntex:
			mat.normal_enabled = true
			mat.normal_texture = ntex
			mat.normal_scale = 1.0

	if rough_path != "" and ResourceLoader.exists(rough_path):
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
		"barrier", "fortress_wall": # Concrete barrier / wall - weathered, matte, not plastic
			mat.albedo_color = Color(0.42, 0.44, 0.45)
			mat.metallic = 0.02
			mat.metallic_specular = 0.35
			mat.roughness = 0.88
			var path := "res://resources/textures/cracked_concrete_02_diff_4k.jpg"
			var norm_path := "res://resources/textures/road/normal.jpg"
			if ResourceLoader.exists(path):
				mat.albedo_texture = load(path)
				mat.uv1_scale = Vector3(4, 2, 4)
			if ResourceLoader.exists(norm_path):
				mat.normal_enabled = true
				mat.normal_texture = load(norm_path)
				mat.normal_scale = 1.2

		"container": # Corrugated Metal Cargo Container - painted, matte, dusty
			mat.albedo_color = Color(0.26, 0.36, 0.48)
			mat.metallic = 0.12
			mat.metallic_specular = 0.35
			mat.roughness = 0.68
			var norm_path := "res://resources/textures/road/normal.jpg"
			if ResourceLoader.exists(norm_path):
				mat.normal_enabled = true
				mat.normal_texture = load(norm_path)
				mat.normal_scale = 0.85

		"pillar": # Industrial Steel Pillar - brushed, not chrome
			mat.albedo_color = Color(0.34, 0.36, 0.40)
			mat.metallic = 0.32
			mat.metallic_specular = 0.35
			mat.roughness = 0.58
			var path := "res://resources/textures/rock/normal.jpg"
			if ResourceLoader.exists(path):
				mat.normal_enabled = true
				mat.normal_texture = load(path)
				mat.normal_scale = 1.0

		"small_crate": # Wooden Crate Stack - rough wood
			mat.albedo_color = Color(0.52, 0.38, 0.24)
			mat.metallic = 0.0
			mat.roughness = 0.92
			var path := "res://resources/textures/forest/albedo.jpg"
			if ResourceLoader.exists(path):
				mat.albedo_texture = load(path)
				mat.uv1_scale = Vector3(2, 2, 2)

		"explosive_barrel": # Hazard Red Explosive Barrel - painted, not emissive plastic
			mat.albedo_color = Color(0.78, 0.22, 0.14)
			mat.metallic = 0.06
			mat.roughness = 0.72
			mat.emission_enabled = false

		"tree_trunk", "fallen_log": # Wood Bark - very matte
			mat.albedo_color = Color(0.32, 0.20, 0.10)
			mat.metallic = 0.0
			mat.roughness = 0.94
			var path := "res://resources/textures/forest/albedo.jpg"
			var norm_path := "res://resources/textures/forest/normal.jpg"
			if ResourceLoader.exists(path):
				mat.albedo_texture = load(path)
				mat.uv1_scale = Vector3(2, 6, 2)
			if ResourceLoader.exists(norm_path):
				mat.normal_enabled = true
				mat.normal_texture = load(norm_path)
				mat.normal_scale = 1.2

		"fern": # Foliage Bush - matte leaves
			mat.albedo_color = Color(0.16, 0.38, 0.16)
			mat.metallic = 0.0
			mat.roughness = 0.88

		_: # Default Rock / Generic - matte stone
			mat.albedo_color = Color(0.40, 0.42, 0.44)
			mat.metallic = 0.02
			mat.roughness = 0.92
			var norm_path := "res://resources/textures/rock/normal.jpg"
			if ResourceLoader.exists(norm_path):
				mat.normal_enabled = true
				mat.normal_texture = load(norm_path)
				mat.normal_scale = 1.2

	_mat_cache["cover_" + cover_type] = mat
	return mat
