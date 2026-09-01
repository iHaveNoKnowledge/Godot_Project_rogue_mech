extends Node3D

## War World MVP — 2000x2000 flat terrain + 2 Main Bases (fortified).
## Phase 1 skeleton: no chunk loader yet, just ground + bases + spawn.

var _bases_spawned: bool = false


func _ready() -> void:
	_setup_ground()
	_setup_combat_systems()
	_spawn_bases()
	_spawn_ore_nodes()
	_spawn_logistic_trucks()
	_spawn_data_events()
	_spawn_carrier()
	_spawn_merchant_manager()
	_decorate_phase2()
	_spawn_player_mecha()
	_setup_hud()


func _setup_ground() -> void:
	var ground = get_node_or_null("Ground")
	if ground == null:
		ground = StaticBody3D.new()
		ground.name = "Ground"
		ground.collision_layer = 2
		add_child(ground)
		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(2000, 1, 2000)
		col.shape = shape
		ground.add_child(col)
		_ensure_ground_mesh(ground)
	else:
		# Scene already has Ground (collision only) — ensure visual mesh + grid exist.
		if not _ground_has_mesh(ground):
			_ensure_ground_mesh(ground)


func _ground_has_mesh(ground: Node) -> bool:
	for child in ground.get_children():
		if child is MeshInstance3D:
			# PlaneMesh/BoxMesh floor counts as ground visual
			var mi := child as MeshInstance3D
			if mi.mesh is PlaneMesh or mi.mesh is BoxMesh:
				# First PlaneMesh found is the floor itself, not a grid line (grid lines are thin strips)
				if mi.mesh is PlaneMesh:
					return true
				# BoxMesh ground in war fallback is 2000x2000 thin — grid lines are 2x2000 thin strips
				if mi.mesh is BoxMesh and (mi.mesh as BoxMesh).size.x > 100.0 and (mi.mesh as BoxMesh).size.z > 100.0:
					return true
			elif mi.mesh is PlaneMesh:
				return true
	return false


func _ensure_ground_mesh(ground: Node) -> void:
	var mi = MeshInstance3D.new()
	var pm = PlaneMesh.new()
	pm.size = Vector2(2000, 2000)
	mi.mesh = pm
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.52, 0.32)
	mat.roughness = 0.85
	mi.material_override = mat
	ground.add_child(mi)
	# Grid lines for orientation (every 200m)
	for x in range(-1000, 1001, 200):
		var line = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(2, 0.1, 2000)
		line.mesh = box
		var lmat = StandardMaterial3D.new()
		lmat.albedo_color = Color(0.6, 0.6, 0.55, 0.5)
		lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		line.material_override = lmat
		line.position = Vector3(x, 0.05, 0)
		ground.add_child(line)
	for z in range(-1000, 1001, 200):
		var line = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(2000, 0.1, 2)
		line.mesh = box
		var lmat = StandardMaterial3D.new()
		lmat.albedo_color = Color(0.6, 0.6, 0.55, 0.5)
		lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		line.material_override = lmat
		line.position = Vector3(0, 0.05, z)
		ground.add_child(line)


func _spawn_bases() -> void:
	if _bases_spawned:
		return
	_bases_spawned = true
	var fb_script = load("res://scripts/arena/forward_base.gd")
	# Friendly Main Base (south)
	var friendly = Node3D.new()
	friendly.name = "FriendlyMainBase"
	friendly.set_script(fb_script)
	add_child(friendly)
	if friendly.has_method("spawn_base"):
		friendly.spawn_base("fortified", Vector3(0, 0, -800))
		friendly.set_meta("team", "friendly")
	# Enemy Main Base (north) with HQ Barrier Shield (90% until within 100m or 10min)
	var enemy = Node3D.new()
	enemy.name = "EnemyMainBase"
	enemy.set_script(fb_script)
	add_child(enemy)
	if enemy.has_method("spawn_base"):
		enemy.spawn_base("fortified", Vector3(0, 0, 800))
		enemy.set_meta("team", "enemy")
		_add_hq_shield(enemy)


func _add_hq_shield(base: Node) -> void:
	var shield = Area3D.new()
	shield.name = "HQBarrierShield"
	shield.collision_layer = 0
	shield.collision_mask = 0
	var col = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 100.0
	col.shape = sphere
	shield.add_child(col)
	shield.set_meta("shield_active", true)
	shield.set_meta("shield_reduction", 0.9)
	base.add_child(shield)
	# Deactivate after 10 minutes
	var timer = Timer.new()
	timer.wait_time = 600.0
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func(): shield.set_meta("shield_active", false))
	shield.add_child(timer)


func _spawn_player_mecha() -> void:
	var mecha = get_node_or_null("Mecha")
	var is_placeholder = mecha != null and mecha.get_node_or_null("PartMeshManager") == null
	if is_placeholder:
		mecha.queue_free()
		mecha = null
	if mecha == null:
		var scene = load("res://scenes/mecha/mecha_base.tscn")
		if scene:
			mecha = scene.instantiate()
			mecha.name = "Mecha"
			add_child(mecha)
			mecha.position = Vector3(0, 3, -750)
			mecha.add_to_group("mecha")
	if mecha and mecha.has_method("set_team"):
		mecha.set_team("friendly")
	_ensure_war_camera(mecha)


func _ensure_war_camera(mecha: Node) -> void:
	if mecha == null:
		return
	if get_node_or_null("MechaCamera") != null or get_node_or_null("WarCamera") != null:
		return
	# Same as Campaign game_world.tscn — Phantom MechaCamera
	var cam_scene = load("res://scenes/camera/mecha_camera.tscn")
	if cam_scene:
		var cam = cam_scene.instantiate()
		cam.name = "MechaCamera"
		add_child(cam)
		return
	var cam = Camera3D.new()
	cam.name = "WarCamera"
	cam.current = true
	cam.fov = 75.0
	add_child(cam)
	var follow = Node.new()
	follow.name = "CameraFollow"
	follow.set_script(load("res://scripts/war/war_camera_follow.gd"))
	add_child(follow)
	if follow.has_method("setup"):
		follow.setup(cam, mecha as Node3D)


func _spawn_ore_nodes() -> void:
	var ore_positions = [
		Vector3(100, 0.5, -650), Vector3(-100, 0.5, -650),
		Vector3(0, 0.5, -600), Vector3(200, 0.5, -700)
	]
	for i in range(ore_positions.size()):
		var node = WarOreNode.new()
		node.position = ore_positions[i]
		node.ore_type = "ore" if i % 2 == 0 else "oil"
		add_child(node)


func _spawn_logistic_trucks() -> void:
	var logistic = WarLogisticSystem.new()
	var depot = Vector3(0, 0, -800)
	for pos in [Vector3(50, 1, -750), Vector3(-50, 1, -750)]:
		var truck = logistic.create_truck(pos, depot)
		add_child(truck)


func _spawn_data_events() -> void:
	var types = ["part", "frame", "module", "weapon"]
	for i in range(3):
		var ev = WarDataEvent.new()
		ev.data_type = types[i % types.size()]
		ev.position = Vector3(randf_range(-150, 150), 1, randf_range(-700, -550))
		add_child(ev)


func _spawn_carrier() -> void:
	var dock = CarrierDock.new()
	var carrier = dock.create_carrier(Vector3(80, 1, -750))
	add_child(carrier)
	# Store dock logic on carrier for later use
	carrier.set_meta("dock_logic", dock)


func _spawn_merchant_manager() -> void:
	var mgr = WarMerchantSystem.new()
	mgr.name = "MerchantManager"
	add_child(mgr)

	var prod = WarProductionQueue.new()
	prod.name = "ProductionQueue"
	add_child(prod)


func _setup_combat_systems() -> void:
	# Reuse Arena combat stack from game_world.tscn (per user: ยกระบบ combat มาใช้แบบเดียวกับ arena)
	for res in [
		["SpawnManager", "res://scripts/systems/spawn_manager.gd"],
		["EffectManager", "res://scripts/effects/effect_manager.gd"],
		["ArenaSeedSystem", "res://scripts/arena/arena_seed_system.gd"],
		["LootSystem", "res://scripts/systems/loot_system.gd"],
		["ConvoyEscort", "res://scripts/systems/convoy_escort.gd"],
	]:
		if get_node_or_null(res[0]) != null:
			continue
		var n = Node3D.new() if res[0] != "ArenaSeedSystem" else Node.new()
		n.name = res[0]
		n.set_script(load(res[1]))
		add_child(n)


func _decorate_phase2() -> void:
	# Place near player start so visible immediately (was 500 away invisible)
	WarMapGenerator.decorate_highland(self, Vector3(150, 5, -650))
	WarMapGenerator.decorate_underground_tunnel(self, Vector3(-150, -5, -650))
	WarMapGenerator.spawn_weapon_cache(self, Vector3(80, 1, -700))
	WarMapGenerator.spawn_weapon_cache(self, Vector3(-80, 1, 350))
	for base in [get_node_or_null("FriendlyMainBase"), get_node_or_null("EnemyMainBase")]:
		if base:
			# Place trigger inside Mech Hangar (now 8x6.5x10 at -7.2,0,0.2) — not floating at 10,1,0
			var hangar_pos := Vector3(-7.2, 0.2, 0.2)
			var mech_hangar = base.get_node_or_null("Mech_Hangar")
			if mech_hangar:
				hangar_pos = mech_hangar.position
			var hangar = WarRealtimeHangar.new()
			hangar.position = hangar_pos
			base.add_child(hangar)


func _setup_hud() -> void:
	# Same HUD as Campaign game_world.tscn — CoreHUD + WeaponHUD + Crosshair + CombatHUD
	for res in [
		["CoreHUD", "res://scenes/ui/core_hud.tscn"],
		["WeaponHUD", "res://scenes/ui/weapon_hud.tscn"],
		["Crosshair", "res://scenes/ui/crosshair.tscn"],
		["CombatHUD", "res://scripts/ui/combat_hud.gd"],
	]:
		if get_node_or_null(res[0]) != null:
			continue
		if res[1].ends_with(".tscn"):
			var sc = load(res[1])
			if sc:
				var n = sc.instantiate()
				n.name = res[0]
				add_child(n)
		else:
			var n = CanvasLayer.new()
			n.name = res[0]
			n.set_script(load(res[1]))
			add_child(n)
	# War extra: Tab/I + Minimap + Ambush
	var hud_script = load("res://scripts/war/war_hud.gd")
	if hud_script and get_node_or_null("WarHUD") == null:
		var hud = CanvasLayer.new()
		hud.name = "WarHUD"
		hud.set_script(hud_script)
		add_child(hud)
	if get_node_or_null("Minimap") == null:
		var minimap = WarMinimap.new()
		add_child(minimap)
	if get_node_or_null("ConvoyAmbush") == null:
		var ambush = WarConvoyAmbush.new()
		ambush.name = "ConvoyAmbush"
		add_child(ambush)
