extends Node3D

var slot_meshes: Dictionary = {}


func _ready() -> void:
	EventBus.part_destroyed.connect(_on_part_destroyed)


func initialize_slot(slot_name: String, part: ArmorPart) -> void:
	var armor_mesh = get_node_or_null("%sArmor" % slot_name.capitalize())
	var frame_mesh = get_node_or_null("%sFrame" % slot_name.capitalize())
	if armor_mesh == null or frame_mesh == null:
		return
	slot_meshes[slot_name] = {"armor": armor_mesh, "frame": frame_mesh}
	if part.mesh_scene:
		var instance = part.mesh_scene.instantiate()
		armor_mesh.add_child(instance)
	if part.inner_frame_scene:
		var instance = part.inner_frame_scene.instantiate()
		frame_mesh.add_child(instance)
	frame_mesh.visible = false
	# กู้คืนสถานะจาก GlobalData
	var armor_dmg = GlobalData.part_damage.get(slot_name + "_armor", 0.0)
	if armor_dmg >= part.break_threshold:
		_show_inner_frame(slot_name)
	var frame_dmg = GlobalData.part_damage.get(slot_name + "_frame", 0.0)
	if frame_dmg >= 1.0:
		_destroy_frame(slot_name)


func _on_part_destroyed(slot_name: String) -> void:
	_show_inner_frame(slot_name)
	_spawn_break_vfx(slot_name)


func _show_inner_frame(slot_name: String) -> void:
	var entry = slot_meshes.get(slot_name)
	if entry == null:
		return
	entry["armor"].visible = false
	entry["frame"].visible = true


func _destroy_frame(slot_name: String) -> void:
	var entry = slot_meshes.get(slot_name)
	if entry == null:
		return
	entry["frame"].visible = false
	_spawn_destroy_vfx(slot_name)


func _spawn_break_vfx(slot_name: String) -> void:
	var entry = slot_meshes.get(slot_name)
	if entry == null:
		return
	var vfx_scene = load("res://scenes/mecha/effects/vfx_armor_break.tscn")
	if vfx_scene:
		var vfx = vfx_scene.instantiate()
		entry["armor"].get_parent().add_child(vfx)
		vfx.global_position = entry["armor"].global_position


func _spawn_destroy_vfx(slot_name: String) -> void:
	var entry = slot_meshes.get(slot_name)
	if entry == null:
		return
	var vfx_scene = load("res://scenes/mecha/effects/vfx_armor_break.tscn")
	if vfx_scene:
		var vfx = vfx_scene.instantiate()
		entry["frame"].get_parent().add_child(vfx)
		vfx.global_position = entry["frame"].global_position
