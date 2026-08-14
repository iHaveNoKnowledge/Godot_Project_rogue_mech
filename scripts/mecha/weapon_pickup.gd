extends Area3D

## Recoverable weapon pickup.
## Instead of auto-collecting on contact, this pickup tracks the mecha that walks
## into it and lets the HUD show a "[F] Pickup" prompt. When the player presses F
## (the "interact" action) the HUD opens a choice: TAKE WEAPON / TAKE AMMO ONLY.

@export var weapon_resource: WeaponPart
@export var bob_speed: float = 2.0
@export var bob_amount: float = 0.3
@export var rotate_speed: float = 1.5

var mesh: MeshInstance3D = null
var original_y: float = 0.0
var timer: float = 0.0

# The mecha currently standing inside this pickup (null when nobody is near).
var nearby_mecha: Node3D = null


func _ready() -> void:
	add_to_group("weapon_pickup")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_create_visual()


func _exit_tree() -> void:
	if nearby_mecha:
		nearby_mecha = null


func is_near_mecha() -> bool:
	return nearby_mecha != null


func get_weapon_manager() -> Node:
	if nearby_mecha == null:
		return null
	return nearby_mecha.get_node_or_null("WeaponManager")


# True when the mecha already carries (hand or back) another copy of this model.
func is_already_carried() -> bool:
	if weapon_resource == null:
		return false
	var wm = get_weapon_manager()
	if wm and wm.has_method("is_weapon_model_carried"):
		return wm.is_weapon_model_carried(weapon_resource.resource_path)
	return false


# Player chose to take the whole weapon into the FIELD PACK (also registers it in
# the stash). Checks Field Pack capacity and that the same model isn't already
# carried; returns false if either rule would be violated.
func take_weapon() -> bool:
	if weapon_resource == null:
		return false
	if not can_take_to_field_pack():
		return false
	if is_already_carried():
		return false
	var wm = get_weapon_manager()
	if wm:
		wm.add_weapon(weapon_resource)
	queue_free()
	return true


# Player chose to scrap the weapon and keep only its ammo (in the battle reserve).
# The scrap metal of the weapon itself becomes crafting material.
func take_ammo_only() -> void:
	var wm = get_weapon_manager()
	if wm and weapon_resource:
		wm.add_ammo(weapon_resource.max_ammo, "", weapon_resource.get_ammo_type())
	if weapon_resource:
		var scrap_value := maxi(2, int(round(float(weapon_resource.weight))) + int(weapon_resource.rarity) * 5)
		GlobalData.gain_scrap(scrap_value)
	queue_free()


# Player chose to send the weapon straight to the DEPOT (permanent stash): it is
# NOT carried into this battle, but is available for loadout later in the hangar.
# The weapon's ammo is sent to the depot ammo stash instead of the battle reserve.
func send_to_depot() -> void:
	if weapon_resource:
		GlobalData.register_weapon(weapon_resource.resource_path, weapon_resource.weapon_name)
		GlobalData.add_reserve_ammo(weapon_resource.get_ammo_type(), weapon_resource.max_ammo)
	queue_free()


func can_take_to_field_pack() -> bool:
	if weapon_resource == null:
		return false
	var current_weight := GlobalData.get_field_pack_weight()
	var wm = get_weapon_manager()
	if wm and wm.has_method("get_battle_field_pack_weight"):
		current_weight = wm.get_battle_field_pack_weight()
	return current_weight + float(weapon_resource.weight) <= GlobalData.get_field_pack_capacity()


func _create_visual() -> void:
	mesh = MeshInstance3D.new()

	# Show the actual weapon model when a weapon resource is set (matches hangar).
	if weapon_resource:
		# Hide any placeholder box mesh defined in the scene (stock pickups).
		for child in get_children():
			if child is MeshInstance3D:
				child.visible = false
		var visual := Node3D.new()
		visual.add_child(WeaponVisualFactory.build(weapon_resource))
		add_child(visual)
		original_y = position.y
		return

	var box = BoxMesh.new()
	box.size = Vector3(0.5, 0.3, 1.2)
	mesh.mesh = box

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.2, 1)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.5, 0.1)
	mat.emission_energy_multiplier = 1.5
	mesh.material_override = mat

	add_child(mesh)
	original_y = position.y


func _process(delta: float) -> void:
	timer += delta
	rotate_y(rotate_speed * delta)
	if mesh and mesh.is_inside_tree():
		mesh.position.y = sin(timer * bob_speed) * bob_amount


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("mecha"):
		nearby_mecha = body


func _on_body_exited(body: Node3D) -> void:
	if body == nearby_mecha:
		nearby_mecha = null
