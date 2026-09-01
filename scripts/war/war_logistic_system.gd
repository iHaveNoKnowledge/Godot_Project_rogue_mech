extends Node
class_name WarLogisticSystem

## Truck/Carrier AI — Automated Logistic Track via NavigationAgent3D
## AI ขับเอง ผู้เล่นกด F ยึดขับได้ถ้าว่าง (per PLAN.md)

func create_truck(pos: Vector3, depot_pos: Vector3) -> Node3D:
	var truck = CharacterBody3D.new()
	truck.name = "Truck"
	truck.position = pos
	truck.add_to_group("vehicle")
	truck.add_to_group("logistic_truck")
	truck.collision_layer = 1
	truck.collision_mask = 2
	# AI driver
	var ai := WarTruckAI.new()
	ai.name = "TruckAI"
	truck.add_child(ai)
	# Visual
	var body = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(3.5, 2.2, 6.0)
	body.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.48, 0.42)
	mat.roughness = 0.8
	body.material_override = mat
	truck.add_child(body)
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(3.5, 2.2, 6.0)
	col.shape = shape
	truck.add_child(col)
	# NavigationAgent for AI
	var agent = NavigationAgent3D.new()
	agent.name = "NavAgent"
	agent.path_desired_distance = 1.5
	agent.target_desired_distance = 2.0
	truck.add_child(agent)
	# Interaction to takeover
	var area = Area3D.new()
	area.name = "InteractArea"
	var a_col = CollisionShape3D.new()
	var a_shape = BoxShape3D.new()
	a_shape.size = Vector3(5, 3, 7)
	a_col.shape = a_shape
	area.add_child(a_col)
	area.set_meta("interact_text", "[F] DRIVE TRUCK")
	truck.add_child(area)
	truck.set_meta("depot_pos", depot_pos)
	truck.set_meta("is_ai_driven", true)
	return truck
