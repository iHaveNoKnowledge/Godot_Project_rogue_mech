extends Node

## Headless verification of combat part-destruction rules:
##   1. A destroyed arm disarms that hand (player) — it can't fire, punch or
##      raise a shield, while the other hand keeps working.
##   2. Enemies: one lost arm still attacks; BOTH arms destroyed → can_attack()
##      false and the mech withdraws.
##   3. Both legs destroyed → ragdoll: a melee rusher ejects a fleeing pilot,
##      a ranged mech keeps its pilot and fires from the ground (movement froze).
##   4. Pilot status light: red for hostiles / blue for the player's side, off
##      when pilot-less or the head is destroyed; destroyed parts spark ONLY
##      while a pilot runs the machine.
##   5. Defeated enemies can drop a salvaged armor instance (occasional).
## Run: godot --headless --path . res://tests/combat_disarm_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("DISARM OK: " + name)
	else:
		_fails += 1
		printerr("DISARM FAIL: " + name)


func _ready() -> void:
	GlobalData.reset_run_data()
	await _verify_player_arm_gate()
	await _verify_enemy_arm_disarm()
	await _verify_enemy_ragdoll()
	await _verify_pilot_light_and_sparks()
	await _verify_salvaged_armor()
	await _verify_scrap_patch_shatters()
	print("COMBAT_DISARM_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _count_mesh_children(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		count += 1
	for child in node.get_children():
		count += _count_mesh_children(child)
	return count


# Counts only the electrical-arc spark meshes (named PartSpark). Physical part
# debris (RigidBody3D chunks) is a separate effect and must NOT count here.
func _count_sparks(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and node.name == "PartSpark":
		count += 1
	for child in node.get_children():
		count += _count_sparks(child)
	return count


func _spawn_enemy(archetype: int) -> Node:
	# FULL layout (enemy_dummy_full.tscn) ships the six body slots the part-
	# destruction rules need. The SIMPLE placeholder scene only has a single
	# "body" part, so arm/leg damage there just destroys the whole mech.
	var scene = load("res://scenes/mecha/enemy_dummy_full.tscn")
	var enemy = scene.instantiate()
	enemy.archetype = archetype
	add_child(enemy)
	return enemy


func _destroy(hs: Node, slot: String) -> void:
	hs.take_damage_to_part(slot, 9999.0, "kinetic", "frame")


func _verify_player_arm_gate() -> void:
	var mecha := CharacterBody3D.new()
	mecha.name = "Mecha"
	add_child(mecha)
	var hs := Node3D.new()
	hs.set_script(load("res://scripts/mecha/mecha_health.gd"))
	hs.name = "HealthSystem"
	hs.is_player = true
	mecha.add_child(hs)
	var wm := Node3D.new()
	wm.set_script(load("res://scripts/mecha/weapon_manager.gd"))
	wm.name = "WeaponManager"
	mecha.add_child(wm)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(wm._hand_usable("left"), "intact arms can fire")
	_destroy(hs, "arm_left")
	await get_tree().process_frame
	_check(hs.is_part_destroyed("arm_left"), "left arm frame destroyed by damage")
	_check(not wm._hand_usable("left"), "destroyed left arm disarms the left hand")
	_check(wm._hand_usable("right"), "right hand stays usable")

	# A punch with the broken hand is refused (no cooldown consumed)...
	var fist = wm._fist()
	wm._try_fire("left", null)
	_check(wm._core_for_weapon(fist).cooldown == 0.0, "broken arm cannot even punch (no cooldown consumed)")
	# ...while the intact hand punches normally.
	wm._try_fire("right", null)
	_check(wm._core_for_weapon(fist).cooldown > 0.0, "intact hand punches normally (cooldown consumed)")
	wm._core_for_weapon(fist).tick(1.0)

	# A destroyed arm can't SELECT weapons (key 1/3 swap is blocked), but it
	# still fights with a SHOULDER BASH that consumes its own cooldown.
	wm._start_selection("left")
	_check(not wm.holding_left, "destroyed arm cannot open the weapon-swap selection")
	wm._start_selection("right")
	_check(wm.holding_right, "intact arm still opens the weapon-swap selection")
	wm._commit_selection("right")
	wm._shoulder_bash("left")
	_check(wm._core_for_weapon(wm._shoulder_weapon_resource()).cooldown > 0.0,
		"shoulder bash consumes the shoulder weapon cooldown")
	wm._core_for_weapon(wm._shoulder_weapon_resource()).tick(1.0)

	# Melee capability: an empty hand and a destroyed arm both count as melee
	# (fist / shoulder), a gun does not.
	wm.right_hand = null
	wm.left_hand = null
	_check(wm._hand_is_melee_capable("left"), "destroyed arm counts as melee (shoulder bash)")
	_check(wm._hand_is_melee_capable("right"), "empty hand counts as melee (bare fist)")
	wm.right_hand = load("res://resources/mech/stock/weapon_beam_rifle.tres")
	_check(not wm._hand_is_melee_capable("right"), "ranged weapon does not count as melee")
	wm.right_hand = null

	# Dual melee charge: with both sides melee (left shoulder + right fist), a
	# fire press DEFERS; when the second button lands inside the window the pair
	# becomes ONE straight charge (the charge core consumes a shot).
	wm._last_left_press_ms = Time.get_ticks_msec() - 5000  # stale, not a pair
	wm._pending_fire = ""
	_check(wm._fire_press("left"), "first melee press is deferred for the dual window")
	_check(wm._pending_fire == "left", "deferred press remembers the waiting side")
	wm._last_right_press_ms = Time.get_ticks_msec()
	_check(wm._fire_press("right"), "second melee press completes the dual charge")
	_check(wm._pending_fire == "", "dual charge clears the pending press")
	_check(wm._core_for_weapon(wm._charge_weapon_resource()).cooldown > 0.0,
		"dual charge consumes the charge weapon cooldown")
	wm._core_for_weapon(wm._charge_weapon_resource()).tick(1.0)

	# When the window expires alone, the deferred press commits as a normal fire.
	# The left arm is destroyed, so the expired press becomes a SHOULDER BASH
	# (consuming the shoulder core), not a fist punch.
	wm._last_left_press_ms = Time.get_ticks_msec() - 5000
	wm._pending_fire = "left"
	wm._pending_fire_ms = Time.get_ticks_msec() - 1000
	wm._commit_normal_fire("left")
	_check(wm._core_for_weapon(wm._shoulder_weapon_resource()).cooldown > 0.0,
		"expired deferral on a destroyed arm commits as a shoulder bash")
	wm._core_for_weapon(wm._shoulder_weapon_resource()).tick(1.0)

	# Player side wears a BLUE status light.
	_check(hs._pilot_light != null, "player mech wears a pilot status light")
	if hs._pilot_light != null:
		_check(hs._pilot_light.light_color.b > 0.6, "player-side light is BLUE")
	mecha.queue_free()
	await get_tree().process_frame


func _verify_enemy_arm_disarm() -> void:
	var enemy := _spawn_enemy(0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(enemy.can_attack(), "intact rusher can attack")
	_destroy(enemy.health_system, "arm_left")
	await get_tree().process_frame
	_check(enemy.can_attack(), "one lost arm still attacks with the other")
	_destroy(enemy.health_system, "arm_right")
	await get_tree().process_frame
	_check(not enemy.can_attack(), "both arms destroyed → cannot attack")
	_check(enemy.flee_reason == "disabled", "disarmed enemy withdraws")
	_check(enemy.ragdolled == false, "lost arms alone don't ragdoll the mech")
	enemy.queue_free()
	await get_tree().process_frame


func _verify_enemy_ragdoll() -> void:
	# Melee rusher: both legs blown off → ragdoll + pilot ejects and flees.
	var rusher := _spawn_enemy(0)
	await get_tree().process_frame
	await get_tree().process_frame
	_destroy(rusher.health_system, "leg_left")
	_destroy(rusher.health_system, "leg_right")
	await get_tree().process_frame
	_check(rusher.ragdolled, "rusher ragdolls once both legs are gone")
	_check(not rusher.piloted, "melee rusher ejects its pilot")
	_check(get_tree().get_nodes_in_group("enemy_pilot").size() >= 1, "an enemy pilot spawns and flees")
	rusher.queue_free()
	await get_tree().process_frame

	# Ranged: keeps its pilot and keeps fighting from the ground.
	var ranged := _spawn_enemy(1)
	await get_tree().process_frame
	await get_tree().process_frame
	_destroy(ranged.health_system, "leg_left")
	_destroy(ranged.health_system, "leg_right")
	await get_tree().process_frame
	_check(ranged.ragdolled, "ranged mech ragdolls when it loses both legs")
	_check(ranged.piloted, "ranged pilot stays and fights from the ground")
	_check(ranged.can_attack(), "ragdolled ranged mech can still fire (arms intact)")
	ranged.queue_free()
	await get_tree().process_frame


func _verify_pilot_light_and_sparks() -> void:
	var enemy := _spawn_enemy(1)
	await get_tree().process_frame
	await get_tree().process_frame
	var hs = enemy.health_system
	var light = enemy.get_node_or_null("Head/PilotLight")
	_check(light != null, "enemy mech wears a head pilot light")
	if light:
		_check(light.visible, "piloted enemy light is ON")
		_check(light.light_color.r > 0.6 and light.light_color.b < 0.5, "enemy light is RED")

	# Destroy an arm while piloted → sparks appear at the joint.
	var sparks_before := _count_sparks(self)
	_destroy(hs, "arm_left")
	var saw_spark := false
	for i in range(600):
		if _count_sparks(self) > sparks_before:
			saw_spark = true
			break
		await get_tree().process_frame
	_check(saw_spark, "destroyed part throws sparks while piloted")

	# Pilot-less mech: light off and no new sparks from further damage.
	hs.set_piloted(false)
	if light:
		_check(not light.visible, "pilot-less mech light goes OFF")
	var quiet_before := _count_sparks(self)
	_destroy(hs, "arm_right")
	var quiet_max := quiet_before
	for i in range(120):
		await get_tree().process_frame
		quiet_max = maxi(quiet_max, _count_sparks(self))
	_check(quiet_max <= quiet_before, "an empty damaged mech throws no sparks")

	# Head destroyed → the status light dies even while piloted.
	hs.set_piloted(true)
	_destroy(hs, "head")
	await get_tree().process_frame
	if light:
		_check(not light.visible, "destroyed head kills the status light")

	# A destroyed BODY = the engine core is gone: no power anywhere, so no
	# sparks even from other destroyed limbs and the pilot light dies too.
	hs.set_piloted(true)
	# Rebuild a fresh enemy: previous damage destroyed head/arms and the body
	# may already be flagged, so start clean for the body-core rule.
	enemy.queue_free()
	await get_tree().process_frame
	var body_enemy := _spawn_enemy(0)
	await get_tree().process_frame
	await get_tree().process_frame
	var bhs = body_enemy.health_system
	var blight = body_enemy.get_node_or_null("Head/PilotLight")
	var b_sparks_before := _count_sparks(self)
	_destroy(bhs, "arm_left")
	_destroy(bhs, "leg_right")
	await get_tree().process_frame
	var b_saw_spark := false
	for i in range(300):
		if _count_sparks(self) > b_sparks_before:
			b_saw_spark = true
			break
		await get_tree().process_frame
	_check(b_saw_spark, "arms+legs damaged with a live body still spark")
	var b_quiet_before := _count_sparks(self)
	_destroy(bhs, "body")
	await get_tree().process_frame
	if blight:
		_check(not blight.visible, "destroyed body kills the pilot light")
	var b_quiet_max := b_quiet_before
	for i in range(120):
		await get_tree().process_frame
		b_quiet_max = maxi(b_quiet_max, _count_sparks(self))
	_check(b_quiet_max <= b_quiet_before, "destroyed body stops all sparks (no engine core)")
	body_enemy.queue_free()
	await get_tree().process_frame


func _verify_salvaged_armor() -> void:
	var loot := Node3D.new()
	loot.set_script(load("res://scripts/systems/loot_system.gd"))
	loot.name = "LootSystem"
	add_child(loot)
	var inst: Dictionary = loot._roll_salvaged_armor()
	_check(not inst.is_empty() and inst.has("uid"), "salvaged armor roll produces a real instance")
	if not inst.is_empty():
		_check(GlobalData.get_armor_instance(str(inst["uid"])).is_empty(), "fresh instance isn't already in the inventory")
	var body := CharacterBody3D.new()
	body.add_to_group("mecha")
	add_child(body)
	var pickup := Area3D.new()
	pickup.set_meta("loot_data", {"type": "armor", "instance": inst})
	add_child(pickup)
	var inv_before: int = GlobalData.armor_inventory.size()
	loot._on_pickup_body_entered(body, pickup)
	_check(GlobalData.armor_inventory.size() == inv_before + 1, "picking up salvaged armor adds it to the inventory")
	body.queue_free()
	loot.queue_free()
	await get_tree().process_frame


# An emergency scrap patch acts exactly like normal armor: when its armor HP
# hits zero the patch SHATTERS — it is removed from GlobalData.scrap_patches
# so the crude plates fall off, the hangar stops showing it, and the next
# battle doesn't re-apply its weak scrap stats.
func _verify_scrap_patch_shatters() -> void:
	var mecha := CharacterBody3D.new()
	mecha.name = "Mecha"
	add_child(mecha)

	# Install a scrap patch on the body slot BEFORE the health system initializes
	# (its _init_parts reads GlobalData.scrap_patches to apply the patch stats).
	GlobalData.scrap_patches["body"] = {
		"scrap_armor_hp": 40.0,
		"armor_class": 0.6,
		"scrap_frame_hp": 30.0,
		"primitives": []
	}
	var hs := Node3D.new()
	hs.set_script(load("res://scripts/mecha/mecha_health.gd"))
	hs.name = "HealthSystem"
	hs.is_player = true
	mecha.add_child(hs)

	await get_tree().process_frame
	await get_tree().process_frame

	_check(GlobalData.scrap_patches.has("body"), "setup: scrap patch is installed on the body")
	_check(is_equal_approx(float(hs.parts["body"]["max_armor"]), 40.0), "patch stats replace the body armor HP")

	# Destroy the patch's armor (no frame damage — the patch's armor breaks
	# exactly like a normal plate would).
	hs.take_damage_to_part("body", 9999.0, "kinetic", "armor")
	await get_tree().process_frame

	_check(hs.is_armor_broken("body"), "patch armor breaks like normal armor")
	_check(not GlobalData.scrap_patches.has("body"), "shattered scrap patch is removed from the persistent stash")

	mecha.queue_free()
	await get_tree().process_frame
