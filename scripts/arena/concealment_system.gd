extends Node

## Concealment system: enemies standing inside a cover footprint (trees,
## buildings — the tall cover objects that hide a mech) are hidden from the
## player. Once they leave the cover zone they become visible again.
##
## This replaces the old "show nothing until in range" fog approach: enemies are
## visible by default, and only vanish while actually inside a concealment zone.
## Groups:
##   concealment  -> tall cover bodies (trees, buildings, tree-trunk covers)
##   enemy        -> enemy mechs to conceal

# How far beyond a cover's collision shape an enemy is still treated as "in
# cover" (so an enemy standing right beside a tree/building counts as hidden).
const COVER_MARGIN: float = 2.5

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
	if concealment_bodies.is_empty():
		return
	var aabbs: Array = []
	for body in concealment_bodies:
		if not is_instance_valid(body):
			continue
		var aabb := _cover_world_aabb(body)
		if aabb.size != Vector3.ZERO:
			aabbs.append(aabb.grow(COVER_MARGIN))

	if aabbs.is_empty():
		return

	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		var hs = enemy.get("health_system")
		if hs == null:
			continue
		if hs.get("is_destroyed"):
			continue
		var concealed := _is_in_cover(enemy.global_position, aabbs)
		if enemy.has_method("set_concealed"):
			enemy.set_concealed(concealed)


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
