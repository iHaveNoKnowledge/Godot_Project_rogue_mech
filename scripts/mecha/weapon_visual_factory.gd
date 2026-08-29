class_name WeaponVisualFactory
extends RefCounted

# Shared mount transforms (hangar preview and battle use the same placements).
const HAND_LEFT_POS := Vector3(-0.85, 1.4, 0.4)
const HAND_RIGHT_POS := Vector3(0.85, 1.4, 0.4)
# Back-carry mount sits BEHIND the torso: weapons are sheathed vertically/upright
# over the shoulder (-105° on X points the blade/barrel upward along the back)
# so they never pierce through the chest or torso.
const BACK_Y := 1.85
const BACK_Z := 0.65
const BACK_ROT_DEG := Vector3(-105, 0, 0)
const CARRY_SPREAD := 0.44
const CARRY_OFFSET_STEP := 0.2222


# Hand position in the forearm node's local space (bottom of the forearm mesh).
const HAND_FOREARM_POS := Vector3(0.0, -0.72, 0.0)


# Returns the mount position for a hand ("left"/"right").
static func hand_mount_position(hand: String) -> Vector3:
	return HAND_LEFT_POS if hand == "left" else HAND_RIGHT_POS


## Determines the effective hold stance for a weapon part
static func get_effective_hold_stance(weapon: WeaponPart) -> WeaponPart.HoldStance:
	if weapon == null:
		return WeaponPart.HoldStance.AUTO
	if "hold_stance" in weapon and weapon.hold_stance != WeaponPart.HoldStance.AUTO:
		return weapon.hold_stance

	var w_type = weapon.weapon_type
	var name_lower = weapon.weapon_name.to_lower()

	if w_type == WeaponPart.WeaponType.SHIELD or name_lower.contains("shield") or name_lower.contains("buckler"):
		return WeaponPart.HoldStance.SHIELD_SIDE
	if name_lower.contains("pile") or name_lower.contains("bunker"):
		return WeaponPart.HoldStance.PILE_BUNKER_GRIP
	if w_type == WeaponPart.WeaponType.MELEE or name_lower.contains("blade") or name_lower.contains("sword") or name_lower.contains("mace") or name_lower.contains("knife") or name_lower.contains("axe") or name_lower.contains("katana") or name_lower.contains("saber"):
		return WeaponPart.HoldStance.MELEE_UPRIGHT
	return WeaponPart.HoldStance.RANGED_RIFLE


# Mounts a weapon onto a hand of the mecha. Reuses the existing node (if the
# given hand already has a mount) so swapping does not pile up stale models.
# The weapon is parented to the Forearm* node (when present) so it sits in the
# hand and follows the arm animations instead of floating at a fixed offset.
static func mount_hand(mecha: Node3D, hand: String, weapon: WeaponPart, node_name: String) -> Node3D:
	var side := "Left" if hand == "left" else "Right"
	var forearm := mecha.get_node_or_null("Arm" + side + "/Forearm" + side) as Node3D
	var mount: Node3D = null
	var stance := get_effective_hold_stance(weapon)

	if forearm != null:
		# Free any stale root-anchored mount from a previous version.
		var stale := mecha.get_node_or_null(node_name)
		if stale != null:
			stale.queue_free()
		mount = forearm.get_node_or_null(node_name)
		if mount == null or not mount.is_inside_tree() or mount.is_queued_for_deletion():
			# The old mount is queued for deletion (e.g. hangar unequip called the
			# preview in the same frame): drop it and build a fresh one so the new
			# weapon isn't added to a node that vanishes at the end of the frame.
			if mount != null and mount.is_inside_tree():
				forearm.remove_child(mount)
			mount = Node3D.new()
			mount.name = node_name
			forearm.add_child(mount)

		match stance:
			WeaponPart.HoldStance.MELEE_UPRIGHT:
				mount.position = HAND_FOREARM_POS
				mount.rotation_degrees = Vector3(0.0, 0.0, 0.0) # Upright combat guard pose
			WeaponPart.HoldStance.PILE_BUNKER_GRIP:
				mount.position = HAND_FOREARM_POS
				mount.rotation_degrees = Vector3(-80.0, 0.0, 0.0) # Horizontal underarm thrust
			WeaponPart.HoldStance.FOREARM_MOUNTED:
				mount.position = Vector3(0.0, -0.45, -0.06) # Direct chassis hardpoint on forearm
				mount.rotation_degrees = Vector3(-80.0, 0.0, 0.0)
			WeaponPart.HoldStance.SHIELD_SIDE:
				mount.position = Vector3(-0.20 if hand == "left" else 0.20, -0.45, 0.0)
				mount.rotation_degrees = Vector3(0.0, 0.0, 0.0)
			_: # RANGED_RIFLE
				mount.position = HAND_FOREARM_POS
				mount.rotation_degrees = Vector3(-80.0, 0.0, 0.0)
	else:
		mount = mecha.get_node_or_null(node_name)
		if mount == null or not mount.is_inside_tree() or mount.is_queued_for_deletion():
			if mount != null and mount.is_inside_tree():
				mecha.remove_child(mount)
			mount = Node3D.new()
			mount.name = node_name
			mecha.add_child(mount)
		mount.position = hand_mount_position(hand)
		mount.rotation_degrees = Vector3.ZERO

	for child in mount.get_children():
		child.queue_free()
	if weapon == null:
		return mount
	mount.add_child(build(weapon))
	var dur_ratio: float = _resolve_weapon_durability(weapon)
	apply_durability_wear_to_node(mount, dur_ratio)
	return mount


# Renders back-carried weapons spread horizontally across the back pack. Reuses
# the existing node (if one is mounted) so swapping does not pile up stale models.
static func mount_carry(mecha: Node3D, weapons: Array, node_name: String) -> Node3D:
	var back_mount = mecha.get_node_or_null(node_name)
	if back_mount == null or not back_mount.is_inside_tree() or back_mount.is_queued_for_deletion():
		# Hangar unequip queue_frees the carry mount and refreshes the preview in
		# the same frame: never reuse a node that is about to die (it would take
		# the fresh weapon models with it when the frame ends).
		if back_mount != null and back_mount.is_inside_tree():
			mecha.remove_child(back_mount)
		back_mount = Node3D.new()
		back_mount.name = node_name
		mecha.add_child(back_mount)
	for child in back_mount.get_children():
		child.queue_free()
	if weapons.is_empty():
		return back_mount
	var offset := -((weapons.size() - 1) * CARRY_OFFSET_STEP)
	for weapon in weapons:
		if weapon == null:
			continue
		var wmount := Node3D.new()
		var side_tilt := clampf(-offset * 20.0, -12.0, 12.0)
		wmount.position = Vector3(offset, BACK_Y, BACK_Z)
		wmount.rotation_degrees = Vector3(BACK_ROT_DEG.x, 0.0, side_tilt)
		wmount.add_child(build(weapon))
		var dur_ratio: float = _resolve_weapon_durability(weapon)
		apply_durability_wear_to_node(wmount, dur_ratio)
		back_mount.add_child(wmount)
		offset += CARRY_SPREAD
	return back_mount


static func _resolve_weapon_durability(weapon: Variant) -> float:
	if weapon == null:
		return 1.0
	if weapon is Dictionary:
		return GlobalData.get_durability_ratio(weapon) if GlobalData else float(weapon.get("durability", 1.0))
	if (weapon is WeaponPart or weapon is Resource) and GlobalData and GlobalData.weapons:
		for item in GlobalData.weapons.weapon_inventory:
			if item is Dictionary and (item.get("path") == weapon.resource_path or item.get("name") == weapon.get("weapon_name")):
				return GlobalData.get_durability_ratio(item)
	return 1.0


## Applies procedural field-repair and battle wear overlay to weapon mesh instances.
static func apply_durability_wear_to_node(node: Node3D, dur_ratio: float) -> void:
	if node == null or dur_ratio >= 0.999:
		return
	var wear := clampf(1.0 - dur_ratio, 0.0, 1.0)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/armor_crack.gdshader")
	mat.set_shader_parameter("wear_amount", wear)
	mat.set_shader_parameter("damage_amount", 0.0)
	mat.set_shader_parameter("noise_offset", Vector3(randf_range(-50.0, 50.0), randf_range(-50.0, 50.0), randf_range(-50.0, 50.0)))
	_apply_material_overlay_recursive(node, mat)


static func _apply_material_overlay_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		node.material_overlay = mat
	for child in node.get_children():
		_apply_material_overlay_recursive(child, mat)


# ---------------------------------------------------------------------------
# Material helpers (Master PBR detail)
# ---------------------------------------------------------------------------
const MASTER_PBR_SHADER: Shader = preload("res://shaders/mecha_master_pbr.gdshader")

static func _mat(albedo: Color, metallic: float, roughness: float, emission: Color = Color.TRANSPARENT, emission_energy: float = 0.0) -> Material:
	var m := ShaderMaterial.new()
	m.shader = MASTER_PBR_SHADER
	m.set_shader_parameter("primary_color", albedo)
	m.set_shader_parameter("trim_color", albedo.darkened(0.35))
	m.set_shader_parameter("metallic", metallic)
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("panel_grid_scale", 8.0 if metallic > 0.5 else 0.0)
	m.set_shader_parameter("panel_line_depth", 0.45)
	m.set_shader_parameter("edge_wear", 0.15 if metallic > 0.5 else 0.05)
	if emission != Color.TRANSPARENT and emission_energy > 0.0:
		m.set_shader_parameter("emission_color", emission)
		m.set_shader_parameter("emission_energy", emission_energy)
	return m


static func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func _add_cyl(parent: Node3D, top_r: float, bottom_r: float, height: float, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func _add_sphere(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## Builds a shared weapon model (Node3D) for a WeaponPart resource.
## Used by BOTH the Hangar preview and the battle WeaponManager so the weapon
## shown in the garage is the exact same model that appears on the mech's hands.
## Every built model carries a "Muzzle" child marker at its barrel tip, placed
## per weapon type — projectile spawn points, muzzle flashes and jam sparks all
## anchor there instead of a fixed hip offset.
static func build(weapon: WeaponPart) -> Node3D:
	var mount := Node3D.new()
	if weapon == null:
		return mount

	if weapon.weapon_name.to_lower().contains("pilot") or (weapon.resource_path != "" and weapon.resource_path.contains("pilot")):
		return build_pilot_weapon(weapon)

	if weapon.mesh_scene:
		var inst: Node3D = weapon.mesh_scene.instantiate()
		mount.add_child(inst)
		# Authored models may ship their own Muzzle node; anything else gets a
		# sensible generic barrel-tip fallback so effects never fire from the hip.
		if find_muzzle_node(inst) == null:
			var fallback := Node3D.new()
			fallback.name = "Muzzle"
			fallback.position = Vector3(0, 0, -1.3)
			inst.add_child(fallback)
		return mount

	var w_type = weapon.weapon_type
	var name_lower = weapon.weapon_name.to_lower()
	var muzzle_local := Vector3(0, 0, -1.27)

	# Common material palette ------------------------------------------------
	var mat_gunmetal := _mat(Color(0.19, 0.20, 0.23), 0.85, 0.35)
	var mat_dark_steel := _mat(Color(0.15, 0.16, 0.18), 0.88, 0.30)
	var mat_silver := _mat(Color(0.78, 0.80, 0.84), 0.92, 0.22)
	var mat_black_polymer := _mat(Color(0.09, 0.09, 0.10), 0.10, 0.75)
	var mat_brown_stock := _mat(Color(0.38, 0.26, 0.16), 0.05, 0.65)
	var mat_energy_blue := _mat(Color(0.16, 0.42, 0.78), 0.80, 0.25, Color(0.20, 0.60, 1.0), 2.2)
	var mat_energy_cyan := _mat(Color(0.22, 0.55, 0.70), 0.75, 0.28, Color(0.30, 0.85, 1.0), 1.8)
	var mat_heat_orange := _mat(Color(0.85, 0.38, 0.12), 0.75, 0.30, Color(1.0, 0.45, 0.10), 2.0)
	var mat_copper := _mat(Color(0.72, 0.38, 0.20), 0.88, 0.32)
	var mat_brass := _mat(Color(0.78, 0.66, 0.30), 0.90, 0.25)
	var mat_olive := _mat(Color(0.31, 0.32, 0.28), 0.65, 0.45)
	var mat_hazard_yellow := _mat(Color(0.92, 0.78, 0.12), 0.20, 0.60)
	var mat_rubber := _mat(Color(0.08, 0.08, 0.08), 0.02, 0.85)

	# -----------------------------------------------------------------------
	# 1) PILE BUNKER — pneumatic spike driver
	# -----------------------------------------------------------------------
	if name_lower.contains("pile") or name_lower.contains("bunker"):
		# Main piston chamber block
		_add_box(mount, Vector3(0.34, 0.30, 1.10), Vector3(0.0, -0.14, -0.02), _mat(Color(0.22, 0.24, 0.26), 0.82, 0.35))
		# Top rail housing
		_add_box(mount, Vector3(0.30, 0.08, 1.05), Vector3(0.0, 0.04, -0.04), mat_dark_steel)
		# Side guide rails (gunmetal rails running full length)
		_add_box(mount, Vector3(0.04, 0.06, 1.18), Vector3(0.17, -0.08, -0.04), mat_silver)
		_add_box(mount, Vector3(0.04, 0.06, 1.18), Vector3(-0.17, -0.08, -0.04), mat_silver)
		# Rear hydraulic accumulator (fat cylinder)
		_add_cyl(mount, 0.11, 0.11, 0.26, Vector3(0.0, -0.14, 0.42), _mat(Color(0.18, 0.18, 0.20), 0.85, 0.30), Vector3(90, 0, 0))
		_add_cyl(mount, 0.09, 0.09, 0.04, Vector3(0.0, -0.14, 0.56), mat_silver, Vector3(90, 0, 0))
		# Side pneumatic cylinders
		_add_cyl(mount, 0.045, 0.045, 0.55, Vector3(0.12, -0.14, 0.18), _mat(Color(0.55, 0.55, 0.58), 0.80, 0.30), Vector3(90, 0, 0))
		_add_cyl(mount, 0.045, 0.045, 0.55, Vector3(-0.12, -0.14, 0.18), _mat(Color(0.55, 0.55, 0.58), 0.80, 0.30), Vector3(90, 0, 0))
		# Handle connector rising to hand
		_add_cyl(mount, 0.05, 0.05, 0.20, Vector3(0.0, -0.04, 0.22), mat_black_polymer, Vector3(0, 0, 0))
		_add_box(mount, Vector3(0.10, 0.06, 0.12), Vector3(0.0, 0.04, 0.24), mat_black_polymer)
		# Warning hazard stripes on sides (yellow/black)
		_add_box(mount, Vector3(0.352, 0.04, 0.12), Vector3(0.0, 0.02, -0.22), mat_hazard_yellow)
		_add_box(mount, Vector3(0.352, 0.04, 0.12), Vector3(0.0, 0.02, -0.42), mat_hazard_yellow)
		# Exhaust vents (three slits on top)
		for i in range(3):
			_add_box(mount, Vector3(0.10, 0.015, 0.04), Vector3(0.0, 0.09, -0.08 - float(i) * 0.18), _mat(Color(0.02, 0.02, 0.02), 0.10, 0.90))
		# Forward kinetic spike (tapered piston)
		var spike_mat := _mat(Color(0.86, 0.90, 0.95), 0.95, 0.18)
		_add_cyl(mount, 0.03, 0.11, 1.25, Vector3(0.0, -0.14, -0.92), spike_mat, Vector3(90, 0, 0))
		_add_cyl(mount, 0.015, 0.03, 0.18, Vector3(0.0, -0.14, -1.64), spike_mat, Vector3(90, 0, 0))
		# Muzzle collar
		_add_cyl(mount, 0.13, 0.13, 0.08, Vector3(0.0, -0.14, -0.60), mat_silver, Vector3(90, 0, 0))
		muzzle_local = Vector3(0, -0.14, -1.74)

	# -----------------------------------------------------------------------
	# 2) SHIELD — physical plates
	# -----------------------------------------------------------------------
	elif w_type == WeaponPart.WeaponType.SHIELD:
		if name_lower.contains("buckler") or name_lower.contains("light"):
			# High-Tech Military Tactical Deflector Buckler:
			# Angular composite reactive strike plate mounted to forearm hardpoint
			var mat_composite := _mat(Color(0.18, 0.22, 0.28), 0.82, 0.32) # Matte naval graphite
			var mat_ceramic_era := _mat(Color(0.24, 0.28, 0.35), 0.70, 0.45) # Reactive ceramic blocks

			# Main angular deflection plate
			_add_box(mount, Vector3(0.07, 0.68, 0.44), Vector3(0.0, 0.10, 0.0), mat_composite)
			# Top deflection bevel (deflects rounds upward at 32 deg)
			_add_box(mount, Vector3(0.065, 0.22, 0.42), Vector3(0.02, 0.42, 0.0), mat_dark_steel, Vector3(0, 0, 32))
			# Bottom breaching / strike bezel (angled down for melee parry/ram)
			_add_box(mount, Vector3(0.065, 0.22, 0.42), Vector3(0.02, -0.22, 0.0), mat_dark_steel, Vector3(0, 0, -32))
			# Twin Modular ERA (Explosive Reactive Armor) Ceramic Tiles on front face
			_add_box(mount, Vector3(0.035, 0.24, 0.16), Vector3(0.05, 0.18, -0.10), mat_ceramic_era)
			_add_box(mount, Vector3(0.035, 0.24, 0.16), Vector3(0.05, 0.18, 0.10), mat_ceramic_era)
			_add_box(mount, Vector3(0.035, 0.20, 0.34), Vector3(0.05, -0.06, 0.0), mat_ceramic_era)
			# Titanium reinforcement spine
			_add_box(mount, Vector3(0.045, 0.62, 0.05), Vector3(0.055, 0.10, 0.0), mat_silver)
			# Hydraulic hardpoint mounting bracket (connects to forearm)
			_add_box(mount, Vector3(0.09, 0.14, 0.18), Vector3(-0.06, 0.10, 0.0), mat_dark_steel)
			_add_cyl(mount, 0.022, 0.022, 0.14, Vector3(-0.06, 0.18, 0.06), mat_silver, Vector3(90, 0, 0))
			_add_cyl(mount, 0.022, 0.022, 0.14, Vector3(-0.06, 0.02, 0.06), mat_silver, Vector3(90, 0, 0))
			# Active Deflector / Shield Type Emitter Strip (Tactical Glowing LED bar)
			var lamp_col := Color(1.0, 0.45, 0.15) if weapon.get_shield_type() == "heat" else Color(0.25, 0.8, 1.0) if weapon.get_shield_type() == "pierce" else Color(0.35, 0.95, 0.45)
			_add_box(mount, Vector3(0.015, 0.46, 0.025), Vector3(0.065, 0.10, 0.0), _mat(lamp_col, 0.20, 0.20, lamp_col, 3.5))
			# Status sensor indicator dot
			_add_sphere(mount, 0.018, 0.018, Vector3(0.06, 0.38, -0.14), _mat(lamp_col, 0.20, 0.20, lamp_col, 4.0))
			muzzle_local = Vector3(0.06, 0.10, 0.0)
		elif name_lower.contains("heavy"):
			# Tower shield — tall with viewport slit
			_add_box(mount, Vector3(0.08, 1.45, 0.82), Vector3(0.0, 0.10, 0.0), _mat(Color(0.20, 0.32, 0.48), 0.78, 0.38))
			# Reinforced frame rim (thickness)
			_add_box(mount, Vector3(0.10, 1.47, 0.04), Vector3(0.0, 0.10, 0.40), mat_dark_steel)
			_add_box(mount, Vector3(0.10, 1.47, 0.04), Vector3(0.0, 0.10, -0.40), mat_dark_steel)
			_add_box(mount, Vector3(0.10, 0.04, 0.84), Vector3(0.0, 0.82, 0.0), mat_dark_steel)
			_add_box(mount, Vector3(0.10, 0.04, 0.84), Vector3(0.0, -0.62, 0.0), mat_dark_steel)
			# Vertical spine ridge
			_add_box(mount, Vector3(0.04, 1.30, 0.06), Vector3(0.05, 0.10, 0.0), mat_silver)
			# Viewport slit (dark horizontal)
			_add_box(mount, Vector3(0.09, 0.08, 0.28), Vector3(0.05, 0.42, 0.0), _mat(Color(0.02, 0.04, 0.06), 0.10, 0.90, Color(0.10, 0.35, 0.55), 1.2))
			# Rivet lines down spine
			for i in range(5):
				_add_sphere(mount, 0.02, 0.02, Vector3(0.06, 0.58 - float(i) * 0.32, 0.0), mat_silver)
			# Rear handles (top grip + forearm strap)
			_add_box(mount, Vector3(0.05, 0.26, 0.05), Vector3(-0.07, 0.30, 0.0), mat_black_polymer)
			_add_box(mount, Vector3(0.04, 0.40, 0.06), Vector3(-0.07, -0.10, 0.0), mat_brown_stock)
			muzzle_local = Vector3(0.06, 0.10, 0.0)
		else:
			# Standard medium shield
			_add_box(mount, Vector3(0.08, 1.25, 0.68), Vector3(0.0, 0.14, 0.0), _mat(Color(0.21, 0.34, 0.50), 0.78, 0.36))
			_add_box(mount, Vector3(0.10, 1.27, 0.03), Vector3(0.0, 0.14, 0.34), mat_dark_steel)
			_add_box(mount, Vector3(0.10, 1.27, 0.03), Vector3(0.0, 0.14, -0.34), mat_dark_steel)
			_add_box(mount, Vector3(0.10, 0.03, 0.70), Vector3(0.0, 0.77, 0.0), mat_dark_steel)
			_add_box(mount, Vector3(0.10, 0.03, 0.70), Vector3(0.0, -0.49, 0.0), mat_dark_steel)
			# Chevron emblem
			_add_box(mount, Vector3(0.015, 0.18, 0.22), Vector3(0.05, 0.22, 0.0), _mat(Color(0.85, 0.85, 0.88), 0.90, 0.20), Vector3(0, 0, 28))
			_add_box(mount, Vector3(0.015, 0.18, 0.22), Vector3(0.05, 0.22, 0.0), _mat(Color(0.85, 0.85, 0.88), 0.90, 0.20), Vector3(0, 0, -28))
			# Central boss
			_add_sphere(mount, 0.09, 0.09, Vector3(0.06, 0.16, 0.0), mat_silver)
			_add_sphere(mount, 0.02, 0.02, Vector3(0.09, 0.16, 0.0), _mat(Color(0.9, 0.2, 0.15), 0.40, 0.30, Color(1.0, 0.25, 0.15), 2.5))
			# Grip
			_add_box(mount, Vector3(0.05, 0.24, 0.04), Vector3(-0.06, 0.18, 0.0), mat_black_polymer)
			muzzle_local = Vector3(0.06, 0.14, 0.0)

	# -----------------------------------------------------------------------
	# 3) MELEE — blades, knives, maces
	# -----------------------------------------------------------------------
	elif w_type == WeaponPart.WeaponType.MELEE or name_lower.contains("blade") or name_lower.contains("knife") or name_lower.contains("mace") or name_lower.contains("sword") or name_lower.contains("katana") or name_lower.contains("saber"):
		if name_lower.contains("mace"):
			# Heavy spiked mace head
			_add_box(mount, Vector3(0.34, 0.34, 0.38), Vector3(0.0, 0.0, -0.72), _mat(Color(0.28, 0.28, 0.32), 0.88, 0.28))
			# Head spikes (6 radial)
			for i in range(6):
				var ang := float(i) / 6.0 * TAU
				var sx := 0.16 * cos(ang)
				var sy := 0.16 * sin(ang)
				_add_cyl(mount, 0.015, 0.045, 0.16, Vector3(sx, sy, -0.72), mat_silver, Vector3(0, 0, 0) if i % 2 == 0 else Vector3(90, 0, 0))
				# Spike tip cone as tiny cylinder
				_add_cyl(mount, 0.005, 0.018, 0.06, Vector3(sx * 1.25, sy * 1.25, -0.72), mat_silver, Vector3(0, 0, 0))
			# Shaft
			_add_cyl(mount, 0.055, 0.055, 1.15, Vector3(0.0, 0.0, -0.18), _mat(Color(0.17, 0.17, 0.19), 0.70, 0.40), Vector3(90, 0, 0))
			# Wrapped grip section
			for i in range(4):
				_add_cyl(mount, 0.062, 0.062, 0.025, Vector3(0.0, 0.0, 0.22 + float(i) * 0.04), mat_brown_stock, Vector3(90, 0, 0))
			# Pommel ring
			_add_cyl(mount, 0.07, 0.07, 0.03, Vector3(0.0, 0.0, 0.42), mat_silver, Vector3(90, 0, 0))
			# Cross guard plate below head
			_add_box(mount, Vector3(0.12, 0.12, 0.04), Vector3(0.0, 0.0, -0.50), mat_dark_steel)
			muzzle_local = Vector3(0, 0, -0.98)
		elif name_lower.contains("knife"):
			# Combat knife — compact tactical blade
			_add_box(mount, Vector3(0.06, 0.025, 0.38), Vector3(0.0, 0.0, -0.22), mat_silver)
			# Fuller groove
			_add_box(mount, Vector3(0.015, 0.008, 0.26), Vector3(0.0, 0.015, -0.22), _mat(Color(0.45, 0.48, 0.52), 0.88, 0.25))
			# Blade edge bevel
			_add_box(mount, Vector3(0.02, 0.018, 0.38), Vector3(0.0, -0.02, -0.22), _mat(Color(0.88, 0.88, 0.90), 0.92, 0.15))
			# Crossguard
			_add_box(mount, Vector3(0.14, 0.04, 0.03), Vector3(0.0, 0.0, -0.02), mat_dark_steel)
			# Grip with finger grooves (polymer)
			_add_cyl(mount, 0.045, 0.045, 0.22, Vector3(0.0, 0.0, 0.14), mat_black_polymer, Vector3(90, 0, 0))
			_add_cyl(mount, 0.048, 0.048, 0.02, Vector3(0.0, 0.0, 0.08), mat_dark_steel, Vector3(90, 0, 0))
			_add_cyl(mount, 0.048, 0.048, 0.02, Vector3(0.0, 0.0, 0.14), mat_dark_steel, Vector3(90, 0, 0))
			_add_cyl(mount, 0.048, 0.048, 0.02, Vector3(0.0, 0.0, 0.20), mat_dark_steel, Vector3(90, 0, 0))
			# Pommel
			_add_cyl(mount, 0.04, 0.04, 0.02, Vector3(0.0, 0.0, 0.26), mat_silver, Vector3(90, 0, 0))
			# Sheath clip detail
			_add_box(mount, Vector3(0.04, 0.03, 0.08), Vector3(0.04, 0.0, 0.06), mat_dark_steel)
			muzzle_local = Vector3(0, 0, -0.42)
		else:
			# Heat Blade / Katana — long thermo blade with crossguard and glowing edge
			# Scabbard mount plate
			# Blade spine (thick back)
			_add_box(mount, Vector3(0.045, 0.10, 1.35), Vector3(0.0, 0.03, -0.64), _mat(Color(0.78, 0.80, 0.84), 0.92, 0.22))
			# Glowing thermal edge (thin strip along the bottom edge, emissive)
			_add_box(mount, Vector3(0.020, 0.16, 1.32), Vector3(0.0, -0.03, -0.64), mat_heat_orange)
			# Fuller / blood groove down the center
			_add_box(mount, Vector3(0.010, 0.04, 0.90), Vector3(0.0, 0.03, -0.62), _mat(Color(0.30, 0.32, 0.35), 0.80, 0.30))
			# Blade tip chamfer (small wedge at tip)
			_add_box(mount, Vector3(0.03, 0.08, 0.12), Vector3(0.0, 0.015, -1.38), _mat(Color(0.82, 0.84, 0.88), 0.90, 0.20), Vector3(0, 15, 0))
			# Tsuba crossguard — ornate
			_add_box(mount, Vector3(0.26, 0.10, 0.08), Vector3(0.0, 0.02, -0.04), mat_dark_steel)
			_add_box(mount, Vector3(0.18, 0.04, 0.06), Vector3(0.0, 0.02, -0.04), mat_brass)
			# Guard side vents (tiny slits)
			_add_box(mount, Vector3(0.08, 0.015, 0.015), Vector3(0.07, 0.02, -0.04), _mat(Color(0.02, 0.02, 0.02), 0.10, 0.90))
			_add_box(mount, Vector3(0.08, 0.015, 0.015), Vector3(-0.07, 0.02, -0.04), _mat(Color(0.02, 0.02, 0.02), 0.10, 0.90))
			# Handle wrap (tsuka) — diamond pattern via alternating boxes
			var handle_len := 0.32
			_add_cyl(mount, 0.055, 0.055, handle_len, Vector3(0.0, 0.02, 0.18), mat_black_polymer, Vector3(90, 0, 0))
			for i in range(5):
				var z := 0.06 + float(i) * 0.05
				_add_box(mount, Vector3(0.07, 0.015, 0.025), Vector3(0.0, 0.055, z), mat_brown_stock)
			# Pommel cap (kashira)
			_add_cyl(mount, 0.06, 0.06, 0.025, Vector3(0.0, 0.02, 0.36), mat_brass, Vector3(90, 0, 0))
			# Emitter collar at blade base (heat vent)
			_add_box(mount, Vector3(0.10, 0.06, 0.05), Vector3(0.0, 0.03, -0.09), _mat(Color(0.22, 0.24, 0.26), 0.85, 0.30, Color(1.0, 0.40, 0.10), 1.5))
			muzzle_local = Vector3(0, 0.015, -1.44)

	# -----------------------------------------------------------------------
	# 4) RAILGUN — hypervelocity accelerator
	# -----------------------------------------------------------------------
	elif w_type == WeaponPart.WeaponType.RAILGUN:
		# Receiver bulk
		_add_box(mount, Vector3(0.32, 0.30, 0.70), Vector3(0.0, 0.10, -0.16), mat_dark_steel)
		# Top rail housing spine
		_add_box(mount, Vector3(0.08, 0.06, 0.68), Vector3(0.0, 0.27, -0.16), mat_silver)
		# Accelerator rails (twin rails extending forward)
		_add_box(mount, Vector3(0.045, 0.10, 1.45), Vector3(0.11, 0.10, -1.02), mat_silver)
		_add_box(mount, Vector3(0.045, 0.10, 1.45), Vector3(-0.11, 0.10, -1.02), mat_silver)
		# Rail inner glow channel (energy line between rails)
		_add_box(mount, Vector3(0.04, 0.04, 1.42), Vector3(0.0, 0.10, -1.02), _mat(Color(0.12, 0.35, 0.85), 0.50, 0.30, Color(0.30, 0.70, 1.0), 3.0))
		# Insulator rings (ceramic spacers every ~0.32m, 4 rings)
		for i in range(4):
			var z := -0.42 - float(i) * 0.32
			_add_box(mount, Vector3(0.30, 0.26, 0.06), Vector3(0.0, 0.10, z), _mat(Color(0.88, 0.88, 0.86), 0.15, 0.55))
			_add_cyl(mount, 0.155, 0.155, 0.04, Vector3(0.0, 0.10, z), mat_copper, Vector3(90, 0, 0))
		# Copper charging coils around rear receiver
		_add_cyl(mount, 0.17, 0.17, 0.08, Vector3(0.0, 0.10, -0.05), mat_copper, Vector3(90, 0, 0))
		_add_cyl(mount, 0.17, 0.17, 0.08, Vector3(0.0, 0.10, 0.12), mat_copper, Vector3(90, 0, 0))
		# Power capacitor bank under receiver (with blue vents)
		_add_box(mount, Vector3(0.30, 0.14, 0.36), Vector3(0.0, -0.08, -0.12), _mat(Color(0.14, 0.16, 0.20), 0.80, 0.35))
		for i in range(3):
			_add_box(mount, Vector3(0.06, 0.015, 0.20), Vector3(-0.08 + float(i) * 0.08, -0.03, -0.12), _mat(Color(0.20, 0.60, 1.0), 0.30, 0.30, Color(0.20, 0.60, 1.0), 2.0))
		# Stock — heavy recoil stock with pad
		_add_box(mount, Vector3(0.22, 0.14, 0.38), Vector3(0.0, 0.04, 0.40), mat_dark_steel)
		_add_box(mount, Vector3(0.20, 0.16, 0.04), Vector3(0.0, 0.04, 0.60), mat_rubber)
		# Grip
		_add_box(mount, Vector3(0.08, 0.18, 0.09), Vector3(0.0, -0.06, 0.18), mat_black_polymer, Vector3(-12, 0, 0))
		# Forward grip / bipod mount under rails
		_add_box(mount, Vector3(0.06, 0.08, 0.14), Vector3(0.0, -0.04, -0.38), mat_black_polymer)
		# Muzzle brake — four-port compensator
		_add_box(mount, Vector3(0.20, 0.20, 0.16), Vector3(0.0, 0.10, -1.78), mat_dark_steel)
		_add_box(mount, Vector3(0.24, 0.04, 0.10), Vector3(0.0, 0.10, -1.78), _mat(Color(0.02, 0.02, 0.02), 0.10, 0.90))
		muzzle_local = Vector3(0, 0.10, -1.88)

	# -----------------------------------------------------------------------
	# 5) MINIGUN / GATLING — rotary cannons
	# -----------------------------------------------------------------------
	elif w_type == WeaponPart.WeaponType.MINIGUN or name_lower.contains("minigun") or name_lower.contains("gatling"):
		var is_minigun := name_lower.contains("minigun")
		# Motor housing block behind barrels
		_add_box(mount, Vector3(0.30, 0.28, 0.42), Vector3(0.0, 0.08, -0.08), mat_gunmetal)
		# Motor detail — side motor cylinder
		_add_cyl(mount, 0.10, 0.10, 0.12, Vector3(0.16, 0.08, -0.08), _mat(Color(0.25, 0.25, 0.28), 0.85, 0.30), Vector3(0, 0, 90))
		# Top feed cover
		_add_box(mount, Vector3(0.18, 0.06, 0.30), Vector3(0.0, 0.23, -0.10), mat_dark_steel)
		# 6 rotating barrels in a circle (radius 0.09)
		var barrel_len := 0.98 if is_minigun else 0.82
		var barrel_r := 0.028 if is_minigun else 0.032
		var barrel_z := -0.68 if is_minigun else -0.58
		for i in range(6):
			var ang := float(i) / 6.0 * TAU
			var bx := 0.09 * cos(ang)
			var by := 0.09 * sin(ang)
			_add_cyl(mount, barrel_r, barrel_r, barrel_len, Vector3(bx, 0.08 + by, barrel_z), mat_silver, Vector3(90, 0, 0))
		# Central hub / axle
		_add_cyl(mount, 0.07, 0.07, 0.08, Vector3(0.0, 0.08, -0.28), mat_dark_steel, Vector3(90, 0, 0))
		_add_cyl(mount, 0.09, 0.09, 0.04, Vector3(0.0, 0.08, -0.40), _mat(Color(0.18, 0.18, 0.20), 0.85, 0.30), Vector3(90, 0, 0))
		# Ammo drum / belt box on side
		if is_minigun:
			_add_cyl(mount, 0.18, 0.18, 0.14, Vector3(0.0, -0.10, 0.02), _mat(Color(0.26, 0.26, 0.28), 0.80, 0.35), Vector3(0, 0, 90))
			_add_box(mount, Vector3(0.08, 0.04, 0.22), Vector3(0.10, 0.00, -0.06), _mat(Color(0.45, 0.38, 0.18), 0.60, 0.40))
		else:
			_add_box(mount, Vector3(0.22, 0.16, 0.20), Vector3(0.18, -0.02, 0.02), _mat(Color(0.28, 0.28, 0.30), 0.80, 0.30))
			_add_box(mount, Vector3(0.04, 0.04, 0.18), Vector3(0.08, 0.04, -0.08), _mat(Color(0.55, 0.48, 0.22), 0.60, 0.40))
		# Feed chute
		_add_box(mount, Vector3(0.06, 0.06, 0.22), Vector3(0.09, 0.04, -0.10), mat_dark_steel)
		# Grip + trigger group
		_add_box(mount, Vector3(0.08, 0.16, 0.09), Vector3(0.0, -0.06, 0.12), mat_black_polymer, Vector3(-10, 0, 0))
		# Stock brace for minigun
		if is_minigun:
			_add_box(mount, Vector3(0.16, 0.08, 0.28), Vector3(0.0, 0.02, 0.32), mat_dark_steel)
		muzzle_local = Vector3(0, 0.08, barrel_z - barrel_len * 0.5 - 0.05)

	# -----------------------------------------------------------------------
	# 6) BEAM RIFLE family — energy rifles
	# -----------------------------------------------------------------------
	elif w_type == WeaponPart.WeaponType.BEAM_RIFLE:
		if name_lower.contains("sniper"):
			# Long precision sniper
			_add_box(mount, Vector3(0.20, 0.18, 0.62), Vector3(0.0, 0.09, -0.18), mat_gunmetal)
			# Extended barrel with heat shroud (long slender)
			_add_cyl(mount, 0.048, 0.052, 1.55, Vector3(0.0, 0.09, -1.08), mat_silver, Vector3(90, 0, 0))
			# Barrel shroud with cooling vents (outer sleeve with cutouts)
			_add_cyl(mount, 0.065, 0.065, 1.20, Vector3(0.0, 0.09, -1.00), _mat(Color(0.16, 0.18, 0.22), 0.75, 0.40), Vector3(90, 0, 0))
			for i in range(5):
				_add_box(mount, Vector3(0.08, 0.015, 0.045), Vector3(0.0, 0.14, -0.52 - float(i) * 0.18), _mat(Color(0.02, 0.02, 0.02), 0.10, 0.90))
			# Large scope (3-9x) on top rail
			_add_box(mount, Vector3(0.04, 0.03, 0.55), Vector3(0.0, 0.20, -0.14), mat_dark_steel)
			_add_cyl(mount, 0.038, 0.038, 0.48, Vector3(0.0, 0.24, -0.16), mat_dark_steel, Vector3(90, 0, 0))
			_add_cyl(mount, 0.028, 0.045, 0.08, Vector3(0.0, 0.24, -0.40), _mat(Color(0.10, 0.30, 0.55), 0.80, 0.20, Color(0.20, 0.55, 1.0), 1.5), Vector3(90, 0, 0))
			_add_cyl(mount, 0.035, 0.035, 0.06, Vector3(0.0, 0.24, 0.08), _mat(Color(0.08, 0.08, 0.08), 0.10, 0.85), Vector3(90, 0, 0))
			# Bipod folded under barrel
			_add_box(mount, Vector3(0.03, 0.14, 0.03), Vector3(0.06, -0.04, -0.62), mat_dark_steel, Vector3(22, 0, 0))
			_add_box(mount, Vector3(0.03, 0.14, 0.03), Vector3(-0.06, -0.04, -0.62), mat_dark_steel, Vector3(-22, 0, 0))
			# Energy cell magazine (glowing)
			_add_box(mount, Vector3(0.09, 0.14, 0.16), Vector3(0.0, -0.06, -0.18), mat_energy_blue)
			_add_box(mount, Vector3(0.015, 0.10, 0.10), Vector3(0.05, -0.06, -0.18), _mat(Color(0.40, 0.80, 1.0), 0.30, 0.30, Color(0.40, 0.80, 1.0), 2.5))
			# Stock — precision adjustable
			_add_box(mount, Vector3(0.16, 0.10, 0.42), Vector3(0.0, 0.07, 0.38), mat_dark_steel)
			_add_box(mount, Vector3(0.14, 0.12, 0.05), Vector3(0.0, 0.07, 0.60), mat_rubber)
			_add_box(mount, Vector3(0.10, 0.06, 0.12), Vector3(0.0, 0.00, 0.34), mat_black_polymer)
			# Grip
			_add_box(mount, Vector3(0.07, 0.16, 0.08), Vector3(0.0, -0.06, 0.10), mat_black_polymer, Vector3(-10, 0, 0))
			# Muzzle brake with side ports
			_add_cyl(mount, 0.065, 0.065, 0.10, Vector3(0.0, 0.09, -1.88), mat_dark_steel, Vector3(90, 0, 0))
			_add_box(mount, Vector3(0.09, 0.015, 0.06), Vector3(0.0, 0.09, -1.88), _mat(Color(0.02, 0.02, 0.02), 0.10, 0.90))
			muzzle_local = Vector3(0, 0.09, -1.94)
		elif name_lower.contains("carbine"):
			# Compact carbine — short and handy
			_add_box(mount, Vector3(0.20, 0.16, 0.42), Vector3(0.0, 0.08, -0.12), mat_gunmetal)
			_add_cyl(mount, 0.055, 0.055, 0.72, Vector3(0.0, 0.08, -0.60), mat_silver, Vector3(90, 0, 0))
			_add_cyl(mount, 0.068, 0.068, 0.50, Vector3(0.0, 0.08, -0.58), _mat(Color(0.16, 0.18, 0.22), 0.75, 0.40), Vector3(90, 0, 0))
			# Red dot sight (small)
			_add_box(mount, Vector3(0.05, 0.05, 0.10), Vector3(0.0, 0.17, -0.18), mat_dark_steel)
			_add_box(mount, Vector3(0.02, 0.02, 0.02), Vector3(0.0, 0.185, -0.20), _mat(Color(1.0, 0.15, 0.15), 0.10, 0.30, Color(1.0, 0.20, 0.20), 3.0))
			# Folding wire stock
			_add_box(mount, Vector3(0.12, 0.04, 0.28), Vector3(0.0, 0.06, 0.28), mat_dark_steel)
			_add_cyl(mount, 0.015, 0.015, 0.22, Vector3(0.05, 0.06, 0.36), mat_silver, Vector3(90, 0, 0))
			_add_cyl(mount, 0.015, 0.015, 0.22, Vector3(-0.05, 0.06, 0.36), mat_silver, Vector3(90, 0, 0))
			_add_box(mount, Vector3(0.06, 0.12, 0.12), Vector3(0.0, -0.05, 0.12), mat_black_polymer, Vector3(-12, 0, 0))
			# Short energy mag
			_add_box(mount, Vector3(0.08, 0.10, 0.12), Vector3(0.0, -0.04, -0.14), mat_energy_blue)
			muzzle_local = Vector3(0, 0.08, -0.98)
		elif name_lower.contains("mk2") or name_lower.contains("mk ii") or name_lower.contains("mk-2"):
			# Upgraded Mark II — adds power cell and gold trim
			_add_box(mount, Vector3(0.24, 0.20, 0.62), Vector3(0.0, 0.09, -0.22), mat_gunmetal)
			_add_cyl(mount, 0.060, 0.060, 1.18, Vector3(0.0, 0.09, -0.90), mat_silver, Vector3(90, 0, 0))
			_add_cyl(mount, 0.072, 0.072, 0.95, Vector3(0.0, 0.09, -0.88), _mat(Color(0.18, 0.20, 0.26), 0.80, 0.32), Vector3(90, 0, 0))
			for i in range(4):
				_add_box(mount, Vector3(0.09, 0.015, 0.04), Vector3(0.0, 0.145, -0.52 - float(i) * 0.18), _mat(Color(0.02, 0.02, 0.02), 0.10, 0.90))
			# Gold trim rail along top
			_add_box(mount, Vector3(0.03, 0.015, 0.58), Vector3(0.0, 0.20, -0.22), mat_brass)
			# Scope — compact ACOG style
			_add_box(mount, Vector3(0.06, 0.06, 0.24), Vector3(0.0, 0.20, -0.22), mat_dark_steel)
			_add_cyl(mount, 0.032, 0.040, 0.06, Vector3(0.0, 0.20, -0.34), _mat(Color(0.15, 0.40, 0.65), 0.80, 0.20, Color(0.25, 0.60, 1.0), 1.8), Vector3(90, 0, 0))
			# Side power cell — glowing bulge on left side
			_add_box(mount, Vector3(0.10, 0.14, 0.20), Vector3(-0.17, 0.08, -0.18), _mat(Color(0.16, 0.35, 0.70), 0.75, 0.30, Color(0.20, 0.60, 1.0), 1.5))
			_add_box(mount, Vector3(0.02, 0.08, 0.12), Vector3(-0.22, 0.08, -0.18), _mat(Color(0.40, 0.80, 1.0), 0.30, 0.30, Color(0.40, 0.80, 1.0), 2.5))
			# Energy mag
			_add_box(mount, Vector3(0.09, 0.13, 0.15), Vector3(0.0, -0.06, -0.20), mat_energy_cyan)
			# Stock with cheek rest
			_add_box(mount, Vector3(0.18, 0.11, 0.38), Vector3(0.0, 0.07, 0.34), mat_dark_steel)
			_add_box(mount, Vector3(0.10, 0.04, 0.20), Vector3(0.0, 0.135, 0.32), mat_black_polymer)
			_add_box(mount, Vector3(0.07, 0.15, 0.08), Vector3(0.0, -0.05, 0.12), mat_black_polymer, Vector3(-11, 0, 0))
			# Muzzle compensator
			_add_cyl(mount, 0.070, 0.055, 0.12, Vector3(0.0, 0.09, -1.52), mat_dark_steel, Vector3(90, 0, 0))
			muzzle_local = Vector3(0, 0.09, -1.60)
		else:
			# Standard Beam Rifle — classic workhorse
			_add_box(mount, Vector3(0.22, 0.18, 0.60), Vector3(0.0, 0.09, -0.20), mat_gunmetal)
			# Barrel + shroud
			_add_cyl(mount, 0.055, 0.055, 1.15, Vector3(0.0, 0.09, -0.88), mat_silver, Vector3(90, 0, 0))
			_add_cyl(mount, 0.068, 0.068, 0.88, Vector3(0.0, 0.09, -0.86), _mat(Color(0.17, 0.19, 0.23), 0.78, 0.35), Vector3(90, 0, 0))
			# Cooling fins along shroud (3 radial fins)
			for i in range(3):
				var z := -0.48 - float(i) * 0.22
				_add_box(mount, Vector3(0.14, 0.015, 0.05), Vector3(0.0, 0.15, z), _mat(Color(0.12, 0.18, 0.28), 0.70, 0.35))
			# Top carry handle / scope rail
			_add_box(mount, Vector3(0.06, 0.04, 0.38), Vector3(0.0, 0.19, -0.20), mat_dark_steel)
			_add_box(mount, Vector3(0.04, 0.03, 0.30), Vector3(0.0, 0.22, -0.20), mat_dark_steel)
			# Iron sights
			_add_box(mount, Vector3(0.02, 0.04, 0.02), Vector3(0.0, 0.23, -0.78), mat_dark_steel)
			_add_box(mount, Vector3(0.03, 0.03, 0.04), Vector3(0.0, 0.21, -0.02), mat_dark_steel)
			# Energy magazine (translucent glow)
			_add_box(mount, Vector3(0.09, 0.13, 0.15), Vector3(0.0, -0.05, -0.18), mat_energy_blue)
			_add_box(mount, Vector3(0.02, 0.08, 0.10), Vector3(0.055, -0.05, -0.18), _mat(Color(0.45, 0.85, 1.0), 0.30, 0.30, Color(0.45, 0.85, 1.0), 2.8))
			# Stock — polymer tactical
			_add_box(mount, Vector3(0.18, 0.11, 0.36), Vector3(0.0, 0.07, 0.32), mat_dark_steel)
			_add_box(mount, Vector3(0.16, 0.12, 0.04), Vector3(0.0, 0.07, 0.51), mat_rubber)
			# Grip
			_add_box(mount, Vector3(0.07, 0.15, 0.08), Vector3(0.0, -0.05, 0.10), mat_black_polymer, Vector3(-12, 0, 0))
			_add_box(mount, Vector3(0.05, 0.04, 0.06), Vector3(0.0, 0.01, 0.14), mat_dark_steel)
			# Muzzle device
			_add_cyl(mount, 0.062, 0.062, 0.09, Vector3(0.0, 0.09, -1.48), mat_dark_steel, Vector3(90, 0, 0))
			_add_cyl(mount, 0.050, 0.062, 0.04, Vector3(0.0, 0.09, -1.54), _mat(Color(0.02, 0.02, 0.02), 0.10, 0.90), Vector3(90, 0, 0))
			muzzle_local = Vector3(0, 0.09, -1.58)

	# -----------------------------------------------------------------------
	# 7) MACHINE GUN family — kinetic automatics
	# -----------------------------------------------------------------------
	elif w_type == WeaponPart.WeaponType.MACHINE_GUN:
		if name_lower.contains("heavy"):
			# Heavy Machine Gun — belt-fed beast with cooling jacket
			_add_box(mount, Vector3(0.30, 0.26, 0.68), Vector3(0.0, 0.09, -0.18), _mat(Color(0.26, 0.26, 0.28), 0.82, 0.35))
			# Thick barrel with perforated cooling jacket
			_add_cyl(mount, 0.055, 0.055, 0.92, Vector3(0.0, 0.09, -0.72), mat_silver, Vector3(90, 0, 0))
			_add_cyl(mount, 0.085, 0.085, 0.70, Vector3(0.0, 0.09, -0.68), _mat(Color(0.20, 0.20, 0.22), 0.78, 0.35), Vector3(90, 0, 0))
			for i in range(6):
				_add_box(mount, Vector3(0.10, 0.012, 0.035), Vector3(0.0, 0.155, -0.42 - float(i) * 0.08), _mat(Color(0.02, 0.02, 0.02), 0.10, 0.90))
			# Belt box on left side (large square ammo can)
			_add_box(mount, Vector3(0.18, 0.18, 0.22), Vector3(-0.22, 0.02, -0.08), _mat(Color(0.32, 0.30, 0.26), 0.70, 0.40))
			_add_box(mount, Vector3(0.16, 0.015, 0.18), Vector3(-0.22, 0.12, -0.08), mat_dark_steel)
			# Feed cover
			_add_box(mount, Vector3(0.18, 0.05, 0.28), Vector3(0.0, 0.22, -0.14), mat_dark_steel)
			# Carry handle
			_add_box(mount, Vector3(0.04, 0.04, 0.26), Vector3(0.0, 0.24, -0.16), _mat(Color(0.18, 0.18, 0.18), 0.60, 0.40), Vector3(0, 0, 0))
			_add_box(mount, Vector3(0.03, 0.06, 0.03), Vector3(0.0, 0.21, -0.28), mat_dark_steel)
			_add_box(mount, Vector3(0.03, 0.06, 0.03), Vector3(0.0, 0.21, -0.04), mat_dark_steel)
			# Bipod
			_add_box(mount, Vector3(0.03, 0.16, 0.03), Vector3(0.07, -0.04, -0.42), mat_dark_steel, Vector3(20, 0, 0))
			_add_box(mount, Vector3(0.03, 0.16, 0.03), Vector3(-0.07, -0.04, -0.42), mat_dark_steel, Vector3(-20, 0, 0))
			# Grip + stock
			_add_box(mount, Vector3(0.08, 0.16, 0.09), Vector3(0.0, -0.06, 0.16), mat_black_polymer, Vector3(-12, 0, 0))
			_add_box(mount, Vector3(0.16, 0.10, 0.30), Vector3(0.0, 0.06, 0.38), mat_black_polymer)
			# Muzzle brake
			_add_cyl(mount, 0.075, 0.075, 0.10, Vector3(0.0, 0.09, -1.20), mat_dark_steel, Vector3(90, 0, 0))
			muzzle_local = Vector3(0, 0.09, -1.26)
		elif name_lower.contains("light"):
			# Light Machine Gun — handy, smaller
			_add_box(mount, Vector3(0.22, 0.18, 0.46), Vector3(0.0, 0.08, -0.14), mat_olive)
			_add_cyl(mount, 0.045, 0.045, 0.72, Vector3(0.0, 0.08, -0.56), mat_silver, Vector3(90, 0, 0))
			_add_cyl(mount, 0.062, 0.062, 0.48, Vector3(0.0, 0.08, -0.52), _mat(Color(0.19, 0.19, 0.21), 0.75, 0.35), Vector3(90, 0, 0))
			# Small box mag on top
			_add_box(mount, Vector3(0.10, 0.05, 0.16), Vector3(0.0, 0.18, -0.12), mat_dark_steel)
			# Side charging handle
			_add_box(mount, Vector3(0.05, 0.02, 0.02), Vector3(0.13, 0.08, -0.10), mat_silver)
			# Handguard with vents
			for i in range(3):
				_add_box(mount, Vector3(0.08, 0.012, 0.03), Vector3(0.0, 0.135, -0.36 - float(i) * 0.09), _mat(Color(0.02, 0.02, 0.02), 0.10, 0.90))
			# Folding stock (skeleton)
			_add_box(mount, Vector3(0.10, 0.04, 0.24), Vector3(0.0, 0.06, 0.26), mat_dark_steel)
			_add_cyl(mount, 0.012, 0.012, 0.18, Vector3(0.045, 0.06, 0.34), mat_silver, Vector3(90, 0, 0))
			_add_cyl(mount, 0.012, 0.012, 0.18, Vector3(-0.045, 0.06, 0.34), mat_silver, Vector3(90, 0, 0))
			_add_box(mount, Vector3(0.06, 0.10, 0.10), Vector3(0.0, -0.05, 0.14), mat_black_polymer, Vector3(-12, 0, 0))
			_add_box(mount, Vector3(0.09, 0.08, 0.10), Vector3(0.0, 0.18, -0.12), _mat(Color(0.10, 0.10, 0.10), 0.60, 0.30))
			muzzle_local = Vector3(0, 0.08, -0.94)
		else:
			# Standard Machine Gun — balanced
			_add_box(mount, Vector3(0.26, 0.20, 0.54), Vector3(0.0, 0.09, -0.16), mat_olive)
			_add_cyl(mount, 0.050, 0.050, 0.82, Vector3(0.0, 0.09, -0.64), mat_silver, Vector3(90, 0, 0))
			_add_cyl(mount, 0.070, 0.070, 0.58, Vector3(0.0, 0.09, -0.60), _mat(Color(0.18, 0.18, 0.20), 0.75, 0.35), Vector3(90, 0, 0))
			# Box magazine below
			_add_box(mount, Vector3(0.12, 0.14, 0.16), Vector3(0.0, -0.06, -0.14), mat_dark_steel)
			_add_box(mount, Vector3(0.10, 0.015, 0.12), Vector3(0.0, -0.13, -0.14), _mat(Color(0.12, 0.12, 0.14), 0.60, 0.45))
			# Top cover + carry handle
			_add_box(mount, Vector3(0.16, 0.04, 0.26), Vector3(0.0, 0.20, -0.14), mat_dark_steel)
			# Iron sights
			_add_box(mount, Vector3(0.02, 0.035, 0.02), Vector3(0.0, 0.215, -0.58), mat_dark_steel)
			# Handguard
			_add_box(mount, Vector3(0.18, 0.08, 0.22), Vector3(0.0, 0.02, -0.36), mat_black_polymer)
			for i in range(3):
				_add_box(mount, Vector3(0.07, 0.012, 0.03), Vector3(0.0, 0.065, -0.30 - float(i) * 0.07), _mat(Color(0.02, 0.02, 0.02), 0.10, 0.90))
			# Stock
			_add_box(mount, Vector3(0.16, 0.10, 0.32), Vector3(0.0, 0.06, 0.32), mat_black_polymer)
			_add_box(mount, Vector3(0.07, 0.14, 0.08), Vector3(0.0, -0.04, 0.12), mat_black_polymer, Vector3(-11, 0, 0))
			# Muzzle
			_add_cyl(mount, 0.062, 0.062, 0.08, Vector3(0.0, 0.09, -1.08), mat_dark_steel, Vector3(90, 0, 0))
			muzzle_local = Vector3(0, 0.09, -1.13)

	# -----------------------------------------------------------------------
	# 8) SHOTGUN family
	# -----------------------------------------------------------------------
	elif w_type == WeaponPart.WeaponType.SHOTGUN:
		if name_lower.contains("sawed"):
			# Sawed-off — short double barrel side-by-side, rustic
			_add_cyl(mount, 0.055, 0.055, 0.46, Vector3(0.065, 0.08, -0.32), mat_silver, Vector3(90, 0, 0))
			_add_cyl(mount, 0.055, 0.055, 0.46, Vector3(-0.065, 0.08, -0.32), mat_silver, Vector3(90, 0, 0))
			_add_box(mount, Vector3(0.20, 0.08, 0.10), Vector3(0.0, 0.08, -0.08), mat_dark_steel)
			# Receiver block
			_add_box(mount, Vector3(0.20, 0.14, 0.28), Vector3(0.0, 0.08, 0.08), _mat(Color(0.22, 0.22, 0.24), 0.75, 0.35))
			# Wooden pistol grip (no full stock)
			_add_box(mount, Vector3(0.10, 0.14, 0.12), Vector3(0.0, -0.04, 0.22), mat_brown_stock, Vector3(-22, 0, 0))
			# Trigger guard
			_add_box(mount, Vector3(0.06, 0.02, 0.08), Vector3(0.0, -0.02, 0.12), mat_dark_steel)
			# Break hinge
			_add_cyl(mount, 0.02, 0.02, 0.16, Vector3(0.0, 0.08, -0.06), mat_silver, Vector3(0, 0, 90))
			muzzle_local = Vector3(0, 0.08, -0.56)
		elif name_lower.contains("combat") or name_lower.contains("assault"):
			# Combat Shotgun / Assault Cannon — tactical pump with box mag
			_add_box(mount, Vector3(0.26, 0.20, 0.52), Vector3(0.0, 0.09, -0.16), _mat(Color(0.20, 0.20, 0.22), 0.80, 0.35))
			# Heavy barrel + compensator (bigger for assault cannon)
			var is_cannon := name_lower.contains("cannon")
			var barrel_r := 0.075 if is_cannon else 0.065
			var barrel_len := 0.68 if is_cannon else 0.62
			_add_cyl(mount, barrel_r, barrel_r, barrel_len, Vector3(0.0, 0.09, -0.56), mat_silver, Vector3(90, 0, 0))
			_add_cyl(mount, barrel_r + 0.015, barrel_r + 0.015, 0.12, Vector3(0.0, 0.09, -0.84), mat_dark_steel, Vector3(90, 0, 0))
			# Box magazine below (tactical)
			_add_box(mount, Vector3(0.11, 0.16, 0.16), Vector3(0.0, -0.06, -0.12), mat_dark_steel)
			_add_box(mount, Vector3(0.09, 0.015, 0.12), Vector3(0.0, -0.14, -0.12), mat_black_polymer)
			# Vertical foregrip
			_add_cyl(mount, 0.035, 0.035, 0.12, Vector3(0.0, -0.04, -0.32), mat_black_polymer, Vector3(0, 0, 0))
			_add_box(mount, Vector3(0.06, 0.04, 0.08), Vector3(0.0, -0.04, -0.32), mat_black_polymer)
			# Top rail + holo sight
			_add_box(mount, Vector3(0.04, 0.02, 0.32), Vector3(0.0, 0.20, -0.16), mat_dark_steel)
			_add_box(mount, Vector3(0.05, 0.04, 0.10), Vector3(0.0, 0.23, -0.16), _mat(Color(0.10, 0.10, 0.10), 0.60, 0.30))
			_add_box(mount, Vector3(0.015, 0.02, 0.06), Vector3(0.0, 0.25, -0.16), _mat(Color(1.0, 0.15, 0.15), 0.10, 0.30, Color(1.0, 0.20, 0.20), 2.5))
			# Stock — collapsible tactical
			_add_box(mount, Vector3(0.14, 0.08, 0.28), Vector3(0.0, 0.06, 0.28), mat_dark_steel)
			_add_box(mount, Vector3(0.12, 0.14, 0.04), Vector3(0.0, 0.06, 0.42), mat_rubber)
			_add_box(mount, Vector3(0.07, 0.14, 0.08), Vector3(0.0, -0.03, 0.10), mat_black_polymer, Vector3(-11, 0, 0))
			muzzle_local = Vector3(0, 0.09, -0.92) if not is_cannon else Vector3(0, 0.09, -0.94)
		else:
			# Standard Shotgun — pump action, tube mag
			_add_box(mount, Vector3(0.24, 0.18, 0.48), Vector3(0.0, 0.08, -0.12), _mat(Color(0.24, 0.22, 0.20), 0.70, 0.40))
			_add_cyl(mount, 0.060, 0.060, 0.78, Vector3(0.0, 0.10, -0.58), mat_silver, Vector3(90, 0, 0))
			# Pump forend (wood/polymer slider)
			_add_box(mount, Vector3(0.18, 0.10, 0.26), Vector3(0.0, 0.02, -0.36), mat_brown_stock)
			_add_box(mount, Vector3(0.16, 0.015, 0.20), Vector3(0.0, 0.02, -0.36), _mat(Color(0.30, 0.22, 0.14), 0.05, 0.60))
			# Under-barrel tube magazine
			_add_cyl(mount, 0.038, 0.038, 0.62, Vector3(0.0, 0.02, -0.48), _mat(Color(0.32, 0.32, 0.34), 0.78, 0.30), Vector3(90, 0, 0))
			# Receiver detail — ejection port
			_add_box(mount, Vector3(0.04, 0.06, 0.14), Vector3(0.12, 0.12, -0.14), _mat(Color(0.05, 0.05, 0.05), 0.10, 0.90))
			# Tubular stock
			_add_box(mount, Vector3(0.14, 0.10, 0.34), Vector3(0.0, 0.07, 0.30), mat_brown_stock)
			_add_box(mount, Vector3(0.12, 0.12, 0.05), Vector3(0.0, 0.07, 0.48), mat_rubber)
			_add_box(mount, Vector3(0.07, 0.13, 0.08), Vector3(0.0, -0.03, 0.10), mat_brown_stock, Vector3(-12, 0, 0))
			muzzle_local = Vector3(0, 0.10, -0.98)

	# -----------------------------------------------------------------------
	# 9) MISSILE family — launcher pods
	# -----------------------------------------------------------------------
	elif w_type == WeaponPart.WeaponType.MISSILE:
		if name_lower.contains("swarm") or name_lower.contains("micro"):
			# Swarm / Micro — many tiny tubes in a block
			_add_box(mount, Vector3(0.42, 0.32, 0.72), Vector3(0.0, 0.10, -0.12), _mat(Color(0.32, 0.28, 0.26), 0.70, 0.40))
			# Top sensor dome
			_add_sphere(mount, 0.05, 0.05, Vector3(0.0, 0.27, -0.08), _mat(Color(0.18, 0.55, 0.35), 0.60, 0.30, Color(0.30, 0.85, 0.45), 2.0))
			# 3x3 grid of micro tubes (9 tubes, 0.04 radius)
			for x in range(3):
				for y in range(3):
					var px := (float(x) - 1.0) * 0.09
					var py := (float(y) - 1.0) * 0.07 + 0.10
					_add_cyl(mount, 0.032, 0.032, 0.68, Vector3(px, py, -0.22), _mat(Color(0.18, 0.18, 0.20), 0.80, 0.35), Vector3(90, 0, 0))
					_add_cyl(mount, 0.025, 0.025, 0.02, Vector3(px, py, -0.56), _mat(Color(0.55, 0.20, 0.12), 0.60, 0.40), Vector3(90, 0, 0))
			# Side mounting rails
			_add_box(mount, Vector3(0.04, 0.06, 0.60), Vector3(0.23, 0.10, -0.14), mat_dark_steel)
			_add_box(mount, Vector3(0.04, 0.06, 0.60), Vector3(-0.23, 0.10, -0.14), mat_dark_steel)
			# Rear thruster plate
			_add_box(mount, Vector3(0.36, 0.08, 0.04), Vector3(0.0, 0.06, 0.24), _mat(Color(0.16, 0.16, 0.18), 0.80, 0.30))
			muzzle_local = Vector3(0, 0.10, -0.57)
		elif name_lower.contains("heavy"):
			# Heavy Missile — one huge tube
			_add_box(mount, Vector3(0.48, 0.40, 0.85), Vector3(0.0, 0.12, -0.10), _mat(Color(0.38, 0.28, 0.20), 0.70, 0.40))
			# Single large launch tube
			_add_cyl(mount, 0.16, 0.16, 0.82, Vector3(0.0, 0.13, -0.28), _mat(Color(0.22, 0.22, 0.24), 0.82, 0.32), Vector3(90, 0, 0))
			# Warhead tip visible at front (cone)
			_add_cyl(mount, 0.02, 0.14, 0.16, Vector3(0.0, 0.13, -0.75), _mat(Color(0.60, 0.22, 0.14), 0.65, 0.35), Vector3(90, 0, 0))
			# Guidance fins (4 small)
			_add_box(mount, Vector3(0.02, 0.12, 0.10), Vector3(0.0, 0.26, -0.28), _mat(Color(0.30, 0.30, 0.32), 0.75, 0.35))
			_add_box(mount, Vector3(0.12, 0.02, 0.10), Vector3(0.0, 0.13, -0.28), _mat(Color(0.30, 0.30, 0.32), 0.75, 0.35))
			# Side rail + locking clamp
			_add_box(mount, Vector3(0.05, 0.10, 0.60), Vector3(0.24, 0.12, -0.12), mat_dark_steel)
			_add_box(mount, Vector3(0.05, 0.10, 0.60), Vector3(-0.24, 0.12, -0.12), mat_dark_steel)
			# Control box on top
			_add_box(mount, Vector3(0.14, 0.06, 0.18), Vector3(0.0, 0.34, -0.10), _mat(Color(0.20, 0.24, 0.28), 0.80, 0.30))
			_add_box(mount, Vector3(0.06, 0.015, 0.10), Vector3(0.0, 0.375, -0.10), _mat(Color(0.20, 0.80, 0.35), 0.30, 0.30, Color(0.20, 0.80, 0.35), 2.0))
			# Exhaust nozzle at rear
			_add_cyl(mount, 0.10, 0.13, 0.08, Vector3(0.0, 0.13, 0.18), mat_dark_steel, Vector3(90, 0, 0))
			muzzle_local = Vector3(0, 0.13, -0.84)
		else:
			# Standard Missile Launcher — 4-tube pod (2x2)
			_add_box(mount, Vector3(0.44, 0.36, 0.78), Vector3(0.0, 0.11, -0.10), _mat(Color(0.42, 0.30, 0.22), 0.70, 0.40))
			for x in range(2):
				for y in range(2):
					var px := (float(x) - 0.5) * 0.16
					var py := (float(y) - 0.5) * 0.14 + 0.11
					_add_cyl(mount, 0.075, 0.075, 0.72, Vector3(px, py, -0.20), _mat(Color(0.20, 0.20, 0.22), 0.82, 0.30), Vector3(90, 0, 0))
					# Tube inner dark + warhead tip
					_add_cyl(mount, 0.055, 0.055, 0.02, Vector3(px, py, -0.54), _mat(Color(0.08, 0.08, 0.08), 0.10, 0.90), Vector3(90, 0, 0))
			# Targeting sensor pod on top
			_add_box(mount, Vector3(0.12, 0.06, 0.16), Vector3(0.0, 0.31, -0.08), _mat(Color(0.22, 0.26, 0.30), 0.80, 0.30))
			_add_sphere(mount, 0.035, 0.035, Vector3(0.0, 0.34, -0.14), _mat(Color(0.20, 0.80, 1.0), 0.30, 0.30, Color(0.20, 0.80, 1.0), 2.5))
			# Side rails
			_add_box(mount, Vector3(0.04, 0.06, 0.64), Vector3(0.24, 0.11, -0.12), mat_dark_steel)
			_add_box(mount, Vector3(0.04, 0.06, 0.64), Vector3(-0.24, 0.11, -0.12), mat_dark_steel)
			# Hazard stripes on front plate
			_add_box(mount, Vector3(0.38, 0.025, 0.015), Vector3(0.0, 0.02, -0.49), mat_hazard_yellow)
			_add_box(mount, Vector3(0.38, 0.025, 0.015), Vector3(0.0, 0.08, -0.49), mat_hazard_yellow)
			muzzle_local = Vector3(0, 0.11, -0.58)

	else:
		# Fallback generic rifle — still detailed with basic furniture
		_add_box(mount, Vector3(0.20, 0.16, 0.90), Vector3(0.0, 0.07, -0.32), mat_gunmetal)
		_add_cyl(mount, 0.050, 0.050, 0.75, Vector3(0.0, 0.07, -0.82), mat_silver, Vector3(90, 0, 0))
		_add_box(mount, Vector3(0.08, 0.08, 0.10), Vector3(0.0, 0.16, -0.20), mat_dark_steel)
		_add_box(mount, Vector3(0.07, 0.12, 0.06), Vector3(0.0, -0.04, 0.08), mat_black_polymer, Vector3(-10, 0, 0))
		_add_box(mount, Vector3(0.14, 0.09, 0.28), Vector3(0.0, 0.05, 0.28), mat_dark_steel)
		muzzle_local = Vector3(0, 0.07, -1.22)

	# Barrel-tip marker: projectiles, muzzle flashes and jam sparks anchor here.
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = muzzle_local
	mount.add_child(muzzle)
	return mount


## Finds the barrel-tip "Muzzle" marker under a mounted weapon model (checks
## authored custom scenes too). Returns null when the model has none.
static func find_muzzle_node(root: Node) -> Node3D:
	if root == null or not is_instance_valid(root):
		return null
	if String(root.name).to_lower() == "muzzle":
		return root as Node3D
	for child in root.get_children():
		var found := find_muzzle_node(child)
		if found != null:
			return found
	return null


## Builds a dedicated HUMAN-SCALED weapon model (for pilots on foot).
## Scale is realistically proportioned for human hands (~18-20cm pistol, ~65cm rifle, ~1.1m anti-tank, ~0.95m bazooka).
static func build_pilot_weapon(weapon: WeaponPart) -> Node3D:
	var mount := Node3D.new()
	if weapon == null:
		return mount

	var name_lower := weapon.weapon_name.to_lower()
	var w_type := weapon.weapon_type
	var muzzle_local := Vector3(0, 0.038, -0.16)

	var mat_gunmetal := _mat(Color(0.20, 0.22, 0.25), 0.85, 0.35)
	var mat_dark_steel := _mat(Color(0.14, 0.15, 0.17), 0.88, 0.30)
	var mat_silver := _mat(Color(0.75, 0.78, 0.82), 0.92, 0.22)
	var mat_black_poly := _mat(Color(0.08, 0.08, 0.09), 0.10, 0.75)
	var mat_brown_poly := _mat(Color(0.28, 0.22, 0.15), 0.15, 0.70)
	var mat_olive_poly := _mat(Color(0.25, 0.30, 0.22), 0.35, 0.65)
	var mat_tritium_green := _mat(Color(0.2, 0.95, 0.3), 0.10, 0.30, Color(0.2, 1.0, 0.3), 4.0)
	var mat_scope_lens := _mat(Color(0.15, 0.45, 0.85), 0.80, 0.15, Color(0.2, 0.6, 1.0), 2.0)
	var mat_hazard := _mat(Color(0.92, 0.75, 0.10), 0.20, 0.55)

	# 1) BAZOOKA / ROCKET LAUNCHER (Human shoulder-fired)
	if name_lower.contains("bazooka") or name_lower.contains("rocket"):
		# Launch tube: 92cm long, 9cm diameter
		_add_cyl(mount, 0.045, 0.045, 0.92, Vector3(0.0, 0.06, -0.15), mat_olive_poly, Vector3(90, 0, 0))
		# Venturi exhaust bell at rear
		_add_cyl(mount, 0.062, 0.045, 0.12, Vector3(0.0, 0.06, 0.35), mat_dark_steel, Vector3(90, 0, 0))
		# Front muzzle reinforcement ring
		_add_cyl(mount, 0.052, 0.052, 0.04, Vector3(0.0, 0.06, -0.60), mat_dark_steel, Vector3(90, 0, 0))
		# Shoulder rest bracket
		_add_box(mount, Vector3(0.08, 0.03, 0.18), Vector3(0.0, 0.01, 0.10), mat_black_poly)
		# Dual grips (forward and rear trigger)
		_add_box(mount, Vector3(0.03, 0.11, 0.04), Vector3(0.0, -0.04, -0.05), mat_black_poly, Vector3(-12, 0, 0))
		_add_box(mount, Vector3(0.03, 0.10, 0.04), Vector3(0.0, -0.03, -0.32), mat_black_poly)
		# Offset optical sight on left
		_add_box(mount, Vector3(0.04, 0.06, 0.12), Vector3(-0.065, 0.10, -0.12), mat_dark_steel)
		_add_cyl(mount, 0.018, 0.018, 0.10, Vector3(-0.065, 0.11, -0.12), mat_scope_lens, Vector3(90, 0, 0))
		# Warhead rocket tip loaded inside front
		_add_cyl(mount, 0.038, 0.010, 0.08, Vector3(0.0, 0.06, -0.62), mat_hazard, Vector3(90, 0, 0))
		muzzle_local = Vector3(0.0, 0.06, -0.68)

	# 2) ANTI-TANK / SNIPER RIFLE (Heavy Anti-Materiel)
	elif name_lower.contains("anti_tank") or name_lower.contains("anti-tank") or name_lower.contains("sniper") or name_lower.contains("antitank"):
		# Long receiver + stock: ~1.10m total
		_add_box(mount, Vector3(0.055, 0.080, 0.42), Vector3(0.0, 0.04, 0.08), mat_gunmetal)
		# Fluted long heavy barrel: 68cm
		_add_cyl(mount, 0.016, 0.018, 0.68, Vector3(0.0, 0.05, -0.48), mat_silver, Vector3(90, 0, 0))
		# Massive tank muzzle brake
		_add_box(mount, Vector3(0.045, 0.036, 0.08), Vector3(0.0, 0.05, -0.83), mat_dark_steel)
		_add_box(mount, Vector3(0.055, 0.012, 0.06), Vector3(0.0, 0.05, -0.83), mat_dark_steel)
		# High-power tactical scope with sunshade
		_add_cyl(mount, 0.022, 0.022, 0.28, Vector3(0.0, 0.12, -0.05), mat_dark_steel, Vector3(90, 0, 0))
		_add_cyl(mount, 0.026, 0.020, 0.04, Vector3(0.0, 0.12, -0.19), mat_scope_lens, Vector3(90, 0, 0))
		# Heavy box magazine (5 rounds) behind trigger
		_add_box(mount, Vector3(0.035, 0.12, 0.07), Vector3(0.0, -0.05, 0.18), mat_dark_steel)
		# Ergonomic pistol grip
		_add_box(mount, Vector3(0.032, 0.11, 0.045), Vector3(0.0, -0.04, 0.02), mat_black_poly, Vector3(-15, 0, 0))
		# Folded bipod
		_add_cyl(mount, 0.007, 0.007, 0.22, Vector3(0.025, -0.02, -0.32), mat_dark_steel, Vector3(90, 0, 0))
		_add_cyl(mount, 0.007, 0.007, 0.22, Vector3(-0.025, -0.02, -0.32), mat_dark_steel, Vector3(90, 0, 0))
		muzzle_local = Vector3(0.0, 0.05, -0.88)

	# 3) ASSAULT RIFLE / CARBINE / SUBMACHINE GUN
	elif name_lower.contains("assault") or name_lower.contains("rifle") or name_lower.contains("smg") or name_lower.contains("submachine"):
		# Upper and lower receiver: ~65cm total length
		_add_box(mount, Vector3(0.042, 0.065, 0.26), Vector3(0.0, 0.03, -0.02), mat_gunmetal)
		# Handguard with cooling slots
		_add_box(mount, Vector3(0.038, 0.052, 0.20), Vector3(0.0, 0.03, -0.24), mat_dark_steel)
		# Barrel & birdcage flash hider
		_add_cyl(mount, 0.010, 0.010, 0.18, Vector3(0.0, 0.035, -0.38), mat_silver, Vector3(90, 0, 0))
		_add_cyl(mount, 0.013, 0.013, 0.035, Vector3(0.0, 0.035, -0.47), mat_dark_steel, Vector3(90, 0, 0))
		# Curved 30-round banana magazine
		_add_box(mount, Vector3(0.022, 0.14, 0.055), Vector3(0.0, -0.06, -0.07), mat_dark_steel, Vector3(12, 0, 0))
		# Pistol grip
		_add_box(mount, Vector3(0.028, 0.10, 0.04), Vector3(0.0, -0.04, 0.07), mat_black_poly, Vector3(-16, 0, 0))
		# Holographic red dot reflex sight
		_add_box(mount, Vector3(0.028, 0.035, 0.07), Vector3(0.0, 0.085, -0.05), mat_black_poly)
		_add_box(mount, Vector3(0.018, 0.018, 0.01), Vector3(0.0, 0.088, -0.05), _mat(Color(1.0, 0.2, 0.2), 0.1, 0.2, Color(1.0, 0.2, 0.2), 3.5))
		# Retractable tactical buttstock
		_add_box(mount, Vector3(0.035, 0.08, 0.16), Vector3(0.0, 0.03, 0.18), mat_black_poly)
		muzzle_local = Vector3(0.0, 0.035, -0.50)

	# 4) MELEE COMBAT BLADE / KNIFE
	elif w_type == WeaponPart.WeaponType.MELEE or name_lower.contains("knife") or name_lower.contains("blade"):
		# Tanto knife blade: 24cm
		_add_box(mount, Vector3(0.006, 0.035, 0.22), Vector3(0.0, 0.0, -0.15), mat_silver)
		# Beveled tip
		_add_box(mount, Vector3(0.005, 0.025, 0.06), Vector3(0.0, 0.005, -0.28), mat_silver, Vector3(25, 0, 0))
		# Crossguard
		_add_box(mount, Vector3(0.018, 0.06, 0.012), Vector3(0.0, 0.0, -0.04), mat_dark_steel)
		# Tactical textured handle
		_add_box(mount, Vector3(0.022, 0.036, 0.12), Vector3(0.0, 0.0, 0.03), mat_black_poly)
		# Pommel strike ring
		_add_cyl(mount, 0.015, 0.015, 0.015, Vector3(0.0, 0.0, 0.10), mat_dark_steel, Vector3(0, 0, 90))
		muzzle_local = Vector3(0.0, 0.0, -0.32)

	# 5) PILOT PISTOL / SIDEARM (Default)
	else:
		# Slide: 18cm long, 2.8cm wide, 3.5cm high
		_add_box(mount, Vector3(0.028, 0.035, 0.18), Vector3(0.0, 0.035, -0.04), mat_gunmetal)
		# Serrations on rear slide
		for i in range(4):
			_add_box(mount, Vector3(0.030, 0.025, 0.005), Vector3(0.0, 0.035, 0.01 - float(i) * 0.012), mat_dark_steel)
		# Barrel tip (stainless steel)
		_add_cyl(mount, 0.007, 0.007, 0.05, Vector3(0.0, 0.038, -0.13), mat_silver, Vector3(90, 0, 0))
		# Frame & underbarrel tactical rail
		_add_box(mount, Vector3(0.026, 0.025, 0.15), Vector3(0.0, 0.010, -0.03), mat_black_poly)
		_add_box(mount, Vector3(0.020, 0.015, 0.06), Vector3(0.0, -0.005, -0.08), mat_dark_steel)
		# Ergonomic pistol grip
		_add_box(mount, Vector3(0.025, 0.095, 0.036), Vector3(0.0, -0.035, 0.015), mat_black_poly, Vector3(-16, 0, 0))
		# Textured grip side panels
		_add_box(mount, Vector3(0.027, 0.075, 0.028), Vector3(0.0, -0.035, 0.015), mat_brown_poly, Vector3(-16, 0, 0))
		# Trigger guard & trigger
		_add_box(mount, Vector3(0.010, 0.035, 0.045), Vector3(0.0, -0.015, -0.03), mat_black_poly)
		_add_box(mount, Vector3(0.006, 0.018, 0.008), Vector3(0.0, -0.012, -0.025), mat_silver, Vector3(15, 0, 0))
		# Tritium glowing 3-dot night sights
		_add_sphere(mount, 0.003, 0.003, Vector3(0.0, 0.055, -0.12), mat_tritium_green)
		_add_sphere(mount, 0.0025, 0.0025, Vector3(0.008, 0.055, 0.04), mat_tritium_green)
		_add_sphere(mount, 0.0025, 0.0025, Vector3(-0.008, 0.055, 0.04), mat_tritium_green)
		muzzle_local = Vector3(0.0, 0.038, -0.16)

	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = muzzle_local
	mount.add_child(muzzle)
	return mount
