class_name Damageable
extends RefCounted
## -----------------------------------------------------------------------
## DAMAGEABLE — interface for anything that can receive damage.
##
## Any node that can be damaged should extend this class (or implement
## these methods). Callers can use `obj is Damageable` instead of
## `obj.has_method("take_damage")`.
##
## The base implementation provides stub methods that do nothing; override
## in your subclass to handle actual damage.
## -----------------------------------------------------------------------


## Apply flat damage to the entity.  `damage_type` is one of "kinetic",
## "beam", "explosive", "missile", "melee".
func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	pass


## Apply damage at a specific world-space position (for directional /
## part-targeting systems).
func take_damage_at_point(amount: float, world_pos: Vector3, damage_type: String = "kinetic") -> void:
	pass


## Apply damage to a specific named part (e.g. "head", "arm_left").
func take_damage_to_part(slot_name: String, amount: float, damage_type: String = "kinetic") -> void:
	pass


## Apply damage to a specific part at a world-space position.
func take_damage_to_part_at(slot_name: String, amount: float, world_pos: Vector3, damage_type: String = "kinetic") -> void:
	pass


## Heal the entity.
func take_heal(amount: float) -> void:
	pass


## Apply an impact force (e.g. from explosions, heavy hits).
func apply_impact(force: Vector3, source_pos: Vector3 = Vector3.ZERO) -> void:
	pass


## Returns true if the entity is still alive / functional.
func is_alive() -> bool:
	return true


## Returns current health as a 0.0–1.0 ratio.
func get_health_percent() -> float:
	return 1.0
