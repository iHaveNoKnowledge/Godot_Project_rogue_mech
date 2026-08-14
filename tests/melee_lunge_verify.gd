extends Node

## Verifies the melee lunge "feel" tuning headlessly:
##   - a swing lunges the mech ~(range - reach) so the thrust visual matches the
##     weapon's range_distance (fist 3.0 -> 1.4m, pile 4.0 -> 2.4m),
##   - the hit check lands at the thrust peak, so hits connect exactly at the
##     weapon's range and whiff just past it,
##   - the mech returns to its origin after the recovery phase,
##   - rapid consecutive swings (combat knife at 0.25s < 0.26s lunge tween) land
##     both hits without the tweens fighting and flinging the mech around.
## Driven by a _process state machine (headless-safe). Tween waits are
## wall-clock based because headless frame pacing is not guaranteed.
## Run: godot --headless --path . res://tests/melee_lunge_verify.tscn

const FIST_DAMAGE: float = 8.0
const KNIFE_DAMAGE: float = 25.0
const BLADE_DAMAGE: float = 50.0
const PILE_DAMAGE: float = 120.0

var _fails := 0
var _checks := 0
var _stage := 0
var _settle := 0
var _fire_msec := 0
var _measuring := false
var _peak_z := 0.0

var _wm: Node = null
var _mecha: CharacterBody3D = null
var _enemy: Node = null
var _cam: Camera3D = null
var _rig: Node = null
var _shake_delta := 0.0
var _crosshair: Node = null
var _flash_after_swing := 0.0
var _time_scale_after_swing := 1.0
var _trail_color_after_swing := Color.WHITE

var _knife: WeaponPart = preload("res://resources/mech/stock/weapon_combat_knife.tres")
var _blade: WeaponPart = preload("res://resources/mech/stock/weapon_heat_blade.tres")
var _pile: WeaponPart = preload("res://resources/mech/stock/weapon_pile_bunker.tres")


# Stand-in for the real camera rig (camera_rig group + add_shake) so the test
# can assert that every melee impact kicks the camera.
class FakeRig:
	extends Node

	var total_shake: float = 0.0

	func add_shake(amount: float) -> void:
		total_shake += amount


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("LUNGE OK: " + name)
	else:
		_fails += 1
		print("LUNGE FAIL: " + name)


func _elapsed(ms: int) -> bool:
	return Time.get_ticks_msec() - _fire_msec >= ms


func _aim_ray_hits_enemy() -> bool:
	var space = get_viewport().get_world_3d().direct_space_state
	var center := get_viewport().get_visible_rect().size / 2.0
	var query := PhysicsRayQueryParameters3D.create(
		_cam.project_ray_origin(center), _cam.project_ray_origin(center) + _cam.project_ray_normal(center) * 30.0)
	query.collision_mask = 10
	var result := space.intersect_ray(query)
	return result and result.get("collider") == _enemy


func _finish() -> void:
	print("LUNGE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _start_swing(hand: String, weapon) -> void:
	_fire_msec = Time.get_ticks_msec()
	_measuring = true
	_peak_z = _mecha.position.z
	var shake_before: float = _rig.total_shake
	_wm._try_fire(hand, weapon)
	_shake_delta = _rig.total_shake - shake_before
	_flash_after_swing = _crosshair._flash_strength
	_time_scale_after_swing = Engine.time_scale
	# The swing's trail spawns synchronously; grab the newest trail box's
	# albedo (iterate so we end on the LAST = this swing's newest box, which
	# matters for the rapid double-swing where swing 1's trail still lingers).
	# Trail boxes are the only BoxMesh meshes with no_depth_test materials
	# (shell casings and other props don't set it), so that's our filter.
	_trail_color_after_swing = Color.WHITE
	for child in get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh \
				and child.material_override is StandardMaterial3D \
				and child.material_override.no_depth_test:
			_trail_color_after_swing = child.material_override.albedo_color


func _process(_delta: float) -> void:
	match _stage:
		0:
			_stage = 1
			_build_scene()
		1:
			# Wait until the physics space sees the enemy ahead.
			if _aim_ray_hits_enemy():
				_stage = 2
				_start_swing("left", null)
		2:
			# Fist @ 3.0m: should hit, lunge ~1.4m, return to origin, and kick
			# the camera with a light impact shake.
			if _elapsed(350):
				_measuring = false
				_stage = 3
				_check(_enemy.damage_taken == FIST_DAMAGE, "fist connects at its 3m range")
				_check(_peak_z <= -1.25, "fist lunges ~1.4m into the punch (peak %.2f)" % _peak_z)
				_check(absf(_mecha.position.z) < 0.05, "mech returns to origin after the fist recovery")
				_check(_shake_delta > 0.09 and _shake_delta < 0.15, "fist impact shakes the camera lightly (%.3f)" % _shake_delta)
				_check(_flash_after_swing > 0.5, "fist impact flashes the screen edge (%.2f)" % _flash_after_swing)
				_check(_crosshair._flash_strength < 0.01, "impact flash fades quickly")
				_check(_time_scale_after_swing == 1.0, "fist impact does NOT trigger hit-stop")
				_check(_trail_color_after_swing.r > 0.85 and _trail_color_after_swing.b > 0.9,
					"fist trail is muted steel-white (%s)" % _trail_color_after_swing)
				_enemy.position = Vector3(0, 1.5, -3.2)
				_enemy.damage_taken = 0.0
		3:
			if _settle >= 3:
				_settle = 0
				_stage = 4
				_start_swing("left", null)
		4:
			# Fist @ 3.2m: just past range -> the swing must whiff, and a whiff
			# must NOT flash the screen.
			if _elapsed(350):
				_measuring = false
				_stage = 5
				_check(_enemy.damage_taken == 0.0, "fist whiffs just past its 3m range (reach == range)")
				_check(_flash_after_swing < 0.01, "whiff does not flash the screen edge")
				_wm.left_hand = _knife
				_enemy.position = Vector3(0, 1.5, -2.5)
				_enemy.damage_taken = 0.0
		5:
			if _settle >= 3:
				_settle = 0
				_stage = 6
				_start_swing("left", _wm.left_hand)
		6:
			# Second knife swing 4 physics frames later, while the first swing's
			# 0.26s lunge tween is still running (knife rate 0.25s < tween).
			if _settle >= 4:
				_settle = 0
				_stage = 7
				_wm._core_for_weapon(_wm.left_hand).tick(0.3)
				_start_swing("left", _wm.left_hand)
		7:
			if _elapsed(400):
				_measuring = false
				_stage = 8
				_check(_enemy.damage_taken == KNIFE_DAMAGE * 2.0, "both rapid knife swings connect (%.0f dmg)" % _enemy.damage_taken)
				# The mech rests where swing 2 STARTED (its own orig_pos), which can be
				# up to a full lunge step (0.9m) into swing 1's thrust depending on
				# frame timing. Bounded combo stepping-forward is correct; the old
				# tween-fighting bug flung the mech far beyond this.
				_check(absf(_mecha.position.z) < 1.0, "mech stays within one lunge step through rapid swings, no tween fighting (z=%.2f)" % _mecha.position.z)
				_check(_shake_delta > 0.12 and _shake_delta < 0.18, "each knife swing shakes the camera (last %.3f)" % _shake_delta)
				_check(_rig.total_shake > 0.25, "both rapid knife swings each kick the camera (total %.3f)" % _rig.total_shake)
				_check(_trail_color_after_swing.r < 0.85 and _trail_color_after_swing.b > 0.9,
					"knife trail is cool silver (%s)" % _trail_color_after_swing)
				# Fresh start for the pile charge: reset the mech to origin so the
				# peak-lunge measurement is measured from a clean stance.
				_mecha.position = Vector3(0, 1.5, 0)
				_wm.left_hand = _pile
				_enemy.position = Vector3(0, 1.5, -4.0)
				_enemy.damage_taken = 0.0
		8:
			if _settle >= 3:
				_settle = 0
				_stage = 9
				_start_swing("left", _wm.left_hand)
		9:
			# Pile bunker @ 4.0m: connects with its big 2.4m charge and the
			# hardest shake of the melee set.
			if _elapsed(400):
				_measuring = false
				_stage = 10
				_check(_enemy.damage_taken == PILE_DAMAGE, "pile bunker connects at its 4m range")
				_check(_peak_z <= -2.25, "pile bunker lunges ~2.4m into the charge (peak %.2f)" % _peak_z)
				_check(absf(_mecha.position.z) < 0.05, "mech returns to origin after the pile recovery")
				_check(_shake_delta > 0.32 and _shake_delta < 0.38, "pile impact kicks the camera hardest (%.3f)" % _shake_delta)
				_check(_shake_delta > _rig.total_shake * 0.45, "pile shake outweighs the earlier melee taps")
				_check(_time_scale_after_swing < 0.1, "pile impact freezes time (hit-stop at %.2f)" % _time_scale_after_swing)
				_check(Engine.time_scale == 1.0, "hit-stop ends and time resumes")
				_check(_trail_color_after_swing.r < 0.8 and _trail_color_after_swing.b < 0.7,
					"pile trail is heavy gunmetal (%s)" % _trail_color_after_swing)
				# Auto-aim: off-center enemies. The camera stays looking straight
				# ahead (-Z) while the enemy sits off the aim line — the swing's
				# forward box must catch a target whose BODY fills the crosshair
				# (0.9m off, within the 1m body radius) and the true auto-aim band
				# (1.1m off, crosshair beside the body) but whiff beyond it (1.4m).
				_wm.left_hand = null
				_enemy.position = Vector3(0.9, 1.5, -3.0)
				_enemy.damage_taken = 0.0
				_mecha.position = Vector3(0, 1.5, 0)
		10:
			if _settle >= 3:
				_settle = 0
				_stage = 11
				_wm._core_for_weapon(_wm._fist()).tick(0.6)
				_start_swing("left", null)
		11:
			if _elapsed(350):
				_stage = 12
				_check(_enemy.damage_taken == FIST_DAMAGE, "off-center enemy whose body fills the crosshair still connects")
				_enemy.position = Vector3(1.1, 1.5, -3.0)
				_enemy.damage_taken = 0.0
				_mecha.position = Vector3(0, 1.5, 0)
		12:
			if _settle >= 3:
				_settle = 0
				_stage = 13
				_wm._core_for_weapon(_wm._fist()).tick(0.6)
				_start_swing("left", null)
		13:
			if _elapsed(350):
				_stage = 14
				_check(_enemy.damage_taken == FIST_DAMAGE, "crosshair-beside-body enemy is caught by the auto-aim band")
				_enemy.position = Vector3(1.4, 1.5, -3.0)
				_enemy.damage_taken = 0.0
				_mecha.position = Vector3(0, 1.5, 0)
		14:
			if _settle >= 3:
				_settle = 0
				_stage = 15
				_wm._core_for_weapon(_wm._fist()).tick(0.6)
				_start_swing("left", null)
		15:
			if _elapsed(350):
				_stage = 16
				_check(_enemy.damage_taken == 0.0, "enemy beyond the auto-aim width whiffs")
				# Heat blade: connects at its 3m range with a warm ember trail.
				_wm.left_hand = _blade
				_enemy.position = Vector3(0, 1.5, -3.0)
				_enemy.damage_taken = 0.0
				_mecha.position = Vector3(0, 1.5, 0)
		16:
			if _settle >= 3:
				_settle = 0
				_stage = 17
				_start_swing("left", _wm.left_hand)
		17:
			if _elapsed(350):
				_stage = 18
				_check(_enemy.damage_taken == BLADE_DAMAGE, "heat blade connects at its 3m range")
				_check(_trail_color_after_swing.r > 0.9 and _trail_color_after_swing.b < 0.55,
					"heat blade trail is warm ember (%s)" % _trail_color_after_swing)
				_finish()


func _build_scene() -> void:
	_mecha = CharacterBody3D.new()
	_mecha.name = "Mecha"
	_mecha.collision_layer = 1
	_mecha.position = Vector3(0, 1.5, 0)
	add_child(_mecha)

	_wm = Node3D.new()
	_wm.name = "WeaponManager"
	_wm.set_script(preload("res://scripts/mecha/weapon_manager.gd"))
	_mecha.add_child(_wm)
	_wm.left_hand = null
	_wm.right_hand = null

	_cam = Camera3D.new()
	_cam.current = true
	_cam.position = Vector3(0, 1.8, 6.0)
	_cam.look_at(Vector3(0, 1.5, -3.0))
	add_child(_cam)

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

	# Fake camera rig so impact shakes can be measured.
	_rig = FakeRig.new()
	_rig.add_to_group("camera_rig")
	add_child(_rig)

	# Real crosshair HUD so the melee-hit impact flash can be verified end-to-end
	# (weapon_manager emits melee_hit_landed -> crosshair flashes).
	var crosshair_scene: PackedScene = preload("res://scenes/ui/crosshair.tscn")
	_crosshair = crosshair_scene.instantiate()
	add_child(_crosshair)


func _physics_process(_delta: float) -> void:
	_settle += 1
	if _measuring and _mecha:
		_peak_z = minf(_peak_z, _mecha.position.z)
