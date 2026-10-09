extends SceneTree

func _initialize() -> void:
	var gd = root.get_node_or_null("GlobalData")
	print("PROBE autoload=" + str(gd != null))
	var S = load("res://scripts/systems/save_game_io.gd")
	gd.weapons.part_damage.clear()
	gd.weapons.part_damage["leg_right"] = 0.5
	gd.weapons.part_damage["head"] = 0.25
	var r1: bool = S.save_run()
	print("PROBE save1=" + str(r1))
	var t1: String = FileAccess.get_file_as_string(gd.SAVE_PATH)
	var j1 = JSON.parse_string(t1)
	print("PROBE j1damage=" + str((j1 as Dictionary).get("damage", {})) + " schema=" + str((j1 as Dictionary).get("schema_version", "MISSING")))
	var lr: bool = S.load_run()
	print("PROBE load=" + str(lr) + " memdamage=" + str(gd.weapons.part_damage))
	var r2: bool = S.save_run()
	print("PROBE save2=" + str(r2))
	var t2: String = FileAccess.get_file_as_string(gd.SAVE_PATH)
	var j2 = JSON.parse_string(t2)
	print("PROBE j2damage=" + str((j2 as Dictionary).get("damage", {})))
	print("PROBE tmp_exists=" + str(FileAccess.file_exists(gd.SAVE_PATH + ".tmp")))
	print("PROBE DONE")
	quit(0)
