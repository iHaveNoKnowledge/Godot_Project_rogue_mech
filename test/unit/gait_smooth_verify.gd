extends Node
## GAIT SMOOTH VERIFY — robotic piston gait must ease in/out of swings.
## Regression for: sprint legs hammering between extremes at full speed
## (linear phase = instant reversals = sewing-machine read).
## Covers:
##  1. Swing endpoints have ~zero velocity (smoothstep, not linear snap).
##  2. Full sprint amplitude preserved (easing must not shrink the stride).

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("GAIT_SMOOTH OK: " + name)
	else:
		_fails += 1
		printerr("GAIT_SMOOTH FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame

	var n := 64
	var vals: Array = []
	for i in range(n + 1):
		vals.append(float(MechaWalkingSystem.calc_robot_sprint_leg(TAU * float(i) / float(n))["thigh"]))

	var lo: float = vals.min()
	var hi: float = vals.max()
	_check(absf(rad_to_deg(hi - lo) - 93.0) < 3.0,
		"sprint swing keeps full -55..+38deg amplitude (span=%.1fdeg)" % rad_to_deg(hi - lo))

	# Reversal smoothness: velocity into/out of the swing extremes (phase
	# wrap 2PI->0 and swing start) must be far below mid-swing velocity.
	# Linear phase slams through reversals at full slope; smoothstep eases.
	var w0: float = absf(vals[1] - vals[0])
	var w1: float = absf(vals[0] - vals[n - 1])
	var mid: float = absf(vals[17] - vals[15])
	_check(w0 + w1 < mid,
		"swing eases at reversals instead of slamming (ends=%.4f mid=%.4f)" % [w0 + w1, mid])

	print("GAIT_SMOOTH_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("GAIT_SMOOTH_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_GAIT_SMOOTH_TESTS_PASSED")
		get_tree().quit(0)
