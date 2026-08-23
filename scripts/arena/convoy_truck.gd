extends StaticBody3D
class_name ConvoyTruck

## Convoy Truck — battle-side physical truck for defense/breakdown events
## - Spawns beside the player in defense battles (black smoke when breakdown)
## - HP is linked to GlobalData.board.convoy_hp (central state)
## - Number of trucks scales with roster: 1 per 2 mechs (max 3)
## - Destructible: enemies target it, player must defend

var truck_index: int = 0
var max_hp: float = 100.0
var is_breakdown: bool = false

var _smoke: GPUParticles3D = null
var _smoke_mesh: MeshInstance3D = null
var _hp_label: Label3D = null
var _hp_bar: ProgressBar = null
var _billboard: Control = null

signal truck_destroyed(idx: int)
signal truck_damaged(idx: int, hp: float, max_hp: float)

func _ready() -> void:
	add_to_group("convoy_truck")
	add_to_group("defense_target")
	collision_layer = 1 | 8 # also enemy targetable
	collision_mask = 1
	_build_model()
	_setup_hp()
	_setup_smoke()
	_setup_billboard()
	_update_visual()

func _build_model() -> void:
	# Clean previous
	for c in get_children():
		if c.name.begins_with("Truck_"):
			c.queue_free()

	# Cab — dark olive drab, flat 1px style
	var cab := MeshInstance3D.new()
	cab.name = "Truck_Cab"
	var cab_m := BoxMesh.new()
	cab_m.size = Vector3(1.2, 1.0, 1.4)
	cab.mesh = cab_m
	var cab_mat := StandardMaterial3D.new()
	cab_mat.albedo_color = Color(0.24, 0.28, 0.22, 1.0)
	cab_mat.roughness = 0.85
	cab_mat.metallic = 0.05
	cab.material_override = cab_mat
	cab.position = Vector3(0, 0.65, 1.1)
	add_child(cab)

	var cab2 := MeshInstance3D.new()
	cab2.name = "Truck_CabTop"
	var cab2m := BoxMesh.new()
	cab2m.size = Vector3(1.15, 0.25, 1.2)
	cab2.mesh = cab2m
	var cab2mat := StandardMaterial3D.new()
	cab2mat.albedo_color = Color(0.18, 0.20, 0.18, 1.0)
	cab2mat.roughness = 0.9
	cab2.material_override = cab2mat
	cab2.position = Vector3(0, 1.25, 1.1)
	add_child(cab2)

	# Windshield — dark glass
	var glass := MeshInstance3D.new()
	glass.name = "Truck_Glass"
	var gm := BoxMesh.new()
	gm.size = Vector3(1.05, 0.45, 0.05)
	glass.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.12, 0.14, 0.16, 1.0)
	gmat.roughness = 0.2
	gmat.metallic = 0.6
	glass.material_override = gmat
	glass.position = Vector3(0, 1.05, 1.75)
	add_child(glass)

	# Cargo container — ridged, olive/khaki
	var bed := MeshInstance3D.new()
	bed.name = "Truck_Bed"
	var bed_m := BoxMesh.new()
	bed_m.size = Vector3(1.6, 1.35, 2.8)
	bed.mesh = bed_m
	var bed_mat := StandardMaterial3D.new()
	bed_mat.albedo_color = Color(0.32, 0.34, 0.28, 1.0)
	bed_mat.roughness = 0.85
	bed.material_override = bed_mat
	bed.position = Vector3(0, 0.85, -0.7)
	add_child(bed)

	# Side ridges
	for z in [-1.6, -0.9, -0.2, 0.5]:
		var ridge := MeshInstance3D.new()
		ridge.name = "Truck_Ridge_%s" % str(z)
		var rm := BoxMesh.new()
		rm.size = Vector3(1.62, 0.08, 0.04)
		ridge.mesh = rm
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.28, 0.30, 0.26, 1.0)
		ridge.material_override = rmat
		ridge.position = Vector3(0, 0.95, z)
		add_child(ridge)

	# Tailgate
	var tail := MeshInstance3D.new()
	tail.name = "Truck_Tail"
	var tm := BoxMesh.new()
	tm.size = Vector3(1.55, 1.25, 0.08)
	tail.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.20, 0.22, 0.20, 1.0)
	tail.material_override = tmat
	tail.position = Vector3(0, 0.85, -2.08)
	add_child(tail)

	# Wheels — 6 wheels 3 axles
	var wheel_offsets = [
		Vector3(-0.75, 0.28, 1.0), Vector3(0.75, 0.28, 1.0),
		Vector3(-0.75, 0.28, -0.1), Vector3(0.75, 0.28, -0.1),
		Vector3(-0.75, 0.28, -1.2), Vector3(0.75, 0.28, -1.2),
	]
	for i in wheel_offsets.size():
		var wpos = wheel_offsets[i]
		var w := MeshInstance3D.new()
		w.name = "Truck_Wheel_%d" % i
		var wm := CylinderMesh.new()
		wm.top_radius = 0.28
		wm.bottom_radius = 0.28
		wm.height = 0.18
		w.mesh = wm
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.08, 0.08, 0.09, 1.0)
		wmat.roughness = 0.95
		w.material_override = wmat
		w.rotation_degrees = Vector3(0, 0, 90)
		w.position = wpos
		add_child(w)
		# Hub
		var hub := MeshInstance3D.new()
		hub.name = "Hub_%d" % i
		var hm := CylinderMesh.new()
		hm.top_radius = 0.1
		hm.bottom_radius = 0.1
		hm.height = 0.19
		hub.mesh = hm
		var hmat := StandardMaterial3D.new()
		hmat.albedo_color = Color(0.22, 0.22, 0.22, 1.0)
		hub.material_override = hmat
		hub.rotation_degrees = Vector3(0, 0, 90)
		hub.position = wpos
		add_child(hub)

	# Collision
	var col := get_node_or_null("CollisionShape3D")
	if col == null:
		col = CollisionShape3D.new()
		col.name = "CollisionShape3D"
		add_child(col)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 1.4, 3.4)
	col.shape = shape
	col.position = Vector3(0, 0.7, -0.1)

	# Convoy marking — stenciled number
	var mark := Label3D.new()
	mark.name = "Mark"
	mark.text = "CONVOY %02d" % (truck_index + 1)
	mark.font_size = 24
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.outline_size = 6
	mark.outline_modulate = Color.BLACK
	mark.modulate = Color(0.92, 0.92, 0.92, 1.0)
	mark.position = Vector3(0, 1.9, -0.7)
	add_child(mark)

func _setup_hp() -> void:
	# Link to central state: max scales with truck count
	var truck_count := _get_truck_count()
	max_hp = GlobalData.board.convoy_hp_max / maxf(truck_count, 1)
	# Ensure central HP is sane
	if GlobalData.board.convoy_hp > GlobalData.board.convoy_hp_max:
		GlobalData.board.convoy_hp = GlobalData.board.convoy_hp_max

func _get_truck_count() -> int:
	if HangarManager:
		var fleet := HangarManager.get_fleet_size()
		return clampi(int(ceil(float(fleet) / 2.0)), 1, 3)
	var mechs := GlobalData.hangar.hangar_mechs.size() if GlobalData.hangar else 1
	return clampi(int(ceil(float(mechs) / 2.0)), 1, 3)

func _setup_billboard() -> void:
	_billboard = Control.new()
	_billboard.name = "HPBillboard"
	# Use Label3D for HP instead of ProgressBar (no Control inside 3D easily)
	_hp_label = Label3D.new()
	_hp_label.name = "HPLabel"
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_label.no_depth_test = true
	_hp_label.font_size = 28
	_hp_label.outline_size = 8
	_hp_label.outline_modulate = Color.BLACK
	_hp_label.position = Vector3(0, 2.6, 0)
	add_child(_hp_label)

func _setup_smoke() -> void:
	# Black smoke column — visible when breakdown or damaged
	_smoke_mesh = MeshInstance3D.new()
	_smoke_mesh.name = "SmokeMesh"
	var sm := CylinderMesh.new()
	sm.top_radius = 0.35
	sm.bottom_radius = 0.55
	sm.height = 3.0
	_smoke_mesh.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.06, 0.06, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_smoke_mesh.material_override = mat
	_smoke_mesh.position = Vector3(0.75, 2.2, 0.9)
	_smoke_mesh.visible = is_breakdown
	add_child(_smoke_mesh)

	# Particle smoke — lightweight GPUParticles
	_smoke = GPUParticles3D.new()
	_smoke.name = "SmokeParticles"
	_smoke.emitting = is_breakdown
	_smoke.amount = 24
	_smoke.lifetime = 2.2
	_smoke.visibility_aabb = AABB(Vector3(-2, 0, -2), Vector3(4, 6, 4))
	var mat2 := ParticleProcessMaterial.new()
	mat2.direction = Vector3(0, 1, 0)
	mat2.initial_velocity_min = 1.2
	mat2.initial_velocity_max = 2.4
	mat2.gravity = Vector3(0, 0.3, 0)
	mat2.scale_min = 0.4
	mat2.scale_max = 0.9
	mat2.color = Color(0.08, 0.08, 0.08, 0.7)
	mat2.angular_velocity_min = -30.0
	mat2.angular_velocity_max = 30.0
	mat2.damping_min = 0.5
	mat2.damping_max = 1.0
	_smoke.process_material = mat2
	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	_smoke.draw_pass_1 = quad
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.10, 0.10, 0.10, 0.65)
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.roughness = 1.0
	pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = pmat
	_smoke.position = Vector3(0.75, 1.4, 0.9)
	add_child(_smoke)

	if is_breakdown:
		_animate_smoke()

func _animate_smoke() -> void:
	if _smoke_mesh == null or not is_inside_tree():
		return
	var t := create_tween().set_loops()
	t.tween_property(_smoke_mesh, "scale", Vector3(1.15, 1.0, 1.15), 0.7).set_trans(Tween.TRANS_SINE)
	t.tween_property(_smoke_mesh, "scale", Vector3(1.0, 1.0, 1.0), 0.7).set_trans(Tween.TRANS_SINE)
	var t2 := create_tween().set_loops()
	t2.tween_property(_smoke_mesh, "position:y", 2.5, 0.9).set_trans(Tween.TRANS_SINE)
	t2.tween_property(_smoke_mesh, "position:y", 2.2, 0.9).set_trans(Tween.TRANS_SINE)

var _damage_cooldown: float = 0.0
func _process(delta: float) -> void:
	_update_visual()
	# Enemies near the truck chip away at convoy HP (defense pressure)
	if GlobalData.board.convoy_defense_active and is_inside_tree():
		_damage_cooldown -= delta
		if _damage_cooldown <= 0.0:
			var enemies := get_tree().get_nodes_in_group("enemy")
			var near := 0
			for e in enemies:
				if not is_instance_valid(e) or not e is Node3D or not (e as Node3D).is_inside_tree():
					continue
				var hs = e.get("health_system")
				if hs == null or hs.get("is_destroyed"):
					continue
				var dist := global_position.distance_to((e as Node3D).global_position)
				if dist < 7.0:
					near += 1
			if near > 0:
				# 3 HP per second per nearby enemy, scaled by count
				take_damage(float(near) * 2.0)
				_damage_cooldown = 0.5

func _update_visual() -> void:
	if _hp_label == null or not is_instance_valid(_hp_label):
		return
	var hp_ratio := GlobalData.board.convoy_hp / maxf(GlobalData.board.convoy_hp_max, 1.0)
	var per_truck_hp := GlobalData.board.convoy_hp / maxf(_get_truck_count(), 1)
	var txt := "TRUCK %d  %.0f%%" % [truck_index + 1, per_truck_hp / maxf(max_hp, 1) * 100.0]
	if is_breakdown:
		txt += "  [BREAKDOWN]"
	_hp_label.text = txt
	if hp_ratio < 0.3:
		_hp_label.modulate = Color(0.95, 0.25, 0.22, 1.0)
	elif hp_ratio < 0.6:
		_hp_label.modulate = Color(0.9, 0.75, 0.25, 1.0)
	else:
		_hp_label.modulate = Color(0.92, 0.92, 0.92, 1.0)
	# Smoke intensity based on damage + breakdown
	var show_smoke := is_breakdown or hp_ratio < 0.7
	if _smoke:
		_smoke.emitting = show_smoke
	if _smoke_mesh:
		_smoke_mesh.visible = show_smoke
		var alpha := 0.55 if is_breakdown else remap(hp_ratio, 0.7, 0.3, 0.15, 0.55)
		(_smoke_mesh.material_override as StandardMaterial3D).albedo_color.a = clampf(alpha, 0.0, 0.6)

func take_damage(amount: float) -> void:
	GlobalData.board.convoy_hp = maxf(GlobalData.board.convoy_hp - amount, 0.0)
	truck_damaged.emit(truck_index, GlobalData.board.convoy_hp, GlobalData.board.convoy_hp_max)
	if EventBus.has_signal("convoy_damaged"):
		EventBus.emit_signal("convoy_damaged", GlobalData.board.convoy_hp, GlobalData.board.convoy_hp_max)
	# Hit flash — scale punch (Node3D has no modulate)
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector3(1.05, 0.97, 1.05), 0.07).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(self, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_QUAD)
	if GlobalData.board.convoy_hp <= 0.0:
		_destroy()

func _destroy() -> void:
	truck_destroyed.emit(truck_index)
	if not GlobalData.board.convoy_destroyed:
		GlobalData.board.convoy_destroyed = true
		GlobalData.narrative.mech_less = true
	# Explosion
	if is_inside_tree() and get_tree().current_scene.has_node("EffectManager"):
		var eff = get_tree().current_scene.get_node("EffectManager")
		if eff and eff.has_method("spawn_explosion"):
			eff.spawn_explosion(global_position + Vector3(0, 1.0, 0), 3.0)
	visible = false
	# Keep collision off
	var col = get_node_or_null("CollisionShape3D")
	if col:
		col.disabled = true
	await get_tree().create_timer(0.4).timeout
	queue_free()

func set_breakdown(active: bool) -> void:
	is_breakdown = active
	if _smoke:
		_smoke.emitting = active
	if _smoke_mesh:
		_smoke_mesh.visible = active
		if active:
			_animate_smoke()
	_update_visual()
