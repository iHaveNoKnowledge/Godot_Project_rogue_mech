extends Node3D
class_name CarrierDock

## =============================================================================
## MECHA TRANSPORTER TRUCK (รถขนส่งหุ่นยนต์) — Heavy Ground Flatbed Carrier
## =============================================================================
## รถขนส่งภาคพื้นดินขนาดใหญ่ (Heavy Mecha Transporter Truck) มีห้องคนขับ (Cab)
## ด้านหน้า, ล้อรถบรรทุกขนาดใหญ่หลายเพลา, และกระบะท้าย (Flatbed Bed) 2 ช่อง
## สำหรับบรรทุกหุ่น Valkren 2 ตัว
##
## ใน Godot 4.6 เมื่อหุ่น CharacterBody3D ยืนบนรถที่กำลังแล่น จะเกิด Physics Jitter
## ระบบนี้แก้ปัญหา Jitter ได้ 100% โดย:
##   1. FREEZE Physics ของตัวหุ่น (velocity = 0, set_physics_process(false))
##   2. ปิด Collision Layer & Mask (0, 0) เพื่อไม่ให้ชนซ้อนทับกับกระบะรถ
##   3. REPARENT ให้ตัวหุ่นเป็น Child ของแท่นกระบะรถขนส่ง (ขยับตามรถแบบ Rigid ไม่มีสั่น)
##   4. UNDOCK ปล่อยหุ่นกลับเป็น Child ของโลก ณ ตำแหน่งท้ายกระบะ คืนค่าฟิสิกส์และ
##      Collision ครบถ้วน พร้อมให้คนขับบังคับเลี้ยวขับลงจากรถขนส่งได้ทันที
## =============================================================================

signal mech_docked(mech: Node3D, bay_idx: int)
signal mech_undocked(mech: Node3D, bay_idx: int)

var _docked: Array = [null, null]
var _saved_physics_state: Dictionary = {}
var _inside_mechas: Array = [[], []]
var carrier_ref: Node3D = null


func _ready() -> void:
	set_process(true)


func create_carrier(pos: Vector3) -> Node3D:
	var truck := CharacterBody3D.new()
	truck.name = "MechaTransporterTruck"
	truck.position = pos
	truck.add_to_group("vehicle")
	truck.add_to_group("carrier")
	truck.add_to_group("transport_truck")
	truck.collision_layer = 1
	truck.collision_mask = 2
	carrier_ref = truck

	# 1. Main Truck Chassis & Flatbed Bed (โครงรถบรรทุกและกระบะบรรทุกหุ่น)
	var bed_mesh := MeshInstance3D.new()
	var bed_box := BoxMesh.new()
	bed_box.size = Vector3(7.2, 1.2, 14.0)
	bed_mesh.mesh = bed_box
	var mat_truck := StandardMaterial3D.new()
	mat_truck.albedo_color = Color(0.24, 0.28, 0.25) # Military Green/Grey
	mat_truck.metallic = 0.6
	mat_truck.roughness = 0.55
	bed_mesh.material_override = mat_truck
	bed_mesh.position = Vector3(0, 0.8, -0.5)
	truck.add_child(bed_mesh)

	var truck_col := CollisionShape3D.new()
	var truck_shape := BoxShape3D.new()
	truck_shape.size = Vector3(7.2, 1.2, 14.0)
	truck_col.shape = truck_shape
	truck_col.position = Vector3(0, 0.8, -0.5)
	truck.add_child(truck_col)

	# 2. Driver Cabin (ห้องคนขับหน้ารถบรรทุก)
	var cab_mesh := MeshInstance3D.new()
	var cab_box := BoxMesh.new()
	cab_box.size = Vector3(6.8, 3.2, 3.8)
	cab_mesh.mesh = cab_box
	var mat_cab := StandardMaterial3D.new()
	mat_cab.albedo_color = Color(0.20, 0.24, 0.22)
	mat_cab.roughness = 0.6
	cab_mesh.material_override = mat_cab
	cab_mesh.position = Vector3(0, 2.6, 4.6)
	truck.add_child(cab_mesh)

	# Cabin Windshield (กระจกหน้ารถ)
	var glass_mesh := MeshInstance3D.new()
	var g_box := BoxMesh.new()
	g_box.size = Vector3(5.8, 1.2, 0.3)
	glass_mesh.mesh = g_box
	var mat_glass := StandardMaterial3D.new()
	mat_glass.albedo_color = Color(0.1, 0.3, 0.4, 0.85)
	mat_glass.metallic = 0.8
	mat_glass.roughness = 0.1
	glass_mesh.material_override = mat_glass
	glass_mesh.position = Vector3(0, 3.0, 6.45)
	truck.add_child(glass_mesh)

	# 3. Heavy Multi-Axle Truck Wheels (ล้อรถบรรทุกหนัก 8 ล้อ)
	var mat_wheel := StandardMaterial3D.new()
	mat_wheel.albedo_color = Color(0.08, 0.08, 0.09)
	mat_wheel.roughness = 0.85

	var wheel_z_positions = [4.2, 1.5, -2.2, -5.5]
	for z_pos in wheel_z_positions:
		for side in [-3.7, 3.7]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 1.05
			cyl.bottom_radius = 1.05
			cyl.height = 0.8
			wheel.mesh = cyl
			wheel.material_override = mat_wheel
			wheel.rotation.z = deg_to_rad(90.0)
			wheel.position = Vector3(side, 0.9, z_pos)
			truck.add_child(wheel)

	# 4. Rear Loading Ramp (ทางลาดท้ายกระบะสำหรับขับขึ้น-ลง)
	var ramp_mesh := MeshInstance3D.new()
	var ramp_box := BoxMesh.new()
	ramp_box.size = Vector3(6.8, 0.3, 2.5)
	ramp_mesh.mesh = ramp_box
	var mat_ramp := StandardMaterial3D.new()
	mat_ramp.albedo_color = Color(0.18, 0.19, 0.20)
	mat_ramp.roughness = 0.8
	ramp_mesh.material_override = mat_ramp
	ramp_mesh.position = Vector3(0, 0.3, -7.8)
	ramp_mesh.rotation.x = deg_to_rad(-18.0)
	truck.add_child(ramp_mesh)

	# Attach self as logic component to truck
	truck.add_child(self)

	# 5. 2 Dedicated Flatbed Dock Bays (กระบะซ้าย Bay 0, กระบะขวา Bay 1)
	var bay_x_offsets = [-1.75, 1.75]
	for i in range(2):
		var dock_bay := Area3D.new()
		dock_bay.name = "Dock%d" % i
		dock_bay.position = Vector3(bay_x_offsets[i], 1.45, -1.8)
		dock_bay.collision_layer = 0
		dock_bay.collision_mask = 1 # detects mechas (layer 1)
		dock_bay.monitoring = true

		var dcol := CollisionShape3D.new()
		var dshape := BoxShape3D.new()
		dshape.size = Vector3(3.0, 2.6, 5.0)
		dcol.shape = dshape
		dock_bay.add_child(dcol)

		# Dock Pad Visual (กระบะเหล็กรองรับหุ่นพร้อมขอบเตือนสีเหลือง)
		var pad_mesh := MeshInstance3D.new()
		var p_box := BoxMesh.new()
		p_box.size = Vector3(2.8, 0.1, 4.6)
		pad_mesh.mesh = p_box
		var p_mat := StandardMaterial3D.new()
		p_mat.albedo_color = Color(0.16, 0.17, 0.19)
		p_mat.roughness = 0.75
		pad_mesh.material_override = p_mat
		pad_mesh.position = Vector3(0, 0.05, 0)
		dock_bay.add_child(pad_mesh)

		var lbl := Label3D.new()
		lbl.text = "TRUCK BED %d\n[F] DOCK (จอดบนกระบะ)" % (i + 1)
		lbl.font_size = 18
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.position = Vector3(0, 2.0, 0)
		dock_bay.add_child(lbl)

		dock_bay.body_entered.connect(_on_dock_body_entered.bind(i))
		dock_bay.body_exited.connect(_on_dock_body_exited.bind(i))
		truck.add_child(dock_bay)

	# 6. Weapon Rack / Field Ammo Crate on Truck Bed
	var rack := Node3D.new()
	rack.name = "WeaponRack"
	rack.position = Vector3(0, 1.5, 2.2)
	truck.add_child(rack)
	for w in 6:
		var slot := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.5, 0.35, 1.2)
		slot.mesh = b
		slot.position = Vector3(-1.5 + (w % 3) * 1.5, 0, (w / 3) * 1.0)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.55, 0.58, 0.60)
		slot.material_override = m
		rack.add_child(slot)

	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	agent.path_desired_distance = 1.5
	agent.target_desired_distance = 2.0
	truck.add_child(agent)

	return truck


func _on_dock_body_entered(body: Node, bay_idx: int) -> void:
	if not (body.is_in_group("mecha") or body.is_in_group("pilot")):
		return
	if not _inside_mechas[bay_idx].has(body):
		_inside_mechas[bay_idx].append(body)
	if _docked[bay_idx] == null:
		EventBus.interaction_prompt_updated.emit("[F] DOCK (TRUCK BED %d)" % (bay_idx + 1), true)


func _on_dock_body_exited(body: Node, bay_idx: int) -> void:
	_inside_mechas[bay_idx].erase(body)
	if _inside_mechas[0].is_empty() and _inside_mechas[1].is_empty():
		EventBus.interaction_prompt_updated.emit("", false)


func _process(_delta: float) -> void:
	# Poll [F] / interact key when inside a dock area on the truck bed
	if Input.is_action_just_pressed("interact"):
		for bay_idx in range(2):
			if _docked[bay_idx] == null and not _inside_mechas[bay_idx].is_empty():
				var candidate = _inside_mechas[bay_idx][0]
				if is_instance_valid(candidate) and candidate is Node3D:
					var mech_to_dock: Node3D = candidate
					# If pilot is driving, resolve vehicle
					if candidate.has_method("get") and candidate.get("current_vehicle") != null:
						mech_to_dock = candidate.get("current_vehicle")
					var truck = carrier_ref if carrier_ref else get_parent()
					dock_mech(mech_to_dock, truck, bay_idx)
					break


## =============================================================================
## DOCK MECH (Anti-Physics Jitter: Freeze + Collision Isolation + Reparent)
## =============================================================================
func dock_mech(mech: Node3D, truck: Node3D, idx: int) -> bool:
	if mech == null or not is_instance_valid(mech):
		return false
	if idx < 0 or idx >= 2 or _docked[idx] != null:
		return false
	if truck == null or not is_instance_valid(truck):
		return false

	var dock_node := truck.get_node_or_null("Dock%d" % idx)
	if dock_node == null:
		return false

	# 1. Save original physics and hierarchy state
	var saved_state := {
		"collision_layer": mech.get("collision_layer") if "collision_layer" in mech else 1,
		"collision_mask": mech.get("collision_mask") if "collision_mask" in mech else 1,
		"parent": mech.get_parent(),
		"was_rigidbody": (mech is RigidBody3D),
		"global_transform_before": mech.global_transform
	}
	_saved_physics_state[idx] = saved_state

	# 2. FREEZE PHYSICS (CharacterBody3D or RigidBody3D)
	if mech is CharacterBody3D:
		mech.velocity = Vector3.ZERO
		mech.set_physics_process(false)
	elif mech is RigidBody3D:
		mech.linear_velocity = Vector3.ZERO
		mech.angular_velocity = Vector3.ZERO
		mech.freeze = true
		mech.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC

	if mech.has_method("set_frozen"):
		mech.set_frozen(true)

	# 3. DISABLE COLLISION: zero layer & mask so Valkren never collides with truck bed
	if "collision_layer" in mech:
		mech.collision_layer = 0
	if "collision_mask" in mech:
		mech.collision_mask = 0

	# 4. REPARENT: Make Valkren a child of Truck Bed Dock Node
	mech.reparent(dock_node)
	mech.position = Vector3.ZERO
	mech.rotation = Vector3.ZERO

	# 5. Metadata & Registry
	mech.set_meta("is_docked", true)
	mech.set_meta("docked_carrier", truck.get_instance_id())
	mech.set_meta("docked_bay", idx)
	_docked[idx] = mech

	if GlobalData.hangar:
		GlobalData.hangar.set_meta("docked_%d" % idx, mech.name)

	EventBus.interaction_prompt_updated.emit("", false)
	mech_docked.emit(mech, idx)
	return true


## =============================================================================
## UNDOCK MECH (In-Place Truck Bed Launch: Reparent World + Restore Collision & Physics)
## =============================================================================
func undock_mech(idx: int, truck: Node3D = null) -> Node3D:
	if idx < 0 or idx >= 2:
		return null
	var mech: Node3D = _docked[idx]
	if mech == null or not is_instance_valid(mech):
		return null

	var host_truck: Node3D = truck if truck else carrier_ref
	if host_truck == null and mech.get_parent():
		host_truck = mech.get_parent().get_parent() as Node3D

	var world_scene: Node = host_truck.get_parent() if (host_truck and host_truck.get_parent()) else mech.get_tree().current_scene
	if world_scene == null:
		return null

	# 1. Capture current global transform on truck bed launch pad
	var launch_transform := mech.global_transform

	# 2. REPARENT: return Valkren back to world scene root
	mech.reparent(world_scene)
	mech.global_transform = launch_transform

	# 3. RESTORE COLLISION LAYER & MASK
	var saved_state: Dictionary = _saved_physics_state.get(idx, {})
	var orig_layer: int = saved_state.get("collision_layer", 1)
	var orig_mask: int = saved_state.get("collision_mask", 1)
	if "collision_layer" in mech:
		mech.collision_layer = orig_layer
	if "collision_mask" in mech:
		mech.collision_mask = orig_mask

	# 4. UNFREEZE PHYSICS
	if mech is CharacterBody3D:
		mech.velocity = Vector3.ZERO
		mech.set_physics_process(true)
	elif mech is RigidBody3D:
		mech.freeze = false
		mech.linear_velocity = Vector3.ZERO
		mech.angular_velocity = Vector3.ZERO

	if mech.has_method("set_frozen"):
		mech.set_frozen(false)

	# 5. Clear Dock State
	mech.remove_meta("is_docked")
	mech.remove_meta("docked_carrier")
	mech.remove_meta("docked_bay")
	_docked[idx] = null
	_saved_physics_state.erase(idx)

	if GlobalData.hangar and GlobalData.hangar.has_meta("docked_%d" % idx):
		GlobalData.hangar.remove_meta("docked_%d" % idx)

	mech_undocked.emit(mech, idx)
	return mech


func is_bay_occupied(idx: int) -> bool:
	if idx < 0 or idx >= 2:
		return false
	return _docked[idx] != null and is_instance_valid(_docked[idx])


func get_docked_mech(idx: int) -> Node3D:
	if idx < 0 or idx >= 2:
		return null
	return _docked[idx]


func get_docked_count() -> int:
	var count := 0
	for m in _docked:
		if m != null and is_instance_valid(m):
			count += 1
	return count
