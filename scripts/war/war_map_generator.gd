extends RefCounted
class_name WarMapGenerator

## Generates HIGHLAND / UNDERGROUND zones + Weapon Cache + Occluder + Chunk markers

static func decorate_highland(parent: Node3D, pos: Vector3) -> void:
	# Grounded mesa — ไม่ลอย (snapped to WarBiomeGenerator ground)
	var xz := Vector2(pos.x, pos.z)
	var mesa := WarBiomeGenerator.spawn_highland_mesa(parent, xz, Vector3(300, 40, 300), 22.0)
	# keep group for AI
	mesa.add_to_group("solid_obstacle")


static func decorate_underground_tunnel(parent: Node3D, pos: Vector3) -> void:
	var tunnel = Node3D.new()
	tunnel.position = pos
	# Floor
	var floor = StaticBody3D.new()
	floor.collision_layer = 2
	var fcol = CollisionShape3D.new()
	var fshape = BoxShape3D.new()
	fshape.size = Vector3(200, 1, 20)
	fcol.shape = fshape
	floor.add_child(fcol)
	var fmi = MeshInstance3D.new()
	var fbox = BoxMesh.new()
	fbox.size = Vector3(200, 1, 20)
	fmi.mesh = fbox
	var fmat = StandardMaterial3D.new()
	fmat.albedo_color = Color(0.18, 0.18, 0.20)
	fmi.material_override = fmat
	floor.add_child(fmi)
	tunnel.add_child(floor)
	# Ceiling with occluder
	var ceiling = MeshInstance3D.new()
	var cbox = BoxMesh.new()
	cbox.size = Vector3(200, 1, 20)
	ceiling.mesh = cbox
	ceiling.position = Vector3(0, 8, 0)
	var cmat = StandardMaterial3D.new()
	cmat.albedo_color = Color(0.15, 0.15, 0.16)
	ceiling.material_override = cmat
	tunnel.add_child(ceiling)
	var occluder = OccluderInstance3D.new()
	var occ_shape = BoxOccluder3D.new()
	occ_shape.size = Vector3(200, 8, 20)
	occluder.occluder = occ_shape
	occluder.position = Vector3(0, 4, 0)
	tunnel.add_child(occluder)
	# SpotLights
	for x in [-60, 0, 60]:
		var light = SpotLight3D.new()
		light.position = Vector3(x, 7, 0)
		light.light_energy = 2.5
		light.spot_range = 30
		light.spot_angle = 45
		tunnel.add_child(light)
	parent.add_child(tunnel)


static func spawn_weapon_cache(parent: Node3D, pos: Vector3) -> void:
	var cache = Area3D.new()
	cache.name = "WeaponCache"
	# snap to ground — ไม่ลอย
	var snapped: Vector3 = WarBiomeGenerator.snap_to_ground(Vector3(pos.x, 0, pos.z), 1.0)
	cache.position = snapped
	cache.add_to_group("weapon_cache")
	var mi = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(3, 2, 3)
	mi.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.65, 0.25, 0.2)
	mat.roughness = 0.7
	mi.material_override = mat
	cache.add_child(mi)
	# ขาตั้งเสายึดกับพื้น — ไม่ลอย
	var stand := MeshInstance3D.new()
	var sbox := BoxMesh.new()
	sbox.size = Vector3(0.4, 1.0, 0.4)
	stand.mesh = sbox
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.35, 0.35, 0.36)
	stand.material_override = smat
	stand.position = Vector3(0, -1.0, 0)
	cache.add_child(stand)
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(4, 3, 4)
	col.shape = shape
	cache.add_child(col)
	var lbl = Label3D.new()
	lbl.text = "WEAPON CACHE\n[F] OPEN"
	lbl.font_size = 18
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0, 2.5, 0)
	cache.add_child(lbl)
	cache.body_entered.connect(func(body):
		if body.is_in_group("mecha") or body.is_in_group("pilot"):
			_open_cache(cache, body)
	)
	parent.add_child(cache)


static func _open_cache(cache: Node, opener: Node) -> void:
	if cache.get_meta("opened", false):
		return
	cache.set_meta("opened", true)
	# Grant random weapon
	var weapons = ["res://resources/mech/stock/weapon_beam_rifle.tres", "res://resources/mech/stock/weapon_heat_blade.tres"]
	var path = weapons[randi() % weapons.size()]
	if ResourceLoader.exists(path):
		GlobalData.weapons.weapon_inventory.append({"path": path, "uid": "cache_%d" % randi()})
		GlobalData.save_run()
	cache.queue_free()
