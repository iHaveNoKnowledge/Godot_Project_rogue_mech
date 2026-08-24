class_name ArmorDamageVisuals
extends RefCounted

## ---------------------------------------------------------------------------
## ARMOR DAMAGE VISUALS MANAGER
##
## Manages procedural damage shader overlays for mech body parts.
## ARMOR and FRAME get INDEPENDENT crack materials per slot:
##   - the armor plate cracks up as its own HP drops,
##   - the inner frame stays pristine until its armor breaks and the frame
##     itself starts taking hits.
## Each material generates a unique random noise seed so crack patterns never
## repeat, and damage_amount tracks real-time health loss of that layer.
##
## FIX 2026-08: Persistence bug — update_slot_layer_damage was a no-op when
## called BEFORE PartMeshManager created its meshes (HealthSystem._ready runs
## before controller's refresh_slots). Now it eagerly creates the material so
## damage set from save data survives into the next battle. Hit localization
## added: cracks radiate from the impact point and spread as dmg grows.
## ---------------------------------------------------------------------------

const DAMAGE_SHADER := preload("res://shaders/armor_crack.gdshader")

const LAYER_ARMOR := "armor"
const LAYER_FRAME := "frame"

var health_system: Node = null
var mecha_root: Node3D = null

# slot_name -> {
#   "armor": ShaderMaterial, "frame": ShaderMaterial,
#   "armor_meshes": Array[MeshInstance3D], "frame_meshes": Array[MeshInstance3D],
# }
var _slot_overlays: Dictionary = {}


func _init(hs: Node = null) -> void:
	if hs:
		attach_to_health_system(hs)


func attach_to_health_system(hs: Node) -> void:
	health_system = hs
	mecha_root = hs.get_parent() as Node3D

	if hs.has_signal("health_changed"):
		if not hs.health_changed.is_connected(_on_health_changed):
			hs.health_changed.connect(_on_health_changed)

	_setup_mesh_overlays()


func _setup_mesh_overlays() -> void:
	if mecha_root == null:
		return

	# 1. Connect to PartMeshManager if present. Armor containers bind to the
	# armor crack material, inner-frame containers to the frame one. Slots are
	# usually rebuilt LATER by PartMeshManager.initialize_slot(), which calls
	# register_slot_container() itself — this pass only catches containers
	# that already exist right now.
	var pmm = mecha_root.get_node_or_null("PartMeshManager")
	if pmm and "slot_meshes" in pmm:
		for slot in pmm.slot_meshes:
			var data: Dictionary = pmm.slot_meshes[slot]
			for key in ["armor", "armor_lower"]:
				var container: Node3D = data.get(key)
				if container:
					register_slot_container(slot, container, LAYER_ARMOR)
			for key in ["frame", "frame_lower"]:
				var container: Node3D = data.get(key)
				if container:
					register_slot_container(slot, container, LAYER_FRAME)
		# Also sync already-persisted damage/hit so early HealthSystem values
		# that were set before meshes existed are not lost.
		_sync_all_from_persist()
		return

	# 2. Fallback for mechs WITHOUT a PartMeshManager (primitive-built dummies):
	# bind each standard section subtree to the slot's armor material.
	var slot_node_map := {
		"head": ["Head"],
		"body": ["Body"],
		"arm_left": ["ArmLeft"],
		"arm_right": ["ArmRight"],
		"leg_left": ["LegLeft"],
		"leg_right": ["LegRight"],
	}

	for slot in slot_node_map:
		for path in slot_node_map[slot]:
			var node = mecha_root.get_node_or_null(path)
			if node:
				register_slot_container(slot, node, LAYER_ARMOR)
	_sync_all_from_persist()


func _get_or_create_layer_entry(slot: String) -> Dictionary:
	if not _slot_overlays.has(slot):
		_slot_overlays[slot] = {
			LAYER_ARMOR: null,
			LAYER_FRAME: null,
			"armor_meshes": [] as Array[MeshInstance3D],
			"frame_meshes": [] as Array[MeshInstance3D],
		}
	return _slot_overlays[slot]


func _get_or_create_slot_mat(slot: String, layer: String) -> ShaderMaterial:
	var entry: Dictionary = _get_or_create_layer_entry(slot)
	if entry.get(layer) != null:
		return entry[layer]

	var mat := ShaderMaterial.new()
	mat.shader = DAMAGE_SHADER
	# Unique random seed per slot AND layer so armor/frame crack patterns
	# never repeat or line up with each other.
	var random_seed := Vector3(
		randf_range(-100.0, 100.0),
		randf_range(-100.0, 100.0),
		randf_range(-100.0, 100.0)
	)
	mat.set_shader_parameter("noise_offset", random_seed)
	mat.set_shader_parameter("damage_amount", 0.0)
	mat.set_shader_parameter("hit_pos", Vector3.ZERO)
	mat.set_shader_parameter("hit_radius", 0.0)
	mat.set_shader_parameter("hit_spread", 3.2)
	entry[layer] = mat
	# Apply persisted damage/hit if any (covers HealthSystem._ready -> early set
	# before meshes existed, and save-restore across battles).
	_apply_persist_to_mat(slot, layer, mat)
	return mat


func _apply_persist_to_mat(slot: String, layer: String, mat: ShaderMaterial) -> void:
	# Restore damage from GlobalData if this is the player mech.
	if GlobalData and GlobalData.weapons:
		var dmg_key := slot if layer == LAYER_ARMOR else slot + "_frame"
		# GlobalData uses "slot" for armor, "slot_frame" for frame
		var dmg: float = float(GlobalData.weapons.part_damage.get(dmg_key, 0.0)) if layer == LAYER_ARMOR else float(GlobalData.weapons.part_damage.get(slot + "_frame", 0.0))
		if dmg > 0.001:
			# If HealthSystem parts already hold the HP, the HealthSystem loop
			# will also call update_slot_layer_damage; this just ensures the mat
			# isn't left at 0 when that call happened before the mat existed.
			var cur: float = float(mat.get_shader_parameter("damage_amount"))
			if cur < dmg:
				mat.set_shader_parameter("damage_amount", clampf(dmg, 0.0, 1.0))
		# Restore hit
		var hit_meta = GlobalData.weapons.part_hit_meta.get(slot) if GlobalData.weapons.part_hit_meta.has(slot) else null
		if hit_meta is Dictionary and str(hit_meta.get("layer", layer)) == layer:
			var pos = hit_meta.get("pos", Vector3.ZERO)
			if pos is Vector3:
				mat.set_shader_parameter("hit_pos", pos)
				mat.set_shader_parameter("hit_radius", float(hit_meta.get("radius", 0.65)))
				mat.set_shader_parameter("hit_spread", 3.2)


## Binds every MeshInstance3D under `container` to the slot's crack material
## for the given surface layer ("armor" plates or "frame" skeleton).
func register_slot_container(slot: String, container: Node, layer: String = LAYER_ARMOR) -> void:
	if container == null or not is_instance_valid(container):
		return
	layer = LAYER_FRAME if str(layer).to_lower() == LAYER_FRAME else LAYER_ARMOR

	var mat := _get_or_create_slot_mat(slot, layer)
	var entry: Dictionary = _get_or_create_layer_entry(slot)
	var mesh_list: Array = entry[layer + "_meshes"]

	var meshes: Array[MeshInstance3D] = []
	_gather_meshes_recursive(container, meshes)
	for mesh in meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = mat
			if not mesh_list.has(mesh):
				mesh_list.append(mesh)
	# Ensure persisted values are on the mat after bind (covers the case where
	# update_slot_layer_damage happened before the mat existed).
	_apply_persist_to_mat(slot, layer, mat)


func _gather_meshes_recursive(node: Node, out_meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		if not out_meshes.has(node):
			out_meshes.append(node)
	for child in node.get_children():
		_gather_meshes_recursive(child, out_meshes)


## Legacy single-layer setter — updates the slot's ARMOR plate damage.
func update_slot_damage(slot: String, damage_ratio: float) -> void:
	update_slot_layer_damage(slot, LAYER_ARMOR, damage_ratio)


## Sets the crack intensity of one surface layer (0.0 = pristine, 1.0 = wrecked).
## Now eagerly creates the material if it does not yet exist (fix for cross-battle
## persistence where HealthSystem set damage before PartMeshManager bound meshes).
func update_slot_layer_damage(slot: String, layer: String, damage_ratio: float) -> void:
	layer = LAYER_FRAME if str(layer).to_lower() == LAYER_FRAME else LAYER_ARMOR
	var mat := _get_or_create_slot_mat(slot, layer)
	mat.set_shader_parameter("damage_amount", clampf(damage_ratio, 0.0, 1.0))


func _on_health_changed(slot_name: String, layer: String, current_hp: float, max_hp: float) -> void:
	if max_hp <= 0.0:
		return
	var damage_ratio := 1.0 - clampf(current_hp / max_hp, 0.0, 1.0)
	# Route by surface layer: armor HP drives the plate's cracks, frame HP the
	# skeleton's — so the frame only scars up AFTER the armor has broken.
	update_slot_layer_damage(slot_name, layer, damage_ratio)


# --- Hit localization ------------------------------------------------------

## Records an impact origin for a slot/layer so cracks radiate from there.
## `local_pos` is in that MeshInstance's MODEL space (approx slot-local).
## `radius` ~0.4-0.9 for small arms, up to 1.8 for heavy/explosive hits.
func update_slot_hit(slot: String, layer: String, local_pos: Vector3, radius: float = 0.65) -> void:
	layer = LAYER_FRAME if str(layer).to_lower() == LAYER_FRAME else LAYER_ARMOR
	var mat := _get_or_create_slot_mat(slot, layer)
	mat.set_shader_parameter("hit_pos", local_pos)
	mat.set_shader_parameter("hit_radius", clampf(radius, 0.0, 6.0))
	# Persist for cross-battle restore (player only, per-slot last hit wins).
	if GlobalData and GlobalData.weapons and health_system and health_system.get("is_player") and bool(health_system.is_player):
		GlobalData.weapons.part_hit_meta[slot] = {"pos": local_pos, "radius": clampf(radius, 0.0, 6.0), "layer": layer}


## Convenience: world_pos → slot-local for the given slot, then update.
func update_slot_hit_from_world(slot: String, layer: String, world_pos: Vector3, radius: float = 0.65) -> void:
	if mecha_root == null:
		update_slot_hit(slot, layer, Vector3.ZERO, radius)
		return
	var section := _get_section_node(slot)
	var local := Vector3.ZERO
	if section != null and is_instance_valid(section):
		local = section.to_local(world_pos)
	else:
		local = mecha_root.to_local(world_pos)
	# Small random jitter so identical hits don't produce identical perfect circles
	local += Vector3(randf_range(-0.06, 0.06), randf_range(-0.06, 0.06), randf_range(-0.06, 0.06))
	update_slot_hit(slot, layer, local, radius)


func _get_section_node(slot_name: String) -> Node3D:
	if mecha_root == null:
		return null
	var node_name: String = GlobalData.SLOT_TO_NODE.get(slot_name, "")
	if node_name == "":
		return null
	return mecha_root.get_node_or_null(node_name)


func _sync_all_from_persist() -> void:
	if GlobalData == null or GlobalData.weapons == null:
		return
	# Synchronize all active slot overlay materials with current persistent state
	for base_slot in _slot_overlays.keys():
		var a_dmg: float = float(GlobalData.weapons.part_damage.get(base_slot, 0.0))
		var f_dmg: float = float(GlobalData.weapons.part_damage.get(base_slot + "_frame", 0.0))

		var a_mat: ShaderMaterial = _slot_overlays[base_slot].get(LAYER_ARMOR)
		if a_mat != null:
			a_mat.set_shader_parameter("damage_amount", clampf(a_dmg, 0.0, 1.0))
			if a_dmg <= 0.001:
				a_mat.set_shader_parameter("hit_radius", 0.0)

		var f_mat: ShaderMaterial = _slot_overlays[base_slot].get(LAYER_FRAME)
		if f_mat != null:
			f_mat.set_shader_parameter("damage_amount", clampf(f_dmg, 0.0, 1.0))
			if f_dmg <= 0.001:
				f_mat.set_shader_parameter("hit_radius", 0.0)

	# Also apply hit metas where mats already exist
	for slot in GlobalData.weapons.part_hit_meta.keys():
		if not _slot_overlays.has(slot):
			continue
		var meta = GlobalData.weapons.part_hit_meta[slot]
		if meta is Dictionary:
			var m_layer: String = str(meta.get("layer", LAYER_ARMOR))
			var mat2 = _slot_overlays[slot].get(m_layer)
			if mat2 != null:
				mat2.set_shader_parameter("hit_pos", meta.get("pos", Vector3.ZERO))
				mat2.set_shader_parameter("hit_radius", float(meta.get("radius", 0.65)))


func clear_slot_damage(slot: String) -> void:
	if _slot_overlays.has(slot):
		var a_mat: ShaderMaterial = _slot_overlays[slot].get(LAYER_ARMOR)
		if a_mat != null:
			a_mat.set_shader_parameter("damage_amount", 0.0)
			a_mat.set_shader_parameter("hit_radius", 0.0)
		var f_mat: ShaderMaterial = _slot_overlays[slot].get(LAYER_FRAME)
		if f_mat != null:
			f_mat.set_shader_parameter("damage_amount", 0.0)
			f_mat.set_shader_parameter("hit_radius", 0.0)


func clear_all_slot_damage() -> void:
	for slot in _slot_overlays.keys():
		clear_slot_damage(slot)


## Helper to apply damage overlays to custom models / dynamic meshes
func bind_custom_mesh(slot: String, mesh_node: MeshInstance3D, layer: String = LAYER_ARMOR) -> void:
	if mesh_node == null:
		return
	var mat := _get_or_create_slot_mat(slot, LAYER_FRAME if str(layer).to_lower() == LAYER_FRAME else LAYER_ARMOR)
	mesh_node.material_overlay = mat
	var entry: Dictionary = _get_or_create_layer_entry(slot)
	var mesh_list: Array = entry[(LAYER_FRAME if str(layer).to_lower() == LAYER_FRAME else LAYER_ARMOR) + "_meshes"]
	if not mesh_list.has(mesh_node):
		mesh_list.append(mesh_node)
