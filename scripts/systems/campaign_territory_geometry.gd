class_name CampaignTerritoryGeometry
extends RefCounted

## Deterministic, data-only territory geography generation and validation.
## Geometry stays separate from campaign nodes, control, ownership, routes,
## and authoritative gameplay adjacency. Input regions are simple polygons.

const COORD_EPSILON := 0.001
const AREA_EPSILON := 0.00001
const CLIP_DENOMINATOR_EPSILON := 0.0000001


## Returns {ok, seed, bounds, sites, regions, geometric_neighbors, errors}.
## IDs are trimmed and sorted before site generation, making ID-to-region
## assignment independent of caller ordering.
static func generate_voronoi(territory_ids: Array, bounds: Rect2, seed: int) -> Dictionary:
	var errors: Array[String] = []
	var ids: Array[String] = []
	for raw_id in territory_ids:
		if not (raw_id is String):
			errors.append("territory ids must be strings")
			continue
		var territory_id := str(raw_id).strip_edges()
		if territory_id.is_empty() or ids.has(territory_id):
			errors.append("territory ids must be unique non-empty strings after trimming")
			continue
		ids.append(territory_id)
	ids.sort()
	if ids.is_empty():
		errors.append("at least one territory id is required")
	if not _rect_is_valid(bounds):
		errors.append("map bounds must be finite and have positive width and height")
	if not errors.is_empty():
		return _failure(errors, seed, bounds)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var sites: Dictionary = {}
	for territory_id in ids:
		sites[territory_id] = Vector2(
			rng.randf_range(bounds.position.x, bounds.end.x),
			rng.randf_range(bounds.position.y, bounds.end.y)
		)
	var regions: Dictionary = {}
	for territory_id in ids:
		var polygon := _rect_polygon(bounds)
		for other_id in ids:
			if other_id != territory_id:
				polygon = _clip_to_nearest_site(polygon, sites[territory_id], sites[other_id])
				if polygon.is_empty():
					break
		regions[territory_id] = polygon
	var validation := validate_regions(regions, bounds)
	return {
		"ok": validation.is_empty(), "seed": seed, "bounds": bounds,
		"sites": sites, "regions": regions,
		"geometric_neighbors": calculate_geometric_neighbors(regions),
		"errors": validation,
	}


## Validates simple polygons against a rectangular domain. A planar arrangement
## is split at every polygon vertex and inter-region edge crossing. Membership
## is constant inside each resulting cell, so gap and overlap areas are counted
## independently. Tolerances: coordinates within 0.001 map units of the edge
## are accepted; area defects <= max(1e-5, domain area * 1e-6) are tolerated.
static func validate_regions(regions: Dictionary, bounds: Rect2) -> Array[String]:
	var errors: Array[String] = []
	if not _rect_is_valid(bounds):
		errors.append("map bounds must be finite and have positive width and height")
		return errors
	if regions.is_empty():
		errors.append("at least one territory region is required")
		return errors
	var polygons: Dictionary = {}
	var ids := regions.keys()
	ids.sort()
	for raw_id in ids:
		if not (raw_id is String):
			errors.append("territory id must be a string")
			continue
		var territory_id := str(raw_id)
		if territory_id.strip_edges().is_empty():
			errors.append("territory id cannot be empty")
		var parsed := _read_simple_polygon(regions[raw_id], territory_id)
		if not parsed.ok:
			errors.append_array(parsed.errors)
			continue
		var polygon: PackedVector2Array = parsed.polygon
		polygons[territory_id] = polygon
		for point in polygon:
			if point.x < bounds.position.x - COORD_EPSILON or point.x > bounds.end.x + COORD_EPSILON or point.y < bounds.position.y - COORD_EPSILON or point.y > bounds.end.y + COORD_EPSILON:
				errors.append("%s has a vertex outside map bounds" % territory_id)
				break
	if polygons.size() != regions.size():
		return errors
	var partition := _measure_partition(polygons, bounds)
	var tolerance := _area_tolerance(bounds)
	if partition.gap_area > tolerance:
		errors.append("territory regions leave a map coverage gap (uncovered area %.6f)" % partition.gap_area)
	if partition.overlap_area > tolerance:
		errors.append("territory regions overlap in their interiors (overlap area %.6f)" % partition.overlap_area)
	return errors


## Geometry yields diagnostic candidates only; explicit gameplay neighbors are
## never inferred or mutated by this comparison.
static func compare_neighbors(geometric_neighbors: Dictionary, explicit_neighbors: Dictionary) -> Dictionary:
	var missing: Array[String] = []
	var without_contact: Array[String] = []
	var invalid: Array[String] = []
	var ids := explicit_neighbors.keys()
	for id in geometric_neighbors:
		if not ids.has(id):
			ids.append(id)
	ids.sort()
	for id in ids:
		var authored: Array = explicit_neighbors.get(id, [])
		var physical: Array = geometric_neighbors.get(id, [])
		for neighbor in physical:
			if not ids.has(neighbor):
				invalid.append("%s -> %s" % [id, neighbor])
			elif not authored.has(neighbor):
				missing.append("%s -> %s" % [id, neighbor])
		for neighbor in authored:
			if not ids.has(neighbor):
				invalid.append("%s -> %s" % [id, neighbor])
			elif not physical.has(neighbor):
				without_contact.append("%s -> %s" % [id, neighbor])
	return {"missing_declarations": missing, "explicit_without_geometric_contact": without_contact, "invalid_references": invalid}


## Reports positive-length collinear boundary contacts, including differently
## subdivided segments. Shared points alone and parallel lines farther apart
## than COORD_EPSILON are not neighbors.
static func calculate_geometric_neighbors(regions: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var ids := regions.keys()
	ids.sort()
	for id in ids:
		result[id] = []
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var a_id: String = ids[i]
			var b_id: String = ids[j]
			if _polygons_share_boundary(regions[a_id], regions[b_id]):
				result[a_id].append(b_id)
				result[b_id].append(a_id)
	return result


static func _polygons_share_boundary(raw_a: Variant, raw_b: Variant) -> bool:
	var a := _to_packed_polygon(raw_a)
	var b := _to_packed_polygon(raw_b)
	for i in range(a.size()):
		for j in range(b.size()):
			if _segments_share_positive_length(a[i], a[(i + 1) % a.size()], b[j], b[(j + 1) % b.size()]):
				return true
	return false


static func _segments_share_positive_length(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> bool:
	var a_dir := a1 - a0
	var b_dir := b1 - b0
	var a_len := a_dir.length()
	var b_len := b_dir.length()
	if a_len <= COORD_EPSILON or b_len <= COORD_EPSILON:
		return false
	var axis := a_dir / a_len
	if absf(axis.cross(b_dir / b_len)) > COORD_EPSILON / maxf(1.0, minf(a_len, b_len)):
		return false
	if absf((b0 - a0).cross(axis)) > COORD_EPSILON or absf((b1 - a0).cross(axis)) > COORD_EPSILON:
		return false
	var p0 := (b0 - a0).dot(axis)
	var p1 := (b1 - a0).dot(axis)
	var overlap := minf(a_len, maxf(p0, p1)) - maxf(0.0, minf(p0, p1))
	return overlap > COORD_EPSILON


static func _measure_partition(polygons: Dictionary, bounds: Rect2) -> Dictionary:
	var ordered_ids := polygons.keys()
	ordered_ids.sort()
	var y_breaks: Array[float] = [bounds.position.y, bounds.end.y]
	var all_polygons: Array[PackedVector2Array] = []
	for id in ordered_ids:
		var polygon: PackedVector2Array = polygons[id]
		all_polygons.append(polygon)
		for point in polygon:
			if point.y > bounds.position.y and point.y < bounds.end.y:
				y_breaks.append(point.y)
	# Add every region-region and region-domain edge crossing so edge order is
	# fixed inside each horizontal slab, including where a boundary enters/leaves.
	var arrangement_polygons := all_polygons.duplicate()
	arrangement_polygons.append(_rect_polygon(bounds))
	for i in range(arrangement_polygons.size()):
		for j in range(i + 1, arrangement_polygons.size()):
			var a: PackedVector2Array = arrangement_polygons[i]
			var b: PackedVector2Array = arrangement_polygons[j]
			for ai in range(a.size()):
				for bi in range(b.size()):
					var crossing = Geometry2D.segment_intersects_segment(a[ai], a[(ai + 1) % a.size()], b[bi], b[(bi + 1) % b.size()])
					if crossing is Vector2 and crossing.y > bounds.position.y and crossing.y < bounds.end.y:
						y_breaks.append(crossing.y)
	y_breaks.sort()
	var unique_y: Array[float] = []
	for y in y_breaks:
		# Only coalesce identical computed events. A distance-based merge can
		# erase a real narrow cell whose accumulated area exceeds the tolerance.
		if unique_y.is_empty() or y != unique_y[-1]:
			unique_y.append(y)
	var gap_area := 0.0
	var overlap_area := 0.0
	for yi in range(unique_y.size() - 1):
		var y0 := unique_y[yi]
		var y1 := unique_y[yi + 1]
		if y1 <= y0:
			continue
		var sample_y := (y0 + y1) * 0.5
		var x_breaks: Array[float] = [bounds.position.x, bounds.end.x]
		for polygon in all_polygons:
			for ei in range(polygon.size()):
				var a := polygon[ei]
				var b := polygon[(ei + 1) % polygon.size()]
				if a.y == b.y or sample_y < minf(a.y, b.y) or sample_y > maxf(a.y, b.y):
					continue
				var t := (sample_y - a.y) / (b.y - a.y)
				var x := a.x + (b.x - a.x) * t
				if x > bounds.position.x and x < bounds.end.x:
					x_breaks.append(x)
		x_breaks.sort()
		var unique_x: Array[float] = []
		for x in x_breaks:
			if unique_x.is_empty() or x != unique_x[-1]:
				unique_x.append(x)
		for xi in range(unique_x.size() - 1):
			var x0 := unique_x[xi]
			var x1 := unique_x[xi + 1]
			if x1 <= x0:
				continue
			# Keep the sample coordinates scalar. Constructing a Vector2 here
			# narrows the midpoint to the engine's Vector2 precision, which can
			# move it onto a region boundary at large world coordinates.
			var sample_x := x0 + (x1 - x0) * 0.5
			var memberships := 0
			for polygon in all_polygons:
				if _contains_interior_point(sample_x, sample_y, polygon):
					memberships += 1
			var cell_area := (x1 - x0) * (y1 - y0)
			if memberships == 0:
				gap_area += cell_area
			elif memberships > 1:
				overlap_area += cell_area
	return {"gap_area": gap_area, "overlap_area": overlap_area}


static func _contains_interior_point(point_x: float, point_y: float, polygon: PackedVector2Array) -> bool:
	# Geometry2D's point test treats points within a tiny internal edge epsilon as
	# boundary points. Arrangement cells can be narrower than that epsilon, so
	# classify their interior samples with a strict ray crossing instead.
	var inside := false
	for index in range(polygon.size()):
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		if (a.y > point_y) != (b.y > point_y):
			var crossing_x: float = a.x + (point_y - a.y) * (b.x - a.x) / (b.y - a.y)
			if point_x < crossing_x:
				inside = not inside
	return inside


static func _read_simple_polygon(raw: Variant, id: String) -> Dictionary:
	if not (raw is Array or raw is PackedVector2Array):
		return {"ok": false, "polygon": PackedVector2Array(), "errors": ["%s polygon must be an Array or PackedVector2Array" % id]}
	var polygon := _to_packed_polygon(raw)
	if polygon.size() < 3:
		return {"ok": false, "polygon": polygon, "errors": ["%s polygon must contain at least 3 vertices with Vector2 values" % id]}
	var errors: Array[String] = []
	for i in range(polygon.size()):
		var point := polygon[i]
		var next := polygon[(i + 1) % polygon.size()]
		if not point.is_finite():
			errors.append("%s polygon contains a non-finite vertex" % id)
		if point.distance_to(next) <= COORD_EPSILON:
			errors.append("%s polygon has a duplicate or near-zero edge" % id)
			break
	if errors.is_empty():
		if absf(_signed_area(polygon)) <= AREA_EPSILON:
			errors.append("%s polygon has zero or negligible area" % id)
		if _has_self_intersection(polygon):
			errors.append("%s polygon self-intersects" % id)
	return {"ok": errors.is_empty(), "polygon": polygon, "errors": errors}


static func _to_packed_polygon(raw: Variant) -> PackedVector2Array:
	if raw is PackedVector2Array:
		return raw
	var polygon := PackedVector2Array()
	if raw is Array:
		for point in raw:
			if not (point is Vector2):
				return PackedVector2Array()
			polygon.append(point)
	return polygon


static func _has_self_intersection(polygon: PackedVector2Array) -> bool:
	for i in range(polygon.size()):
		for j in range(i + 1, polygon.size()):
			if j == (i + 1) % polygon.size() or (j + 1) % polygon.size() == i:
				continue
			if Geometry2D.segment_intersects_segment(polygon[i], polygon[(i + 1) % polygon.size()], polygon[j], polygon[(j + 1) % polygon.size()]) != null:
				return true
	return false


static func _clip_to_nearest_site(polygon: PackedVector2Array, site: Vector2, other: Vector2) -> PackedVector2Array:
	var output := PackedVector2Array()
	if polygon.is_empty():
		return output
	var delta := other - site
	var midpoint := (site + other) * 0.5
	for index in range(polygon.size()):
		var current := polygon[index]
		var next := polygon[(index + 1) % polygon.size()]
		var current_inside := (current - midpoint).dot(delta) <= 0.0
		var next_inside := (next - midpoint).dot(delta) <= 0.0
		if current_inside:
			output.append(current)
		if current_inside != next_inside:
			var direction := next - current
			var denominator := direction.dot(delta)
			if denominator != 0.0:
				var t := (midpoint - current).dot(delta) / denominator
				output.append(current + direction * clampf(t, 0.0, 1.0))
	return output


static func _signed_area(polygon: PackedVector2Array) -> float:
	var twice := 0.0
	for i in range(polygon.size()):
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		twice += a.x * b.y - b.x * a.y
	return twice * 0.5


static func _rect_polygon(bounds: Rect2) -> PackedVector2Array:
	return PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)])


static func _rect_is_valid(bounds: Rect2) -> bool:
	return bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.x > 0.0 and bounds.size.y > 0.0


static func _area_tolerance(bounds: Rect2) -> float:
	return maxf(AREA_EPSILON, bounds.size.x * bounds.size.y * 0.000001)


static func _failure(errors: Array[String], seed: int, bounds: Rect2) -> Dictionary:
	return {"ok": false, "seed": seed, "bounds": bounds, "sites": {}, "regions": {}, "geometric_neighbors": {}, "errors": errors}
