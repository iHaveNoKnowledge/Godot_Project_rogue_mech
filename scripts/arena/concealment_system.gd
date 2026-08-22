extends Node

## Concealment system: enemies standing inside a cover footprint (trees,
## buildings — the tall cover objects that hide a mech) are hidden from the
## player. Once they leave the cover zone they become visible again.
##
## Enemies are also hidden when a terrain crest (hill, dune, bank) blocks the
## line of sight from the camera to their feet — an enemy on the far side of a
## hill is concealed until the player crests it. Cover bodies are excluded from
## the crest ray so trees/buildings keep working through the footprint check
## (an enemy behind a tree trunk is NOT hidden unless it stands in the
## footprint, matching the low-barrier rule).
##
## This replaces the old "show nothing until in range" fog approach: enemies are
## visible by default, and only vanish while actually inside a concealment zone
## or behind a terrain crest.
## Groups:
##   concealment  -> tall cover bodies (trees, buildings, tree-trunk covers)
##   enemy        -> enemy mechs to conceal

# Footprint margin for cover bounds (0.0 so standing beside cover does not count as inside).
const COVER_MARGIN: float = 0.0

# Terrain physics layer: ground, hills, dunes, banks, rocks, bridges.
const TERRAIN_LAYER := 2

# The crest ray must be blocked this far short of the enemy's feet to count as
# concealment — grazing the ground right at the feet doesn't hide the mech.
const CREST_MARGIN: float = 0.5

const CHECK_INTERVAL: float = 0.12
var check_timer: float = 0.0
var concealment_bodies: Array = []


func _ready() -> void:
	# Cover spawns a frame after the arena generates; refresh the body list then
	# and keep it in sync if cover is destroyed mid-fight.
	await get_tree().process_frame
	await get_tree().process_frame
	_refresh_concealment_bodies()
	EventBus.cover_destroyed.connect(_on_cover_destroyed)


func _refresh_concealment_bodies() -> void:
	concealment_bodies = []
	for body in get_tree().get_nodes_in_group("concealment"):
		if is_instance_valid(body) and body is Node3D:
			concealment_bodies.append(body)


func _on_cover_destroyed(_pos: Vector3, _type: String) -> void:
	_refresh_concealment_bodies()


func _process(delta: float) -> void:
	check_timer -= delta
	if check_timer > 0.0:
		return
	check_timer = CHECK_INTERVAL
	_update_all()


func _update_all() -> void:
	var aabbs: Array = []
	for body in concealment_bodies:
		if not is_instance_valid(body):
			continue
		var aabb := _cover_world_aabb(body)
		if aabb.size != Vector3.ZERO:
			aabbs.append(aabb.grow(COVER_MARGIN))

	# Crest check needs a live camera + the physics space. No camera (e.g.
	# headless tests) or no space means footprint-only concealment.
	var camera_pos := _camera_position()
	var space: PhysicsDirectSpaceState3D = null
	var cover_rids: Array[RID] = []
	if camera_pos != Vector3.INF:
		space = get_viewport().get_world_3d().direct_space_state
		cover_rids = _cover_rids()

	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		var hs = enemy.get("health_system")
		if hs == null:
			continue
		if hs.get("is_destroyed"):
			continue
		var concealed := _is_in_cover(enemy.global_position, aabbs)
		if not concealed and space != null:
			concealed = _is_crest_hidden(enemy.global_position, camera_pos, space, cover_rids)
		if enemy.has_method("set_concealed"):
			enemy.set_concealed(concealed)


# The active 3D camera's world position, or Vector3.INF when no camera exists
# (headless tests / board screens) so the crest check is skipped.
func _camera_position() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.INF
	return cam.global_position


# RIDs of every cover/concealment body, so the crest ray only collides with the
# terrain (hills/dunes/banks) and never with trees, buildings or low barriers —
# those keep their footprint-based concealment rules.
func _cover_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for group in ["cover", "concealment"]:
		for body in get_tree().get_nodes_in_group(group):
			if is_instance_valid(body) and body is CollisionObject3D:
				rids.append((body as CollisionObject3D).get_rid())
	return rids


# True when a terrain crest between the camera and the enemy's feet blocks the
# line of sight. Finds the ground surface under the enemy with a straight-down
# probe, then casts from the camera to that point: any terrain hit well short
# of the feet means the enemy is behind a hill.
func _is_crest_hidden(enemy_pos: Vector3, camera_pos: Vector3, space: PhysicsDirectSpaceState3D, cover_rids: Array[RID]) -> bool:
	# Where do the enemy's feet actually rest? Probe down onto the terrain.
	var down := PhysicsRayQueryParameters3D.create(
		enemy_pos + Vector3(0, 40.0, 0), enemy_pos + Vector3(0, -40.0, 0), TERRAIN_LAYER)
	down.exclude = cover_rids
	var ground := space.intersect_ray(down)
	if ground.is_empty():
		return false
	var feet: Vector3 = (ground["position"] as Vector3) + Vector3(0, 0.25, 0)

	var to_feet := feet - camera_pos
	var total_dist := to_feet.length()
	if total_dist < 1.0:
		return false

	var los := PhysicsRayQueryParameters3D.create(camera_pos, feet, TERRAIN_LAYER)
	los.exclude = cover_rids
	var hit := space.intersect_ray(los)
	if hit.is_empty():
		return false
	var hit_dist: float = camera_pos.distance_to(hit["position"] as Vector3)
	return hit_dist < total_dist - CREST_MARGIN


func _is_in_cover(pos: Vector3, aabbs: Array) -> bool:
	for aabb in aabbs:
		if aabb.has_point(pos):
			return true
	return false


# World-space AABB of a concealment body's collision shape (box or cylinder),
# so rotated covers are still detected via their true footprint.
func _cover_world_aabb(cover: Node3D) -> AABB:
	for child in cover.get_children():
		if child is CollisionShape3D and child.shape != null:
			var s: Shape3D = child.shape
			var half: Vector3
			if s is BoxShape3D:
				half = (s as BoxShape3D).size * 0.5
			elif s is CylinderShape3D:
				var cyl := s as CylinderShape3D
				half = Vector3(cyl.radius, cyl.height * 0.5, cyl.radius)
			else:
				continue
			var t: Transform3D = (child as CollisionShape3D).global_transform
			var half_world: Vector3 = (t.basis * half).abs()
			return AABB(t.origin - half_world, half_world * 2.0)
	return AABB()
