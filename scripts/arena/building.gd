extends StaticBody3D

var base_ref: Node = null

func take_damage(amount: float, _type: String = "kinetic") -> void:
	if base_ref and is_instance_valid(base_ref) and base_ref.has_method("take_damage"):
		base_ref.take_damage(self, amount)
	else:
		# Fallback: direct hp meta
		var hp: float = float(get_meta("hp", 50.0)) - amount
		set_meta("hp", hp)
		if hp <= 0:
			queue_free()

func take_damage_at_point(amount: float, _pos: Vector3, type: String = "kinetic") -> void:
	take_damage(amount, type)
