class_name TelegraphPresentation
extends Node3D

## =============================================================================
## TELEGRAPH PRESENTATION — Generic Capability Telegraph Visuals (Phase 2E-11B)
##
## Consumes public telegraph descriptors (Array[Dictionary]) from WeaponManager
## and renders visual warning indicators (corridor, core, target reticle).
##
## AUTHORITY BOUNDARIES:
## - Downstream of gameplay only.
## - Strictly presentation/display: DOES NOT deal damage, DOES NOT consume energy,
##   DOES NOT trigger cooldowns, DOES NOT mutate combat state or timing.
## - Reads authoritative progress [0.0..1.0] and geometry (source -> target).
## =============================================================================

@export var weapon_manager: Node = null

# Active visual instance mapping: session_id -> Node3D
var _instances: Dictionary = {}


func _process(_delta: float) -> void:
	if weapon_manager and weapon_manager.has_method("get_active_telegraph_descriptors"):
		var descriptors: Array = weapon_manager.get_active_telegraph_descriptors()
		sync_descriptors(descriptors)


## Synchronizes visual telegraph instances with the array of active descriptors.
func sync_descriptors(descriptors: Array) -> void:
	var seen_ids: Dictionary = {}

	for desc in descriptors:
		if not (desc is Dictionary):
			continue

		var is_active: bool = bool(desc.get("active", desc.get("is_active", false)))
		if not is_active:
			continue

		var s_id: String = str(desc.get("session_id", ""))
		if s_id == "":
			s_id = "desc_%d_%s" % [int(desc.get("started_at", 0)), str(desc.get("source", Vector3.ZERO))]

		seen_ids[s_id] = true

		if not _instances.has(s_id):
			var inst := _create_presentation_instance(desc)
			_instances[s_id] = inst
			add_child(inst)
			_play_charge_sound(desc)

		var inst_node: Node3D = _instances[s_id]
		if is_instance_valid(inst_node) and inst_node.has_method("update_from_descriptor"):
			inst_node.update_from_descriptor(desc)

	# Prune instances whose descriptors are no longer active or present
	var to_remove: Array = []
	for existing_id in _instances.keys():
		if not seen_ids.has(existing_id):
			to_remove.append(existing_id)

	for rem_id in to_remove:
		var node: Node3D = _instances[rem_id]
		_instances.erase(rem_id)
		if is_instance_valid(node):
			node.queue_free()


## Returns the count of currently active presentation instances.
func get_active_presentation_count() -> int:
	return _instances.size()


## Returns a specific presentation instance by session_id.
func get_presentation(session_id: String) -> Node3D:
	return _instances.get(session_id, null)


## Immediately clears and frees all active presentation instances.
func clear() -> void:
	for node in _instances.values():
		if is_instance_valid(node):
			node.queue_free()
	_instances.clear()


func _exit_tree() -> void:
	clear()


# -----------------------------------------------------------------------------
# Internal Factory & Audio
# -----------------------------------------------------------------------------

func _create_presentation_instance(desc: Dictionary) -> Node3D:
	return TelegraphVisualInstance.new(desc)


func _play_charge_sound(desc: Dictionary) -> void:
	# Audio is presentation-only and non-authoritative
	var audio_mgr = Engine.get_main_loop().root.get_node_or_null("/root/AudioManager") if Engine.get_main_loop() else null
	if audio_mgr and is_instance_valid(audio_mgr) and audio_mgr.has_method("play_sfx"):
		var src: Vector3 = desc.get("source_position", desc.get("source", Vector3.ZERO))
		audio_mgr.play_sfx("cockpit_alert", src, -4.0)


# =============================================================================
# TelegraphVisualInstance — Individual Telegraph Presentation Node
# =============================================================================
class TelegraphVisualInstance extends Node3D:
	var session_id: String = ""
	var source_pos: Vector3 = Vector3.ZERO
	var target_pos: Vector3 = Vector3.ZERO
	var beam_radius: float = 6.0
	var progress: float = 0.0

	# Sub-visual nodes
	var beam_container: Node3D
	var outer_mesh_inst: MeshInstance3D
	var inner_mesh_inst: MeshInstance3D
	var target_reticle: Node3D
	var target_ring_mesh: MeshInstance3D
	var area_disc_mesh: MeshInstance3D

	# Materials
	var outer_mat: StandardMaterial3D
	var inner_mat: StandardMaterial3D
	var reticle_mat: StandardMaterial3D
	var disc_mat: StandardMaterial3D

	func _init(desc: Dictionary) -> void:
		name = "TelegraphInstance_" + str(desc.get("session_id", "anon"))
		session_id = str(desc.get("session_id", ""))
		_build_hierarchy()

	func _build_hierarchy() -> void:
		beam_container = Node3D.new()
		beam_container.name = "BeamContainer"
		add_child(beam_container)

		# Outer corridor mesh (translucent warning sheath for directional lines)
		outer_mesh_inst = MeshInstance3D.new()
		outer_mesh_inst.name = "OuterCorridor"
		var outer_cylinder = CylinderMesh.new()
		outer_cylinder.radial_segments = 16
		outer_mesh_inst.mesh = outer_cylinder

		outer_mat = StandardMaterial3D.new()
		outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		outer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		outer_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		outer_mat.albedo_color = Color(1.0, 0.45, 0.1, 0.15)
		outer_mesh_inst.material_override = outer_mat
		outer_mesh_inst.rotation_degrees = Vector3(90, 0, 0)
		beam_container.add_child(outer_mesh_inst)

		# Inner beam core (focused laser line)
		inner_mesh_inst = MeshInstance3D.new()
		inner_mesh_inst.name = "InnerBeam"
		var inner_cylinder = CylinderMesh.new()
		inner_cylinder.radial_segments = 12
		inner_cylinder.top_radius = 0.15
		inner_cylinder.bottom_radius = 0.15
		inner_mesh_inst.mesh = inner_cylinder

		inner_mat = StandardMaterial3D.new()
		inner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		inner_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		inner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		inner_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		inner_mat.albedo_color = Color(1.0, 0.95, 0.6, 0.6)
		inner_mat.emission_enabled = true
		inner_mat.emission = Color(1.0, 0.6, 0.2)
		inner_mat.emission_energy_multiplier = 2.0
		inner_mesh_inst.material_override = inner_mat
		inner_mesh_inst.rotation_degrees = Vector3(90, 0, 0)
		beam_container.add_child(inner_mesh_inst)

		# Target Reticle / Warning Ring & Area Indicator
		target_reticle = Node3D.new()
		target_reticle.name = "TargetReticle"
		add_child(target_reticle)

		target_ring_mesh = MeshInstance3D.new()
		target_ring_mesh.name = "TargetRing"
		var ring_torus = TorusMesh.new()
		ring_torus.inner_radius = 5.0
		ring_torus.outer_radius = 6.0
		ring_torus.rings = 24
		ring_torus.ring_segments = 8
		target_ring_mesh.mesh = ring_torus

		reticle_mat = StandardMaterial3D.new()
		reticle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		reticle_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		reticle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		reticle_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		reticle_mat.albedo_color = Color(1.0, 0.35, 0.1, 0.5)
		reticle_mat.emission_enabled = true
		reticle_mat.emission = Color(1.0, 0.4, 0.1)
		reticle_mat.emission_energy_multiplier = 2.0
		target_ring_mesh.material_override = reticle_mat
		target_reticle.add_child(target_ring_mesh)

		# Area Ground Disc (translucent ground warning zone for area/radius geometries)
		area_disc_mesh = MeshInstance3D.new()
		area_disc_mesh.name = "AreaDisc"
		var disc_cyl = CylinderMesh.new()
		disc_cyl.radial_segments = 32
		disc_cyl.height = 0.05
		area_disc_mesh.mesh = disc_cyl

		disc_mat = StandardMaterial3D.new()
		disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		disc_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		disc_mat.albedo_color = Color(1.0, 0.4, 0.1, 0.12)
		area_disc_mesh.material_override = disc_mat
		area_disc_mesh.visible = false
		target_reticle.add_child(area_disc_mesh)

	## Updates transform, geometry, and visual progression from authoritative descriptor.
	func update_from_descriptor(desc: Dictionary) -> void:
		source_pos = desc.get("source_position", desc.get("source", desc.get("origin", Vector3.ZERO)))
		target_pos = desc.get("target_position", desc.get("target", Vector3.ZERO))
		progress = clampf(float(desc.get("progress", 0.0)), 0.0, 1.0)

		var geom_type: String = str(desc.get("geometry_type", "")).to_lower()
		var area_shape: String = str(desc.get("area_shape", "")).to_lower()
		var targeting_mode: String = str(desc.get("targeting_mode", "")).to_lower()
		var is_area: bool = (geom_type in ["sphere", "circle", "cylinder", "area"] or targeting_mode == "area_radius" or area_shape in ["sphere", "circle", "cylinder"])

		var area_params: Dictionary = desc.get("area_parameters", {})
		var effective_radius: float
		if is_area:
			effective_radius = float(area_params.get("radius", area_params.get("range", 25.0)))
		else:
			var width: float = float(area_params.get("width", area_params.get("beam_radius", 12.0)))
			effective_radius = maxf(width * 0.5, 0.5)
		beam_radius = effective_radius

		if is_area:
			# Area Geometry (e.g. Jammer, radial pulse, shockwave)
			beam_container.visible = false
			area_disc_mesh.visible = true
			target_reticle.visible = true

			if is_inside_tree():
				target_reticle.global_position = target_pos
			else:
				target_reticle.position = target_pos

			# Update area perimeter ring and ground warning disc
			var ring_torus := target_ring_mesh.mesh as TorusMesh
			if ring_torus:
				ring_torus.inner_radius = maxf(effective_radius * 0.97, 0.4)
				ring_torus.outer_radius = effective_radius

			var disc_cyl := area_disc_mesh.mesh as CylinderMesh
			if disc_cyl:
				disc_cyl.top_radius = effective_radius
				disc_cyl.bottom_radius = effective_radius
				disc_cyl.height = 0.05

			var disc_alpha: float = 0.08 + progress * 0.25
			disc_mat.albedo_color = Color(1.0, 0.4, 0.1, disc_alpha)

			var reticle_alpha: float = 0.35 + progress * 0.65
			var reticle_emission: float = 1.5 + progress * 6.5
			reticle_mat.albedo_color = Color(1.0, 0.35, 0.1, reticle_alpha)
			reticle_mat.emission_energy_multiplier = reticle_emission
		else:
			# Directional Line/Beam Geometry (e.g. Satellite Cannon)
			beam_container.visible = true
			area_disc_mesh.visible = false
			target_reticle.visible = true

			# 1. Update Beam Geometry (spans source to target)
			var dist: float = source_pos.distance_to(target_pos)
			if dist < 0.001:
				dist = 0.001

			var mid_point: Vector3 = (source_pos + target_pos) * 0.5
			if is_inside_tree():
				beam_container.global_position = mid_point
				var dir_to_target: Vector3 = (target_pos - source_pos).normalized()
				if dir_to_target.length_squared() > 0.001:
					var up_vec: Vector3 = Vector3.UP
					if absf(dir_to_target.dot(Vector3.UP)) > 0.99:
						up_vec = Vector3.RIGHT
					beam_container.look_at(target_pos, up_vec)
				target_reticle.global_position = target_pos
			else:
				beam_container.position = mid_point
				target_reticle.position = target_pos

			# Update corridor dimensions
			var outer_cyl := outer_mesh_inst.mesh as CylinderMesh
			if outer_cyl:
				outer_cyl.height = dist
				outer_cyl.top_radius = beam_radius
				outer_cyl.bottom_radius = beam_radius

			var inner_cyl := inner_mesh_inst.mesh as CylinderMesh
			if inner_cyl:
				inner_cyl.height = dist
				var core_rad: float = 0.12 + progress * 0.28
				inner_cyl.top_radius = core_rad
				inner_cyl.bottom_radius = core_rad

			# 2. Update Target Reticle Size
			var ring_torus := target_ring_mesh.mesh as TorusMesh
			if ring_torus:
				ring_torus.inner_radius = maxf(beam_radius * 0.85, 0.4)
				ring_torus.outer_radius = maxf(beam_radius, 0.6)

			# 3. Update Progress Feedback (alpha, emission, intensity)
			var corridor_alpha: float = 0.10 + progress * 0.35
			outer_mat.albedo_color = Color(1.0, 0.45, 0.1, corridor_alpha)

			var core_alpha: float = 0.40 + progress * 0.60
			var core_emission: float = 1.5 + progress * 5.5
			inner_mat.albedo_color = Color(1.0, 0.95, 0.6, core_alpha)
			inner_mat.emission_energy_multiplier = core_emission

			var reticle_alpha: float = 0.35 + progress * 0.65
			var reticle_emission: float = 1.5 + progress * 6.5
			reticle_mat.albedo_color = Color(1.0, 0.35, 0.1, reticle_alpha)
			reticle_mat.emission_energy_multiplier = reticle_emission
