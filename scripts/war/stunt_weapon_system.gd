extends RefCounted
class_name StuntWeaponSystem

## Stunt Weapon — stun 2-4s, reactor-specific (per PLAN.md 7.6)
## Combustion = 4s, Hybrid = 2.5s, Ancient = 0-0.5s

const STUNT_DURATIONS: Dictionary = {
	"combustion": 4.0,
	"hybrid": 2.5,
	"ancient": 0.3,
	"legendary": 0.0,
}


static func get_stunt_duration(reactor_type: String) -> float:
	reactor_type = reactor_type.to_lower()
	if reactor_type.contains("ancient") or reactor_type.contains("legendary"):
		return 0.3
	if reactor_type.contains("hybrid") or reactor_type.contains("overclock"):
		return 2.5
	return 4.0


static func try_stun(target: Node, reactor_type: String) -> bool:
	var dur = get_stunt_duration(reactor_type)
	if dur <= 0.05:
		return false # Ancient immune
	if target.has_method("apply_stunt"):
		target.apply_stunt(dur)
		return true
	# Fallback: set meta and disable movement via ewar
	target.set_meta("stunned_until", Time.get_ticks_msec() + int(dur * 1000))
	if target.has_method("set_stunned"):
		target.set_stunned(true)
		var t = target.get_tree().create_timer(dur)
		t.timeout.connect(func():
			if is_instance_valid(target) and target.has_method("set_stunned"):
				target.set_stunned(false)
		)
	return true
