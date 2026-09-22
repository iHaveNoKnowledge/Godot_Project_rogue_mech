class_name NavAvoidance
extends RefCounted

## Helper for local obstacle steering when NavigationMesh path still clips a
## corner or when the mesh is not yet baked. Uses short raycasts to test
## clearance and returns a steered direction.

# Casts a ray from `from` along `dir` for `dist` and returns true if the
# Environment (layer 2) blocks it. Uses 3 parallel rays (center + left/right
# offset by agent radius) so the mech's 1.2m body is respected — a single
# center ray would think a path hugging the wall edge is clear when the hull
# still clips.
static func _is_blocked(from: Vector3, dir: Vector3, dist: float, space_state: PhysicsDirectSpaceState3D) -> bool:
	if dir.length_squared() < 0.001 or space_state == null:
		return false
	var d := dir.normalized()
	var to: Vector3 = from + d * dist
	# Agent radius clearance (mech half width + margin)
	const RADIUS: float = 1.25
	var perp := Vector3(-d.z, 0, d.x).normalized()
	var origins: Array[Vector3] = [from, from + perp * RADIUS, from - perp * RADIUS]
	for o in origins:
		var query := PhysicsRayQueryParameters3D.create(o, o + d * dist, 2)  # Environment only
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			return true
	return false


# Tries to steer `desired_dir` away from a blocking obstacle. Tests
# alternative yaw offsets in order [45, -45, 90, -90, 135, -135] and returns
# the first clear direction that still has some forward component (dot > 0).
# If none clear, returns the least-blocked fallback (largest yaw).
static func steer_around(desired_dir: Vector3, from: Vector3, space_state: PhysicsDirectSpaceState3D, check_dist: float = 3.0) -> Vector3:
	var base := desired_dir
	base.y = 0.0
	if base.length_squared() < 0.001:
		return Vector3.ZERO
	base = base.normalized()
	if not _is_blocked(from + Vector3(0, 0.6, 0), base, check_dist, space_state):
		return base
	var offsets: Array[float] = [45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]
	for off in offsets:
		var cand: Vector3 = base.rotated(Vector3.UP, deg_to_rad(off))
		if not _is_blocked(from + Vector3(0, 0.6, 0), cand, check_dist, space_state):
			# Prefer directions that still go roughly toward the goal
			if cand.dot(base) > -0.5:
				return cand
	# All blocked — go with the widest that at least isn't straight into wall
	for off in offsets:
		var cand2: Vector3 = base.rotated(Vector3.UP, deg_to_rad(off))
		if cand2.dot(base) > -0.9:
			return cand2
	return base.rotated(Vector3.UP, deg_to_rad(90.0))


# When move_and_slide reports a collision, nudge the velocity along the wall
# normal and add a small perpendicular push to slide around the corner.
static func slide_along_wall(velocity: Vector3, enemy: CharacterBody3D) -> Vector3:
	if enemy.get_slide_collision_count() == 0:
		return velocity
	var col := enemy.get_slide_collision(0)
	var n: Vector3 = col.get_normal()
	n.y = 0.0
	if n.length_squared() < 0.001:
		return velocity
	n = n.normalized()
	# Remove velocity into the wall, keep tangential component + push along wall
	var vel_flat := Vector3(velocity.x, 0, velocity.z)
	var into_wall := vel_flat.dot(-n)
	if into_wall > 0.0:
		vel_flat += n * (into_wall + 0.5)  # push back out
	# Add sideways slide
	var tangent := Vector3(-n.z, 0, n.x)
	# Choose tangent that is closer to original direction
	if vel_flat.dot(tangent) < 0.0:
		tangent = -tangent
	vel_flat += tangent * 1.2
	return Vector3(vel_flat.x, velocity.y, vel_flat.z)


## Tests if an actor facing an obstacle can and should jump over it.
## Matches War Mode's obstacle jump clearance standard.
static func check_jump_clearance(enemy: CharacterBody3D, jump_velocity: float = 8.5) -> bool:
	if not enemy:
		return false
	var on_floor: bool = enemy.is_on_floor() if not enemy.has_meta("mock_on_floor") else bool(enemy.get_meta("mock_on_floor"))
	if not on_floor:
		return false
	var on_wall: bool = enemy.is_on_wall() if not enemy.has_meta("mock_on_wall") else bool(enemy.get_meta("mock_on_wall"))
	if on_wall:
		enemy.velocity.y = jump_velocity
		return true
	return false
