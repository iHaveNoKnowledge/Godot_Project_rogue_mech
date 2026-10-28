extends Node

const Geometry = preload("res://scripts/systems/campaign_territory_geometry.gd")
const DOMAIN := Rect2(Vector2.ZERO, Vector2(10.0, 10.0))
var _checks := 0
var _fails := 0


func _ready() -> void:
	_test_valid_partition_and_coverage_failures()
	_test_sub_epsilon_gap_fixture()
	_test_close_distinct_partition()
	_test_large_coordinate_midpoint_gap()
	_test_below_tolerance_gap()
	_test_invalid_polygons()
	_test_shared_boundaries()
	_test_neighbor_diagnostics()
	_test_generator_determinism_and_inputs()
	if _checks != 42:
		_fails += 1
		printerr("TERRITORY GEOMETRY FAIL: expected 42 checks but executed %d" % _checks)
	print("CAMPAIGN_TERRITORY_GEOMETRY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _test_valid_partition_and_coverage_failures() -> void:
	var left := _rect(0.0, 0.0, 5.0, 10.0)
	var right := _rect(5.0, 0.0, 10.0, 10.0)
	_check(Geometry.validate_regions({"a": left, "b": right}, DOMAIN).is_empty(), "known two-polygon partition is valid")
	_expect_error({"a": _rect(0.0, 0.0, 4.0, 10.0), "b": _rect(5.0, 0.0, 10.0, 10.0)}, "coverage gap", "gap-only layout reports uncovered map area")
	_expect_error({"a": _rect(0.0, 0.0, 6.0, 10.0), "b": _rect(5.0, 0.0, 10.0, 10.0)}, "overlap in their interiors", "overlap-only layout reports interior overlap")
	var balanced := Geometry.validate_regions({"a": _rect(0.0, 0.0, 6.0, 10.0), "b": _rect(5.0, 0.0, 9.0, 10.0)}, DOMAIN)
	_check(_has_error(balanced, "overlap in their interiors") and _has_error(balanced, "coverage gap"), "equal summed area with a balanced gap and overlap reports both defects")
	_expect_error({"outside": _rect(-1.0, 0.0, 10.0, 10.0)}, "outside map bounds", "polygon extending outside map domain is rejected")


func _test_sub_epsilon_gap_fixture() -> void:
	var domain := Rect2(Vector2.ZERO, Vector2(0.05, 1000.0))
	var gap_width := 3.0e-8
	var region_width := (domain.size.x - 4.0 * gap_width) / 5.0
	var regions: Dictionary = {}
	var cursor := 0.0
	for index in range(5):
		var region_end := cursor + region_width
		regions["region_%d" % index] = _rect(cursor, 0.0, region_end, domain.size.y)
		cursor = region_end + (gap_width if index < 4 else 0.0)
	var total_gap_area := 0.0
	var all_gaps_sub_epsilon := true
	for index in range(4):
		var left_region: PackedVector2Array = regions["region_%d" % index]
		var right_region: PackedVector2Array = regions["region_%d" % (index + 1)]
		var actual_gap := right_region[0].x - left_region[1].x
		all_gaps_sub_epsilon = all_gaps_sub_epsilon and actual_gap > 0.0 and actual_gap < 1.0e-7
		total_gap_area += actual_gap * domain.size.y
	var area_tolerance := maxf(0.00001, domain.size.x * domain.size.y * 0.000001)
	print("SUB_EPSILON_FIXTURE: widths=%s total_gap_area=%.9f area_tolerance=%.9f" % [str([
		regions["region_1"][0].x - regions["region_0"][1].x,
		regions["region_2"][0].x - regions["region_1"][1].x,
		regions["region_3"][0].x - regions["region_2"][1].x,
		regions["region_4"][0].x - regions["region_3"][1].x,
	]), total_gap_area, area_tolerance])
	_check(all_gaps_sub_epsilon, "fixture contains four positive gaps narrower than arrangement epsilon")
	_check(total_gap_area > area_tolerance, "fixture missing area exceeds configured coverage tolerance")
	_expect_error_for_bounds(regions, domain, "coverage gap", "sub-epsilon gaps are rejected by coverage validation")


func _test_close_distinct_partition() -> void:
	var domain := Rect2(Vector2.ZERO, Vector2(0.05, 1000.0))
	var regions := {
		"left": _rect(0.0, 0.0, 0.01, domain.size.y),
		"right": _rect(0.01000003, 0.0, domain.size.x, domain.size.y),
	}
	_check(Geometry.validate_regions(regions, domain).is_empty(), "distinct boundaries 3e-8 apart preserve the below-tolerance valid layout")


func _test_large_coordinate_midpoint_gap() -> void:
	var domain := Rect2(Vector2(16777216.0, 0.0), Vector2(8.0, 1000.0))
	var regions := {
		"a": _rect(16777216.0, 0.0, 16777218.0, 1000.0),
		"b": _rect(16777220.0, 0.0, 16777224.0, 1000.0),
	}
	var actual_gap_area: float = (regions["b"][0].x - regions["a"][1].x) * domain.size.y
	var errors := Geometry.validate_regions(regions, domain)
	_check(actual_gap_area == 2000.0, "large-coordinate regression fixture has the reported 2000-unit gap")
	_check(_has_error(errors, "coverage gap"), "large-coordinate midpoint rounding no longer hides an over-tolerance gap")


func _test_below_tolerance_gap() -> void:
	var domain := Rect2(Vector2.ZERO, Vector2(0.05, 1000.0))
	var regions := {
		"left": _rect(0.0, 0.0, 0.02, domain.size.y),
		"right": _rect(0.02000003, 0.0, domain.size.x, domain.size.y),
	}
	var area_tolerance := maxf(0.00001, domain.size.x * domain.size.y * 0.000001)
	var actual_gap_area: float = (regions["right"][0].x - regions["left"][1].x) * domain.size.y
	_check(actual_gap_area < area_tolerance and Geometry.validate_regions(regions, domain).is_empty(), "a positive gap below the documented area tolerance is intentionally accepted")


func _test_invalid_polygons() -> void:
	_expect_error({"bowtie": PackedVector2Array([Vector2(0, 0), Vector2(10, 10), Vector2(0, 10), Vector2(10, 0)])}, "self-intersects", "self-intersecting polygon is rejected")
	_expect_error({"empty": PackedVector2Array()}, "at least 3 vertices", "empty polygon is rejected")
	_expect_error({"point": PackedVector2Array([Vector2.ZERO])}, "at least 3 vertices", "one-vertex polygon is rejected")
	_expect_error({"line": PackedVector2Array([Vector2.ZERO, Vector2.RIGHT])}, "at least 3 vertices", "two-vertex polygon is rejected")
	_expect_error({"flat": PackedVector2Array([Vector2(0, 0), Vector2(5, 0), Vector2(10, 0)])}, "zero or negligible area", "collinear polygon is rejected")
	_expect_error({"repeat_close": PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10), Vector2(0, 0)])}, "duplicate or near-zero edge", "repeated closing vertex is rejected explicitly")
	_expect_error({"near_edge": PackedVector2Array([Vector2(0, 0), Vector2(0.0002, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])}, "duplicate or near-zero edge", "near-zero edge is rejected")
	_expect_error({"malformed": [Vector2.ZERO, "bad", Vector2.ONE]}, "at least 3 vertices", "malformed vertex data is rejected")
	_expect_error({"nonfinite": PackedVector2Array([Vector2(0, 0), Vector2(INF, 0), Vector2(0, 10)])}, "non-finite vertex", "non-finite coordinate is rejected")
	_check(Geometry.validate_regions({"clockwise": PackedVector2Array([Vector2(0, 0), Vector2(0, 10), Vector2(10, 10), Vector2(10, 0)])}, DOMAIN).is_empty(), "valid clockwise winding is accepted")


func _test_shared_boundaries() -> void:
	var a := _rect(0.0, 0.0, 5.0, 10.0)
	var b := _rect(5.0, 0.0, 10.0, 10.0)
	var matching := Geometry.calculate_geometric_neighbors({"a": a, "b": b})
	_check(matching.a == ["b"] and matching.b == ["a"], "identical shared-edge endpoints yield symmetric neighbors")
	var subdivided := PackedVector2Array([Vector2(5, 0), Vector2(10, 0), Vector2(10, 10), Vector2(5, 10), Vector2(5, 5)])
	var split_result := Geometry.calculate_geometric_neighbors({"a": a, "b": subdivided})
	_check(split_result.a == ["b"] and split_result.b == ["a"], "one side's collinear subdivided edge is detected")
	var vertex_touch := {
		"a": PackedVector2Array([Vector2(0, 0), Vector2(5, 0), Vector2(5, 5), Vector2(0, 5)]),
		"b": PackedVector2Array([Vector2(5, 5), Vector2(10, 5), Vector2(10, 10), Vector2(5, 10)]),
	}
	_check(Geometry.calculate_geometric_neighbors(vertex_touch).a.is_empty(), "single shared vertex is not an adjacency edge")
	var near_parallel := {"a": _rect(0.0, 0.0, 5.0, 10.0), "b": _rect(5.005, 0.0, 10.0, 10.0)}
	_check(Geometry.calculate_geometric_neighbors(near_parallel).a.is_empty(), "nearby distinct parallel edges beyond coordinate tolerance are not neighbors")
	var tolerated_drift := {"a": _rect(0.0, 0.0, 5.0, 10.0), "b": _rect(5.0005, 0.0, 10.0, 10.0)}
	_check(Geometry.calculate_geometric_neighbors(tolerated_drift).a == ["b"], "shared boundary drift within documented coordinate tolerance is detected")


func _test_neighbor_diagnostics() -> void:
	var regions := {"a": _rect(0.0, 0.0, 5.0, 10.0), "b": _rect(5.0, 0.0, 10.0, 10.0)}
	var geometric := Geometry.calculate_geometric_neighbors(regions)
	var matching := Geometry.compare_neighbors(geometric, {"a": ["b"], "b": ["a"]})
	_check(matching.missing_declarations.is_empty() and matching.explicit_without_geometric_contact.is_empty() and matching.invalid_references.is_empty(), "explicit neighbors matching geometry produce no conflicts")
	var contradictory := Geometry.compare_neighbors(geometric, {"a": [], "b": []})
	_check(contradictory.missing_declarations == ["a -> b", "b -> a"], "omitted physical neighbors are reported as missing declarations")
	var false_claim := Geometry.compare_neighbors({"a": [], "b": []}, {"a": ["b"], "b": ["a"]})
	_check(false_claim.explicit_without_geometric_contact == ["a -> b", "b -> a"], "explicit gameplay adjacency without geometric contact is reported")
	_check(Geometry.calculate_geometric_neighbors(regions)["a"] == ["b"], "geometric candidates remain separate and do not mutate authored neighbors")


func _test_generator_determinism_and_inputs() -> void:
	var ids := ["terr_alpha", "terr_beta", "terr_gamma", "terr_delta"]
	var first := Geometry.generate_voronoi(ids, DOMAIN, 92817)
	var same := Geometry.generate_voronoi(ids.duplicate(), DOMAIN, 92817)
	_check(first.ok, "seeded Voronoi output validates as a partition")
	_check(first.regions == same.regions, "same seed and normalized inputs reproduce identical polygons")
	var reversed_ids := ids.duplicate()
	reversed_ids.reverse()
	var reordered := Geometry.generate_voronoi(reversed_ids, DOMAIN, 92817)
	_check(first.regions == reordered.regions and first.sites == reordered.sites, "reordered IDs preserve stable ID-to-region assignments")
	var varied := Geometry.generate_voronoi(ids, DOMAIN, 92818)
	_check(first.regions != varied.regions, "different seeds vary a multi-region layout")
	_check(Geometry.validate_regions(first.regions, DOMAIN).is_empty(), "generated regions stay within bounds and form a valid partition")
	_check(not Geometry.generate_voronoi(["a", "a"], DOMAIN, 1).ok, "duplicate territory IDs are rejected")
	_expect_generation_error(["  ", "a"], DOMAIN, "non-empty strings", "blank territory ID is rejected")
	_expect_generation_error([4, "a"], DOMAIN, "must be strings", "non-string territory ID is rejected")
	_expect_generation_error([], DOMAIN, "at least one territory", "zero territory count is rejected")
	_expect_generation_error(["a"], Rect2(Vector2.ZERO, Vector2(0, 10)), "positive width", "zero-width bounds are rejected")
	_expect_generation_error(["a"], Rect2(Vector2(INF, 0), Vector2(10, 10)), "finite", "non-finite bounds are rejected")


func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


func _expect_error(regions: Dictionary, fragment: String, label: String) -> void:
	var errors := Geometry.validate_regions(regions, DOMAIN)
	_check(_has_error(errors, fragment), label)


func _expect_error_for_bounds(regions: Dictionary, bounds: Rect2, fragment: String, label: String) -> void:
	var errors := Geometry.validate_regions(regions, bounds)
	_check(_has_error(errors, fragment), label)


func _expect_generation_error(ids: Array, bounds: Rect2, fragment: String, label: String) -> void:
	var result := Geometry.generate_voronoi(ids, bounds, 9)
	_check(not result.ok and _has_error(result.errors, fragment), label)


func _has_error(errors: Array, fragment: String) -> bool:
	for error in errors:
		if str(error).contains(fragment):
			return true
	return false


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("TERRITORY GEOMETRY OK: " + label)
	else:
		_fails += 1
		printerr("TERRITORY GEOMETRY FAIL: " + label)
