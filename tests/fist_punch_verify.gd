extends Node

## Verifies the bare-fist unarmed melee: when a hand is EMPTY, firing falls back
## to a punch instead of doing nothing.
##   1. The fist is a real MELEE WeaponPart with tuned unarmed damage.
##   2. An empty-hand fire lands the swing on an enemy ahead (camera aim ray).
##   3. The punch obeys the shared WeaponCore cooldown — no spamming, and both
##      hands share the same fist cadence.
## The test is driven by a _process state machine (polling) because in headless
## runs `await` inside while loops / timer timeouts may never resume.
## Run: godot --headless --path . res://tests/fist_punch_verify.tscn

const FIST_DAMAGE: float = 8.0

var _fails := 0
var _checks := 0
var _stage := 0
var _settle := 0

var _wm: Node = null
var _mecha: CharacterBody3D = null
var _enemy: Node = null
var _cam: Camera3D = null


# The swing's hit reach is measured from the LUNGED position, so the mech's
# current stance affects whether a punch connects. The test force-advances the
# shared core without waiting for the real 0.26s lunge tween (headless pacing),
# so reset the stance to the resting origin before each hit-expecting punch to
# simulate the previous lunge having completed (real cadences — fist 0.5s,
# knife 0.25s — never fire into another swing's 0.05s anticipation pull-back).
func _reset_stance() -> void:
	if _mecha:
		_mecha.position = Vector3(0, 1.5, 0)


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("FIST OK: " + name)
	else:
		_fails += 1
		print("FIST FAIL: " + name)


# True once the aim ray from the camera's screen center actually sees the enemy
# (physics needs a step to register freshly-added bodies).
func _aim_ray_hits_enemy() -> bool:
	var space = get_viewport().get_world_3d().direct_space_state
	var center := get_viewport().get_visible_rect().size / 2.0
	var query := PhysicsRayQueryParameters3D.create(
		_cam.project_ray_origin(center), _cam.project_ray_origin(center) + _cam.project_ray_normal(center) * 30.0)
	query.collision_mask = 10
	var result := space.intersect_ray(query)
	return result and result.get("collider") == _enemy


func _finish() -> void:
	print("FIST_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _process(_delta: float) -> void:
	match _stage:
		0:
			# Build the scene: player mecha with the real WeaponManager (both
			# hands forced empty), an aiming camera, and an enemy dummy ahead.
			_stage = 1
			_build_scene()
		1:
			# Wait until the physics space sees the enemy.
			if _aim_ray_hits_enemy():
				_stage = 2
				var fist: WeaponPart = _wm._fist()
				_check(fist != null, "fist weapon is built on demand")
				_check(fist.weapon_type == WeaponPart.WeaponType.MELEE, "fist counts as a melee weapon")
				_check(fist.damage == FIST_DAMAGE, "fist uses the configured unarmed damage")
				_check(fist.max_ammo == 0 and fist.ammo_per_shot == 0, "fist needs no ammo")
				_wm._try_fire("left", null)
		2:
			if _settle >= 2:
				_settle = 0
				_stage = 3
				_check(_enemy.damage_taken == FIST_DAMAGE, "empty-hand punch deals the fist damage")
				_check(_wm._melee_combo == 1, "punch counts as a melee swing")
				# An immediate second punch is gated by the shared fist core.
				_wm._try_fire("left", null)
		3:
			if _settle >= 2:
				_settle = 0
				_stage = 4
				_check(_enemy.damage_taken == FIST_DAMAGE, "punch cooldown blocks spamming")
		4:
			# Force-advance the shared core past the cooldown (deterministic —
			# headless physics ticks too slowly to wait on). The manager ticks
			# the same core every physics frame while the hand is empty.
			_wm._core_for_weapon(_wm._fist()).tick(1.0)
			_reset_stance()
			_stage = 5
			_wm._try_fire("left", null)
		5:
			if _settle >= 2:
				_settle = 0
				_stage = 6
				_check(_enemy.damage_taken == FIST_DAMAGE * 2.0, "fist swings again after the cooldown")
				# Right punch right after a left one is still on cooldown...
				_wm._try_fire("right", null)
		6:
			if _settle >= 2:
				_settle = 0
				_stage = 7
				_check(_enemy.damage_taken == FIST_DAMAGE * 2.0, "hands share the punch cooldown")
		7:
			_wm._core_for_weapon(_wm._fist()).tick(1.0)
			_reset_stance()
			_stage = 8
			_wm._try_fire("right", null)
		8:
			if _settle >= 2:
				_stage = 9
				_check(_enemy.damage_taken == FIST_DAMAGE * 3.0, "right empty hand punches as well")
				_finish()


func _build_scene() -> void:
	_mecha = CharacterBody3D.new()
	_mecha.collision_layer = 1
	_mecha.position = Vector3(0, 1.5, 0)
	add_child(_mecha)
	_wm = Node3D.new()
	_wm.set_script(preload("res://scripts/mecha/weapon_manager.gd"))
	_mecha.add_child(_wm)
	_wm.left_hand = null
	_wm.right_hand = null

	# Camera drives the center-screen aim ray, exactly like the real mech HUD.
	_cam = Camera3D.new()
	_cam.current = true
	_cam.position = Vector3(0, 1.8, 6.0)
	_cam.look_at(Vector3(0, 1.5, -3.0))
	add_child(_cam)

	# Enemy dummy 3m ahead on collision layer 8 (aim ray + swing ray targets).
	_enemy = CharacterBody3D.new()
	_enemy.set_script(preload("res://tests/melee_dummy_target.gd"))
	_enemy.collision_layer = 8
	_enemy.add_to_group("enemy")
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 1.0
	capsule.height = 4.5
	col.shape = capsule
	col.position = Vector3(0, 2.25, 0)
	_enemy.add_child(col)
	_enemy.position = Vector3(0, 1.5, -3.0)
	add_child(_enemy)


func _physics_process(_delta: float) -> void:
	_settle += 1
