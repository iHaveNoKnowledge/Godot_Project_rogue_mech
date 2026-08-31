extends Node3D
class_name WarReactorBay

## Ancient Reactor bay at Main Base — produces Energy for Legendary mechs (per PLAN.md)

var _level: int = 1
var _energy_stored: float = 0.0
var _max_energy: float = 1000.0


func upgrade() -> bool:
	if _level >= 3:
		return false
	var cost = 600 if _level == 1 else 1200
	if GlobalData.currency.credits < cost:
		return false
	GlobalData.currency.try_spend_credits(cost)
	_level += 1
	_max_energy = 1000.0 * _level
	return true


func _process(delta: float) -> void:
	_energy_stored = minf(_energy_stored + 5.0 * delta * _level, _max_energy)


func get_energy() -> float:
	return _energy_stored


func consume(amount: float) -> bool:
	if _energy_stored < amount:
		return false
	_energy_stored -= amount
	return true
