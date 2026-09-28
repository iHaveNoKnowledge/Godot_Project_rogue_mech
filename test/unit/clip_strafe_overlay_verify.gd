extends Node
## CLIP STRAFE OVERLAY VERIFY — sideways strafing must add lateral
## stepping onto the forward run clip (which only knows forward).
## Covers the pure overlay math (no mech needed):
##  1. Zero sideways motion -> zero overlay (forward run untouched).
##  2. Full strafe -> rolls and lifts on both legs, outward leg bigger.
##  3. Phase advance swaps the lifting leg (alternating sidesteps).

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("STRAFE_OVERLAY OK: " + name)
	else:
		_fails += 1
		printerr("STRAFE_OVERLAY FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame

	var idle := MechaWalkingSystem.calc_strafe_overlay(0.0, 1.2)
	_check(float(idle["roll_l"]) == 0.0 and float(idle["roll_r"]) == 0.0
		and float(idle["lift_l"]) == 0.0 and float(idle["lift_r"]) == 0.0,
		"no sideways motion means no overlay")

	var r := MechaWalkingSystem.calc_strafe_overlay(1.0, PI * 0.5)
	_check(float(r["roll_l"]) != 0.0 and float(r["roll_r"]) != 0.0,
		"full right strafe rolls both legs (l=%.3f r=%.3f)" % [float(r["roll_l"]), float(r["roll_r"])])
	_check(float(r["lift_l"]) >= 0.0 and float(r["lift_r"]) >= 0.0,
		"lifts never push feet underground")
	_check(float(r["lift_l"]) + float(r["lift_r"]) > 0.05,
		"strafe visibly lifts a foot (total=%.3f)" % (float(r["lift_l"]) + float(r["lift_r"])))

	var p0 := MechaWalkingSystem.calc_strafe_overlay(1.0, PI * 0.5)
	var p1 := MechaWalkingSystem.calc_strafe_overlay(1.0, PI * 1.5)
	_check((float(p0["lift_l"]) - float(p0["lift_r"])) * (float(p1["lift_l"]) - float(p1["lift_r"])) < 0.0,
		"half-cycle phase advance swaps the lifting leg")

	var l := MechaWalkingSystem.calc_strafe_overlay(-1.0, PI * 0.5)
	_check(float(l["roll_l"]) < 0.0 and float(l["roll_r"]) < 0.0,
		"left strafe mirrors right strafe")

	print("STRAFE_OVERLAY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("STRAFE_OVERLAY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_STRAFE_OVERLAY_TESTS_PASSED")
		get_tree().quit(0)
