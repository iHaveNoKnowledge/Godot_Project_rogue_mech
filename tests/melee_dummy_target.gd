extends CharacterBody3D

## Minimal physics target for the melee verify test: a layer-1 (player) or
## layer-8 (enemy) body with a take_damage counter so swing collision checks
## can be asserted headlessly.

var damage_taken: float = 0.0
var health_system: Node = null


func _ready() -> void:
	health_system = FakeHealth.new()
	add_child(health_system)


func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	damage_taken += amount


class FakeHealth:
	extends Node

	var is_destroyed: bool = false
	var parts: Dictionary = {}

	func take_heal(_amount: float) -> void:
		pass
