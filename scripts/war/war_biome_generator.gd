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
