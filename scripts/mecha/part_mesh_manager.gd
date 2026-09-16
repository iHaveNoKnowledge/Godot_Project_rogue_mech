extends Node3D

const MASTER_PBR_SHADER: Shader = preload("res://shaders/mecha_master_pbr.gdshader")
# Centralized scale — use MechaScaleSystem.WORLD_SCALE (newest). Kept here for legacy callers that reference part_mesh_manager.WORLD_SCALE
const WORLD_SCALE: float = MechaScaleSystem.WORLD_SCALE
const INV_WORLD_SCALE: float = MechaScaleSystem.INV_WORLD_SCALE

var slot_meshes: Dictionary = {}
# When true, slots without an inner frame render a faint translucent skeleton
# instead of hiding — used by the hangar's from-zero REGISTER assembly so the
# player can see where each missing frame goes. Driven by the garage preview.
var ghost_mode: bool = false
# Cached ghost material: ghost frames rebuild constantly during an assembly.
var _ghost_mat: StandardMaterial3D = null

# Shared base materials (class-wide cache). Every mech build — player, allies
# AND every enemy spawn — used to news up ~30 ShaderMaterials per mech
# (2 armor + 3 frame per slot x 6 slots), stalling combat entry and every
# reinforcement wave. The base materials are never mutated after creation
# (damage cracks use separate material_overlay slots, the realistic-fix pass
# skips ShaderMaterials), so sharing them across all meshes/mechs is safe and
# also cuts draw-state changes. Armor paint varies by color -> keyed by html.
static var _shared_armor_mats: Dictionary = {}
static var _shared_dark_trim_mat: ShaderMaterial = null
static var _shared_frame_mat: ShaderMaterial = null
static var _shared_chrome_mat: ShaderMaterial = null
static var _shared_eye_mat: ShaderMaterial = null
static var _shared_holo_mat: StandardMaterial3D = null
static var _shared_pilot_mat: StandardMaterial3D = null
static var _shared_visor_mat: StandardMaterial3D = null

## Cockpit Tub & Sliding Carriage state
const COCKPIT_BLENDER_GLB := "res://assets/models/mech_cockpit_tub.glb"
## Hybrid Blender/procedural switch. true = use Blender .glb/.tscn when the
## ArmorPart assigns mesh_scene/inner_frame_scene, otherwise fall back to the
## procedural builders. false = force procedural for every slot (debug/art check).
@export var use_blender_models: bool = true
var is_cockpit_open: bool = false
var is_cockpit_pilot_seated: bool = false
var _cockpit_tween: Tween = null


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
	if entry.get("armor_foot") and entry["armor_foot"]: entry["armor_foot"].visible = false
	if entry["frame"]: entry["frame"].visible = false
	if entry.get("frame_lower") and entry["frame_lower"]: entry["frame_lower"].visible = false
	if entry.get("frame_foot") and entry["frame_foot"]: entry["frame_foot"].visible = false


## Toggles cockpit hatch extension. When open, front carriage slides forward-down along guide rails.
func set_cockpit_open(open: bool, animate: bool = true) -> void:
	is_cockpit_open = open
	var target_pos := Vector3(0.0, -0.22, -0.44) if open else Vector3.ZERO
	var target_rot := Vector3(10.0, 0.0, 0.0) if open else Vector3.ZERO

	var carriages: Array[Node3D] = []
	var body_entry = slot_meshes.get("body")
	if body_entry:
		if body_entry.get("frame") and is_instance_valid(body_entry["frame"]):
			var c = body_entry["frame"].get_node_or_null("SlidingCarriage")
			if c is Node3D:
				carriages.append(c)
		if body_entry.get("armor") and is_instance_valid(body_entry["armor"]):
			var c = body_entry["armor"].get_node_or_null("SlidingCarriage")
			if c is Node3D:
				carriages.append(c)

	if carriages.is_empty():
		return

	if AudioManager and AudioManager.has_method("play_hatch_open"):
		var sfx_pos := Vector3.ZERO
		if is_instance_valid(carriages[0]) and carriages[0].is_inside_tree():
			sfx_pos = carriages[0].global_position
		if open:
			AudioManager.play_hatch_open(sfx_pos)
		else:
			AudioManager.play_hatch_close(sfx_pos)

	if _cockpit_tween and _cockpit_tween.is_valid():
		_cockpit_tween.kill()

	if not animate or not is_inside_tree():
		for c in carriages:
			c.position = target_pos
			c.rotation_degrees = target_rot
		_update_hatch_pistons()
		return

	_cockpit_tween = create_tween()
	_cockpit_tween.set_parallel(true)
	var duration := 0.75
	var trans := Tween.TRANS_CUBIC
	var ease := Tween.EASE_OUT if open else Tween.EASE_IN_OUT

	for c in carriages:
		_cockpit_tween.tween_property(c, "position", target_pos, duration).set_trans(trans).set_ease(ease)
		_cockpit_tween.tween_property(c, "rotation_degrees", target_rot, duration).set_trans(trans).set_ease(ease)

	_cockpit_tween.tween_method(func(_v: float): _update_hatch_pistons(), 0.0, 1.0, duration)


## Dynamically tracks and rotates the hatch hydraulic cylinders on the tub and piston rods on the carriage
## so that as the hatch opens and drops, the pistons realistically tilt and extend between their clevis pivots.
func _update_hatch_pistons() -> void:
	var body_entry = slot_meshes.get("body")
	if not body_entry or not body_entry.get("frame") or not is_instance_valid(body_entry["frame"]):
		return
	var frame_mesh: Node3D = body_entry["frame"]
	var tub = frame_mesh.get_node_or_null("CockpitTub")
	var carriage = frame_mesh.get_node_or_null("SlidingCarriage")
	if not tub or not carriage:
		return

	for side in ["L", "R"]:
		var piv_tub = tub.find_child("HatchPivotTub_" + side, true, false) as Node3D
		var piv_car = carriage.find_child("HatchPivotCarriage_" + side, true, false) as Node3D
		if piv_tub and piv_car and piv_tub.is_inside_tree() and piv_car.is_inside_tree():
			var g_tub: Vector3 = piv_tub.global_position
			var g_car: Vector3 = piv_car.global_position
			if g_tub.distance_squared_to(g_car) > 0.001:
				piv_tub.look_at(g_car, Vector3.UP)
				piv_car.look_at(g_tub, Vector3.UP)
				piv_car.rotate_object_local(Vector3.UP, PI)


## Sets whether the pilot mannequin inside the cockpit tub is visible.
func set_cockpit_pilot_seated(seated: bool) -> void:
	is_cockpit_pilot_seated = seated
	var body_entry = slot_meshes.get("body")
	if body_entry and body_entry.get("frame") and is_instance_valid(body_entry["frame"]):
		var pilot = body_entry["frame"].get_node_or_null("CockpitTub/CockpitPilot")
		if pilot is Node3D:
			pilot.visible = seated


## Synchronizes newly rebuilt slot meshes with current cockpit open/seated state.
func _sync_cockpit_state() -> void:
	var target_pos := Vector3(0.0, -0.22, -0.44) if is_cockpit_open else Vector3.ZERO
	var target_rot := Vector3(10.0, 0.0, 0.0) if is_cockpit_open else Vector3.ZERO
	var body_entry = slot_meshes.get("body")
	if body_entry:
		if body_entry.get("frame") and is_instance_valid(body_entry["frame"]):
			var c = body_entry["frame"].get_node_or_null("SlidingCarriage")
			if c is Node3D:
				c.position = target_pos
				c.rotation_degrees = target_rot
			var pilot = body_entry["frame"].get_node_or_null("CockpitTub/CockpitPilot")
			if pilot is Node3D:
				pilot.visible = is_cockpit_pilot_seated
		if body_entry.get("armor") and is_instance_valid(body_entry["armor"]):
			var c = body_entry["armor"].get_node_or_null("SlidingCarriage")
			if c is Node3D:
				c.position = target_pos
				c.rotation_degrees = target_rot
	_update_hatch_pistons()


func initialize_slot(slot_name: String, part: ArmorPart, apply_player_damage: bool = true, frame_data: Variant = null) -> void:
	var parent_node = _get_slot_parent_node(slot_name)
	if parent_node == null:
		return

	var lower_parent_node = _get_slot_lower_parent_node(slot_name)
	var foot_parent_node = _get_slot_foot_parent_node(slot_name)

	# Hide legacy placeholder primitives in mecha_base.tscn
	_hide_legacy_slot_meshes(parent_node)
	if lower_parent_node:
		_hide_legacy_slot_meshes(lower_parent_node)
	if foot_parent_node:
		_hide_legacy_slot_meshes(foot_parent_node)

	# 1. Setup Frame & Armor containers for Upper Joint (Shoulder / Hip)
	# Scale 1.0 world: containers scaled to WORLD_SCALE so procedural meshes (authored at 1.6) render at true 4.73m
	var frame_mesh = parent_node.get_node_or_null("FrameMesh")
	if frame_mesh == null:
		frame_mesh = Node3D.new()
		frame_mesh.name = "FrameMesh"
		frame_mesh.scale = Vector3.ONE * WORLD_SCALE
		parent_node.add_child(frame_mesh)
	else:
		frame_mesh.scale = Vector3.ONE * WORLD_SCALE

	var armor_mesh = parent_node.get_node_or_null("ArmorMesh")
	if armor_mesh == null:
		armor_mesh = Node3D.new()
		armor_mesh.name = "ArmorMesh"
		armor_mesh.scale = Vector3.ONE * WORLD_SCALE
		parent_node.add_child(armor_mesh)
	else:
		armor_mesh.scale = Vector3.ONE * WORLD_SCALE

	# 2. Setup Frame & Armor containers for Lower Joint (Elbow / Knee)
	var frame_mesh_lower: Node3D = null
	var armor_mesh_lower: Node3D = null
	if lower_parent_node:
		frame_mesh_lower = lower_parent_node.get_node_or_null("FrameMesh")
		if frame_mesh_lower == null:
			frame_mesh_lower = Node3D.new()
			frame_mesh_lower.name = "FrameMesh"
			frame_mesh_lower.scale = Vector3.ONE * WORLD_SCALE
			lower_parent_node.add_child(frame_mesh_lower)
		else:
			frame_mesh_lower.scale = Vector3.ONE * WORLD_SCALE

		armor_mesh_lower = lower_parent_node.get_node_or_null("ArmorMesh")
		if armor_mesh_lower == null:
			armor_mesh_lower = Node3D.new()
			armor_mesh_lower.name = "ArmorMesh"
			armor_mesh_lower.scale = Vector3.ONE * WORLD_SCALE
			lower_parent_node.add_child(armor_mesh_lower)
		else:
			armor_mesh_lower.scale = Vector3.ONE * WORLD_SCALE

	# 2b. Setup Frame & Armor containers for the Ankle/Foot Joint.
	# The foot is a separate movable part from the lower leg so FootIK can
	# pivot it at the ankle independently of the shin.
	var frame_mesh_foot: Node3D = null
	var armor_mesh_foot: Node3D = null
	if foot_parent_node:
		frame_mesh_foot = foot_parent_node.get_node_or_null("FrameMesh")
		if frame_mesh_foot == null:
			frame_mesh_foot = Node3D.new()
			frame_mesh_foot.name = "FrameMesh"
			frame_mesh_foot.scale = Vector3.ONE * WORLD_SCALE
			foot_parent_node.add_child(frame_mesh_foot)
		else:
			frame_mesh_foot.scale = Vector3.ONE * WORLD_SCALE

		armor_mesh_foot = foot_parent_node.get_node_or_null("ArmorMesh")
		if armor_mesh_foot == null:
			armor_mesh_foot = Node3D.new()
			armor_mesh_foot.name = "ArmorMesh"
			armor_mesh_foot.scale = Vector3.ONE * WORLD_SCALE
			foot_parent_node.add_child(armor_mesh_foot)
		else:
			armor_mesh_foot.scale = Vector3.ONE * WORLD_SCALE

	slot_meshes[slot_name] = {
		"armor": armor_mesh,
		"frame": frame_mesh,
		"armor_lower": armor_mesh_lower,
		"frame_lower": frame_mesh_lower,
		"armor_foot": armor_mesh_foot,
		"frame_foot": frame_mesh_foot
	}

	# 3. Build Inner Frame (Upper + Lower + Foot articulated segments)
	# Hybrid Blender/procedural: try Blender model first, fall back to
	# procedural when no model is assigned, the scene is missing/corrupt,
	# or the instance contains no renderable meshes.
	_clear_children(frame_mesh)
	if frame_mesh_lower: _clear_children(frame_mesh_lower)
	if frame_mesh_foot: _clear_children(frame_mesh_foot)

	var frame_ok := false
	if use_blender_models and part and (part.inner_frame_scene != null or part.inner_frame_scene_lower != null):
		frame_ok = _attach_custom_mesh_scene(frame_mesh, frame_mesh_lower, part.inner_frame_scene, part.inner_frame_scene_lower, frame_mesh_foot)
	if not frame_ok:
		# Ensure a failed Blender attach leaves no half-built nodes behind.
		_clear_children(frame_mesh)
		if frame_mesh_lower: _clear_children(frame_mesh_lower)
		if frame_mesh_foot: _clear_children(frame_mesh_foot)
		_build_procedural_inner_frame(slot_name, frame_mesh, frame_mesh_lower, frame_data, frame_mesh_foot)
	frame_mesh.visible = true
	if frame_mesh_lower: frame_mesh_lower.visible = true
	if frame_mesh_foot: frame_mesh_foot.visible = true

	# 4. Build Outer Armor Plate (Upper + Lower + Foot articulated armor sleeves)
	_clear_children(armor_mesh)
	if armor_mesh_lower: _clear_children(armor_mesh_lower)
	if armor_mesh_foot: _clear_children(armor_mesh_foot)

	if part != null:
		var armor_ok := false
		if use_blender_models and (part.mesh_scene != null or part.mesh_scene_lower != null):
			armor_ok = _attach_custom_mesh_scene(armor_mesh, armor_mesh_lower, part.mesh_scene, part.mesh_scene_lower, armor_mesh_foot)
		if not armor_ok:
			_clear_children(armor_mesh)
			if armor_mesh_lower: _clear_children(armor_mesh_lower)
			if armor_mesh_foot: _clear_children(armor_mesh_foot)
			_build_procedural_outer_armor(slot_name, armor_mesh, armor_mesh_lower, part, armor_mesh_foot)

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
			if armor_mesh_foot: armor_mesh_foot.visible = true
	else:
		armor_mesh.visible = false
		if armor_mesh_lower: armor_mesh_lower.visible = false
		if armor_mesh_foot: armor_mesh_foot.visible = false

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
				if armor_mesh_foot:
					dmg_vis.register_slot_container(slot_name, armor_mesh_foot, "armor")
				if frame_mesh:
					dmg_vis.register_slot_container(slot_name, frame_mesh, "frame")
				if frame_mesh_lower:
					dmg_vis.register_slot_container(slot_name, frame_mesh_lower, "frame")
				if frame_mesh_foot:
					dmg_vis.register_slot_container(slot_name, frame_mesh_foot, "frame")
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

	if slot_name.to_lower() == "body":
		_sync_cockpit_state()


func _normalize_mesh_orientation(node: Node3D) -> void:
	if node == null:
		return
	if node.has_meta("orientation_y_deg"):
		node.rotation_degrees.y += float(node.get_meta("orientation_y_deg"))
	elif node.has_meta("invert_forward") and bool(node.get_meta("invert_forward")):
		node.rotation_degrees.y += 180.0


# Attaches a Blender-authored scene (or pair) into the slot containers.
# Returns true only when at least one renderable mesh landed in a container.
# Any failure (null scene, broken instance, no meshes) returns false so the
# caller can fall back to the procedural builders — the mech never renders
# an empty slot just because a .glb/.tscn is missing.
func _attach_custom_mesh_scene(upper_container: Node3D, lower_container: Node3D, upper_scene: PackedScene, lower_scene: PackedScene, foot_container: Node3D = null) -> bool:
	if upper_container == null:
		return false
	if upper_scene == null and lower_scene == null:
		return false

	# Explicit lower scene specified - counter-scale so authoring at true meters (scale 1.0) renders correct in WORLD_SCALE container
	if lower_scene != null and lower_container != null:
		var attached_any := false
		if upper_scene != null:
			var up_inst := _try_safe_instantiate(upper_scene)
			if up_inst != null:
				up_inst.scale *= INV_WORLD_SCALE
				_normalize_mesh_orientation(up_inst)
				upper_container.add_child(up_inst)
				_apply_realistic_fix_recursive(up_inst)
				attached_any = true
		var low_inst := _try_safe_instantiate(lower_scene)
		if low_inst != null:
			low_inst.scale *= INV_WORLD_SCALE
			_normalize_mesh_orientation(low_inst)
			lower_container.add_child(low_inst)
			_apply_realistic_fix_recursive(low_inst)
			attached_any = true
		if not attached_any:
			return false
		return _container_has_meshes(upper_container) or (lower_container != null and _container_has_meshes(lower_container)) or (foot_container != null and _container_has_meshes(foot_container))

	# Single scene provided -> auto-split if lower nodes exist
	if upper_scene != null:
		var instance := _try_safe_instantiate(upper_scene)
		if instance == null:
			return false
		instance.scale *= INV_WORLD_SCALE
		_normalize_mesh_orientation(instance)
		if lower_container != null:
			var lower_nodes: Array[Node] = []
			var foot_nodes: Array[Node] = []
			for child in instance.get_children():
				var cname := child.name.to_lower()
				# Foot/ankle/toe nodes belong on the dedicated ankle pivot so
				# the foot stays independently transformable from the shin.
				if foot_container != null and (cname.contains("foot") or cname.contains("ankle") or cname.contains("toe")):
					foot_nodes.append(child)
				elif cname.contains("lower") or cname.contains("forearm") or cname.contains("shin") or cname.contains("knee") or cname.contains("calf"):
					lower_nodes.append(child)

			if not lower_nodes.is_empty():
				for lnode in lower_nodes:
					instance.remove_child(lnode)
					# lnode already part of instance's scaled hierarchy; when moved to WORLD_SCALE container, keep counter-scale
					# Instance root was INV, so lnode world is already correct via container; no extra scale needed as it inherits from new container
					# But if lnode itself has no extra scale, its world via lower_container (1.68) * INV (0.595) =1.0, same as instance root. Since we already scaled instance root, child inherits that INV, moving it without adjusting keeps INV.
					# To keep consistent, ensure lnode scale remains as is (inherits INV from instance root via its own transform, but after reparent, it loses that). So we re-apply INV.
					if lnode is Node3D:
						var ln3d := lnode as Node3D
						# Compensate: instance root INV no longer affects it, so apply INV directly
						ln3d.scale *= INV_WORLD_SCALE
						_normalize_mesh_orientation(ln3d)
					lower_container.add_child(lnode)
					_apply_realistic_fix_recursive(lnode)
			if not foot_nodes.is_empty():
				for fnode in foot_nodes:
					instance.remove_child(fnode)
					if fnode is Node3D:
						var fn3d := fnode as Node3D
						fn3d.scale *= INV_WORLD_SCALE
						_normalize_mesh_orientation(fn3d)
					foot_container.add_child(fnode)
					_apply_realistic_fix_recursive(fnode)

		upper_container.add_child(instance)
		_apply_realistic_fix_recursive(instance)
		if _container_has_meshes(upper_container):
			return true
		if lower_container != null and _container_has_meshes(lower_container):
			return true
		if foot_container != null and _container_has_meshes(foot_container):
			return true
		# Instance added but contains no meshes (e.g. empty wrapper) — let the
		# caller clean up and fall back to procedural.
		return false
	return false


# Safe PackedScene instantiate: returns the Node3D root or null. A broken
# .tscn/.glb (missing ext_resource, script error) must never crash slot build.
func _try_safe_instantiate(scene: PackedScene) -> Node3D:
	if scene == null:
		return null
	if not scene.can_instantiate():
		push_warning("[PartMeshManager] Blender scene cannot instantiate, falling back to procedural.")
		return null
	var inst := scene.instantiate()
	if inst == null or not (inst is Node3D):
		if is_instance_valid(inst) and not (inst is Node3D):
			inst.queue_free()
		push_warning("[PartMeshManager] Blender scene root is not Node3D, falling back to procedural.")
		return null
	return inst as Node3D


# True when the container (or any descendant) holds a MeshInstance3D with a mesh.
func _container_has_meshes(container: Node) -> bool:
	if container == null:
		return false
	for child in container.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			return true
		if _container_has_meshes(child):
			return true
	return false


func _hide_legacy_slot_meshes(parent_node: Node3D) -> void:
	if not parent_node: return
	for child in parent_node.get_children():
		if child.name != "FrameMesh" and child.name != "ArmorMesh" \
			and child.name != "ForearmLeft" and child.name != "ForearmRight" \
			and child.name != "ShinLeft" and child.name != "ShinRight" \
			and child.name != "FootLeft" and child.name != "FootRight" \
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
		initialize_slot(slot, null, apply_player_scrap, frame_data)
		_show_inner_frame(slot)
		_render_scrap_patch(slot)
	elif not is_armor_equipped:
		# INNER FRAME EQUIPPED, NO ARMOR: Render bare skeletal inner frame only
		initialize_slot(slot, null, apply_player_scrap, frame_data)
		_show_inner_frame(slot)
	else:
		# INNER FRAME + OUTER ARMOR EQUIPPED: Render armor over inner frame
		initialize_slot(slot, build_part_for_slot(equipped), apply_player_scrap, frame_data)


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
			container.scale = Vector3.ONE * WORLD_SCALE
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
			scrap_mat.set_shader_parameter("metalness", 0.22)
			scrap_mat.set_shader_parameter("roughness_base", 0.68)
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

# Dedicated ankle/foot pivots (THIGH > KNEE > SHIN > ANKLE > FOOT). The foot is
# a separate movable part from the lower leg: FootLeft/FootRight hang off the
# Shin nodes at ankle height so FootIK can rotate them independently.
const _FOOT_NODE_NAMES: Dictionary = {
	"leg_left": "LegLeft/ShinLeft/FootLeft",
	"leg_right": "LegRight/ShinRight/FootRight",
}


func _get_slot_lower_parent_node(slot_name: String) -> Node3D:
	var mecha = get_parent()
	if not mecha:
		return null
	var path: String = _LOWER_NODE_NAMES.get(slot_name.to_lower(), "")
	if path == "":
		return null
	return mecha.get_node_or_null(path)


# Returns the ankle/foot pivot node for leg slots (null for all other slots).
# Auto-creates the Foot node under the Shin when the base scene predates it
# (older instances / enemy dummies built before the ankle joint existed).
func _get_slot_foot_parent_node(slot_name: String) -> Node3D:
	var mecha = get_parent()
	if not mecha:
		return null
	var path: String = _FOOT_NODE_NAMES.get(slot_name.to_lower(), "")
	if path == "":
		return null
	var foot: Node3D = mecha.get_node_or_null(path) as Node3D
	if foot == null:
		var shin := _get_slot_lower_parent_node(slot_name)
		if shin == null:
			return null
		foot = Node3D.new()
		foot.name = "FootLeft" if slot_name.to_lower() == "leg_left" else "FootRight"
		# Ankle height in Shin-local space: the old ankle actuator sat at
		# container-local -0.53 inside the WORLD_SCALE (1.68) container, so the
		# pivot sits at -0.53 * WORLD_SCALE to keep world placement identical.
		foot.position = Vector3(0, -0.53 * WORLD_SCALE, 0)
		shin.add_child(foot)
	return foot


func _clear_children(node: Node) -> void:
	if not node: return
	for child in node.get_children():
		node.remove_child(child)
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
	if entry.get("armor_foot") and entry["armor_foot"]: entry["armor_foot"].visible = false
	if entry["frame"]: entry["frame"].visible = true
	if entry.get("frame_lower") and entry["frame_lower"]: entry["frame_lower"].visible = true
	if entry.get("frame_foot") and entry["frame_foot"]: entry["frame_foot"].visible = true


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
	for container in [entry["frame"], entry.get("frame_lower"), entry.get("frame_foot")]:
		if container != null:
			_apply_material_recursive(container, ghost_mat)


func _apply_material_recursive(node: Node, mat: Material) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			child.material_override = mat
		_apply_material_recursive(child, mat)


# ---------------------------------------------------------------------------
# IMPORTED GLB REALISTIC FIX - makes shiny imported models look painted/matte
# Any MeshInstance3D from .glb that still uses default StandardMaterial3D with
# low roughness / high metallic gets clamped to realistic painted values.
# If the model already uses mecha_master_pbr shader, it is left untouched.
# ---------------------------------------------------------------------------
func _apply_realistic_fix_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		# Check material_override first, then mesh surface materials
		if mi.material_override != null:
			_fix_material_if_needed(mi.material_override)
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var surf_mat = mi.mesh.surface_get_material(i)
				if surf_mat != null:
					_fix_material_if_needed(surf_mat)
				# Also check per-instance surface override
				var override = mi.get_surface_override_material(i)
				if override != null:
					_fix_material_if_needed(override)
		# Also scan child GeometryInstance3D that may hold own overrides
	for child in node.get_children():
		_apply_realistic_fix_recursive(child)


func _fix_material_if_needed(mat: Material) -> void:
	# Skip already realistic shader materials (master PBR / scrap / cloth)
	if mat is ShaderMaterial:
		return
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		# Heuristic: if material is overly shiny (metallic > 0.4 or roughness < 0.45)
		# clamp it to painted armor look. Don't touch emissive / transparent mats.
		if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return
		var needs_fix := false
		if sm.metallic > 0.45:
			sm.metallic = 0.08
			needs_fix = true
		elif sm.metallic > 0.25:
			sm.metallic = 0.12
			needs_fix = true
		if sm.roughness < 0.45:
			sm.roughness = 0.68
			needs_fix = true
		elif sm.roughness < 0.58:
			sm.roughness = 0.65
			needs_fix = true
		# Also ensure specular isn't too high (paint F0)
		if sm.metallic < 0.2 and needs_fix:
			sm.metallic_specular = 0.35
		# Poly Haven realistic PBR metal textures for imported .glb mechs (PBR maps).
		# Only when the model brings no texture of its own, triplanar-mapped so it
		# works regardless of the model's UVs. Skips emissive mats (sensors/glow).
		if sm.albedo_texture == null and not sm.emission_enabled:
			var pbr_diff := "res://resources/textures/mech/pbr/metal_plate_diff.png"
			var pbr_nor := "res://resources/textures/mech/pbr/metal_plate_nor_gl.png"
			var pbr_rough := "res://resources/textures/mech/pbr/metal_plate_rough.png"
			var pbr_ao := "res://resources/textures/mech/pbr/metal_plate_ao.png"
			if ResourceLoader.exists(pbr_diff):
				sm.albedo_texture = load(pbr_diff)
				sm.normal_enabled = true
				sm.normal_texture = load(pbr_nor)
				sm.roughness_texture = load(pbr_rough)
				sm.ao_enabled = true
				sm.ao_texture = load(pbr_ao)
				sm.uv1_triplanar = true
				sm.uv1_scale = Vector3(1.2, 1.2, 1.2)


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
		mat.metallic = 0.15
		mat.roughness = 0.72
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
		var debris_id_cb := debris.get_instance_id()
		tween.tween_callback(func():
			var d = instance_from_id(debris_id_cb)
			if is_instance_valid(d):
				d.queue_free()
		)
		# Safety hard-free if tween was killed early (scene change)
		var debris_id_fallback := debris.get_instance_id()
		get_tree().create_timer(4.0).timeout.connect(func():
			var d2 = instance_from_id(debris_id_fallback)
			if is_instance_valid(d2):
				d2.queue_free()
		, CONNECT_ONE_SHOT)
		
	var vfx_scene = load("res://scenes/mecha/effects/vfx_armor_break.tscn")
	if vfx_scene and entry["armor"] and entry["armor"].is_inside_tree():
		var vfx = vfx_scene.instantiate()
		entry["armor"].get_parent().add_child(vfx)
		vfx.global_position = entry["armor"].global_position


# Helper materials for inner frame & armor - REALISTIC PBR VALUES
# Painted surfaces are dielectric (metallic ~0), brushed metal is ~0.7-0.85, chrome is refined but not mirror
# All shared class-wide (see _shared_* cache): identical params, never mutated.
func _get_dark_frame_material() -> ShaderMaterial:
	if _shared_frame_mat == null or not is_instance_valid(_shared_frame_mat):
		var mat = ShaderMaterial.new()
		mat.shader = MASTER_PBR_SHADER
		mat.set_shader_parameter("primary_color", Color(0.14, 0.16, 0.20))
		mat.set_shader_parameter("metallic", 0.35)
		mat.set_shader_parameter("roughness", 0.62)
		mat.set_shader_parameter("panel_grid_scale", 0.0)
		mat.set_shader_parameter("edge_wear", 0.12)
		mat.set_shader_parameter("rim_strength", 0.05)
		_apply_polyhaven_pbr(mat, 2.0, 0.6)
		_shared_frame_mat = mat
	return _shared_frame_mat

func _get_chrome_material() -> ShaderMaterial:
	if _shared_chrome_mat == null or not is_instance_valid(_shared_chrome_mat):
		var mat = ShaderMaterial.new()
		mat.shader = MASTER_PBR_SHADER
		mat.set_shader_parameter("primary_color", Color(0.72, 0.74, 0.78))
		mat.set_shader_parameter("metallic", 0.88)
		mat.set_shader_parameter("roughness", 0.32)
		mat.set_shader_parameter("panel_grid_scale", 0.0)
		mat.set_shader_parameter("edge_wear", 0.04)
		mat.set_shader_parameter("rim_strength", 0.06)
		_shared_chrome_mat = mat
	return _shared_chrome_mat

func _get_eye_sensor_material() -> ShaderMaterial:
	if _shared_eye_mat == null or not is_instance_valid(_shared_eye_mat):
		var mat = ShaderMaterial.new()
		mat.shader = MASTER_PBR_SHADER
		mat.set_shader_parameter("primary_color", Color(1.0, 0.12, 0.20))
		mat.set_shader_parameter("emission_color", Color(1.0, 0.15, 0.25))
		mat.set_shader_parameter("emission_energy", 5.0)
		mat.set_shader_parameter("pulse_speed", 2.0)
		_shared_eye_mat = mat
	return _shared_eye_mat

# Shared outer-armor materials. armor_mat varies only by paint color, so it is
# cached per color-html; dark trim is a constant single shared instance.
func _get_shared_armor_mat(col: Color) -> ShaderMaterial:
	var key := col.to_html()
	if _shared_armor_mats.has(key):
		var cached: ShaderMaterial = _shared_armor_mats[key]
		if is_instance_valid(cached):
			return cached
	# Realistic painted armor: metallic ~0.08 (paint over primer), roughness ~0.65-0.72 matte
	var armor_mat = ShaderMaterial.new()
	armor_mat.shader = MASTER_PBR_SHADER
	armor_mat.render_priority = 1
	armor_mat.set_shader_parameter("primary_color", col)
	armor_mat.set_shader_parameter("trim_color", Color(0.12, 0.14, 0.18))
	armor_mat.set_shader_parameter("metallic", 0.08)
	armor_mat.set_shader_parameter("roughness", 0.68)
	armor_mat.set_shader_parameter("panel_grid_scale", 0.0)
	armor_mat.set_shader_parameter("edge_wear", 0.10)
	armor_mat.set_shader_parameter("rim_strength", 0.06)
	_apply_polyhaven_pbr(armor_mat, 1.2, 0.8)
	_apply_comfy_armor_detail(armor_mat)
	_shared_armor_mats[key] = armor_mat
	return armor_mat

func _get_shared_dark_trim_mat() -> ShaderMaterial:
	if _shared_dark_trim_mat == null or not is_instance_valid(_shared_dark_trim_mat):
		var dark_trim_mat = ShaderMaterial.new()
		dark_trim_mat.shader = MASTER_PBR_SHADER
		dark_trim_mat.render_priority = 1
		dark_trim_mat.set_shader_parameter("primary_color", Color(0.12, 0.14, 0.18))
		dark_trim_mat.set_shader_parameter("trim_color", Color(0.08, 0.09, 0.11))
		dark_trim_mat.set_shader_parameter("metallic", 0.12)
		dark_trim_mat.set_shader_parameter("roughness", 0.72)
		dark_trim_mat.set_shader_parameter("panel_grid_scale", 0.0)
		dark_trim_mat.set_shader_parameter("edge_wear", 0.12)
		dark_trim_mat.set_shader_parameter("rim_strength", 0.05)
		_apply_polyhaven_pbr(dark_trim_mat, 1.5, 0.9)
		_apply_comfy_armor_detail(dark_trim_mat)
		_shared_dark_trim_mat = dark_trim_mat
	return _shared_dark_trim_mat

# Poly Haven realistic PBR metal textures
const PBR_METAL_DIFFUSE := "res://resources/textures/mech/pbr/metal_plate_diff.png"
const PBR_METAL_NORMAL := "res://resources/textures/mech/pbr/metal_plate_nor_gl.png"
const PBR_METAL_ROUGH := "res://resources/textures/mech/pbr/metal_plate_rough.png"
const PBR_METAL_AO := "res://resources/textures/mech/pbr/metal_plate_ao.png"

func _apply_polyhaven_pbr(mat: ShaderMaterial, uv_scale: float = 1.2, normal_str: float = 0.8) -> void:
	if not ResourceLoader.exists(PBR_METAL_DIFFUSE):
		return
	mat.set_shader_parameter("use_pbr_maps", true)
	mat.set_shader_parameter("use_triplanar", true)
	mat.set_shader_parameter("pbr_uv_scale", uv_scale)
	mat.set_shader_parameter("pbr_albedo", load(PBR_METAL_DIFFUSE))
	mat.set_shader_parameter("pbr_normal", load(PBR_METAL_NORMAL))
	mat.set_shader_parameter("pbr_roughness", load(PBR_METAL_ROUGH))
	mat.set_shader_parameter("pbr_ao", load(PBR_METAL_AO))
	mat.set_shader_parameter("normal_strength", normal_str)


# ComfyUI armor detail overlay (Z-Image-Turbo, neutral mid-gray multiply).
# Bound when the texture exists; otherwise the shader default (off) keeps the
# old look. Shared by every procedural armor/trim material so the whole body
# gets the same worn-metal grain.
const COMFY_ARMOR_DETAIL_TEX := "res://resources/textures/mech/comfy_armor_detail.png"

func _apply_comfy_armor_detail(mat: ShaderMaterial, strength: float = 0.35) -> void:
	if not ResourceLoader.exists(COMFY_ARMOR_DETAIL_TEX):
		return
	mat.set_shader_parameter("has_detail_tex", true)
	mat.set_shader_parameter("detail_tex", load(COMFY_ARMOR_DETAIL_TEX))
	mat.set_shader_parameter("detail_strength", strength)


func _get_shared_holo_mat() -> StandardMaterial3D:
	if _shared_holo_mat == null:
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.12, 0.85, 1.0, 0.55)
		mat.emission_enabled = true
		mat.emission = Color(0.15, 0.90, 1.0)
		mat.emission_energy_multiplier = 2.5
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shared_holo_mat = mat
	return _shared_holo_mat


func _get_shared_pilot_mat() -> StandardMaterial3D:
	if _shared_pilot_mat == null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.18, 0.22, 0.28)
		mat.metallic = 0.1
		mat.roughness = 0.75
		_shared_pilot_mat = mat
	return _shared_pilot_mat


func _get_shared_visor_mat() -> StandardMaterial3D:
	if _shared_visor_mat == null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.75, 0.15)
		mat.metallic = 0.85
		mat.roughness = 0.2
		mat.emission_enabled = true
		mat.emission = Color(0.95, 0.75, 0.15)
		mat.emission_energy_multiplier = 1.2
		_shared_visor_mat = mat
	return _shared_visor_mat


func _create_cockpit_pilot_mannequin() -> Node3D:
	var pilot_mannequin = Node3D.new()
	pilot_mannequin.name = "CockpitPilot"
	var pilot_mat = _get_shared_pilot_mat()
	var visor_mat = _get_shared_visor_mat()

	# Reclined Torso (24° natural mecha combat seating toward +Z)
	var pilot_torso = MeshInstance3D.new()
	var pt_box = BoxMesh.new()
	pt_box.size = Vector3(0.28, 0.42, 0.18)
	pilot_torso.mesh = pt_box
	pilot_torso.rotation_degrees.x = 24.0
	pilot_torso.position = Vector3(0, -0.06, 0.16)
	pilot_torso.material_override = pilot_mat
	pilot_mannequin.add_child(pilot_torso)

	# Head resting on 24° reclined headrest (Z=0.28, Y=0.32)
	var pilot_head = MeshInstance3D.new()
	var ph_sph = SphereMesh.new()
	ph_sph.radius = 0.09
	ph_sph.height = 0.18
	pilot_head.mesh = ph_sph
	pilot_head.rotation_degrees.x = 24.0
	pilot_head.position = Vector3(0, 0.32, 0.28)
	pilot_head.material_override = pilot_mat
	pilot_mannequin.add_child(pilot_head)

	var pilot_visor = MeshInstance3D.new()
	var pv_box = BoxMesh.new()
	pv_box.size = Vector3(0.13, 0.04, 0.06)
	pilot_visor.mesh = pv_box
	pilot_visor.rotation_degrees.x = 24.0
	pilot_visor.position = Vector3(0, 0.32, 0.20)
	pilot_visor.material_override = visor_mat
	pilot_mannequin.add_child(pilot_visor)

	# Arms reaching down-forward to HOTAS sticks, legs dropping into sunken footwell
	for arm_sign in [-1.0, 1.0]:
		var pilot_arm = MeshInstance3D.new()
		var pa_box = BoxMesh.new()
		pa_box.size = Vector3(0.06, 0.06, 0.26)
		pilot_arm.mesh = pa_box
		pilot_arm.position = Vector3(arm_sign * 0.20, -0.08, -0.04)
		pilot_arm.rotation_degrees.x = 18.0
		pilot_arm.material_override = pilot_mat
		pilot_mannequin.add_child(pilot_arm)

		var pilot_leg = MeshInstance3D.new()
		var pl_box = BoxMesh.new()
		pl_box.size = Vector3(0.08, 0.07, 0.38)
		pilot_leg.mesh = pl_box
		pilot_leg.position = Vector3(arm_sign * 0.12, -0.32, -0.24)
		pilot_leg.rotation_degrees.x = -68.0
		pilot_leg.material_override = pilot_mat
		pilot_mannequin.add_child(pilot_leg)
	return pilot_mannequin


# ==============================================================================
# SKELETAL INNER FRAME GENERATOR (UPPER + LOWER JOINT SPLIT)
# ==============================================================================
func _build_procedural_inner_frame(slot_name: String, upper_container: Node3D, lower_container: Node3D = null, frame_data: Variant = null, foot_container: Node3D = null) -> void:
	var frame_mat = _get_dark_frame_material()
	var chrome_mat = _get_chrome_material()
	var eye_mat = _get_eye_sensor_material()

	match slot_name.to_lower():
		"head":
			# Compact Low-Profile Sensor Turret Core (ป้อมปืน/เซนเซอร์เหลี่ยมมุมตัด เตี้ยลู่ลม)
			var skull = MeshInstance3D.new()
			var s_box = BoxMesh.new()
			s_box.size = Vector3(0.20, 0.12, 0.22)
			skull.mesh = s_box
			skull.position = Vector3(0, 0.04, -0.02)
			skull.material_override = frame_mat
			upper_container.add_child(skull)

			# Tactical Sensor Visor / Dual Optical Aperture
			var eye = MeshInstance3D.new()
			var e_box = BoxMesh.new()
			e_box.size = Vector3(0.14, 0.04, 0.04)
			eye.mesh = e_box
			eye.position = Vector3(0, 0.04, -0.13)
			eye.material_override = eye_mat
			upper_container.add_child(eye)

			# Short Chamfered Neck Collar Hub (คอกระบอกสั้นลง เหลี่ยมมุมตัด มีรายละเอียดโครงใน)
			var neck = MeshInstance3D.new()
			var n_box = BoxMesh.new()
			n_box.size = Vector3(0.14, 0.08, 0.14)
			neck.mesh = n_box
			neck.position = Vector3(0, -0.05, 0)
			neck.material_override = chrome_mat
			upper_container.add_child(neck)

			# Neck side mechanical pivot flanges
			for flange_x in [-0.08, 0.08]:
				var flange = MeshInstance3D.new()
				var fl_cyl = CylinderMesh.new()
				fl_cyl.top_radius = 0.025
				fl_cyl.bottom_radius = 0.025
				fl_cyl.height = 0.03
				flange.mesh = fl_cyl
				flange.rotation_degrees.z = 90
				flange.position = Vector3(flange_x, -0.05, 0)
				flange.material_override = frame_mat
				upper_container.add_child(flange)

		"body":
			# --- 1. REAR STRUCTURAL SPINE & WAIST CHASSIS (Stationary) ---
			var spine = MeshInstance3D.new()
			var sp_box = BoxMesh.new()
			sp_box.size = Vector3(0.20, 0.90, 0.18)
			spine.mesh = sp_box
			spine.position = Vector3(0, 0.05, 0.22)
			spine.material_override = frame_mat
			upper_container.add_child(spine)

			# Resolve custom 3D inner frame model if specified for this body frame series
			var frame_model_path: String = ""
			var target_frame = frame_data
			if target_frame == null and GlobalData != null and GlobalData.weapons != null:
				target_frame = GlobalData.weapons.equipped_frames.get("body")
			# If still null/unspecified and in standalone testing, fallback to default standard frame (frame_body_01)
			if target_frame == null and GlobalData != null and GlobalData.frame_catalog.has("body") and not GlobalData.frame_catalog["body"].is_empty():
				target_frame = GlobalData.frame_catalog["body"][0]

			if target_frame is Dictionary:
				frame_model_path = target_frame.get("model_path", "")
				if frame_model_path.is_empty() and target_frame.has("id"):
					var entry = ArmorSystem.get_frame_catalog_entry(target_frame.get("id", ""))
					frame_model_path = entry.get("model_path", "")
			elif target_frame is String and not target_frame.is_empty():
				var entry = ArmorSystem.get_frame_catalog_entry(target_frame)
				frame_model_path = entry.get("model_path", "")

			# --- 2. COCKPIT TUB & SLIDING CARRIAGE (Blender 3D Asset or Procedural Fallback) ---
			var has_waist_core := false
			var blender_cockpit_scene: PackedScene = null
			if not frame_model_path.is_empty() and ResourceLoader.exists(frame_model_path):
				blender_cockpit_scene = load(frame_model_path) as PackedScene
			if blender_cockpit_scene != null:
				var b_inst = blender_cockpit_scene.instantiate()

				# Extract WaistCore (Mailes Kenbu style hemispherical ball joint + hydraulic dampers)
				var b_waist = b_inst.find_child("WaistCore", true, false)
				if b_waist:
					b_waist.get_parent().remove_child(b_waist)
					b_waist.owner = null
					b_waist.name = "WaistCore"
					upper_container.add_child(b_waist)
					has_waist_core = true

				# Extract SlidingCarriage (Kenbu front armor cowl & hatch)
				var b_carriage = b_inst.find_child("SlidingCarriage", true, false)
				if b_carriage:
					b_carriage.get_parent().remove_child(b_carriage)
					b_carriage.owner = null
					b_carriage.name = "SlidingCarriage"
					if is_cockpit_open:
						b_carriage.position = Vector3(0.0, -0.22, -0.44)
						b_carriage.rotation_degrees = Vector3(10.0, 0.0, 0.0)
					else:
						b_carriage.position = Vector3.ZERO
						b_carriage.rotation_degrees = Vector3.ZERO
					upper_container.add_child(b_carriage)

				# Extract CockpitTub (Stationary tub structure)
				var b_tub = b_inst.find_child("CockpitTub", true, false)
				if b_tub:
					b_tub.get_parent().remove_child(b_tub)
					b_tub.owner = null
					b_tub.name = "CockpitTub"
					upper_container.add_child(b_tub)
					b_inst.queue_free()
				else:
					b_inst.name = "CockpitTub"
					upper_container.add_child(b_inst)
					b_tub = b_inst

				# Set holographic display shader material on HUD if present
				var holo = b_tub.find_child("HoloHUD_Display", true, false)
				if holo == null:
					holo = b_tub.find_child("CenterHUD", true, false)
					if holo:
						holo.name = "HoloHUD_Display"
				if holo and holo is MeshInstance3D:
					holo.material_override = _get_shared_holo_mat()

				# Mount seated pilot mannequin into cockpit tub
				var pilot_mannequin = _create_cockpit_pilot_mannequin()
				pilot_mannequin.visible = is_cockpit_pilot_seated
				b_tub.add_child(pilot_mannequin)
			else:
				# --- Procedural Fallback ---
				var cockpit_tub = Node3D.new()
				cockpit_tub.name = "CockpitTub"
				upper_container.add_child(cockpit_tub)

				# Cockpit floor
				var tub_floor = MeshInstance3D.new()
				var tf_box = BoxMesh.new()
				tf_box.size = Vector3(0.48, 0.04, 0.44)
				tub_floor.mesh = tf_box
				tub_floor.position = Vector3(0, -0.08, -0.05)
				tub_floor.material_override = frame_mat
				cockpit_tub.add_child(tub_floor)

				# Cockpit left wall
				var tub_left = MeshInstance3D.new()
				var tl_box = BoxMesh.new()
				tl_box.size = Vector3(0.04, 0.32, 0.44)
				tub_left.mesh = tl_box
				tub_left.position = Vector3(-0.24, 0.08, -0.05)
				tub_left.material_override = frame_mat
				cockpit_tub.add_child(tub_left)

				# Cockpit right wall
				var tub_right = MeshInstance3D.new()
				var tr_box = BoxMesh.new()
				tr_box.size = Vector3(0.04, 0.32, 0.44)
				tub_right.mesh = tr_box
				tub_right.position = Vector3(0.24, 0.08, -0.05)
				tub_right.material_override = frame_mat
				cockpit_tub.add_child(tub_right)

				# Cockpit rear bulkhead / armored seat mount
				var tub_bulkhead = MeshInstance3D.new()
				var tb_box = BoxMesh.new()
				tb_box.size = Vector3(0.48, 0.42, 0.06)
				tub_bulkhead.mesh = tb_box
				tub_bulkhead.position = Vector3(0, 0.13, 0.16)
				tub_bulkhead.material_override = frame_mat
				cockpit_tub.add_child(tub_bulkhead)

				# Left & Right Hydraulic Guide Slide Rails (on top rim of tub walls)
				for rail_sign in [-1.0, 1.0]:
					var rail = MeshInstance3D.new()
					var r_cyl = CylinderMesh.new()
					r_cyl.top_radius = 0.018
					r_cyl.bottom_radius = 0.018
					r_cyl.height = 0.46
					rail.mesh = r_cyl
					rail.rotation_degrees.x = 90.0
					rail.position = Vector3(rail_sign * 0.24, 0.24, -0.05)
					rail.material_override = chrome_mat
					cockpit_tub.add_child(rail)

				# Ergonomic Bucket Seat
				var dark_trim = _get_shared_dark_trim_mat()

				var seat_base = MeshInstance3D.new()
				var sb_box = BoxMesh.new()
				sb_box.size = Vector3(0.26, 0.08, 0.24)
				seat_base.mesh = sb_box
				seat_base.position = Vector3(0, -0.02, 0.04)
				seat_base.material_override = dark_trim
				cockpit_tub.add_child(seat_base)

				var seat_back = MeshInstance3D.new()
				var sbk_box = BoxMesh.new()
				sbk_box.size = Vector3(0.26, 0.32, 0.06)
				seat_back.mesh = sbk_box
				seat_back.rotation_degrees.x = -8.0
				seat_back.position = Vector3(0, 0.18, 0.13)
				seat_back.material_override = dark_trim
				cockpit_tub.add_child(seat_back)

				var headrest = MeshInstance3D.new()
				var hr_box = BoxMesh.new()
				hr_box.size = Vector3(0.18, 0.12, 0.08)
				headrest.mesh = hr_box
				headrest.position = Vector3(0, 0.38, 0.11)
				headrest.material_override = dark_trim
				cockpit_tub.add_child(headrest)

				# Dual Flight Joysticks
				for stick_sign in [-1.0, 1.0]:
					var stick_base = MeshInstance3D.new()
					var stkb_box = BoxMesh.new()
					stkb_box.size = Vector3(0.06, 0.04, 0.06)
					stick_base.mesh = stkb_box
					stick_base.position = Vector3(stick_sign * 0.16, -0.04, -0.08)
					stick_base.material_override = frame_mat
					cockpit_tub.add_child(stick_base)

					var stick = MeshInstance3D.new()
					var st_cyl = CylinderMesh.new()
					st_cyl.top_radius = 0.012
					st_cyl.bottom_radius = 0.012
					st_cyl.height = 0.10
					stick.mesh = st_cyl
					stick.rotation_degrees.x = -15.0
					stick.position = Vector3(stick_sign * 0.16, 0.03, -0.08)
					stick.material_override = chrome_mat
					cockpit_tub.add_child(stick)

				# Forward Dashboard Console & Glowing Holo-HUD Screen
				var console_deck = MeshInstance3D.new()
				var cd_box = BoxMesh.new()
				cd_box.size = Vector3(0.36, 0.05, 0.12)
				console_deck.mesh = cd_box
				console_deck.rotation_degrees.x = -25.0
				console_deck.position = Vector3(0, 0.08, -0.22)
				console_deck.material_override = dark_trim
				cockpit_tub.add_child(console_deck)

				var holo_screen = MeshInstance3D.new()
				holo_screen.name = "HoloHUD_Display"
				var hs_box = BoxMesh.new()
				hs_box.size = Vector3(0.28, 0.14, 0.01)
				holo_screen.mesh = hs_box
				holo_screen.rotation_degrees.x = -15.0
				holo_screen.position = Vector3(0, 0.19, -0.20)
				holo_screen.material_override = _get_shared_holo_mat()
				cockpit_tub.add_child(holo_screen)

				var pilot_mannequin = _create_cockpit_pilot_mannequin()
				pilot_mannequin.visible = is_cockpit_pilot_seated
				cockpit_tub.add_child(pilot_mannequin)

				# --- 3. SLIDING FRONT CARRIAGE (Slides forward and down when cockpit open) ---
				var carriage = Node3D.new()
				carriage.name = "SlidingCarriage"
				if is_cockpit_open:
					carriage.position = Vector3(0.0, -0.22, -0.44)
					carriage.rotation_degrees = Vector3(10.0, 0.0, 0.0)
				upper_container.add_child(carriage)

				# Front Rib Arc
				var rib = MeshInstance3D.new()
				var r_box = BoxMesh.new()
				r_box.size = Vector3(0.54, 0.08, 0.16)
				rib.mesh = r_box
				rib.position = Vector3(0, 0.12, -0.24)
				rib.material_override = frame_mat
				carriage.add_child(rib)

				# Front Chin Frame
				var chin = MeshInstance3D.new()
				var ch_box = BoxMesh.new()
				ch_box.size = Vector3(0.36, 0.10, 0.14)
				chin.mesh = ch_box
				chin.position = Vector3(0, -0.16, -0.22)
				chin.material_override = frame_mat
				carriage.add_child(chin)

				# Hydraulic Slide Runners (telescoping along tub guide rails)
				for side_sign in [-1.0, 1.0]:
					var runner = MeshInstance3D.new()
					var rn_cyl = CylinderMesh.new()
					rn_cyl.top_radius = 0.025
					rn_cyl.bottom_radius = 0.025
					rn_cyl.height = 0.38
					runner.mesh = rn_cyl
					runner.rotation_degrees.x = 90.0
					runner.position = Vector3(side_sign * 0.25, 0.24, -0.08)
					runner.material_override = chrome_mat
					carriage.add_child(runner)

					var clasp = MeshInstance3D.new()
					var cl_box = BoxMesh.new()
					cl_box.size = Vector3(0.04, 0.12, 0.08)
					clasp.mesh = cl_box
					clasp.position = Vector3(side_sign * 0.28, 0.12, -0.18)
					clasp.material_override = chrome_mat
					carriage.add_child(clasp)

			# Shoulder Clavicle Axles & Sockets connecting body to arm shoulder pivots (X = ±0.782, Y = 0.288)
			for side_sign in [-1.0, 1.0]:
				# Horizontal Clavicle Axle Beam from spine out to shoulder
				var clavicle = MeshInstance3D.new()
				var cl_cyl = CylinderMesh.new()
				cl_cyl.top_radius = 0.08
				cl_cyl.bottom_radius = 0.08
				cl_cyl.height = 0.48
				clavicle.mesh = cl_cyl
				clavicle.rotation_degrees.z = 90
				clavicle.position = Vector3(side_sign * 0.54, 0.288, 0)
				clavicle.material_override = chrome_mat
				upper_container.add_child(clavicle)

				# Outer Shoulder Socket Cup that cups the arm shoulder ball
				var socket = MeshInstance3D.new()
				var s_cyl = CylinderMesh.new()
				s_cyl.top_radius = 0.16
				s_cyl.bottom_radius = 0.16
				s_cyl.height = 0.14
				socket.mesh = s_cyl
				socket.rotation_degrees.z = 90
				socket.position = Vector3(side_sign * 0.76, 0.288, 0)
				socket.material_override = frame_mat
				upper_container.add_child(socket)

				# Inner Shoulder Hub
				var inner_hub = MeshInstance3D.new()
				var h_box = BoxMesh.new()
				h_box.size = Vector3(0.24, 0.26, 0.26)
				inner_hub.mesh = h_box
				inner_hub.position = Vector3(side_sign * 0.38, 0.288, 0)
				inner_hub.material_override = frame_mat
				upper_container.add_child(inner_hub)

			if not has_waist_core:
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

			# --- PELVIS / HIP GIRDLE CHASSIS (connects waist directly to leg hip pivots X = ±0.529, Y = -0.518) ---
			# 1. Central Pelvis / Sacrum Core
			# Wanzer rebalance: widened/deepened (Y unchanged) so the pelvis
			# properly connects the fixed torso to the thicker thighs.
			var pelvis = MeshInstance3D.new()
			var p_box = BoxMesh.new()
			p_box.size = Vector3(0.60, 0.22, 0.40)
			pelvis.mesh = p_box
			pelvis.position = Vector3(0, -0.48, 0)
			pelvis.material_override = frame_mat
			upper_container.add_child(pelvis)

			# 2. Transverse Hip Axle Beam bridging from waist to left & right hip joints
			var hip_axle = MeshInstance3D.new()
			var a_cyl = CylinderMesh.new()
			a_cyl.top_radius = 0.13
			a_cyl.bottom_radius = 0.13
			a_cyl.height = 1.10
			hip_axle.mesh = a_cyl
			hip_axle.rotation_degrees.z = 90
			hip_axle.position = Vector3(0, -0.518, 0)
			hip_axle.material_override = chrome_mat
			upper_container.add_child(hip_axle)

			# 3. Left & Right Hip Ball Socket Cups (Enclosing the leg hip spheres!)
			for hip_sign in [-1.0, 1.0]:
				var hip_socket = MeshInstance3D.new()
				var hs_cyl = CylinderMesh.new()
				hs_cyl.top_radius = 0.24
				hs_cyl.bottom_radius = 0.24
				hs_cyl.height = 0.18
				hip_socket.mesh = hs_cyl
				hip_socket.rotation_degrees.z = 90
				hip_socket.position = Vector3(hip_sign * 0.529, -0.518, 0)
				hip_socket.material_override = frame_mat
				upper_container.add_child(hip_socket)

				# Diagonal Hip Hydraulic Brace from pelvis to hip socket
				var brace = MeshInstance3D.new()
				var b_cyl = CylinderMesh.new()
				b_cyl.top_radius = 0.05
				b_cyl.bottom_radius = 0.05
				b_cyl.height = 0.24
				brace.mesh = b_cyl
				brace.rotation_degrees.z = hip_sign * 45.0
				brace.position = Vector3(hip_sign * 0.32, -0.45, 0)
				brace.material_override = chrome_mat
				upper_container.add_child(brace)

			# 4. Front Groin / Crotch Armor Deflector
			var crotch = MeshInstance3D.new()
			var c_box = BoxMesh.new()
			c_box.size = Vector3(0.28, 0.24, 0.20)
			crotch.mesh = c_box
			crotch.position = Vector3(0, -0.52, -0.12)
			crotch.rotation_degrees.x = -15.0
			crotch.material_override = frame_mat
			upper_container.add_child(crotch)

		"arm_left", "arm_right":
			# --- UPPER ARM SEGMENT (Attaches to Shoulder Pivot ArmLeft/ArmRight) ---
			# Wanzer rebalance: width/depth scaled UP to match the fixed torso
			# and the carried weapons. Lengths (Y) are unchanged.
			var shoulder_joint = MeshInstance3D.new()
			var s_sphere = SphereMesh.new()
			s_sphere.radius = 0.23
			s_sphere.height = 0.46
			shoulder_joint.mesh = s_sphere
			shoulder_joint.material_override = frame_mat
			upper_container.add_child(shoulder_joint)

			var shoulder_bolt = MeshInstance3D.new()
			var b_cyl = CylinderMesh.new()
			b_cyl.top_radius = 0.22
			b_cyl.bottom_radius = 0.22
			b_cyl.height = 0.14
			shoulder_bolt.mesh = b_cyl
			shoulder_bolt.rotation_degrees.z = 90
			shoulder_bolt.material_override = chrome_mat
			upper_container.add_child(shoulder_bolt)

			var upper_arm = MeshInstance3D.new()
			var u_box = BoxMesh.new()
			u_box.size = Vector3(0.30, 0.40, 0.30)
			upper_arm.mesh = u_box
			upper_arm.position = Vector3(0, -0.19, 0)
			upper_arm.material_override = frame_mat
			upper_container.add_child(upper_arm)

			# --- LOWER ARM SEGMENT (Attaches to Elbow Pivot ForearmLeft/ForearmRight) ---
			if lower_container:
				var elbow_disc = MeshInstance3D.new()
				var e_cyl = CylinderMesh.new()
				e_cyl.top_radius = 0.16
				e_cyl.bottom_radius = 0.16
				e_cyl.height = 0.18
				elbow_disc.mesh = e_cyl
				elbow_disc.rotation_degrees.z = 90
				elbow_disc.position = Vector3(0, 0, 0)
				elbow_disc.material_override = chrome_mat
				lower_container.add_child(elbow_disc)

				var forearm_frame = MeshInstance3D.new()
				var f_box = BoxMesh.new()
				f_box.size = Vector3(0.32, 0.45, 0.32)
				forearm_frame.mesh = f_box
				forearm_frame.position = Vector3(0, -0.225, 0)
				forearm_frame.material_override = frame_mat
				lower_container.add_child(forearm_frame)

				var hand_block = MeshInstance3D.new()
				var h_box = BoxMesh.new()
				h_box.size = Vector3(0.20, 0.18, 0.22)
				hand_block.mesh = h_box
				hand_block.position = Vector3(0, -0.47, 0)
				hand_block.material_override = chrome_mat
				lower_container.add_child(hand_block)

		"leg_left", "leg_right":
			# --- UPPER LEG SEGMENT (Attaches to Hip Pivot LegLeft/LegRight) ---
			# Wanzer rebalance: width/depth scaled UP for load-bearing mass.
			# Lengths (Y) are unchanged so stride and ground contact are kept.
			var hip_joint = MeshInstance3D.new()
			var h_sphere = SphereMesh.new()
			h_sphere.radius = 0.24
			h_sphere.height = 0.48
			hip_joint.mesh = h_sphere
			hip_joint.material_override = frame_mat
			upper_container.add_child(hip_joint)

			var thigh_frame = MeshInstance3D.new()
			var t_box = BoxMesh.new()
			t_box.size = Vector3(0.36, 0.44, 0.38)
			thigh_frame.mesh = t_box
			thigh_frame.position = Vector3(0, -0.275, 0)
			thigh_frame.material_override = frame_mat
			upper_container.add_child(thigh_frame)

			# Twin hydraulic struts on thigh back
			for strut_x in [-0.09, 0.09]:
				var t_strut = MeshInstance3D.new()
				var ts_cyl = CylinderMesh.new()
				ts_cyl.top_radius = 0.028
				ts_cyl.bottom_radius = 0.028
				ts_cyl.height = 0.36
				t_strut.mesh = ts_cyl
				t_strut.position = Vector3(strut_x, -0.275, 0.15)
				t_strut.material_override = chrome_mat
				upper_container.add_child(t_strut)

			# --- LOWER LEG SEGMENT (Attaches to Knee Pivot ShinLeft/ShinRight) ---
			if lower_container:
				# Heavy rotary actuator knee disc
				var knee_disc = MeshInstance3D.new()
				var k_cyl = CylinderMesh.new()
				k_cyl.top_radius = 0.19
				k_cyl.bottom_radius = 0.19
				k_cyl.height = 0.20
				knee_disc.mesh = k_cyl
				knee_disc.rotation_degrees.z = 90
				knee_disc.position = Vector3(0, 0, 0)
				knee_disc.material_override = chrome_mat
				lower_container.add_child(knee_disc)

				var shin_frame = MeshInstance3D.new()
				var s_box = BoxMesh.new()
				s_box.size = Vector3(0.36, 0.44, 0.36)
				shin_frame.mesh = s_box
				shin_frame.position = Vector3(0, -0.275, 0)
				shin_frame.material_override = frame_mat
				lower_container.add_child(shin_frame)

				# Dual shock-absorber dampers behind shin
				for damper_x in [-0.09, 0.09]:
					var damper = MeshInstance3D.new()
					var d_cyl = CylinderMesh.new()
					d_cyl.top_radius = 0.028
					d_cyl.bottom_radius = 0.028
					d_cyl.height = 0.40
					damper.mesh = d_cyl
					damper.position = Vector3(damper_x, -0.275, 0.15)
					damper.material_override = chrome_mat
					lower_container.add_child(damper)

			# --- ANKLE + FOOT (separate movable part on the Foot pivot) ---
			# Foot meshes live in foot_container (child of the Foot node at
			# ankle height) so the foot pivots independently of the shin.
			# Positions below are Foot-local (ankle = origin).
			var foot_parent := foot_container if foot_container != null else lower_container
			var foot_y_off := -0.53 if foot_container != null else 0.0
			if foot_parent:
				var ankle = MeshInstance3D.new()
				ankle.name = "AnkleJoint"
				var a_cyl = CylinderMesh.new()
				a_cyl.top_radius = 0.15
				a_cyl.bottom_radius = 0.15
				a_cyl.height = 0.14
				ankle.mesh = a_cyl
				ankle.rotation_degrees.z = 90
				ankle.position = Vector3(0, 0, 0) if foot_container != null else Vector3(0, -0.53, 0)
				ankle.material_override = chrome_mat
				foot_parent.add_child(ankle)

				# Ankle side pivot flanges (visible mechanical connection)
				for flange_x in [-0.16, 0.16]:
					var flange = MeshInstance3D.new()
					flange.name = "AnkleFlange"
					var fl_cyl = CylinderMesh.new()
					fl_cyl.top_radius = 0.05
					fl_cyl.bottom_radius = 0.05
					fl_cyl.height = 0.05
					flange.mesh = fl_cyl
					flange.rotation_degrees.z = 90
					flange.position = Vector3(flange_x, 0, 0) if foot_container != null else Vector3(flange_x, -0.53, 0)
					flange.material_override = frame_mat
					foot_parent.add_child(flange)

				# Walking Tank Broad Skid Foot with Outriggers & Roller Housing
				var foot_block = MeshInstance3D.new()
				foot_block.name = "FootBlock"
				var ft_box = BoxMesh.new()
				ft_box.size = Vector3(0.36, 0.08, 0.50)
				foot_block.mesh = ft_box
				foot_block.position = Vector3(0, -0.58 - foot_y_off, -0.04)
				foot_block.material_override = frame_mat
				foot_parent.add_child(foot_block)

				# Left & Right ski runners / outrigger stabilizer rails
				for skid_x in [-0.19, 0.19]:
					var skid_rail = MeshInstance3D.new()
					skid_rail.name = "FootSkid"
					var sr_box = BoxMesh.new()
					sr_box.size = Vector3(0.05, 0.10, 0.54)
					skid_rail.mesh = sr_box
					skid_rail.position = Vector3(skid_x, -0.57 - foot_y_off, -0.04)
					skid_rail.material_override = chrome_mat
					foot_parent.add_child(skid_rail)

				# Front roller skate wheel pod
				var roller_pod = MeshInstance3D.new()
				roller_pod.name = "FootRoller"
				var rp_cyl = CylinderMesh.new()
				rp_cyl.top_radius = 0.055
				rp_cyl.bottom_radius = 0.055
				rp_cyl.height = 0.30
				roller_pod.mesh = rp_cyl
				roller_pod.rotation_degrees.z = 90
				roller_pod.position = Vector3(0, -0.59 - foot_y_off, -0.24)
				roller_pod.material_override = chrome_mat
				foot_parent.add_child(roller_pod)

				# Rear heel skid block
				var heel = MeshInstance3D.new()
				heel.name = "FootHeel"
				var h_box = BoxMesh.new()
				h_box.size = Vector3(0.28, 0.07, 0.16)
				heel.mesh = h_box
				heel.position = Vector3(0, -0.58 - foot_y_off, 0.20)
				heel.rotation_degrees.x = 10
				heel.material_override = frame_mat
				foot_parent.add_child(heel)

				# Front toe clamp claws
				for claw_x in [-0.11, 0.11]:
					var claw = MeshInstance3D.new()
					claw.name = "FootClaw"
					var c_box = BoxMesh.new()
					c_box.size = Vector3(0.06, 0.06, 0.18)
					claw.mesh = c_box
					claw.position = Vector3(claw_x, -0.59 - foot_y_off, -0.27)
					claw.rotation_degrees.x = -15
					claw.material_override = frame_mat
					foot_parent.add_child(claw)

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
func _build_procedural_outer_armor(slot_name: String, upper_container: Node3D, lower_container: Node3D = null, part: ArmorPart = null, foot_container: Node3D = null) -> void:
	var col = Color(0.28, 0.32, 0.38) # Sleek Titanium Gunmetal
	if part and "part_color" in part and part.part_color != Color.TRANSPARENT and part.part_color.a > 0.1:
		col = part.part_color

	# Shared cached materials (same look, no per-slot/per-mech rebuild cost).
	var armor_mat := _get_shared_armor_mat(col)
	var dark_trim_mat := _get_shared_dark_trim_mat()

	match slot_name.to_lower():
		"head":
			# Compact Turret Sensor Cowl (เกราะส่วนหัวลู่ลมขนาดกะทัดรัด)
			var helmet = MeshInstance3D.new()
			var h_box = BoxMesh.new()
			h_box.size = Vector3(0.24, 0.14, 0.24)
			helmet.mesh = h_box
			helmet.position = Vector3(0, 0.05, -0.02)
			helmet.material_override = armor_mat
			upper_container.add_child(helmet)

			for side_x in [-0.13, 0.13]:
				var cheek = MeshInstance3D.new()
				var c_box = BoxMesh.new()
				c_box.size = Vector3(0.04, 0.10, 0.18)
				cheek.mesh = c_box
				cheek.position = Vector3(side_x, 0.03, -0.04)
				cheek.material_override = dark_trim_mat
				upper_container.add_child(cheek)

			var brow = MeshInstance3D.new()
			var b_prism = PrismMesh.new()
			b_prism.size = Vector3(0.18, 0.10, 0.16)
			brow.mesh = b_prism
			brow.rotation_degrees.x = -25
			brow.position = Vector3(0, 0.10, -0.06)
			brow.material_override = armor_mat
			upper_container.add_child(brow)

			var collar = MeshInstance3D.new()
			var cl_cyl = CylinderMesh.new()
			cl_cyl.top_radius = 0.12
			cl_cyl.bottom_radius = 0.14
			cl_cyl.height = 0.06
			collar.mesh = cl_cyl
			collar.position = Vector3(0, -0.05, 0)
			collar.material_override = dark_trim_mat
			upper_container.add_child(collar)

		"body":
			# Classic Outer Armor Hatch Plate attached to SlidingCarriage
			var armor_carriage = Node3D.new()
			armor_carriage.name = "SlidingCarriage"
			if is_cockpit_open:
				armor_carriage.position = Vector3(0.0, -0.22, -0.48)
				armor_carriage.rotation_degrees = Vector3(8.0, 0.0, 0.0)
			upper_container.add_child(armor_carriage)

			# Classic Angled Chest Armor Plate (รูป 2-3)
			var chest = MeshInstance3D.new()
			var c_prism = PrismMesh.new()
			c_prism.size = Vector3(0.95, 0.65, 0.48)
			chest.mesh = c_prism
			chest.rotation_degrees.x = 90
			chest.position = Vector3(0, 0.12, -0.14)
			chest.material_override = armor_mat
			armor_carriage.add_child(chest)

			# Dual Classic Front Intake Vents
			for side_x in [-0.42, 0.42]:
				var vent = MeshInstance3D.new()
				var v_box = BoxMesh.new()
				v_box.size = Vector3(0.14, 0.35, 0.25)
				vent.mesh = v_box
				vent.position = Vector3(side_x, 0.15, -0.08)
				vent.material_override = dark_trim_mat
				armor_carriage.add_child(vent)

			# Front Hatch Center Slot Trim
			var center_trim = MeshInstance3D.new()
			var ct_box = BoxMesh.new()
			ct_box.size = Vector3(0.44, 0.08, 0.05)
			center_trim.mesh = ct_box
			center_trim.position = Vector3(0, 0.02, -0.36)
			center_trim.material_override = dark_trim_mat
			armor_carriage.add_child(center_trim)

			# Classic Abdominal Armor Flap
			var ab_plate = MeshInstance3D.new()
			var ab_box = BoxMesh.new()
			ab_box.size = Vector3(0.58, 0.35, 0.26)
			ab_plate.mesh = ab_box
			ab_plate.position = Vector3(0, -0.28, -0.10)
			ab_plate.material_override = armor_mat
			armor_carriage.add_child(ab_plate)

			# Armored Neck Cowl / Collar Ring sealing the gap between cockpit roof and lowered head socket
			var neck_cowl = MeshInstance3D.new()
			var nc_cyl = CylinderMesh.new()
			nc_cyl.top_radius = 0.18
			nc_cyl.bottom_radius = 0.24
			nc_cyl.height = 0.14
			neck_cowl.mesh = nc_cyl
			neck_cowl.position = Vector3(0, 0.28, -0.04)
			neck_cowl.material_override = dark_trim_mat
			upper_container.add_child(neck_cowl)

			# Shoulder cowls extending outward to bridge torso to shoulder pivots
			for side_x in [-0.58, 0.58]:
				var shoulder_cowl = MeshInstance3D.new()
				var sc_box = BoxMesh.new()
				sc_box.size = Vector3(0.34, 0.28, 0.38)
				shoulder_cowl.mesh = sc_box
				shoulder_cowl.position = Vector3(side_x, 0.22, -0.02)
				shoulder_cowl.material_override = dark_trim_mat
				upper_container.add_child(shoulder_cowl)

			# Pelvis chassis & hip girdle (bridges waist to leg hip joints)
			# Wanzer rebalance: widened (Y unchanged) to meet the thicker thighs.
			var pelvis_armor = MeshInstance3D.new()
			var p_box = BoxMesh.new()
			p_box.size = Vector3(0.76, 0.24, 0.40)
			pelvis_armor.mesh = p_box
			pelvis_armor.position = Vector3(0, -0.48, -0.04)
			pelvis_armor.material_override = dark_trim_mat
			upper_container.add_child(pelvis_armor)

			# Left & right articulated hip skirts (cover hip sockets and connect waist to thighs)
			for side_x in [-0.54, 0.54]:
				var skirt = MeshInstance3D.new()
				var sk_box = BoxMesh.new()
				sk_box.size = Vector3(0.13, 0.34, 0.42)
				skirt.mesh = sk_box
				skirt.position = Vector3(side_x, -0.48, -0.02)
				skirt.rotation_degrees.z = -12.0 if side_x < 0 else 12.0
				skirt.material_override = armor_mat
				upper_container.add_child(skirt)

		"arm_left", "arm_right":
			var is_left = slot_name.to_lower() == "arm_left"
			var dir_sign = -1.0 if is_left else 1.0

			# --- UPPER ARM ARMOR (Shoulder Pauldron attached to ArmLeft/ArmRight) ---
			# Wanzer rebalance: thickened in width/depth (Y unchanged) so the
			# arm carries enough mass for its weapon.
			var pauldron = MeshInstance3D.new()
			var p_box = BoxMesh.new()
			p_box.size = Vector3(0.56, 0.36, 0.56)
			pauldron.mesh = p_box
			pauldron.position = Vector3(dir_sign * 0.08, 0.04, 0)
			pauldron.material_override = armor_mat
			upper_container.add_child(pauldron)

			var trim = MeshInstance3D.new()
			var t_box = BoxMesh.new()
			t_box.size = Vector3(0.60, 0.10, 0.60)
			trim.mesh = t_box
			trim.position = Vector3(dir_sign * 0.08, 0.17, 0)
			trim.material_override = dark_trim_mat
			upper_container.add_child(trim)

			# --- LOWER ARM ARMOR (Forearm Guard attached to ForearmLeft/ForearmRight) ---
			if lower_container:
				var forearm_guard = MeshInstance3D.new()
				var fg_box = BoxMesh.new()
				fg_box.size = Vector3(0.42, 0.46, 0.42)
				forearm_guard.mesh = fg_box
				forearm_guard.position = Vector3(0, -0.225, 0)
				forearm_guard.material_override = armor_mat
				lower_container.add_child(forearm_guard)

				var elbow_cap = MeshInstance3D.new()
				var ec_box = BoxMesh.new()
				ec_box.size = Vector3(0.30, 0.18, 0.14)
				elbow_cap.mesh = ec_box
				elbow_cap.position = Vector3(0, 0, 0.16)
				elbow_cap.material_override = dark_trim_mat
				lower_container.add_child(elbow_cap)

				var knuckle = MeshInstance3D.new()
				var k_box = BoxMesh.new()
				k_box.size = Vector3(0.22, 0.07, 0.22)
				knuckle.mesh = k_box
				knuckle.position = Vector3(0, -0.45, -0.02)
				knuckle.material_override = armor_mat
				lower_container.add_child(knuckle)

		"leg_left", "leg_right":
			# --- UPPER LEG ARMOR (Thigh Guard attached to LegLeft/LegRight) ---
			# Wanzer rebalance: thickened in width/depth (Y unchanged).
			var thigh_armor = MeshInstance3D.new()
			var ta_box = BoxMesh.new()
			ta_box.size = Vector3(0.48, 0.44, 0.48)
			thigh_armor.mesh = ta_box
			thigh_armor.position = Vector3(0, -0.275, 0)
			thigh_armor.material_override = armor_mat
			upper_container.add_child(thigh_armor)

			for side_x in [-0.25, 0.25]:
				var t_side = MeshInstance3D.new()
				var ts_box = BoxMesh.new()
				ts_box.size = Vector3(0.07, 0.38, 0.36)
				t_side.mesh = ts_box
				t_side.position = Vector3(side_x, -0.275, 0)
				t_side.material_override = dark_trim_mat
				upper_container.add_child(t_side)

			# --- LOWER LEG ARMOR (Knee Cap + Shin Guard attached to ShinLeft/ShinRight) ---
			if lower_container:
				var knee_cap = MeshInstance3D.new()
				var k_prism = PrismMesh.new()
				k_prism.size = Vector3(0.38, 0.28, 0.30)
				knee_cap.mesh = k_prism
				knee_cap.rotation_degrees.x = 90
				knee_cap.position = Vector3(0, 0, 0.17)
				knee_cap.material_override = armor_mat
				lower_container.add_child(knee_cap)

				var shin_armor = MeshInstance3D.new()
				var sa_box = BoxMesh.new()
				sa_box.size = Vector3(0.48, 0.48, 0.46)
				shin_armor.mesh = sa_box
				shin_armor.position = Vector3(0, -0.275, 0.04)
				shin_armor.material_override = armor_mat
				lower_container.add_child(shin_armor)

				for side_x in [-0.25, 0.25]:
					var calf_plate = MeshInstance3D.new()
					var cp_box = BoxMesh.new()
					cp_box.size = Vector3(0.07, 0.36, 0.32)
					calf_plate.mesh = cp_box
					calf_plate.position = Vector3(side_x, -0.275, 0.02)
					calf_plate.material_override = dark_trim_mat
					lower_container.add_child(calf_plate)

			# --- FOOT ARMOR (separate movable part on the Foot pivot) ---
			# Positions are Foot-local (ankle = origin); world placement is
			# unchanged from the old Shin-local layout.
			var foot_armor_parent := foot_container if foot_container != null else lower_container
			var foot_armor_off := -0.53 if foot_container != null else 0.0
			if foot_armor_parent:
				# Ankle cuff armor ringing the joint
				var ankle_cuff = MeshInstance3D.new()
				ankle_cuff.name = "AnkleCuff"
				var ac_cyl = CylinderMesh.new()
				ac_cyl.top_radius = 0.19
				ac_cyl.bottom_radius = 0.21
				ac_cyl.height = 0.10
				ankle_cuff.mesh = ac_cyl
				ankle_cuff.position = Vector3(0, -0.02, 0) if foot_container != null else Vector3(0, -0.53, 0)
				ankle_cuff.material_override = dark_trim_mat
				foot_armor_parent.add_child(ankle_cuff)

				# Wide Walking Tank Skid Foot Armor
				var foot_cap = MeshInstance3D.new()
				foot_cap.name = "FootCap"
				var fc_box = BoxMesh.new()
				fc_box.size = Vector3(0.40, 0.12, 0.52)
				foot_cap.mesh = fc_box
				foot_cap.position = Vector3(0, -0.56 - foot_armor_off, -0.04)
				foot_cap.material_override = armor_mat
				foot_armor_parent.add_child(foot_cap)

				for skid_x in [-0.21, 0.21]:
					var skid_guard = MeshInstance3D.new()
					skid_guard.name = "FootSkidGuard"
					var sg_box = BoxMesh.new()
					sg_box.size = Vector3(0.06, 0.09, 0.56)
					skid_guard.mesh = sg_box
					skid_guard.position = Vector3(skid_x, -0.56 - foot_armor_off, -0.04)
					skid_guard.material_override = dark_trim_mat
					foot_armor_parent.add_child(skid_guard)

				var toe_deflector = MeshInstance3D.new()
				toe_deflector.name = "FootToe"
				var td_box = BoxMesh.new()
				td_box.size = Vector3(0.34, 0.08, 0.16)
				toe_deflector.mesh = td_box
				toe_deflector.position = Vector3(0, -0.57 - foot_armor_off, -0.27)
				toe_deflector.rotation_degrees.x = -15
				toe_deflector.material_override = dark_trim_mat
				foot_armor_parent.add_child(toe_deflector)

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
		{"pos": Vector3(0, 0.1, 0), "rot": Vector3(0, 0, 0.15), "scale": Vector3(0.18, 0.05, 0.18), "color": BINDING_COLOR_LIGHT},
		{"pos": Vector3(0, -0.15, 0), "rot": Vector3(0, 0, -0.1), "scale": Vector3(0.16, 0.04, 0.16), "color": BINDING_COLOR_ACCENT},
	],
	"arm_right": [
		{"pos": Vector3(0, 0.1, 0), "rot": Vector3(0, 0, -0.15), "scale": Vector3(0.18, 0.05, 0.18), "color": BINDING_COLOR_LIGHT},
		{"pos": Vector3(0, -0.15, 0), "rot": Vector3(0, 0, 0.1), "scale": Vector3(0.16, 0.04, 0.16), "color": BINDING_COLOR_ACCENT},
	],
	"leg_left": [
		{"pos": Vector3(0, 0.15, 0), "rot": Vector3(0, 0, 0), "scale": Vector3(0.21, 0.05, 0.21), "color": BINDING_COLOR_DARK},
		{"pos": Vector3(0, -0.2, 0), "rot": Vector3(0, 0, 0), "scale": Vector3(0.19, 0.04, 0.19), "color": BINDING_COLOR_LIGHT},
	],
	"leg_right": [
		{"pos": Vector3(0, 0.15, 0), "rot": Vector3(0, 0, 0), "scale": Vector3(0.21, 0.05, 0.21), "color": BINDING_COLOR_DARK},
		{"pos": Vector3(0, -0.2, 0), "rot": Vector3(0, 0, 0), "scale": Vector3(0.19, 0.04, 0.19), "color": BINDING_COLOR_LIGHT},
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
		mi.position = (tmpl.get("pos", Vector3.ZERO) as Vector3) * WORLD_SCALE
		mi.rotation = tmpl.get("rot", Vector3.ZERO)
		mi.scale = (tmpl.get("scale", Vector3.ONE) as Vector3) * WORLD_SCALE

		# Torus mesh for the cloth wrap ring - scaled to world
		var torus := TorusMesh.new()
		torus.inner_radius = 0.38 * WORLD_SCALE
		torus.outer_radius = 0.52 * WORLD_SCALE
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
	_cloak_visual.scale = Vector3.ONE * WORLD_SCALE
	body_node.add_child(_cloak_visual)
	_cloak_visual.position = Vector3(0, 0.3, 0.15) * WORLD_SCALE  # Back of torso

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
