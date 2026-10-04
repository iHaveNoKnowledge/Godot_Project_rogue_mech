extends Node3D

var was_hit: bool = false
var damage_taken: float = 0.0

func take_damage_at_point(dmg: float, _point: Vector3, _type: String) -> void:
	was_hit = true
	damage_taken = dmg

func take_damage(dmg: float, _type: String = "blunt") -> void:
	was_hit = true
	damage_taken = dmg
