extends RefCounted
class_name WarBiomeGenerator

## War Biome 2000x2000 — 3-Tier Multi-Elevation Terrain & Tactical Biome Cover
## Tier 0: Low Ground Canyons & Riverbeds (Y = -10m to -14m)
## Tier 1: Mid Ground Plains & Bases (Y = 0m +/- 1.5m)
## Tier 2: High Ground Mesas & Plateaus (Y = +18m to +24m)
## Connected via strategic ramps (12-15 deg) for vehicles, while mechas can booster-jump.
## 16 Chunked HeightMapShape3D collision + seamless displaced terrain mesh.

enum Biome { DESERT, CITY_RUINS, FOREST, RIVER_VALLEY }

const MAP_SIZE := 2000.0
const HALF := 1000.0

static var _noise: FastNoiseLite = null
static var _seed: int = 0
static var _zone_centers: Array = []
static var _zone_biomes: Array = []


static func _ensure_noise(p_seed: int) -> void:
	if _noise != null and _seed == p_seed:
		return
	_seed = p_seed
	_noise = FastNoiseLite.new()
	_noise.seed = p_seed
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 0.005
	_noise.fractal_octaves = 3

	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	_zone_centers.clear()
	_zone_biomes.clear()
	var pts := [
		Vector2(-500, -500), # Southwest - Desert
		Vector2(500, -500),  # Southeast - Forest
		Vector2(-500, 500),  # Northwest - City Ruins
		Vector2(500, 500),   # Northeast - River Valley
		Vector2(0, 0),       # Center - Crossroads
	]
	for i in range(pts.size()):
		pts[i] += Vector2(rng.randf_range(-80, 80), rng.randf_range(-80, 80))
	_zone_centers = pts

	# Assign distinct biomes to the zones
	_zone_biomes = [
		Biome.DESERT,
		Biome.FOREST,
		Biome.CITY_RUINS,
		Biome.RIVER_VALLEY,
		Biome.FOREST
	]


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ab_len_sq := ab.length_squared()
	if ab_len_sq < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	var proj := a + ab * t
	return p.distance_to(proj)


static func _dist_to_river(wx: float, wz: float) -> float:
	var p := Vector2(wx, wz)
	var d1 := _dist_to_segment(p, Vector2(140.0, -750.0), Vector2(210.0, -250.0))
	var d2 := _dist_to_segment(p, Vector2(210.0, -250.0), Vector2(180.0, 200.0))
	var d3 := _dist_to_segment(p, Vector2(180.0, 200.0), Vector2(250.0, 750.0))
	return minf(d1, minf(d2, d3))


## Unified 3-Tier Multi-Elevation Height Function
static func get_ground_height(wx: float, wz: float) -> float:
	if _noise == null:
		_ensure_noise(int(GlobalData.board.board_seed) if (GlobalData and GlobalData.board) else 1337)

	# 1. Base rolling terrain noise (gentle variations +/- 1.6m)
	var h: float = _noise.get_noise_2d(wx * 0.8, wz * 0.8) * 1.6

	# 2. High Ground Mesas & Ramps (Tier 2, Y = +20m to +24m)
	# Mesa 1 (West Desert/City, center -450, -100, radius 130m, height +22m, ramp east)
	var m1_center := Vector2(-450.0, -100.0)
	var m1_dist := Vector2(wx, wz).distance_to(m1_center)
	if m1_dist < 180.0:
		var in_ramp1 := (wx >= -390.0 and wx <= -310.0 and absf(wz - (-100.0)) < 35.0)
		if in_ramp1:
			var t := clampf((-310.0 - wx) / 80.0, 0.0, 1.0)
			h += t * 22.0
		elif m1_dist <= 130.0:
			h += 22.0
		elif m1_dist < 160.0:
			var t := clampf((160.0 - m1_dist) / 30.0, 0.0, 1.0)
			h += t * 22.0

	# Mesa 2 (East Forest/River Highland, center 520, -250, radius 120m, height +20m, ramp west)
	var m2_center := Vector2(520.0, -250.0)
	var m2_dist := Vector2(wx, wz).distance_to(m2_center)
	if m2_dist < 170.0:
		var in_ramp2 := (wx >= 390.0 and wx <= 470.0 and absf(wz - (-250.0)) < 35.0)
		if in_ramp2:
			var t := clampf((wx - 390.0) / 80.0, 0.0, 1.0)
			h += t * 20.0
		elif m2_dist <= 120.0:
			h += 20.0
		elif m2_dist < 150.0:
			var t := clampf((150.0 - m2_dist) / 30.0, 0.0, 1.0)
			h += t * 20.0

	# Mesa 3 (North-West City High Plaza, center -420, 420, radius 125m, height +22m, ramp south)
	var m3_center := Vector2(-420.0, 420.0)
	var m3_dist := Vector2(wx, wz).distance_to(m3_center)
	if m3_dist < 175.0:
		var in_ramp3 := (wz >= 280.0 and wz <= 360.0 and absf(wx - (-420.0)) < 35.0)
		if in_ramp3:
			var t := clampf((wz - 280.0) / 80.0, 0.0, 1.0)
			h += t * 22.0
		elif m3_dist <= 125.0:
			h += 22.0
		elif m3_dist < 155.0:
			var t := clampf((155.0 - m3_dist) / 30.0, 0.0, 1.0)
			h += t * 22.0

	# Mesa 4 (North-East River Bluff, center 480, 380, radius 120m, height +24m, ramp west)
	var m4_center := Vector2(480.0, 380.0)
	var m4_dist := Vector2(wx, wz).distance_to(m4_center)
	if m4_dist < 170.0:
		var in_ramp4 := (wx >= 350.0 and wx <= 430.0 and absf(wz - 380.0) < 35.0)
		if in_ramp4:
			var t := clampf((wx - 350.0) / 80.0, 0.0, 1.0)
			h += t * 24.0
		elif m4_dist <= 120.0:
			h += 24.0
		elif m4_dist < 150.0:
			var t := clampf((150.0 - m4_dist) / 30.0, 0.0, 1.0)
			h += t * 24.0

	# 3. Low Ground: River Canyon & Desert Quarry (Tier 0, Y = -10m to -14m)
	# River Canyon
	var river_d := _dist_to_river(wx, wz)
	if river_d < 65.0:
		# Vehicle ramps descending into canyon at 3 strategic crossings
		var in_canyon_ramp := (absf(wz - (-450.0)) < 40.0 and wx >= 120.0 and wx <= 210.0) or \
							  (absf(wz - 0.0) < 40.0 and wx >= 140.0 and wx <= 230.0) or \
							  (absf(wz - 480.0) < 40.0 and wx >= 160.0 and wx <= 250.0)
		if in_canyon_ramp:
			var ramp_start_x := 120.0 if wz < -200.0 else (140.0 if wz < 240.0 else 160.0)
			var t := clampf((wx - ramp_start_x) / 80.0, 0.0, 1.0)
			h -= t * 12.0
		elif river_d <= 35.0:
			h -= 12.0
		else:
			var t := clampf((65.0 - river_d) / 30.0, 0.0, 1.0)
			h -= t * 12.0

	# Desert Sunken Quarry / Trench (Southwest, around (-400, -520) to (-600, -350))
	var q_d := _dist_to_segment(Vector2(wx, wz), Vector2(-400.0, -520.0), Vector2(-600.0, -350.0))
	if q_d < 60.0:
		var in_q_ramp := (wx >= -370.0 and wx <= -300.0 and absf(wz - (-520.0)) < 35.0)
		if in_q_ramp:
			var t := clampf((-300.0 - wx) / 70.0, 0.0, 1.0)
			h -= t * 10.0
		elif q_d <= 30.0:
			h -= 10.0
		else:
			var t := clampf((60.0 - q_d) / 30.0, 0.0, 1.0)
			h -= t * 10.0

	# 4. Flatten Base Areas (Friendly at (0, -800), Enemy at (0, 800))
	var d_friendly := Vector2(wx, wz).distance_to(Vector2(0, -800.0))
	if d_friendly < 140.0:
		h *= clampf((d_friendly - 40.0) / 100.0, 0.0, 1.0)

	var d_enemy := Vector2(wx, wz).distance_to(Vector2(0, 800.0))
	if d_enemy < 140.0:
		h *= clampf((d_enemy - 40.0) / 100.0, 0.0, 1.0)

	# 5. Map outer boundaries attenuation
	var edge := maxf(absf(wx), absf(wz))
	if edge > 850.0:
		h *= clampf((1000.0 - edge) / 150.0, 0.0, 1.0)

	return h


static func snap_to_ground(pos: Vector3, half_height: float) -> Vector3:
	return Vector3(pos.x, get_ground_height(pos.x, pos.z) + half_height + 0.02, pos.z)


static func biome_at(wx: float, wz: float) -> int:
	if _zone_centers.is_empty():
		_ensure_noise(int(GlobalData.board.board_seed) if (GlobalData and GlobalData.board) else 1337)
	var best := 0
	var best_d := INF
	for i in range(_zone_centers.size()):
		var c: Vector2 = _zone_centers[i]
		var d := Vector2(wx, wz).distance_squared_to(c)
		if d < best_d:
			best_d = d
			best = i
	return int(_zone_biomes[best])


static func biome_color(b: int) -> Color:
	match b:
		Biome.DESERT: return Color(0.76, 0.64, 0.42)
		Biome.CITY_RUINS: return Color(0.38, 0.39, 0.42)
		Biome.FOREST: return Color(0.24, 0.38, 0.18)
		Biome.RIVER_VALLEY: return Color(0.28, 0.44, 0.32)
		_: return Color(0.45, 0.52, 0.32)


## Generates 16 Chunked HeightMapShape3D colliders + continuous displaced visual terrain
static func build_biome_ground(parent: Node3D, p_seed: int = 1337) -> void:
	_ensure_noise(p_seed)

	# 4x4 Chunks covering 2000x2000 (each chunk is 500x500)
	var chunk_step := 10.0 # 10m grid spacing
	var samples := 51      # 50 quads = 500m

	for cx_idx in range(4):
		for cz_idx in range(4):
			var cx: float = -750.0 + float(cx_idx) * 500.0
			var cz: float = -750.0 + float(cz_idx) * 500.0

			var chunk_body := StaticBody3D.new()
			chunk_body.name = "TerrainChunk_%d_%d" % [cx_idx, cz_idx]
			chunk_body.collision_layer = 2
			chunk_body.collision_mask = 1
			chunk_body.position = Vector3(cx, 0, cz)

			# 1. HeightMapShape3D collision
			var height_data := PackedFloat32Array()
			height_data.resize(samples * samples)

			for r in range(samples):
				var wz := cz - 250.0 + float(r) * chunk_step
				for c in range(samples):
					var wx := cx - 250.0 + float(c) * chunk_step
					height_data[r * samples + c] = get_ground_height(wx, wz)

			var shape := HeightMapShape3D.new()
			shape.map_width = samples
			shape.map_depth = samples
			shape.map_data = height_data

			var col := CollisionShape3D.new()
			col.name = "Collision"
			col.shape = shape
			col.scale = Vector3(chunk_step, 1.0, chunk_step)
			chunk_body.add_child(col)

			# 2. SurfaceTool visual mesh with slope-aware shading
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)

			for r in range(samples):
				var wz := cz - 250.0 + float(r) * chunk_step
				for c in range(samples):
					var wx := cx - 250.0 + float(c) * chunk_step
					var gy := height_data[r * samples + c]

					var b: int = biome_at(wx, wz)
					var b_col: Color = biome_color(b)

					# Slope shading: estimate local slope
					var gy_right: float = get_ground_height(wx + 2.0, wz)
					var gy_up: float = get_ground_height(wx, wz + 2.0)
					var slope: float = maxf(absf(gy_right - gy), absf(gy_up - gy))

					var vert_col: Color = b_col
					if slope > 1.2:
						# Steep slope / cliff -> rocky slate
						vert_col = b_col.lerp(Color(0.28, 0.28, 0.30), 0.75)
					elif gy < -6.0:
						# Canyon bed / river mud
						vert_col = b_col.lerp(Color(0.18, 0.22, 0.20), 0.5)
					elif gy > 16.0:
						# High ground plateau sun exposure
						vert_col = b_col.lightened(0.12)

					st.set_color(vert_col)
					st.set_uv(Vector2(float(c) / float(samples - 1) * 8.0, float(r) / float(samples - 1) * 8.0))
					st.add_vertex(Vector3(wx - cx, gy, wz - cz))

			# Add quad indices (counter-clockwise winding so normals point UP)
			for r in range(samples - 1):
				for c in range(samples - 1):
					var i0: int = r * samples + c
					var i1: int = r * samples + (c + 1)
					var i2: int = (r + 1) * samples + c
					var i3: int = (r + 1) * samples + (c + 1)

					st.add_index(i0)
					st.add_index(i1)
					st.add_index(i2)

					st.add_index(i1)
					st.add_index(i3)
					st.add_index(i2)

			st.generate_normals()
			var mesh := st.commit()

			var mi := MeshInstance3D.new()
			mi.name = "TerrainMesh"
			mi.mesh = mesh
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.roughness = 0.85
			mi.material_override = mat
			chunk_body.add_child(mi)

			parent.add_child(chunk_body)


## Populates distinct tactical obstacles & cover across all 4 biomes
static func populate_biome_scatter(parent: Node3D, p_seed: int = 1337) -> void:
	_ensure_noise(p_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed + 101

	# --- 1. Distinct Indestructible Landmark Archetypes ---
	# Desert: Giant crashed starship frame & sandstone arch
	_spawn_crashed_ship_frame(parent, Vector3(-500, 0, -450))
	_spawn_sandstone_arch(parent, Vector3(-380, 0, -320), Vector3(36, 18, 12))

	# City Ruins: Collapsed highway overpass & skyscraper core ruins
	_spawn_collapsed_highway(parent, Vector2(-350, 320), Vector2(-200, 420), 14.0)
	_spawn_skyscraper_core(parent, Vector3(-450, 0, 480), Vector3(18, 28, 18))

	# Forest: Ancient giant redwood stumps & mossy megalith crags
	_spawn_giant_stump(parent, Vector3(450, 0, -450), 5.0, 14.0)
	_spawn_megalith_cluster(parent, Vector3(380, 0, -350))

	# River Valley: Stone bridge across river canyon with massive piers
	spawn_bridge(parent, Vector2(120, 50), Vector2(250, 50), 4.0, 10.0)
	spawn_bridge(parent, Vector2(100, -450), Vector2(240, -450), 4.0, 10.0)

	# --- 2. Distinct Destructible Tactical Cover Props ---
	for qx in [-1, 1]:
		for qz in [-1, 1]:
			var cx: float = qx * 500.0
			var cz: float = qz * 500.0
			var b: int = biome_at(cx, cz)

			match b:
				Biome.DESERT:
					# Sandstone spires (destructible vertical cover)
					_spawn_cover_spires(parent, 20, Vector2(cx, cz), Vector2(360, 360), p_seed + 11)
					# Sandbag parapets / bunker trenches
					_spawn_cover_sandbags(parent, 16, Vector2(cx, cz), Vector2(350, 350), p_seed + 12)
					# Scrap metal barricades
					_spawn_cover_boxes(parent, 14, Vector2(cx, cz), Vector2(340, 340), Vector3(3.0, 2.2, 1.2), Color(0.55, 0.42, 0.28), p_seed + 13, 220.0, "scrap")

				Biome.CITY_RUINS:
					# Concrete blast barriers (Jersey barriers)
					_spawn_cover_boxes(parent, 24, Vector2(cx, cz), Vector2(360, 360), Vector3(4.5, 1.6, 0.8), Color(0.42, 0.42, 0.44), p_seed + 21, 200.0, "barrier")
					# Ruined office walls
					_spawn_cover_boxes(parent, 16, Vector2(cx, cz), Vector2(350, 350), Vector3(6.0, 2.8, 1.0), Color(0.36, 0.36, 0.38), p_seed + 22, 260.0, "wall")
					# Shipping containers
					_spawn_shipping_containers(parent, 12, Vector2(cx, cz), Vector2(350, 350), p_seed + 23)

				Biome.FOREST:
					# Destructible tall trees (cylinder + cone)
					_spawn_cover_trees(parent, 35, Vector2(cx, cz), Vector2(360, 360), p_seed + 31)
					# Fallen giant logs (low crouch cover)
					_spawn_cover_boxes(parent, 15, Vector2(cx, cz), Vector2(350, 350), Vector3(5.5, 1.3, 1.3), Color(0.32, 0.22, 0.14), p_seed + 32, 180.0, "log")
					# Mossy woodland boulders
					_spawn_cover_boxes(parent, 16, Vector2(cx, cz), Vector2(340, 340), Vector3(2.8, 2.2, 2.6), Color(0.28, 0.35, 0.24), p_seed + 33, 250.0, "boulder")

				Biome.RIVER_VALLEY:
					# Riverbed boulders
					_spawn_cover_boxes(parent, 18, Vector2(cx, cz), Vector2(360, 360), Vector3(3.2, 2.0, 3.0), Color(0.36, 0.42, 0.34), p_seed + 41, 220.0, "boulder")
					# Checkpoint sandbags near crossings
					_spawn_cover_sandbags(parent, 14, Vector2(cx, cz), Vector2(350, 350), p_seed + 42)
					# Steel guard barriers
					_spawn_cover_boxes(parent, 12, Vector2(cx, cz), Vector2(340, 340), Vector3(5.0, 1.4, 0.6), Color(0.48, 0.48, 0.50), p_seed + 43, 160.0, "railing")


## --- Landmark Spawners (Indestructible) ---

static func _spawn_crashed_ship_frame(parent: Node3D, pos: Vector3) -> void:
	var root := StaticBody3D.new()
	root.name = "CrashedShipWreckage"
	root.collision_layer = 2
	root.collision_mask = 1
	root.add_to_group("solid_obstacle")
	var gy := get_ground_height(pos.x, pos.z)
	root.position = Vector3(pos.x, gy + 4.0, pos.z)
	root.rotation_degrees = Vector3(12.0, 35.0, -8.0)

	# Main keel hull
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(45.0, 8.0, 12.0)
	col.shape = box
	root.add_child(col)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.22, 0.20)
	mat.metallic = 0.6
	mat.roughness = 0.7
	mi.material_override = mat
	root.add_child(mi)

	# Rib beams
	for x_off in [-15.0, 0.0, 15.0]:
		var rib := MeshInstance3D.new()
		var rbm := BoxMesh.new()
		rbm.size = Vector3(2.5, 14.0, 14.0)
		rib.mesh = rbm
		rib.position = Vector3(x_off, 2.0, 0)
		rib.material_override = mat
		root.add_child(rib)

	parent.add_child(root)


static func _spawn_sandstone_arch(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var root := StaticBody3D.new()
	root.name = "SandstoneArch"
	root.collision_layer = 2
	root.collision_mask = 1
	root.add_to_group("solid_obstacle")
	var gy := get_ground_height(pos.x, pos.z)
	root.position = Vector3(pos.x, gy, pos.z)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.52, 0.35)
	mat.roughness = 0.95

	# Left pillar
	var p1 := CollisionShape3D.new()
	var b1 := BoxShape3D.new()
	b1.size = Vector3(size.z, size.y, size.z)
	p1.shape = b1
	p1.position = Vector3(-size.x * 0.4, size.y * 0.5, 0)
	root.add_child(p1)
	var m1 := MeshInstance3D.new()
	var bm1 := BoxMesh.new()
	bm1.size = b1.size
	m1.mesh = bm1
	m1.position = p1.position
	m1.material_override = mat
	root.add_child(m1)

	# Right pillar
	var p2 := CollisionShape3D.new()
	p2.shape = b1
	p2.position = Vector3(size.x * 0.4, size.y * 0.5, 0)
	root.add_child(p2)
	var m2 := MeshInstance3D.new()
	m2.mesh = bm1
	m2.position = p2.position
	m2.material_override = mat
	root.add_child(m2)

	# Cross arch span
	var span := CollisionShape3D.new()
	var b_span := BoxShape3D.new()
	b_span.size = Vector3(size.x, 3.5, size.z * 1.1)
	span.shape = b_span
	span.position = Vector3(0, size.y, 0)
	root.add_child(span)
	var m_span := MeshInstance3D.new()
	var bm_span := BoxMesh.new()
	bm_span.size = b_span.size
	m_span.mesh = bm_span
	m_span.position = span.position
	m_span.material_override = mat
	root.add_child(m_span)

	parent.add_child(root)


static func _spawn_collapsed_highway(parent: Node3D, start_xz: Vector2, end_xz: Vector2, height: float) -> void:
	var root := Node3D.new()
	root.name = "CollapsedHighway"
	parent.add_child(root)

	var start := Vector3(start_xz.x, 0, start_xz.y)
	var end := Vector3(end_xz.x, 0, end_xz.y)
	var total := start.distance_to(end)
	var dir := (end - start).normalized()
	var segments: int = maxi(1, int(ceil(total / 18.0)))
	var seg_len: float = total / float(segments)

	for i in range(segments):
		var mid := start + dir * (seg_len * (float(i) + 0.5))
		var gy: float = get_ground_height(mid.x, mid.z)
		# Tilted collapse slope
		var deck_y: float = gy + lerpf(height, 0.5, float(i) / float(segments))

		var slab := StaticBody3D.new()
		slab.collision_layer = 2
		slab.collision_mask = 1
		slab.add_to_group("solid_obstacle")
		slab.position = Vector3(mid.x, deck_y, mid.z)
		slab.rotation.y = -atan2(dir.z, dir.x)
		slab.rotation.z = deg_to_rad(4.0)

		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(seg_len + 0.5, 1.2, 10.0)
		col.shape = box
		slab.add_child(col)

		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = box.size
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.32, 0.32, 0.34)
		mat.roughness = 0.8
		mi.material_override = mat
		slab.add_child(mi)

		root.add_child(slab)

		# Giant support pier
		if i % 2 == 0 and deck_y - gy > 2.5:
			var pier := StaticBody3D.new()
			pier.collision_layer = 2
			pier.collision_mask = 1
			pier.add_to_group("solid_obstacle")
			var pier_h: float = deck_y - gy - 0.6
			pier.position = Vector3(mid.x, gy + pier_h * 0.5, mid.z)

			var pcol := CollisionShape3D.new()
			var pbox := BoxShape3D.new()
			pbox.size = Vector3(2.5, pier_h, 2.5)
			pcol.shape = pbox
			pier.add_child(pcol)

			var pmi := MeshInstance3D.new()
			var pbm := BoxMesh.new()
			pbm.size = pbox.size
			pmi.mesh = pbm
			pmi.material_override = mat
			pier.add_child(pmi)

			root.add_child(pier)


static func _spawn_skyscraper_core(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "SkyscraperCore"
	body.collision_layer = 2
	body.collision_mask = 1
	body.add_to_group("solid_obstacle")
	var gy := get_ground_height(pos.x, pos.z)
	body.position = Vector3(pos.x, gy + size.y * 0.5, pos.z)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.26, 0.27, 0.30)
	mat.roughness = 0.9
	mi.material_override = mat
	body.add_child(mi)

	parent.add_child(body)


static func _spawn_giant_stump(parent: Node3D, pos: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.name = "GiantAncientStump"
	body.collision_layer = 2
	body.collision_mask = 1
	body.add_to_group("solid_obstacle")
	var gy := get_ground_height(pos.x, pos.z)
	body.position = Vector3(pos.x, gy + height * 0.5, pos.z)

	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	col.shape = cyl
	body.add_child(col)

	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.9
	cm.bottom_radius = radius * 1.15
	cm.height = height
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.16, 0.10)
	mat.roughness = 0.9
	mi.material_override = mat
	body.add_child(mi)

	parent.add_child(body)


static func _spawn_megalith_cluster(parent: Node3D, pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "MegalithCluster"
	var gy := get_ground_height(pos.x, pos.z)
	root.position = Vector3(pos.x, gy, pos.z)

	for off in [Vector3(0, 0, 0), Vector3(-6, 0, 4), Vector3(5, 0, -5), Vector3(-4, 0, -6)]:
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 1
		body.add_to_group("solid_obstacle")
		body.position = off + Vector3(0, 3.5, 0)
		body.rotation_degrees = Vector3(randf_range(-10, 10), randf_range(0, 360), randf_range(-10, 10))

		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3.5, 7.0, 3.5)
		col.shape = box
		body.add_child(col)

		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = box.size
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.38, 0.32)
		mat.roughness = 0.9
		mi.material_override = mat
		body.add_child(mi)

		root.add_child(body)

	parent.add_child(root)


## --- Destructible Tactical Cover Spawners ---

static func _spawn_cover_boxes(parent: Node3D, count: int, center: Vector2, extents: Vector2, size: Vector3, color: Color, seed_off: int, max_hp: float = 200.0, cover_type: String = "barrier") -> void:
	var CoverObjectScript = load("res://scripts/arena/cover_object.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_off

	for i in range(count):
		var wx: float = rng.randf_range(center.x - extents.x, center.x + extents.x)
		var wz: float = rng.randf_range(center.y - extents.y, center.y + extents.y)
		var gy: float = get_ground_height(wx, wz)
		var s := rng.randf_range(0.88, 1.15)
		var sz := size * s

		var cover = CoverObjectScript.new()
		cover.max_hp = max_hp * s
		cover.current_hp = cover.max_hp
		cover.cover_type = cover_type
		cover.position = Vector3(wx, gy + sz.y * 0.5, wz)
		cover.rotation.y = rng.randf_range(0, TAU)

		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = sz
		col.shape = shape
		cover.add_child(col)

		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = sz
		mi.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.85
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		cover.add_child(mi)

		parent.add_child(cover)


static func _spawn_cover_spires(parent: Node3D, count: int, center: Vector2, extents: Vector2, seed_off: int) -> void:
	var CoverObjectScript = load("res://scripts/arena/cover_object.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_off

	for i in range(count):
		var wx: float = rng.randf_range(center.x - extents.x, center.x + extents.x)
		var wz: float = rng.randf_range(center.y - extents.y, center.y + extents.y)
		var gy: float = get_ground_height(wx, wz)
		var h := rng.randf_range(3.5, 6.0)
		var rad := rng.randf_range(0.8, 1.4)

		var cover = CoverObjectScript.new()
		cover.max_hp = 180.0
		cover.current_hp = cover.max_hp
		cover.cover_type = "sandstone_spire"
		cover.position = Vector3(wx, gy + h * 0.5, wz)

		var col := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = rad
		cyl.height = h
		col.shape = cyl
		cover.add_child(col)

		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = rad * 0.4
		cm.bottom_radius = rad * 1.1
		cm.height = h
		mi.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.68, 0.48, 0.32)
		mat.roughness = 0.95
		mi.material_override = mat
		cover.add_child(mi)

		parent.add_child(cover)


static func _spawn_cover_sandbags(parent: Node3D, count: int, center: Vector2, extents: Vector2, seed_off: int) -> void:
	var CoverObjectScript = load("res://scripts/arena/cover_object.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_off

	for i in range(count):
		var wx: float = rng.randf_range(center.x - extents.x, center.x + extents.x)
		var wz: float = rng.randf_range(center.y - extents.y, center.y + extents.y)
		var gy: float = get_ground_height(wx, wz)

		var cover = CoverObjectScript.new()
		cover.max_hp = 150.0
		cover.current_hp = 150.0
		cover.cover_type = "sandbag"
		cover.position = Vector3(wx, gy + 0.65, wz)
		cover.rotation.y = rng.randf_range(0, TAU)

		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3.8, 1.3, 0.9)
		col.shape = box
		cover.add_child(col)

		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = box.size
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.62, 0.56, 0.42)
		mat.roughness = 0.9
		mi.material_override = mat
		cover.add_child(mi)

		parent.add_child(cover)


static func _spawn_shipping_containers(parent: Node3D, count: int, center: Vector2, extents: Vector2, seed_off: int) -> void:
	var CoverObjectScript = load("res://scripts/arena/cover_object.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_off
	var colors := [Color(0.75, 0.22, 0.18), Color(0.20, 0.42, 0.68), Color(0.35, 0.35, 0.38)]

	for i in range(count):
		var wx: float = rng.randf_range(center.x - extents.x, center.x + extents.x)
		var wz: float = rng.randf_range(center.y - extents.y, center.y + extents.y)
		var gy: float = get_ground_height(wx, wz)

		var cover = CoverObjectScript.new()
		cover.max_hp = 300.0
		cover.current_hp = 300.0
		cover.cover_type = "container"
		cover.position = Vector3(wx, gy + 1.4, wz)
		cover.rotation.y = rng.randf_range(0, TAU)

		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(6.0, 2.8, 2.5)
		col.shape = box
		cover.add_child(col)

		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = box.size
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i % colors.size()]
		mat.roughness = 0.7
		mat.metallic = 0.5
		mi.material_override = mat
		cover.add_child(mi)

		parent.add_child(cover)


static func _spawn_cover_trees(parent: Node3D, count: int, center: Vector2, extents: Vector2, seed_off: int) -> void:
	var CoverObjectScript = load("res://scripts/arena/cover_object.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_off

	for i in range(count):
		var wx: float = rng.randf_range(center.x - extents.x, center.x + extents.x)
		var wz: float = rng.randf_range(center.y - extents.y, center.y + extents.y)
		var gy: float = get_ground_height(wx, wz)
		var trunk_h := rng.randf_range(4.0, 6.5)

		var cover = CoverObjectScript.new()
		cover.max_hp = 140.0
		cover.current_hp = 140.0
		cover.cover_type = "tree"
		cover.position = Vector3(wx, gy, wz)

		# Collision around trunk
		var col := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.65
		cyl.height = trunk_h
		col.shape = cyl
		col.position = Vector3(0, trunk_h * 0.5, 0)
		cover.add_child(col)

		# Trunk visual
		var t_mi := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.45
		tm.bottom_radius = 0.65
		tm.height = trunk_h
		t_mi.mesh = tm
		t_mi.position = col.position
		var t_mat := StandardMaterial3D.new()
		t_mat.albedo_color = Color(0.28, 0.18, 0.12)
		t_mi.material_override = t_mat
		cover.add_child(t_mi)

		# Foliage canopy (tall cone)
		var c_mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1
		cm.bottom_radius = 2.4
		cm.height = trunk_h * 1.2
		c_mi.mesh = cm
		c_mi.position = Vector3(0, trunk_h * 0.9, 0)
		var c_mat := StandardMaterial3D.new()
		c_mat.albedo_color = Color(0.16, 0.32, 0.14)
		c_mi.material_override = c_mat
		cover.add_child(c_mi)

		parent.add_child(cover)


## Existing Helper bridges & grounded methods (kept for backward compatibility)
static func spawn_grounded_box(parent: Node3D, pos_xz: Vector2, size: Vector3, color: Color) -> StaticBody3D:
	var wx: float = pos_xz.x
	var wz: float = pos_xz.y
	var gy: float = get_ground_height(wx, wz)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	body.position = Vector3(wx, gy + size.y * 0.5, wz)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
	return body


static func spawn_bridge(parent: Node3D, start_xz: Vector2, end_xz: Vector2, deck_height: float = 6.0, deck_width: float = 8.0) -> Node3D:
	var root := Node3D.new()
	root.name = "WarBridge"
	parent.add_child(root)
	var start := Vector3(start_xz.x, 0, start_xz.y)
	var end := Vector3(end_xz.x, 0, end_xz.y)
	var total := start.distance_to(end)
	var dir := (end - start).normalized()
	var segments: int = maxi(1, int(ceil(total / 10.0)))
	var seg_len: float = total / float(segments)

	# Calculate bridge baseline across ends
	var y_start := get_ground_height(start_xz.x, start_xz.y) + deck_height
	var y_end := get_ground_height(end_xz.x, end_xz.y) + deck_height

	for i in range(segments):
		var t_seg := (float(i) + 0.5) / float(segments)
		var mid := start + dir * (seg_len * (float(i) + 0.5))
		var deck_y := lerpf(y_start, y_end, t_seg)

		var slab := StaticBody3D.new()
		slab.collision_layer = 2
		slab.collision_mask = 1
		slab.add_to_group("solid_obstacle")
		slab.position = Vector3(mid.x, deck_y, mid.z)
		var ang := atan2(dir.z, dir.x)
		slab.rotation.y = -ang

		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(seg_len + 0.2, 0.8, deck_width)
		col.shape = box
		slab.add_child(col)

		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = box.size
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.36, 0.36, 0.38)
		mi.material_override = mat
		slab.add_child(mi)
		root.add_child(slab)

		# Pillars
		var px: float = mid.x
		var pz: float = mid.z
		var pgy: float = get_ground_height(px, pz)
		var pillar_h: float = deck_y - 0.4 - pgy
		if pillar_h > 1.2:
			var pillar := StaticBody3D.new()
			pillar.collision_layer = 2
			pillar.collision_mask = 1
			pillar.add_to_group("solid_obstacle")
			pillar.position = Vector3(px, pgy + pillar_h * 0.5, pz)

			var pcol := CollisionShape3D.new()
			var pbox := BoxShape3D.new()
			pbox.size = Vector3(2.0, pillar_h, 2.0)
			pcol.shape = pbox
			pillar.add_child(pcol)

			var pmi := MeshInstance3D.new()
			var pbm := BoxMesh.new()
			pbm.size = pbox.size
			pmi.mesh = pbm
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = Color(0.32, 0.32, 0.34)
			pmi.material_override = pmat
			pillar.add_child(pmi)
			root.add_child(pillar)

	return root


static func spawn_highland_mesa(parent: Node3D, center_xz: Vector2, size: Vector3, mesa_height: float = 18.0) -> StaticBody3D:
	var wx: float = center_xz.x
	var wz: float = center_xz.y
	var gy: float = get_ground_height(wx, wz)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	body.add_to_group("solid_obstacle")
	body.position = Vector3(wx, gy + mesa_height * 0.5, wz)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, mesa_height, size.z)
	col.shape = shape
	body.add_child(col)

	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x, mesa_height, size.z)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.48, 0.42)
	mat.roughness = 0.9
	mi.material_override = mat
	body.add_child(mi)

	parent.add_child(body)
	return body


static func spawn_multimesh_scatter(parent: Node3D, mesh: Mesh, count: int, area_center: Vector2, area_extents: Vector2, min_scale: float = 0.8, max_scale: float = 1.4) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = count
	mm.mesh = mesh
	var rng := RandomNumberGenerator.new()
	rng.seed = int(area_center.x * 1000 + area_center.y * 1000) + count

	for i in range(count):
		var wx: float = rng.randf_range(area_center.x - area_extents.x, area_center.x + area_extents.x)
		var wz: float = rng.randf_range(area_center.y - area_extents.y, area_center.y + area_extents.y)
		var gy: float = get_ground_height(wx, wz)
		var s: float = rng.randf_range(min_scale, max_scale)
		var t := Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(wx, gy + s * 0.5, wz))
		t = t.rotated(Vector3.UP, rng.randf_range(0, TAU))
		mm.set_instance_transform(i, t)

	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mat := StandardMaterial3D.new()
	if mesh is BoxMesh:
		mat.albedo_color = Color(0.45, 0.38, 0.30)
	else:
		mat.albedo_color = Color(0.18, 0.32, 0.16)
	mat.roughness = 0.9
	inst.material_override = mat
	parent.add_child(inst)
	return inst


# ---------------------------------------------------------------------------
# DENSE WAR ENVIRONMENT GENERATORS (Outposts, Frontline Ruins, Wrecks, Pipes)
# ---------------------------------------------------------------------------

const _CoverScript = preload("res://scripts/arena/cover_object.gd")

## Spawns a forward military outpost with concrete bunker, watchtower, comms mast, and sandbag perimeter.
static func spawn_military_outpost(parent: Node, center: Vector3, is_friendly: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "MilitaryOutpost_%s_%d_%d" % ["Friendly" if is_friendly else "Enemy", int(center.x), int(center.z)]
	var gy := get_ground_height(center.x, center.z)
	root.position = Vector3(center.x, gy, center.z)

	var team_color := Color(0.24, 0.28, 0.22) if is_friendly else Color(0.30, 0.22, 0.20) # Olive vs Maroon Camo
	var steel_color := Color(0.20, 0.22, 0.25)
	var hazard_color := Color(0.85, 0.65, 0.15)

	# 1. Main Reinforced Command Bunker
	var bunker := StaticBody3D.new()
	bunker.collision_layer = 2
	bunker.collision_mask = 1
	bunker.add_to_group("solid_obstacle")
	bunker.name = "CommandBunker"
	bunker.position = Vector3(0, 2.2, 0)

	var b_col := CollisionShape3D.new()
	var b_shape := BoxShape3D.new()
	b_shape.size = Vector3(12.0, 4.4, 9.0)
	b_col.shape = b_shape
	bunker.add_child(b_col)

	var b_mesh := MeshInstance3D.new()
	var b_bm := BoxMesh.new()
	b_bm.size = b_shape.size
	b_mesh.mesh = b_bm
	var b_mat := StandardMaterial3D.new()
	b_mat.albedo_color = team_color
	b_mat.roughness = 0.85
	b_mesh.material_override = b_mat
	bunker.add_child(b_mesh)

	# Slanted blast roof cap
	var roof_mesh := MeshInstance3D.new()
	var r_bm := BoxMesh.new()
	r_bm.size = Vector3(13.2, 0.8, 10.2)
	roof_mesh.mesh = r_bm
	roof_mesh.position = Vector3(0, 2.4, 0)
	var r_mat := StandardMaterial3D.new()
	r_mat.albedo_color = Color(team_color.r * 0.8, team_color.g * 0.8, team_color.b * 0.8)
	r_mat.roughness = 0.8
	roof_mesh.material_override = r_mat
	bunker.add_child(roof_mesh)

	root.add_child(bunker)

	# 2. Elevated Sniper Watchtower (8.5m tall)
	var tower := StaticBody3D.new()
	tower.collision_layer = 2
	tower.collision_mask = 1
	tower.add_to_group("solid_obstacle")
	tower.name = "Watchtower"
	tower.position = Vector3(12.0, 0, -8.0)

	# Tower 4 steel legs
	for ox in [-1.5, 1.5]:
		for oz in [-1.5, 1.5]:
			var leg := CollisionShape3D.new()
			var l_shape := BoxShape3D.new()
			l_shape.size = Vector3(0.5, 8.0, 0.5)
			leg.shape = l_shape
			leg.position = Vector3(ox, 4.0, oz)
			tower.add_child(leg)

			var leg_mi := MeshInstance3D.new()
			var leg_bm := BoxMesh.new()
			leg_bm.size = l_shape.size
			leg_mi.mesh = leg_bm
			var leg_mat := StandardMaterial3D.new()
			leg_mat.albedo_color = steel_color
			leg_mat.metallic = 0.6
			leg_mat.roughness = 0.4
			leg_mi.material_override = leg_mat
			leg_mi.position = leg.position
			tower.add_child(leg_mi)

	# Tower Platform at Y=8m
	var plat_col := CollisionShape3D.new()
	var plat_shape := BoxShape3D.new()
	plat_shape.size = Vector3(4.2, 0.6, 4.2)
	plat_col.shape = plat_shape
	plat_col.position = Vector3(0, 8.0, 0)
	tower.add_child(plat_col)

	var plat_mi := MeshInstance3D.new()
	var plat_bm := BoxMesh.new()
	plat_bm.size = plat_shape.size
	plat_mi.mesh = plat_bm
	plat_mi.position = plat_col.position
	plat_mi.material_override = b_mat
	tower.add_child(plat_mi)

	# Tower Amber Beacon Light
	var beacon := OmniLight3D.new()
	beacon.position = Vector3(0, 9.2, 0)
	beacon.light_color = Color(1.0, 0.7, 0.15)
	beacon.light_energy = 2.4
	beacon.omni_range = 18.0
	tower.add_child(beacon)

	var beacon_lens := MeshInstance3D.new()
	var s_mesh := SphereMesh.new()
	s_mesh.radius = 0.25
	s_mesh.height = 0.5
	beacon_lens.mesh = s_mesh
	beacon_lens.position = beacon.position
	var b_lens_mat := StandardMaterial3D.new()
	b_lens_mat.emission_enabled = true
	b_lens_mat.emission = Color(1.0, 0.65, 0.1)
	b_lens_mat.emission_energy_multiplier = 3.0
	beacon_lens.material_override = b_lens_mat
	tower.add_child(beacon_lens)

	root.add_child(tower)

	# 3. Comms Radar Antenna Mast (12m tall)
	var mast := StaticBody3D.new()
	mast.collision_layer = 2
	mast.collision_mask = 1
	mast.add_to_group("solid_obstacle")
	mast.name = "RadarMast"
	mast.position = Vector3(-11.0, 0, 8.0)

	var mast_col := CollisionShape3D.new()
	var m_shape := CylinderShape3D.new()
	m_shape.radius = 0.4
	m_shape.height = 12.0
	mast_col.shape = m_shape
	mast_col.position = Vector3(0, 6.0, 0)
	mast.add_child(mast_col)

	var mast_mi := MeshInstance3D.new()
	var m_cm := CylinderMesh.new()
	m_cm.top_radius = 0.3
	m_cm.bottom_radius = 0.6
	m_cm.height = 12.0
	mast_mi.mesh = m_cm
	mast_mi.position = mast_col.position
	var mast_mat := StandardMaterial3D.new()
	mast_mat.albedo_color = Color(0.75, 0.2, 0.2) # Aviation Red/White mast
	mast_mat.roughness = 0.5
	mast_mi.material_override = mast_mat
	mast.add_child(mast_mi)

	# Radar Dish
	var dish := MeshInstance3D.new()
	var dish_mesh := CylinderMesh.new()
	dish_mesh.top_radius = 1.8
	dish_mesh.bottom_radius = 0.2
	dish_mesh.height = 0.4
	dish.mesh = dish_mesh
	dish.position = Vector3(0, 11.5, 0)
	dish.rotation = Vector3(deg_to_rad(35.0), deg_to_rad(45.0), 0)
	var dish_mat := StandardMaterial3D.new()
	dish_mat.albedo_color = Color(0.85, 0.88, 0.90)
	dish_mat.metallic = 0.7
	dish.material_override = dish_mat
	mast.add_child(dish)

	root.add_child(mast)

	# 4. Destructible Tactical Sandbag Barricades & Steel Barriers
	var barrier_offsets := [
		{"pos": Vector3(0, 0.6, 9.0), "rot": 0.0, "type": "sandbag", "hp": 180.0},
		{"pos": Vector3(7.0, 0.6, 8.0), "rot": -0.35, "type": "sandbag", "hp": 180.0},
		{"pos": Vector3(-7.0, 0.6, 8.0), "rot": 0.35, "type": "sandbag", "hp": 180.0},
		{"pos": Vector3(-12.0, 0.9, 0.0), "rot": 1.57, "type": "barrier", "hp": 300.0},
		{"pos": Vector3(12.0, 0.9, 0.0), "rot": 1.57, "type": "barrier", "hp": 300.0},
		{"pos": Vector3(0, 0.6, -9.0), "rot": 0.0, "type": "sandbag", "hp": 180.0},
	]

	for bo in barrier_offsets:
		var cover = _CoverScript.new()
		cover.cover_type = bo["type"]
		cover.max_hp = bo["hp"]
		cover.current_hp = bo["hp"]
		cover.position = bo["pos"]
		cover.rotation.y = bo["rot"]

		var c_col := CollisionShape3D.new()
		var c_box := BoxShape3D.new()
		c_box.size = Vector3(4.8, 1.2 if bo["type"] == "sandbag" else 1.8, 1.0)
		c_col.shape = c_box
		cover.add_child(c_col)

		var c_mi := MeshInstance3D.new()
		var c_bm := BoxMesh.new()
		c_bm.size = c_box.size
		c_mi.mesh = c_bm
		var c_mat := StandardMaterial3D.new()
		c_mat.albedo_color = Color(0.60, 0.54, 0.40) if bo["type"] == "sandbag" else steel_color
		c_mat.roughness = 0.9
		c_mi.material_override = c_mat
		cover.add_child(c_mi)

		root.add_child(cover)

	# 5. Supply Crates & Fuel Drum Cluster
	for crate_idx in range(4):
		var crate = _CoverScript.new()
		crate.cover_type = "container"
		crate.max_hp = 140.0
		crate.current_hp = 140.0
		var cx := randf_range(-4.0, 4.0)
		var cz := randf_range(5.5, 7.5)
		crate.position = Vector3(cx, 0.75, cz)

		var crate_col := CollisionShape3D.new()
		var crate_box := BoxShape3D.new()
		crate_box.size = Vector3(1.5, 1.5, 1.5)
		crate_col.shape = crate_box
		crate.add_child(crate_col)

		var crate_mi := MeshInstance3D.new()
		var crate_bm := BoxMesh.new()
		crate_bm.size = crate_box.size
		crate_mi.mesh = crate_bm
		var cr_mat := StandardMaterial3D.new()
		cr_mat.albedo_color = hazard_color if crate_idx % 2 == 0 else Color(0.35, 0.28, 0.22)
		cr_mat.roughness = 0.8
		crate_mi.material_override = cr_mat
		crate.add_child(crate_mi)

		root.add_child(crate)

	parent.add_child(root)
	return root


## Spawns an urban frontline ruin with broken two-story slabs, trench lines, dragon's teeth, and a wrecked mecha.
static func spawn_frontline_ruins(parent: Node, center: Vector3, radius: float = 35.0) -> Node3D:
	var root := Node3D.new()
	root.name = "FrontlineRuins_%d_%d" % [int(center.x), int(center.z)]
	var gy := get_ground_height(center.x, center.z)
	root.position = Vector3(center.x, gy, center.z)

	var concrete_color := Color(0.28, 0.28, 0.29)
	var blast_scorch_color := Color(0.12, 0.12, 0.13)

	# 1. Main Collapsed Concrete Ruin (Two-Story Fractured L-Shape)
	var ruin_building := StaticBody3D.new()
	ruin_building.collision_layer = 2
	ruin_building.collision_mask = 1
	ruin_building.add_to_group("solid_obstacle")
	ruin_building.name = "CollapsedBuilding"
	ruin_building.position = Vector3(0, 3.8, 0)

	# North Wall with blast breach
	var n_col := CollisionShape3D.new()
	var n_box := BoxShape3D.new()
	n_box.size = Vector3(14.0, 7.6, 1.2)
	n_col.shape = n_box
	n_col.position = Vector3(0, 0, -5.0)
	ruin_building.add_child(n_col)

	var n_mi := MeshInstance3D.new()
	var n_bm := BoxMesh.new()
	n_bm.size = n_box.size
	n_mi.mesh = n_bm
	n_mi.position = n_col.position
	var r_mat := StandardMaterial3D.new()
	r_mat.albedo_color = concrete_color
	r_mat.roughness = 0.95
	n_mi.material_override = r_mat
	ruin_building.add_child(n_mi)

	# West Wall
	var w_col := CollisionShape3D.new()
	var w_box := BoxShape3D.new()
	w_box.size = Vector3(1.2, 7.6, 10.0)
	w_col.shape = w_box
	w_col.position = Vector3(-6.4, 0, 0)
	ruin_building.add_child(w_col)

	var w_mi := MeshInstance3D.new()
	var w_bm := BoxMesh.new()
	w_bm.size = w_box.size
	w_mi.mesh = w_bm
	w_mi.position = w_col.position
	w_mi.material_override = r_mat
	ruin_building.add_child(w_mi)

	# Slanted Collapsed Second Floor Slab
	var slab_col := CollisionShape3D.new()
	var s_box := BoxShape3D.new()
	s_box.size = Vector3(10.0, 0.6, 8.0)
	slab_col.shape = s_box
	slab_col.position = Vector3(-1.0, 0.4, -0.5)
	slab_col.rotation = Vector3(deg_to_rad(22.0), 0, deg_to_rad(-8.0))
	ruin_building.add_child(slab_col)

	var slab_mi := MeshInstance3D.new()
	var s_bm := BoxMesh.new()
	s_bm.size = s_box.size
	slab_mi.mesh = s_bm
	slab_mi.position = slab_col.position
	slab_mi.rotation = slab_col.rotation
	var scorch_mat := StandardMaterial3D.new()
	scorch_mat.albedo_color = blast_scorch_color
	scorch_mat.roughness = 0.92
	slab_mi.material_override = scorch_mat
	ruin_building.add_child(slab_mi)

	root.add_child(ruin_building)

	# 2. Trench Sandbag Parapets
	var trench_parapets := [
		{"pos": Vector3(8.0, 0.6, 6.0), "rot": 0.25},
		{"pos": Vector3(13.0, 0.6, 8.0), "rot": -0.15},
		{"pos": Vector3(-8.0, 0.6, 10.0), "rot": 0.35},
		{"pos": Vector3(-13.0, 0.6, 12.0), "rot": -0.10},
	]

	for tp in trench_parapets:
		var cover = _CoverScript.new()
		cover.cover_type = "sandbag"
		cover.max_hp = 220.0
		cover.current_hp = 220.0
		cover.position = tp["pos"]
		cover.rotation.y = tp["rot"]

		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(5.2, 1.2, 1.2)
		col.shape = box
		cover.add_child(col)

		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = box.size
		mi.mesh = bm
		var s_mat := StandardMaterial3D.new()
		s_mat.albedo_color = Color(0.55, 0.48, 0.36)
		s_mat.roughness = 0.95
		mi.material_override = s_mat
		cover.add_child(mi)

		root.add_child(cover)

	# 3. Line of Anti-Tank Dragon's Teeth (Pyramidal concrete obstacles)
	for i in range(5):
		var dt := StaticBody3D.new()
		dt.collision_layer = 2
		dt.collision_mask = 1
		dt.add_to_group("solid_obstacle")
		dt.position = Vector3(float(i - 2) * 3.5, 0.9, 16.0 + float(i % 2) * 1.5)

		var dt_col := CollisionShape3D.new()
		var dt_box := BoxShape3D.new()
		dt_box.size = Vector3(1.8, 1.8, 1.8)
		dt_col.shape = dt_box
		dt.add_child(dt_col)

		var dt_mi := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(1.8, 1.8, 1.8)
		dt_mi.mesh = prism
		dt_mi.material_override = r_mat
		dt.add_child(dt_mi)

		root.add_child(dt)

	# 4. Wrecked Valkren Mecha Carcass
	spawn_wrecked_mecha(root, Vector3(5.5, 0, -2.0), deg_to_rad(45.0))

	parent.add_child(root)
	return root


## Spawns a burned-out, smoking Valkren mecha carcass providing solid heavy combat cover.
static func spawn_wrecked_mecha(parent: Node, pos: Vector3, yaw_rad: float = 0.0) -> StaticBody3D:
	var wreck := StaticBody3D.new()
	wreck.name = "WreckedMecha"
	wreck.collision_layer = 2
	wreck.collision_mask = 1
	wreck.add_to_group("solid_obstacle")
	wreck.add_to_group("cover")
	wreck.add_to_group("wreckage")
	wreck.position = pos
	wreck.rotation.y = yaw_rad

	var charred_mat := StandardMaterial3D.new()
	charred_mat.albedo_color = Color(0.14, 0.14, 0.15)
	charred_mat.metallic = 0.65
	charred_mat.roughness = 0.75

	var ember_mat := StandardMaterial3D.new()
	ember_mat.albedo_color = Color(0.1, 0.05, 0.05)
	ember_mat.emission_enabled = true
	ember_mat.emission = Color(1.0, 0.35, 0.08)
	ember_mat.emission_energy_multiplier = 2.5

	# Tilted Torso (Heavy Cover)
	var torso_col := CollisionShape3D.new()
	var t_box := BoxShape3D.new()
	t_box.size = Vector3(2.4, 2.8, 2.0)
	torso_col.shape = t_box
	torso_col.position = Vector3(0, 1.4, 0)
	torso_col.rotation = Vector3(deg_to_rad(-18.0), 0, deg_to_rad(12.0))
	wreck.add_child(torso_col)

	var torso_mi := MeshInstance3D.new()
	var t_bm := BoxMesh.new()
	t_bm.size = t_box.size
	torso_mi.mesh = t_bm
	torso_mi.position = torso_col.position
	torso_mi.rotation = torso_col.rotation
	torso_mi.material_override = charred_mat
	wreck.add_child(torso_mi)

	# Shattered Shoulder & Arm
	var arm_col := CollisionShape3D.new()
	var a_box := BoxShape3D.new()
	a_box.size = Vector3(1.2, 3.2, 1.2)
	arm_col.shape = a_box
	arm_col.position = Vector3(2.2, 0.6, 0.8)
	arm_col.rotation = Vector3(deg_to_rad(75.0), deg_to_rad(30.0), 0)
	wreck.add_child(arm_col)

	var arm_mi := MeshInstance3D.new()
	var a_bm := BoxMesh.new()
	a_bm.size = a_box.size
	arm_mi.mesh = a_bm
	arm_mi.position = arm_col.position
	arm_mi.rotation = arm_col.rotation
	arm_mi.material_override = charred_mat
	wreck.add_child(arm_mi)

	# Smoldering Reactor Core Breach (Emissive Embers)
	var breach := MeshInstance3D.new()
	var b_sphere := SphereMesh.new()
	b_sphere.radius = 0.4
	b_sphere.height = 0.8
	breach.mesh = b_sphere
	breach.position = Vector3(-0.3, 1.2, 0.9)
	breach.material_override = ember_mat
	wreck.add_child(breach)

	# Ambient Warm Glow
	var ember_light := OmniLight3D.new()
	ember_light.position = breach.position
	ember_light.light_color = Color(1.0, 0.45, 0.1)
	ember_light.light_energy = 1.2
	ember_light.omni_range = 6.0
	wreck.add_child(ember_light)

	parent.add_child(wreck)
	return wreck


## Spawns an industrial elevated pipeline spanning between two points with concrete support saddles and refinery silos.
static func spawn_industrial_pipeline(parent: Node, p1: Vector3, p2: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "IndustrialPipeline_%d_%d" % [int(p1.x), int(p1.z)]

	var pipe_mat := StandardMaterial3D.new()
	pipe_mat.albedo_color = Color(0.40, 0.44, 0.48)
	pipe_mat.metallic = 0.75
	pipe_mat.roughness = 0.35

	var concrete_mat := StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.32, 0.32, 0.34)
	concrete_mat.roughness = 0.9

	var silo_mat := StandardMaterial3D.new()
	silo_mat.albedo_color = Color(0.55, 0.58, 0.62)
	silo_mat.metallic = 0.5
	silo_mat.roughness = 0.4

	var total_dist := p1.distance_to(p2)
	var dir := (p2 - p1).normalized()
	var stanchion_spacing := 14.0
	var steps := int(ceil(total_dist / stanchion_spacing))

	# Pipe elevation ~2.5m above ground
	var elevation := 2.5

	for i in range(steps):
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var seg_start := p1.lerp(p2, t0)
		var seg_end := p1.lerp(p2, t1)
		var seg_mid := (seg_start + seg_end) * 0.5
		var seg_len := seg_start.distance_to(seg_end)

		var gy := get_ground_height(seg_mid.x, seg_mid.z)
		var pipe_y := gy + elevation

		# Pipe segment (StaticBody3D)
		var pipe_seg := StaticBody3D.new()
		pipe_seg.collision_layer = 2
		pipe_seg.collision_mask = 1
		pipe_seg.add_to_group("solid_obstacle")
		pipe_seg.position = Vector3(seg_mid.x, pipe_y, seg_mid.z)

		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.75
		shape.height = seg_len
		col.shape = shape
		# Orient cylinder along direction vector
		col.rotation = Vector3(PI * 0.5, atan2(dir.x, dir.z), 0)
		pipe_seg.add_child(col)

		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.75
		cm.bottom_radius = 0.75
		cm.height = seg_len
		mi.mesh = cm
		mi.rotation = col.rotation
		mi.material_override = pipe_mat
		pipe_seg.add_child(mi)

		root.add_child(pipe_seg)

		# Concrete Support Saddle Pier at stanchion
		var pier := StaticBody3D.new()
		pier.collision_layer = 2
		pier.collision_mask = 1
		pier.add_to_group("solid_obstacle")
		var pier_h := elevation + 0.5
		pier.position = Vector3(seg_start.x, gy + pier_h * 0.5, seg_start.z)

		var pier_col := CollisionShape3D.new()
		var p_box := BoxShape3D.new()
		p_box.size = Vector3(1.8, pier_h, 1.8)
		pier_col.shape = p_box
		pier.add_child(pier_col)

		var pier_mi := MeshInstance3D.new()
		var p_bm := BoxMesh.new()
		p_bm.size = p_box.size
		pier_mi.mesh = p_bm
		pier_mi.material_override = concrete_mat
		pier.add_child(pier_mi)

		root.add_child(pier)

	# Fuel Storage Silo at pipe terminus
	var silo := StaticBody3D.new()
	silo.name = "FuelSilo"
	silo.collision_layer = 2
	silo.collision_mask = 1
	silo.add_to_group("solid_obstacle")
	var s_gy := get_ground_height(p2.x, p2.z)
	silo.position = Vector3(p2.x, s_gy + 5.0, p2.z)

	var s_col := CollisionShape3D.new()
	var s_shape := CylinderShape3D.new()
	s_shape.radius = 3.5
	s_shape.height = 10.0
	s_col.shape = s_shape
	silo.add_child(s_col)

	var s_mi := MeshInstance3D.new()
	var s_cm := CylinderMesh.new()
	s_cm.top_radius = 3.5
	s_cm.bottom_radius = 3.5
	s_cm.height = 10.0
	s_mi.mesh = s_cm
	s_mi.material_override = silo_mat
	silo.add_child(s_mi)

	# Top dome cap
	var dome := MeshInstance3D.new()
	var d_mesh := SphereMesh.new()
	d_mesh.radius = 3.5
	d_mesh.height = 3.5
	dome.mesh = d_mesh
	dome.position = Vector3(0, 5.0, 0)
	dome.material_override = silo_mat
	silo.add_child(dome)

	root.add_child(silo)

	parent.add_child(root)
	return root
