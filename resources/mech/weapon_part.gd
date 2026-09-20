extends Resource
class_name WeaponPart

enum WeaponType { BEAM_RIFLE, MACHINE_GUN, MISSILE, SHOTGUN, MELEE, SHIELD, RAILGUN, MINIGUN }
enum TriggerMode { AUTO, SEMI, BURST }
enum HoldStance { AUTO, RANGED_RIFLE, MELEE_UPRIGHT, PILE_BUNKER_GRIP, FOREARM_MOUNTED, SHIELD_SIDE }

## The three attack types. Every weapon deals one of these, every armor plate
## defends against one of them, and every shield's plating resists one of them
## best. Rock-paper-scissors layer on top of raw damage: matching type = the
## defense works, mismatched = it doesn't.
enum DamageType { HEAT, PIERCE, BLUNT }

@export var weapon_name: String = ""
@export var weapon_type: WeaponType = WeaponType.BEAM_RIFLE
@export var hold_stance: HoldStance = HoldStance.AUTO
@export var damage: float = 25.0
@export var fire_rate: float = 0.2
@export var max_ammo: int = 100
@export var ammo_per_shot: int = 1
## Trigger discipline (TriggerMode AUTO/SEMI/BURST): AUTO sprays while held,
## SEMI fires one attempt per press, BURST fires up to burst_count shots per
## press. Gated per hand by TriggerState; melee/shields always behave as AUTO.
@export var trigger_mode: int = 0
## Shots per trigger pull when trigger_mode is BURST.
@export var burst_count: int = 3
## Projectiles spawned per trigger pull (volley weapons). Must be >= 1, and
## when ammo_per_shot > 1 it should match it — otherwise the player pays for
## rounds that never leave the barrel (the old Swarm bug: 3 rockets in, 1 out).
@export var projectiles_per_shot: int = 1
@export var projectile_speed: float = 50.0
@export var spread: float = 0.0
@export var weight: float = 5.0
@export var range_distance: float = 50.0
@export var mesh_scene: PackedScene
@export var icon: Texture2D
@export var description: String = ""
@export var rarity: int = 0
@export var source_path: String = ""
@export var tech_id: String = "" # TechnologySystem ID (""; empty = technology-neutral legacy weapon)
@export var special_capability: Dictionary = {} # Advanced / Special weapon capability definition (Phase 2E-5)

@export var ammo_type: String = "" # AmmoSystem id ("bullet", "shell", "spike", "energy_cell", "rocket", "missile", "explosive", "heavy_round", "none"; empty = auto-inferred)
@export var reload_time: float = 2.0 # seconds to refill the magazine from reserve
## Onboard round fabricator (rounds/second forged straight into the magazine,
## 0 = off). For the railgun's spike printer: slow trickle so heat — not the
## magazine — is the real limiter when reserves run dry.
@export var ammo_regen_per_sec: float = 0.0

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
@export var sfx_reload: String = "" # reload sound name override (empty = default)

# Damage type this weapon deals: "heat" / "pierce" / "blunt". Empty means
# get_damage_type() derives it from the weapon category (beam/missile = heat,
# bullet/rail = pierce, shotgun/melee = blunt). Set explicitly on weapons that
# differ from their category (beam sniper = pierce, knife = pierce, heat blade
# = heat, pile bunker = pierce).
@export var damage_type: String = ""

# Shield-specific
@export var shield_hp: float = 300.0
# Which attack type this shield's plating resists best ("heat"/"pierce"/"blunt").
# While raised, the shield fully blocks attacks but drains its HP at 40% rate
# against its OWN type and 100% against the other two — an anti-pierce plate
# soaks pierce hits for ages but melts against heat or blunt.
@export var shield_type: String = ""


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


func get_damage_type() -> String:
	if not damage_type.is_empty():
		return damage_type.to_lower()
	match weapon_type:
		WeaponType.BEAM_RIFLE, WeaponType.MISSILE:
			return "heat"
		WeaponType.MACHINE_GUN, WeaponType.RAILGUN, WeaponType.MINIGUN:
			return "pierce"
		_:
			return "blunt"


# The anti-type of this shield ("heat"/"pierce"/"blunt"). Falls back to blunt
# so a shield with no plating still counts as a plain physical plate.
func get_shield_type() -> String:
	return shield_type.to_lower() if not shield_type.is_empty() else "blunt"


## True when firing this weapon flings a spent brass casing. Only kinetic
## firearms eject shells — energy guns (beam), missiles, melee and shields
## never do (the pile bunker's loaded blast keeps its own exception in code).
func ejects_shell_casing() -> bool:
	match weapon_type:
		WeaponType.MACHINE_GUN, WeaponType.SHOTGUN, WeaponType.RAILGUN, WeaponType.MINIGUN:
			return true
	return false


func get_ammo_type() -> String:
	if not ammo_type.is_empty():
		return ammo_type.to_lower()
	match weapon_type:
		WeaponType.BEAM_RIFLE:
			return "energy_cell"
		WeaponType.MACHINE_GUN:
			return "bullet"
		WeaponType.SHOTGUN:
			return "shell"
		WeaponType.MISSILE:
			return "missile"
		WeaponType.RAILGUN:
			return "spike"
		WeaponType.MINIGUN:
			return "heavy_round"
		WeaponType.MELEE, WeaponType.SHIELD:
			return "none"
		_:
			return "bullet"


# =============================================================================
# ADVANCED / SPECIAL CAPABILITY CONTRACT (Phase 2E-5)
# =============================================================================

func has_special_capability() -> bool:
	return not special_capability.is_empty()


func get_special_capability() -> Dictionary:
	return special_capability.duplicate(true)


func get_special_capability_type() -> String:
	return str(special_capability.get("capability_type", ""))


func get_targeting_mode() -> String:
	return str(special_capability.get("targeting_mode", "point"))


func get_area_parameters() -> Dictionary:
	var area = special_capability.get("area_parameters", {})
	return area.duplicate(true) if area is Dictionary else {}


func get_duration() -> float:
	return float(special_capability.get("duration", 0.0))
