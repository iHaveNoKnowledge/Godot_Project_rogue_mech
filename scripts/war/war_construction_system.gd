extends RefCounted
class_name WarConstructionSystem

## Factory รถก่อสร้างฐาน — ขน ore ไปสร้าง Outpost/Bunker/Ruins กลางสนามรบ
## ใช้คู่กับ WarConstructionAI (AI loop depot <-> build_site)

static func create_construction_truck(pos: Vector3, depot_pos: Vector3, build_site: Vector3 = Vector3.ZERO) -> Node3D:
	var truck := CharacterBody3D.new()
	truck.name = "ConstructionTruck"
	truck.position = pos
	truck.add_to_group("vehicle")
	truck.add_to_group("construction_truck")
	truck.collision_layer = 1
	truck.collision_mask = 2
	truck.set_meta("depot_pos", depot_pos)
	truck.set_meta("is_ai_driven", true)
	truck.set_meta("hauled_ore", 0)

	# AI
	var ai := WarConstructionAI.new()
	ai.name = "ConstructionAI"
	if build_site != Vector3.ZERO:
		ai.build_site = build_site
	truck.add_child(ai)

	# --- Visual: 6-wheel construction truck with crane ---
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.8, 2.4, 7.0)
	body.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.82, 0.62, 0.18) # Construction yellow
	mat.roughness = 0.7
	body.material_override = mat
	truck.add_child(body)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.8, 2.4, 7.0)
	col.shape = shape
	truck.add_child(col)

	# Crane arm
	var crane := MeshInstance3D.new()
	crane.name = "CraneArm"
	var arm_box := BoxMesh.new()
	arm_box.size = Vector3(0.6, 0.6, 4.5)
	crane.mesh = arm_box
	var mat_arm := StandardMaterial3D.new()
	mat_arm.albedo_color = Color(0.25, 0.25, 0.26)
	mat_arm.metallic = 0.6
	crane.material_override = mat_arm
	crane.position = Vector3(0, 1.6, -1.0)
	truck.add_child(crane)

	# Cabin
	var cab := MeshInstance3D.new()
	var cab_box := BoxMesh.new()
	cab_box.size = Vector3(3.4, 1.8, 2.2)
	cab.mesh = cab_box
	var mat_cab := StandardMaterial3D.new()
	mat_cab.albedo_color = Color(0.22, 0.22, 0.24)
	cab.material_override = mat_cab
	cab.position = Vector3(0, 1.2, 2.8)
	truck.add_child(cab)

	# NavAgent
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	agent.path_desired_distance = 1.5
	agent.target_desired_distance = 2.5
	truck.add_child(agent)

	# Interact area
	var area := Area3D.new()
	area.name = "InteractArea"
	var a_col := CollisionShape3D.new()
	var a_shape := BoxShape3D.new()
	a_shape.size = Vector3(6, 3, 8)
	a_col.shape = a_shape
	area.add_child(a_col)
	area.set_meta("interact_text", "[F] DRIVE CONSTRUCTION TRUCK")
	truck.add_child(area)

	return truck

## สร้าง construction site marker (จุดให้รถวิ่งไปสร้าง) — ไม่ใช่สิ่งก่อสร้างจริง
static func create_build_site(pos: Vector3, build_type: String = "outpost") -> Node3D:
	var marker := Node3D.new()
	marker.name = "BuildSite_%s" % build_type
	marker.position = pos
	marker.add_to_group("construction_site")
	marker.set_meta("build_type", build_type)
	marker.set_meta("built", false)
	# Visual hologram
	var holo := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.5
	cyl.bottom_radius = 3.5
	cyl.height = 0.2
	holo.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 1.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.7, 1.0)
	mat.emission_energy_multiplier = 1.2
	holo.material_override = mat
	holo.position = Vector3(0, 0.1, 0)
	marker.add_child(holo)

	var lbl := Label3D.new()
	lbl.text = "BUILD SITE\n[%s] %d ORE" % [build_type.to_upper(), 120]
	lbl.font_size = 16
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0, 2.2, 0)
	marker.add_child(lbl)

	return marker
