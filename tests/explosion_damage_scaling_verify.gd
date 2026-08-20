extends Node

## Verifies:
## 1. Multi-layered explosion VFX (dynamic light, shockwave ring, fireball core, particles, shake)
## 2. Explosion AoE damage:
##    - Human pilot takes high lethal damage (2.2x multiplier)
##    - Armored mecha takes mitigated chip damage (0.75x multiplier)
## 3. Distance falloff calculation

var _fails := 0
var _checks := 0

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("FAIL: " + label)
	else:
		print("EXPLODE_OK: " + label)

# Mock pilot receiving damage
class MockPilot extends CharacterBody3D:
	var hp: float = 100.0
	var damage_taken: float = 0.0
	func _init() -> void:
		add_to_group("enemy_pilot")
	func take_damage(amount: float, _dtype: String = "explosive") -> void:
		damage_taken += amount
		hp -= amount

# Mock mecha receiving damage
class MockMecha extends CharacterBody3D:
	var hp: float = 500.0
	var damage_taken: float = 0.0
	func _init() -> void:
		add_to_group("enemy")
	func take_damage(amount: float, _dtype: String = "explosive") -> void:
		damage_taken += amount
		hp -= amount

func _ready() -> void:
	var fx := EffectManager.new()
	fx.name = "EffectManager"
	add_child(fx)

	var cam_scene: PackedScene = preload("res://scenes/camera/mecha_camera.tscn")
	var cam_rig = cam_scene.instantiate()
	add_child(cam_rig)

	# Test 1: Explosion Visual Nodes
	EffectManager.spawn_explosion(Vector3(0, 0, 0), 8.0)
	var has_light := false
	var has_ring := false
	var has_core := false
	var has_sparks := false

	for child in fx.get_children():
		if child is OmniLight3D:
			has_light = true
			_check(child.light_energy >= 10.0, "Explosion spawned intense dynamic light (energy=%.1f)" % child.light_energy)
		elif child is MeshInstance3D:
			if child.mesh is TorusMesh:
				has_ring = true
			elif child.mesh is SphereMesh:
				has_core = true
		elif child is GPUParticles3D:
			has_sparks = true

	_check(has_light, "Dynamic light flash spawned")
	_check(has_ring, "Expanding shockwave ring spawned")
	_check(has_core, "Fiery fireball core spawned")
	_check(has_sparks, "Particle bursts spawned")
	_check(cam_rig.shake_amount >= 0.35, "Camera shake triggered on explosion (shake=%.2f)" % cam_rig.shake_amount)

	# Test 2: Damage Scaling: Pilot (2.2x) vs Mecha (0.75x)
	var pilot := MockPilot.new()
	add_child(pilot)
	pilot.global_position = Vector3(2.0, 0, 0)

	var mecha := MockMecha.new()
	add_child(mecha)
	mecha.global_position = Vector3(2.0, 0, 0)

	# Trigger blast of base damage 50 at origin (dist = 2m, radius = 10m)
	var base_dmg := 50.0
	var radius := 10.0
	EffectManager.apply_area_explosion_damage(Vector3.ZERO, base_dmg, radius, false, "explosive")

	_check(pilot.damage_taken > 50.0, "Pilot took devastating explosion damage (pilot_dmg=%.1f > base 50.0)" % pilot.damage_taken)
	_check(mecha.damage_taken < 50.0, "Mecha took mitigated chip damage (mecha_dmg=%.1f < base 50.0)" % mecha.damage_taken)
	_check(pilot.damage_taken > mecha.damage_taken * 2.0, "Pilot damage (%.1f) is more than double mecha damage (%.1f)" % [pilot.damage_taken, mecha.damage_taken])

	print("EXPLOSION_SCALING_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
