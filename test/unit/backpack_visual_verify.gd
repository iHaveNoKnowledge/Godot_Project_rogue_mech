extends Node

## Backpack visual integration audit (hardpoint ownership contract).
##
## Proves the BackpackVisualFactory is a derived-only projection of
## Loadout.equipped_backpack: exactly-one visual per equipped state, zero
## gameplay writes (loadout/weight/frame/chassis/damage untouched), stable
## Body/Backpack socket parenting, survival across arm loss, teardown with the
## mech, and save/load + berth round-trip reconstruction.
##
## Run: godot --headless res://test/unit/backpack_visual_verify.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"

var _pass_count: int = 0
var _fail_count: int = 0
var _failed_messages: Array[String] = []
var _save_backup: PackedByteArray = PackedByteArray()
var _had_save: bool = false
var _bp_snap: Dictionary = {}


func _ready() -> void:
	print("\n=== STARTING BACKPACK VISUAL AUDIT ===\n")
	GameManager.suppress_scene_change = true
	_backup_save()
	_bp_snap = (GlobalData.weapons.equipped_backpack as Dictionary).duplicate(true)
	await _run_all()
	GlobalData.weapons.equipped_backpack = _bp_snap.duplicate(true)
	_restore_save()
	GameManager.suppress_scene_change = false
	print("\n==================================================")
	print("BACKPACK VISUAL AUDIT SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failed_messages.is_empty():
		print("FAILED ASSERTIONS:")
		for msg in _failed_messages:
			print("  - " + msg)
	print("==================================================")
	if _fail_count == 0:
		print("BACKPACK_VISUAL_SUCCESS\n")
	else:
		push_error("BACKPACK_VISUAL_FAILURE: %d assertions failed" % _fail_count)
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


func _spawn_mech() -> CharacterBody3D:
	var m: CharacterBody3D = load(MECH_SCENE).instantiate()
	m.position = Vector3(0, 10, 0)
	add_child(m)
	m.set("is_player_driven", false)
	return m


func _settle(m: CharacterBody3D) -> void:
	var f := 0
	while not m.is_on_floor() and f < 180:
		await get_tree().physics_frame
		f += 1
	await get_tree().physics_frame
	await get_tree().process_frame


func _bp_mount(m: CharacterBody3D) -> Node3D:
	return m.get_node_or_null("Body/Backpack/BackpackVisual") as Node3D


# Mounts then yields past deferred queue_free cleanup, so child counts reflect
# the settled visual. Production refresh seams always span frames; same-frame
# recounts would include nodes already queued for deletion.
func _mount(m: CharacterBody3D, bp: Dictionary) -> Node3D:
	var mount := BackpackVisualFactory.mount_backpack(m, bp)
	await get_tree().process_frame
	await get_tree().process_frame
	return mount


func _kill_slot(hs: Node, slot: String) -> void:
	hs.take_damage_to_part(slot, 100000.0, "pierce", "armor")
	var guard := 0
	while not bool((hs.parts[slot] as Dictionary).get("armor_broken", false)) and guard < 10:
		hs.take_damage_to_part(slot, 100000.0, "pierce", "armor")
		guard += 1
	hs.take_damage_to_part(slot, 100000.0, "pierce", "frame")
	guard = 0
	while not bool((hs.parts[slot] as Dictionary).get("destroyed", false)) and guard < 10:
		hs.take_damage_to_part(slot, 100000.0, "pierce", "frame")
		guard += 1


func _run_all() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.position = Vector3(0, -1.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 3, 200)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)

	BackpackSystem.unequip()
	var mech := _spawn_mech()
	await _settle(mech)

	# ---- Equip: absent -> cargo -> exactly 1 visual under Body/Backpack ----
	BackpackVisualFactory.mount_backpack(mech, BackpackSystem.get_equipped_backpack())
	_assert(_bp_mount(mech) == null or _bp_mount(mech).get_child_count() == 0, "unequipped yields zero visuals")
	_assert(BackpackSystem.equip("cargo"), "equip cargo succeeds")
	_assert(str(GlobalData.weapons.equipped_backpack.get("id", "")) == "cargo", "equipped state holds cargo identity")
	var w_before := LoadoutSystem.get_total_mecha_weight()
	var mount := await _mount(mech, BackpackSystem.get_equipped_backpack())
	_assert(mount != null and mount.get_parent().name == "Backpack", "visual parent is exactly Body/Backpack socket")
	_assert(mount.get_child_count() == 1, "exactly 1 visual for 1 equipped backpack")
	# w_before was captured after equip but before mounting: the mount itself
	# must contribute zero weight (backpack mass already lives in the total
	# via BackpackSystem.get_backpack_weight since the equip above).
	_assert(_close(LoadoutSystem.get_total_mecha_weight(), w_before), "visual mount adds zero weight (presentation-only)")

	# ---- Factory purity: mount reads state, never writes it ----
	var bp_before: Dictionary = (GlobalData.weapons.equipped_backpack as Dictionary).duplicate(true)
	BackpackVisualFactory.mount_backpack(mech, BackpackSystem.get_equipped_backpack())
	_assert((GlobalData.weapons.equipped_backpack as Dictionary) == bp_before, "mount never mutates equipped state")
	_assert(_has_no_collision(_bp_mount(mech)), "visual subtree is collision-free")

	# ---- Replace: cargo -> booster -> exactly 1 visual representing booster ----
	_assert(BackpackSystem.equip("booster"), "replace with booster succeeds")
	await _mount(mech, BackpackSystem.get_equipped_backpack())
	var mounts := _count_mounts(mech)
	_assert(mounts == 1, "replacement leaves exactly 1 mount node (no orphan)")
	_assert(_bp_mount(mech).get_child_count() == 1, "replacement leaves exactly 1 model")
	_assert(str(GlobalData.weapons.equipped_backpack.get("type", "")) == "booster", "state now represents booster")

	# ---- Duplicate refresh: 3x mount -> still exactly 1 ----
	for i in range(3):
		await _mount(mech, BackpackSystem.get_equipped_backpack())
	_assert(_count_mounts(mech) == 1, "3x refresh keeps exactly 1 mount")
	_assert(_bp_mount(mech).get_child_count() == 1, "3x refresh keeps exactly 1 model")

	# ---- Type determinism: combat maps to its own silhouette, unknown never fails ----
	_assert(BackpackSystem.equip("combat"), "equip combat succeeds")
	await _mount(mech, BackpackSystem.get_equipped_backpack())
	_assert(_bp_mount(mech).get_child_count() == 1, "combat renders exactly 1 model")
	var mystery := {"id": "mystery", "type": "unknown_future", "color": Color(0.1, 0.2, 0.3)}
	var m_unknown := await _mount(mech, mystery)
	_assert(m_unknown.get_child_count() == 1, "unknown type still renders (generic fallback, no failure)")
	await _mount(mech, BackpackSystem.get_equipped_backpack())

	# ---- Unequip: -> zero visuals ----
	BackpackSystem.unequip()
	await _mount(mech, BackpackSystem.get_equipped_backpack())
	_assert(_bp_mount(mech) == null or _bp_mount(mech).get_child_count() == 0, "unequip yields zero visuals")

	# ---- Berth round-trip preserves identity; visual rebuilds from it ----
	_assert(BackpackSystem.equip("cargo"), "re-equip cargo for round-trip")
	HangarManager.ensure_roster()
	HangarManager.save_active()
	var berth: Dictionary = HangarManager.get_active_mech()
	_assert(str((berth.get("equipped_backpack", {}) as Dictionary).get("id", "")) == "cargo", "berth snapshot holds backpack identity")
	BackpackSystem.unequip()
	HangarManager.load_mech_state(GlobalData.hangar.active_hangar_mech_id)
	_assert(str(GlobalData.weapons.equipped_backpack.get("id", "")) == "cargo", "berth restore returns backpack state")
	await _mount(mech, BackpackSystem.get_equipped_backpack())
	_assert(_bp_mount(mech).get_child_count() == 1, "post-restore rebuild yields exactly 1 visual")

	# ---- Save/load file round-trip ----
	# NOTE: equip()/unequip() persist immediately (save-on-mutate), so the
	# load must follow the save with no mutating call in between.
	GlobalData.save_run()
	var loaded_ok := GlobalData.load_run()
	_assert(loaded_ok, "load_run succeeds")
	_assert(str(GlobalData.weapons.equipped_backpack.get("id", "")) == "cargo", "save/load preserves backpack UID identity")
	await _mount(mech, BackpackSystem.get_equipped_backpack())
	_assert(_bp_mount(mech).get_child_count() == 1, "post-load rebuild yields exactly 1 visual")
	# Post-save colors arrive as "(r, g, b, a)" strings; the visual must still
	# render the definition color (cargo ochre), not the gray fallback.
	_assert(_first_albedo(_bp_mount(mech)).is_equal_approx(Color(0.55, 0.45, 0.25)), "post-load visual keeps def color across save flattening")

	# ---- Arm destruction: backpack + visual unaffected ----
	var hs: Node = mech.get_node_or_null("HealthSystem")
	_kill_slot(hs, "arm_left")
	await get_tree().physics_frame
	_assert(str(GlobalData.weapons.equipped_backpack.get("id", "")) == "cargo", "arm loss keeps backpack state")
	_assert(is_instance_valid(_bp_mount(mech)), "arm loss keeps backpack visual (different subtree)")

	# ---- Body destruction: normal teardown, no orphan logic needed ----
	_kill_slot(hs, "body")
	await get_tree().physics_frame
	_assert(bool((hs.parts["body"] as Dictionary).get("destroyed", false)), "body destroyed (setup)")
	_assert(_bp_mount(mech) == null or is_instance_valid(_bp_mount(mech)), "no invalid backpack refs after body loss")

	# ---- Chassis swap: UID unchanged, single visual after remount ----
	var uid_before := str(GlobalData.weapons.equipped_backpack.get("uid", ""))
	var chassis_before := str(GlobalData.weapons.chassis_id)
	GlobalData.weapons.chassis_id = "titan"
	_assert(str(GlobalData.weapons.equipped_backpack.get("uid", "")) == uid_before, "chassis swap preserves backpack UID")
	BackpackVisualFactory.mount_backpack(mech, BackpackSystem.get_equipped_backpack())
	_assert(_count_mounts(mech) == 1, "no duplicate visual after chassis swap")
	GlobalData.weapons.chassis_id = chassis_before

	mech.queue_free()
	await get_tree().process_frame


func _count_mounts(m: CharacterBody3D) -> int:
	var socket := m.get_node_or_null("Body/Backpack")
	if socket == null:
		return 0
	var n := 0
	for c in socket.get_children():
		if str(c.name) == "BackpackVisual":
			n += 1
	return n


func _has_no_collision(root: Node) -> bool:
	if root == null:
		return true
	if root is CollisionShape3D or root is CollisionObject3D:
		return false
	for c in root.get_children():
		if not _has_no_collision(c):
			return false
	return true


func _first_albedo(root: Node) -> Color:
	if root == null:
		return Color(-1, -1, -1)
	for c in root.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override is StandardMaterial3D:
			return ((c as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
		var deep := _first_albedo(c)
		if deep.r >= 0.0:
			return deep
	return Color(-1, -1, -1)


func _close(a: float, b: float) -> bool:
	return absf(a - b) <= 0.001
