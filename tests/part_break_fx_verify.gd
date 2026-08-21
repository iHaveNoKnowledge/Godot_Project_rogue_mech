extends Node3D

## Verification test for the Multi-type Part Break VFX System:
## - Armor Shatter Debris (flying metal shards, spark trails, ricochet particles)
## - Fiery Explosion Blast (fire burst ball, rolling flames, smoke plume)
## - Heavy Blunt Impact (expanding shockwave, heavy plate chunks)
## - EMP Arc Overload (crackling high-voltage electrical arcs)
## - Catastrophic Frame Destruction (combined blast with shrapnel & persistent smoke emitter)

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("PART_BREAK_OK: %s" % msg)
	else:
		_fails += 1
		print("PART_BREAK_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Part Break VFX Verification ---")
	await _test_effect_factory_methods()
	await _test_mecha_health_part_break_variants()

	print("PART_BREAK_FX_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_effect_factory_methods() -> void:
	# 1. Test armor shatter debris spawning
	var initial_children = get_child_count()
	EffectFactory.spawn_armor_shatter_debris(get_tree(), Vector3(0, 1, 0), 10, 0.25, Color(0.7, 0.7, 0.7), self)
	_check(get_child_count() > initial_children, "spawn_armor_shatter_debris added shard nodes to scene")

	# 2. Test electrical arc burst spawning
	var mid_children = get_child_count()
	EffectFactory.spawn_electrical_arc_burst(get_tree(), Vector3(0, 1, 0), 6, 0.8, 0.35, self)
	_check(get_child_count() > mid_children, "spawn_electrical_arc_burst added arc nodes to scene")

	# 3. Test damaged smoke emitter attachment
	var limb := Node3D.new()
	add_child(limb)
	var emitter = EffectFactory.spawn_damaged_smoke_emitter(limb, Vector3.ZERO)
	_check(emitter != null and limb.get_node_or_null("DamagedSmokeEmitter") != null, "spawn_damaged_smoke_emitter attached GPUParticles3D to limb")
	limb.queue_free()


func _test_mecha_health_part_break_variants() -> void:
	var mech_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mech: CharacterBody3D = mech_scene.instantiate()
	mech.position = Vector3(0, 5, 0)
	add_child(mech)
	await get_tree().process_frame
	await get_tree().process_frame

	var hs: MechaHealthBase = mech.get_node_or_null("HealthSystem")
	_check(hs != null, "Mech has HealthSystem")

	# 1. Pierce/Kinetic damage -> Armor Shatter Debris
	var count_before = get_child_count()
	hs.take_damage_to_part("arm_left", 9999.0, "pierce", "armor")
	_check(hs.parts["arm_left"]["armor_broken"], "ArmLeft armor broken by pierce")
	_check(get_child_count() > count_before, "Pierce armor break spawned shatter debris nodes")

	# 2. Heat damage -> Fire Explosion Burst
	count_before = get_child_count()
	hs.take_damage_to_part("arm_right", 9999.0, "heat", "armor")
	_check(hs.parts["arm_right"]["armor_broken"], "ArmRight armor broken by heat")
	_check(get_child_count() > count_before, "Heat armor break spawned fire burst nodes")

	# 3. Blunt damage -> Heavy Impact & Shockwave Ring
	count_before = get_child_count()
	hs.take_damage_to_part("leg_left", 9999.0, "blunt", "armor")
	_check(hs.parts["leg_left"]["armor_broken"], "LegLeft armor broken by blunt")
	_check(get_child_count() > count_before, "Blunt armor break spawned shockwave and debris nodes")

	# 4. EMP damage -> Electrical Arc Burst
	count_before = get_child_count()
	hs.take_damage_to_part("leg_right", 9999.0, "emp", "armor")
	_check(hs.parts["leg_right"]["armor_broken"], "LegRight armor broken by EMP")
	_check(get_child_count() > count_before, "EMP armor break spawned electrical arc nodes")

	# 5. Frame Destroyed -> Catastrophic Frame Destruction
	count_before = get_child_count()
	hs.take_damage_to_part("arm_left", 9999.0, "kinetic", "frame")
	_check(hs.parts["arm_left"]["destroyed"], "ArmLeft frame destroyed")
	_check(get_child_count() > count_before, "Frame destruction spawned catastrophic blast & debris nodes")

	mech.queue_free()
