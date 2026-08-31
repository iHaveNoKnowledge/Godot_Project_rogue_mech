extends Node
class_name WarAIJumpSystem

## AI jump over obstacles — both sides (per PLAN.md)

var _ray: RayCast3D = null


func setup(mecha: CharacterBody3D) -> void:
	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -3)
	_ray.enabled = true
	_ray.collision_mask = 2
	mecha.add_child(_ray)


func try_jump(mecha: CharacterBody3D) -> bool:
	if _ray == null or not _ray.is_colliding():
		return false
	if not mecha.is_on_floor():
		return false
	mecha.velocity.y = 8.5
	return true
