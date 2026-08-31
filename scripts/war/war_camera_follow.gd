extends Node

var _cam: Camera3D = null
var _target: Node3D = null
var _offset: Vector3 = Vector3(0, 6, 12)


func setup(cam: Camera3D, target: Node3D) -> void:
	_cam = cam
	_target = target


func _process(_delta: float) -> void:
	if _cam == null or _target == null or not is_instance_valid(_target):
		return
	if not _cam.is_inside_tree():
		return
	var tgt_pos = _target.global_position + _offset
	_cam.global_position = _cam.global_position.lerp(tgt_pos, 0.08)
	_cam.look_at(_target.global_position + Vector3(0, 1.5, 0), Vector3.UP)
