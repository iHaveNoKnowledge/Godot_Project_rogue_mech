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


## Authoritatively applies a disruption effect (electronic / movement inhibition) to a target node.
## Handles status lifecycle, metadata, node methods, and recovery timers.
static func apply_disruption(target: Node, duration: float, disruption_data: Dictionary = {}) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	var expire_ms := Time.get_ticks_msec() + int(duration * 1000.0)
	target.set_meta("disrupted_until", expire_ms)
	target.set_meta("disruption_data", disruption_data)

	if target.has_method("apply_disruption"):
		target.apply_disruption(duration, disruption_data)
		return true
	elif target.has_method("apply_stunt"):
		target.apply_stunt(duration)
		return true
	elif target.has_method("set_stunned"):
		target.set_stunned(true)
		var tree := target.get_tree()
		if tree:
			var t := tree.create_timer(duration)
			t.timeout.connect(func():
				if is_instance_valid(target) and target.has_method("set_stunned"):
					if Time.get_ticks_msec() >= int(target.get_meta("disrupted_until", 0)):
						target.set_stunned(false)
			)
		return true

	return true


## Authoritatively applies a generic effect request payload to all targets referenced in the request.
## Returns the count of successfully affected targets.
static func apply_effect_request(effect_request: Dictionary) -> int:
	if effect_request.is_empty():
		return 0

	var affected_count := 0
	var cap_type: String = str(effect_request.get("capability_type", "")).to_lower()
	var duration: float = float(effect_request.get("duration", 0.0))
	var effect_data: Dictionary = effect_request.get("effect_payload", {}) if effect_request.get("effect_payload") is Dictionary else {}

	var targets: Array = []
	if effect_request.has("targets") and effect_request["targets"] is Array:
		targets = effect_request["targets"]
	elif effect_request.has("target_nodes") and effect_request["target_nodes"] is Array:
		targets = effect_request["target_nodes"]

	for target in targets:
		if target is Node and is_instance_valid(target):
			var applied := false
			match cap_type:
				"disruption":
					applied = apply_disruption(target, duration, effect_data)
				_:
					applied = apply_disruption(target, duration, effect_data)
			if applied:
				affected_count += 1

	return affected_count

