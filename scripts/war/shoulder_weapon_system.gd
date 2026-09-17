extends RefCounted
class_name ShoulderWeaponSystem

## Shoulder Left Q / Right E — per PLAN.md 6

const SHOULDER_SLOTS: Array[String] = ["shoulder_left", "shoulder_right"]

static func equip_shoulder(side: String, weapon_path: String) -> bool:
	var slot = "shoulder_left" if side == "left" else "shoulder_right"
	if not ResourceLoader.exists(weapon_path):
		return false
	GlobalData.weapons.equipped_parts[slot] = {"path": weapon_path, "uid": "shoulder_%s_%d" % [side, randi()]}
	GlobalData.save_run()
	return true


## DEPRECATED for combat firing: real shoulder shots go through
## WeaponManager._try_fire_shoulder() -> WeaponCore (same cooldown/ammo/heat
## rules as hands). This stub only plays the equip SFX and spawns nothing —
## do NOT use it to fire or you get "fires once / heat never cools" bugs.
static func fire_shoulder(side: String, from_pos: Vector3, dir: Vector3) -> void:
	push_warning("ShoulderWeaponSystem.fire_shoulder is deprecated; WeaponManager owns shoulder firing via WeaponCore.")
	var slot = "shoulder_left" if side == "left" else "shoulder_right"
	var data = GlobalData.weapons.equipped_parts.get(slot, {})
	if data is Dictionary and not data.is_empty():
		var path = str(data.get("path", ""))
		if ResourceLoader.exists(path):
			var weapon = load(path)
			if weapon and AudioManager:
				AudioManager.play_weapon_sfx(weapon.weapon_type if "weapon_type" in weapon else 0, from_pos)
