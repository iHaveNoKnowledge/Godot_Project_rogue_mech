class_name EnemyState
extends Node

## Base class for all enemy AI states.
## Subclasses override enter(), exit(), and physics_process().

var enemy: CharacterBody3D
var state_machine: Node


func enter() -> void:
	pass


func exit() -> void:
	pass


func physics_process(_delta: float) -> void:
	pass


func on_damage(_amount: float) -> void:
	pass
