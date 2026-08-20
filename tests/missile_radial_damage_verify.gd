extends Node

## Verifies:
## 1. Bullets (kinetic/point-damage): damage ONLY the exact hit part.
## 2. Missiles/Explosions (explosive radial damage):
##    - Primary impact part takes direct blast damage.
##    - Adjacent armor parts take proportional splash damage based on distance.
##    - Farther parts take less/no damage.

var _fails := 0
var _checks := 0

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("FAIL: " + label)
	else:
		print("RADIAL_OK: " + label)

func _ready() -> void:
	var fx := EffectManager.new()
	fx.name = "EffectManager"
	add_child(fx)

	# 1. Setup mock mecha with MechaHealth
	var mecha := CharacterBody3D.new()
	mecha.name = "TestMecha"
	add_child(mecha)

	# Setup section nodes to represent physical limb positions
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 2.0, 0)
	mecha.add_child(head)

	var body := Node3D.new()
	body.name = "Body"
	body.position = Vector3(0, 1.2, 0)
	mecha.add_child(body)

	var arm_r := Node3D.new()
	arm_r.name = "ArmRight"
	arm_r.position = Vector3(0.9, 1.4, 0)
	mecha.add_child(arm_r)

	var arm_l := Node3D.new()
	arm_l.name = "ArmLeft"
	arm_l.position = Vector3(-0.9, 1.4, 0)
	mecha.add_child(arm_l)

	var leg_r := Node3D.new()
	leg_r.name = "LegRight"
	leg_r.position = Vector3(0.4, 0.4, 0)
	mecha.add_child(leg_r)

	var leg_l := Node3D.new()
	leg_l.name = "LegLeft"
	leg_l.position = Vector3(-0.4, 0.4, 0)
	mecha.add_child(leg_l)

	var health_script = preload("res://scripts/mecha/mecha_health_base.gd")
	var hs := Node3D.new()
	hs.name = "HealthSystem"
	hs.set_script(health_script)
	mecha.add_child(hs)

	# Initialize parts
	for slot in ["head", "body", "arm_right", "arm_left", "leg_right", "leg_left"]:
		hs.parts[slot] = {
			"armor_hp": 100.0,
			"max_armor": 100.0,
			"frame_hp": 100.0,
			"max_frame": 100.0,
			"armor_broken": false,
			"destroyed": false,
			"mesh": null
		}

	# Test 1: Kinetic Bullet hit on Right Arm
	var arm_r_pos = arm_r.global_position
	hs.take_damage_at_point(30.0, arm_r_pos, "kinetic")
	_check(hs.parts["arm_right"]["armor_hp"] == 70.0, "Kinetic bullet damaged only Right Arm (hp=70.0)")
	_check(hs.parts["body"]["armor_hp"] == 100.0, "Kinetic bullet did NOT damage Body (hp=100.0)")
	_check(hs.parts["head"]["armor_hp"] == 100.0, "Kinetic bullet did NOT damage Head (hp=100.0)")

	# Reset Right Arm HP
	hs.parts["arm_right"]["armor_hp"] = 100.0

	# Test 2: Missile Explosive Blast on Right Arm
	hs.take_damage_at_point(50.0, arm_r_pos, "explosive")
	var r_arm_hp: float = hs.parts["arm_right"]["armor_hp"]
	var body_hp: float = hs.parts["body"]["armor_hp"]
	var head_hp: float = hs.parts["head"]["armor_hp"]
	var l_arm_hp: float = hs.parts["arm_left"]["armor_hp"]

	_check(r_arm_hp < 100.0, "Missile blast hit primary Right Arm (hp=%.1f < 100)" % r_arm_hp)
	_check(body_hp < 100.0, "Missile blast radiated splash damage to Body (hp=%.1f < 100)" % body_hp)
	_check(head_hp < 100.0, "Missile blast radiated splash damage to Head (hp=%.1f < 100)" % head_hp)
	_check(r_arm_hp < body_hp, "Direct hit part took more damage than adjacent splash parts (r_arm_hp %.1f < body_hp %.1f)" % [r_arm_hp, body_hp])
	_check(body_hp < l_arm_hp or l_arm_hp == 100.0, "Close parts took more splash damage than distant opposite arm (body_hp %.1f <= l_arm_hp %.1f)" % [body_hp, l_arm_hp])

	print("MISSILE_RADIAL_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
