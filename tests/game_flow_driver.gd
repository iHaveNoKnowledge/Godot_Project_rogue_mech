extends Node

## Integration driver for the REAL game scenes (not isolated panels). Lives on
## /root so it survives the scene swaps enter_board()/enter_combat() perform
## (change_scene_to_file frees the current scene — the test scene itself).
##
## Verifies the new behaviors in the real game:
##   BOARD  — board loads, the token walks, an event popup opens, and closing
##            it does NOT reload the board scene nor restart the intermission
##            BGM (the fix that kept walking uninterrupted by event popups).
##   COMBAT — game_world boots with the new systems: extended escape zones,
##            screen-top RETREAT banner (turns on when standing in a zone),
##            core HUD energy readout, mecha + enemy energy fields, and a
##            rusher that breaks off to recharge when drained.
## Run via: godot --headless --path . res://tests/game_flow_verify.tscn

var _fails := 0
var _checks := 0
var _music_track_id: int = -1


func _ready() -> void:
	# The driver must keep ticking while the tree is paused (event popups pause
	# the whole tree, and scene swaps re-enter it).
	process_mode = Node.PROCESS_MODE_ALWAYS


func run() -> void:
	GlobalData.reset_run_data()
	GlobalData.ensure_hangar_roster()
	GlobalData.save_run()

	await _verify_board_walk_and_event()
	# The weapon-instance flow uses GlobalData/LoadoutSystem only (the same
	# calls the pickup + hangar make), so it can run right after the board.
	await _verify_weapon_instances()
	# Install a REAL emergency scrap patch on the body before combat so the
	# combat mech's _init_parts() applies its weak scrap armor stats.
	_install_test_scrap_patch()
	await _verify_combat()

	# Leave combat the way a real player does (the pause menu's abandon path)
	# so the engine unloads the world through its own scene machinery.
	GameManager.return_to_board()
	var back: Node = await _wait_for_board()
	_check(back != null, "return_to_board lands back on the board after combat")
	# The patch shattered in combat — enter the REAL hangar and confirm the
	# garage mech no longer renders any scrap patch on the body.
	await _verify_hangar_after_patch()

	# The board restarts the intermission BGM; stop it and wait out the full
	# 1s fade so no MP3 stream is decoding when the audio thread tears down at
	# exit (a live playback at exit segfaults the dummy renderer's teardown
	# even though every check above passed).
	AudioManager.stop_music()
	for i in range(90):
		await get_tree().process_frame

	print("GAME_FLOW_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("FLOW_OK: " + label)
	else:
		_fails += 1
		print("FLOW_FAIL: " + label)
		push_error("FAIL: " + label)


# Waits until the current scene is the board (or a timeout elapses).
func _wait_for_board(max_frames: int = 120) -> Node:
	for i in range(max_frames):
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("move_to_tile"):
			return scene
	return null


func _wait_for_combat(max_frames: int = 120) -> Node:
	for i in range(max_frames):
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene != null and scene.get_node_or_null("ArenaGenerator") != null:
			return scene
	return null


# Waits until the current scene is the hangar (HangarScene has garage_panel).
func _wait_for_hangar(max_frames: int = 120) -> Node:
	for i in range(max_frames):
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene != null and "garage_panel" in scene:
			return scene
	return null


# Waits until at least one enemy is alive in the current scene (spawns after
# the ~1s drop-pod delay), or a timeout elapses.
func _wait_for_enemies(max_frames: int = 1200) -> Array:
	for i in range(max_frames):
		await get_tree().physics_frame
		var enemies := get_tree().get_nodes_in_group("enemy")
		var alive: Array = []
		for e in enemies:
			if is_instance_valid(e) and e.get("health_system") != null:
				var hs = e.health_system
				# 1-arg Object.get() (a 2-arg get is only valid on Dictionaries).
				if not bool(hs.get("is_destroyed")):
					alive.append(e)
		if not alive.is_empty():
			return alive
	return []


# Picking up the same gun twice must create TWO separate stash instances
# (each with its own uid/durability), and equipping the same model in BOTH
# hands must work when the player owns 2+ copies — the real flow the pickup
# (register_weapon) and the hangar (set_hand_weapon) use.
func _verify_weapon_instances() -> void:
	var stash_before: int = GlobalData.weapon_inventory.size()
	var pile_bunker := "res://resources/mech/stock/weapon_pile_bunker.tres"
	# Exactly what weapon_pickup.send_to_depot() does for each pickup.
	GlobalData.register_weapon(pile_bunker, "Pile Bunker")
	GlobalData.register_weapon(pile_bunker, "Pile Bunker")
	var gained: int = GlobalData.weapon_inventory.size() - stash_before
	_check(gained == 2, "picking up the same gun twice registers 2 separate stash instances (got %d)" % gained)
	_check(GlobalData.count_owned_weapon(pile_bunker) == 2, "stash counts both gun copies separately")

	# Hangar equip path: left hand takes one copy, right hand takes the other.
	GlobalData.set_hand_weapon("left", pile_bunker)
	GlobalData.set_hand_weapon("right", pile_bunker)
	_check(str(GlobalData.weapon_loadout.get("left", "")) == pile_bunker, "left hand holds a gun copy")
	_check(str(GlobalData.weapon_loadout.get("right", "")) == pile_bunker, "right hand holds the second gun copy")
	_check(GlobalData.count_owned_weapon(pile_bunker) == 2, "both gun copies stay in the stash after dual-wield equip")


# Installs a REAL emergency scrap patch on the body slot (the same RepairSystem
# call the intermission repair panel makes) so the combat mech loads with weak
# scrap armor that must SHATTER when its HP depletes.
func _install_test_scrap_patch() -> void:
	# The patch needs a damaged slot (cost > 0) and scrap to spend.
	GlobalData.part_damage["body"] = 0.9
	GlobalData.scrap = 5000
	var patch: Dictionary = RepairSystem.apply_emergency_repair("body", [])
	_check(not patch.is_empty(), "real RepairSystem installs a scrap patch on the body")
	_check(GlobalData.scrap_patches.has("body"), "scrap patch is recorded in the persistent stash")


func _verify_board_walk_and_event() -> void:
	GameManager.enter_board()
	var board: Node = await _wait_for_board()
	_check(board != null, "board scene loads after enter_board")
	if board == null:
		return

	_check(AudioManager.current_music_category == "intermission", "intermission BGM bound on board entry (category=%s)" % AudioManager.current_music_category)
	_music_track_id = AudioManager.current_track.get_instance_id() if AudioManager.current_track else -1

	# Walk the token to an adjacent tile (same movement path the keyboard uses:
	# _try_step). IntermissionUI may be up, so bypass its gate; and we avoid
	# scene-changing tiles (combat / safehouse / city) so the board stays up for
	# the popup test below.
	var mp_before: int = GlobalData.board_mp
	var stepped := false
	for d: Vector2i in board.DIRS:
		var target: Vector2i = board.current_pos + d
		if board.nodes_dict.has(target):
			var tile = board.nodes_dict[target]
			var ttype := str(tile.get_meta("tile_type", "empty"))
			if BoardConfig.is_passable(str(tile.get_meta("terrain", "plain"))) \
					and ttype not in ["combat", "safehouse", "city", "enemy_base", "exit"]:
				if board._try_step(target):
					stepped = true
					break
	_check(stepped, "player token walks to an adjacent board tile")
	_check(GlobalData.board_mp < mp_before or GlobalData.current_tile != Vector2i.ZERO, "walking consumed board MP / moved the token")
	# An event/data tile step can open a popup on its own — close it so the
	# manual popup test below starts from a clean, unpaused board.
	var walk_popup: Node = board.get_node_or_null("EventUI")
	if walk_popup and walk_popup.visible:
		walk_popup._on_continue_pressed()
		await get_tree().process_frame
		await get_tree().process_frame

	# Surface an event popup over the board (like a random encounter).
	var board_instance_id := board.get_instance_id()
	EventBus.event_triggered.emit({
		"name": "TEST REPORT",
		"effect": "none",
		"amount": 0,
		"desc": "Integration check popup.",
	})
	await get_tree().process_frame
	var event_ui: Node = board.get_node_or_null("EventUI")
	_check(event_ui != null and event_ui.visible, "event popup opens over the board")
	_check(get_tree().paused, "tree pauses while the popup is open")
	if event_ui == null:
		return

	# Close it via the real Continue handler. The board must NOT reload and the
	# intermission music must NOT restart (the fix for interrupted walking).
	event_ui._on_continue_pressed()
	await get_tree().process_frame
	await get_tree().process_frame
	var board_after: Node = get_tree().current_scene
	_check(board_after != null and board_after.get_instance_id() == board_instance_id, "closing the popup does NOT reload the board scene")
	_check(not get_tree().paused, "tree unpauses after the popup closes")
	_check(AudioManager.current_music_category == "intermission", "intermission BGM still active after the popup")
	if AudioManager.current_track:
		_check(AudioManager.current_track.get_instance_id() == _music_track_id, "intermission track instance unchanged (not restarted)")

	# The popup close runs the board's in-place refresh (the fix for walking
	# being interrupted): call it and confirm it doesn't error and the token
	# survives. The walk itself was already proven before the popup.
	_check(board_after.has_method("refresh_after_event"), "board exposes refresh_after_event")
	board_after.refresh_after_event()
	await get_tree().process_frame
	_check(board_after.get_node_or_null("PlayerToken") != null, "player token survives the popup close")


func _verify_combat() -> void:
	# Enter a real battle from the board.
	GameManager.enter_combat("grunt")
	var world: Node = await _wait_for_combat()
	_check(world != null, "combat scene loads after enter_combat")
	if world == null:
		return

	# --- Arena + escape zones (extended past the wall) ---
	var zones := get_tree().get_nodes_in_group("escape_zone")
	_check(zones.size() == 4, "real arena generates 4 escape zones (got %d)" % zones.size())
	var arena_half := GlobalData.current_arena_size * 0.5
	var zone_extended := false
	var zone: Node = null
	if not zones.is_empty():
		zone = zones[0]
		var col: CollisionShape3D = null
		for ch in zone.get_children():
			if ch is CollisionShape3D:
				col = ch
				break
		if col and col.shape is BoxShape3D:
			var size := (col.shape as BoxShape3D).size
			var edge: float = maxf(absf(zone.global_position.x), absf(zone.global_position.z))
			var outward: float = edge + minf(size.x, size.z) * 0.5
			zone_extended = outward > arena_half
	_check(zone_extended, "real escape zone trigger reaches past the arena edge (%.0fm half)" % arena_half)

	# --- Combat HUD: screen-top RETREAT banner exists ---
	var combat_hud: Node = _find_node_with(current_scene_or_root(), "retreat_panel")
	_check(combat_hud != null, "combat HUD builds the screen-top RETREAT banner")
	if combat_hud != null:
		_check(combat_hud.retreat_panel != null and not combat_hud.retreat_panel.visible, "RETREAT banner hidden while outside a zone")

	# --- Core HUD: energy readout built (the compile-fixed panel) ---
	var core_hud: Node = _find_node_with(current_scene_or_root(), "energy_bar")
	_check(core_hud != null and core_hud.energy_bar != null, "core HUD builds the energy readout")

	# --- Player mecha energy ---
	var mecha: Node = GameManager.get_player_mecha()
	_check(mecha != null, "player mecha exists in combat")
	if mecha:
		_check("energy" in mecha and "max_energy" in mecha, "player mecha carries the energy pool")

	# --- Standing in an escape zone lights up the RETREAT banner ---
	if zone != null and combat_hud != null and mecha != null:
		mecha.global_position = zone.global_position + Vector3(0, 2.0, 0)
		# Give the physics server a few frames to re-sync the teleported body and
		# emit the Area3D overlap before asserting.
		var detected := false
		for i in range(10):
			await get_tree().physics_frame
			if zone.is_player_inside():
				detected = true
				break
		_check(detected, "escape zone detects the player inside it")
		if detected:
			# The combat HUD repaints every idle frame (status label proves _process
			# runs in the real scene); its poll may race the zone's body detection
			# flicker, so drive the poll deterministically to assert the wiring:
			# a detected player makes the banner visible with the hold countdown.
			var status_text: String = combat_hud.status_label.text if combat_hud.status_label else ""
			_check(status_text.contains("WAVE") or status_text.contains("BOSS"), "combat HUD _process runs in the real scene (%s)" % status_text)
			combat_hud._update_retreat_indicator()
			await get_tree().physics_frame
			_check(combat_hud.retreat_panel.visible, "RETREAT banner shows while the player stands in a zone")
			_check(combat_hud.retreat_label.text.contains("HOLD"), "RETREAT banner shows the hold countdown (%s)" % combat_hud.retreat_label.text)
		# Step out again — in SMALL hops so the physics server reliably crosses
		# the zone boundary and fires body_exited (a single big teleport can be
		# skipped by overlap detection), exactly as a player walking away would.
		var home: Vector3 = Vector3(0, 2.0, 0)
		var hid := false
		for i in range(60):
			var to_home: Vector3 = home - mecha.global_position
			if to_home.length() < 3.0:
				mecha.global_position = home
			else:
				mecha.global_position += to_home.normalized() * 3.0
			await get_tree().physics_frame
			if not combat_hud.retreat_panel.visible:
				hid = true
				break
		_check(hid, "RETREAT banner hides after leaving the zone")

	# --- Enemies spawn with the energy system and retreat when drained ---
	var enemies: Array = await _wait_for_enemies()
	_check(not enemies.is_empty(), "enemies spawn in real combat")
	# The real wave spawns units one-by-one via pending coroutines (await
	# enemy.ready in _spawn_enemy). Wait until the count is stable so every
	# spawn has fully finished before we verify/teardown — quitting while a
	# spawn coroutine is still in flight leaks that enemy's resources at exit
	# (a dummy-renderer teardown segfault that is otherwise unreproducible
	# when the wave has settled).
	var prev_count := -1
	var stable_frames := 0
	for i in range(240):
		await get_tree().physics_frame
		var count := get_tree().get_nodes_in_group("enemy").size()
		if count == prev_count:
			stable_frames += 1
			if stable_frames >= 30:
				break
		else:
			prev_count = count
			stable_frames = 0
	if not enemies.is_empty():
		var enemy_with_energy: Node = null
		var rusher: Node = null
		for e in enemies:
			if "energy" in e and "dash_energy_cost" in e and enemy_with_energy == null:
				enemy_with_energy = e
			var arch_raw = e.get("archetype")
			if arch_raw != null and int(arch_raw) == 0 and rusher == null:
				rusher = e
		_check(enemy_with_energy != null, "spawned enemies carry the energy pool + per-archetype tuning")
		if rusher != null and mecha != null:
			_check(rusher.dash_energy_cost > 0.0, "a rusher spawned with its tuned dash cost")
			# Park the player right next to the rusher so it spots and engages it
			# (spawn ring is ~110m out — out of the 50m detection range), then
			# drain the pool: it must break off to recharge (StateFlee).
			mecha.global_position = rusher.global_position + Vector3(6.0, 2.0, 0.0)
			await get_tree().physics_frame
			await get_tree().physics_frame
			var saw_target := rusher.target != null
			_check(saw_target, "rusher detects the nearby player")
			rusher.energy = 5.0
			var fled := false
			for i in range(90):
				await get_tree().physics_frame
				if rusher.state_machine and rusher.state_machine.current_state and rusher.state_machine.current_state.name == "StateFlee":
					fled = true
					break
			_check(fled, "drained rusher breaks off to recharge in real combat")
			# Recharge so it can chase again for the wall-barrier check below.
			rusher.energy = rusher.max_energy
			if rusher.flee_reason != "":
				rusher.flee_reason = ""

		# --- A chasing enemy must be STOPPED by the retreat wall barrier ---
		# (the enemy-only StaticBody on layer 32: enemies never walk through the
		# glow wall, only the player does).
		await _verify_enemy_blocked_by_retreat_wall(rusher, mecha)
		# --- The real scrap patch shatters when its armor HP depletes ---
		await _verify_scrap_patch_shatters(mecha)


# A chasing enemy (rusher) must be physically stopped by the retreat wall
# barrier: park the player just past the glow wall (outside the arena edge, on
# the escape apron), drop the rusher just inside it, and confirm the rusher
# chases toward the player but never crosses the barrier plane.
func _verify_enemy_blocked_by_retreat_wall(rusher: Node, mecha: Node) -> void:
	var world: Node = current_scene_or_root()
	if world == null or rusher == null or mecha == null:
		return
	# Locate a RetreatWallBarrier (enemy-only StaticBody, layer 32).
	var barrier: Node = null
	var stack: Array = [world]
	while not stack.is_empty() and barrier == null:
		var node: Node = stack.pop_back()
		if node is StaticBody3D and node.name == "RetreatWallBarrier":
			barrier = node
			break
		for child in node.get_children():
			stack.append(child)
	_check(barrier != null, "real combat scene contains a RetreatWallBarrier")
	if barrier == null:
		return

	# Determine the barrier's blocking axis: the box is slim (1.5m) on the axis
	# that spans the arena edge, thick on the other two.
	var size := Vector3(20.0, 8.0, 1.5)
	for child in barrier.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			size = (child.shape as BoxShape3D).size
	var axis := "z" if size.z < size.x else "x"
	var plane: float = barrier.global_position.z if axis == "z" else barrier.global_position.x
	# Player beyond the wall (outside arena edge, still on the escape apron).
	var outward := 1.0 if (barrier.global_position.z if axis == "z" else barrier.global_position.x) > 0.0 else -1.0
	if axis == "z":
		mecha.global_position = Vector3(0, 2.0, plane + outward * 4.0)
		rusher.global_position = Vector3(0, 1.0, plane - outward * 8.0)
	else:
		mecha.global_position = Vector3(plane + outward * 4.0, 2.0, 0)
		rusher.global_position = Vector3(plane - outward * 8.0, 1.0, 0)
	# Give the AI a moment to spot the player and start chasing.
	var spotted := false
	for i in range(30):
		await get_tree().physics_frame
		if rusher.target != null:
			spotted = true
			break
	_check(spotted, "rusher spots the player standing beyond the retreat wall")
	# Let it chase for a while; it must never cross the barrier plane.
	var crossed := false
	for i in range(240):
		await get_tree().physics_frame
		if not is_instance_valid(rusher):
			break
		var coord: float = rusher.global_position.z if axis == "z" else rusher.global_position.x
		if axis == "z":
			if (outward > 0.0 and coord >= plane + 0.5) or (outward < 0.0 and coord <= plane - 0.5):
				crossed = true
				break
		else:
			if (outward > 0.0 and coord >= plane + 0.5) or (outward < 0.0 and coord <= plane - 0.5):
				crossed = true
				break
	_check(not crossed, "chasing rusher never crosses the retreat wall barrier")


# The real scrap patch installed before combat must behave exactly like normal
# armor: when its armor HP hits zero the patch is removed from the persistent
# stash (GlobalData.scrap_patches), so the hangar stops showing it.
func _verify_scrap_patch_shatters(mecha: Node) -> void:
	if mecha == null:
		return
	var hs: Node = mecha.get_node_or_null("HealthSystem")
	_check(hs != null, "player mech carries a HealthSystem in real combat")
	if hs == null:
		return
	_check(GlobalData.scrap_patches.has("body"), "scrap patch still present at the start of combat")
	_check(hs.has_method("is_armor_broken") and not hs.is_armor_broken("body"), "patched body armor is intact at the start of combat")
	# Destroy the patch's armor exactly like a plate taking a big hit.
	hs.take_damage_to_part("body", 9999.0, "kinetic", "armor")
	await get_tree().physics_frame
	_check(hs.is_armor_broken("body"), "patch armor breaks like normal armor in real combat")
	_check(not GlobalData.scrap_patches.has("body"), "shattered scrap patch is removed from the persistent stash in real combat")


# After combat returns to the board, enter the REAL hangar and confirm the
# garage mech no longer renders any scrap patch on the shattered slot.
func _verify_hangar_after_patch() -> void:
	# The body patch shattered in combat, so the stash must be empty of it.
	_check(not GlobalData.scrap_patches.has("body"), "stash has no body scrap patch when entering the hangar")
	GameManager.enter_hangar()
	var hangar: Node = await _wait_for_hangar()
	_check(hangar != null, "hangar scene loads after combat")
	if hangar == null:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var gp = hangar.get("garage_panel") if "garage_panel" in hangar else null
	if gp:
		# Drive the real display path (the same refresh the nav panel calls).
		gp.update_all_slots_preview()
		await get_tree().process_frame
		await get_tree().process_frame
		var pmm: Node = gp.get_part_mesh_manager()
		_check(pmm != null, "hangar garage builds a PartMeshManager")
		if pmm:
			var patch_visible := _mech_has_visible_scrap_patch(pmm)
			_check(not patch_visible, "hangar garage mech shows no scrap patch after it shattered")
			# The body slot must still render (frame + armor) — only the scrap
			# patch primitives were removed. slot_meshes is the real render state.
			var body_entry: Variant = pmm.get("slot_meshes").get("body", {}) if pmm.get("slot_meshes") is Dictionary else {}
			var body_renders := false
			if body_entry is Dictionary:
				var armor_node: Node = body_entry.get("armor") if body_entry.has("armor") else null
				var frame_node: Node = body_entry.get("frame") if body_entry.has("frame") else null
				body_renders = (armor_node != null and armor_node.visible) or (frame_node != null and frame_node.visible)
			_check(body_renders, "hangar body slot still renders after the patch shattered")
	# Back to the board so the standard teardown (music fade + quit) runs as usual.
	GameManager.enter_board()
	await _wait_for_board()


# Scans a PartMeshManager's mech for any visible ScrapPatch primitive container
# (rendered only while GlobalData.scrap_patches holds that slot).
func _mech_has_visible_scrap_patch(pmm: Node) -> bool:
	if pmm == null:
		return false
	var stack: Array = [pmm.get_parent()]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == null:
			continue
		if node.name == "ScrapPatch" and node.get("visible") == true:
			return true
		for child in node.get_children():
			stack.append(child)
	return false


# --- helpers ---------------------------------------------------------------

func current_scene_or_root() -> Node:
	var scene := get_tree().current_scene
	return scene if scene != null else get_tree().root


func _find_node_with(root: Node, property: String) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node != null and property in node:
			return node
		for child in node.get_children():
			stack.append(child)
	return null
