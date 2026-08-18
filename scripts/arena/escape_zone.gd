extends Area3D

## A retreat point on the battlefield edge (replaces the old boundary walls).
## While the player mech stays inside the zone a hold timer builds up; the zone's
## light indicator shifts from cyan to amber to red as it charges. If the player
## holds position for the full escape time the battle is abandoned and the player
## retreats back to the board without any victory rewards.

const DEFAULT_ESCAPE_TIME := 15.0

@export var escape_time: float = DEFAULT_ESCAPE_TIME

# Distance-based visibility: the glow wall only renders when the player is
# close to it (fade starts at VISIBLE_NEAR, fully invisible beyond VISIBLE_FAR).
# Far walls of the square frame simply don't draw, keeping the view clean.
const VISIBLE_NEAR := 22.0
const VISIBLE_FAR := 48.0
var _distance_alpha := 1.0

# Indicator colors: idle → charging → almost done.
const IDLE_COLOR := Color(0.35, 0.8, 1.0)
const CHARGE_COLOR := Color(0.9, 0.9, 0.2)
const DANGER_COLOR := Color(1.0, 0.25, 0.2)

var _time_inside := 0.0
var _player_inside := false
var _tracked_body: Node3D = null
var _escaped := false
var _battle_over := false

var _zone_mesh: MeshInstance3D
var _zone_material: StandardMaterial3D
var _beacon: OmniLight3D

# Local offset from the (widened) trigger box center to the arena edge where
# the visible glow wall is drawn. Set by the generator so the wall stays pinned
# at the edge while the trigger extends deeper into the field.
var wall_local: Vector3 = Vector3.ZERO

# Radial distance from the arena center to the boundary this zone hugs (the
# square arena edge for the classic frame, the footprint outline for irregular
# maps). Consumers/tests use it to confirm the trigger pokes past the wall.
var edge_dist: float = 0.0


func _ready() -> void:
	# Detect the player mech (collision layer 1); never behave as a collidable body.
	collision_layer = 0
	collision_mask = 1
	monitoring = true

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	EventBus.combat_ended.connect(_on_combat_ended)
	# Rebuild the visuals if the generator attached them after _ready.
	if _zone_material == null:
		_build_visuals()


func _process(_delta: float) -> void:
	_update_distance_visibility()


func _physics_process(delta: float) -> void:
	if _escaped or _battle_over or GameManager.is_escaping:
		return
	if _player_inside:
		# Re-validate each frame: the mech may have left or been destroyed.
		if _tracked_body == null or not is_instance_valid(_tracked_body) or not _is_player_body(_tracked_body):
			_player_inside = false
			_tracked_body = null
			_time_inside = 0.0
			_update_visual()
			return
		_time_inside += delta
		_update_visual()
		if _time_inside >= escape_time:
			_complete_escape()


func _on_body_entered(body: Node3D) -> void:
	if _is_player_body(body):
		_player_inside = true
		_tracked_body = body


func _on_body_exited(body: Node3D) -> void:
	if body == _tracked_body:
		_player_inside = false
		_tracked_body = null
		_time_inside = 0.0
		_update_visual()


func _on_combat_ended(_victory: bool) -> void:
	_battle_over = true


func _is_player_body(body: Node3D) -> bool:
	if body != GameManager.get_player_mecha() and not body.is_in_group("mecha"):
		return false
	# A destroyed mech is no longer able to retreat on foot.
	var hs = body.get_node_or_null("HealthSystem")
	if hs and hs.get("is_destroyed"):
		return false
	return true


func _complete_escape() -> void:
	if _escaped or _battle_over or GameManager.is_escaping:
		return
	_escaped = true
	_update_visual()
	GameManager.is_escaping = true
	EventBus.combat_escaped.emit()


# --- State accessors for the combat HUD --------------------------------------
# The screen-top RETREAT indicator polls the zone group instead of receiving a
# signal so it stays correct across re-spawns and zone rebuilds.

func is_player_inside() -> bool:
	return _player_inside and _tracked_body != null and is_instance_valid(_tracked_body)


func is_escape_complete() -> bool:
	return _escaped


# How far the hold has charged, 0..1 (drives the HUD color ramp).
func get_hold_progress() -> float:
	return clampf(_time_inside / maxf(escape_time, 0.001), 0.0, 1.0)


# Seconds left before the retreat completes (for the HUD countdown).
func get_hold_remaining() -> float:
	return maxf(escape_time - _time_inside, 0.0)


func _update_distance_visibility() -> void:
	if _zone_material == null:
		return
	var mecha = GameManager.get_player_mecha()
	if mecha == null:
		_distance_alpha = 1.0
		return
	var d := global_position.distance_to(mecha.global_position)
	_distance_alpha = clampf(1.0 - (d - VISIBLE_NEAR) / maxf(VISIBLE_FAR - VISIBLE_NEAR, 0.001), 0.0, 1.0)
	if _zone_mesh:
		_zone_mesh.visible = _distance_alpha > 0.03
	_update_visual()


func _update_visual() -> void:
	if _zone_material == null:
		return

	var t := clampf(_time_inside / maxf(escape_time, 0.001), 0.0, 1.0)
	var color: Color
	var energy: float
	var alpha: float

	if _escaped:
		color = DANGER_COLOR
		energy = 8.0
		alpha = 0.6
	elif _player_inside:
		if t < 0.5:
			color = IDLE_COLOR.lerp(CHARGE_COLOR, t * 2.0)
		else:
			color = CHARGE_COLOR.lerp(DANGER_COLOR, (t - 0.5) * 2.0)
		var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
		energy = 1.5 + t * 4.0
		energy *= pulse
		alpha = 0.35 + t * 0.3
	else:
		color = IDLE_COLOR
		energy = 0.6
		alpha = 0.18

	# Distance fade: far walls stay invisible; close ones (or the one being
	# charged) show at their normal alpha.
	energy *= _distance_alpha
	alpha *= _distance_alpha

	_zone_material.emission = color
	_zone_material.emission_energy_multiplier = energy
	_zone_material.albedo_color = Color(color.r, color.g, color.b, alpha)

	if _beacon:
		_beacon.light_color = color
		_beacon.light_energy = 0.4 + t * 3.0


# Builds the glow wall and beacon light. The generator adds the collision
# shape first so _ready() can read its size and build matching visuals. The
# trigger box is much thicker than the wall (it extends past the wall into the
# outside strip), so the visible wall is drawn as a slim slab; it is purely
# cosmetic — the player walks straight through it. No world-space text is
# drawn anymore: the RETREAT readout lives on the combat HUD at the top of
# the screen instead.
func _build_visuals() -> void:
	var col := _find_collision_shape()
	var size := Vector3(20.0, 2.0, 20.0)
	if col and col.shape is BoxShape3D:
		size = (col.shape as BoxShape3D).size

	# Glow wall: a slim translucent force-field slab spanning the zone's full
	# height, far more transparent than before so the battlefield edge reads
	# as a light veil rather than a solid barrier. The zone origin is the
	# collision box center (placed by the generator at wall_height/2), so the
	# wall sits grounded with no offset.
	_zone_material = StandardMaterial3D.new()
	_zone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_zone_material.albedo_color = Color(IDLE_COLOR.r, IDLE_COLOR.g, IDLE_COLOR.b, 0.08)
	_zone_material.emission_enabled = true
	_zone_material.emission = IDLE_COLOR
	_zone_material.emission_energy_multiplier = 0.4
	_zone_material.roughness = 0.4

	_zone_mesh = MeshInstance3D.new()
	_zone_mesh.name = "GlowWall"
	var wall := BoxMesh.new()
	# The trigger extends PAST this wall (the retreat hold keeps charging in the
	# dead zone behind it), so the visible slab is capped at a slim thickness.
	# Zones can be oriented with their long axis along X or Z, so cap whichever
	# axis is the thin (radial) one.
	if size.z < size.x:
		wall.size = Vector3(size.x, size.y, minf(size.z, 1.5))
	else:
		wall.size = Vector3(minf(size.x, 1.5), size.y, size.z)
	_zone_mesh.mesh = wall
	_zone_mesh.material_override = _zone_material
	# Pinned at the arena edge (wall_local), not at the widened trigger center.
	_zone_mesh.position = wall_local
	add_child(_zone_mesh)

	# Beacon light.
	_beacon = OmniLight3D.new()
	_beacon.name = "Beacon"
	_beacon.light_color = IDLE_COLOR
	_beacon.light_energy = 0.4
	_beacon.omni_range = 18.0
	_beacon.position = wall_local + Vector3(0, size.y * 0.5 + 1.5, 0)
	add_child(_beacon)


# Locates the generator-attached trigger shape by class (unnamed runtime nodes
# get "@ClassName@id" names in Godot 4.6, so name lookups never match).
func _find_collision_shape() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null

	_update_visual()
