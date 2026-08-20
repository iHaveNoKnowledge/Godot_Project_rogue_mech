class_name WeaponCore
extends RefCounted

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

enum Style { BULLET, MISSILE, SHOTGUN, ORB }

## Projectile mesh variety (player loadout uses BULLET/MISSILE/SHOTGUN; enemy
## grunts and allied dummies use ORB to keep their silhouette readable).
var projectile_style: int = Style.ORB
var projectile_color: Color = Color(1, 0.8, 0.2)
# Railgun rounds leave a sonic-boom shockwave ring along their flight path.
var sonic_boom: bool = false

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

# --- Ammo config ---
var ammo_per_shot: int = 1
var max_ammo: int = 100
var unlimited_ammo: bool = false
var reload_time: float = 1.0
var auto_reload: bool = true
var manual_reload: bool = false

# --- Heat config (heat_capacity > 0 enables the system) ---
var heat_capacity: float = 0.0
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
	core.heat_capacity = weapon.heat_capacity
	core.heat_per_shot = weapon.heat_per_shot
	core.heat_cool_rate = weapon.heat_cool_rate
	core.heat_release_ratio = weapon.heat_release_ratio
	core.ammo = weapon.max_ammo
	core.projectile_style = Style.BULLET
	core.projectile_color = Color(1, 0.8, 0.2)
	# The attack type (heat/pierce/blunt) is data on the weapon — the core just
	# carries it to the projectile so armor/shield defenses can match on it.
	core.damage_type = weapon.get_damage_type()
	match weapon.weapon_type:
		WeaponPart.WeaponType.MISSILE:
			core.projectile_style = Style.MISSILE
		WeaponPart.WeaponType.SHOTGUN:
			core.projectile_style = Style.SHOTGUN
			core.pellets = 7
		WeaponPart.WeaponType.RAILGUN:
			# Railgun rounds are hypervelocity: electric-blue bolt, no bullet drop
			# sag, and a sonic-boom shockwave ring along the flight path.
			core.projectile_style = Style.BULLET
			core.projectile_color = Color(0.45, 0.85, 1.0)
			core.sonic_boom = true
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
	core.reload_time = float(stats.get("reload_time", 3.0))
	core.damage_type = str(stats.get("damage_type", "kinetic"))
	core.impact = float(stats.get("impact", 0.0))
	core.projectile_style = Style.ORB
	core.projectile_color = stats.get("projectile_color", Color(1, 0.8, 0.2))
	core.unlimited_ammo = core.max_ammo <= 0
	core.auto_reload = not core.unlimited_ammo
	return core


func tick(delta: float) -> void:
	if cooldown > 0.0:
		cooldown = maxf(cooldown - delta, 0.0)

	if reloading:
		reload_timer -= delta
		if reload_timer <= 0.0 and not manual_reload:
			complete_reload()

	_cool_heat(delta)


func can_fire() -> bool:
	if cooldown > 0.0 or reloading or overheated:
		return false
	if not unlimited_ammo and ammo < ammo_per_shot:
		return false
	return true


## Consumes the shot's cost (cooldown, ammo, heat) WITHOUT spawning a
## projectile. Used by melee weapons, where the caller runs its own lunge/hit
## animation but still obeys the shared weapon rules.
func consume_shot() -> bool:
	if not can_fire():
		return false
	cooldown = fire_interval
	if not unlimited_ammo:
		ammo = maxi(ammo - ammo_per_shot, 0)
		ammo_changed.emit(ammo, max_ammo)
		if ammo <= 0 and auto_reload:
			begin_reload()
	_accumulate_heat()
	fired.emit()
	return true


## Consumes a shot and spawns the projectile(s). Returns true when a shot was
## actually fired (ammo/heat/cooldown all consumed).
func try_fire(from_pos: Vector3, aim_dir: Vector3, fired_by_enemy: bool, owner: Node) -> bool:
	if not consume_shot():
		return false

	for i in range(pellets):
		var pellet_dir := aim_dir
		if pellets > 1 and spread > 0.0:
			var sx := randf_range(-spread, spread)
			var sy := randf_range(-spread, spread)
			pellet_dir = (aim_dir + Vector3(sx, sy, 0)).normalized()
		_spawn_projectile(from_pos, pellet_dir, fired_by_enemy, owner)
	fired.emit()
	return true


func begin_reload() -> bool:
	if reloading or max_ammo <= 0 or ammo >= max_ammo:
		return false
	reloading = true
	reload_timer = reload_time
	return true


## Finishes a reload, drawing from `reserve` when set (player) or refilling the
## whole magazine (enemies / infinite ammo). Returns the ammo refilled.
func complete_reload() -> int:
	if not reloading:
		return 0
	reloading = false
	reload_timer = 0.0
	var needed := max_ammo - ammo
	var refilled := 0
	if unlimited_ammo or reserve <= 0:
		refilled = needed
	else:
		refilled = mini(needed, reserve)
		reserve -= refilled
	ammo += refilled
	ammo_changed.emit(ammo, max_ammo)
	return refilled


# --- Heat ---
func _accumulate_heat() -> void:
	if heat_capacity <= 0.0:
		return
	heat = minf(heat + heat_per_shot, heat_capacity)
	overheated = heat >= heat_capacity
	heat_changed.emit(heat, heat_capacity, overheated)


func _cool_heat(delta: float) -> void:
	if heat_capacity <= 0.0:
		return
	if heat <= 0.0:
		return
	# Tactical Smog: heat cool rate x0.5 — chemical smoke traps heat in the barrel.
	var cool_rate := heat_cool_rate
	if GlobalData.current_hazard == GlobalData.HAZARD_TACTICAL_SMOG:
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


# --- Projectile spawning (shared with the player's WeaponManager) ---
func _spawn_projectile(from_pos: Vector3, aim_dir: Vector3, fired_by_enemy: bool, owner: Node) -> void:
	if owner == null or owner.get_tree() == null or owner.get_tree().current_scene == null:
		return

	var proj_script := load("res://scripts/systems/projectile.gd")
	var projectile := CharacterBody3D.new()
	projectile.set_script(proj_script)
	projectile.collision_layer = 0
	projectile.collision_mask = 0

	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.1
	collision.shape = shape
	projectile.add_child(collision)

	var mesh := MeshInstance3D.new()
	match projectile_style:
		Style.MISSILE:
			var box := BoxMesh.new()
			box.size = Vector3(0.1, 0.1, 0.4)
			mesh.mesh = box
		Style.SHOTGUN:
			var pellet := CapsuleMesh.new()
			pellet.radius = 0.02
			pellet.height = 0.15
			mesh.mesh = pellet
		Style.ORB:
			var orb := SphereMesh.new()
			orb.radius = 0.15
			orb.height = 0.3
			mesh.mesh = orb
		_:  # BULLET
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.03
			capsule.height = 0.25
			mesh.mesh = capsule

	var mat := StandardMaterial3D.new()
	mat.albedo_color = projectile_color
	mat.emission_enabled = true
	mat.emission = projectile_color
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	projectile.add_child(mesh)

	owner.get_tree().current_scene.add_child(projectile)
	projectile.global_position = from_pos
	mesh.global_position = from_pos
	mesh.look_at(from_pos + aim_dir, Vector3.UP)
	if projectile_style != Style.ORB:
		mesh.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))

	projectile.speed = projectile_speed
	projectile.damage = damage * damage_multiplier
	projectile.damage_type = damage_type
	projectile.impact = impact
	projectile.direction = aim_dir
	projectile.fired_by_enemy = fired_by_enemy
	projectile.sonic_boom = sonic_boom
	if sonic_boom:
		# Hypervelocity round: no bullet drop sag, flat railgun trajectory.
		projectile.drop_gravity = 0.0
		projectile.lifetime = 3.0

	EffectManager.spawn_muzzle_flash(from_pos, aim_dir, projectile_color)
