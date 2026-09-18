class_name WeaponCore
extends RefCounted

const PartPenaltySystem = preload("res://scripts/systems/part_penalty_system.gd")

## Shared weapon firing core. Owns the firing mechanics (cooldown, ammo, reload,
## heat/overheat) plus projectile spawning, so the player's WeaponManager and
## enemy/ally AI all drive the SAME rules. The caller only supplies where the
## shot comes from, which direction it flies, and who owns the projectile.
##
## Two ways to build:
##   WeaponCore.from_weapon(weapon: WeaponPart)  -> player loadout weapons
##   WeaponCore.from_stats(stats: Dictionary)    -> enemy/ally archetype stats
##
## Reload behavior:
##   - `auto_reload` (enemies): ticks finish the reload on their own.
##   - Player: begin_reload()/complete_reload() driven by the WeaponManager so
##     the battle-reserve economy and the animated reload HUD stay intact.
##     `manual_reload` prevents tick() from auto-completing the player's reload
##     (the manager finishes it at the exact end of its animation).

signal ammo_changed(current: int, max_ammo: int)
signal heat_changed(current: float, max_heat: float, overheated: bool)
signal fired

## Projectile look: BULLET = brass pellet (kinetic firearms), BEAM = energy
## bolt (beam rifles/carbines/snipers), SLUG = hypervelocity railgun rod with
## a trailing vapor cone, MISSILE / SHOTGUN / ORB / CANNON_SHELL as before.
## (BEAM/SLUG appended last so existing int values never shift.)
enum Style { BULLET, MISSILE, SHOTGUN, ORB, CANNON_SHELL, BEAM, SLUG }

## Projectile mesh variety (player loadout uses BULLET/MISSILE/SHOTGUN/CANNON_SHELL; enemy
## grunts and allied dummies use ORB to keep their silhouette readable).
var projectile_style: int = Style.ORB
var projectile_color: Color = Color(1, 0.8, 0.2)
var trail_head: Color = Color(1, 0.8, 0.3, 0.9)
var trail_fade: Color = Color(1, 0.7, 0.2)
# Railgun rounds leave a sonic-boom shockwave ring along their flight path.
var sonic_boom: bool = false
var explosion_radius: float = 0.0

# --- Firing config ---
var fire_interval: float = 0.2
var damage: float = 25.0
# Per-instance upgrade bonus applied to spawned projectiles (hangar weapon
# upgrades raise this; enemies / fresh pickups stay at 1.0).
var damage_multiplier: float = 1.0
var projectile_speed: float = 50.0
var damage_type: String = "kinetic"
var impact: float = 0.0
var spread: float = 0.0
var pellets: int = 1
var drop_gravity: float = 0.0

# --- Ammo config ---
var ammo_per_shot: int = 1
var max_ammo: int = 100
var unlimited_ammo: bool = false
var reload_time: float = 1.0
var auto_reload: bool = true
var manual_reload: bool = false
## Onboard fabricator trickle (rounds/sec into the magazine, 0 = off).
var ammo_regen_per_sec: float = 0.0
var ammo_regen_accum: float = 0.0

# --- Heat config (heat_capacity > 0 enables the system) ---
var heat_capacity: float = 0.0
var max_heat: float:
	get: return heat_capacity
	set(val): heat_capacity = val
var heat_per_shot: float = 0.0
var heat_cool_rate: float = 10.0
var heat_release_ratio: float = 0.5

# --- Live state ---
var ammo: int = 0
var cooldown: float = 0.0
var heat: float = 0.0
var overheated: bool = false
var reloading: bool = false
var reload_timer: float = 0.0

## Optional ammo pool backing reloads. When set, complete_reload() draws from it
## instead of assuming an infinite mag refill (player battle reserve).
var reserve: int = 0


static func from_weapon(weapon: WeaponPart) -> WeaponCore:
	var core := WeaponCore.new()
	core.fire_interval = weapon.get_fire_interval()
	core.damage = weapon.damage
	core.projectile_speed = weapon.projectile_speed
	core.impact = weapon.impact
	core.spread = weapon.spread
	core.ammo_per_shot = weapon.ammo_per_shot
	core.max_ammo = weapon.max_ammo
	core.reload_time = weapon.reload_time
	core.ammo_regen_per_sec = weapon.ammo_regen_per_sec
	core.ammo_regen_accum = 0.0
	# Frame modules (cryo loop) widen the tank; per-shot/cooler bonuses
	# apply dynamically in _accumulate_heat()/_cool_heat() so mid-run
	# installs take effect without rebuilding the core.
	core.heat_capacity = weapon.heat_capacity * FrameModuleSystem.calculate_heat_capacity_multiplier()
	core.heat_per_shot = weapon.heat_per_shot
	core.heat_cool_rate = weapon.heat_cool_rate
	core.heat_release_ratio = weapon.heat_release_ratio
	core.ammo = weapon.max_ammo
	core.projectile_style = Style.BULLET
	core.projectile_color = Color(1, 0.8, 0.2)
	core.trail_head = Color(1, 0.8, 0.3, 0.9)
	core.trail_fade = Color(1, 0.7, 0.2)
	# The attack type (heat/pierce/blunt) is data on the weapon — the core just
	# carries it to the projectile so armor/shield defenses can match on it.
	core.damage_type = weapon.get_damage_type()
	var wname_lower := weapon.weapon_name.to_lower()
	if wname_lower.contains("cannon") or core.damage_type == "explosive":
		core.projectile_style = Style.CANNON_SHELL
		core.projectile_color = Color(1.0, 0.55, 0.15)
		core.explosion_radius = 4.2
		core.damage_type = "explosive"
	else:
		match weapon.weapon_type:
			WeaponPart.WeaponType.MISSILE:
				core.projectile_style = Style.MISSILE
			WeaponPart.WeaponType.SHOTGUN:
				core.projectile_style = Style.SHOTGUN
				core.pellets = 7
			WeaponPart.WeaponType.BEAM_RIFLE:
				# Energy guns fire coherent light, not brass: elongated cyan
				# bolt with a matching ion trail.
				core.projectile_style = Style.BEAM
				core.projectile_color = Color(0.35, 0.9, 1.0)
				core.trail_head = Color(0.4, 0.95, 1.0, 0.9)
				core.trail_fade = Color(0.2, 0.7, 1.0)
			WeaponPart.WeaponType.RAILGUN:
				# Railgun rounds are hypervelocity: solid pale slug up front
				# with a vapor-cone + shockwave-ring wake, no bullet drop sag.
				core.projectile_style = Style.SLUG
				core.projectile_color = Color(0.75, 0.92, 1.0)
				core.trail_head = Color(0.85, 0.95, 1.0, 0.9)
				core.trail_fade = Color(0.5, 0.8, 1.0)
				core.sonic_boom = true
	# Volley weapons (Swarm pods): one trigger pull launches N projectiles for
	# N rounds — never charge ammo that doesn't leave the barrel.
	core.pellets = maxi(core.pellets, weapon.projectiles_per_shot)
	return core


## Builds a core from enemy/ally stats (attack_damage, attack_cooldown,
## max_ammo, reload_time). Melee/support archetypes stay ammo-free via
## unlimited_ammo; ranged/heavy keep their finite magazine + auto reload.
static func from_stats(stats: Dictionary) -> WeaponCore:
	var core := WeaponCore.new()
	core.fire_interval = float(stats.get("attack_cooldown", 1.0))
	core.damage = float(stats.get("attack_damage", 10.0))
	core.projectile_speed = float(stats.get("projectile_speed", 30.0))
	core.max_ammo = int(stats.get("max_ammo", 0))
	core.ammo = core.max_ammo
	core.reserve = int(stats.get("reserve_ammo", -1))
	core.reload_time = float(stats.get("reload_time", 3.0))
	core.damage_type = str(stats.get("damage_type", "kinetic"))
	core.impact = float(stats.get("impact", 0.0))
	core.projectile_style = Style.ORB
	core.projectile_color = stats.get("projectile_color", Color(1, 0.8, 0.2))
	if stats.has("unlimited_ammo"):
		core.unlimited_ammo = bool(stats["unlimited_ammo"])
	else:
		core.unlimited_ammo = core.max_ammo <= 0 or core.reserve < 0
	core.auto_reload = not core.unlimited_ammo
	return core


func tick(delta: float) -> void:
	if cooldown > 0.0:
		cooldown = maxf(cooldown - delta, 0.0)

	if reloading:
		reload_timer -= delta
		if reload_timer <= 0.0 and not manual_reload:
			complete_reload()

	_regen_ammo(delta)
	_cool_heat(delta)


func can_fire() -> bool:
	if cooldown > 0.0 or reloading or overheated:
		return false
	if not unlimited_ammo and ammo < ammo_per_shot:
		return false
	return true


func is_completely_dry() -> bool:
	return not unlimited_ammo and ammo <= 0 and reserve <= 0


## Consumes the shot's cost (cooldown, ammo, heat) WITHOUT spawning a
## projectile. Used by melee weapons, where the caller runs its own lunge/hit
## animation but still obeys the shared weapon rules.
func consume_shot() -> bool:
	if not can_fire():
		return false
	var interval := fire_interval
	if heat_capacity > 0.0 and heat > 0.0:
		var heat_ratio := clampf(heat / heat_capacity, 0.0, 1.0)
		interval /= FrameModuleSystem.calculate_heat_fire_rate_multiplier(heat_ratio)
	cooldown = interval
	if not unlimited_ammo:
		ammo = maxi(ammo - ammo_per_shot, 0)
		ammo_changed.emit(ammo, max_ammo)
		if ammo <= 0 and auto_reload and (unlimited_ammo or reserve > 0):
			begin_reload()
	_accumulate_heat()
	fired.emit()
	return true


## Consumes a shot and spawns the projectile(s). Returns true when a shot was
## actually fired (ammo/heat/cooldown all consumed).
func try_fire(from_pos: Vector3, aim_dir: Vector3, fired_by_enemy: bool, owner: Node) -> bool:
	if not consume_shot():
		return false

	if fired_by_enemy and owner != null and owner.has_method("report_technology_observation"):
		owner.report_technology_observation("weapon_fired")


	# Dynamic heat spread (barrel thermal blooming): higher heat causes higher bullet dispersion.
	var current_spread := spread
	# GDD §6.1: Head damage increases weapon spread (HUD glitch / optics degraded)
	if not fired_by_enemy:
		current_spread += PartPenaltySystem.head_spread_penalty()
	if heat_capacity > 0.0 and heat > 0.0:
		var heat_ratio := clampf(heat / heat_capacity, 0.0, 1.0)
		# Spread increases progressively as barrel heats up (rewards burst-firing & cooling)
		# Reduced from 0.075 → 0.032 so sustained fire stays tighter (user report: bullets wild)
		current_spread += heat_ratio * 0.032

	# Player aim stabilization: tighten spread by 30% so bullets feel laser-straight.
	# Combined with chest-stable aim_dir (weapon_manager) this fixes “ยิงแล้วกระสุนมั่วเพราะแขนแกว่ง”.
	if not fired_by_enemy:
		current_spread *= 0.70

	for i in range(pellets):
		var pellet_dir := aim_dir
		if current_spread > 0.0:
			var up_vec := Vector3.UP if absf(aim_dir.y) < 0.9 else Vector3.RIGHT
			var right_vec := aim_dir.cross(up_vec).normalized()
			var true_up := right_vec.cross(aim_dir).normalized()
			var angle := randf_range(0.0, TAU)
			var radius := randf_range(0.0, current_spread)
			pellet_dir = (aim_dir + right_vec * (cos(angle) * radius) + true_up * (sin(angle) * radius)).normalized()
		_spawn_projectile(from_pos, pellet_dir, fired_by_enemy, owner)
	fired.emit()
	return true


func try_fire_homing(from_pos: Vector3, aim_dir: Vector3, target_node: Node3D, fired_by_enemy: bool = false, owner: Node = null, burst_spread: float = 0.25) -> bool:
	if not consume_shot():
		return false

	var launch_dir := aim_dir
	if burst_spread > 0.0:
		var up_vec := Vector3.UP if absf(aim_dir.y) < 0.9 else Vector3.RIGHT
		var right_vec := aim_dir.cross(up_vec).normalized()
		var true_up := right_vec.cross(aim_dir).normalized()
		var angle := randf_range(0.0, TAU)
		# Arc upward and outward slightly like Macross swarm missiles
		launch_dir = (aim_dir + right_vec * (cos(angle) * burst_spread) + true_up * (sin(angle) * burst_spread * 0.7 + 0.22)).normalized()

	_spawn_projectile(from_pos, launch_dir, fired_by_enemy, owner, target_node)
	fired.emit()
	return true


func begin_reload() -> bool:
	if reloading or max_ammo <= 0 or ammo >= max_ammo:
		return false
	if not unlimited_ammo and reserve <= 0:
		return false
	reloading = true
	reload_timer = reload_time
	return true


## Finishes a reload, drawing from `reserve` when set or refilling the
## whole magazine when unlimited. Returns the ammo refilled.
func complete_reload() -> int:
	if not reloading:
		return 0
	reloading = false
	reload_timer = 0.0
	var needed := max_ammo - ammo
	var refilled := 0
	if unlimited_ammo:
		refilled = needed
	elif reserve > 0:
		refilled = mini(needed, reserve)
		reserve -= refilled
	else:
		refilled = 0
	ammo += refilled
	ammo_changed.emit(ammo, max_ammo)
	return refilled


# --- Fabricator trickle (railgun spike printer) ---
func _regen_ammo(delta: float) -> void:
	if ammo_regen_per_sec <= 0.0 or unlimited_ammo or reloading:
		return
	if ammo >= max_ammo:
		ammo_regen_accum = 0.0
		return
	ammo_regen_accum += ammo_regen_per_sec * delta
	while ammo_regen_accum >= 1.0 and ammo < max_ammo:
		ammo_regen_accum -= 1.0
		ammo += 1
		ammo_changed.emit(ammo, max_ammo)
	if ammo >= max_ammo:
		ammo_regen_accum = 0.0


# --- Heat ---
func _accumulate_heat() -> void:
	if heat_capacity <= 0.0:
		return
	# GDD §4.3: Power Core class modifies heat accumulation
	var using_bio := false
	if GlobalData.has_method("fuel"):
		using_bio = GlobalData.fuel.is_mech_using_bio_fuel()
	var effective_heat = heat_per_shot * _PCS.heat_accumulation_multiplier("", using_bio)
	# GDD §6.1: Torso damage increases heat accumulation (easier overheat)
	effective_heat *= _PPS.total_heat_multiplier()
	# Frame modules (vent protocol) bleed heat off each shot.
	effective_heat *= FrameModuleSystem.calculate_heat_per_shot_multiplier()
	heat = minf(heat + effective_heat, heat_capacity)
	overheated = heat >= heat_capacity
	heat_changed.emit(heat, heat_capacity, overheated)


func _cool_heat(delta: float) -> void:
	if heat_capacity <= 0.0:
		return
	# GDD §4.3: Combustion core adds passive heat accumulation
	var passive = _PCS.passive_heat_rate()
	if passive > 0.0:
		heat = minf(heat + passive * delta, heat_capacity)
	# Tactical Smog: heat cool rate x0.5 — chemical smoke traps heat in the barrel.
	var cool_rate := heat_cool_rate * FrameModuleSystem.calculate_heat_cool_rate_multiplier()
	if GlobalData.board.current_hazard == GlobalData.HAZARD_TACTICAL_SMOG:
		cool_rate *= GlobalData.SMOG_HEAT_COOL_PENALTY
	var cooled := maxf(heat - cool_rate * delta, 0.0)
	if overheated and cooled <= heat_capacity * heat_release_ratio:
		overheated = false
	heat = cooled
	heat_changed.emit(heat, heat_capacity, overheated)


func get_heat_percent() -> float:
	if heat_capacity <= 0.0:
		return 0.0
	return heat / heat_capacity


func is_overheated() -> bool:
	return overheated


const PROJ_SCRIPT = preload("res://scripts/systems/projectile.gd")
const _PCS = preload("res://scripts/systems/power_core_system.gd")
const _PPS = preload("res://scripts/systems/part_penalty_system.gd")

static var _cached_shapes: Dictionary = {}
static var _cached_meshes: Dictionary = {}
static var _cached_materials: Dictionary = {}

static func _get_cached_shape() -> SphereShape3D:
	if not _cached_shapes.has("sphere"):
		var shape := SphereShape3D.new()
		shape.radius = 0.1
		_cached_shapes["sphere"] = shape
	return _cached_shapes["sphere"]

static func _get_cached_mesh(style: int) -> Mesh:
	if _cached_meshes.has(style):
		return _cached_meshes[style]
	var m: Mesh
	match style:
		Style.MISSILE:
			var box := BoxMesh.new()
			box.size = Vector3(0.1, 0.1, 0.4)
			m = box
		Style.SHOTGUN:
			var pellet := CapsuleMesh.new()
			pellet.radius = 0.02
			pellet.height = 0.15
			m = pellet
		Style.CANNON_SHELL:
			# Heavy 120mm Tungsten-HE Autocannon Shell (large luminous round)
			var shell := CapsuleMesh.new()
			shell.radius = 0.08
			shell.height = 0.45
			m = shell
		Style.ORB:
			var orb := SphereMesh.new()
			orb.radius = 0.15
			orb.height = 0.3
			m = orb
		_:  # BULLET
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.03
			capsule.height = 0.25
			m = capsule
	_cached_meshes[style] = m
	return m

static func _get_cached_material(color: Color) -> StandardMaterial3D:
	var key: int = color.to_rgba32()
	if _cached_materials.has(key):
		return _cached_materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	_cached_materials[key] = mat
	return mat


static var _cached_flame_material: StandardMaterial3D = null


## Builds a real missile model with its NOSE pointing down local -Z (Godot's
## forward), so a single look_at() down the flight line aims it correctly.
## Hull cylinder + cone warhead + cross tail fins + exhaust flame glow.
static func _build_missile_model(hull_mat: StandardMaterial3D) -> Node3D:
	var root := Node3D.new()

	var body := MeshInstance3D.new()
	var hull := CylinderMesh.new()
	hull.top_radius = 0.05
	hull.bottom_radius = 0.05
	hull.height = 0.30
	body.mesh = hull
	body.material_override = hull_mat
	body.rotation_degrees.x = -90.0  # lay the cylinder axis along Z, top toward -Z
	body.position = Vector3(0, 0, -0.02)
	root.add_child(body)

	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.004
	cone.bottom_radius = 0.05
	cone.height = 0.16
	nose.mesh = cone
	nose.material_override = hull_mat
	nose.rotation_degrees.x = -90.0
	nose.position = Vector3(0, 0, -0.25)  # tip reaches z -0.33, ahead of the hull
	root.add_child(nose)

	var fin_v := MeshInstance3D.new()
	var fv := BoxMesh.new()
	fv.size = Vector3(0.015, 0.16, 0.12)
	fin_v.mesh = fv
	fin_v.material_override = hull_mat
	fin_v.position = Vector3(0, 0, 0.07)
	root.add_child(fin_v)

	var fin_h := MeshInstance3D.new()
	var fh := BoxMesh.new()
	fh.size = Vector3(0.16, 0.015, 0.12)
	fin_h.mesh = fh
	fin_h.material_override = hull_mat
	fin_h.position = Vector3(0, 0, 0.07)
	root.add_child(fin_h)

	var flame := MeshInstance3D.new()
	var fl := SphereMesh.new()
	fl.radius = 0.035
	fl.height = 0.09
	flame.mesh = fl
	flame.material_override = _get_flame_material()
	flame.position = Vector3(0, 0, 0.20)  # burning exhaust behind the tail fins
	root.add_child(flame)

	return root


static func _get_flame_material() -> StandardMaterial3D:
	if _cached_flame_material == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.55, 0.15)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.6, 0.2)
		m.emission_energy_multiplier = 6.0
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_cached_flame_material = m
	return _cached_flame_material


## Blender-authored FX (assets/models/projectile_fx.glb: BeamBolt + RailSlug
## with its VaporCone wake, front authored toward +Y so -Z leads in Godot).
## Loaded lazily; when the GLB is missing (headless tests) the procedural
## builders below take over so gameplay never breaks.
const FX_GLB_PATH = "res://assets/models/projectile_fx.glb"
## Beam bolts fly 33% longer than authored so the laser reads at range.
const BEAM_LENGTH_MULT = 1.33
static var _fx_scene: PackedScene = null
static var _fx_missing := false


## Extracts one named mesh node out of the FX GLB (with its children, e.g.
## the vapor cone parented under the slug). Returns null when unavailable.
static func _fx_node(node_name: String) -> Node3D:
	if _fx_missing:
		return null
	if _fx_scene == null:
		if not ResourceLoader.exists(FX_GLB_PATH):
			_fx_missing = true
			return null
		_fx_scene = load(FX_GLB_PATH) as PackedScene
		if _fx_scene == null:
			_fx_missing = true
			return null
	var inst := _fx_scene.instantiate() as Node3D
	if inst == null:
		return null
	var n := inst.find_child(node_name, true, true) as Node3D
	if n == null:
		inst.queue_free()
		return null
	var parent := n.get_parent()
	if parent != null:
		parent.remove_child(n)
		n.owner = null
	inst.queue_free()
	return n


static var _cached_hot_material: StandardMaterial3D = null
static var _cached_vapor_material: StandardMaterial3D = null


## White-hot unshaded core shared by beam bolts and railgun slugs.
static func _get_hot_material() -> StandardMaterial3D:
	if _cached_hot_material == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1, 1, 1)
		m.emission_enabled = true
		m.emission = Color(0.9, 1.0, 1.0)
		m.emission_energy_multiplier = 6.0
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_cached_hot_material = m
	return _cached_hot_material


## Translucent vapor-cone skin for the railgun's sonic wake.
static func _get_vapor_material() -> StandardMaterial3D:
	if _cached_vapor_material == null:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.7, 0.9, 1.0, 0.4)
		m.emission_enabled = true
		m.emission = Color(0.6, 0.85, 1.0)
		m.emission_energy_multiplier = 2.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cached_vapor_material = m
	return _cached_vapor_material


## Energy bolt: white-hot core inside a colored halo, long axis on Z so the
## container's -Z stays the flight direction (no extra roll after look_at).
static func _build_beam_bolt(halo_mat: StandardMaterial3D) -> Node3D:
	var authored := _fx_node("BeamBolt")
	if authored != null:
		authored.name = "BeamBolt"
		authored.scale = Vector3(1.0, 1.0, BEAM_LENGTH_MULT)
		return authored
	var root := Node3D.new()
	root.name = "BeamBolt"
	root.scale = Vector3(1.0, 1.0, BEAM_LENGTH_MULT)
	var core := MeshInstance3D.new()
	var core_mesh := CapsuleMesh.new()
	core_mesh.radius = 0.03
	core_mesh.height = 1.3
	core.mesh = core_mesh
	core.material_override = _get_hot_material()
	core.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(core)
	var halo := MeshInstance3D.new()
	var halo_mesh := CapsuleMesh.new()
	halo_mesh.radius = 0.07
	halo_mesh.height = 1.1
	halo.mesh = halo_mesh
	halo.material_override = halo_mat
	halo.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(halo)
	return root


## Railgun slug: dense pale rod up front (leads), vapor cone trailing behind
## (+Z, the wake), plus the expanding shockwave rings from projectile.gd.
static func _build_rail_slug(rod_mat: StandardMaterial3D) -> Node3D:
	var authored := _fx_node("RailSlug")
	if authored != null:
		authored.name = "RailSlug"
		return authored
	var root := Node3D.new()
	root.name = "RailSlug"
	var rod := MeshInstance3D.new()
	var rod_mesh := CapsuleMesh.new()
	rod_mesh.radius = 0.05
	rod_mesh.height = 0.9
	rod.mesh = rod_mesh
	rod.material_override = rod_mat
	rod.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(rod)
	var tip := MeshInstance3D.new()
	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = 0.06
	tip_mesh.height = 0.12
	tip.mesh = tip_mesh
	tip.material_override = _get_hot_material()
	tip.position = Vector3(0, 0, -0.48)
	root.add_child(tip)
	var cone := MeshInstance3D.new()
	cone.name = "VaporCone"
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.04
	cone_mesh.bottom_radius = 0.30
	cone_mesh.height = 1.1
	cone.mesh = cone_mesh
	cone.material_override = _get_vapor_material()
	cone.rotation_degrees = Vector3(-90, 0, 0) # narrow end forward, flare aft
	cone.position = Vector3(0, 0, 0.95)
	root.add_child(cone)
	return root


# --- Projectile spawning (shared with the player's WeaponManager) ---
func _spawn_projectile(from_pos: Vector3, aim_dir: Vector3, fired_by_enemy: bool, owner: Node, target_node: Node3D = null) -> void:
	if owner == null or not owner.is_inside_tree() or owner.get_tree().current_scene == null:
		return

	var projectile := CharacterBody3D.new()
	projectile.set_script(PROJ_SCRIPT)
	projectile.collision_layer = 0
	projectile.collision_mask = 0

	var collision := CollisionShape3D.new()
	collision.shape = _get_cached_shape()
	projectile.add_child(collision)

	var visual: Node3D
	if projectile_style == Style.MISSILE:
		# Real missile silhouette aimed by its own nose (-Z): NO extra roll,
		# which used to stand the old box mesh on end pointing at the sky.
		visual = _build_missile_model(_get_cached_material(projectile_color))
	elif projectile_style == Style.BEAM:
		# Coherent energy bolt, already -Z forward: no extra roll.
		visual = _build_beam_bolt(_get_cached_material(projectile_color))
	elif projectile_style == Style.SLUG:
		# Hypervelocity slug + vapor cone, already -Z forward: no extra roll.
		visual = _build_rail_slug(_get_cached_material(projectile_color))
	else:
		var mesh := MeshInstance3D.new()
		mesh.mesh = _get_cached_mesh(projectile_style)
		mesh.material_override = _get_cached_material(projectile_color)
		visual = mesh
	projectile.add_child(visual)

	# Energy rounds carry real light: the beam/slug visibly illuminates dark
	# corners as it flies (emissive mesh alone only glows, it lights nothing).
	# No shadows — cheap clustered omni that dies with the projectile.
	if projectile_style == Style.BEAM or projectile_style == Style.SLUG:
		var glow := OmniLight3D.new()
		if projectile_style == Style.BEAM:
			glow.light_color = Color(0.5, 0.9, 1.0)
			glow.light_energy = 3.0
			glow.omni_range = 6.0
		else:
			glow.light_color = Color(0.75, 0.9, 1.0)
			glow.light_energy = 2.0
			glow.omni_range = 5.0
		glow.omni_attenuation = 1.2
		projectile.add_child(glow)

	owner.get_tree().current_scene.add_child(projectile)
	projectile.global_position = from_pos
	visual.global_position = from_pos
	# look_at() orients -Z toward the aim line; pick an up vector that never
	# runs colinear with the direction (straight-up shots included).
	var up := Vector3.UP
	if absf(aim_dir.normalized().dot(up)) > 0.99:
		up = Vector3.RIGHT
	visual.look_at(from_pos + aim_dir, up)
	if projectile_style == Style.BULLET or projectile_style == Style.SHOTGUN or projectile_style == Style.CANNON_SHELL:
		visual.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))

	if projectile_style == Style.MISSILE:
		projectile.visual_node = visual       # re-aimed every frame to the live flight vector
		projectile.explosive_visual = true    # missiles always detonate visibly on impact

	var final_speed := projectile_speed
	if not fired_by_enemy and heat_capacity > 0.0 and heat > 0.0:
		var heat_ratio := clampf(heat / heat_capacity, 0.0, 1.0)
		final_speed *= FrameModuleSystem.calculate_heat_proj_speed_multiplier(heat_ratio)
	projectile.speed = final_speed
	projectile.damage = damage * damage_multiplier
	projectile.damage_type = damage_type
	projectile.impact = impact
	projectile.direction = aim_dir
	projectile.fired_by_enemy = fired_by_enemy
	projectile.target_node = target_node
	projectile.sonic_boom = sonic_boom
	projectile.is_beam = (projectile_style == Style.BEAM)
	projectile.trail_head = trail_head
	projectile.trail_fade = trail_fade
	projectile.drop_gravity = drop_gravity
	if explosion_radius > 0.0:
		projectile.explosion_radius = explosion_radius
		projectile.explosive_visual = true
	if sonic_boom:
		# Hypervelocity round: no bullet drop sag, flat railgun trajectory.
		projectile.drop_gravity = 0.0
		projectile.lifetime = 3.0

	EffectManager.spawn_muzzle_flash(from_pos, aim_dir, projectile_color)
	if projectile_style == Style.CANNON_SHELL:
		var tree := owner.get_tree()
		if tree:
			EffectFactory.spawn_smoke_plume(tree, from_pos + aim_dir * 0.5, 7, 0.35, 0.7, 1.2)
			EffectFactory.spawn_fire_burst(tree, from_pos + aim_dir * 0.4, 0.65, 0.25, 4.0)
