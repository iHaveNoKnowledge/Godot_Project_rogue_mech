extends CharacterBody3D

## A defeated enemy's pilot bailing out of a crippled mech: a small figure in
## the unit's colors that either fights back with a personal weapon or sprints
## toward the nearest escape zone to flee the battlefield. The pilot is a real
## target — the player can shoot it down. Its HP pool mirrors the player's
## PilotSystem rule: HP reaching 0 is PERMANENT DEATH (the pilot is gone for
## good), instead of every enemy pilot always getting away.

var _target: Node3D = null
var _run_speed: float = 6.5
var _life: float = 8.0
var _color: Color = Color(0.75, 0.2, 0.2)
var _dead: bool = false

# Enemy pilot HP: a fleeing pilot is fragile but not a one-shot. Uses the same
# "HP 0 = dead forever" rule as the player pilot (PilotSystem), so both sides
# share one permanent-death system.
var hp: float = 40.0
var max_hp: float = 40.0

# Compatibility interface so systems querying .health_system on any "enemy" node work seamlessly
class PilotHealthAdapter:
	var _p: CharacterBody3D
	var is_destroyed: bool:
		get:
			return _p == null or not is_instance_valid(_p) or _p._dead
	var parts: Dictionary = {}
	var max_total_armor: float = 0.0
	var max_total_frame: float:
		get:
			return _p.max_hp if (_p and is_instance_valid(_p)) else 40.0
	var current_total_frame: float:
		get:
			return _p.hp if (_p and is_instance_valid(_p)) else 0.0

	func _init(pilot: CharacterBody3D) -> void:
		_p = pilot

	func take_damage(amount: float, _slot: String = "") -> void:
		if _p and is_instance_valid(_p):
			_p.take_damage(amount)

	func take_heal(amount: float) -> void:
		if _p and is_instance_valid(_p):
			_p.hp = minf(_p.hp + amount, _p.max_hp)

var health_system: PilotHealthAdapter = null

func _init() -> void:
	health_system = PilotHealthAdapter.new(self)

# --- Fight-on-foot ----------------------------------------------------------
# When ejected, there's a probability the pilot stands and fights instead of
# fleeing. A fighting pilot uses a personal weapon (pistol by default) and
# shoots at the player mech within range.
var _fights_on_foot: bool = false
var _fight_range: float = 30.0
var _fire_cooldown: float = 0.0
var _fire_rate: float = 0.4  # seconds between shots
var _fire_core: WeaponCore = null
var _weapon_mesh: Node3D = null

# --- Retreat mode -----------------------------------------------------------
# Non-fighting pilots sprint toward the nearest escape zone. A pulsing label
# above their head shows the countdown until they escape.
var _retreat_target: Node3D = null  # nearest escape zone
var _retreat_label: Label3D = null
var _retreat_tween: Tween = null
var _retreat_timer: float = 0.0
var _escape_time: float = 8.0  # seconds to reach the zone
var _escaped: bool = false


## Chance (0.0–1.0) that an ejected pilot decides to fight on foot instead of
## fleeing. Ranged archetypes are braver (higher chance); melee have none.
static func fight_chance(archetype: int) -> float:
	match archetype:
		0: return 0.0   # Rusher: always flees (melee brawler)
		1: return 0.45  # Ranged: fights back often
		2: return 0.0   # Heavy: always flees (too slow on foot)
		3: return 0.30  # Support: sometimes fights
		4: return 0.0   # Shield melee: always flees
		5: return 0.40  # Shield ranged: fights back
		_: return 0.2


func setup(target: Node3D, color: Color) -> void:
	_target = target
	_color = color


func setup_fighting(target: Node3D, color: Color, archetype: int) -> void:
	_target = target
	_color = color
	_fights_on_foot = randf() < fight_chance(archetype)


func _ready() -> void:
	add_to_group("enemy_pilot")
	add_to_group("enemy")
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(60)

	# Hittable like the enemy mechs: layer 8 is the enemy hit layer the player's
	# weapons (ranged aim ray + melee) scan, so the pilot is a real target.
	collision_layer = 8
	collision_mask = 3

	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.22
	capsule.height = 0.9
	col.shape = capsule
	col.position.y = 0.45
	add_child(col)

	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.9
	body.mesh = mesh
	body.position.y = 0.45
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color
	mat.emission_enabled = true
	mat.emission = _color
	mat.emission_energy_multiplier = 0.6
	body.material_override = mat
	add_child(body)

	if _fights_on_foot:
		_equip_weapon()
	else:
		_find_retreat_point()
		_spawn_retreat_label()


# Player fire hits the fleeing pilot: HP drops and, at 0, the pilot dies
# permanently (never comes back in the run) instead of always getting away.
func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if _dead or amount <= 0.0:
		return
	hp -= amount
	EffectManager.spawn_damage_number(global_position + Vector3(0, 1.6, 0), amount, Color(1.0, 0.5, 0.2))
	if AudioManager:
		AudioManager.play_impact_by_type(damage_type, global_position)
	if hp <= 0.0:
		_die()


# Permanent death: the pilot collapses (small hit-mark effect) and is gone.
func _die() -> void:
	if _dead:
		return
	_dead = true
	EffectManager.spawn_explosion(global_position + Vector3(0, 0.8, 0))
	queue_free()


# --- Weapon system ----------------------------------------------------------

func _equip_weapon() -> void:
	var pistol_path := "res://resources/mech/stock/weapon_pilot_pistol.tres"
	var weapon: WeaponPart = load(pistol_path)
	if weapon == null:
		return
	_fire_core = WeaponCore.from_weapon(weapon)
	_fire_core.fire_interval = 0.0
	_fire_core.auto_reload = false
	_fire_core.manual_reload = true
	_fire_core.unlimited_ammo = true  # enemy pilots have infinite ammo for balance
	# Build a small weapon model so the pilot reads as armed.
	_weapon_mesh = Node3D.new()
	_weapon_mesh.add_child(WeaponVisualFactory.build(weapon))
	_weapon_mesh.position = Vector3(0.45, 1.05, -0.15)
	_weapon_mesh.rotation = Vector3(0, 0, -0.35)
	add_child(_weapon_mesh)


func _try_fire_at_player() -> void:
	if _fire_core == null or _target == null or not is_instance_valid(_target):
		return
	var to_target := (_target.global_position - global_position)
	var dist := to_target.length()
	if dist > _fight_range or dist < 1.5:
		return
	var aim_dir := to_target.normalized()
	aim_dir.y = 0.0
	aim_dir = aim_dir.normalized()
	# Aim slightly up to account for pilot being short vs mech torso.
	aim_dir.y = (to_target.y + 1.0) / maxf(dist, 1.0)
	aim_dir = aim_dir.normalized()

	var muzzle := global_position + Vector3(0, 1.2, 0)
	if _fire_core.try_fire(muzzle, aim_dir, true, self):
		if AudioManager:
			AudioManager.play_sfx("machine_gun", muzzle, -8.0)
		# Recoil the pilot slightly.
		velocity.x += -aim_dir.x * 0.6
		velocity.z += -aim_dir.z * 0.6


# --- Retreat system ---------------------------------------------------------

func _find_retreat_point() -> void:
	var zones := get_tree().get_nodes_in_group("escape_zone")
	if zones.is_empty():
		_retreat_target = null
		return
	var best_dist := INF
	for zone in zones:
		if not is_instance_valid(zone):
			continue
		if zone.has_method("is_escape_complete") and zone.is_escape_complete():
			continue
		var d := global_position.distance_to(zone.global_position)
		if d < best_dist:
			best_dist = d
			_retreat_target = zone


func _spawn_retreat_label() -> void:
	_retreat_label = Label3D.new()
	_retreat_label.name = "RetreatLabel"
	_retreat_label.text = "ESCAPING"
	_retreat_label.font_size = 14
	_retreat_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_retreat_label.no_depth_test = true
	_retreat_label.modulate = Color(1.0, 0.8, 0.2)
	_retreat_label.position = Vector3(0, 1.5, 0)
	add_child(_retreat_label)

	# Pulse the label so the player notices the escaping pilot.
	_retreat_tween = create_tween().set_loops()
	_retreat_tween.tween_property(_retreat_label, "modulate:a", 0.35, 0.4)
	_retreat_tween.tween_property(_retreat_label, "modulate:a", 1.0, 0.4)


func _update_retreat_label() -> void:
	if _retreat_label == null or _escaped:
		return
	var remaining := maxf(_escape_time - _retreat_timer, 0.0)
	_retreat_label.text = "ESCAPING %.1fs" % remaining


# --- Main loop --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _dead:
		return

	_life -= delta
	if _life <= 0.0 or global_position.distance_to(Vector3.ZERO) > 60.0:
		_cleanup_label()
		queue_free()
		return

	if _fights_on_foot:
		_process_fight(delta)
	else:
		_process_retreat(delta)


func _process_fight(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)

	# Face the player when in range.
	if _target != null and is_instance_valid(_target):
		var to_target := (_target.global_position - global_position)
		to_target.y = 0.0
		if to_target.length() > 0.5:
			rotation.y = lerp_angle(rotation.y, atan2(to_target.x, to_target.z), 6.0 * delta)

		# Strafe slowly while fighting — don't stand still.
		var strafe_dir := Vector3.ZERO
		if to_target.length() > 2.0:
			# Circle-strafe perpendicular to the player.
			strafe_dir = to_target.normalized()
			strafe_dir = strafe_dir.cross(Vector3.UP).normalized()
			if randf() < 0.02:
				strafe_dir = -strafe_dir  # randomly reverse direction
		velocity.x = strafe_dir.x * _run_speed * 0.4
		velocity.z = strafe_dir.z * _run_speed * 0.4
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	velocity.y -= 20.0 * delta
	move_and_slide()

	# Fire at the player.
	if _fire_cooldown <= 0.0:
		_try_fire_at_player()
		_fire_cooldown = _fire_rate


func _process_retreat(delta: float) -> void:
	_retreat_timer += delta
	_update_retreat_label()

	# Escape check: if close enough to the zone, the pilot vanishes.
	if _retreat_target != null and is_instance_valid(_retreat_target):
		var dist := global_position.distance_to(_retreat_target.global_position)
		if dist < 4.0:
			_complete_escape()
			return

	# Auto-escape after the timer expires (the pilot made it off-screen).
	if _retreat_timer >= _escape_time:
		_complete_escape()
		return

	# Move toward the retreat point, or away from the player if no zone exists.
	var dir := Vector3.ZERO
	if _retreat_target != null and is_instance_valid(_retreat_target):
		dir = (_retreat_target.global_position - global_position)
		dir.y = 0.0
	elif _target != null and is_instance_valid(_target):
		dir = (global_position - _target.global_position)
		dir.y = 0.0

	if dir.length() < 0.5:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		dir = dir.normalized()
		velocity.x = dir.x * _run_speed
		velocity.z = dir.z * _run_speed
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 8.0 * delta)

	velocity.y -= 20.0 * delta
	move_and_slide()


func _complete_escape() -> void:
	if _escaped:
		return
	_escaped = true
	_cleanup_label()
	queue_free()


func _cleanup_label() -> void:
	if _retreat_tween and _retreat_tween.is_valid():
		_retreat_tween.kill()
		_retreat_tween = null
	if _retreat_label != null and is_instance_valid(_retreat_label):
		_retreat_label.queue_free()
		_retreat_label = null
