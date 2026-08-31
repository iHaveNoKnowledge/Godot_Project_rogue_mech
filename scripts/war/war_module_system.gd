extends RefCounted
class_name WarModuleSystem

## Module — ติด/ถอดได้ ตกให้ชิงได้ (Phase1: 3 ตัว)

const STARTER_MODULES: Array[String] = [
	"mod_reactor_fission",
	"mod_targeting_fcs",
	"mod_recoil_gyro_l",
]

static func get_module_entry(mod_id: String) -> Dictionary:
	return GlobalData.get_frame_property_entry(mod_id)


static func attach_to_slot(slot: String, mod_id: String) -> bool:
	var entry = get_module_entry(mod_id)
	if entry.is_empty():
		return false
	var inst = entry.duplicate(true)
	inst["slot"] = slot
	inst["uid"] = "mod_%d_%d" % [Time.get_ticks_usec(), randi() % 99999]
	GlobalData.weapons.attachments.append(inst)
	GlobalData.save_run()
	return true


static func detach(mod_uid: String) -> bool:
	for i in range(GlobalData.weapons.attachments.size()):
		var att = GlobalData.weapons.attachments[i]
		if str(att.get("uid", "")) == mod_uid:
			GlobalData.weapons.attachments.remove_at(i)
			GlobalData.save_run()
			return true
	return false


static func spawn_dropped_module(pos: Vector3, mod_id: String, parent: Node) -> Node3D:
	var entry = get_module_entry(mod_id)
	if entry.is_empty():
		return null
	var pickup = Area3D.new()
	pickup.name = "DroppedModule_%s" % mod_id
	pickup.position = pos
	pickup.add_to_group("dropped_module")
	pickup.set_meta("module_id", mod_id)
	var mi = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.8, 0.8, 0.8)
	mi.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = entry.get("color", Color(0.2, 0.7, 1.0))
	mat.emission_enabled = true
	mat.emission = entry.get("color", Color(0.2, 0.7, 1.0))
	mat.emission_energy_multiplier = 1.5
	mi.material_override = mat
	pickup.add_child(mi)
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(1.5, 1.5, 1.5)
	col.shape = shape
	pickup.add_child(col)
	var lbl = Label3D.new()
	lbl.text = "%s\n[F] PICKUP" % str(entry.get("name", mod_id)).to_upper()
	lbl.font_size = 18
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0, 1.2, 0)
	pickup.add_child(lbl)
	pickup.body_entered.connect(func(body):
		if body.is_in_group("mecha") or body.is_in_group("pilot"):
			var slot = entry.get("slot", "body")
			attach_to_slot(slot, mod_id)
			pickup.queue_free()
	)
	parent.add_child(pickup)
	return pickup
