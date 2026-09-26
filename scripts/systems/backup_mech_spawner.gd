extends Node

const SpawnManagerScript := preload("res://scripts/systems/spawn_manager.gd")

## RESERVE MECH CALL — battlefield backup delivery.
## The player calls a spare hangar mech via TAB > Call Reserve Mech. A drop
## point is picked at the arena edge (clear of solid obstacles), a beacon
## marks the spot and a top-of-screen announcement warns "reserve inbound";
## the mech is delivered 30s later, kneeling and boardable like an eject-parked
## machine.

const RESERVE_DELIVERY_TIME := 30.0
# Beacon lifetime in seconds after delivery (the beacon node is freed after
# the mech lands, so this is only a safety cap).
const DROP_MARKER_LIFETIME := 120.0

# mech_id -> {"drop_pos": Vector3, "timer": float, "marker": Node}
var _pending: Dictionary = {}


func call_reserve_mech(mech_id: String) -> bool:
	if mech_id == "" or _pending.has(mech_id) or not _roster_has(mech_id):
		return false
	# EMP & Jamming Zone: electromagnetic interference blocks reserve delivery.
	if GlobalData.board.current_hazard == GlobalData.HAZARD_EMP_ZONE:
		_announce("RESERVE BLOCKED — EMP JAMMING ACTIVE")
		return false
	var drop_pos := _pick_drop_point()
	if drop_pos == Vector3.INF:
		push_warning("No clear drop point at the arena edge for the reserve mech.")
		return false
	_pending[mech_id] = {
		"drop_pos": drop_pos,
		"timer": RESERVE_DELIVERY_TIME,
		"marker": _spawn_drop_marker(drop_pos),
	}
	_announce("RESERVE MECH INBOUND — ETA %.0fs" % RESERVE_DELIVERY_TIME)
	return true


func _physics_process(delta: float) -> void:
	if _pending.is_empty():
		return
	for mech_id in _pending.keys():
		var info: Dictionary = _pending[mech_id]
		info["timer"] = float(info["timer"]) - delta
		if float(info["timer"]) <= 0.0:
			_deliver(mech_id)


func _deliver(mech_id: String) -> void:
	var info: Dictionary = _pending[mech_id]
	_pending.erase(mech_id)
	var marker = info.get("marker")
	if marker and is_instance_valid(marker):
		marker.queue_free()
	_spawn_reserve_mech(mech_id, info["drop_pos"])
	_announce("RESERVE MECH DELIVERED")


# True when a hangar berth with this id exists (the called mech must be real).
func _roster_has(mech_id: String) -> bool:
	for mech in HangarManager.get_mechs():
		if mech is Dictionary and str(mech.get("id", "")) == mech_id:
			return true
	return false


# A glowing pillar beacon at the drop point so the player can see exactly where
# the reserve mech will land (and defend the LZ).
func _spawn_drop_marker(pos: Vector3) -> Node3D:
	var marker := Node3D.new()
	marker.name = "ReserveDropMarker"
	marker.position = pos

	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 1.4
	cyl.height = 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.8, 1.0, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.7, 1.0)
	mat.emission_energy_multiplier = 1.6
	cyl.material = mat
	mesh.mesh = cyl
	mesh.position = Vector3(0, 1.0, 0)
	marker.add_child(mesh)

	var light := OmniLight3D.new()
	light.omni_range = 14.0
	light.light_color = Color(0.4, 0.85, 1.0)
	light.light_energy = 2.2
	light.position = Vector3(0, 2.2, 0)
	marker.add_child(light)

	get_parent().add_child(marker)
	return marker


# Picks a landing spot at the arena edge: a random ring point clear of solid
# obstacles (same rule that keeps enemy spawns out of terrain). Returns
# Vector3.INF when no clear point could be found after scanning the ring.
func _pick_drop_point() -> Vector3:
	var arena_gen = get_parent().get_node_or_null("ArenaGenerator")
	var half: float = 110.0
	if arena_gen != null and arena_gen.get("arena_size") != null:
		half = float(arena_gen.arena_size) * 0.42
	# Clear of the retreat glow wall (kept at the 240m edge), inside the arena.
	var covers := get_tree().get_nodes_in_group("solid_obstacle")
	for i in range(24):
		var angle := (i / 24.0) * TAU + randf_range(-0.02, 0.02)
		var pos := Vector3(cos(angle) * half, 0.0, sin(angle) * half)
		if _is_blocked(pos, covers):
			continue
		var space := get_viewport().get_world_3d().direct_space_state
		return SpawnManagerScript.snap_to_ground(pos, space)
	return Vector3.INF


func _is_blocked(pos: Vector3, covers: Array) -> bool:
	return SpawnManagerScript.is_pos_blocked_by_covers(pos, covers)


# Spawns the called hangar mech at the drop point, kneeling and boardable —
# exactly like an eject-parked machine (empty cockpit, pilot can climb in).
# The delivered mech is dressed from the CALLED berth's snapshot (not the
# active mech's), and the active mech's loadout is never touched.
func _spawn_reserve_mech(mech_id: String, spawn_pos: Vector3) -> void:
	var backup = preload("res://scenes/mecha/mecha_base.tscn").instantiate()
	backup.name = "ReserveMech"
	backup.add_to_group("backup_mech")
	backup.set_meta("hangar_mech_id", mech_id)
	for child in backup.get_children():
		child.set_process(false)
		child.set_physics_process(false)

	get_parent().add_child(backup)
	# Parked delivery: physics stays off AFTER add_child, because the base
	# _ready cascade re-enables processing (a pre-add disable does not stick).
	backup.set_physics_process(false)
	var pmm = backup.get_node_or_null("PartMeshManager")
	if pmm:
		# Dress the delivered mech from the called berth's armor/frame plates
		# (same snapshot path ally bodies use) instead of the active mech's.
		var loadout := _mech_catalog_loadout(mech_id)
		if not loadout.is_empty() and pmm.has_method("refresh_from_loadout"):
			pmm.refresh_from_loadout(loadout)
		elif pmm.has_method("refresh_slots"):
			pmm.refresh_slots()
		if pmm.has_method("set_cockpit_open"):
			pmm.set_cockpit_open(true, false)
			pmm.set_cockpit_pilot_seated(false)

	# Animation node is MechaAnimation (the legacy "AnimationSystem" name was
	# renamed; get_node_or_null keeps this safe on older dummy scenes).
	var anim = backup.get_node_or_null("MechaAnimation")
	if anim:
		anim.set_process(true)
		anim.set_physics_process(true)
		if anim.has_method("set_kneeling"):
			anim.set_kneeling(true)

	var space := get_viewport().get_world_3d().direct_space_state
	var pos := SpawnManagerScript.snap_to_ground(spawn_pos, space)
	pos.y -= SpawnManagerScript.body_bottom_offset(backup)
	backup.global_position = pos


# Builds the per-slot frame + armor loadout dict from a berth's snapshot so the
# reserve mech renders exactly like that mech in the hangar (same catalog path
# the ally bodies + enemy bodies use). Shared helper lives in SaveGameIO.
func _mech_catalog_loadout(mech_id: String) -> Dictionary:
	for mech in HangarManager.get_mechs():
		if not (mech is Dictionary) or str(mech.get("id", "")) != mech_id:
			continue
		return SaveGameIO.build_mech_catalog_loadout(mech)
	return {}


# Top-of-screen announcement via the combat HUD banner (fades automatically).
func _announce(text: String) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var hud = scene.get_node_or_null("CombatHUD")
	if hud and hud.has_method("announce"):
		hud.announce(text)
