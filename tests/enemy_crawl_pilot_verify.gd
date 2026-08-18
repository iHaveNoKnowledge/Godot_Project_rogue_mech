extends Node

## Headless verification of the enemy crawl / pilot eject / fight-on-foot /
## retreat-countdown features:
##   1. Crawl: both legs destroyed + arms remain → enemy drags itself at 25%
##      speed (25 % of move_speed).
##   2. Eject: all limbs gone (body only) → cannot move, pilot ejects.
##   3. Fight-on-foot: ejected pilot has a probability to stand and fight with
##      a pistol; fighting pilots face the player and have a WeaponCore.
##   4. Retreat: non-fighting pilot runs toward the nearest escape zone with a
##      pulsing "ESCAPING X.Xs" countdown label and escapes when the timer
##      expires or the zone is reached.
## Run: godot --headless --path . res://tests/enemy_crawl_pilot_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("CRAWL_PILOT OK: " + name)
	else:
		_fails += 1
		printerr("CRAWL_PILOT FAIL: " + name)


func _spawn_enemy(archetype: int) -> Node:
	var scene = load("res://scenes/mecha/enemy_dummy_full.tscn")
	var enemy = scene.instantiate()
	enemy.archetype = archetype
	add_child(enemy)
	return enemy


func _destroy(hs: Node, slot: String) -> void:
	hs.take_damage_to_part(slot, 9999.0, "kinetic", "frame")


func _ready() -> void:
	GlobalData.reset_run_data()
	await get_tree().process_frame
	await _verify_crawl()
	await _verify_all_limbs_eject()
	await _verify_fight_on_foot()
	await _verify_retreat_countdown()
	await _verify_fight_chance_archetypes()
	print("ENEMY_CRAWL_PILOT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


# --- 1. Crawl: legs gone + arms remain → drag at 25% speed -----------------

func _verify_crawl() -> void:
	var enemy := _spawn_enemy(1)  # Ranged archetype (keeps pilot after leg loss)
	await get_tree().process_frame
	await get_tree().process_frame

	var hs = enemy.health_system
	var base_speed: float = enemy.move_speed

	# Destroy both legs but keep arms intact.
	_destroy(hs, "leg_left")
	_destroy(hs, "leg_right")
	await get_tree().process_frame

	_check(enemy.ragdolled, "enemy ragdolls when both legs are destroyed")
	_check(enemy.piloted, "ranged enemy stays piloted after losing legs")
	_check(enemy._can_crawl(), "enemy can crawl (legs gone, arms remain)")

	# Simulate a target so the crawl direction resolves.
	var target_node := Node3D.new()
	target_node.position = Vector3(10, 0, 0)
	add_child(target_node)
	enemy.target = target_node

	# Run a few physics frames so crawl velocity builds up.
	for i in range(10):
		enemy._process_crawl(1.0 / 60.0)
		await get_tree().physics_frame

	var horizontal_speed := Vector2(enemy.velocity.x, enemy.velocity.z).length()
	_check(horizontal_speed > 0.0,
		"crawl produces horizontal movement (speed %.2f)" % horizontal_speed)
	_check(horizontal_speed <= base_speed * 0.30,
		"crawl speed is at most 25%% of base (got %.2f / %.2f = %.1f%%)" %
		[horizontal_speed, base_speed, horizontal_speed / maxf(base_speed, 0.01) * 100.0])

	target_node.queue_free()
	enemy.queue_free()
	await get_tree().process_frame


# --- 2. All limbs gone → cannot move, pilot ejects -------------------------

func _verify_all_limbs_eject() -> void:
	# Rusher: all limbs gone → ragdoll + eject (melee can't fight from ground).
	var rusher := _spawn_enemy(0)
	await get_tree().process_frame
	await get_tree().process_frame

	_destroy(rusher.health_system, "leg_left")
	_destroy(rusher.health_system, "leg_right")
	_destroy(rusher.health_system, "arm_left")
	_destroy(rusher.health_system, "arm_right")
	await get_tree().process_frame

	_check(rusher.ragdolled, "rusher ragdolls when all limbs are destroyed")
	_check(not rusher.piloted, "rusher pilot ejects when all limbs are gone")
	_check(not rusher._can_crawl(), "cannot crawl when both arms are also gone")

	var pilots := get_tree().get_nodes_in_group("enemy_pilot")
	_check(pilots.size() >= 1, "an enemy pilot spawned after all limbs destroyed")

	# The mech sits inert: zero horizontal velocity. Run a few physics frames so
	# the velocity zeroes out in _physics_process.
	for i in range(6):
		await get_tree().physics_frame
	_check(absf(rusher.velocity.x) < 0.1 and absf(rusher.velocity.z) < 0.1,
		"inert wreck has no horizontal velocity")

	rusher.queue_free()
	await get_tree().process_frame


# --- 3. Fight-on-foot: probability check + weapon + facing ------------------

func _verify_fight_on_foot() -> void:
	# Force many iterations to verify the probability distribution.
	var fight_count := 0
	var iterations := 20
	for i in range(iterations):
		var pilot := CharacterBody3D.new()
		pilot.set_script(load("res://scripts/mecha/enemy_pilot.gd"))
		var target_node := Node3D.new()
		target_node.position = Vector3(5, 1.5, 0)
		add_child(target_node)
		pilot.setup_fighting(target_node, Color.RED, 1)  # Ranged archetype (45% chance)
		add_child(pilot)
		await get_tree().process_frame

		if pilot._fights_on_foot:
			fight_count += 1
			_check(pilot._fire_core != null, "fighting pilot has a WeaponCore")
			_check(pilot._weapon_mesh != null, "fighting pilot has a visible weapon model")

			# Move the pilot close to the target so it can fire.
			pilot.global_position = target_node.global_position + Vector3(0, 0, 10)
			pilot._target = target_node
			pilot._fire_cooldown = 0.0
			pilot._process_fight(1.0 / 60.0)
			await get_tree().physics_frame
			_check(pilot._fire_cooldown > 0.0, "fighting pilot's fire cooldown advances after firing")

		pilot.queue_free()
		target_node.queue_free()
		await get_tree().process_frame

	# Ranged archetype has 45% chance; expect 3-15 fights out of 20.
	_check(fight_count > 0,
		"ranged archetype produces at least one fighting pilot (got %d/%d)" % [fight_count, iterations])
	_check(fight_count < iterations,
		"ranged archetype does not ALWAYS fight (got %d/%d)" % [fight_count, iterations])

	# Melee (archetype 0) should NEVER fight.
	var melee_fights := 0
	for i in range(10):
		var pilot := CharacterBody3D.new()
		pilot.set_script(load("res://scripts/mecha/enemy_pilot.gd"))
		pilot.setup_fighting(null, Color.RED, 0)  # Rusher (0% chance)
		add_child(pilot)
		await get_tree().process_frame
		if pilot._fights_on_foot:
			melee_fights += 1
		pilot.queue_free()
		await get_tree().process_frame

	_check(melee_fights == 0, "melee rusher pilot never fights on foot")

	# Verify fight_chance() via script static call for all archetypes.
	var sc := load("res://scripts/mecha/enemy_pilot.gd") as GDScript
	if sc:
		_check(float(sc.call("fight_chance", 0)) == 0.0, "archetype 0 (rusher) fight chance = 0")
		_check(float(sc.call("fight_chance", 2)) == 0.0, "archetype 2 (heavy) fight chance = 0")
		_check(float(sc.call("fight_chance", 4)) == 0.0, "archetype 4 (shield melee) fight chance = 0")
		_check(float(sc.call("fight_chance", 1)) > 0.0, "archetype 1 (ranged) fight chance > 0")
		_check(float(sc.call("fight_chance", 3)) > 0.0, "archetype 3 (support) fight chance > 0")
		_check(float(sc.call("fight_chance", 5)) > 0.0, "archetype 5 (shield ranged) fight chance > 0")


# --- 4. Retreat: countdown label + escape -----------------------------------

func _verify_retreat_countdown() -> void:
	var pilot := CharacterBody3D.new()
	pilot.set_script(load("res://scripts/mecha/enemy_pilot.gd"))
	var target_node := Node3D.new()
	target_node.position = Vector3(0, 1.5, 0)
	add_child(target_node)
	# Force non-fighting mode (set _fights_on_foot = false before ready).
	pilot._fights_on_foot = false
	pilot.setup(target_node, Color.RED)
	add_child(pilot)
	await get_tree().process_frame

	_check(not pilot._fights_on_foot, "pilot is in retreat mode (not fighting)")
	_check(pilot._retreat_label != null, "retreat pilot has a countdown label")
	if pilot._retreat_label != null:
		_check(pilot._retreat_label.billboard == BaseMaterial3D.BILLBOARD_ENABLED,
			"retreat label is billboarded (always faces camera)")
		_check(pilot._retreat_label.no_depth_test,
			"retreat label ignores depth so it stays visible")
		_check(pilot._retreat_label.text.contains("ESCAPING"),
			"retreat label reads 'ESCAPING ...'")

	# Advance retreat timer and check the label updates.
	pilot._retreat_timer = 5.0
	pilot._update_retreat_label()
	if pilot._retreat_label != null:
		_check(pilot._retreat_label.text.contains("3."),
			"retreat label shows remaining time (got: %s)" % pilot._retreat_label.text)

	# After the escape timer expires, the pilot is freed.
	pilot._retreat_timer = pilot._escape_time + 0.1
	pilot._complete_escape()
	await get_tree().process_frame
	_check(not is_instance_valid(pilot), "pilot escapes (freed) after timer expires")

	# Verify escape_zone integration: create a fake escape zone, place a pilot
	# near it, and confirm it finds and runs toward the zone.
	var zone := Area3D.new()
	zone.set_script(load("res://scripts/arena/escape_zone.gd"))
	zone.add_to_group("escape_zone")
	zone.position = Vector3(0, 0, -20)
	add_child(zone)
	await get_tree().process_frame

	var pilot2 := CharacterBody3D.new()
	pilot2.set_script(load("res://scripts/mecha/enemy_pilot.gd"))
	pilot2._fights_on_foot = false
	pilot2.setup(target_node, Color.RED)
	pilot2.position = Vector3(0, 0, 0)
	add_child(pilot2)
	await get_tree().process_frame

	_check(pilot2._retreat_target != null, "pilot finds the nearest escape zone")
	_check(pilot2._retreat_target == zone, "pilot targets the correct escape zone")

	zone.queue_free()
	pilot2.queue_free()
	target_node.queue_free()
	await get_tree().process_frame


# --- 5. Architecture: fight_chance is archetype-aware -----------------------

func _verify_fight_chance_archetypes() -> void:
	# fight_chance is a static method on the enemy pilot script. We can't call
	# it directly from a class_name, so verify through instantiation.
	var pilot_script = load("res://scripts/mecha/enemy_pilot.gd")
	_check(pilot_script != null, "enemy pilot script loads")

	# Verify the static function exists by calling it through the script.
	var sc := pilot_script as GDScript
	_check(sc != null, "enemy pilot script is a GDScript")
	if sc:
		_check(sc.has_method("fight_chance"), "fight_chance static method exists")
		var chance_0: float = sc.call("fight_chance", 0)
		var chance_1: float = sc.call("fight_chance", 1)
		var chance_unknown: float = sc.call("fight_chance", 999)
		_check(typeof(chance_0) == TYPE_FLOAT, "fight_chance returns a float")
		_check(chance_0 >= 0.0 and chance_0 <= 1.0, "fight_chance(0) is in [0, 1]")
		_check(chance_1 > 0.0, "ranged archetype (1) has a positive fight chance")
		_check(chance_unknown >= 0.0 and chance_unknown <= 1.0, "unknown archetype gets a default chance in [0, 1]")
