extends Node

func _ready() -> void:
	print("--- Starting Full Project Syntax & GDScript Compilation Verification ---")
	var passed := 0
	var failed := 0
	var files: Array[String] = []
	_scan_dir("res://scripts", files)
	_scan_dir("res://tests", files)
	_scan_dir("res://autoload", files)
	_scan_dir("res://resources", files)

	for file_path in files:
		if not file_path.ends_with(".gd"):
			continue
		var script = load(file_path)
		if script != null and script is GDScript:
			passed += 1
		else:
			failed += 1
			printerr("FAILED TO LOAD: ", file_path)

	print("==================================================")
	print("PROJECT SYNTAX VERIFICATION RESULTS:")
	print("Passed: %d | Failed: %d" % [passed, failed])
	print("==================================================")
	get_tree().quit(1 if failed > 0 else 0)

func _scan_dir(dir_path: String, out_files: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			var full_path := dir_path.path_join(name)
			if dir.current_is_dir():
				_scan_dir(full_path, out_files)
			else:
				out_files.append(full_path)
		name = dir.get_next()
