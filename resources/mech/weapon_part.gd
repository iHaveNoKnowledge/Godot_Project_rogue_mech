extends Resource
class_name WeaponPart

enum WeaponType { BEAM_RIFLE, MACHINE_GUN, MISSILE, SHOTGUN, MELEE, SHIELD, RAILGUN, MINIGUN }

@export var weapon_name: String = ""
@export var weapon_type: WeaponType = WeaponType.BEAM_RIFLE
@export var damage: float = 25.0
@export var fire_rate: float = 0.2
@export var max_ammo: int = 100
@export var ammo_per_shot: int = 1
@export var projectile_speed: float = 50.0
@export var spread: float = 0.0
@export var weight: float = 5.0
@export var range_distance: float = 50.0
@export var mesh_scene: PackedScene
@export var icon: Texture2D
@export var description: String = ""
@export var rarity: int = 0

@export var ammo_type: String = "" # "kinetic", "energy", "explosive", "missile", "none" (if empty, auto-inferred)

# ----
# GRIP / TWO-HAND REQUIREMENT
# ----
# `two_handed` marks big weapons (railgun / minigun). When two_handed is true the
# weapon NEEDS both hands UNLESS the mech's Power stat meets `power_required`.
# With enough Power it can be gripped one-handed like a normal weapon.
@export var two_handed: bool = false
@export var power_required: float = 0.0

# ----
# HEAT SYSTEM
# Every weapon gets a heat metre. `heat_capacity` > 0 enables the system; each
# shot adds `heat_per_shot`, and `heat_cool_rate` points/second are shed while
# idle. At full heat the weapon is locked until it cools below
# `overheat_release_ratio * heat_capacity`.
@export var heat_capacity: float = 0.0
@export var heat_per_shot: float = 0.0
@export var heat_cool_rate: float = 10.0
@export var heat_release_ratio: float = 0.5

# ----
# RECOIL on the shooter: how hard the mech gets pushed back per shot.
@export var recoil_force: float = 0.0
@export var recoil_shake: float = 0.0

# ----
# IMPACT / STAGGER on the target
# Heavy hits punch the enemy back and interrupt its attack for a moment.
@export var impact: float = 0.0

# Sound override (null = use type default)
@export var fire_sfx: AudioStream

# Shield-specific
@export var shield_hp: float = 300.0
@export var shield_recharge_rate: float = 20.0


func get_fire_interval() -> float:
	return fire_rate


func uses_heat() -> bool:
	return heat_capacity > 0.0


func can_fire(current_ammo: int) -> bool:
	return current_ammo >= ammo_per_shot


# True when the weapon must be grabbed with both hands because the equipped mech
# does NOT have the Power required to one-hand it.
func requires_two_hand(power: float) -> bool:
	return two_handed and (power < power_required)


func get_ammo_type() -> String:
	if not ammo_type.is_empty():
		return ammo_type.to_lower()
	match weapon_type:
		WeaponType.BEAM_RIFLE:
			return "energy"
		WeaponType.MACHINE_GUN, WeaponType.SHOTGUN:
			return "kinetic"
		WeaponType.MISSILE:
			return "missile"
		WeaponType.MELEE, WeaponType.SHIELD:
			return "none"
		_:
			return "kinetic"
