extends RefCounted
class_name WarBiomeGenerator

## War Biome 2000x2000 — 4 โซน Voronoi แบบ seeded  + ทุกของวางบนพื้นจริง (no floating)
## ของยกสูงต้องมีคาน/เสา — bridge จะมีเสาทุก 25m, highland เป็นเนินติดพื้นไม่ใช่กล่องลอย

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
	_noise.frequency = 0.006
	_noise.fractal_octaves = 3
	# Voronoi centers 4 จุด + 1 กลาง (seeded)
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	_zone_centers.clear()
	_zone_biomes.clear()
	var pts := [
		Vector2(-550, -550), Vector2(550, -550),
		Vector2(-550, 550), Vector2(550, 550),
		Vector2(0, 0),
	]
	# jitter
	for i in range(pts.size()):
		pts[i] += Vector2(rng.randf_range(-120, 120), rng.randf_range(-120, 120))
	_zone_centers = pts
	for i in range(pts.size()):
		_zone_biomes.append(rng.randi_range(0, Biome.size() - 1))


static func get_ground_height(wx: float, wz: float) -> float:
	if _noise == null:
		_ensure_noise(int(GlobalData.board.board_seed) if GlobalData.board else 1337)
	# พื้นเอียงอ่อนๆ 2-3m ไม่ให้ลอย
	var h: float = _noise.get_noise_2d(wx * 1.0, wz * 1.0) * 2.8
	# ลดความสูงใกล้ขอบแมพให้เป็นฐานเรียบสำหรับวางฐานทัพ
	var edge := maxf(absf(wx), absf(wz))
	if edge > 800.0:
		h *= clampf((1000.0 - edge) / 200.0, 0.0, 1.0)
	return h


static func snap_to_ground(pos: Vector3, half_height: float) -> Vector3:
	return Vector3(pos.x, get_ground_height(pos.x, pos.z) + half_height + 0.02, pos.z)


static func biome_at(wx: float, wz: float) -> int:
	if _zone_centers.is_empty():
		_ensure_noise(int(GlobalData.board.board_seed) if GlobalData.board else 1337)
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
		Biome.DESERT: return Color(0.78, 0.68, 0.45)
		Biome.CITY_RUINS: return Color(0.42, 0.42, 0.44)
		Biome.FOREST: return Color(0.22, 0.38, 0.18)
		Biome.RIVER_VALLEY: return Color(0.28, 0.42, 0.30)
		_: return Color(0.45, 0.52, 0.32)


static func build_biome_ground(parent: Node3D, p_seed: int = 1337) -> void:
	_ensure_noise(p_seed)
	# สร้าง 4 patch สีตาม biome + displaced mesh เล็กๆ ให้เห็นเนินอ่อนๆ
	var patch_size := 1000.0
	var half_patch := 500.0
	for qx in [-1, 1]:
		for qz in [-1, 1]:
			var cx: float = qx * half_patch
			var cz: float = qz * half_patch
			var b: int = biome_at(cx, cz)
			var col: Color = biome_color(b)
			var patch := MeshInstance3D.new()
			patch.name = "BiomePatch_%d_%d" % [qx, qz]
			var pm := PlaneMesh.new()
			pm.size = Vector2(patch_size, patch_size)
			pm.subdivide_depth = 10
			pm.subdivide_width = 10
			patch.mesh = pm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = col
			mat.roughness = 0.9
			patch.material_override = mat
			patch.position = Vector3(cx, get_ground_height(cx, cz) + 0.01, cz)
			parent.add_child(patch)
			# label
			var lbl := Label3D.new()
			lbl.text = "%s" % Biome.keys()[b]
			lbl.font_size = 28
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.no_depth_test = true
			lbl.position = Vector3(cx, get_ground_height(cx, cz) + 6.0, cz)
			parent.add_child(lbl)


static func spawn_grounded_box(parent: Node3D, pos_xz: Vector2, size: Vector3, color: Color) -> StaticBody3D:
	var wx: float = pos_xz.x
	var wz: float = pos_xz.y
	var gy: float = get_ground_height(wx, wz)
	var body := StaticBody3D.new()
	body.collision_layer = 2
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


## สะพานยกสูง — วาง deck แยกท่อน + เสาทุก ~25m ลงถึงพื้นจริง
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
	for i in range(segments):
		var mid := start + dir * (seg_len * (i + 0.5))
		var gy: float = get_ground_height(mid.x, mid.z)
		var deck_y: float = gy + deck_height
		# deck slab
		var slab := StaticBody3D.new()
		slab.collision_layer = 2
		slab.position = Vector3(mid.x, deck_y, mid.z)
		# rotate to align
		var ang := atan2(dir.z, dir.x)
		slab.rotation.y = -ang
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(seg_len + 0.2, 0.6, deck_width)
		col.shape = box
		slab.add_child(col)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(seg_len + 0.2, 0.6, deck_width)
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.38, 0.38, 0.40)
		mi.material_override = mat
		slab.add_child(mi)
		root.add_child(slab)
		# pillar ใต้แต่ละรอยต่อ (รวมหัว-ท้าย)
		for t in [0.0, 1.0]:
			var px: float = start.x + dir.x * (seg_len * (i + t))
			var pz: float = start.z + dir.z * (seg_len * (i + t))
			# pillar ทุก 25m จริง — ข้ามถี่เกินไปจะแน่น ให้วางทุก 2 segment หรือหัวท้าย
			if i % 2 != 0 and t == 0.0:
				continue
			var pgy: float = get_ground_height(px, pz)
			var pillar_h: float = deck_y - 0.3 - pgy
			if pillar_h < 0.8:
				continue
			var pillar := StaticBody3D.new()
			pillar.collision_layer = 2
			pillar.position = Vector3(px, pgy + pillar_h * 0.5, pz)
			var pcol := CollisionShape3D.new()
			var pbox := BoxShape3D.new()
			pbox.size = Vector3(1.4, pillar_h, 1.4)
			pcol.shape = pbox
			pillar.add_child(pcol)
			var pmi := MeshInstance3D.new()
			var pbm := BoxMesh.new()
			pbm.size = Vector3(1.4, pillar_h, 1.4)
			pmi.mesh = pbm
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = Color(0.35, 0.35, 0.36)
			pmi.material_override = pmat
			pillar.add_child(pmi)
			root.add_child(pillar)
	return root


## Highland แบบ mesa ติดพื้น — ไม่ลอย มีผนังข้างลงถึงพื้นจริง
static func spawn_highland_mesa(parent: Node3D, center_xz: Vector2, size: Vector3, mesa_height: float = 18.0) -> StaticBody3D:
	var wx: float = center_xz.x
	var wz: float = center_xz.y
	var gy: float = get_ground_height(wx, wz)
	# Mesa วางบนพื้น — bottom ที่ gy
	var body := StaticBody3D.new()
	body.collision_layer = 2
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
	mat.albedo_color = Color(0.55, 0.52, 0.48)
	mat.roughness = 0.9
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
	return body
