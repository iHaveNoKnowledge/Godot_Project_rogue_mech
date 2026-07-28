class_name EnemyTankHealth
extends MechaHealthBase

# เรียกใช้งานสัญญาณเพื่อหยุดยั้งความสามารถรถถัง
signal mobility_lost()
signal turret_disabled()

func _init_parts() -> void:
	parts = {
		"hull": {
			"armor_hp": 80.0, "max_armor": 80.0, "armor_class": 1.2,
			"frame_hp": 60.0, "max_frame": 60.0,
			"armor_broken": false, "destroyed": false, "mesh": null
		},
		"turret": {
			"armor_hp": 40.0, "max_armor": 40.0, "armor_class": 0.9,
			"frame_hp": 30.0, "max_frame": 30.0,
			"armor_broken": false, "destroyed": false, "mesh": null
		},
		"treads": {
			"armor_hp": 50.0, "max_armor": 50.0, "armor_class": 0.7,
			"frame_hp": 40.0, "max_frame": 40.0,
			"armor_broken": false, "destroyed": false, "mesh": null
		}
	}
	is_player = false


func _find_meshes() -> void:
	# ค้นหาโหนดโมเดล 3D ย่อยของตัวรถถัง
	var hull_node = get_node_or_null("../HullMesh")
	var turret_node = get_node_or_null("../TurretMesh")
	var treads_node = get_node_or_null("../TreadsMesh")
	
	if hull_node: parts["hull"]["mesh"] = hull_node
	if turret_node: parts["turret"]["mesh"] = turret_node
	if treads_node: parts["treads"]["mesh"] = treads_node


# ตรวจจับพาร์ทที่ถูกทำลายและส่งผลกระทบต่อลักษณะทางกายภาพของรถถัง
func _on_frame_destroyed(slot_name: String) -> void:
	super._on_frame_destroyed(slot_name)
	
	match slot_name:
		"treads":
			# สายพานขาด: รถถังหยุดเคลื่อนไหวถาวร (Mobility Kill)
			mobility_lost.emit()
			if get_parent().has_method("disable_movement"):
				get_parent().disable_movement()
		"turret":
			# ป้อมปืนพัง: หยุดทำงานการยิงปืนหลักสวนผู้เล่น
			turret_disabled.emit()
			if get_parent().has_method("disable_weapons"):
				get_parent().disable_weapons()
		"hull":
			# ตัวถังหลักพัง: ระเบิดรถถังพังทลายทันที
			_on_mecha_destroyed()
