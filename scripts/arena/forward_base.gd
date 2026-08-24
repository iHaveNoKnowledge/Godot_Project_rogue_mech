extends Node3D
class_name ForwardBase

## Forward Operating Base — destructible enemy camp / fortified base
## Spawns multiple buildings, each with HP, targeted by player.
## Victory: destroy HQ (main hangar/comm tower) + optionally clear all.

signal building_destroyed(name: String, remaining: int)
signal base_destroyed()

var _buildings: Array[Node] = []
var _hq: Node = null
var is_fortified: bool = false # false=camp (tents), true=rooted (concrete)

# Building defs: name, size, pos, color, hp, type
const BUILDINGS_CAMP: Array[Dictionary] = [
	{"name":"Command Tent", "size":Vector3(2.2,1.4,2.4), "pos":Vector3(0,0.7,0), "color":Color(0.42,0.38,0.28), "hp":80.0, "hq":true, "mesh":"prism"},
	{"name":"Barracks Tent A", "size":Vector3(1.8,1.1,2.0), "pos":Vector3(-2.8,0.55,0.6), "color":Color(0.38,0.35,0.28), "hp":45.0, "hq":false, "mesh":"prism"},
	{"name":"Barracks Tent B", "size":Vector3(1.8,1.1,2.0), "pos":Vector3(-2.8,0.55,-1.4), "color":Color(0.38,0.35,0.28), "hp":45.0, "hq":false, "mesh":"prism"},
	{"name":"Mess Tent", "size":Vector3(2.0,1.0,1.6), "pos":Vector3(2.6,0.5,0.8), "color":Color(0.35,0.32,0.28), "hp":35.0, "hq":false, "mesh":"prism"},
	{"name":"Supply Stack", "size":Vector3(1.4,0.9,1.2), "pos":Vector3(2.4,0.45,-1.0), "color":Color(0.40,0.38,0.32), "hp":30.0, "hq":false, "mesh":"box"},
	{"name":"Comm Mast", "size":Vector3(0.35,3.2,0.35), "pos":Vector3(0.9,1.6,1.8), "color":Color(0.28,0.30,0.34), "hp":40.0, "hq":false, "mesh":"cylinder"},
]

const BUILDINGS_FORTIFIED: Array[Dictionary] = [
	{"name":"HQ Warehouse", "size":Vector3(4.2,2.4,3.2), "pos":Vector3(0,1.2,0), "color":Color(0.42,0.42,0.44), "hp":220.0, "hq":true, "mesh":"box"},
	{"name":"Mech Hangar", "size":Vector3(3.8,2.8,3.6), "pos":Vector3(-3.6,1.4,0.2), "color":Color(0.32,0.34,0.36), "hp":180.0, "hq":false, "mesh":"hangar"},
	{"name":"Comm Tower", "size":Vector3(0.45,5.0,0.45), "pos":Vector3(3.2,2.5,1.6), "color":Color(0.26,0.28,0.32), "hp":90.0, "hq":false, "mesh":"tower"},
	{"name":"Barracks Block", "size":Vector3(2.6,1.6,2.2), "pos":Vector3(-2.0,0.8,-2.8), "color":Color(0.36,0.36,0.38), "hp":80.0, "hq":false, "mesh":"box"},
	{"name":"Mess Hall", "size":Vector3(2.4,1.4,1.9), "pos":Vector3(3.0,0.7,-2.4), "color":Color(0.34,0.32,0.30), "hp":60.0, "hq":false, "mesh":"box"},
	{"name":"Tank Depot", "size":Vector3(2.0,1.0,1.2), "pos":Vector3(1.8,0.5,2.8), "color":Color(0.30,0.32,0.30), "hp":50.0, "hq":false, "mesh":"box"},
	{"name":"Training Yard Fence", "size":Vector3(4.0,0.5,3.0), "pos":Vector3(-0.2,0.25,2.9), "color":Color(0.40,0.36,0.28), "hp":25.0, "hq":false, "mesh":"fence"},
]

func _ready() -> void:
	add_to_group("forward_base")
	add_to_group("enemy_base")

func spawn_base(kind: String = "camp", pos: Vector3 = Vector3.ZERO) -> void:
	is_fortified = (kind == "rooted" or kind == "fortified")
	global_position = pos
	_clear()
	var defs: Array[Dictionary] = BUILDINGS_FORTIFIED if is_fortified else BUILDINGS_CAMP
	for def in defs:
		var b := _create_building(def)
		add_child(b)
		_buildings.append(b)
		if def.get("hq", false):
			_hq = b
	# Ground decal — concrete apron for fortified, dirt for camp
	_add_apron(is_fortified)
	# Perimeter lights
	_add_perimeter_lights()
	# Add floating badge
	_add_badge()

func _clear() -> void:
	for b in _buildings:
		if is_instance_valid(b):
			b.queue_free()
	_buildings.clear()
	_hq = null
	for c in get_children():
		if c.name.begins_with("Apron") or c.name.begins_with("Badge"):
			c.queue_free()

func _create_building(def: Dictionary) -> Node3D:
	var root := StaticBody3D.new()
	root.name = str(def.get("name","Building")).replace(" ","_")
	root.collision_layer = 2 | 8
	root.collision_mask = 1
	root.set_script(load("res://scripts/arena/building.gd"))
	root.set("base_ref", self)

	var mesh_type: String = str(def.get("mesh","box"))
	var size: Vector3 = def.get("size", Vector3.ONE)
	var col: Color = def.get("color", Color(0.4,0.4,0.4))
	var hp: float = float(def.get("hp",50.0))

	# Meta for health
	root.set_meta("building_name", str(def.get("name","")))
	root.set_meta("max_hp", hp)
	root.set_meta("hp", hp)
	root.set_meta("is_hq", bool(def.get("hq",false)))

	var mi: MeshInstance3D = null
	match mesh_type:
		"prism":
			mi = MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = size
			pm.left_to_right = 0.7
			mi.mesh = pm
		"hangar":
			mi = _build_hangar_mesh(size, col)
			root.add_child(mi)
			# Collision for hangar (use box)
			var col_shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = size
			col_shape.shape = box
			col_shape.position = Vector3(0, size.y*0.5, 0)
			root.add_child(col_shape)
			# HP label
			_add_hp_label(root, str(def.get("name","")), hp)
			root.set_meta("mesh_instance", mi)
			return root
		"tower":
			# Vertical cylinder + dish
			var base := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.18
			cm.bottom_radius = 0.36
			cm.height = size.y
			base.mesh = cm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = col
			mat.roughness = 0.8
			base.material_override = mat
			base.position = Vector3(0, size.y*0.5, 0)
			root.add_child(base)
			# Dish
			var dish := MeshInstance3D.new()
			var dm := CylinderMesh.new()
			dm.top_radius = 0.85
			dm.bottom_radius = 0.12
			dm.height = 0.18
			dish.mesh = dm
			var dmat := StandardMaterial3D.new()
			dmat.albedo_color = Color(0.72,0.74,0.78,1.0)
			dmat.roughness = 0.4
			dish.material_override = dmat
			dish.position = Vector3(0, size.y + 0.15, 0)
			dish.rotation_degrees = Vector3(18, 0, 0)
			root.add_child(dish)
			# Collision
			var col2 := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.height = size.y
			cyl.radius = 0.35
			col2.shape = cyl
			col2.position = Vector3(0, size.y*0.5, 0)
			root.add_child(col2)
			_add_hp_label(root, str(def.get("name","")), hp)
			return root
		"fence":
			# Training yard as low wall loop
			for i in 4:
				var seg := MeshInstance3D.new()
				var sm := BoxMesh.new()
				var wall_len := size.x if i %2==0 else size.z
				sm.size = Vector3(wall_len, 0.6, 0.12)
				seg.mesh = sm
				var wmat := StandardMaterial3D.new()
				wmat.albedo_color = col
				seg.material_override = wmat
				match i:
					0: seg.position = Vector3(0, 0.3, size.z*0.5)
					1: seg.position = Vector3(size.x*0.5, 0.3, 0)
					2: seg.position = Vector3(0, 0.3, -size.z*0.5)
					3: seg.position = Vector3(-size.x*0.5, 0.3, 0)
				seg.rotation_degrees = Vector3(0, 90 if i%2==1 else 0, 0)
				root.add_child(seg)
			var colf := CollisionShape3D.new()
			var bf := BoxShape3D.new()
			bf.size = Vector3(size.x, 0.6, size.z)
			colf.shape = bf
			colf.position = Vector3(0, 0.3, 0)
			root.add_child(colf)
			_add_hp_label(root, str(def.get("name","")), hp)
			return root
		_:
			mi = MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = size
			mi.mesh = bm

	if mi:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.roughness = 0.82
		# HQ gets striped hazard for visibility
		if bool(def.get("hq",false)):
			mat.emission_enabled = true
			mat.emission = Color(0.35,0.12,0.10)
			mat.emission_energy_multiplier = 0.4
		mi.material_override = mat
		mi.position = Vector3(0, size.y*0.5, 0)
		root.add_child(mi)
		root.set_meta("mesh_instance", mi)

	# Collision
	var col_shape := CollisionShape3D.new()
	var shape: Shape3D
	if mesh_type == "prism":
		var b := BoxShape3D.new()
		b.size = size * Vector3(1.0,0.7,1.0)
		shape = b
	elif mesh_type == "cylinder":
		var c := CylinderShape3D.new()
		c.height = size.y
		c.radius = size.x
		shape = c
	else:
		var b := BoxShape3D.new()
		b.size = size
		shape = b
	col_shape.shape = shape
	col_shape.position = Vector3(0, size.y*0.5, 0)
	root.add_child(col_shape)

	_add_hp_label(root, str(def.get("name","")), hp)
	return root

func _build_hangar_mesh(size: Vector3, col: Color) -> MeshInstance3D:
	var root := MeshInstance3D.new()
	# Hangar as box with open front (simulate via two walls + roof)
	var base := BoxMesh.new()
	base.size = Vector3(size.x, size.y*0.25, size.z)
	var m1 := MeshInstance3D.new()
	m1.mesh = base
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	m1.material_override = mat
	m1.position = Vector3(0, size.y*0.12, 0)
	root.add_child(m1)
	# Walls
	for x in [-size.x*0.45, size.x*0.45]:
		var w := BoxMesh.new()
		w.size = Vector3(0.18, size.y, size.z)
		var wm := MeshInstance3D.new()
		wm.mesh = w
		wm.material_override = mat
		wm.position = Vector3(x, size.y*0.5, 0)
		root.add_child(wm)
	# Roof
	var roof := BoxMesh.new()
	roof.size = Vector3(size.x, 0.15, size.z)
	var rm := MeshInstance3D.new()
	rm.mesh = roof
	rm.material_override = mat
	rm.position = Vector3(0, size.y - 0.07, 0)
	root.add_child(rm)
	# Interior mech silhouette (hint)
	var mech := BoxMesh.new()
	mech.size = Vector3(0.9, 1.6, 0.7)
	var mm := MeshInstance3D.new()
	mm.mesh = mech
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.18,0.20,0.22,1.0)
	mm.material_override = mmat
	mm.position = Vector3(0, 0.8, 0)
	root.add_child(mm)
	return root

func _add_hp_label(root: Node3D, bname: String, hp: float) -> void:
	var lbl := Label3D.new()
	lbl.name = "HPLabel"
	lbl.text = "%s\n%.0f HP" % [bname.to_upper(), hp]
	lbl.font_size = 20
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.outline_size = 6
	lbl.outline_modulate = Color.BLACK
	lbl.modulate = Color(0.92,0.92,0.92,1.0) if not bool(root.get_meta("is_hq")) else Color(1.0,0.55,0.45,1.0)
	lbl.position = Vector3(0, float(root.get_meta("max_hp")) * 0.015 + 2.2, 0)
	root.add_child(lbl)
	root.set_meta("hp_label", lbl)

func _add_apron(fortified: bool) -> void:
	var apron := MeshInstance3D.new()
	apron.name = "Apron"
	var pm := BoxMesh.new()
	var s := 10.0 if fortified else 7.0
	pm.size = Vector3(s, 0.04, s)
	apron.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22,0.22,0.24,1.0) if fortified else Color(0.32,0.30,0.26,1.0)
	mat.roughness = 0.95
	apron.material_override = mat
	apron.position = Vector3(0, 0.02, 0)
	add_child(apron)

func _add_perimeter_lights() -> void:
	for i in 4:
		var ang := float(i) * PI * 0.5
		var pos := Vector3(cos(ang)*4.2, 0.12, sin(ang)*4.2)
		var light := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		light.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0,0.32,0.28,1.0)
		mat.emission_enabled = true
		mat.emission = Color(1.0,0.25,0.20)
		mat.emission_energy_multiplier = 3.0
		light.material_override = mat
		light.position = pos
		add_child(light)

func _add_badge() -> void:
	var badge := Label3D.new()
	badge.name = "Badge"
	badge.text = "ENEMY FORWARD BASE" if is_fortified else "ENEMY CAMP"
	badge.font_size = 32
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.no_depth_test = true
	badge.outline_size = 8
	badge.outline_modulate = Color.BLACK
	badge.modulate = Color(1.0,0.35,0.30,1.0)
	badge.position = Vector3(0, 5.2, 0)
	add_child(badge)

func take_damage(building: Node3D, amount: float) -> void:
	if not is_instance_valid(building) or not building.has_meta("hp"):
		return
	var hp: float = float(building.get_meta("hp")) - amount
	building.set_meta("hp", hp)
	var max_hp: float = float(building.get_meta("max_hp"))
	var lbl: Label3D = building.get_meta("hp_label") as Label3D
	if lbl and is_instance_valid(lbl):
		lbl.text = "%s\n%.0f / %.0f" % [str(building.get_meta("building_name")).to_upper(), maxf(hp,0), max_hp]
		if hp / max_hp < 0.3:
			lbl.modulate = Color(1,0.3,0.25)
		elif hp / max_hp < 0.6:
			lbl.modulate = Color(0.9,0.7,0.25)
	# Flash — some types (fence/mini) store no single mesh_instance; guard the meta
	var mi: MeshInstance3D = null
	if building.has_meta("mesh_instance"):
		mi = building.get_meta("mesh_instance") as MeshInstance3D
	if mi and is_instance_valid(mi):
		var tw := create_tween()
		tw.tween_property(mi, "scale", Vector3(1.06,0.96,1.06), 0.06)
		tw.tween_property(mi, "scale", Vector3.ONE, 0.12)
	if hp <= 0:
		_destroy_building(building)

func _destroy_building(building: Node3D) -> void:
	var bname: String = str(building.get_meta("building_name"))
	var is_hq: bool = bool(building.get_meta("is_hq"))
	# Explosion
	if is_inside_tree() and get_tree().current_scene.has_node("EffectManager"):
		var eff = get_tree().current_scene.get_node("EffectManager")
		if eff and eff.has_method("spawn_explosion"):
			eff.spawn_explosion(building.global_position + Vector3(0,1.0,0), 3.5 if is_hq else 2.2)
	_buildings.erase(building)
	building.queue_free()
	building_destroyed.emit(bname, _buildings.size())
	if is_hq:
		base_destroyed.emit()
		# Also count as combat victory if all HQ gone
		if get_tree().current_scene.has_node("SpawnManager"):
			# let spawn manager know base is down
			pass
	# If all buildings gone, also base destroyed
	if _buildings.is_empty():
		base_destroyed.emit()

func is_destroyed() -> bool:
	return _buildings.is_empty() or (_hq != null and not is_instance_valid(_hq))

func get_remaining_count() -> int:
	return _buildings.size()
