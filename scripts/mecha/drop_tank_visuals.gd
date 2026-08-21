extends Node3D

## Drop Tank Visuals (GDD §2.4)
## Procedurally builds external fuel canisters on the mech's backpack.
## Mounts: up to 3 cylindrical tanks (left, right, dorsal) with connecting
## struts. Shows spark VFX when damaged, and purge/detonation effects.

var _tank_nodes: Array[MeshInstance3D] = []
var _strut_nodes: Array[MeshInstance3D] = []
var _spark_timer: float = 0.0
var _is_sparking: bool = false
var _tank_mat: StandardMaterial3D = null
var _tank_damaged_mat: StandardMaterial3D = null
var _parent_mecha: Node = null


func _ready() -> void:
	_parent_mecha = get_parent()
	# Build materials once.
	_build_materials()
	# Initial visibility based on GlobalData.
	_refresh()


func _process(delta: float) -> void:
	if _is_sparking and not _tank_nodes.is_empty():
		_spark_timer -= delta
		if _spark_timer <= 0.0:
			_spawn_spark_vfx()
			_spark_timer = 0.12
	# Flicker the damaged material when HP is low.
	var mecha = _get_mecha()
	var energy_sys = mecha.get_node_or_null("EnergySystem") if mecha else null
	if energy_sys and "_drop_tank_hp" in energy_sys:
		var hp_ratio: float = energy_sys._drop_tank_hp / maxf(energy_sys._drop_tank_hp + 1.0, 1.0)
		if energy_sys._drop_tank_active and hp_ratio < 0.5:
			_apply_flicker(hp_ratio)
		elif _tank_damaged_mat != null:
			_tank_damaged_mat.emission_energy_multiplier = 3.0


# ---------------------------------------------------------------------------
# MATERIALS
# ---------------------------------------------------------------------------

func _build_materials() -> void:
	# Normal fuel tank: dark olive drab with orange fuel-level stripe.
	_tank_mat = StandardMaterial3D.new()
	_tank_mat.albedo_color = Color(0.32, 0.38, 0.28)
	_tank_mat.metallic = 0.6
	_tank_mat.roughness = 0.45
	_tank_mat.emission_enabled = true
	_tank_mat.emission = Color(0.8, 0.45, 0.0)
	_tank_mat.emission_energy_multiplier = 1.5

	# Damaged / sparking tank: same base but brighter emission + flicker.
	_tank_damaged_mat = StandardMaterial3D.new()
	_tank_damaged_mat.albedo_color = Color(0.32, 0.38, 0.28)
	_tank_damaged_mat.metallic = 0.6
	_tank_damaged_mat.roughness = 0.45
	_tank_damaged_mat.emission_enabled = true
	_tank_damaged_mat.emission = Color(1.0, 0.6, 0.1)
	_tank_damaged_mat.emission_energy_multiplier = 3.0


func _get_strut_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.45, 0.48)
	mat.metallic = 0.8
	mat.roughness = 0.3
	return mat


# ---------------------------------------------------------------------------
# BUILD / REBUILD
# ---------------------------------------------------------------------------

func _refresh() -> void:
	_clear_tanks()
	var count: int = 0
	if _parent_mecha:
		count = GlobalData.fuel.drop_tanks_attached
	if count <= 0:
		return
	# Mount positions relative to the backpack node (Body/Backpack).
	# Tank 0 = left side, Tank 1 = right side, Tank 2 = dorsal (top).
	var positions: Array[Vector3] = [
		Vector3(-0.55, 0.0, 0.0),   # left
		Vector3(0.55, 0.0, 0.0),    # right
		Vector3(0.0, 0.45, -0.15),  # dorsal (top-back)
	]
	var rotations: Array[Vector3] = [
		Vector3(0, 0, deg_to_rad(8)),   # left: slight outward tilt
		Vector3(0, 0, deg_to_rad(-8)),  # right: slight outward tilt
		Vector3(deg_to_rad(-15), 0, 0), # dorsal: angled backward
	]
	for i in range(mini(count, 3)):
		var tank := _build_tank_cylinder()
		tank.position = positions[i]
		tank.rotation = rotations[i]
		add_child(tank)
		_tank_nodes.append(tank)
		# Build strut connecting tank to the backpack frame.
		var strut := _build_strut(positions[i])
		add_child(strut)
		_strut_nodes.append(strut)


func _build_tank_cylinder() -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.12
	cylinder.bottom_radius = 0.14
	cylinder.height = 0.85
	mesh_inst.mesh = cylinder
	mesh_inst.material_override = _tank_mat
	return mesh_inst


func _build_strut(tank_pos: Vector3) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.06, 0.25)
	mesh_inst.mesh = box
	mesh_inst.material_override = _get_strut_material()
	# Position the strut between the backpack center and the tank.
	mesh_inst.position = tank_pos * 0.5 + Vector3(0, 0, -0.1)
	return mesh_inst


func _clear_tanks() -> void:
	for tank in _tank_nodes:
		if is_instance_valid(tank):
			tank.queue_free()
	for strut in _strut_nodes:
		if is_instance_valid(strut):
			strut.queue_free()
	_tank_nodes.clear()
	_strut_nodes.clear()


# ---------------------------------------------------------------------------
# DAMAGE VFX (called by mecha_controller when drop tank HP drops)
# ---------------------------------------------------------------------------

func on_drop_tank_damaged() -> void:
	_is_sparking = true
	_spark_timer = 0.0
	# Switch all tanks to the damaged material.
	for tank in _tank_nodes:
		if is_instance_valid(tank):
			tank.material_override = _tank_damaged_mat


func on_drop_tank_destroyed() -> void:
	_is_sparking = false
	# Tanks vanish in the detonation VFX (handled by mecha_controller).


func on_drop_tank_purged() -> void:
	_is_sparking = false
	# Flash + fade out, then clear.
	for tank in _tank_nodes:
		if is_instance_valid(tank):
			_fade_out_node(tank)
	for strut in _strut_nodes:
		if is_instance_valid(strut):
			_fade_out_node(strut)
	# Delayed clear after the fade.
	await get_tree().create_timer(0.4).timeout
	_clear_tanks()


func _fade_out_node(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	if node is MeshInstance3D and node.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = node.material_override
		var tween := create_tween().set_parallel(true)
		tween.tween_property(node, "scale", node.scale * 1.3, 0.3).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	else:
		node.visible = false


# ---------------------------------------------------------------------------
# SPARK VFX
# ---------------------------------------------------------------------------

func _spawn_spark_vfx() -> void:
	if _tank_nodes.is_empty():
		return
	var tank = _tank_nodes[randi() % _tank_nodes.size()]
	if not is_instance_valid(tank):
		return
	var spark := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.04, 0.15)
	spark.mesh = box
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.7, 0.1, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.2)
	mat.emission_energy_multiplier = 5.0
	spark.material_override = mat
	# Position spark at a random point on the tank surface.
	var offset := Vector3(randf_range(-0.1, 0.1), randf_range(-0.3, 0.3), randf_range(-0.1, 0.1))
	spark.global_position = tank.global_position + offset
	spark.global_rotation = tank.global_rotation
	# Parent to the scene so it isn't freed with the tank.
	var scene = get_tree().current_scene
	if scene:
		scene.add_child(spark)
		var tween := create_tween()
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.15)
		tween.tween_callback(spark.queue_free)


func _apply_flicker(hp_ratio: float) -> void:
	if _tank_damaged_mat == null:
		return
	# Flicker faster as HP drops lower.
	var flicker := sin(Time.get_ticks_msec() * 0.01) * 0.5 + 0.5
	var intensity := lerpf(2.0, 6.0, 1.0 - hp_ratio) * flicker
	_tank_damaged_mat.emission_energy_multiplier = intensity


# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

func _get_mecha() -> Node:
	if _parent_mecha and is_instance_valid(_parent_mecha):
		return _parent_mecha
	return null
