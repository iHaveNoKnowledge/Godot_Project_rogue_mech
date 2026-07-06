extends Node3D

func _ready() -> void:
	_init_camera()


func _init_camera() -> void:
	var camera = Camera3D.new()
	camera.position = Vector3(0, 20, 10)
	camera.rotation_degrees.x = -60
	camera.name = "BoardCamera"
	add_child(camera)
