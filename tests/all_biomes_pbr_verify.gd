extends SceneTree

func _init() -> void:
	print("--- Running All Biomes PBR Verification ---")
	var ArenaGenClass = preload("res://scripts/arena/arena_generator.gd")
	var MaterialFactoryClass = preload("res://scripts/arena/material_factory.gd")

	var themes = [
		{"id": ArenaGenClass.BiomeTheme.DESERT, "name": "Desert"},
		{"id": ArenaGenClass.BiomeTheme.CITY_HIGHRISE, "name": "City Highrise"},
		{"id": ArenaGenClass.BiomeTheme.CROSSROADS, "name": "Crossroads"},
		{"id": ArenaGenClass.BiomeTheme.RIVER_BRIDGE, "name": "River Bridge"},
		{"id": ArenaGenClass.BiomeTheme.FOREST, "name": "Forest"},
		{"id": ArenaGenClass.BiomeTheme.FOREST_ROAD, "name": "Forest Road"}
	]

	var checks := 0
	var fails := 0

	for t in themes:
		var theme_id: int = t["id"]
		var theme_name: String = t["name"]

		var dummy_tex := ImageTexture.create_from_image(Image.create(16, 16, false, Image.FORMAT_RGB8))
		var mat: StandardMaterial3D = MaterialFactoryClass.get_ground_material(theme_id, dummy_tex)
		if mat == null:
			printerr("PBR_FAIL: Material is null for ", theme_name)
			fails += 1
			continue
		checks += 1
		print("PBR_OK: [%s] Material created successfully" % theme_name)

		if theme_id != 0: # Desert uses comfy tileable or 3D GLB model
			if mat.detail_enabled and mat.detail_albedo != null:
				checks += 1
				print("PBR_OK: [%s] Detail PBR Albedo enabled (%s)" % [theme_name, mat.detail_albedo.resource_path.get_file()])
			else:
				printerr("PBR_FAIL: [%s] Detail albedo missing!" % theme_name)
				fails += 1

			if mat.detail_normal != null:
				checks += 1
				print("PBR_OK: [%s] Detail PBR Normal enabled (%s)" % [theme_name, mat.detail_normal.resource_path.get_file()])
			else:
				printerr("PBR_FAIL: [%s] Detail normal missing!" % theme_name)
				fails += 1

			if mat.ao_enabled and mat.ao_texture != null:
				checks += 1
				print("PBR_OK: [%s] Ambient Occlusion enabled (%s)" % [theme_name, mat.ao_texture.resource_path.get_file()])
			else:
				printerr("PBR_FAIL: [%s] AO texture missing!" % theme_name)
				fails += 1

	print("--- All Biomes PBR Verification Finished ---")
	if fails == 0:
		print("ALL_BIOMES_PBR_OK: %d checks passed with 0 failures!" % checks)
	else:
		printerr("ALL_BIOMES_PBR_FAIL: %d failures out of %d checks" % [fails, checks])

	quit()
