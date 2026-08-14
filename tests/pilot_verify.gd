extends Node

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("PILOT OK: " + name)
	else:
		_fails += 1
		printerr("PILOT FAIL: " + name)


func _ready() -> void:
	GlobalData.reset_run_data()
	await get_tree().process_frame

	# --- Baseline state ---
	_check(GlobalData.get_pilot_max_hp() == 100.0, "pilot max HP defaults to 100")
	_check(GlobalData.get_pilot_hp() == 100.0, "pilot starts at full HP")
	_check(not PilotSystem.is_injured(), "healthy pilot is not injured")
	_check(GlobalData.get_pilot_weapons().size() == 1, "pilot starts with one personal weapon")
	_check(GlobalData.get_pilot_ammo("kinetic") == 120, "pilot starts with kinetic ammo")

	# --- Damage / eject ---
	PilotSystem.take_damage(40)
	_check(GlobalData.get_pilot_hp() == 60.0, "pilot takes 40 damage")
	_check(PilotSystem.is_injured(), "damaged pilot is injured")
	PilotSystem.take_damage(999.0)
	_check(GlobalData.get_pilot_hp() == 0.0, "pilot HP clamps at 0")
	_check(get_hp_after_eject() == 0.0, "eject damage cannot drop below 0")

	# --- Healing items ---
	var restored := PilotSystem.heal(25.0)
	_check(restored == 25.0, "heal restores exactly 25")
	_check(GlobalData.get_pilot_hp() == 25.0, "pilot HP now 25")
	restored = PilotSystem.heal(200.0)
	_check(restored == 75.0, "heal clamps at max HP")
	_check(GlobalData.get_pilot_hp() == 100.0, "pilot back at full HP")

	# --- Item inventory + use ---
	PilotSystem.take_damage(70)
	_check(GlobalData.get_pilot_hp() == 30.0, "pilot at 30 HP before medkit")
	_check(PilotSystem.get_item_count("medkit_small") == 0, "no medkit owned yet")
	var used := PilotSystem.use_heal_item("medkit_small")
	_check(used == 0.0, "cannot use a medkit you do not own")
	PilotSystem.add_item("medkit_small")
	PilotSystem.add_item("medkit_small")
	_check(PilotSystem.get_item_count("medkit_small") == 2, "two small medkits owned")
	used = PilotSystem.use_heal_item("medkit_small")
	_check(used == 30.0, "small medkit heals 30")
	_check(GlobalData.get_pilot_hp() == 60.0, "pilot at 60 HP after small medkit")
	_check(PilotSystem.get_item_count("medkit_small") == 1, "one small medkit consumed")

	# Cannot heal when already full.
	PilotSystem.heal(200.0)
	used = PilotSystem.use_heal_item("medkit_small")
	_check(used == 0.0, "cannot waste a medkit at full HP")

	# Surgical kit = full restore.
	PilotSystem.take_damage(40)
	PilotSystem.add_item("medkit_large")
	used = PilotSystem.use_heal_item("medkit_large")
	_check(used == 40.0, "surgical kit restores to full")
	_check(GlobalData.get_pilot_hp() == 100.0, "pilot at full HP after surgical kit")
	_check(PilotSystem.get_item_count("medkit_large") == 0, "surgical kit consumed")

	# --- City trading ---
	var credits_before := GlobalData.credits
	var price := PilotSystem.get_item_price("medkit_small")
	_check(price == 50, "small medkit price is 50 credits")
	# Give the pilot enough credits to buy one medkit.
	GlobalData.gain_credits(1000)
	_check(PilotSystem.buy_item("medkit_small"), "can buy a medkit at a city")
	# One small medkit was already owned/consumed earlier, so buying one more
	# brings the stack back up to 2 (1 leftover + 1 bought).
	_check(PilotSystem.get_item_count("medkit_small") == 2, "bought medkit is in inventory")
	_check(GlobalData.credits == credits_before + 1000 - 50, "buy spent exactly 50 credits")
	var before_ammo := GlobalData.get_pilot_ammo("energy")
	var bought := PilotSystem.buy_ammo("energy", 20)
	_check(bought == 20, "bought 20 energy ammo")
	_check(GlobalData.get_pilot_ammo("energy") == before_ammo + 20, "energy ammo increased")
	# Can't buy an unknown item.
	_check(not PilotSystem.buy_item("nonexistent"), "unknown item cannot be bought")

	# --- On-mech-destroyed wounding ---
	GlobalData.pilot_hp = 100.0
	PilotSystem.on_mecha_destroyed()
	_check(GlobalData.get_pilot_hp() == 65.0, "eject wounds the pilot (100 - 35)")
	_check(PilotSystem.is_injured(), "wounded pilot is injured after mech loss")

	# --- Save/load roundtrip preserves pilot state ---
	GlobalData.pilot_hp = 42.0
	GlobalData.pilot_items = {"medkit_medium": 2}
	PilotSystem.add_weapon("res://resources/mech/stock/weapon_machine_gun.tres")
	GlobalData.save_run()
	GlobalData.pilot_hp = 100.0
	GlobalData.pilot_items = {}
	GlobalData.pilot_weapons = []
	_check(GlobalData.load_run(), "save loads back")
	_check(GlobalData.get_pilot_hp() == 42.0, "pilot HP survives save/load")
	_check(GlobalData.get_pilot_item_count("medkit_medium") == 2, "pilot items survive save/load")
	_check(GlobalData.get_pilot_weapons().size() == 2, "pilot weapons survive save/load")

	print("PILOT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func get_hp_after_eject() -> float:
	# on_mecha_destroyed also takes 35 damage; called when HP already 0 stays 0.
	var before := GlobalData.get_pilot_hp()
	PilotSystem.on_mecha_destroyed()
	return GlobalData.get_pilot_hp()
