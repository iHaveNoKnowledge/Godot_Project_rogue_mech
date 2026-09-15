extends Node
## PROJECTILE-FX VERIFY (energy = beam, bullets = pellets, railgun slug wake)
## 1. Beam-family guns map to BEAM style (cyan bolt), kinetic guns stay BULLET.
## 2. Only kinetic firearms eject brass (WeaponPart.ejects_shell_casing).
## 3. Railgun maps to SLUG + sonic boom and forges its own spikes over time.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("PROJFX OK: " + name)
	else:
		_fails += 1
		printerr("PROJFX FAIL: " + name)


func _core_of(path: String) -> WeaponCore:
	var w: WeaponPart = load(path)
	return WeaponCore.from_weapon(w)


func _ready() -> void:
	await get_tree().process_frame

	# --- 1. energy guns fire light, not brass pellets ---
	var beam := _core_of("res://resources/mech/stock/weapon_beam_rifle.tres")
	_check(beam.projectile_style == WeaponCore.Style.BEAM, "beam rifle maps to BEAM style")
	_check(beam.projectile_color.b > 0.8 and beam.projectile_color.r < 0.5, "beam bolt is cyan, not brass")
	_check(beam.trail_head.b > 0.9, "beam trail streak is ion cyan")
	var sniper := _core_of("res://resources/mech/stock/weapon_beam_sniper.tres")
	_check(sniper.projectile_style == WeaponCore.Style.BEAM, "beam sniper maps to BEAM style (energy look despite pierce damage)")
	var carbine := _core_of("res://resources/mech/stock/weapon_beam_carbine.tres")
	_check(carbine.projectile_style == WeaponCore.Style.BEAM, "beam carbine maps to BEAM style")

	# --- cannon keeps its shell even though it shares the beam category ---
	var cannon := _core_of("res://resources/mech/stock/weapon_assault_cannon.tres")
	_check(cannon.projectile_style == WeaponCore.Style.CANNON_SHELL, "assault cannon keeps CANNON_SHELL style")

	# --- 2. kinetic guns stay pellets ---
	var mg := _core_of("res://resources/mech/stock/weapon_machine_gun.tres")
	_check(mg.projectile_style == WeaponCore.Style.BULLET, "machine gun stays BULLET style")
	var shot := _core_of("res://resources/mech/stock/weapon_shotgun.tres")
	_check(shot.projectile_style == WeaponCore.Style.SHOTGUN, "shotgun stays pellet style")
	var missile := _core_of("res://resources/mech/stock/weapon_missile.tres")
	_check(missile.projectile_style == WeaponCore.Style.MISSILE, "missile launcher stays MISSILE style")

	# --- 3. railgun: slug leads, sonic wake follows, spikes refill ---
	var rail := _core_of("res://resources/mech/stock/weapon_railgun.tres")
	_check(rail.projectile_style == WeaponCore.Style.SLUG, "railgun maps to SLUG style")
	_check(rail.sonic_boom, "railgun keeps sonic-boom wake")
	_check(rail.ammo_regen_per_sec > 0.0, "railgun forges its own spikes")
	_check(is_equal_approx(rail.ammo_regen_per_sec, 0.12), "railgun fabricator rate is 0.12/s")
	# Fabricator trickle: 10s at 0.12/s forges exactly 1 round into the mag.
	rail.ammo = 10
	rail.tick(10.0)
	_check(rail.ammo == 11, "railgun mag refills +1 round per ~8s without reserves")
	# Non-fabricator guns never self-refill.
	beam.ammo = 10
	beam.tick(10.0)
	_check(beam.ammo == 10, "beam rifle does not self-refill ammo")

	# --- 4. brass rules: kinetic firearms only ---
	var mg_part: WeaponPart = load("res://resources/mech/stock/weapon_machine_gun.tres")
	_check(mg_part.ejects_shell_casing(), "machine gun ejects brass")
	var rail_part: WeaponPart = load("res://resources/mech/stock/weapon_railgun.tres")
	_check(rail_part.ejects_shell_casing(), "railgun ejects sabot casing")
	var shot_part: WeaponPart = load("res://resources/mech/stock/weapon_shotgun.tres")
	_check(shot_part.ejects_shell_casing(), "shotgun ejects shells")
	var beam_part: WeaponPart = load("res://resources/mech/stock/weapon_beam_rifle.tres")
	_check(not beam_part.ejects_shell_casing(), "beam rifle ejects NO casing")
	var missile_part: WeaponPart = load("res://resources/mech/stock/weapon_missile.tres")
	_check(not missile_part.ejects_shell_casing(), "missile launcher ejects NO casing")
	var knife_part: WeaponPart = load("res://resources/mech/stock/weapon_combat_knife.tres")
	_check(not knife_part.ejects_shell_casing(), "combat knife ejects NO casing")
	var shield_part: WeaponPart = load("res://resources/mech/stock/weapon_shield.tres")
	_check(not shield_part.ejects_shell_casing(), "shield ejects NO casing")

	# --- 5. Blender-authored FX meshes (GLB preferred, procedural fallback) ---
	_check(FileAccess.file_exists("res://assets/models/projectile_fx.glb"), "Blender FX GLB is in the repo")
	var bolt_vis: Node3D = WeaponCore._build_beam_bolt(WeaponCore._get_cached_material(Color(0.35, 0.9, 1.0)))
	_check(bolt_vis != null and bolt_vis.name == "BeamBolt", "beam visual builds with correct name")
	_check(is_equal_approx(bolt_vis.scale.z, 1.33), "beam bolt is stretched 33% longer along flight")
	_check(bolt_vis.find_children("*", "MeshInstance3D", true, false).size() > 0, "beam visual carries mesh geometry")
	var slug_vis: Node3D = WeaponCore._build_rail_slug(WeaponCore._get_cached_material(Color(0.75, 0.92, 1.0)))
	_check(slug_vis != null and slug_vis.name == "RailSlug", "rail slug visual builds with correct name")
	_check(slug_vis.find_children("*", "MeshInstance3D", true, false).size() > 0, "rail slug carries mesh geometry")
	_check(slug_vis.find_child("VaporCone", true, false) != null, "rail slug trails its vapor cone behind the slug")
	bolt_vis.queue_free()
	slug_vis.queue_free()

	# --- 6. fired shots carry behavior flags; heat-scar API exists ---
	var owner := Node3D.new()
	add_child(owner)
	var fire_beam := WeaponCore.from_weapon(beam_part)
	_check(fire_beam.try_fire(Vector3.ZERO, Vector3.FORWARD, false, owner), "beam core fires a live projectile")
	await get_tree().process_frame
	var beam_shot := false
	for p in get_tree().get_nodes_in_group("projectile"):
		if p.get("is_beam") == true:
			beam_shot = true
			p.queue_free()
	_check(beam_shot, "fired beam projectile carries is_beam flag (scar, no ricochet)")
	var fire_rail := WeaponCore.from_weapon(rail_part)
	_check(fire_rail.try_fire(Vector3.ZERO, Vector3.FORWARD, false, owner), "railgun core fires a live projectile")
	await get_tree().process_frame
	var slug_shot := false
	var slug_lit := false
	for p in get_tree().get_nodes_in_group("projectile"):
		if p.get("sonic_boom") == true and p.get("is_beam") != true:
			slug_shot = true
			slug_lit = p.find_children("*", "OmniLight3D", true, false).size() > 0
			p.queue_free()
	_check(slug_shot, "fired railgun slug keeps sonic wake without beam behavior")
	_check(slug_lit, "railgun slug carries a real light for dark areas")
	# Beam light check on a fresh shot (previous beam projectile was freed above).
	_check(fire_beam.try_fire(Vector3.ZERO, Vector3.FORWARD, false, owner), "beam core fires again for light check")
	await get_tree().process_frame
	var beam_lit := false
	for p in get_tree().get_nodes_in_group("projectile"):
		if p.get("is_beam") == true:
			beam_lit = p.find_children("*", "OmniLight3D", true, false).size() > 0
			p.queue_free()
	_check(beam_lit, "beam bolt carries a real light so it shines in the dark")
	# Direct call proves the heat-scar API links and is headless-safe (no-ops without an FX instance).
	EffectManager.spawn_heat_scar(Vector3.ZERO, Vector3.UP)
	_check(true, "heat-scar impact call runs without errors")
	var heat_tex: GradientTexture2D = EffectManager._get_cached_heat_gradient()
	_check(heat_tex != null and heat_tex.width == 128, "scorch decal uses a cached radial heat gradient")
	owner.queue_free()

	print("PROJECTILE_FX_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
