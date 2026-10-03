extends Node
## COMBAT GEOMETRY CLOSURE VERIFY (Phase 2F)
##
## Proves variant combat geometry resolves through FrameVariantData/Resolver:
##  A. Muzzle fallbacks derive from variant rest; mounted muzzles stay
##     authoritative (model-authored markers untouched).
##  B. Melee invariant range_distance == lunge + reach holds per weapon and
##     per variant (reach grows only by measured arm delta; lunge shrinks).
##  C. Capsule per variant; hitbox sphere intentionally invariant (gameplay
##     abstraction, documented).
##  D. Enemy/ally dummies resolve heavy/extended through the same resolver
##     (no duplicated tables); Standard dummies byte-unchanged.

const STOCK := {
	"blade": "res://resources/mech/stock/weapon_heat_blade.tres",
	"knife": "res://resources/mech/stock/weapon_combat_knife.tres",
	"mace": "res://resources/mech/stock/weapon_mace.tres",
	"pile": "res://resources/mech/stock/weapon_pile_bunker.tres",
	"rifle": "res://resources/mech/stock/weapon_beam_rifle.tres",
}

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("GEOCLOSE OK: " + name)
	else:
		_fails += 1
		printerr("GEOCLOSE FAIL: " + name)


func _freeze(n: Node) -> void:
	n.set_process(false)
	n.set_physics_process(false)
	for c in n.get_children():
		_freeze(c)


func _variant_mech(vid: String) -> Node3D:
	var scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mech: Node3D = scene.instantiate()
	if vid != "standard":
		FrameVariantResolver.apply_variant(mech, vid)
	_freeze(mech)
	add_child(mech)
	_freeze(mech)
	return mech


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await _test_muzzle_fallback()
	await _test_fallback_routing()
	await _test_melee_invariant()
	await _test_collision_envelope()
	await _test_dummy_geometry()
	print("COMBAT_GEOMETRY_CLOSURE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("COMBAT_GEOMETRY_CLOSURE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_COMBAT_GEOMETRY_CLOSURE_TESTS_PASSED")
		get_tree().quit(0)


# --- A. muzzle fallback ---------------------------------------------------------
func _test_muzzle_fallback() -> void:
	var std_m := _variant_mech("standard")
	var hvy_m := _variant_mech("heavy")
	var ext_m := _variant_mech("extended")
	await get_tree().process_frame
	# Standard reproduces the legacy design points exactly.
	_check(FrameVariantResolver.hand_fallback_for(std_m, "left").distance_to(Vector3(-0.65, 1.4, -1.1)) < 0.001, "standard hand fallback == legacy (-0.65,1.4,-1.1)")
	_check(FrameVariantResolver.hand_fallback_for(std_m, "right").distance_to(Vector3(0.65, 1.4, -1.1)) < 0.001, "standard hand fallback mirrored")
	_check(FrameVariantResolver.shoulder_fallback_for(std_m, "left").distance_to(Vector3(-1.1424, 4.511, 0)) < 0.0001, "standard shoulder fallback == SHOULDER_LEFT_POS")
	# Heavy / Extended derive from variant rest (independently computed values).
	_check(FrameVariantResolver.hand_fallback_for(hvy_m, "left").distance_to(Vector3(-0.7397, 1.5395, -1.1)) < 0.002, "heavy hand fallback derived (%.4f)" % FrameVariantResolver.hand_fallback_for(hvy_m, "left").x)
	_check(FrameVariantResolver.shoulder_fallback_for(hvy_m, "left").distance_to(Vector3(-1.30, 4.86, 0)) < 0.0001, "heavy shoulder fallback == arm rest + mount")
	_check(FrameVariantResolver.hand_fallback_for(ext_m, "left").distance_to(Vector3(-0.65, 1.6453, -1.1)) < 0.002, "extended hand fallback derived")
	_check(FrameVariantResolver.shoulder_fallback_for(ext_m, "right").distance_to(Vector3(1.1424, 5.037, 0)) < 0.0001, "extended shoulder fallback == arm rest + mount")
	# Mounted visual muzzle stays authoritative (model marker, not fallback).
	var rifle: WeaponPart = load(STOCK["rifle"])
	var mount = WeaponVisualFactory.mount_hand(std_m, "right", rifle, "GeoRifle")
	var muzzle := WeaponVisualFactory.find_muzzle_node(mount)
	_check(muzzle != null, "mounted rifle exposes model muzzle marker")
	if muzzle != null:
		_check((muzzle as Node3D).global_position.distance_to(FrameVariantResolver.hand_fallback_for(std_m, "right")) > 0.5, "mounted muzzle != fallback (marker authoritative)")
	for m in [std_m, hvy_m, ext_m]:
		(m as Node3D).queue_free()
	await get_tree().process_frame


# --- A2. no duplicated Standard geometry in fallback paths -------------------------
# Structural proof: INF-only fire/smoke/salvo/jam fallbacks resolve through
# the resolver. The only remaining literal offsets are the intentional
# receiver/breach presentation points (jam sparks + pile casing: ±0.6,
# 1.5, 0.5), documented as frame-independent by design.
func _test_fallback_routing() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/mecha/weapon_manager.gd")
	_check(not src.is_empty(), "weapon_manager source readable")
	_check(src.find("shoulder_mount_position(") < 0, "no shoulder_mount_position fallback remains")
	_check(src.find("0.65, 1.4, -1.1") < 0 and src.find("-0.65, 1.4, -1.1") < 0, "no legacy hand-fire fallback literal remains")
	_check(src.find("FrameVariantResolver.shoulder_fallback_for") > 0, "shoulder INF paths route via resolver")
	_check(src.find("FrameVariantResolver.hand_fallback_for") > 0, "hand INF paths route via resolver")
	_check(src.find("0.6, 1.5, 0.5") > 0, "intentional jam/casing presentation point preserved (not migrated)")


# --- B. melee invariant --------------------------------------------------------------
func _test_melee_invariant() -> void:
	var weapons := {}
	for k in STOCK:
		weapons[k] = load(STOCK[k])
		_check(weapons[k] != null, "stock loads: " + k)
	var fist := WeaponPart.new()
	fist.weapon_name = "Bare Fist"
	fist.weapon_type = WeaponPart.WeaponType.MELEE
	fist.range_distance = 3.0
	weapons["fist"] = fist
	# Standard lunge values are the long-documented ones (parity). Manager lives
	# in-tree like melee_sync_verify (its _ready needs the scene tree).
	var wm = Node3D.new()
	wm.set_script(load("res://scripts/mecha/weapon_manager.gd"))
	add_child(wm)
	await get_tree().process_frame
	_check(absf(float(wm._melee_lunge_dist(weapons["blade"])) - 3.6) < 0.01, "standard blade lunge 3.6")
	_check(absf(float(wm._melee_lunge_dist(weapons["knife"])) - 2.6) < 0.01, "standard knife lunge 2.6")
	_check(absf(float(wm._melee_lunge_dist(weapons["mace"])) - 3.4) < 0.01, "standard mace lunge 3.4")
	_check(absf(float(wm._melee_lunge_dist(weapons["pile"])) - 4.4) < 0.01, "standard pile lunge 4.4")
	wm.queue_free()
	await get_tree().process_frame
	# Per variant, through REAL manager nodes parented to variant mechs
	# (same pattern as melee_sync_verify; process-local side effects only):
	# range == lunge + reach, with reach grown only by measured arm delta.
	for vid in ["standard", "heavy", "extended"]:
		var mech := _variant_mech(vid)
		var wmn = Node3D.new()
		wmn.set_script(load("res://scripts/mecha/weapon_manager.gd"))
		wmn.name = "WeaponManager"
		mech.add_child(wmn)
		await get_tree().process_frame
		var reach: float = FrameVariantResolver.melee_hit_reach_for(mech)
		for k in ["blade", "knife", "mace", "pile", "fist"]:
			var w: WeaponPart = weapons[k]
			var lunge: float = float(wmn._melee_lunge_dist(w))
			_check(absf(lunge - maxf(float(w.range_distance) - reach, 0.9)) < 0.01, "%s %s: manager lunge uses variant reach" % [vid, k])
			_check(absf(lunge + reach - float(w.range_distance)) < 0.01, "%s %s: range %.1f == lunge %.3f + reach %.4f" % [vid, k, float(w.range_distance), lunge, reach])
		print("GEOCLOSE %s reach=%.4f blade-lunge=%.4f" % [vid, reach, maxf(5.2 - reach, 0.9)])
		mech.queue_free()
		await get_tree().process_frame
	# No double scaling: reach component check (arm delta only, x1 application).
	var std_r: float = FrameVariantResolver.melee_hit_reach_for(_variant_mech("standard"))
	_check(absf(std_r - 1.6) < 0.0001, "standard reach exactly 1.6 (zero arm delta)")


# --- C. collision envelope -----------------------------------------------------------------
func _test_collision_envelope() -> void:
	var expect := {
		"standard": [5.5, 1.05, 2.75],
		"heavy": [5.9, 1.15, 2.95],
		"extended": [6.1, 1.05, 3.05],
	}
	var shapes := {}
	for vid in ["standard", "heavy", "extended"]:
		var mech := _variant_mech(vid)
		await get_tree().process_frame
		var col := mech.get_node_or_null("CollisionShape3D") as CollisionShape3D
		_check(col != null and col.shape is CapsuleShape3D, vid + " capsule present")
		if col != null:
			shapes[vid] = col.shape
			_check(absf((col.shape as CapsuleShape3D).height - expect[vid][0]) < 0.0001, "%s capsule h=%.1f" % [vid, expect[vid][0]])
			_check(absf((col.shape as CapsuleShape3D).radius - expect[vid][1]) < 0.0001, "%s capsule r=%.2f" % [vid, expect[vid][1]])
			_check(absf(col.position.y - expect[vid][2]) < 0.0001, "%s capsule centered (%.2f)" % [vid, expect[vid][2]])
		# Hitbox sphere: intentional gameplay abstraction, invariant by design.
		var hb := mech.get_node_or_null("Hitbox/HitboxShape") as CollisionShape3D
		_check(hb != null and hb.shape is SphereShape3D and absf((hb.shape as SphereShape3D).radius - 2.688) < 0.0001, vid + " hitbox sphere r=2.688 unchanged")
		mech.queue_free()
		await get_tree().process_frame
	_check(shapes.get("standard") != shapes.get("heavy") and shapes.get("heavy") != shapes.get("extended"), "capsule shapes duplicated per instance (no shared-subresource leak)")


# --- D. enemy / ally dummy geometry ----------------------------------------------------------------
func _dummy_variant_probe(scene_path: String, kind: String) -> void:
	var scene: PackedScene = load(scene_path)
	_check(scene != null and scene.can_instantiate(), kind + " dummy scene loads")
	if kind == "ally":
		await _ally_variant_probe()
		return
	# Enemy: full _ready flow (variant set pre-tree, like a spawner).
	var std_d: Node3D = scene.instantiate()
	add_child(std_d)
	await get_tree().process_frame
	await get_tree().process_frame
	var arm_s := (std_d.get_node_or_null("ArmLeft") as Node3D).position if std_d.get_node_or_null("ArmLeft") else Vector3(999, 999, 999)
	_check((arm_s as Vector3).is_equal_approx(Vector3(-1.1424, 4.261, 0)), kind + " standard ArmLeft untouched (-1.1424,4.261,0)")
	std_d.queue_free()
	await get_tree().process_frame
	for vid in ["heavy", "extended"]:
		var d: Node3D = scene.instantiate()
		d.set("frame_variant", vid)
		add_child(d)
		await get_tree().process_frame
		await get_tree().process_frame
		_check_dummy_variant(d, kind, vid)
		d.queue_free()
		await get_tree().process_frame


# Ally flow is spawner-driven (apply_mech_loadout -> _build_catalog_body):
# variant set before the loadout, mirroring production order.
func _ally_variant_probe() -> void:
	var scene: PackedScene = load("res://scenes/mecha/ally_dummy.tscn")
	var berth := {
		"id": "mech_geo",
		"parts": {}, "frames": {}, "damage": {}, "scrap_patches": {},
		"weapon_loadout": {"left": "", "right": "", "carry": []},
	}
	var std_a: Node3D = scene.instantiate()
	std_a.set("template_id", "ally_gm")
	add_child(std_a)
	std_a.apply_mech_loadout(berth)
	await get_tree().process_frame
	await get_tree().process_frame
	var arm_s := (std_a.get_node_or_null("ArmLeft") as Node3D).position if std_a.get_node_or_null("ArmLeft") else Vector3(999, 999, 999)
	_check((arm_s as Vector3).is_equal_approx(Vector3(-1.14, 3.444, 0)), "ally standard ArmLeft keeps tscn placeholder (-1.14,3.444,0)")
	std_a.queue_free()
	await get_tree().process_frame
	for vid in ["heavy", "extended"]:
		var a: Node3D = scene.instantiate()
		a.set("template_id", "ally_gm")
		a.set("frame_variant", vid)
		add_child(a)
		a.apply_mech_loadout(berth.duplicate(true))
		await get_tree().process_frame
		await get_tree().process_frame
		_check_dummy_variant(a, "ally", vid)
		a.queue_free()
		await get_tree().process_frame


func _check_dummy_variant(d: Node3D, kind: String, vid: String) -> void:
	var a := (d.get_node_or_null("ArmLeft") as Node3D).position if d.get_node_or_null("ArmLeft") else Vector3(999, 999, 999)
	var want: Vector3 = (FrameVariantData.get_variant(vid)["rest"] as Dictionary)["ArmLeft"]
	_check((a as Vector3).is_equal_approx(want), kind + " " + vid + " ArmLeft from shared resolver data")
	var col := d.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var want_h: float = float((FrameVariantData.get_variant(vid)["body"] as Dictionary)["capsule_h"])
	_check(col != null and col.shape is CapsuleShape3D and absf((col.shape as CapsuleShape3D).height - want_h) < 0.01, kind + " " + vid + " capsule h=%.1f via resolver" % want_h)


func _test_dummy_geometry() -> void:
	await _dummy_variant_probe("res://scenes/mecha/ally_dummy.tscn", "ally")
	await _dummy_variant_probe("res://scenes/mecha/enemy_dummy.tscn", "enemy")
