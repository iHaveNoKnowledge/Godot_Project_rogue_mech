extends Node
class_name WarMerchantSystem

## Merchant — instant buy 1.5-2x cost, spawns every 2-3 min (per PLAN.md 7.5)

var _timer: float = 0.0
var _interval: float = 150.0 # 2.5 min
var _active_merchant: Node = null


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= _interval and _active_merchant == null:
		_timer = 0
		_interval = randf_range(120, 180)
		_spawn_merchant()


func _spawn_merchant() -> void:
	var merchant = Area3D.new()
	merchant.name = "Merchant"
	merchant.position = Vector3(randf_range(-500, 500), 0.5, randf_range(-500, 500))
	merchant.add_to_group("merchant")
	var mi = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(4, 2, 4)
	mi.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.7, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.75, 0.2)
	mat.emission_energy_multiplier = 1.2
	mi.material_override = mat
	merchant.add_child(mi)
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(6, 3, 6)
	col.shape = shape
	merchant.add_child(col)
	var lbl = Label3D.new()
	lbl.text = "MERCHANT\n[F] BUY PARTS (1.5x)"
	lbl.font_size = 20
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0, 2.5, 0)
	merchant.add_child(lbl)
	# Auto despawn 90s
	var timer = Timer.new()
	timer.wait_time = 90.0
	timer.one_shot = true
	timer.timeout.connect(merchant.queue_free)
	merchant.add_child(timer)
	timer.start()
	get_parent().add_child(merchant)
	_active_merchant = merchant
	merchant.tree_exited.connect(func(): _active_merchant = null)
