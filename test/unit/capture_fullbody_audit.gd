extends Node
## FULL MECHA VISUAL INTEGRATION AUDIT CAPTURE
## Renders all 8 required full-body audit perspectives with solid framing.

func _ready() -> void:
	await get_tree().process_frame
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.84, 0.85, 0.87)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.80, 0.81, 0.84)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -45, 0)
	sun.light_energy = 1.2
	add_child(sun)

	var fill_sun := DirectionalLight3D.new()
	fill_sun.rotation_degrees = Vector3(20, 135, 0)
	fill_sun.light_energy = 0.5
	add_child(fill_sun)

	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	DirAccess.make_dir_recursive_absolute("res://imgs/valkren_hand_ref")

	# === 1. Standard Frame Base ===
	var mech: CharacterBody3D = load("res://scenes/mecha/mecha_base.tscn").instantiate()
	add_child(mech)
	await get_tree().process_frame
	var pmm = mech.get_node_or_null("PartMeshManager")
	for slot in ["arm_left", "arm_right", "body", "head", "leg_left", "leg_right"]:
		var part := ArmorPart.new()
		part.slot_id = slot
		pmm.initialize_slot(slot, part, false, ({} if slot == "body" else null))
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	var center := Vector3(0.0, 2.6, 0.0)

	# --- 1. Full Body Front ---
	cam.position = center + Vector3(0.0, 0.1, -6.2)
	cam.look_at(center, Vector3.UP)
	cam.fov = 48.0
	await _snap("full_body_front.png")

	# --- 2. Full Body 3/4 Front ---
	cam.position = center + Vector3(-4.2, 0.2, -4.6)
	cam.look_at(center, Vector3.UP)
	cam.fov = 48.0
	await _snap("full_body_3quarter.png")

	# --- 3. Full Body Rear ---
	cam.position = center + Vector3(0.0, 0.1, 6.2)
	cam.look_at(center, Vector3.UP)
	cam.fov = 48.0
	await _snap("full_body_rear.png")

	# --- 4. Full Body Rifle ---
	var rifle := WeaponPart.new()
	rifle.weapon_type = WeaponPart.WeaponType.BEAM_RIFLE
	WeaponVisualFactory.mount_hand(mech, "right", rifle, "AuditRifle")
	cam.position = center + Vector3(4.2, 0.1, -4.6)
	cam.look_at(center, Vector3.UP)
	cam.fov = 48.0
	await _snap("full_body_rifle.png")

	# --- 5. Full Body Melee ---
	var blade := WeaponPart.new()
	blade.weapon_type = WeaponPart.WeaponType.MELEE
	blade.weapon_name = "Heat Blade"
	WeaponVisualFactory.mount_hand(mech, "right", blade, "AuditBlade")
	cam.position = center + Vector3(4.2, 0.1, -4.6)
	cam.look_at(center, Vector3.UP)
	cam.fov = 48.0
	await _snap("full_body_melee.png")

	# --- 6. Full Body Heavy Frame Variant ---
	mech.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var heavy_mech: CharacterBody3D = load("res://scenes/mecha/mecha_base.tscn").instantiate()
	FrameVariantResolver.apply_variant(heavy_mech, "heavy")
	add_child(heavy_mech)
	await get_tree().process_frame
	var pmm_h = heavy_mech.get_node_or_null("PartMeshManager")
	for slot in ["arm_left", "arm_right", "body", "head", "leg_left", "leg_right"]:
		var part := ArmorPart.new()
		part.slot_id = slot
		pmm_h.initialize_slot(slot, part, false, ({} if slot == "body" else null))
	var h_rifle := WeaponPart.new()
	h_rifle.weapon_type = WeaponPart.WeaponType.BEAM_RIFLE
	WeaponVisualFactory.mount_hand(heavy_mech, "right", h_rifle, "HeavyRifle")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	var h_center := Vector3(0.0, 2.6, 0.0)
	cam.position = h_center + Vector3(4.2, 0.1, -4.6)
	cam.look_at(h_center, Vector3.UP)
	cam.fov = 48.0
	await _snap("full_body_heavy.png")

	# --- 7. Full Body Sprint Posture ---
	heavy_mech.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var sprint_mech: CharacterBody3D = load("res://scenes/mecha/mecha_base.tscn").instantiate()
	add_child(sprint_mech)
	await get_tree().process_frame
	var pmm_s = sprint_mech.get_node_or_null("PartMeshManager")
	for slot in ["arm_left", "arm_right", "body", "head", "leg_left", "leg_right"]:
		var part := ArmorPart.new()
		part.slot_id = slot
		pmm_s.initialize_slot(slot, part, false, ({} if slot == "body" else null))
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	var s_center := Vector3(0.0, 2.6, 0.0)
	cam.position = s_center + Vector3(-4.5, 0.2, -4.5)
	cam.look_at(s_center, Vector3.UP)
	cam.fov = 48.0
	await _snap("full_body_sprint.png")

	# --- 8. Full Body Combat (Melee Attack Pose) ---
	var s_blade := WeaponPart.new()
	s_blade.weapon_type = WeaponPart.WeaponType.MELEE
	s_blade.weapon_name = "Heat Blade"
	WeaponVisualFactory.mount_hand(sprint_mech, "right", s_blade, "CombatBlade")
	await get_tree().process_frame
	await get_tree().process_frame
	cam.position = s_center + Vector3(4.5, 0.2, -4.5)
	cam.look_at(s_center, Vector3.UP)
	cam.fov = 48.0
	await _snap("full_body_combat.png")

	print("ALL_FULL_BODY_AUDIT_CAPTURES_COMPLETED")
	get_tree().quit(0)


func _snap(filename: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("res://imgs/valkren_hand_ref/" + filename)
	print("SAVED %s (err=%d)" % [filename, err])
