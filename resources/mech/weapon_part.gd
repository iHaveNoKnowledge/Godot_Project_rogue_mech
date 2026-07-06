extends Resource
class_name WeaponPart

enum WeaponType { BEAM_RIFLE, MACHINE_GUN, MISSILE, SHOTGUN, MELEE }

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


func get_fire_interval() -> float:
	return fire_rate


func can_fire(current_ammo: int) -> bool:
	return current_ammo >= ammo_per_shot
