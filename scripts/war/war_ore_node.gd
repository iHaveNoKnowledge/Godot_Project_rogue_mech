extends Area3D
class_name WarOreNode

## Ore Node — ซ่อนแร่/น้ำมัน ให้ Truck/Humvee มาเก็บแล้วขนกลับ Depot

@export var ore_type: String = "ore" # ore / oil
@export var amount: int = 100
@export var respawn_time: float = 60.0

var _collected: bool = false
var _respawn_timer: float = 0.0


func _ready() -> void:
	add_to_group("ore_node")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	body_entered.connect(_on_body_entered)
	_setup_visual()


func _setup_visual() -> void:
	var mi = MeshInstance3D.new()
	if ore_type == "oil":
		var cyl = CylinderMesh.new()
		cyl.top_radius = 1.2
		cyl.bottom_radius = 1.2
		cyl.height = 2.5
		mi.mesh = cyl
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.15, 0.12)
		mat.roughness = 0.9
		mi.material_override = mat
	else:
		var box = BoxMesh.new()
		box.size = Vector3(2.5, 1.8, 2.5)
		mi.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.65, 0.55, 0.25)
		mat.metallic = 0.3
		mat.roughness = 0.7
		mi.material_override = mat
	add_child(mi)
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(4, 3, 4)
	col.shape = shape
	add_child(col)
	var lbl = Label3D.new()
	lbl.text = "%s\n%d" % [ore_type.to_upper(), amount]
	lbl.font_size = 24
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.outline_size = 6
	lbl.position = Vector3(0, 2.5, 0)
	add_child(lbl)


func _on_body_entered(body: Node) -> void:
	if _collected:
		return
	if body.is_in_group("mecha") or body.is_in_group("vehicle"):
		collect(body)


func collect(collector: Node) -> void:
	if _collected:
		return
	_collected = true
	visible = false
	if ore_type == "oil":
		if collector.has_method("add_fuel"):
			collector.add_fuel(amount)
		else:
			GlobalData.fuel.add_mech_fuel(0, float(amount))
	else:
		# Store on collector for logistic — must haul to Depot
		collector.set_meta("hauled_ore", int(collector.get_meta("hauled_ore", 0)) + amount)
		collector.set_meta("hauled_scrap", int(collector.get_meta("hauled_scrap", 0)) + amount)
	# Respawn after time
	_respawn_timer = respawn_time


func _process(delta: float) -> void:
	if _collected:
		_respawn_timer -= delta
		if _respawn_timer <= 0:
			_collected = false
			visible = true
