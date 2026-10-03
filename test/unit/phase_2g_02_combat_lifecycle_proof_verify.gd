extends Node
## PHASE 2G-02 COMBAT LIFECYCLE PROOF (audit 2G-01 follow-up, test-only).
##
## Proves three lifecycle invariants on production paths (the fourth —
## single combat_ended emission — is already proven by
## phase_2e_20 TEST A/F/G and is referenced, not duplicated):
##  1. Projectile owner exclusion is structural: a shot only ever matches
##     the opposing group set, so the firer cannot be hit.
##  2. Destroyed targets reject further HP mutation on every take_damage*
##     entry (the existing is_destroyed guard).
##  3. One destruction lifecycle emits mecha_destroyed exactly once, even
##     under repeated lethal hits.
## Conventions reused: melee_dummy_target mock, projectile.gd script nodes,
## MechaHealthBase.new() preload pattern, group-based identity.

const MechaHealthBase = preload("res://scripts/mecha/mecha_health_base.gd")
const ProjectileScript = preload("res://scripts/systems/projectile.gd")
const DummyTarget = preload("res://tests/melee_dummy_target.gd")

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("LIFECYCLE-PROOF OK: " + name)
	else:
		_fails += 1
		printerr("LIFECYCLE-PROOF FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await _test_owner_exclusion_player_shot()
	await _test_owner_exclusion_enemy_shot()
	await _test_dead_target_rejection()
	await _test_single_death_emission()
	print("PHASE_2G_02_COMBAT_LIFECYCLE_PROOF_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("PHASE_2G_02_COMBAT_LIFECYCLE_PROOF_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_PHASE_2G_02_LIFECYCLE_PROOF_TESTS_PASSED")
		get_tree().quit(0)


func _mock_hitbox(group_name: String) -> CharacterBody3D:
	var m := CharacterBody3D.new()
	m.set_script(DummyTarget)
	m.add_to_group(group_name)
	m.position = Vector3.ZERO
	add_child(m)
	return m


func _live_round(from: Vector3, enemy_flag: bool) -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.set_script(ProjectileScript)
	add_child(p)
	p.global_position = from
	p.direction = Vector3(0, 0, -1)
	p.speed = 60.0
	p.damage = 25.0
	p.damage_type = "kinetic"
	p.fired_by_enemy = enemy_flag
	return p


func _fly_until_done(p: CharacterBody3D) -> void:
	for i in range(40):
		if not is_instance_valid(p) or p.is_queued_for_deletion():
			return
		await get_tree().physics_frame
	# Safety net: a round that never resolves is itself a lifecycle failure
	# mode (it would hit lifetime expiry instead); force resolution check.
	if is_instance_valid(p) and not p.is_queued_for_deletion():
		p.queue_free()


# --- 1a. player-flagged shot: owner (mecha group) untouched, enemy hit -------
func _test_owner_exclusion_player_shot() -> void:
	var owner := _mock_hitbox("mecha")
	var foe := _mock_hitbox("enemy")
	await get_tree().process_frame
	var p := _live_round(Vector3(0, 1.5, 12), false)
	await _fly_until_done(p)
	_check(float(owner.get("damage_taken")) == 0.0, "player-flagged round cannot damage its mecha-group owner (owner took %.1f)" % float(owner.get("damage_taken")))
	_check(float(foe.get("damage_taken")) == 25.0, "same-spot enemy-group target IS hit (control proves filtering, not absence)")
	owner.queue_free()
	foe.queue_free()
	await get_tree().process_frame


# --- 1b. enemy-flagged shot: mirrored exclusion ---------------------------------
func _test_owner_exclusion_enemy_shot() -> void:
	var owner := _mock_hitbox("enemy")
	var victim := _mock_hitbox("mecha")
	await get_tree().process_frame
	var p := _live_round(Vector3(0, 1.5, 12), true)
	await _fly_until_done(p)
	_check(float(owner.get("damage_taken")) == 0.0, "enemy-flagged round cannot damage its enemy-group owner")
	_check(float(victim.get("damage_taken")) == 25.0, "same-spot mecha-group target IS hit (control)")
	owner.queue_free()
	victim.queue_free()
	await get_tree().process_frame


func _lethal_health() -> MechaHealthBase:
	var hs = MechaHealthBase.new()
	hs.parts = {"body": {"destroyed": false, "armor_broken": true, "armor_hp": 0.0, "frame_hp": 20.0, "max_armor": 0.0, "max_frame": 20.0}}
	add_child(hs)
	return hs


# --- 2. dead targets reject further mutation on every entry -----------------------
func _test_dead_target_rejection() -> void:
	var hs := _lethal_health()
	await get_tree().process_frame
	hs.take_damage_to_part("body", 9999.0, "kinetic", "frame")
	await get_tree().process_frame
	_check(hs.get("is_destroyed") == true, "lethal frame hit destroys the target")
	var snap_frame: float = float(hs.get("total_frame_hp"))
	hs.take_damage(500.0, "kinetic")
	hs.take_damage_at_point(500.0, Vector3.ZERO, "kinetic")
	hs.take_damage_to_part("body", 500.0, "kinetic", "frame")
	await get_tree().process_frame
	_check(absf(float(hs.get("total_frame_hp")) - snap_frame) < 0.0001, "post-death hits cannot mutate HP (%.2f == %.2f)" % [float(hs.get("total_frame_hp")), snap_frame])
	hs.queue_free()
	await get_tree().process_frame


# --- 3. one lifecycle: exactly one death emission ----------------------------------
func _test_single_death_emission() -> void:
	var hs := _lethal_health()
	var deaths := {"n": 0}
	var cb := func() -> void:
		deaths["n"] += 1
	hs.mecha_destroyed.connect(cb)
	add_child(hs)
	await get_tree().process_frame
	hs.take_damage_to_part("body", 9999.0, "kinetic", "frame")
	await get_tree().process_frame
	await get_tree().process_frame
	hs.take_damage(9999.0, "kinetic")
	hs.take_damage_at_point(9999.0, Vector3.ZERO, "kinetic")
	hs.take_damage_to_part("body", 9999.0, "kinetic", "frame")
	await get_tree().process_frame
	_check(int(deaths["n"]) == 1, "one destruction lifecycle emits mecha_destroyed exactly once (got %d)" % int(deaths["n"]))
	hs.queue_free()
	await get_tree().process_frame
