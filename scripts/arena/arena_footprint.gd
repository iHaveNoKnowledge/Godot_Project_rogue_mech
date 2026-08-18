class_name ArenaFootprint
extends RefCounted

## An irregular, deterministic battlefield footprint for combat arenas.
##
## The footprint lives on a coarse grid of cells (CELL_SIZE per cell) inside the
## arena's square bounding box. Generation is seeded (board seed + sector +
## tile) so the same battle always fights on the same shape while different
## battles get different, non-rectangular silhouettes (L/T/cross/blob). The
## shape is grown from a center skeleton into arms, then blob-expanded — always
## connected, never the full square.
##
## Consumers (escape/apron/void frame, spawn ring, cover scatter, nav source)
## read the boundary segments and cell membership so the whole battlefield
## hugs the irregular outline instead of a square.

const CELL_SIZE := 40.0

var seed_value: int = 0
var arena_size: float = 240.0
var n: int = 6
var origin := Vector2.ZERO
var cells: Dictionary = {}          # Vector2i -> true (grid coords)
var world_centers := PackedVector2Array()
var centroid := Vector2.ZERO
var bounds := Rect2()
# Merged boundary segments in world space: {a: Vector2, b: Vector2, normal: Vector2}
# (normal points OUTWARD from the footprint). Form a closed loop.
var segments: Array = []
var perimeter: float = 0.0
# Only the boundary runs that sit on the footprint's EXTREME supporting lines
# (the outer edges of the bounding box). Interior notch/slot walls of L/T/cross
# silhouettes reach deep into the map — retreat zones/apron/void frames and the
# spawn ring must hug the OUTER hull instead, or they'd sit in the middle of the
# battlefield.
var outer_segments: Array = []
var outer_perimeter: float = 0.0


static func create(seed: int, arena_size: float) -> ArenaFootprint:
	var f := ArenaFootprint.new()
	f.seed_value = seed
	f.arena_size = arena_size
	f._generate()
	return f


func is_inside(pos: Vector2) -> bool:
	# Grid bounds are INCLUSIVE on the far edge: cells span [min, max] and a
	# point exactly on the max boundary (e.g. a ring sample at a corner) still
	# counts as inside. The tiny epsilon keeps floor() from pushing a boundary
	# point into the cell just beyond the grid.
	var gx := int(floor((pos.x - origin.x) / CELL_SIZE - 1e-5))
	var gy := int(floor((pos.y - origin.y) / CELL_SIZE - 1e-5))
	if gx < 0 or gx >= n or gy < 0 or gy >= n:
		return false
	return cells.has(Vector2i(gx, gy))


# Minimum horizontal distance from a point to the footprint outline (0 when the
# point sits on a boundary edge). Used to keep spawns clear of the retreat
# trigger, which extends ~12m inside the outline.
func distance_to_outline(pos: Vector2) -> float:
	var d := INF
	for s in segments:
		d = minf(d, _distance_to_segment(pos, s["a"], s["b"]))
	return d if d != INF else 0.0


static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 <= 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _generate() -> void:
	n = clampi(int(round(arena_size / CELL_SIZE)), 5, 12)
	origin = Vector2(-arena_size / 2.0, -arena_size / 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var grid_area := n * n
	var target := clampi(int(round(grid_area * rng.randf_range(0.55, 0.80))), 6, grid_area - 4)

	var center := Vector2i(n / 2, n / 2)
	cells[center] = true

	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	# Plant skeleton arms so the blob gets L/T/cross silhouettes instead of a
	# round mound. Each arm walks outward from the center and turns randomly.
	var arms := rng.randi_range(2, 4)
	for arm in range(arms):
		var dir: Vector2i = dirs[rng.randi_range(0, 3)]
		var cur := center
		var steps := rng.randi_range(2, maxi(3, n / 2))
		for s in range(steps):
			cur += dir
			if _in_bounds(cur) and not cells.has(cur):
				cells[cur] = true
			if rng.randf() < 0.4:
				dir = dirs[rng.randi_range(0, 3)]

	# Blob-expand from the border to the target cell count (keeps it connected).
	var guard := 0
	while cells.size() < target and guard < 2000:
		guard += 1
		var border := _compute_border()
		if border.is_empty():
			break
		cells[border[rng.randi_range(0, border.size() - 1)]] = true

	_compute_derived()


func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < n and c.y >= 0 and c.y < n


func _compute_border() -> Array:
	# Grid cells (not yet in the region) that touch the region orthogonally.
	var border := []
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for gx in range(n):
		for gy in range(n):
			var c := Vector2i(gx, gy)
			if cells.has(c):
				continue
			for d in dirs:
				if cells.has(c + d):
					border.append(c)
					break
	return border


func _compute_derived() -> void:
	world_centers.clear()
	var sum := Vector2.ZERO
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for c: Vector2i in cells:
		var w := origin + (Vector2(c) + Vector2(0.5, 0.5)) * CELL_SIZE
		world_centers.append(w)
		sum += w
		min_p.x = minf(min_p.x, w.x)
		min_p.y = minf(min_p.y, w.y)
		max_p.x = maxf(max_p.x, w.x)
		max_p.y = maxf(max_p.y, w.y)
	if not world_centers.is_empty():
		centroid = sum / float(world_centers.size())
	bounds = Rect2(min_p, max_p - min_p)

	var raw: Array = []
	for c: Vector2i in cells:
		var cell_x0: float = origin.x + float(c.x) * CELL_SIZE
		var cell_x1: float = cell_x0 + CELL_SIZE
		var cell_y0: float = origin.y + float(c.y) * CELL_SIZE
		var cell_y1: float = cell_y0 + CELL_SIZE
		if not cells.has(c + Vector2i(1, 0)):
			raw.append({"a": Vector2(cell_x1, cell_y0), "b": Vector2(cell_x1, cell_y1), "normal": Vector2(1, 0)})
		if not cells.has(c + Vector2i(-1, 0)):
			raw.append({"a": Vector2(cell_x0, cell_y1), "b": Vector2(cell_x0, cell_y0), "normal": Vector2(-1, 0)})
		if not cells.has(c + Vector2i(0, 1)):
			raw.append({"a": Vector2(cell_x0, cell_y1), "b": Vector2(cell_x1, cell_y1), "normal": Vector2(0, 1)})
		if not cells.has(c + Vector2i(0, -1)):
			raw.append({"a": Vector2(cell_x1, cell_y0), "b": Vector2(cell_x0, cell_y0), "normal": Vector2(0, -1)})

	segments = _merge_segments(raw)
	perimeter = 0.0
	for s in segments:
		perimeter += (s["a"] as Vector2).distance_to(s["b"])

	# Keep only the boundary runs on the extreme supporting lines (the outer
	# edges of the cell bounding box). Interior notch/slot walls are excluded so
	# retreat frames and spawns stay at the battlefield's true outer edge.
	var min_gx := n
	var max_gx := -1
	var min_gy := n
	var max_gy := -1
	for c: Vector2i in cells:
		min_gx = mini(min_gx, c.x)
		max_gx = maxi(max_gx, c.x)
		min_gy = mini(min_gy, c.y)
		max_gy = maxi(max_gy, c.y)
	var min_x_edge: float = origin.x + float(min_gx) * CELL_SIZE
	var max_x_edge: float = origin.x + float(max_gx + 1) * CELL_SIZE
	var min_y_edge: float = origin.y + float(min_gy) * CELL_SIZE
	var max_y_edge: float = origin.y + float(max_gy + 1) * CELL_SIZE
	outer_segments = []
	outer_perimeter = 0.0
	for s in segments:
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var on_extreme := false
		if absf(a.x - b.x) < 0.01:
			on_extreme = absf(a.x - min_x_edge) < 0.01 or absf(a.x - max_x_edge) < 0.01
		else:
			on_extreme = absf(a.y - min_y_edge) < 0.01 or absf(a.y - max_y_edge) < 0.01
		if on_extreme:
			outer_segments.append(s)
			outer_perimeter += a.distance_to(b)


# Merges axis-aligned raw boundary edges into long runs so the escape frame,
# apron and void barrier stay low-node (one box per run, not per cell edge).
func _merge_segments(raw: Array) -> Array:
	var result: Array = []
	# Group by axis (segment is vertical when a.x == b.x) + outward normal.
	var vertical: Array = []  # {const, normal, a.y, b.y}
	var horizontal: Array = []
	var eps := 0.01

	for s in raw:
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var normal: Vector2 = s["normal"]
		if absf(a.x - b.x) < eps:  # vertical run at x == const
			vertical.append({
				"const": a.x, "normal": normal,
				"lo": minf(a.y, b.y), "hi": maxf(a.y, b.y),
			})
		else:  # horizontal run at y == const
			horizontal.append({
				"const": a.y, "normal": normal,
				"lo": minf(a.x, b.x), "hi": maxf(a.x, b.x),
			})

	vertical.sort_custom(func(x, y): return x["const"] < y["const"] or (absf(x["const"] - y["const"]) < eps and x["lo"] < y["lo"]))
	horizontal.sort_custom(func(x, y): return x["const"] < y["const"] or (absf(x["const"] - y["const"]) < eps and x["lo"] < y["lo"]))

	_merge_runs(vertical, result, true)
	_merge_runs(horizontal, result, false)
	return result


func _merge_runs(runs: Array, result: Array, is_vertical: bool) -> void:
	var eps := 0.01
	var i := 0
	while i < runs.size():
		var cur = runs[i]
		var lo: float = cur["lo"]
		var hi: float = cur["hi"]
		var normal: Vector2 = cur["normal"]
		var c: float = cur["const"]
		var j := i + 1
		while j < runs.size():
			var nxt = runs[j]
			if absf(nxt["const"] - c) > eps or (nxt["normal"] - normal).length() > eps:
				break
			# Same line + same side; merge only if adjacent or overlapping.
			if nxt["lo"] <= hi + eps:
				hi = maxf(hi, nxt["hi"])
				j += 1
			else:
				break
		var a: Vector2
		var b: Vector2
		if is_vertical:
			a = Vector2(c, lo)
			b = Vector2(c, hi)
		else:
			a = Vector2(lo, c)
			b = Vector2(hi, c)
		result.append({"a": a, "b": b, "normal": normal})
		i = j


# Evenly-spaced points just inside the OUTER boundary, sampled by arc-length so
# an L/T/cross shape gets spawns hugging its real hull instead of a circle. The
# outer hull is used (not the full outline) so spawns never sit deep inside the
# map along an interior notch wall.
func ring_points(count: int, inward: float = 10.0) -> Array:
	var points := []
	var loop := outer_segments if not outer_segments.is_empty() else segments
	var loop_perimeter := outer_perimeter if not outer_segments.is_empty() else perimeter
	if loop.is_empty() or count <= 0:
		return points
	var step := loop_perimeter / float(count)
	var seg_idx := 0
	var seg_dist := 0.0
	var seg_len := (loop[0]["a"] as Vector2).distance_to(loop[0]["b"])
	var t := 0.0
	for k in range(count):
		while t > seg_dist + seg_len and seg_idx < loop.size() - 1:
			seg_dist += seg_len
			seg_idx += 1
			seg_len = (loop[seg_idx]["a"] as Vector2).distance_to(loop[seg_idx]["b"])
		# Keep samples interior to the segment: a sample sitting exactly on a
		# segment end (a corner of the outline) can land right on a grid line,
		# making its inside/outside classification ambiguous.
		var frac: float = clampf((t - seg_dist) / maxf(seg_len, 0.001), 0.05, 0.95)
		var seg: Dictionary = loop[seg_idx]
		var a: Vector2 = seg["a"]
		var b: Vector2 = seg["b"]
		var normal: Vector2 = seg["normal"]
		var p: Vector2 = a.lerp(b, frac) - normal * inward
		points.append(Vector3(p.x, 0.05, p.y))
		t += step
	return points
