extends Node3D

func _ready() -> void:
	print("--- BEGIN TEST: Standing Posture & Shin Perpendicularity ---")

	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	assert(mecha_scene != null, "mecha_base.tscn must be loadable")
	var mecha = mecha_scene.instantiate()
	add_child(mecha)

	await get_tree().physics_frame
	await get_tree().physics_frame

	var anim = mecha.get_node_or_null("MechaAnimation")
	assert(anim != null, "MechaAnimation node must exist")

	var leg_l = mecha.get_node_or_null("LegLeft")
	var shin_l = mecha.get_node_or_null("LegLeft/ShinLeft")
	var body = mecha.get_node_or_null("Body")
	assert(leg_l != null and shin_l != null and body != null, "Limb nodes must exist")

	# 1. Test Combat Crouch (Default Primary Stance)
	anim.set_stance_mode("combat_crouch")
	for i in range(120):
		anim._process(0.016)

	var thigh_pitch_deg = rad_to_deg(leg_l.rotation.x)
	var shin_local_pitch_deg = rad_to_deg(shin_l.rotation.x)
	var shin_global_pitch_deg = rad_to_deg(shin_l.global_rotation.x)
	var body_tilt_deg = rad_to_deg(body.rotation.x)

	print("Combat Crouch Measurements:")
	print("  - Thigh Pitch: %.2f deg (expected ~26 deg)" % thigh_pitch_deg)
	print("  - Shin Local Pitch: %.2f deg (expected ~ -26 deg)" % shin_local_pitch_deg)
	print("  - Shin World Pitch: %.2f deg (expected 0.0 deg perpendicular to ground)" % shin_global_pitch_deg)
	print("  - Body Tilt: %.2f deg (expected 0.0 deg upright)" % body_tilt_deg)

	assert(absf(body_tilt_deg) < 0.5, "Torso must be upright (near 0 deg)")
	assert(absf(thigh_pitch_deg - 26.0) < 1.0, "Thigh must be slanted forward around 26 deg")
	assert(absf(shin_global_pitch_deg) < 0.5, "Shin must be perpendicular to ground (global pitch near 0 deg)")
	print("  [PASS] Combat Crouch posture verified: Torso upright, Thigh angled, Shin perpendicular")

	# 2. Test Upright Formal
	anim.set_stance_mode("upright_formal")
	for i in range(120):
		anim._process(0.016)

	var u_thigh_deg = rad_to_deg(leg_l.rotation.x)
	var u_shin_deg = rad_to_deg(shin_l.global_rotation.x)
	var u_body_deg = rad_to_deg(body.rotation.x)
	assert(absf(u_thigh_deg) < 0.5, "Upright formal thigh should be vertical")
	assert(absf(u_shin_deg) < 0.5, "Upright formal shin should be vertical")
	assert(absf(u_body_deg) < 0.5, "Upright formal body should be vertical")
	print("  [PASS] Upright Formal posture verified")

	# 3. Test Wide Squat
	anim.set_stance_mode("wide_squat")
	for i in range(120):
		anim._process(0.016)

	var w_shin_deg = rad_to_deg(shin_l.global_rotation.x)
	assert(absf(w_shin_deg) < 0.5, "Wide squat shin should be perpendicular to ground")
	print("  [PASS] Wide Squat shin perpendicularity verified")

	print("\n=== ALL STANDING POSTURE VERIFICATION TESTS PASSED (100%) ===")
	get_tree().quit(0)
