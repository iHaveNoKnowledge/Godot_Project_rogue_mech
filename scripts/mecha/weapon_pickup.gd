extends Area3D

## Recoverable weapon pickup.
## Tracks nearby players (both Mechas and Pilots on foot).
## Supports Field Loot UI interactions:
##   - Direct Hand Equip / Swap
##   - Field Pack Carrier storage (with live weight limit check)
##   - Ammo unloading to player reserves
##   - Convoy Salvage Tagging (with distinctive sandwich triangle badge 🔺)

@export var weapon_resource: WeaponPart
@export var bob_speed: float = 2.0
@export var bob_amount: float = 0.3
@export var rotate_speed: float = 1.5

var mesh: MeshInstance3D = null
var original_y: float = 0.0
var timer: float = 0.0

var nearby_entity: Node3D = null
var nearby_mecha: Node3D = null

var is_tagged_for_convoy: bool = false
var current_ammo: int = -1
var _tag_badge: Node3D = null


func _ready() -> void:
	add_to_group("weapon_pickup")
	add_to_group("loot_pickup")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if weapon_resource and current_ammo < 0:
		current_ammo = weapon_resource.max_ammo
	_create_visual()


func _exit_tree() -> void:
	nearby_entity = null
	nearby_mecha = null


func is_near_player() -> bool:
	return nearby_entity != null and is_instance_valid(nearby_entity)


func is_near_mecha() -> bool:
	return nearby_mecha != null and is_instance_valid(nearby_mecha)


func get_weapon_manager() -> Node:
	if nearby_entity == null or not is_instance_valid(nearby_entity):
		return null
	return nearby_entity.get_node_or_null("WeaponManager")


## Tags this weapon to be automatically salvaged into the Convoy Depot after winning combat
func tag_for_convoy(tagged: bool) -> void:
	is_tagged_for_convoy = tagged
	set_meta("tagged_for_convoy", tagged)
	_update_tag_visual()


func _update_tag_visual() -> void:
	if _tag_badge and is_instance_valid(_tag_badge):
		_tag_badge.queue_free()
		_tag_badge = null

	if not is_tagged_for_convoy:
		return

	# Create a floating sandwich triangle 3D badge above the weapon
	_tag_badge = Node3D.new()
	_tag_badge.name = "ConvoyTagBadge"
	_tag_badge.position = Vector3(0.0, 0.8, 0.0)

	var label := Label3D.new()
	label.name = "BadgeLabel"
	label.text = "▲ [CONVOY SALVAGE] ▲"
	label.font_size = 32
	label.outline_size = 6
	label.outline_modulate = Color.BLACK
	label.modulate = Color(1.0, 0.75, 0.15) # Amber Gold
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	_tag_badge.add_child(label)

	add_child(_tag_badge)


## Unloads remaining ammunition from this dropped weapon into the player's ammo reserve
func unload_ammo_to_player(player_body: Node3D = null) -> int:
	if weapon_resource == null:
		return 0
	if current_ammo <= 0:
		return 0

	var target := player_body if player_body != null else nearby_entity
	var ammo_type := weapon_resource.get_ammo_type()
	var amount := current_ammo

	if target != null and is_instance_valid(target):
		if target.is_in_group("mecha"):
			var wm = target.get_node_or_null("WeaponManager")
			if wm:
				wm.add_ammo(amount, "", ammo_type)
		elif target.is_in_group("pilot"):
			PilotSystem.add_ammo(ammo_type, amount)
	else:
		# Fallback to GlobalData
		LoadoutSystem.add_reserve_ammo(ammo_type, amount)

	current_ammo = 0
	return amount


## True when the mecha already carries another copy of this model
func is_already_carried() -> bool:
	if weapon_resource == null:
		return false
	var wm = get_weapon_manager()
	if wm and wm.has_method("is_weapon_model_carried"):
		return wm.is_weapon_model_carried(weapon_resource.resource_path)
	return false


## Adds the weapon to the player's Field Pack / Carrier
func take_weapon(player_body: Node3D = null) -> bool:
	if weapon_resource == null:
		return false
	var target := player_body if player_body != null else nearby_entity
	if target == null:
		return false

	var wm = target.get_node_or_null("WeaponManager")
	if wm and wm.has_method("add_weapon"):
		wm.add_weapon(weapon_resource)
	else:
		LoadoutSystem.register_weapon(weapon_resource.resource_path, weapon_resource.weapon_name)

	queue_free()
	return true


func take_ammo_only(player_body: Node3D = null) -> void:
	unload_ammo_to_player(player_body)
	if weapon_resource:
		var scrap_val := maxi(2, int(round(float(weapon_resource.weight))) + int(weapon_resource.rarity) * 5)
		GlobalData.currency.gain_scrap(scrap_val)
	queue_free()


func can_take_to_field_pack(player_body: Node3D = null) -> bool:
	if weapon_resource == null:
		return false
	var target := player_body if player_body != null else nearby_entity
	var current_weight := LoadoutSystem.get_field_pack_weight()
	if target != null and is_instance_valid(target):
		var wm = target.get_node_or_null("WeaponManager")
		if wm and wm.has_method("get_battle_field_pack_weight"):
			current_weight = wm.get_battle_field_pack_weight()
	return current_weight + float(weapon_resource.weight) <= LoadoutSystem.get_field_pack_capacity()


func _create_visual() -> void:
	mesh = MeshInstance3D.new()

	if weapon_resource:
		for child in get_children():
			if child is MeshInstance3D and child.name != "ConvoyTagBadge":
				child.visible = false
		var visual := Node3D.new()
		visual.name = "WeaponMeshContainer"
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
	var vis = get_node_or_null("WeaponMeshContainer")
	if vis and is_instance_valid(vis):
		vis.position.y = sin(timer * bob_speed) * bob_amount
	elif mesh and mesh.is_inside_tree():
		mesh.position.y = sin(timer * bob_speed) * bob_amount


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("mecha") or body.is_in_group("pilot"):
		nearby_entity = body
		if body.is_in_group("mecha"):
			nearby_mecha = body


func _on_body_exited(body: Node3D) -> void:
	if body == nearby_entity:
		nearby_entity = null
	if body == nearby_mecha:
		nearby_mecha = null
