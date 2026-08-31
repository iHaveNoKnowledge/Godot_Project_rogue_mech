extends Node3D

## War World MVP — 2000x2000 flat terrain + 2 Main Bases (fortified).
## Phase 1 skeleton: no chunk loader yet, just ground + bases + spawn.

var _bases_spawned: bool = false


func _ready() -> void:
	_setup_ground()
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
		var mi = MeshInstance3D.new()
		var pm = PlaneMesh.new()
		pm.size = Vector2(2000, 2000)
		mi.mesh = pm
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.38, 0.32)
		mat.roughness = 0.95
		mi.material_override = mat
		ground.add_child(mi)


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
	if get_node_or_null("WarCamera") != null:
		return
	# Simple third-person camera behind mecha (reuse PhantomCamera logic simplified)
	var cam = Camera3D.new()
	cam.name = "WarCamera"
	cam.current = true
	cam.fov = 75.0
	cam.position = Vector3(0, 6, 12)
	# look_at needs tree, defer
	cam.set_meta("target_pos", Vector3.ZERO)
	# Attach as sibling of mecha, follow via script
	add_child(cam)
	var follow = Node.new()
	follow.name = "CameraFollow"
	follow.set_script(load("res://scripts/war/war_camera_follow.gd"))
	add_child(follow)
	if follow.has_method("setup"):
		follow.setup(cam, mecha as Node3D)


func _spawn_ore_nodes() -> void:
	var ore_positions = [
		Vector3(400, 0.5, 0), Vector3(-400, 0.5, 200),
		Vector3(200, 0.5, 400), Vector3(-300, 0.5, -300)
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
		ev.position = Vector3(randf_range(-600, 600), 1, randf_range(-400, 400))
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


func _decorate_phase2() -> void:
	WarMapGenerator.decorate_highland(self, Vector3(500, 5, 500))
	WarMapGenerator.decorate_underground_tunnel(self, Vector3(-500, -5, -500))
	WarMapGenerator.spawn_weapon_cache(self, Vector3(300, 1, -300))
	WarMapGenerator.spawn_weapon_cache(self, Vector3(-350, 1, 350))
	for base in [get_node_or_null("FriendlyMainBase"), get_node_or_null("EnemyMainBase")]:
		if base:
			var hangar = WarRealtimeHangar.new()
			hangar.position = Vector3(10, 1, 0)
			base.add_child(hangar)


func _setup_hud() -> void:
	# Tab/I handled by WarHUD overlay
	var hud_script = load("res://scripts/war/war_hud.gd")
	if hud_script:
		var hud = CanvasLayer.new()
		hud.name = "WarHUD"
		hud.set_script(hud_script)
		add_child(hud)
	var minimap = WarMinimap.new()
	add_child(minimap)
	var ambush = WarConvoyAmbush.new()
	ambush.name = "ConvoyAmbush"
	add_child(ambush)
