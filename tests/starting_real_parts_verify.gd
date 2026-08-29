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
	print("--- Running starting_real_parts_verify ---")
	_test_fresh_game_start_parts()
	_test_hollow_ghost_part_recovery()
	_test_hangar_ui_displays_real_names()

	print("STARTING_REAL_PARTS_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _test_fresh_game_start_parts() -> void:
	print("Testing Fresh Game Start Real Parts Integrity...")
	GlobalData.reset_run_data()

	for slot in GlobalData.MECHA_SLOTS:
		var part = GlobalData.weapons.equipped_parts.get(slot)
		_check(part != null, "Equipped part exists for slot %s" % slot)
		_check(part is Dictionary and not part.is_empty(), "Part is non-empty dictionary for slot %s" % slot)
		_check(part.has("name") and part["name"] != "" and part["name"] != "Unknown Armor", "Part has valid real name '%s' for slot %s" % [part.get("name", ""), slot])
		_check(part.has("uid") and part["uid"] != "", "Part has unique instance UID for slot %s" % slot)
		_check(part.has("hp") or part.has("max_hp"), "Part has HP stat for slot %s" % slot)

		var frame = GlobalData.weapons.equipped_frames.get(slot)
		_check(frame != null and frame.has("name") and frame["name"] != "", "Equipped frame exists with valid name for slot %s" % slot)


func _test_hollow_ghost_part_recovery() -> void:
	print("Testing Recovery of Hollow / Corrupted Ghost Parts from Old Saves...")
	GlobalData.reset_run_data()

	# Simulate a hollow/ghost part with only a uid and no name/stats
	GlobalData.weapons.equipped_parts["arm_left"] = {"uid": "a_ghost_123", "equipped": true}
	GlobalData.weapons.equipped_parts["leg_right"] = {}

	# Run instance validation & default recovery
	SaveGameIO.ensure_equipped_parts_are_instances()
	ArmorSystem.ensure_default_equipped_parts()

	var healed_arm = GlobalData.weapons.equipped_parts.get("arm_left")
	_check(healed_arm != null and healed_arm.has("name") and healed_arm["name"] != "Unknown Armor", "Hollow arm_left healed into real part: " + str(healed_arm.get("name", "")))
	_check(healed_arm.has("hp") and float(healed_arm.get("hp", 0)) > 0, "Healed arm_left has valid positive HP")

	var healed_leg = GlobalData.weapons.equipped_parts.get("leg_right")
	_check(healed_leg != null and healed_leg.has("name") and healed_leg["name"] != "Unknown Armor", "Empty leg_right healed into real part: " + str(healed_leg.get("name", "")))


func _test_hangar_ui_displays_real_names() -> void:
	print("Testing Hangar UI Real Part Names Display...")
	GlobalData.reset_run_data()

	var hangar_scene = preload("res://scenes/ui/hangar_scene.tscn")
	var hangar = hangar_scene.instantiate()
	add_child(hangar)

	for slot in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
		hangar.slot_panel.select(slot)
		var text = hangar.currently_equipped_label.text
		_check(text != "" and text != "Unknown Armor" and not "Unknown" in text, "Slot %s displays real name in Hangar: '%s'" % [slot, text])

	hangar.queue_free()
