extends Area3D
class_name WarDataEvent

## Data Event — เกิดกลางแมพ ให้เก็บแล้วแบกกลับฐานวิจัย (CTF)
## Roll: Part/Frame/Module/Weapon (Phase1: 4 แบบก่อน)

@export var data_type: String = "part" # part / frame / module / weapon

var _collected: bool = false
var _carrier: Node = null


func _ready() -> void:
	add_to_group("data_event")
	collision_layer = 0
	collision_mask = 0
	body_entered.connect(_on_body_entered)
	_setup_visual()


func _setup_visual() -> void:
	var mi = MeshInstance3D.new()
	var prism = PrismMesh.new()
	prism.size = Vector3(1.5, 1.2, 1.5)
	mi.mesh = prism
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.85, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.7, 1.0)
	mat.emission_energy_multiplier = 2.5
	mi.material_override = mat
	add_child(mi)
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(3, 2, 3)
	col.shape = shape
	add_child(col)
	var lbl = Label3D.new()
	lbl.text = "DATA: %s\n[F] COLLECT" % data_type.to_upper()
	lbl.font_size = 22
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.outline_size = 6
	lbl.position = Vector3(0, 2.0, 0)
	add_child(lbl)
	# Floating anim
	var tw = create_tween()
	tw.set_loops()
	tw.tween_property(mi, "position:y", 0.3, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(mi, "position:y", 0.0, 0.8).set_trans(Tween.TRANS_SINE)


func _on_body_entered(body: Node) -> void:
	if _collected:
		return
	if body.is_in_group("mecha") or body.is_in_group("pilot"):
		if Input.is_action_pressed("interact") or true:
			collect(body)


func collect(carrier: Node) -> void:
	if _collected:
		return
	_collected = true
	_carrier = carrier
	carrier.set_meta("carried_data", data_type)
	carrier.set_meta("carried_data_speed_penalty", 0.2)
	visible = false
	# Show carry indicator
	if carrier is Node3D:
		var badge = Label3D.new()
		badge.name = "DataCarryBadge"
		badge.text = "CARRYING DATA"
		badge.font_size = 20
		badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		badge.no_depth_test = true
		badge.modulate = Color(0.2, 0.85, 1.0)
		badge.position = Vector3(0, 3.5, 0)
		carrier.add_child(badge)
	# Auto-research when reaching friendly base
	queue_free()


func deliver_to_base(base: Node, carrier: Node) -> void:
	var dtype = str(carrier.get_meta("carried_data", ""))
	if dtype == "":
		return
	# Roll research — grant part/module
	_grant_reward(dtype, carrier, base)
	carrier.remove_meta("carried_data")
	carrier.remove_meta("carried_data_speed_penalty")
	var badge = carrier.get_node_or_null("DataCarryBadge")
	if badge:
		badge.queue_free()


func _grant_reward(dtype: String, carrier: Node, base: Node) -> void:
	var rolled = WarValkyrionSystem.roll_data_reward() if dtype == "part" else dtype
	match rolled:
		"part":
			var entry = GlobalData.armor_catalog.get("body", [])[0] if not GlobalData.armor_catalog.is_empty() else {}
			if entry is Dictionary and not entry.is_empty():
				GlobalData.weapons.armor_inventory.append(entry.duplicate(true))
		"frame":
			var fentry = GlobalData.frame_catalog.get("body", [])[0] if not GlobalData.frame_catalog.is_empty() else {}
			if fentry is Dictionary and not fentry.is_empty():
				GlobalData.weapons.armor_inventory.append(fentry.duplicate(true))
		"module":
			var mod = GlobalData.frame_property_catalog[randi() % GlobalData.frame_property_catalog.size()] if not GlobalData.frame_property_catalog.is_empty() else {}
			if mod is Dictionary:
				GlobalData.weapons.attachments.append(mod.duplicate(true))
		"weapon", "weapon_data":
			var wpath = GlobalData.DEFAULT_LEFT_WEAPON_PATH
			if ResourceLoader.exists(wpath):
				GlobalData.weapons.weapon_inventory.append({"path": wpath, "uid": "war_%d" % randi()})
		"full_blueprint":
			WarValkyrionSystem.grant_blueprint(carrier)
		"whole_mech":
			var parent = base.get_parent() if base else carrier.get_parent()
			if parent:
				WarValkyrionSystem.grant_whole_mech(parent, carrier.global_position + Vector3(5, 0, 0))
	GlobalData.save_run()
	if base:
		base.set_meta("last_research", rolled)
