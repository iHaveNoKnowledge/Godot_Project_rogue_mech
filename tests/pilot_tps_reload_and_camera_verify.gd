extends Node

var _fails: int = 0
var _checks: int = 0

func _check(condition: bool, name: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: " + name)
	else:
		_fails += 1
		printerr("  FAIL: " + name)

func _ready() -> void:
	print("--- Running pilot_tps_reload_and_camera_verify ---")
	_test_camera_framing()
	_test_human_scale_and_visuals()
	_test_magazine_and_reload_system()

	print("PILOT_TPS_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _test_camera_framing() -> void:
	print("Testing Camera Framing: Pilot Human TPS vs Mecha...")
	var cam_scene = preload("res://scenes/camera/mecha_camera.tscn")
	var cam_rig = cam_scene.instantiate()
	add_child(cam_rig)

	var mecha = CharacterBody3D.new()
	mecha.name = "TestMecha"
	mecha.add_to_group("mecha")
	add_child(mecha)

	var pilot = CharacterBody3D.new()
	pilot.name = "TestPilot"
	pilot.add_to_group("pilot")
	add_child(pilot)

	# 1. Target Mecha: High over-the-shoulder framing (Y=3.2m, dist=6.8m)
	cam_rig._on_camera_target_changed(mecha)
	_check(is_equal_approx(cam_rig._target_spring_length, 6.8), "Mecha camera spring length is 6.8m")
	_check(is_equal_approx(cam_rig._target_offset_y, 3.2), "Mecha camera offset Y is 3.2m (chest-high for mech)")
	_check(is_equal_approx(cam_rig._target_offset_x, 1.8), "Mecha camera offset X is 1.8m")

	# 2. Target Pilot: Low human over-the-shoulder TPS framing (Y=1.45m, dist=2.4m)
	cam_rig._on_camera_target_changed(pilot)
	_check(is_equal_approx(cam_rig._target_spring_length, 2.4), "Pilot camera spring length is 2.4m (close tactical distance)")
	_check(is_equal_approx(cam_rig._target_offset_y, 1.45), "Pilot camera offset Y is 1.45m (true human eye/shoulder level)")
	_check(is_equal_approx(cam_rig._target_offset_x, 0.55), "Pilot camera offset X is 0.55m (tight shoulder offset)")
	_check(cam_rig.pitch_limit.y >= 70.0, "Pilot camera allows looking up at towering mechas (pitch max >= 70 deg)")

	cam_rig.queue_free()
	mecha.queue_free()
	pilot.queue_free()


func _test_human_scale_and_visuals() -> void:
	print("Testing Pilot Tactical Human Scale & Mesh...")
	var pilot_scene = preload("res://scenes/pilot/pilot.tscn")
	var pilot = pilot_scene.instantiate()
	add_child(pilot)

	var col: CollisionShape3D = pilot.get_node("CollisionShape3D")
	var shape: CapsuleShape3D = col.shape
	_check(shape.height >= 1.70 and shape.height <= 1.85, "Pilot physical height is realistic adult human (%.2fm)" % shape.height)
	_check(shape.radius >= 0.25 and shape.radius <= 0.35, "Pilot physical radius is human width (%.2fm)" % shape.radius)

	var human_vis: Node3D = pilot.get_node_or_null("TacticalHumanVisual")
	_check(human_vis != null, "TacticalHumanVisual mesh instance spawned on pilot")

	pilot.queue_free()


func _test_magazine_and_reload_system() -> void:
	print("Testing Pilot Magazine Capacity & TPS Reload System...")
	GameManager.current_state = GameManager.State.EJECT
	GlobalData.reset_run_data()
	GlobalData.pilot.pilot_ammo["kinetic"] = 120
	GlobalData.pilot.pilot_ammo["explosive"] = 10

	var pilot_scene = preload("res://scenes/pilot/pilot.tscn")
	var pilot = pilot_scene.instantiate()
	add_child(pilot)

	# 1. Test Magazine Sizing
	_check(pilot.get_max_magazine() > 0, "Pilot weapon has positive magazine capacity")
	_check(pilot.get_current_magazine() == pilot.get_max_magazine(), "Pilot weapon spawns fully loaded (%d/%d)" % [pilot.get_current_magazine(), pilot.get_max_magazine()])

	# 2. Fire weapon and verify magazine decrement
	var init_mag = pilot.get_current_magazine()
	pilot.current_magazine -= 1
	_check(pilot.get_current_magazine() == init_mag - 1, "Magazine decrements after firing")

	# 3. Manual Reload [R]
	var init_reserve = pilot.get_reserve_ammo()
	pilot.start_reload()
	_check(pilot.is_currently_reloading(), "start_reload() triggers is_reloading = true")
	_check(pilot.get_reload_duration() > 0.0, "Reload duration is positive (%.1fs)" % pilot.get_reload_duration())

	# 4. Progress reload time
	pilot._physics_process(pilot.get_reload_duration() + 0.1)
	_check(not pilot.is_currently_reloading(), "Reload completes after duration expires")
	_check(pilot.get_current_magazine() == pilot.get_max_magazine(), "Magazine restored to full (%d)" % pilot.get_max_magazine())
	_check(pilot.get_reserve_ammo() == init_reserve - 1, "Reserve ammo consumed exactly 1 round for reload")

	# 5. Empty Magazine Auto-Reload Trigger
	pilot.current_magazine = 0
	pilot._try_fire()
	_check(pilot.is_currently_reloading(), "Firing with empty magazine automatically triggers reload")

	pilot.queue_free()
