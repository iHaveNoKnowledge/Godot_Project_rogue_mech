class_name TriggerState
extends RefCounted

## Per-hand trigger gate: makes "one pull = ? shots" data on the gun instead
## of the old function-tied rule (every gun sprayed while held).
##
##   AUTO — hold sprays at the gun's fire_rate (default, unchanged behavior).
##   SEMI — one shot attempt per press; holding does nothing until re-pressed.
##   BURST — one press fires up to burst_total shots at fire_rate, then stops
##            until re-pressed (only shots that consume ammo count down).
##
## The manager calls press() on the commit-press, allow_hold_shot() every held
## frame, on_hold_shot_fired() when a held-frame shot consumed ammo, and
## release() when the button goes up. Melee/fists stay AUTO (mode 0 default).

const AUTO := 0
const SEMI := 1
const BURST := 2

var mode: int = AUTO
var burst_total: int = 3
var burst_left: int = 0
var _last_path: String = ""


func sync(weapon: WeaponPart) -> void:
	if weapon == null:
		mode = AUTO
		burst_total = 3
		return
	mode = clampi(int(weapon.trigger_mode), AUTO, BURST)
	burst_total = maxi(int(weapon.burst_count), 1)
	# Melee and shields ignore trigger discipline — swings stay hold-to-swing.
	if weapon.weapon_type == WeaponPart.WeaponType.MELEE \
			or weapon.weapon_type == WeaponPart.WeaponType.SHIELD:
		mode = AUTO
	if mode != BURST:
		burst_left = 0
	# A fresh gun starts a fresh burst — leftovers never carry across a swap.
	var wpath := str(weapon.resource_path)
	if wpath != _last_path:
		burst_left = 0
		_last_path = wpath


func press() -> void:
	if mode == BURST:
		burst_left = burst_total


func release() -> void:
	burst_left = 0


func allow_hold_shot() -> bool:
	match mode:
		SEMI:
			return false
		BURST:
			return burst_left > 0
	return true


func on_hold_shot_fired() -> void:
	if mode == BURST:
		burst_left = maxi(burst_left - 1, 0)
