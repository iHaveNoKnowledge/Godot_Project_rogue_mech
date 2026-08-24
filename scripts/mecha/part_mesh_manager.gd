extends Node3D

var slot_meshes: Dictionary = {}
# When true, slots without an inner frame render a faint translucent skeleton
# instead of hiding — used by the hangar's from-zero REGISTER assembly so the
# player can see where each missing frame goes. Driven by the garage preview.
var ghost_mode: bool = false
# Cached ghost material: ghost frames rebuild constantly during an assembly.
var _ghost_mat: StandardMaterial3D = null


func set_ghost_mode(enabled: bool) -> void:
	ghost_mode = enabled


func _ready() -> void:
	var mecha = get_parent()
	if mecha:
		var health = mecha.get_node_or_null("HealthSystem")
		if health:
			if health.has_signal("part_destroyed"):
				health.part_destroyed.connect(_on_part_destroyed)
			if health.has_signal("armor_broken"):
				health.armor_broken.connect(_on_armor_broken)
	_hide_all_legacy_models()


func _on_armor_broken(slot_name: String) -> void:
	_show_inner_frame(slot_name)


# Hides legacy glTF model (Zenisrev) and default primitive meshes in mecha_base.tscn
func _hide_all_legacy_models() -> void:
	var mecha = get_parent()
	if not mecha:
		return
	var zenisrev = mecha.get_node_or_null("Zenisrev")
	if zenisrev:
		zenisrev.visible = false

	for slot in GlobalData.MECHA_SLOTS:
		var p_node = _get_slot_parent_node(slot)
		if p_node:
			_hide_legacy_slot_meshes(p_node)
		var l_node = _get_slot_lower_parent_node(slot)
		if l_node:
			_hide_legacy_slot_meshes(l_node)


# Hides BOTH frame and armor for a slot when NO inner frame is equipped on that slot.
func hide_slot_completely(slot_name: String) -> void:
	var entry = slot_meshes.get(slot_name)
	if entry == null:
		return
	if entry["armor"]: entry["armor"].visible = false
	if entry.get("armor_lower") and entry["armor_lower"]: entry["armor_lower"].visible = false
	if entry["frame"]: entry["frame"].visible = false
	if entry.get("frame_lower") and entry["frame_lower"]: entry["frame_lower"].visible = false


func initialize_slot(slot_name: String, part: ArmorPart, apply_player_damage: bool = true) -> void:
	var parent_node = _get_slot_parent_node(slot_name)
	if parent_node == null:
		return

	var lower_parent_node = _get_slot_lower_parent_node(slot_name)

	# Hide legacy placeholder primitives in mecha_base.tscn
	_hide_legacy_slot_meshes(parent_node)
	if lower_parent_node:
		_hide_legacy_slot_meshes(lower_parent_node)

	# 1. Setup Frame & Armor containers for Upper Joint (Shoulder / Hip)
	var frame_mesh = parent_node.get_node_or_null("FrameMesh")
	if frame_mesh == null:
		frame_mesh = Node3D.new()
		frame_mesh.name = "FrameMesh"
		parent_node.add_child(frame_mesh)

	var armor_mesh = parent_node.get_node_or_null("ArmorMesh")
	if armor_mesh == null:
		armor_mesh = Node3D.new()
		armor_mesh.name = "ArmorMesh"
		parent_node.add_child(armor_mesh)

	# 2. Setup Frame & Armor containers for Lower Joint (Elbow / Knee)
	var frame_mesh_lower: Node3D = null
	var armor_mesh_lower: Node3D = null
	if lower_parent_node:
		frame_mesh_lower = lower_parent_node.get_node_or_null("FrameMesh")
		if frame_mesh_lower == null:
			frame_mesh_lower = Node3D.new()
			frame_mesh_lower.name = "FrameMesh"
			lower_parent_node.add_child(frame_mesh_lower)

		armor_mesh_lower = lower_parent_node.get_node_or_null("ArmorMesh")
		if armor_mesh_lower == null:
			armor_mesh_lower = Node3D.new()
			armor_mesh_lower.name = "ArmorMesh"
			lower_parent_node.add_child(armor_mesh_lower)

	slot_meshes[slot_name] = {
		"armor": armor_mesh,
		"frame": frame_mesh,
		"armor_lower": armor_mesh_lower,
		"frame_lower": frame_mesh_lower
	}

	# 3. Build Inner Frame (Upper + Lower articulated segments)
	_clear_children(frame_mesh)
	if frame_mesh_lower: _clear_children(frame_mesh_lower)

	if part and (part.inner_frame_scene != null or part.inner_frame_scene_lower != null):
		_attach_custom_mesh_scene(frame_mesh, frame_mesh_lower, part.inner_frame_scene, part.inner_frame_scene_lower)
	else:
		_build_procedural_inner_frame(slot_name, frame_mesh, frame_mesh_lower)
	frame_mesh.visible = true
	if frame_mesh_lower: frame_mesh_lower.visible = true

	# 4. Build Outer Armor Plate (Upper + Lower articulated armor sleeves)
	_clear_children(armor_mesh)
	if armor_mesh_lower: _clear_children(armor_mesh_lower)

	if part != null:
		if part.mesh_scene != null or part.mesh_scene_lower != null:
			_attach_custom_mesh_scene(armor_mesh, armor_mesh_lower, part.mesh_scene, part.mesh_scene_lower)
		else:
			_build_procedural_outer_armor(slot_name, armor_mesh, armor_mesh_lower, part)

		# Player-only: reflect the current combat damage cache in the visuals.
		# Enemies (refresh_from_loadout) skip this — their damage lives in their
		# own health system and is driven by the part_destroyed signal instead.
		var armor_dmg: float = 0.0
		var frame_dmg: float = 0.0
		if apply_player_damage:
			armor_dmg = GlobalData.weapons.part_damage.get(slot_name, 0.0)
			frame_dmg = GlobalData.weapons.part_damage.get(slot_name + "_frame", 0.0)
		if frame_dmg >= 1.0:
			hide_slot_completely(slot_name)
		elif armor_dmg >= 1.0:
			_show_inner_frame(slot_name)
		else:
			armor_mesh.visible = true
			if armor_mesh_lower: armor_mesh_lower.visible = true
	else:
		armor_mesh.visible = false
		if armor_mesh_lower: armor_mesh_lower.visible = false

	# Register with ArmorDamageVisuals if health system exists on mecha.
	# Runs for EVERY slot (armored or bare frame): armor plates bind to the
	# armor crack material, the inner skeleton to its own frame material —
	# so the frame stays pristine until its armor plate breaks.
	var mecha = get_parent()
	if mecha:
		var hs = mecha.get_node_or_null("HealthSystem")
		if hs and hs.get("damage_visuals"):
			var dmg_vis = hs.damage_visuals
			if dmg_vis != null and dmg_vis.has_method("register_slot_container"):
				dmg_vis.register_slot_container(slot_name, armor_mesh, "armor")
				if armor_mesh_lower:
					dmg_vis.register_slot_container(slot_name, armor_mesh_lower, "armor")
				if frame_mesh:
					dmg_vis.register_slot_container(slot_name, frame_mesh, "frame")
				if frame_mesh_lower:
					dmg_vis.register_slot_container(slot_name, frame_mesh_lower, "frame")
				# Cross-battle persistence: ensure material already holds the saved damage/hit
				# (HealthSystem set damage before meshes existed — see ArmorDamageVisuals fix,
				# but also explicitly sync here so PartMeshManager is the source of truth).
				if apply_player_damage and dmg_vis.has_method("update_slot_layer_damage"):
					var a_dmg := float(GlobalData.weapons.part_damage.get(slot_name, 0.0))
					var f_dmg := float(GlobalData.weapons.part_damage.get(slot_name + "_frame", 0.0))
					dmg_vis.update_slot_layer_damage(slot_name, "armor", clampf(a_dmg, 0.0, 1.0))
					dmg_vis.update_slot_layer_damage(slot_name, "frame", clampf(f_dmg, 0.0, 1.0))
					# Restore last impact origin so the crack pattern still radiates from the hit
					if GlobalData.weapons.part_hit_meta.has(slot_name) and dmg_vis.has_method("_apply_persist_to_mat"):
						var meta = GlobalData.weapons.part_hit_meta[slot_name]
						if meta is Dictionary:
							var m_layer := str(meta.get("layer", "armor"))
							var m_pos = meta.get("pos", Vector3.ZERO)
							var m_rad := float(meta.get("radius", 0.65))
							if m_pos is Vector3:
								dmg_vis.update_slot_hit(slot_name, m_layer, m_pos as Vector3, m_rad)


func _attach_custom_mesh_scene(upper_container: Node3D, lower_container: Node3D, upper_scene: PackedScene, lower_scene: PackedScene) -> void:
	if upper_container == null:
		return

	# Explicit lower scene specified
	if lower_scene != null and lower_container != null:
		if upper_scene != null:
			upper_container.add_child(upper_scene.instantiate())
		lower_container.add_child(lower_scene.instantiate())
		return

	# Single scene provided -> auto-split if lower nodes exist
	if upper_scene != null:
		var instance = upper_scene.instantiate()
		if lower_container != null:
			var lower_nodes: Array[Node] = []
			for child in instance.get_children():
				var cname := child.name.to_lower()
				if cname.contains("lower") or cname.contains("forearm") or cname.contains("shin") or cname.contains("knee") or cname.contains("calf") or cname.contains("foot"):
					lower_nodes.append(child)

			if not lower_nodes.is_empty():
				for lnode in lower_nodes:
					instance.remove_child(lnode)
					lower_container.add_child(lnode)

		upper_container.add_child(instance)


func _hide_legacy_slot_meshes(parent_node: Node3D) -> void:
	if not parent_node: return
	for child in parent_node.get_children():
		if child.name != "FrameMesh" and child.name != "ArmorMesh" \
			and child.name != "ForearmLeft" and child.name != "ForearmRight" \
			and child.name != "ShinLeft" and child.name != "ShinRight" \
			and not child.name.begins_with("WeaponVisual_") \
			and not child.name.begins_with("Attachment_") \
			and not child is Light3D:
			child.visible = false
			for grand in child.get_children():
				if (grand is VisualInstance3D or grand is Node3D) and not grand is Light3D:
					grand.visible = false


# Converts a GlobalData equipped part (Dictionary instance, ArmorPart resource or
# null) into the ArmorPart used for rendering that slot.
func build_part_for_slot(equipped: Variant) -> ArmorPart:
	if equipped is ArmorPart:
		return equipped
	var part_obj := ArmorPart.new()
	if equipped is Dictionary:
		# Seed the visual fields from the authored ArmorPart resource behind this
		# catalog/instance entry (path), so each part id can carry its own
		# mesh_scene + inner_frame_scene. Catalog/instance overrides win after.
		var authored := _load_authored_part(equipped)
		if authored != null:
			part_obj.mesh_scene = authored.mesh_scene
			part_obj.mesh_scene_lower = authored.mesh_scene_lower
			part_obj.inner_frame_scene = authored.inner_frame_scene
			part_obj.inner_frame_scene_lower = authored.inner_frame_scene_lower
			part_obj.slot_id = authored.slot_id
			part_obj.part_color = authored.part_color
			part_obj.max_hp = authored.max_hp
			part_obj.part_name = authored.part_name
		part_obj.part_name = equipped.get("name", equipped.get("part_name", part_obj.part_name))
		part_obj.max_hp = GlobalData.weapons.part_stat(equipped, "max_hp", part_obj.max_hp)
		if equipped.has("color"):
			part_obj.part_color = equipped.get("color")
		if equipped.has("mesh_scene_lower") and equipped["mesh_scene_lower"] != null:
			var sc = equipped["mesh_scene_lower"]
			part_obj.mesh_scene_lower = sc if sc is PackedScene else (load(str(sc)) if ResourceLoader.exists(str(sc)) else null)
		if equipped.has("inner_frame_scene_lower") and equipped["inner_frame_scene_lower"] != null:
			var sc = equipped["inner_frame_scene_lower"]
			part_obj.inner_frame_scene_lower = sc if sc is PackedScene else (load(str(sc)) if ResourceLoader.exists(str(sc)) else null)
	return part_obj


# Loads the ArmorPart resource behind a catalog/instance entry. Resolves the
# entry's explicit "path" first; if absent (or not an ArmorPart), falls back to
# the convention path res://resources/mech/parts/{slot}/{id}.tres so future
# part ids render their own model just by dropping a .tres into that folder.
# Returns null when nothing authored exists — callers then use the procedural
# builders.
func _load_authored_part(equipped: Dictionary) -> ArmorPart:
	var res := _try_load_part(str(equipped.get("path", "")))
	if res == null:
		res = _try_load_part(_convention_part_path(equipped))
	return res


func _try_load_part(res_path: String) -> ArmorPart:
	if res_path == "" or not ResourceLoader.exists(res_path):
		return null
	var res = load(res_path)
	return res as ArmorPart


func _convention_part_path(equipped: Dictionary) -> String:
	var part_id := str(equipped.get("id", equipped.get("db_id", "")))
	if part_id == "":
		return ""
	var slot := str(equipped.get("slot", ""))
	if slot == "":
		slot = ArmorSystem.get_armor_catalog_slot(part_id)
	if slot == "":
		return ""
	return "res://resources/mech/parts/%s/%s.tres" % [slot, part_id]


# Rebuilds the visuals of every armor slot from the current GlobalData loadout.
# Hides slots without an inner frame, renders bare frames without armor, and
# renders the equipped armor otherwise. Shared by the hangar and the mecha.
func refresh_slots() -> void:
	_hide_all_legacy_models()
	# A destroyed BODY means the engine core is gone — there is no mech left to
	# stand. The whole machine disappears from the hangar (empty slot) instead of
	# showing a torso-less ghost standing on its legs. In ghost mode (emergency
	# repair) every slot renders a faint skeleton so the driver can still see
	# where each destroyed part goes and place scrap armor on it.
	if float(GlobalData.weapons.part_damage.get("body_frame", 0.0)) >= 1.0:
		for slot in GlobalData.MECHA_SLOTS:
			if ghost_mode:
				_render_ghost_skeleton(slot)
			else:
				hide_slot_completely(slot)
		return
	for slot in GlobalData.MECHA_SLOTS:
		# A destroyed limb (inner frame gone) is gone for good: the slot renders
		# nothing rather than a floating ghost frame, matching combat where the
		# broken part is removed from the mech. In ghost mode (emergency repair /
		# from-zero assembly) the skeleton stays visible so the player can see
		# where the missing frame goes and place a scrap patch on it.
		if float(GlobalData.weapons.part_damage.get(slot + "_frame", 0.0)) >= 1.0:
			if ghost_mode:
				_render_ghost_skeleton(slot)
			else:
				hide_slot_completely(slot)
			continue
		_rebuild_slot(slot, GlobalData.weapons.equipped_frames.get(slot), GlobalData.weapons.equipped_parts.get(slot), true)


# Builds every armor slot from explicit per-slot frame + armor dictionaries —
# same rendering path as the player mech, but fed from an arbitrary loadout so
# enemies can be assembled from the armor catalog. `loadout` maps slot name to
# a {"frame": {...}, "armor": {...}} pair (either may be null/empty).
func refresh_from_loadout(loadout: Dictionary) -> void:
	_hide_all_legacy_models()
	for slot in GlobalData.MECHA_SLOTS:
		var entry: Dictionary = loadout.get(slot, {})
		_rebuild_slot(slot, entry.get("frame"), entry.get("armor"), false)


# Core per-slot rebuild shared by refresh_slots() and refresh_from_loadout().
func _rebuild_slot(slot: String, frame_data: Variant, equipped: Variant, apply_player_scrap: bool) -> void:
	var has_frame = frame_data != null and not (frame_data is Dictionary and frame_data.is_empty())

	var is_armor_equipped = (
		equipped != null and
		not (equipped is Dictionary and equipped.is_empty()) and
		not (equipped is Dictionary and not equipped.get("equipped", false))
	)

	if not has_frame:
		if ghost_mode:
			# GHOST ASSEMBLY PREVIEW: render a translucent skeleton so the player
			# can see where the missing inner frame goes (REGISTER blank slate /
			# emergency repair of a destroyed frame).
			# Note: initialize_slot clears children with queue_free(), so the old
			# ghost meshes overlap the rebuilt frame for exactly one frame — a
			# pre-existing pattern, invisible in practice; don't "fix" it.
			_render_ghost_skeleton(slot)
		else:
			# NO INNER FRAME EQUIPPED: Hide slot completely
			hide_slot_completely(slot)
	elif apply_player_scrap and GlobalData.weapons.scrap_patches.has(slot):
		# EMERGENCY SCRAP PATCH: the slot was rebuilt from scrap, so show the
		# bare inner frame (or scrap stand-in) plus the crude patch primitives
		# the driver placed on it.
		initialize_slot(slot, null, apply_player_scrap)
		_show_inner_frame(slot)
		_render_scrap_patch(slot)
	elif not is_armor_equipped:
		# INNER FRAME EQUIPPED, NO ARMOR: Render bare skeletal inner frame only
		initialize_slot(slot, null, apply_player_scrap)
		_show_inner_frame(slot)
	else:
		# INNER FRAME + OUTER ARMOR EQUIPPED: Render armor over inner frame
		initialize_slot(slot, build_part_for_slot(equipped), apply_player_scrap)


# Rebuilds (or removes) the ScrapPatch primitive visuals for a patched slot.
# Primitive data is stored JSON-safe (arrays) in GlobalData.weapons.scrap_patches. Each
# primitive renders under the skeleton node it is attached to (see the per-
# primitive "attach" field and GlobalData.SCRAP_ATTACH_OPTIONS) so the crude
# armor follows the limb it was placed on.
func refresh_scrap_patches() -> void:
	var mecha = get_parent()
	if mecha == null:
		return
	# Hide every existing patch container first, so stale primitives never linger
	# when a patch is removed or its attach target changes.
	for slot in GlobalData.MECHA_SLOTS:
		for path in GlobalData.scrap_attach_node_paths(slot):
			var parent = mecha.get_node_or_null(path)
			if parent == null:
				continue
			var container = parent.get_node_or_null("ScrapPatch")
			if container:
				_free_patch_children(container)
				container.visible = false
		if GlobalData.weapons.scrap_patches.has(slot):
			_render_scrap_patch(slot)


func _render_scrap_patch(slot: String) -> void:
	var patch: Dictionary = GlobalData.weapons.scrap_patches.get(slot, {})
	if patch.is_empty():
		return
	var primitives: Array = patch.get("primitives", [])
	if not (primitives is Array):
		return

	var containers_used: Dictionary = {}
	for primitive in primitives:
		if not (primitive is Dictionary):
			continue
		var parent = _get_scrap_patch_parent(slot, str(primitive.get("attach", "")))
		if parent == null:
			continue
		var container: Node3D = parent.get_node_or_null("ScrapPatch")
		if container == null:
			container = Node3D.new()
			container.name = "ScrapPatch"
			parent.add_child(container)
		if not containers_used.has(container):
			_free_patch_children(container)
			containers_used[container] = true
		container.visible = true

		var shape: String = str(primitive.get("shape", "box"))
		var pos: Vector3 = GlobalData.scrap_primitive_pos(primitive)
		var rot: Vector3 = GlobalData.scrap_primitive_rot(primitive)
		var scale: Vector3 = GlobalData.scrap_primitive_scale(primitive)
		var color: Color = GlobalData.scrap_primitive_color(primitive)

		var mi := MeshInstance3D.new()
		mi.position = pos
		mi.rotation = rot
		mi.scale = scale
		var is_cloth := shape.to_lower() in ["wrap", "bandage", "cloth", "ribbon", "scarf"]
		mi.mesh = _build_scrap_primitive_mesh(shape)

		if is_cloth:
			var cloth_mat := ShaderMaterial.new()
			cloth_mat.shader = preload("res://shaders/cloth_wrap.gdshader")
			cloth_mat.set_shader_parameter("cloth_color", color)
			mi.material_override = cloth_mat
		else:
			var scrap_mat := ShaderMaterial.new()
			scrap_mat.shader = preload("res://shaders/scrap_metal.gdshader")
			scrap_mat.set_shader_parameter("plate_color", color)
			scrap_mat.set_shader_parameter("rust_intensity", 0.45)
			scrap_mat.set_shader_parameter("metalness", 0.75)
			scrap_mat.set_shader_parameter("roughness_base", 0.45)
			mi.material_override = scrap_mat

		container.add_child(mi)


func _get_scrap_patch_parent(slot: String, attach_path: String) -> Node3D:
	var mecha = get_parent()
	if mecha == null:
		return null
	if attach_path != "":
		var node = mecha.get_node_or_null(attach_path)
		if node != null:
			return node
	return _get_slot_parent_node(slot)


func _free_patch_children(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.free()


func _build_scrap_primitive_mesh(shape: String) -> Mesh:
	match shape.to_lower():
		"sphere":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			return s
		"wedge":
			var w := PrismMesh.new()
			w.size = Vector3.ONE
			return w
		"cylinder":
			var c := CylinderMesh.new()
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 1.0
			return c
		"wrap", "bandage", "cloth", "ribbon":
			var t := TorusMesh.new()
			t.inner_radius = 0.38
			t.outer_radius = 0.52
			t.rings = 16
			t.ring_segments = 12
			return t
		_:
			var b := BoxMesh.new()
			b.size = Vector3.ONE
			return b


func _get_slot_parent_node(slot_name: String) -> Node3D:
	var mecha = get_parent()
	if not mecha:
		return null
	var node_name: String = GlobalData.SLOT_TO_NODE.get(slot_name.to_lower(), "")
	if node_name == "":
		return null
	return mecha.get_node_or_null(node_name)


const _LOWER_NODE_NAMES: Dictionary = {
	"arm_left": "ArmLeft/ForearmLeft",
	"arm_right": "ArmRight/ForearmRight",
	"leg_left": "LegLeft/ShinLeft",
	"leg_right": "LegRight/ShinRight",
}


func _get_slot_lower_parent_node(slot_name: String) -> Node3D:
	var mecha = get_parent()
	if not mecha:
		return null
	var path: String = _LOWER_NODE_NAMES.get(slot_name.to_lower(), "")
	if path == "":
		return null
	return mecha.get_node_or_null(path)


func _clear_children(node: Node) -> void:
	if not node: return
	for child in node.get_children():
		child.queue_free()


func _on_part_destroyed(slot_name: String) -> void:
	# Play cloth tear SFX if this slot had frame bindings
	if GlobalData.weapons.frame_bindings.has(slot_name) and GlobalData.weapons.frame_bindings[slot_name]:
		var entry = slot_meshes.get(slot_name)
		if entry != null and entry["frame"] != null and AudioManager:
			AudioManager.play_cloth_tear(entry["frame"].global_position)
	hide_slot_completely(slot_name)
	_spawn_break_vfx(slot_name)


# Rebuilds a slot's inner frame skeleton with the translucent ghost material.
# Shared by the from-zero REGISTER assembly (blank slate) and the emergency
# repair editor (a destroyed frame) so the player can see where the missing
# frame goes and place scrap armor on it.
func _render_ghost_skeleton(slot_name: String) -> void:
	initialize_slot(slot_name, null, false)
	_show_inner_frame(slot_name)
	_apply_ghost_material(slot_name)


func _show_inner_frame(slot_name: String) -> void:
	var entry = slot_meshes.get(slot_name)
	if entry == null:
		return
	if entry["armor"]: entry["armor"].visible = false
	if entry.get("armor_lower") and entry["armor_lower"]: entry["armor_lower"].visible = false
	if entry["frame"]: entry["frame"].visible = true
	if entry.get("frame_lower") and entry["frame_lower"]: entry["frame_lower"].visible = true


# True when `slot_name` is rendering the translucent ghost frame — i.e. ghost
# mode is armed AND the slot currently has no real frame and its skeleton is
# visible with a transparent override. Used by the hangar verify tests.
func is_ghost_frame_visible(slot_name: String) -> bool:
	if not ghost_mode:
		return false
	var entry = slot_meshes.get(slot_name)
	if entry == null or entry["frame"] == null or not entry["frame"].visible:
		return false
	return _has_translucent_override(entry["frame"])


func _has_translucent_override(node: Node) -> bool:
	for child in node.get_children():
		if child is GeometryInstance3D:
			var mat = child.material_override
			if mat is BaseMaterial3D and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				return true
		if _has_translucent_override(child):
			return true
	return false


# Translucent cyan hologram material for the from-zero assembly preview.
# Cached (not rebuilt per slot) since ghosts redraw on every preview refresh.
func _get_ghost_frame_material() -> StandardMaterial3D:
	if _ghost_mat == null:
		_ghost_mat = StandardMaterial3D.new()
		_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_mat.albedo_color = Color(0.35, 0.8, 1.0, 0.18)
		_ghost_mat.metallic = 0.2
		_ghost_mat.roughness = 0.4
		_ghost_mat.emission_enabled = true
		_ghost_mat.emission = Color(0.2, 0.6, 1.0)
		_ghost_mat.emission_energy_multiplier = 0.6
	return _ghost_mat


# Overrides every mesh under the slot's frame containers with the ghost
# material so the whole skeleton renders as a faint hologram.
func _apply_ghost_material(slot_name: String) -> void:
	var entry = slot_meshes.get(slot_name)
	if entry == null:
		return
	var ghost_mat := _get_ghost_frame_material()
	for container in [entry["frame"], entry.get("frame_lower")]:
		if container != null:
			_apply_material_recursive(container, ghost_mat)


func _apply_material_recursive(node: Node, mat: Material) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			child.material_override = mat
		_apply_material_recursive(child, mat)


func _spawn_break_vfx(slot_name: String) -> void:
	var entry = slot_meshes.get(slot_name)
	if entry == null or entry["frame"] == null:
		return
	var origin_pos = entry["frame"].global_position
	
	for i in range(5):
		var debris = RigidBody3D.new()
		
		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(randf_range(0.15, 0.35), randf_range(0.15, 0.35), randf_range(0.1, 0.2))
		col.shape = shape
		debris.add_child(col)
		
		var mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = shape.size
		mesh_inst.mesh = box
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.40, 0.60)
		mat.metallic = 0.75
		mat.roughness = 0.3
		mesh_inst.material_override = mat
		debris.add_child(mesh_inst)
		
		get_tree().current_scene.add_child(debris)
		# Position must be set while already inside the tree (global_position on a
		# node not yet added to the scene returns a null transform).
		debris.position = origin_pos + Vector3(randf_range(-0.3, 0.3), randf_range(0.2, 0.6), randf_range(-0.3, 0.3))
		
		var impulse = Vector3(randf_range(-4, 4), randf_range(3, 7), randf_range(-4, 4))
		debris.apply_central_impulse(impulse)
		
		var tween = debris.create_tween()
		tween.tween_property(mesh_inst, "scale", Vector3.ZERO, 0.5).set_delay(2.5)
		tween.tween_callback(debris.queue_free)
		
	var vfx_scene = load("res://scenes/mecha/effects/vfx_armor_break.tscn")
	if vfx_scene and entry["armor"] and entry["armor"].is_inside_tree():
		var vfx = vfx_scene.instantiate()
		entry["armor"].get_parent().add_child(vfx)
		vfx.global_position = entry["armor"].global_position


# Helper materials for inner frame & armor
func _get_dark_frame_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.render_priority = 0
	mat.albedo_color = Color(0.14, 0.16, 0.20)
	mat.metallic = 0.92
	mat.roughness = 0.25
	return mat

func _get_chrome_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.render_priority = 0
	mat.albedo_color = Color(0.85, 0.88, 0.92)
	mat.metallic = 0.98
	mat.roughness = 0.10
	return mat

func _get_eye_sensor_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.render_priority = 0
	mat.albedo_color = Color(1.0, 0.12, 0.20)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.15, 0.25)
	mat.emission_energy_multiplier = 4.0
	return mat


# ==============================================================================
# SKELETAL INNER FRAME GENERATOR (UPPER + LOWER JOINT SPLIT)
# ==============================================================================
func _build_procedural_inner_frame(slot_name: String, upper_container: Node3D, lower_container: Node3D = null) -> void:
	var frame_mat = _get_dark_frame_material()
	var chrome_mat = _get_chrome_material()
	var eye_mat = _get_eye_sensor_material()

	match slot_name.to_lower():
		"head":
			var skull = MeshInstance3D.new()
			var s_box = BoxMesh.new()
			s_box.size = Vector3(0.24, 0.22, 0.28)
			skull.mesh = s_box
			skull.position = Vector3(0, 0.04, 0)
			skull.material_override = frame_mat
			upper_container.add_child(skull)

			var eye = MeshInstance3D.new()
			var e_box = BoxMesh.new()
			e_box.size = Vector3(0.16, 0.08, 0.06)
			eye.mesh = e_box
			eye.position = Vector3(0, 0.06, -0.14)
			eye.material_override = eye_mat
			upper_container.add_child(eye)

			var neck = MeshInstance3D.new()
			var n_cyl = CylinderMesh.new()
			n_cyl.top_radius = 0.08
			n_cyl.bottom_radius = 0.08
			n_cyl.height = 0.26
			neck.mesh = n_cyl
			neck.position = Vector3(0, -0.13, 0)
			neck.material_override = chrome_mat
			upper_container.add_child(neck)

		"body":
			var spine = MeshInstance3D.new()
			var sp_box = BoxMesh.new()
			sp_box.size = Vector3(0.18, 0.90, 0.18)
			spine.mesh = sp_box
			spine.position = Vector3(0, 0.05, 0)
			spine.material_override = frame_mat
			upper_container.add_child(spine)

			for rib_y in [0.28, 0.08, -0.12]:
				var rib = MeshInstance3D.new()
				var r_box = BoxMesh.new()
				r_box.size = Vector3(0.56, 0.08, 0.32)
				rib.mesh = r_box
				rib.position = Vector3(0, rib_y, 0)
				rib.material_override = frame_mat
				upper_container.add_child(rib)

			var core = MeshInstance3D.new()
			var c_cyl = CylinderMesh.new()
			c_cyl.top_radius = 0.14
			c_cyl.bottom_radius = 0.14
			c_cyl.height = 0.48
			core.mesh = c_cyl
			core.position = Vector3(0, 0.10, 0)
			core.material_override = chrome_mat
			upper_container.add_child(core)

			for side_x in [-0.42, 0.42]:
				var socket = MeshInstance3D.new()
				var s_cyl = CylinderMesh.new()
				s_cyl.top_radius = 0.14
				s_cyl.bottom_radius = 0.14
				s_cyl.height = 0.16
				socket.mesh = s_cyl
				socket.rotation_degrees.z = 90
				socket.position = Vector3(side_x, 0.28, 0)
				socket.material_override = frame_mat
				upper_container.add_child(socket)

			var waist = MeshInstance3D.new()
			var w_cyl = CylinderMesh.new()
			w_cyl.top_radius = 0.22
			w_cyl.bottom_radius = 0.22
			w_cyl.height = 0.12
			waist.mesh = w_cyl
			waist.position = Vector3(0, -0.38, 0)
			waist.material_override = frame_mat
			upper_container.add_child(waist)

			for piston_x in [-0.14, 0.14]:
				var piston = MeshInstance3D.new()
				var p_cyl = CylinderMesh.new()
				p_cyl.top_radius = 0.03
				p_cyl.bottom_radius = 0.03
				p_cyl.height = 0.32
				piston.mesh = p_cyl
				piston.position = Vector3(piston_x, -0.24, 0)
				piston.material_override = chrome_mat
				upper_container.add_child(piston)

		"arm_left", "arm_right":
			# --- UPPER ARM SEGMENT (Attaches to Shoulder Pivot ArmLeft/ArmRight) ---
			var shoulder_joint = MeshInstance3D.new()
			var s_sphere = SphereMesh.new()
			s_sphere.radius = 0.16
			s_sphere.height = 0.32
			shoulder_joint.mesh = s_sphere
			shoulder_joint.material_override = frame_mat
			upper_container.add_child(shoulder_joint)

			var shoulder_bolt = MeshInstance3D.new()
			var b_cyl = CylinderMesh.new()
			b_cyl.top_radius = 0.17
			b_cyl.bottom_radius = 0.17
			b_cyl.height = 0.08
			shoulder_bolt.mesh = b_cyl
			shoulder_bolt.rotation_degrees.z = 90
			shoulder_bolt.material_override = chrome_mat
			upper_container.add_child(shoulder_bolt)

			var upper_arm = MeshInstance3D.new()
			var u_box = BoxMesh.new()
			u_box.size = Vector3(0.16, 0.38, 0.16)
			upper_arm.mesh = u_box
			upper_arm.position = Vector3(0, -0.19, 0)
			upper_arm.material_override = frame_mat
			upper_container.add_child(upper_arm)

			# --- LOWER ARM SEGMENT (Attaches to Elbow Pivot ForearmLeft/ForearmRight) ---
			if lower_container:
				var elbow_disc = MeshInstance3D.new()
				var e_cyl = CylinderMesh.new()
				e_cyl.top_radius = 0.11
				e_cyl.bottom_radius = 0.11
				e_cyl.height = 0.12
				elbow_disc.mesh = e_cyl
				elbow_disc.rotation_degrees.z = 90
				elbow_disc.position = Vector3(0, 0, 0)
				elbow_disc.material_override = chrome_mat
				lower_container.add_child(elbow_disc)

				var forearm_frame = MeshInstance3D.new()
				var f_box = BoxMesh.new()
				f_box.size = Vector3(0.18, 0.45, 0.18)
				forearm_frame.mesh = f_box
				forearm_frame.position = Vector3(0, -0.225, 0)
				forearm_frame.material_override = frame_mat
				lower_container.add_child(forearm_frame)

				var hand_block = MeshInstance3D.new()
				var h_box = BoxMesh.new()
				h_box.size = Vector3(0.14, 0.14, 0.16)
				hand_block.mesh = h_box
				hand_block.position = Vector3(0, -0.46, 0)
				hand_block.material_override = chrome_mat
				lower_container.add_child(hand_block)

		"leg_left", "leg_right":
			# --- UPPER LEG SEGMENT (Attaches to Hip Pivot LegLeft/LegRight) ---
			var hip_joint = MeshInstance3D.new()
			var h_sphere = SphereMesh.new()
			h_sphere.radius = 0.18
			h_sphere.height = 0.36
			hip_joint.mesh = h_sphere
			hip_joint.material_override = frame_mat
			upper_container.add_child(hip_joint)

			var thigh_frame = MeshInstance3D.new()
			var t_box = BoxMesh.new()
			t_box.size = Vector3(0.18, 0.44, 0.18)
			thigh_frame.mesh = t_box
			thigh_frame.position = Vector3(0, -0.275, 0)
			thigh_frame.material_override = frame_mat
			upper_container.add_child(thigh_frame)

			# --- LOWER LEG SEGMENT (Attaches to Knee Pivot ShinLeft/ShinRight) ---
			if lower_container:
				var knee_disc = MeshInstance3D.new()
				var k_cyl = CylinderMesh.new()
				k_cyl.top_radius = 0.12
				k_cyl.bottom_radius = 0.12
				k_cyl.height = 0.12
				knee_disc.mesh = k_cyl
				knee_disc.rotation_degrees.z = 90
				knee_disc.position = Vector3(0, 0, 0)
				knee_disc.material_override = chrome_mat
				lower_container.add_child(knee_disc)

				var shin_frame = MeshInstance3D.new()
				var s_box = BoxMesh.new()
				s_box.size = Vector3(0.18, 0.44, 0.18)
				shin_frame.mesh = s_box
				shin_frame.position = Vector3(0, -0.275, 0)
				shin_frame.material_override = frame_mat
				lower_container.add_child(shin_frame)

				var damper = MeshInstance3D.new()
				var d_cyl = CylinderMesh.new()
				d_cyl.top_radius = 0.022
				d_cyl.bottom_radius = 0.022
				d_cyl.height = 0.40
				damper.mesh = d_cyl
				damper.position = Vector3(0, -0.275, 0.10)
				damper.material_override = chrome_mat
				lower_container.add_child(damper)

				var ankle = MeshInstance3D.new()
				var a_cyl = CylinderMesh.new()
				a_cyl.top_radius = 0.09
				a_cyl.bottom_radius = 0.09
				a_cyl.height = 0.08
				ankle.mesh = a_cyl
				ankle.position = Vector3(0, -0.53, 0)
				ankle.material_override = chrome_mat
				lower_container.add_child(ankle)

				var foot_block = MeshInstance3D.new()
				var ft_box = BoxMesh.new()
				ft_box.size = Vector3(0.16, 0.05, 0.18)
				foot_block.mesh = ft_box
				foot_block.position = Vector3(0, -0.58, 0)
				foot_block.material_override = frame_mat
				lower_container.add_child(foot_block)

				for claw_x in [-0.08, 0.08]:
					var claw = MeshInstance3D.new()
					var c_box = BoxMesh.new()
					c_box.size = Vector3(0.05, 0.05, 0.22)
					claw.mesh = c_box
					claw.position = Vector3(claw_x, -0.59, -0.14)
					claw.rotation_degrees.x = -15
					claw.material_override = frame_mat
					lower_container.add_child(claw)

				var heel = MeshInstance3D.new()
				var h_box = BoxMesh.new()
				h_box.size = Vector3(0.12, 0.05, 0.15)
				heel.mesh = h_box
				heel.position = Vector3(0, -0.59, 0.12)
				heel.rotation_degrees.x = 15
				heel.material_override = frame_mat
				lower_container.add_child(heel)

		_:
			var box = BoxMesh.new()
			box.size = Vector3(0.2, 0.8, 0.2)
			var base_mesh = MeshInstance3D.new()
			base_mesh.mesh = box
			base_mesh.material_override = frame_mat
			upper_container.add_child(base_mesh)


# ==============================================================================
# MODULAR OUTER ARMOR GENERATOR (UPPER + LOWER JOINT SPLIT)
# ==============================================================================
func _build_procedural_outer_armor(slot_name: String, upper_container: Node3D, lower_container: Node3D = null, part: ArmorPart = null) -> void:
	var col = Color(0.28, 0.32, 0.38) # Sleek Titanium Gunmetal
	if part and "part_color" in part and part.part_color != Color.TRANSPARENT and part.part_color.a > 0.1:
		col = part.part_color

	var armor_mat = StandardMaterial3D.new()
	armor_mat.render_priority = 1
	armor_mat.grow = true
	armor_mat.grow_amount = 0.003
	armor_mat.albedo_color = col
	armor_mat.metallic = 0.88
	armor_mat.roughness = 0.32

	var dark_trim_mat = StandardMaterial3D.new()
	dark_trim_mat.render_priority = 1
	dark_trim_mat.grow = true
	dark_trim_mat.grow_amount = 0.0035
	dark_trim_mat.albedo_color = Color(0.12, 0.14, 0.18)
	dark_trim_mat.metallic = 0.94
	dark_trim_mat.roughness = 0.22

	match slot_name.to_lower():
		"head":
			var helmet = MeshInstance3D.new()
			var h_box = BoxMesh.new()
			h_box.size = Vector3(0.36, 0.26, 0.36)
			helmet.mesh = h_box
			helmet.position = Vector3(0, 0.04, 0)
			helmet.material_override = armor_mat
			upper_container.add_child(helmet)

			for side_x in [-0.18, 0.18]:
				var cheek = MeshInstance3D.new()
				var c_box = BoxMesh.new()
				c_box.size = Vector3(0.06, 0.18, 0.22)
				cheek.mesh = c_box
				cheek.position = Vector3(side_x, -0.02, -0.05)
				cheek.material_override = dark_trim_mat
				upper_container.add_child(cheek)

			var brow = MeshInstance3D.new()
			var b_prism = PrismMesh.new()
			b_prism.size = Vector3(0.18, 0.20, 0.28)
			brow.mesh = b_prism
			brow.rotation_degrees.x = -25
			brow.position = Vector3(0, 0.18, -0.05)
			brow.material_override = armor_mat
			upper_container.add_child(brow)

			var collar = MeshInstance3D.new()
			var cl_cyl = CylinderMesh.new()
			cl_cyl.top_radius = 0.20
			cl_cyl.bottom_radius = 0.22
			cl_cyl.height = 0.12
			collar.mesh = cl_cyl
			collar.position = Vector3(0, -0.16, 0)
			collar.material_override = dark_trim_mat
			upper_container.add_child(collar)

		"body":
			var chest = MeshInstance3D.new()
			var c_prism = PrismMesh.new()
			c_prism.size = Vector3(0.95, 0.65, 0.48)
			chest.mesh = c_prism
			chest.rotation_degrees.x = 90
			chest.position = Vector3(0, 0.12, -0.14)
			chest.material_override = armor_mat
			upper_container.add_child(chest)

			for side_x in [-0.42, 0.42]:
				var vent = MeshInstance3D.new()
				var v_box = BoxMesh.new()
				v_box.size = Vector3(0.14, 0.35, 0.25)
				vent.mesh = v_box
				vent.position = Vector3(side_x, 0.15, -0.08)
				vent.material_override = dark_trim_mat
				upper_container.add_child(vent)

			var ab_plate = MeshInstance3D.new()
			var ab_box = BoxMesh.new()
			ab_box.size = Vector3(0.58, 0.35, 0.26)
			ab_plate.mesh = ab_box
			ab_plate.position = Vector3(0, -0.28, -0.10)
			ab_plate.material_override = armor_mat
			upper_container.add_child(ab_plate)

		"arm_left", "arm_right":
			var is_left = slot_name.to_lower() == "arm_left"
			var dir_sign = -1.0 if is_left else 1.0

			# --- UPPER ARM ARMOR (Shoulder Pauldron attached to ArmLeft/ArmRight) ---
			var pauldron = MeshInstance3D.new()
			var p_box = BoxMesh.new()
			p_box.size = Vector3(0.44, 0.32, 0.44)
			pauldron.mesh = p_box
			pauldron.position = Vector3(dir_sign * 0.08, 0.04, 0)
			pauldron.material_override = armor_mat
			upper_container.add_child(pauldron)

			var trim = MeshInstance3D.new()
			var t_box = BoxMesh.new()
			t_box.size = Vector3(0.48, 0.10, 0.48)
			trim.mesh = t_box
			trim.position = Vector3(dir_sign * 0.08, 0.16, 0)
			trim.material_override = dark_trim_mat
			upper_container.add_child(trim)

			# --- LOWER ARM ARMOR (Forearm Guard attached to ForearmLeft/ForearmRight) ---
			if lower_container:
				var forearm_guard = MeshInstance3D.new()
				var fg_box = BoxMesh.new()
				fg_box.size = Vector3(0.30, 0.44, 0.30)
				forearm_guard.mesh = fg_box
				forearm_guard.position = Vector3(0, -0.225, 0)
				forearm_guard.material_override = armor_mat
				lower_container.add_child(forearm_guard)

				var knuckle = MeshInstance3D.new()
				var k_box = BoxMesh.new()
				k_box.size = Vector3(0.16, 0.05, 0.16)
				knuckle.mesh = k_box
				knuckle.position = Vector3(0, -0.45, -0.02)
				knuckle.material_override = armor_mat
				lower_container.add_child(knuckle)

		"leg_left", "leg_right":
			# --- UPPER LEG ARMOR (Thigh Guard attached to LegLeft/LegRight) ---
			var thigh_armor = MeshInstance3D.new()
			var ta_box = BoxMesh.new()
			ta_box.size = Vector3(0.32, 0.42, 0.32)
			thigh_armor.mesh = ta_box
			thigh_armor.position = Vector3(0, -0.275, 0)
			thigh_armor.material_override = armor_mat
			upper_container.add_child(thigh_armor)

			# --- LOWER LEG ARMOR (Knee Cap + Shin Guard attached to ShinLeft/ShinRight) ---
			if lower_container:
				var knee_cap = MeshInstance3D.new()
				var k_prism = PrismMesh.new()
				k_prism.size = Vector3(0.24, 0.22, 0.20)
				knee_cap.mesh = k_prism
				knee_cap.rotation_degrees.x = 90
				knee_cap.position = Vector3(0, 0, 0.15)
				knee_cap.material_override = armor_mat
				lower_container.add_child(knee_cap)

				var shin_armor = MeshInstance3D.new()
				var sa_box = BoxMesh.new()
				sa_box.size = Vector3(0.34, 0.48, 0.30)
				shin_armor.mesh = sa_box
				shin_armor.position = Vector3(0, -0.275, 0.04)
				shin_armor.material_override = armor_mat
				lower_container.add_child(shin_armor)

				var foot_cap = MeshInstance3D.new()
				var fc_box = BoxMesh.new()
				fc_box.size = Vector3(0.26, 0.09, 0.28)
				foot_cap.mesh = fc_box
				foot_cap.position = Vector3(0, -0.58, -0.04)
				foot_cap.material_override = armor_mat
				lower_container.add_child(foot_cap)

		_:
			var box = BoxMesh.new()
			box.size = Vector3(0.6, 0.6, 0.6)
			var base_mesh = MeshInstance3D.new()
			base_mesh.mesh = box
			base_mesh.material_override = armor_mat
			upper_container.add_child(base_mesh)


# ---------------------------------------------------------------------------
# INNER FRAME BINDING (GDD §6.2)
# Composite cloth wraps around exposed inner frame to reinforce cracks.
# Visual: thick bandages tightly wrapped along the frame skeleton.
# ---------------------------------------------------------------------------

## Cloth wrap colors for frame bindings.
const BINDING_COLOR_LIGHT := Color(0.72, 0.70, 0.65, 0.92)   # Off-white composite cloth
const BINDING_COLOR_DARK := Color(0.45, 0.42, 0.38, 0.88)    # Dirty grey wrap
const BINDING_COLOR_ACCENT := Color(0.55, 0.60, 0.50, 0.85)  # Military green tint

## Default binding layout per slot: position, rotation, scale for each wrap ring.
## Each entry = one cloth torus around the frame at that offset.
var _binding_templates: Dictionary = {
	"head": [
		{"pos": Vector3(0, 0.15, 0), "rot": Vector3(0, 0, 0), "scale": Vector3(0.28, 0.06, 0.28), "color": BINDING_COLOR_LIGHT},
	],
	"body": [
		{"pos": Vector3(0, 0.2, 0), "rot": Vector3(0, 0, 0), "scale": Vector3(0.38, 0.08, 0.35), "color": BINDING_COLOR_LIGHT},
		{"pos": Vector3(0, -0.1, 0), "rot": Vector3(0, 0, 0), "scale": Vector3(0.35, 0.06, 0.32), "color": BINDING_COLOR_DARK},
	],
	"arm_left": [
		{"pos": Vector3(0, 0.1, 0), "rot": Vector3(0, 0, 0.15), "scale": Vector3(0.14, 0.05, 0.14), "color": BINDING_COLOR_LIGHT},
		{"pos": Vector3(0, -0.15, 0), "rot": Vector3(0, 0, -0.1), "scale": Vector3(0.12, 0.04, 0.12), "color": BINDING_COLOR_ACCENT},
	],
	"arm_right": [
		{"pos": Vector3(0, 0.1, 0), "rot": Vector3(0, 0, -0.15), "scale": Vector3(0.14, 0.05, 0.14), "color": BINDING_COLOR_LIGHT},
		{"pos": Vector3(0, -0.15, 0), "rot": Vector3(0, 0, 0.1), "scale": Vector3(0.12, 0.04, 0.12), "color": BINDING_COLOR_ACCENT},
	],
	"leg_left": [
		{"pos": Vector3(0, 0.15, 0), "rot": Vector3(0, 0, 0), "scale": Vector3(0.16, 0.05, 0.16), "color": BINDING_COLOR_DARK},
		{"pos": Vector3(0, -0.2, 0), "rot": Vector3(0, 0, 0), "scale": Vector3(0.14, 0.04, 0.14), "color": BINDING_COLOR_LIGHT},
	],
	"leg_right": [
		{"pos": Vector3(0, 0.15, 0), "rot": Vector3(0, 0, 0), "scale": Vector3(0.16, 0.05, 0.16), "color": BINDING_COLOR_DARK},
		{"pos": Vector3(0, -0.2, 0), "rot": Vector3(0, 0, 0), "scale": Vector3(0.14, 0.04, 0.14), "color": BINDING_COLOR_LIGHT},
],
}


## Tracking for flutter animation on frame bindings.
var _binding_meshes: Dictionary = {}  # slot -> Array[MeshInstance3D]
var _binding_base_rotations: Dictionary = {}  # slot -> Array[Vector3]
var _binding_time: float = 0.0


## Spawns composite cloth bindings around the exposed inner frame for a slot.
## Called after emergency repair when the frame is damaged but not destroyed.
func spawn_frame_binding(slot: String) -> void:
	var mecha = get_parent()
	if mecha == null:
		return
	var parent := _get_slot_parent_node(slot)
	if parent == null:
		return

	# Remove existing bindings for this slot first
	_remove_frame_binding(slot)

	var container := Node3D.new()
	container.name = "FrameBinding"
	parent.add_child(container)

	var templates: Array = _binding_templates.get(slot, [])
	for tmpl in templates:
		if not (tmpl is Dictionary):
			continue
		var mi := MeshInstance3D.new()
		mi.position = tmpl.get("pos", Vector3.ZERO)
		mi.rotation = tmpl.get("rot", Vector3.ZERO)
		mi.scale = tmpl.get("scale", Vector3.ONE)

		# Torus mesh for the cloth wrap ring
		var torus := TorusMesh.new()
		torus.inner_radius = 0.38
		torus.outer_radius = 0.52
		torus.rings = 16
		torus.ring_segments = 12
		mi.mesh = torus

		# Cloth wrap shader material
		var cloth_mat := ShaderMaterial.new()
		cloth_mat.shader = preload("res://shaders/cloth_wrap.gdshader")
		cloth_mat.set_shader_parameter("cloth_color", tmpl.get("color", BINDING_COLOR_LIGHT))
		mi.material_override = cloth_mat

		container.add_child(mi)
		# Track mesh for flutter animation
		if not _binding_meshes.has(slot):
			_binding_meshes[slot] = []
			_binding_base_rotations[slot] = []
		_binding_meshes[slot].append(mi)
		_binding_base_rotations[slot].append(tmpl.get("rot", Vector3.ZERO))

	# Record binding in GlobalData for persistence
	if not GlobalData.weapons.frame_bindings.has(slot):
		GlobalData.weapons.frame_bindings[slot] = true


## Removes the frame binding visual for a slot.
func _remove_frame_binding(slot: String) -> void:
	var mecha = get_parent()
	if mecha == null:
		return
	var parent := _get_slot_parent_node(slot)
	if parent == null:
		return
	var container = parent.get_node_or_null("FrameBinding")
	if container:
		container.queue_free()
	_binding_meshes.erase(slot)
	_binding_base_rotations.erase(slot)
	GlobalData.weapons.frame_bindings.erase(slot)


## Rebuilds all frame binding visuals from saved data.
## Called on combat entry / board spawn to restore bindings from a previous run.
func refresh_frame_bindings() -> void:
	for slot in GlobalData.weapons.frame_bindings:
		if GlobalData.weapons.frame_bindings[slot]:
			spawn_frame_binding(slot)


## Removes all frame bindings (e.g. after professional repair).
func clear_all_frame_bindings() -> void:
	for slot in GlobalData.MECHA_SLOTS:
		_remove_frame_binding(slot)


## Removes a specific frame binding (e.g. after professional repair of one slot).
func remove_frame_binding(slot: String) -> void:
	_remove_frame_binding(slot)


## Updates frame binding flutter animation each frame.
## Bindings sway gently with movement and vibrate on impact.
## Called from mecha controller _physics_process.
func update_frame_bindings(delta: float, velocity: Vector3) -> void:
	if _binding_meshes.is_empty():
		return

	_binding_time += delta
	var speed := velocity.length()
	var flutter := clampf(speed / 12.0, 0.05, 0.8)  # Gentle even at rest

	for slot in _binding_meshes:
		var meshes: Array = _binding_meshes[slot]
		var bases: Array = _binding_base_rotations[slot]
		for i in meshes.size():
			var mi: MeshInstance3D = meshes[i]
			if not is_instance_valid(mi):
				continue
			var base_rot: Vector3 = bases[i]
			# Each ring gets a unique phase offset based on slot + index
			var phase := hash(slot) * 0.001 + float(i) * 1.2
			# Primary sway: slow Z oscillation (wrapping looseness)
			var sway_z := sin(_binding_time * 2.5 + phase) * 2.5 * flutter
			# Secondary breathe: subtle X rotation pulse
			var breathe_x := cos(_binding_time * 1.8 + phase * 0.7) * 1.5 * flutter
			# Micro-jitter: high-frequency vibrate when moving fast
			var jitter := sin(_binding_time * 18.0 + phase * 3.0) * 0.8 * clampf(speed / 20.0, 0.0, 1.0)
			mi.rotation_degrees = base_rot + Vector3(breathe_x + jitter, 0, sway_z)


# ---------------------------------------------------------------------------
# THERMAL CLOAK VISUAL (GDD §6.2)
# Physics-enabled cloth cape that flutters with movement.
# Attaches to the body section and flaps based on velocity.
# ---------------------------------------------------------------------------

var _cloak_visual: Node3D = null
var _cloak_meshes: Array[MeshInstance3D] = []
var _cloak_time: float = 0.0
var _cloak_was_active: bool = false

## Cloak cloth material — military green with slight transparency.
func _get_cloak_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/cloth_wrap.gdshader")
	mat.set_shader_parameter("cloth_color", Color(0.32, 0.38, 0.28, 0.85))
	return mat


## Spawns the thermal cloak visual on the mecha's body.
func spawn_cloak_visual() -> void:
	if _cloak_visual != null and is_instance_valid(_cloak_visual):
		return
	var mecha = get_parent()
	if mecha == null:
		return
	var body_node = mecha.get_node_or_null("Body")
	if body_node == null:
		body_node = mecha

	_cloak_visual = Node3D.new()
	_cloak_visual.name = "ThermalCloak"
	body_node.add_child(_cloak_visual)
	_cloak_visual.position = Vector3(0, 0.3, 0.15)  # Back of torso

	var mat := _get_cloak_material()
	_cloak_meshes.clear()

	# Main cape panel (large quad behind the back)
	var main_cape := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 1.0)
	main_cape.mesh = quad
	main_cape.material_override = mat
	main_cape.position = Vector3(0, -0.2, 0)
	main_cape.rotation_degrees.x = 15.0  # Slight backward lean
	_cloak_visual.add_child(main_cape)
	_cloak_meshes.append(main_cape)

	# Left shoulder drape
	var left_drape := MeshInstance3D.new()
	var lquad := QuadMesh.new()
	lquad.size = Vector2(0.35, 0.6)
	left_drape.mesh = lquad
	left_drape.material_override = mat
	left_drape.position = Vector3(-0.35, 0.1, 0.05)
	left_drape.rotation_degrees.x = 25.0
	left_drape.rotation_degrees.z = 10.0
	_cloak_visual.add_child(left_drape)
	_cloak_meshes.append(left_drape)

	# Right shoulder drape
	var right_drape := MeshInstance3D.new()
	var rquad := QuadMesh.new()
	rquad.size = Vector2(0.35, 0.6)
	right_drape.mesh = rquad
	right_drape.material_override = mat
	right_drape.position = Vector3(0.35, 0.1, 0.05)
	right_drape.rotation_degrees.x = 25.0
	right_drape.rotation_degrees.z = -10.0
	_cloak_visual.add_child(right_drape)
	_cloak_meshes.append(right_drape)

	# Lower trailing edge
	var trail := MeshInstance3D.new()
	var tquad := QuadMesh.new()
	tquad.size = Vector2(0.5, 0.4)
	trail.mesh = tquad
	trail.material_override = mat
	trail.position = Vector3(0, -0.6, 0.2)
	trail.rotation_degrees.x = 35.0
	_cloak_visual.add_child(trail)
	_cloak_meshes.append(trail)

	_cloak_visual.visible = false


## Removes the cloak visual.
func remove_cloak_visual() -> void:
	if _cloak_visual != null and is_instance_valid(_cloak_visual):
		_cloak_visual.queue_free()
		_cloak_visual = null
	_cloak_meshes.clear()


## Updates cloak visibility and flutter animation each frame.
## Called from the mecha controller's _process or _physics_process.
func update_cloak_visual(delta: float, velocity: Vector3) -> void:
	var should_show := false
	if GlobalData.thermal_cloak != null and GlobalData.thermal_cloak.is_cloak_active():
		should_show = true

	# Spawn/remove as needed
	if should_show and (_cloak_visual == null or not is_instance_valid(_cloak_visual)):
		spawn_cloak_visual()
	elif not should_show and _cloak_visual != null and is_instance_valid(_cloak_visual):
		remove_cloak_visual()
		return

	if _cloak_visual == null or not is_instance_valid(_cloak_visual):
		return

	_cloak_visual.visible = should_show
	if not should_show:
		return

	# Physics-based flutter animation
	_cloak_time += delta
	var speed := velocity.length()
	var flutter_intensity := clampf(speed / 15.0, 0.1, 1.0)  # More flutter at higher speed

	# Main cape: sway side to side + wave up/down
	if _cloak_meshes.size() > 0:
		var cape := _cloak_meshes[0]
		cape.rotation_degrees.z = sin(_cloak_time * 3.0) * 8.0 * flutter_intensity
		cape.rotation_degrees.x = 15.0 + cos(_cloak_time * 2.5) * 5.0 * flutter_intensity

	# Left drape: opposite phase
	if _cloak_meshes.size() > 1:
		var ld := _cloak_meshes[1]
		ld.rotation_degrees.z = 10.0 + sin(_cloak_time * 3.5 + 1.0) * 6.0 * flutter_intensity
		ld.rotation_degrees.x = 25.0 + cos(_cloak_time * 2.0) * 4.0 * flutter_intensity

	# Right drape: opposite phase
	if _cloak_meshes.size() > 2:
		var rd := _cloak_meshes[2]
		rd.rotation_degrees.z = -10.0 + sin(_cloak_time * 3.5 + 2.0) * 6.0 * flutter_intensity
		rd.rotation_degrees.x = 25.0 + cos(_cloak_time * 2.0 + 1.0) * 4.0 * flutter_intensity

	# Trail: strong wave at the bottom
	if _cloak_meshes.size() > 3:
		var tr := _cloak_meshes[3]
		tr.rotation_degrees.z = sin(_cloak_time * 4.0) * 12.0 * flutter_intensity
		tr.rotation_degrees.x = 35.0 + cos(_cloak_time * 3.0) * 8.0 * flutter_intensity
		tr.position.y = -0.6 + sin(_cloak_time * 2.0) * 0.05 * flutter_intensity
