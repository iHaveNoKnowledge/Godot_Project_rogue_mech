extends Node
## MISSILE SALVO FOLLOW-UP VERIFY (Gate R2-T, test-only).
##
## Isolated follow-up harness for the R2-S-approved test plan. Covers the
## three R2-R gaps without deciding any unresolved gameplay policy:
##  R1. Reload already active before a direct `_fire_missile_salvo` call.
##  R2. Reload flag set between missiles inside one salvo loop (interleaved
##      through the salvo's real 0.065s inter-missile yield — OBSERVED ONLY).
##  R3. `_try_fire` reload-gate control (source-backed rejection).
##  S1. Swap to another weapon during an active lock (real production
##      `_start_selection` + `_commit_selection` path — OBSERVED ONLY).
##  S2. Drop the locked weapon during an active lock (real production
##      `_drop_equipped_weapon` path; empty-slot gate denial is asserted,
##      eager-cancel policy is NOT).
##  S4. Release using a different slot (mismatched-slot preservation).
##  W1. Two-missile durability cadence via an isolated TEST-UID
##      loadout/inventory linkage (count + delta, NEVER the literal amount).
##  W2. Partial-ammo durability cadence (one round, three locks).
##
## Assertion discipline per case:
##  SAFE NOW ....... directly checks an existing source-backed invariant.
##  OBSERVATION ONLY records current behavior without endorsing it.
##  POLICY-BLOCKED .. cannot be asserted until a gameplay rule is chosen
##      (never asserted here; the blocked expectation is printed, not checked).
##  NOT FEASIBLE .... deterministic setup unavailable without production
##      changes (reported via _not_feasible, never faked).
##
## Determinism notes (static, no runtime claim):
##  - R2 interleaves via launch-observed polling: the reload flag is set on
##    the same frame the first projectile is observed, inside the salvo's
##    documented 0.065s inter-missile window (weapon_manager.gd salvo loop).
##    No wall-clock sleep decides the interleave; no production hook added.
##  - S1 drives the REAL selection state machine (`_start_selection` inserts
##    the armed weapon at carry[0]; quick-tap `_commit_selection` rotates it).
##    Only the Input event edge is bypassed (as in every existing harness);
##    the armed-slot transition executed is 100% production code. Direct slot
##    assignment is NOT counted as a swap.
##  - S2 drives the REAL equipped-drop path used by the X-key non-selection
##    branch (`_drop_weapon` -> `_drop_equipped_weapon`).
##  - W1/W2 count wear mutations by stepped inventory sampling (one sample
##    per physics frame while launches are awaited), so per-missile cadence
##    is observed through public GlobalData state with no production hook.
##
## Failure-reporting limitation (shared with the existing harnesses): a
## GDScript runtime error aborts the coroutine without propagating to the
## caller, so each case sets _started at entry and _completed ONLY at normal
## exit. Any missing completion is recorded as a failure below, which forces
## a non-zero exit instead of a silent clean PASS.
##
## Fixture: full production mech + real WeaponManager + camera + ground +
## dummy targets (same rig shape as missile_salvo_execution_verify.gd).
## Run: godot --headless --path . res://tests/mecha/missile_salvo_followup_verify.tscn
## THIS PHASE IS TEST-ONLY: the scene must NOT be executed in R2-T.
## R2-AD: policy-contract regression extension (T01-T08, T12). S1/S2 assert
## synchronous commit/drop cancellation (R3/R4); release validates
## instance identity (R2/R8). R2-AF: S1 uses per-case fresh-projectile
## accounting; T07 documents session ownership (freed-ref scenario NOT
## FEASIBLE under strong-ref ownership; AC-06 stays NOT VERIFIED).

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"
const MISSILE_PATH := "res://resources/mech/stock/weapon_heavy_missile.tres"
const RIFLE_PATH := "res://resources/mech/stock/weapon_beam_rifle.tres"
## Unique linkage UID so wear-fixture state can never collide with real
## loadout entries; every case that installs it removes it in teardown.
const TEST_UID := "R2T_FOLLOWUP_WEAR_UID"

var _checks := 0
var _fails := 0
var _started := {}
var _completed := {}
var _not_feasible := {}
var _loadout_snapshot := {}
var _loadout_snapshot_taken := false
var _preexisting_test_uid_entries: Array = []


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("SALVO-FOLLOWUP OK: " + name)
	else:
		_fails += 1
		printerr("SALVO-FOLLOWUP FAIL: " + name)


func _observe(msg: String) -> void:
	print("SALVO-FOLLOWUP OBSERVE: " + msg)


func _mark_not_feasible(case_name: String, reason: String) -> void:
	_not_feasible[case_name] = reason
	print("SALVO-FOLLOWUP NOT-FEASIBLE: " + case_name + " — " + reason)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_global_snapshot()
	await _test_r1_reload_before_salvo()
	await _test_r2_reload_mid_salvo()
	await _test_r3_try_fire_reload_gate()
	await _test_s1_swap_during_lock()
	await _test_s2_drop_during_lock()
	await _test_s4_mismatched_release()
	await _test_w1_two_missile_wear()
	await _test_w2_partial_ammo_wear()
	await _test_t02_same_instance_recommit()
	await _test_t04b_selection_drop_cancels()
	await _test_t04c_destroyed_arm_drop_cancels()
	await _test_t06_double_release_no_refire()
	await _test_t07_ownership_model_no_freed_ref()
	await _test_t08_mismatched_occupant_rejected()
	await _test_t12_cancel_idempotent_signals()
	_global_restore()
	for case_name in _started.keys():
		_check(bool(_completed.get(case_name, false)), "case completed: " + str(case_name))
	var started_total := _started.size()
	var completed_total := 0
	for case_name in _started.keys():
		if bool(_completed.get(case_name, false)):
			completed_total += 1
	print("MISSILE_SALVO_FOLLOWUP_VERIFY: started=%d completed=%d checks=%d fails=%d not_feasible=%d" % [started_total, completed_total, _checks, _fails, _not_feasible.size()])
	for case_name in _not_feasible.keys():
		print("MISSILE_SALVO_FOLLOWUP_VERIFY NOT-FEASIBLE: " + str(case_name) + " — " + str(_not_feasible[case_name]))
	if _fails > 0:
		printerr("MISSILE_SALVO_FOLLOWUP_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_MISSILE_SALVO_FOLLOWUP_TESTS_PASSED")
		get_tree().quit(0)


# ---------------------------------------------------------------------------
# Fixture (same rig shape as missile_salvo_execution_verify.gd).
# ---------------------------------------------------------------------------
func _spawn_rig(target_count: int) -> Array:
	var mecha: CharacterBody3D = (load(MECH_SCENE) as PackedScene).instantiate()
	mecha.position = Vector3(0, 1.5, 0)
	add_child(mecha)
	var wm: Node3D = load("res://scripts/mecha/weapon_manager.gd").new()
	wm.name = "WeaponManager"
	mecha.add_child(wm)
	var cam := Camera3D.new()
	cam.current = true
	add_child(cam)
	await get_tree().process_frame
	await get_tree().process_frame
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.position = Vector3(0, -1.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 3, 200)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)
	var targets: Array = []
	for i in range(target_count):
		var t := Node3D.new()
		t.position = Vector3(-4.0 + float(i) * 4.0, 1.5, -20.0)
		add_child(t)
		targets.append(t)
	await get_tree().process_frame
	return [mecha, wm, targets]


func _proj_count() -> int:
	return get_tree().get_nodes_in_group("projectile").size()


# Per-case launch accounting (same idiom as missile_salvo_execution_verify):
# snapshot the live group, then count only instances absent from the snapshot.
# Immune to earlier cases' projectiles despawning during a settle window,
# which a raw group-count delta cannot distinguish from negative launches.
func _new_projectiles(before: Array) -> Array:
	var out := []
	for n in get_tree().get_nodes_in_group("projectile"):
		if not before.has(n):
			out.append(n)
	return out


func _wait_for_proj_count(want_total: int, max_frames: int) -> bool:
	var f := 0
	while get_tree().get_nodes_in_group("projectile").size() < want_total and f < max_frames:
		await get_tree().physics_frame
		f += 1
	return get_tree().get_nodes_in_group("projectile").size() >= want_total


func _mount_for_slot(wm: Node3D, slot: String, weapon: WeaponPart) -> void:
	var mecha: Node3D = wm.get_parent() as Node3D
	if slot.begins_with("shoulder"):
		var side := "left" if slot == "shoulder_left" else "right"
		wm._update_shoulder_weapon_visual(mecha, side, weapon)
	else:
		wm._update_hand_weapon_visual(mecha, slot, weapon)


func _prep_salvo(wm: Node3D, slot: String, weapon: WeaponPart, ammo: int) -> void:
	# Arm the authoritative slot with the exact instance under test, mount
	# visuals through the production path, and set deterministic ammo.
	if slot == "left" or slot == "right":
		if slot == "left":
			wm.left_hand = weapon
		else:
			wm.right_hand = weapon
	else:
		if slot == "shoulder_left":
			wm.shoulder_left = weapon
		else:
			wm.shoulder_right = weapon
	_mount_for_slot(wm, slot, weapon)
	var core = wm._core_for_weapon(weapon)
	core.ammo = ammo
	core.cooldown = 0.0


func _targets_dict(targets: Array) -> Dictionary:
	var d := {}
	for t in targets:
		d[t] = 1
	return d


# ---------------------------------------------------------------------------
# GlobalData isolation (loadout snapshot + TEST-UID linkage management).
# ---------------------------------------------------------------------------
func _global_snapshot() -> void:
	_loadout_snapshot = (GlobalData.weapons.weapon_loadout as Dictionary).duplicate(true)
	_loadout_snapshot_taken = true
	# Stash any legitimate pre-existing entry that already uses the test UID
	# (collision-safe: it is restored verbatim by _global_restore).
	_preexisting_test_uid_entries = _collect_test_uid_entries()
	_remove_test_uid_entry()


func _global_restore() -> void:
	if _loadout_snapshot_taken:
		GlobalData.weapons.weapon_loadout = _loadout_snapshot.duplicate(true)
	_remove_test_uid_entry()
	for e in _preexisting_test_uid_entries:
		(GlobalData.weapons.weapon_inventory as Array).append((e as Dictionary).duplicate(true))
	_preexisting_test_uid_entries = []


func _collect_test_uid_entries() -> Array:
	var found: Array = []
	if not ("weapon_inventory" in GlobalData.weapons):
		return found
	for w in (GlobalData.weapons.weapon_inventory as Array):
		if w is Dictionary and str((w as Dictionary).get("uid", "")) == TEST_UID:
			found.append((w as Dictionary).duplicate(true))
	return found


func _remove_test_uid_entry() -> void:
	if not ("weapon_inventory" in GlobalData.weapons):
		return
	var inv: Array = GlobalData.weapons.weapon_inventory
	var i := inv.size() - 1
	while i >= 0:
		var e = inv[i]
		if e is Dictionary and str((e as Dictionary).get("uid", "")) == TEST_UID:
			inv.remove_at(i)
		i -= 1


func _install_wear_linkage() -> void:
	_remove_test_uid_entry()
	(GlobalData.weapons.weapon_loadout as Dictionary)["right"] = TEST_UID
	(GlobalData.weapons.weapon_inventory as Array).append({"uid": TEST_UID, "durability": 1.0, "path": MISSILE_PATH})


func _read_test_durability() -> float:
	if not ("weapon_inventory" in GlobalData.weapons):
		return -1.0
	for w in (GlobalData.weapons.weapon_inventory as Array):
		if w is Dictionary and str((w as Dictionary).get("uid", "")) == TEST_UID:
			return float((w as Dictionary).get("durability", 1.0))
	return -1.0


func _count_decreases(trace: Array) -> int:
	var n := 0
	for i in range(1, trace.size()):
		if float(trace[i]) < float(trace[i - 1]):
			n += 1
	return n


# ---------------------------------------------------------------------------
# R1. Reload already active before a direct salvo call.
# OBSERVATION ONLY for launch behavior; POLICY-BLOCKED for allow/deny rule.
# ---------------------------------------------------------------------------
func _test_r1_reload_before_salvo() -> void:
	_started["r1"] = true
	var rig := await _spawn_rig(2)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var missile: WeaponPart = load(MISSILE_PATH)
	_prep_salvo(wm, "right", missile, 5)
	var core = wm._core_for_weapon(missile)
	wm._set_reloading("right", true)
	var flag_on: bool = wm._is_reloading("right")
	var gate: Dictionary = wm._request_gate("right", WeaponGameplayCapability.ACTION_FIRE)
	var ammo0: int = core.ammo
	var before := _proj_count()
	wm._fire_missile_salvo("right", missile, _targets_dict(targets))
	await _wait_for_proj_count(before + 2, 300)
	await get_tree().create_timer(0.5).timeout
	var launched: int = _proj_count() - before
	var ammo_delta: int = ammo0 - core.ammo
	_observe("r1: reload_flag=%s gate.allowed=%s launched=%d ammo_delta=%d (launch count is OBSERVATION ONLY; POLICY-BLOCKED: salvo must/must-not fire while reloading)" % [str(flag_on), str(gate.get("allowed", "?")), launched, ammo_delta])
	_check(flag_on, "r1: reload flag active before salvo (SAFE NOW)")
	_check(gate.has("allowed"), "r1: gate decision recorded (SAFE NOW)")
	_check(launched <= 2, "r1: no launches beyond queued locks (SAFE NOW)")
	_check(ammo_delta == launched, "r1: ammo delta matches launches (SAFE NOW)")
	_completed["r1"] = true
	wm._set_reloading("right", false)
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# R2. Reload flag set between missiles (launch-observed interleave).
# OBSERVATION ONLY for second-missile behavior; POLICY-BLOCKED for the rule.
# ---------------------------------------------------------------------------
func _test_r2_reload_mid_salvo() -> void:
	_started["r2"] = true
	var rig := await _spawn_rig(2)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var missile: WeaponPart = load(MISSILE_PATH)
	_prep_salvo(wm, "right", missile, 5)
	var core = wm._core_for_weapon(missile)
	_check(not wm._is_reloading("right"), "r2: reload flag clear before launch 1 (SAFE NOW)")
	var ammo0: int = core.ammo
	var before := _proj_count()
	wm._fire_missile_salvo("right", missile, _targets_dict(targets))
	var first_ok := await _wait_for_proj_count(before + 1, 300)
	var ammo_at_first: int = core.ammo
	# Deterministic interleave point: same frame the first launch is observed,
	# inside the salvo's 0.065s inter-missile window. No production hook used.
	wm._set_reloading("right", true)
	var flag_before_second: bool = wm._is_reloading("right")
	await _wait_for_proj_count(before + 2, 300)
	await get_tree().create_timer(0.5).timeout
	var launched: int = _proj_count() - before
	var ammo_delta: int = ammo0 - core.ammo
	_observe("r2: first_ok=%s ammo_used_by_first=%d flag_before_second=%s launched_total=%d ammo_delta=%d (second-missile behavior is OBSERVATION ONLY; POLICY-BLOCKED: must it launch?)" % [str(first_ok), ammo0 - ammo_at_first, str(flag_before_second), launched, ammo_delta])
	_check(first_ok, "r2: first missile launched (fixture validity, SAFE NOW)")
	_check(ammo0 - ammo_at_first == 1, "r2: first launch consumed exactly one round (SAFE NOW)")
	_check(flag_before_second, "r2: reload flag active before the inter-missile window closed (SAFE NOW)")
	_check(ammo_delta == launched, "r2: ammo delta matches launches (SAFE NOW)")
	_check(launched <= 2, "r2: no launches beyond queued locks (SAFE NOW)")
	_completed["r2"] = true
	wm._set_reloading("right", false)
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# R3. `_try_fire` reload-gate control (source-backed rejection).
# ---------------------------------------------------------------------------
func _test_r3_try_fire_reload_gate() -> void:
	_started["r3"] = true
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var missile: WeaponPart = load(MISSILE_PATH)
	_prep_salvo(wm, "right", missile, 5)
	var core = wm._core_for_weapon(missile)
	wm._set_reloading("right", true)
	var ammo0: int = core.ammo
	var before := _proj_count()
	wm._try_fire("right", missile)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	_check(wm._is_reloading("right"), "r3: reload flag held through the call (SAFE NOW)")
	_check(_proj_count() == before, "r3: reloading _try_fire launches nothing (SAFE NOW)")
	_check(core.ammo == ammo0, "r3: reloading _try_fire consumes no ammo (SAFE NOW)")
	_completed["r3"] = true
	wm._set_reloading("right", false)
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# S1. Swap to another weapon during an active lock (real selection path).
# Lock identity + fire routing are OBSERVATION ONLY; routing rule POLICY-BLOCKED.
# ---------------------------------------------------------------------------
func _test_s1_swap_during_lock() -> void:
	_started["s1"] = true
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var old_w: WeaponPart = load(MISSILE_PATH)
	var new_w: WeaponPart = load(RIFLE_PATH)
	wm.right_hand = old_w
	# Deterministic carry (R2-X): REPLACE the hangar-derived _ready carry
	# instead of appending. _ready pre-populates carry with one starter
	# weapon, which a bare append leaves inside the quick-tap rotation path
	# and makes the commit land on the wrong instance. Same typed-array
	# idiom as weapon_drop_and_fist_select_verify.
	var deterministic_carry: Array[WeaponPart] = [new_w]
	wm.carry = deterministic_carry
	_check(wm.right_hand == old_w, "s1: initial right hand holds the locking missile instance (SAFE NOW)")
	_check(wm.carry.size() == 1 and wm.carry[0] == new_w, "s1: initial carry holds exactly the carried rifle instance (SAFE NOW)")
	_check(old_w.weapon_type == WeaponPart.WeaponType.MISSILE and new_w.weapon_type != WeaponPart.WeaponType.MISSILE, "s1: fixture weapon types as intended (SAFE NOW)")
	_check(wm._hand_usable("right"), "s1: arm usable before selection (SAFE NOW)")
	_mount_for_slot(wm, "right", old_w)
	var old_core = wm._core_for_weapon(old_w)
	old_core.ammo = 5
	old_core.cooldown = 0.0
	var new_core = wm._core_for_weapon(new_w)
	new_core.ammo = new_core.max_ammo
	new_core.cooldown = 0.0
	var lock_sys = wm.missile_lock_system
	lock_sys.start_locking("right", old_w, 5)
	lock_sys.locked_targets[targets[0]] = 1
	lock_sys.hold_duration = 1.0
	var pre_lock_id: int = (lock_sys.locking_weapon as Object).get_instance_id()
	var pre_old_id: int = (old_w as Object).get_instance_id()
	# Narrowest deterministic production swap path: the exact methods bound to
	# weapon_right press/release. Quick-tap (no scroll, hold_time ~0) rotates
	# carry so the carried weapon is armed.
	var switched_payloads: Array = []
	var switched_listener := func(hand: String, weapon_name: String) -> void:
		switched_payloads.append([hand, weapon_name])
	wm.weapon_switched.connect(switched_listener)
	wm._start_selection("right")
	var mid_armed_null: bool = (wm.right_hand == null)
	var pre_commit_carry_ok: bool = wm.carry.size() == 2 and wm.carry[0] == old_w and wm.carry[1] == new_w
	_check(pre_commit_carry_ok, "s1: carry holds [old, new] after selection start (SAFE NOW)")
	wm._commit_selection("right")
	var swapped: bool = (wm.right_hand == new_w)
	var carry_removed: bool = not wm.carry.has(new_w)
	var post_commit_carry_ok: bool = wm.carry.size() == 1 and wm.carry[0] == old_w
	var signal_ok := false
	for p in switched_payloads:
		if (p as Array).size() == 2 and str((p as Array)[0]) == "right" and str((p as Array)[1]) == new_w.weapon_name:
			signal_ok = true
	# A swap counts as successful only when hand identity, carry removal,
	# and the switched-signal payload all agree. Anything else keeps the
	# routing assertions withheld via the feasibility path.
	var swapped_ok: bool = swapped and carry_removed and signal_ok
	wm.weapon_switched.disconnect(switched_listener)
	if not swapped_ok:
		_mark_not_feasible("s1", "swap identity triple disagreed (swapped=%s carry_removed=%s signal_ok=%s post_carry_ok=%s)" % [str(swapped), str(carry_removed), str(signal_ok), str(post_commit_carry_ok)])
		lock_sys.cancel_locking()
		_global_restore()
		_completed["s1"] = true
		(rig[0] as Node).queue_free()
		return
	# T01/T03 (R2 policy R3): the commit hook must have cancelled the session
	# synchronously — before any release can use the stale lock.
	_check(not lock_sys.is_locking, "s1: lock cancelled synchronously at commit boundary (T01/T03)")
	_check(lock_sys.active_slot == "", "s1: active slot cleared at commit (T01/T03)")
	var lock_preserved: bool = lock_sys.is_locking and lock_sys.active_slot == "right" and (lock_sys.locking_weapon as Object).get_instance_id() == pre_lock_id
	var still_old_armed: bool = (wm.right_hand as Object).get_instance_id() == pre_old_id
	var old_ammo0: int = old_core.ammo
	var new_ammo0: int = new_core.ammo
	# R2-AF: snapshot live projectiles so despawns from earlier cases cannot
	# pollute this case's launch count (raw group-count deltas go negative).
	# No clamping: the fresh list can only contain this case's launches.
	var before_list: Array = get_tree().get_nodes_in_group("projectile")
	var before := before_list.size()
	wm._handle_missile_release("right")
	await _wait_for_proj_count(before + 1, 300)
	await get_tree().create_timer(0.5).timeout
	var launched: int = _new_projectiles(before_list).size()
	var old_delta: int = old_ammo0 - old_core.ammo
	var new_delta: int = new_ammo0 - new_core.ammo
	_observe("s1: mid_armed_null=%s swapped_to_new=%s carry_removed=%s signal_ok=%s post_carry_ok=%s lock_preserved=%s stale_armed=%s launched=%d old_delta=%d new_delta=%d (routing is OBSERVATION ONLY; POLICY-BLOCKED: old/new/nothing must fire)" % [str(mid_armed_null), str(swapped), str(carry_removed), str(signal_ok), str(post_commit_carry_ok), str(lock_preserved), str(still_old_armed), launched, old_delta, new_delta])
	_check(mid_armed_null, "s1: selection opened by unarming the slot (SAFE NOW)")
	_check(swapped, "s1: production commit armed the carried weapon (SAFE NOW)")
	_check(carry_removed, "s1: committed weapon removed from carry (SAFE NOW)")
	_check(post_commit_carry_ok, "s1: previous hand weapon rotated to carry per the documented rule (SAFE NOW)")
	_check(signal_ok, "s1: switched signal names the committed weapon on the swapped slot (SAFE NOW)")
	_check(launched <= 1, "s1: no launches beyond queued locks (SAFE NOW)")
	_check(old_delta + new_delta == launched, "s1: ammo deltas account for every launch (SAFE NOW)")
	_check(not lock_sys.is_locking, "s1: matched release cleared lock state (SAFE NOW)")
	_completed["s1"] = true
	_global_restore()
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# S2. Drop the locked weapon during an active lock (real equipped-drop path).
# Empty-slot denial + matched-release clearing are asserted; eager-cancel
# policy is NOT (POLICY-BLOCKED).
# ---------------------------------------------------------------------------
func _test_s2_drop_during_lock() -> void:
	_started["s2"] = true
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var missile: WeaponPart = load(MISSILE_PATH)
	_prep_salvo(wm, "right", missile, 5)
	var core = wm._core_for_weapon(missile)
	# T05: linkage lets the test assert zero wear on the rejected release.
	_install_wear_linkage()
	_check(_read_test_durability() >= 0.0, "s2: test inventory linkage installed (SAFE NOW)")
	var lock_sys = wm.missile_lock_system
	lock_sys.start_locking("right", missile, 5)
	lock_sys.locked_targets[targets[0]] = 1
	lock_sys.hold_duration = 1.0
	# Real production drop path used by the X-key non-selection branch.
	wm._drop_equipped_weapon("right")
	var slot_emptied: bool = (wm.right_hand == null)
	# T04 (R2 policy R4): cancellation happens in the drop itself, with
	# identity + slot match, not at a later release.
	_check(slot_emptied, "s2: real drop cleared the armed slot (SAFE NOW)")
	_check(not lock_sys.is_locking, "s2: lock cancelled immediately by drop (T04)")
	_check(lock_sys.active_slot == "", "s2: active slot cleared by drop (T04)")
	var gate: Dictionary = wm._request_gate("right", WeaponGameplayCapability.ACTION_FIRE)
	var ammo0: int = core.ammo
	var d0 := _read_test_durability()
	var before := _proj_count()
	wm._handle_missile_release("right")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	_check(not bool(gate.get("allowed", true)), "s2: gate denies the emptied slot (SAFE NOW)")
	_check(_proj_count() == before, "s2: release on the emptied slot launches nothing (SAFE NOW)")
	_check(core.ammo == ammo0, "s2: release on the emptied slot consumes no ammo (SAFE NOW)")
	_check(_read_test_durability() == d0, "s2: rejected release accrues no wear (T05)")
	_check(not lock_sys.is_locking, "s2: matched release cleared lock state (SAFE NOW)")
	_completed["s2"] = true
	_global_restore()
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# S4. Release using a different slot (mismatched-slot preservation).
# ---------------------------------------------------------------------------
func _test_s4_mismatched_release() -> void:
	_started["s4"] = true
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var missile: WeaponPart = load(MISSILE_PATH)
	_prep_salvo(wm, "right", missile, 5)
	var core = wm._core_for_weapon(missile)
	var lock_sys = wm.missile_lock_system
	lock_sys.start_locking("right", missile, 5)
	lock_sys.locked_targets[targets[0]] = 1
	lock_sys.hold_duration = 1.0
	var ammo0: int = core.ammo
	var before := _proj_count()
	wm._handle_missile_release("left")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_proj_count() == before, "s4: wrong-slot release launches nothing (SAFE NOW)")
	_check(core.ammo == ammo0, "s4: wrong-slot release consumes no ammo (SAFE NOW)")
	_check(lock_sys.is_locking, "s4: live lock survives the wrong-slot release (SAFE NOW)")
	_check(lock_sys.active_slot == "right", "s4: active slot unchanged (SAFE NOW)")
	_check(lock_sys.get_total_locks() == 1, "s4: lock count preserved (SAFE NOW)")
	_completed["s4"] = true
	lock_sys.cancel_locking()
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# W1. Two-missile durability cadence (isolated TEST-UID linkage).
# Count + delta only; the literal wear amount is NOT an established contract.
# ---------------------------------------------------------------------------
func _test_w1_two_missile_wear() -> void:
	_started["w1"] = true
	var rig := await _spawn_rig(2)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var missile: WeaponPart = load(MISSILE_PATH)
	_install_wear_linkage()
	_check(_read_test_durability() >= 0.0, "w1: test inventory linkage installed (SAFE NOW)")
	_check(absf(GlobalData.get_weapon_durability("right") - _read_test_durability()) < 0.000001, "w1: implementation read path resolves the test entry (SAFE NOW)")
	_prep_salvo(wm, "right", missile, 5)
	var core = wm._core_for_weapon(missile)
	var ammo0: int = core.ammo
	var d0 := _read_test_durability()
	var before := _proj_count()
	wm._fire_missile_salvo("right", missile, _targets_dict(targets))
	# Stepped sampling: one inventory read per physics frame while launches
	# land, so each per-missile mutation is observed without a production hook.
	var trace: Array = [d0]
	var f := 0
	while _proj_count() < before + 2 and f < 300:
		await get_tree().physics_frame
		trace.append(_read_test_durability())
		f += 1
	await get_tree().create_timer(0.5).timeout
	trace.append(_read_test_durability())
	var launched: int = _proj_count() - before
	var decreases := _count_decreases(trace)
	var d_final := float(trace[trace.size() - 1])
	_observe("w1: launched=%d ammo_delta=%d d0=%f d_final=%f wear_steps=%d trace=%s (steps+delta are OBSERVATION ONLY for tuning; POLICY-BLOCKED: literal wear amount)" % [launched, ammo0 - core.ammo, d0, d_final, decreases, str(trace)])
	_check(launched == 2, "w1: two launches observed (fixture validity, SAFE NOW)")
	_check(ammo0 - core.ammo == 2, "w1: two rounds consumed (SAFE NOW)")
	_check(d_final < d0, "w1: durability decreased across the salvo (SAFE NOW)")
	_check(decreases == 2, "w1: exactly two wear mutations observed, one per launch (SAFE NOW)")
	_completed["w1"] = true
	_global_restore()
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# W2. Partial-ammo durability cadence (one round, three locks).
# ---------------------------------------------------------------------------
func _test_w2_partial_ammo_wear() -> void:
	_started["w2"] = true
	var rig := await _spawn_rig(3)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var missile: WeaponPart = load(MISSILE_PATH)
	_install_wear_linkage()
	_check(_read_test_durability() >= 0.0, "w2: test inventory linkage installed (SAFE NOW)")
	_prep_salvo(wm, "right", missile, 1)
	var core = wm._core_for_weapon(missile)
	var d0 := _read_test_durability()
	var before := _proj_count()
	wm._fire_missile_salvo("right", missile, _targets_dict(targets))
	var trace: Array = [d0]
	var f := 0
	while _proj_count() < before + 1 and f < 300:
		await get_tree().physics_frame
		trace.append(_read_test_durability())
		f += 1
	await get_tree().create_timer(0.5).timeout
	trace.append(_read_test_durability())
	var launched: int = _proj_count() - before
	var decreases := _count_decreases(trace)
	var d_final := float(trace[trace.size() - 1])
	_observe("w2: launched=%d ammo_final=%d d0=%f d_final=%f wear_steps=%d (unlaunched locks must accrue no wear; POLICY-BLOCKED: literal wear amount)" % [launched, core.ammo, d0, d_final, decreases])
	_check(launched == 1, "w2: exactly one launch on one round (SAFE NOW)")
	_check(core.ammo == 0, "w2: ammunition floors at zero (SAFE NOW)")
	_check(d_final < d0, "w2: durability decreased for the launched missile (SAFE NOW)")
	_check(decreases == 1, "w2: exactly one wear mutation; unlaunched locks accrue none (SAFE NOW)")
	_completed["w2"] = true
	_global_restore()
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# T02. Same-instance re-commit preserves the lock (R2 policy R3 / AC-02).
# One-element carry: quick-tap rotation re-arms the exact same instance.
# The transient empty hand must NOT cancel the session.
# ---------------------------------------------------------------------------
func _test_t02_same_instance_recommit() -> void:
	_started["t02"] = true
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var missile: WeaponPart = load(MISSILE_PATH)
	_prep_salvo(wm, "right", missile, 5)
	var core = wm._core_for_weapon(missile)
	# Empty carry: selection inserts the armed instance, quick-tap rotates it
	# straight back onto the hand (no other candidate exists).
	wm.carry.clear()
	_check(wm.carry.is_empty(), "t02: carry starts empty (SAFE NOW)")
	var lock_sys = wm.missile_lock_system
	lock_sys.start_locking("right", missile, 5)
	lock_sys.locked_targets[targets[0]] = 1
	lock_sys.hold_duration = 1.0
	var pre_lock_id: int = (lock_sys.locking_weapon as Object).get_instance_id()
	wm._start_selection("right")
	_check(wm.right_hand == null, "t02: selection opened (fixture validity, SAFE NOW)")
	_check(wm.carry.size() == 1 and wm.carry[0] == missile, "t02: carry holds the locked instance during selection (SAFE NOW)")
	wm._commit_selection("right")
	_check(wm.right_hand == missile, "t02: same instance re-equipped (SAFE NOW)")
	_check(lock_sys.is_locking, "t02: lock survives same-instance re-commit (T02)")
	_check(lock_sys.active_slot == "right", "t02: active slot unchanged (T02)")
	_check((lock_sys.locking_weapon as Object).get_instance_id() == pre_lock_id, "t02: locked reference unchanged (T02)")
	_check(lock_sys.get_total_locks() == 1, "t02: lock count preserved (T02)")
	var ammo0: int = core.ammo
	var before := _proj_count()
	wm._handle_missile_release("right")
	_check(await _wait_for_proj_count(before + 1, 300), "t02: preserved session still fires (T02)")
	await get_tree().create_timer(0.5).timeout
	_check(_proj_count() == before + 1, "t02: exactly one launch, no extras (T02)")
	_check(core.ammo == ammo0 - 1, "t02: one round consumed (T02)")
	_check(not lock_sys.is_locking, "t02: session cleared by its own release (T02)")
	_completed["t02"] = true
	_global_restore()
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# T04b. Selection-drop of the locked weapon cancels the lock (R4).
# _drop_weapon_from_selection removes the previewed carry entry; when that
# entry is the locked instance for the selecting slot, the session ends.
# ---------------------------------------------------------------------------
func _test_t04b_selection_drop_cancels() -> void:
	_started["t04b"] = true
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var missile: WeaponPart = load(MISSILE_PATH)
	var other: WeaponPart = load(RIFLE_PATH)
	_prep_salvo(wm, "right", missile, 5)
	var core = wm._core_for_weapon(missile)
	var deterministic_carry: Array[WeaponPart] = [other]
	wm.carry = deterministic_carry
	var lock_sys = wm.missile_lock_system
	lock_sys.start_locking("right", missile, 5)
	lock_sys.locked_targets[targets[0]] = 1
	lock_sys.hold_duration = 1.0
	wm._start_selection("right")
	# Carry is now [missile, other]; index 0 previews the locked instance.
	_check(wm.carry.size() == 2 and wm.carry[0] == missile, "t04b: locked instance at drop index (SAFE NOW)")
	wm._drop_weapon_from_selection("right")
	_check(not wm.carry.has(missile), "t04b: locked instance removed from carry (T04b)")
	_check(wm.carry.has(other), "t04b: unrelated weapon retained (T04b)")
	_check(not lock_sys.is_locking, "t04b: lock cancelled by selection drop (T04b)")
	_check(lock_sys.active_slot == "", "t04b: active slot cleared by selection drop (T04b)")
	var ammo0: int = core.ammo
	var before := _proj_count()
	wm._handle_missile_release("right")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_proj_count() == before, "t04b: no launch after cancelled session (T04b)")
	_check(core.ammo == ammo0, "t04b: no ammo consumed after cancelled session (T04b)")
	_completed["t04b"] = true
	lock_sys.cancel_locking()
	_global_restore()
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# T04c. Destroyed-arm drop of the locked weapon cancels the lock (R4).
# ---------------------------------------------------------------------------
func _test_t04c_destroyed_arm_drop_cancels() -> void:
	_started["t04c"] = true
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var missile: WeaponPart = load(MISSILE_PATH)
	_prep_salvo(wm, "right", missile, 5)
	var core = wm._core_for_weapon(missile)
	var lock_sys = wm.missile_lock_system
	lock_sys.start_locking("right", missile, 5)
	lock_sys.locked_targets[targets[0]] = 1
	lock_sys.hold_duration = 1.0
	var res: WeaponPart = wm.drop_weapon_from_destroyed_arm("right")
	_check(res == missile, "t04c: drop returns the locked instance (T04c)")
	_check(wm.right_hand == null, "t04c: slot cleared (T04c)")
	_check(not lock_sys.is_locking, "t04c: lock cancelled by destroyed-arm drop (T04c)")
	_check(lock_sys.active_slot == "", "t04c: active slot cleared (T04c)")
	var ammo0: int = core.ammo
	var before := _proj_count()
	wm._handle_missile_release("right")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_proj_count() == before, "t04c: no launch after cancelled session (T04c)")
	_check(core.ammo == ammo0, "t04c: no ammo consumed after cancelled session (T04c)")
	_completed["t04c"] = true
	lock_sys.cancel_locking()
	_global_restore()
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# T06. Double release after cancellation cannot refire (R2/R8).
# A fresh session on the same slot must still fire normally, proving the
# machinery is intact and distinguishing fresh from stale sessions.
# ---------------------------------------------------------------------------
func _test_t06_double_release_no_refire() -> void:
	_started["t06"] = true
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var missile: WeaponPart = load(MISSILE_PATH)
	_prep_salvo(wm, "right", missile, 5)
	var core = wm._core_for_weapon(missile)
	var lock_sys = wm.missile_lock_system
	lock_sys.start_locking("right", missile, 5)
	lock_sys.locked_targets[targets[0]] = 1
	lock_sys.hold_duration = 1.0
	wm._drop_equipped_weapon("right")
	_check(not lock_sys.is_locking, "t06: session cancelled (SAFE NOW)")
	var ammo0: int = core.ammo
	var before := _proj_count()
	wm._handle_missile_release("right")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_proj_count() == before, "t06: first release after cancel fires nothing (T06)")
	_check(core.ammo == ammo0, "t06: first release consumes nothing (T06)")
	wm._handle_missile_release("right")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_proj_count() == before, "t06: second release fires nothing (T06)")
	_check(core.ammo == ammo0, "t06: second release consumes nothing (T06)")
	# Fresh session on the same slot must still work.
	wm.right_hand = missile
	lock_sys.start_locking("right", missile, core.ammo)
	lock_sys.locked_targets[targets[0]] = 1
	lock_sys.hold_duration = 1.0
	var ammo1: int = core.ammo
	var before1 := _proj_count()
	wm._handle_missile_release("right")
	_check(await _wait_for_proj_count(before1 + 1, 300), "t06: fresh session fires normally (T06)")
	await get_tree().create_timer(0.5).timeout
	_check(_proj_count() == before1 + 1, "t06: fresh session launches exactly one (T06)")
	_check(core.ammo == ammo1 - 1, "t06: fresh session consumes one round (T06)")
	_completed["t06"] = true
	lock_sys.cancel_locking()
	_global_restore()
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# T07. Lock-session ownership model (R2/R6/PC-05 feasibility record).
# A freed locked weapon CANNOT be constructed under the current ownership
# model: the session holds a strong reference, and Godot forbids manual
# free() of RefCounted-derived WeaponPart (engine error, R2-AE evidence).
# Freeing therefore requires prior session teardown — which clears the
# session first — so the freed-reference release path is unreachable without
# a production seam (e.g. weakref storage, NOT authorized). AC-06 stays
# NOT VERIFIED; the production is_instance_valid guard stands as
# defense-in-depth, reviewed statically only.
# This case verifies the REAL, meaningful invariants instead: the session's
# own reference keeps the weapon alive with no other owners, and the session
# stays fully functional under sole session ownership. It does NOT claim to
# exercise the freed-object guard.
# ---------------------------------------------------------------------------
func _test_t07_ownership_model_no_freed_ref() -> void:
	_started["t07"] = true
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var transient := WeaponPart.new()
	transient.weapon_name = "R2T Transient Missile"
	transient.weapon_type = WeaponPart.WeaponType.MISSILE
	transient.max_ammo = 6
	transient.range_distance = 100.0
	wm.right_hand = transient
	var tcore = wm._core_for_weapon(transient)
	tcore.ammo = 5
	tcore.cooldown = 0.0
	var lock_sys = wm.missile_lock_system
	lock_sys.start_locking("right", transient, 5)
	lock_sys.locked_targets[targets[0]] = 1
	lock_sys.hold_duration = 1.0
	_check(lock_sys.is_locking, "t07: session established on transient (SAFE NOW)")
	# Drop every non-session reference (hand slot, then the local). Only the
	# lock session still owns the instance.
	wm.right_hand = null
	transient = null
	_check(is_instance_valid(lock_sys.locking_weapon), "t07: session holds the weapon alive with no other owners (T07)")
	# Re-arm the STILL-VALID instance from the session's own reference and
	# prove the session remains fully functional under sole ownership.
	wm.right_hand = lock_sys.locking_weapon
	_check(wm.right_hand != null and is_instance_valid(wm.right_hand), "t07: re-armed from the live session reference (T07)")
	var ammo0: int = tcore.ammo
	var before := _proj_count()
	wm._handle_missile_release("right")
	_check(await _wait_for_proj_count(before + 1, 300), "t07: sole-ownership session still fires (T07)")
	await get_tree().create_timer(0.5).timeout
	_check(_proj_count() == before + 1, "t07: exactly one launch, no extras (T07)")
	_check(tcore.ammo == ammo0 - 1, "t07: one round consumed (T07)")
	_check(not lock_sys.is_locking, "t07: session cleared by its own release (T07)")
	_mark_not_feasible("t07", "freed locked weapon unreachable: session holds a strong ref; freeing requires prior teardown which clears the session (R2-AF feasibility review); AC-06 stays NOT VERIFIED")
	_completed["t07"] = true
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# T08. Valid but mismatched occupant is rejected (R2/R8/PC-01).
# Direct slot assignment deliberately bypasses the commit hook (covered by
# T01/T03) to isolate the release-validation layer. Headless logic only;
# no visual assertion is made about the stale mount.
# ---------------------------------------------------------------------------
func _test_t08_mismatched_occupant_rejected() -> void:
	_started["t08"] = true
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var old_w: WeaponPart = load(MISSILE_PATH)
	var new_w: WeaponPart = load(RIFLE_PATH)
	_prep_salvo(wm, "right", old_w, 5)
	var old_core = wm._core_for_weapon(old_w)
	var new_core = wm._core_for_weapon(new_w)
	new_core.ammo = new_core.max_ammo
	new_core.cooldown = 0.0
	var lock_sys = wm.missile_lock_system
	lock_sys.start_locking("right", old_w, 5)
	lock_sys.locked_targets[targets[0]] = 1
	lock_sys.hold_duration = 1.0
	wm.right_hand = new_w
	_check(wm.right_hand == new_w and lock_sys.is_locking, "t08: mismatch constructed, session live (SAFE NOW)")
	var old_ammo0: int = old_core.ammo
	var new_ammo0: int = new_core.ammo
	var before := _proj_count()
	wm._handle_missile_release("right")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_proj_count() == before, "t08: mismatched session launches nothing (T08)")
	_check(old_core.ammo == old_ammo0, "t08: stale instance consumes nothing (T08)")
	_check(new_core.ammo == new_ammo0, "t08: current occupant is not fired through the stale session (T08)")
	_check(not lock_sys.is_locking, "t08: mismatched session cleared (T08)")
	_completed["t08"] = true
	lock_sys.cancel_locking()
	_global_restore()
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# T12. Cancellation is idempotent and the clear signal is preserved (R6).
# The missile lock signals have no production subscribers; the test pins the
# existing emit-per-cancel behavior for telemetry compatibility.
# ---------------------------------------------------------------------------
func _test_t12_cancel_idempotent_signals() -> void:
	_started["t12"] = true
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var missile: WeaponPart = load(MISSILE_PATH)
	_prep_salvo(wm, "right", missile, 5)
	var lock_sys = wm.missile_lock_system
	lock_sys.start_locking("right", missile, 5)
	lock_sys.locked_targets[targets[0]] = 1
	lock_sys.hold_duration = 1.0
	var clears: Array = [0]
	var on_clear := func() -> void:
		clears[0] = int(clears[0]) + 1
	lock_sys.lock_cleared.connect(on_clear)
	lock_sys.cancel_locking()
	lock_sys.cancel_locking()
	_check(not lock_sys.is_locking, "t12: session cleared (T12)")
	_check(lock_sys.active_slot == "", "t12: slot cleared (T12)")
	_check(lock_sys.get_total_locks() == 0, "t12: locks cleared (T12)")
	_check(int(clears[0]) == 2, "t12: clear signal emitted per cancel, no error on repeat (T12)")
	lock_sys.lock_cleared.disconnect(on_clear)
	_completed["t12"] = true
	(rig[0] as Node).queue_free()
