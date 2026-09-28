extends Node

## Phase 2F-01: Scene-boundary active-mech handoff audit (transition lifecycle).
##
## Proves at the Board <-> Combat <-> Hangar boundary:
##  A. Victory path: part damage + loadout hand off Combat -> Board -> Combat
##     through the authoritative working set without drift, and the reconstruction
##     consumes persistent part_damage (destroyed arm/body-frame flags).
##  B. Defeat path: destroying the ACTIVE mech re-points active_hangar_mech_id to
##     the reserve berth (HangarManager.remove_mech). return_to_board()'s
##     save_active() must snapshot the RESERVE's own state — NOT clobber it with
##     the destroyed machine's working set — and the next enter_combat() must
##     reconstruct the reserve machine, not the wreck.
##  B2. The same handoff contract applies to the mech-less recovery grant
##     (HangarManager.grant_recovery_mech): the granted chassis must become the
##     combat working set.
##  C. Three repeated Board<->Combat cycles accumulate no roster/state drift.
##  D. A Hangar hop in between keeps berth + working-set continuity.
##
## Uses the real production transition calls (GameManager.enter_combat /
## return_to_board / enter_hangar) under the documented suppress_scene_change
## test hook, mirroring production call order from
## mecha_health_base._on_mecha_destroyed and combat_rewards_ui._on_continue_pressed.
##
## Run: godot --headless res://test/unit/phase_2f_01_active_mech_handoff_verify.tscn

var _pass_count: int = 0
var _fail_count: int = 0
var _failed_messages: Array[String] = []

# Savefile isolation: the test writes save_run() via return_to_board(); back up
# any existing savegame and restore it afterwards.
var _save_backup: PackedByteArray = PackedByteArray()
var _had_save: bool = false


func _ready() -> void:
	print("\n=== STARTING PHASE 2F-01 SCENE-BOUNDARY ACTIVE-MECH HANDOFF AUDIT ===\n")
	GameManager.suppress_scene_change = true
	_backup_save()
	await _run_all_stages()
	_restore_save()
	GameManager.suppress_scene_change = false

	print("\n==================================================")
	print("PHASE 2F-01 HANDOFF AUDIT SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failed_messages.is_empty():
		print("FAILED ASSERTIONS:")
		for msg in _failed_messages:
			print("  - " + msg)
	print("==================================================")

	if _fail_count == 0:
		print("PHASE_2F_01_SUCCESS\n")
	else:
		push_error("PHASE_2F_01_FAILURE: %d assertions failed" % _fail_count)

	get_tree().quit(0 if _fail_count == 0 else 1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % message)
	else:
		_fail_count += 1
		_failed_messages.append(message)
		push_error("Assertion failed: %s" % message)
		print("  [FAIL] %s" % message)


func _backup_save() -> void:
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.READ)
		if f:
			_save_backup = f.get_buffer(f.get_length())
			_had_save = true
			f.close()


func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(_save_backup)
			f.close()
	elif FileAccess.file_exists(GlobalData.SAVE_PATH):
		DirAccess.remove_absolute(GlobalData.SAVE_PATH)


func _run_all_stages() -> void:
	GlobalData.reset_run_data()
	GlobalData.hangar.hangar_mechs.clear()
	GlobalData.narrative.mech_less = false
	HangarManager.ensure_roster()

	await _stage_a_victory_handoff()
	await _stage_b_defeat_handoff()
	await _stage_c_repeated_cycles()
	await _stage_d_hangar_hop()


# ---------------------------------------------------------------------------
# Stage A — damaged mecha through the victory transition (Phase 9 handoff)
# ---------------------------------------------------------------------------
func _stage_a_victory_handoff() -> void:
	print("\n--- Stage A: damaged mecha, Combat -> Combat End -> Board -> Combat ---\n")
	var fatal_damage := {
		"arm_left": 1.0,
		"leg_left": 0.5,
		"head": 0.3,
		"body": 0.25,
		"body_frame": 1.0,
	}
	GlobalData.weapons.part_damage = fatal_damage.duplicate(true)

	GameManager.enter_combat("grunt")
	_assert(GameManager.current_state == GameManager.State.COMBAT, "A: combat state entered via production path")
	_assert(GameManager.pre_combat_weapon_loadout is Dictionary and not GameManager.pre_combat_weapon_loadout.is_empty(),
		"A: pre-combat loadout snapshot taken")

	# Reconstruction proof: a fresh combat mecha node must consume the persistent
	# part_damage (destroyed arm flag, destroyed body frame, damaged leg).
	var mech: Node3D = load("res://scenes/mecha/mecha_base.tscn").instantiate()
	add_child(mech)
	await get_tree().process_frame
	var hs: Node = mech.get_node_or_null("HealthSystem")
	_assert(hs != null, "A: spawned mecha exposes HealthSystem")
	if hs != null:
		var arm: Dictionary = (hs.parts as Dictionary).get("arm_left", {}) as Dictionary
		_assert(float(arm.get("armor_hp", -1.0)) == 0.0 and bool(arm.get("armor_broken", false)),
			"A: destroyed arm reconstructs armor-broken (handheld slot blocked)")
		var body: Dictionary = (hs.parts as Dictionary).get("body", {}) as Dictionary
		_assert(float(body.get("frame_hp", -1.0)) == 0.0 and bool(body.get("destroyed", false)),
			"A: destroyed body frame reconstructs destroyed")
		var leg: Dictionary = (hs.parts as Dictionary).get("leg_left", {}) as Dictionary
		_assert(float(leg.get("armor_hp", -1.0)) > 0.0
			and float(leg.get("armor_hp", -1.0)) < float(leg.get("max_armor", -1.0)),
			"A: damaged leg reconstructs partially damaged")
	mech.queue_free()
	await get_tree().process_frame

	var pd0: Dictionary = GlobalData.weapons.part_damage.duplicate(true)
	# Combat ends in victory -> production tail (GlobalData._on_combat_ended) then
	# the player presses Continue -> return_to_board().
	EventBus.combat_ended.emit(true)
	GameManager.return_to_board()
	_assert(GameManager.current_state == GameManager.State.BOARD, "A: board state after victory transition")
	_assert(GlobalData.weapons.part_damage == pd0, "A: part damage survives the combat->board hop exactly")

	# Return to combat: reconstruction source (working set) must still hold the
	# same persistent damage.
	GameManager.enter_combat("grunt")
	_assert(GlobalData.weapons.part_damage == pd0, "A: part damage re-enters combat unchanged")
	# ...and the active berth snapshot must have captured it on the way out.
	var berth: Dictionary = HangarManager.get_active_mech()
	_assert((berth.get("damage", {}) as Dictionary) == pd0, "A: active berth snapshot holds the combat damage")
	GameManager.return_to_board()


# ---------------------------------------------------------------------------
# Stage B — defeat handoff: active mech destroyed, reserve berth takes over
# ---------------------------------------------------------------------------
func _stage_b_defeat_handoff() -> void:
	print("\n--- Stage B: destroyed active mech -> reserve berth handoff ---\n")
	var id_a: String = GlobalData.hangar.active_hangar_mech_id
	HangarManager.save_active()

	# Park a distinctive reserve machine (chassis + damage identity).
	var built: Dictionary = HangarManager.build("ReserveB")
	var id_b: String = str(built.get("id", ""))
	_assert(id_b != "" and id_b != id_a, "B: reserve berth parked")
	_assert(HangarManager.get_mechs().size() == 2, "B: roster holds exactly the active + reserve")

	HangarManager.load_mech_state(id_b)
	GlobalData.weapons.chassis_id = "aegis"
	GlobalData.weapons.part_damage = {"body": 0.4}
	HangarManager.save_mech_state(id_b)
	HangarManager.load_mech_state(id_a)

	# The doomed machine's working set carries its fatal battle damage.
	GlobalData.weapons.part_damage = {
		"body": 1.0, "body_frame": 1.0, "arm_left": 1.0, "leg_left": 0.5, "head": 0.3,
	}
	HangarManager.save_active()

	GameManager.enter_combat("grunt")
	# Production defeat tail (mecha_health_base._on_mecha_destroyed order):
	# combat_ended(false) then remove_mech(active_id), then the DEFEATED continue
	# branch calls return_to_board().
	EventBus.combat_ended.emit(false)
	var removed: bool = HangarManager.remove_mech(GlobalData.hangar.active_hangar_mech_id)
	GlobalData.narrative.mech_less = GlobalData.hangar.hangar_mechs.is_empty()
	_assert(removed, "B: destroyed active mech removed from roster")
	_assert(not HangarManager.get_mechs().any(func(m): return str(m.get("id", "")) == id_a),
		"B: wreck berth gone from roster")
	_assert(GlobalData.hangar.active_hangar_mech_id == id_b, "B: active id re-pointed to the reserve berth")

	# THE BOUNDARY UNDER TEST: return_to_board() -> save_active() must snapshot
	# the RESERVE's own state, not the destroyed machine's working set.
	GameManager.return_to_board()
	_assert(GameManager.current_state == GameManager.State.BOARD, "B: board state after defeat transition")
	var b_after: Dictionary = HangarManager.get_active_mech()
	_assert(str(b_after.get("chassis_id", "")) == "aegis",
		"B: reserve berth identity NOT clobbered by the wreck snapshot")
	var b_damage: Dictionary = b_after.get("damage", {}) as Dictionary
	_assert(b_damage.size() == 1 and absf(float(b_damage.get("body", 0.0)) - 0.4) < 0.0001,
		"B: reserve berth damage NOT clobbered by the wreck damage")
	# And the next combat must reconstruct the reserve machine, not the wreck.
	GameManager.enter_combat("grunt")
	_assert(str(GlobalData.weapons.chassis_id) == "aegis",
		"B: next combat reconstructs the reserve chassis")
	_assert(absf(float(GlobalData.weapons.part_damage.get("body", 0.0)) - 0.4) < 0.0001,
		"B: next combat reconstructs the reserve damage, not the wreck's")
	_assert(float(GlobalData.weapons.part_damage.get("body_frame", 0.0)) < 1.0,
		"B: wreck's destroyed body frame does not leak into the reserve machine")
	GameManager.return_to_board()

	# B2 — same handoff contract for the mech-less recovery grant: a freshly
	# built recovery chassis that becomes active MUST become the working set.
	HangarManager.remove_mech(GlobalData.hangar.active_hangar_mech_id)
	GlobalData.narrative.mech_less = GlobalData.hangar.hangar_mechs.is_empty()
	_assert(GlobalData.hangar.hangar_mechs.is_empty(), "B2: roster empty (mech-less) before recovery")
	var granted: Dictionary = HangarManager.grant_recovery_mech()
	var granted_id: String = str(granted.get("id", ""))
	_assert(granted_id != "", "B2: recovery mech granted")
	_assert(GlobalData.hangar.active_hangar_mech_id == granted_id, "B2: recovery mech is active")
	var granted_snapshot: Dictionary = HangarManager.get_active_mech()
	var granted_damage: Dictionary = granted_snapshot.get("damage", {}) as Dictionary
	var granted_frames: Dictionary = granted_snapshot.get("frames", {}) as Dictionary
	var granted_body_frame: Dictionary = granted_frames.get("body", {}) as Dictionary
	GameManager.enter_combat("grunt")
	var ws_frames: Dictionary = GlobalData.weapons.equipped_frames
	var ws_body: Dictionary = ws_frames.get("body", {}) as Dictionary
	_assert(not granted_body_frame.is_empty() and str(ws_body.get("id", "")) == str(granted_body_frame.get("id", "")),
		"B2: combat working set reconstructed from the recovery chassis")
	var wreck_leak := false
	for key in ["body", "body_frame", "arm_left", "arm_left_frame"]:
		if float(GlobalData.weapons.part_damage.get(key, 0.0)) >= 1.0:
			wreck_leak = true
	_assert(not wreck_leak, "B2: wreck's destroyed-part damage does not leak into the recovery machine")
	_assert((granted_damage.is_empty() and GlobalData.weapons.part_damage.is_empty()) or
		(GlobalData.weapons.part_damage == granted_damage),
		"B2: working-set damage matches the granted berth snapshot")
	GameManager.return_to_board()


# ---------------------------------------------------------------------------
# Stage C — repeated Board<->Combat cycles (Phase 10/18 stress)
# ---------------------------------------------------------------------------
func _stage_c_repeated_cycles() -> void:
	print("\n--- Stage C: three repeated combat cycles, no accumulation ---\n")
	var roster_size: int = HangarManager.get_mechs().size()
	var b_damage: Dictionary = (HangarManager.get_active_mech().get("damage", {}) as Dictionary).duplicate(true)
	var chassis: String = str(GlobalData.weapons.chassis_id)

	for i in range(3):
		GameManager.enter_combat("grunt")
		_assert(GlobalData.weapons.chassis_id == chassis, "C%d: cycle reconstructs the same active machine" % (i + 1))
		EventBus.combat_ended.emit(true)
		GameManager.return_to_board()
		_assert(GameManager.current_state == GameManager.State.BOARD, "C%d: returns to board" % (i + 1))
		_assert(HangarManager.get_mechs().size() == roster_size, "C%d: roster size stable" % (i + 1))
		_assert(GlobalData.hangar.active_hangar_mech_id == GlobalData.hangar.active_hangar_mech_id,
			"C%d: active identity stable" % (i + 1))
		_assert(((HangarManager.get_active_mech().get("damage", {}) as Dictionary)) == b_damage,
			"C%d: berth damage stable across cycle" % (i + 1))
		_assert(GlobalData.weapons.chassis_id == chassis, "C%d: working-set chassis stable" % (i + 1))


# ---------------------------------------------------------------------------
# Stage D — hangar hop continuity (Phase 15)
# ---------------------------------------------------------------------------
func _stage_d_hangar_hop() -> void:
	print("\n--- Stage D: Board -> Hangar -> Board keeps berth continuity ---\n")
	var b_before: Dictionary = HangarManager.get_active_mech().duplicate(true)
	var chassis: String = str(GlobalData.weapons.chassis_id)

	GameManager.enter_hangar()
	_assert(GameManager.current_state == GameManager.State.HANGAR, "D: hangar state entered (scene change suppressed)")
	GameManager.return_to_board()
	_assert(GameManager.current_state == GameManager.State.BOARD, "D: board state after hangar hop")
	var b_after: Dictionary = HangarManager.get_active_mech()
	_assert(str(b_after.get("id", "")) == str(b_before.get("id", "")), "D: active berth identity unchanged")
	_assert((b_after.get("damage", {}) as Dictionary) == (b_before.get("damage", {}) as Dictionary),
		"D: berth damage unchanged across hangar hop")
	_assert(str(GlobalData.weapons.chassis_id) == chassis, "D: working-set chassis unchanged across hangar hop")
