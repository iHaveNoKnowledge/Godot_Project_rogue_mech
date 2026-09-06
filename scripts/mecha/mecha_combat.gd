extends Node

enum Mode { RANGED, CLOSE_COMBAT }

@onready var mecha: CharacterBody3D = get_parent()
@onready var aim_ray: RayCast3D = $"../AimRay"

var current_mode: Mode = Mode.RANGED
var lock_on_target: Node3D = null
var is_aiming: bool = false
var current_aim_point: Vector3 = Vector3.ZERO

# --- Deflect / Guard System ---
var is_guarding: bool = false
var guard_time: float = 0.0
const DEFLECT_WINDOW: float = 0.18 # 180ms timing for Just Deflect parry
const DEFLECT_LUNGE_SPEED: float = 8.0


func _ready() -> void:
	EventBus.lock_on_target_acquired.connect(_on_lock_on)
	EventBus.lock_on_target_lost.connect(_on_lock_off)


func _on_lock_on(target: Node3D) -> void:
	lock_on_target = target


func _on_lock_off() -> void:
	lock_on_target = null


func is_close_combat() -> bool:
	return current_mode == Mode.CLOSE_COMBAT


func toggle_combat_mode() -> void:
	var new_mode := Mode.CLOSE_COMBAT if current_mode == Mode.RANGED else Mode.RANGED
	set_combat_mode(new_mode)


func set_combat_mode(new_mode: Mode) -> void:
	if current_mode == new_mode:
		return
	current_mode = new_mode
	var mode_name := "close_combat" if current_mode == Mode.CLOSE_COMBAT else "ranged"
	EventBus.combat_mode_toggled.emit(mode_name)
	if AudioManager:
		AudioManager.play_sfx("cockpit_alert", mecha.global_position if mecha else Vector3.ZERO, 0.4)


func is_deflect_active() -> bool:
	return is_guarding and guard_time <= DEFLECT_WINDOW


func start_guard() -> void:
	if not is_guarding:
		is_guarding = true
		guard_time = 0.0
		EventBus.guard_state_changed.emit(true)


func stop_guard() -> void:
	if is_guarding:
		is_guarding = false
		guard_time = 0.0
		EventBus.guard_state_changed.emit(false)


## Triggers a Just Deflect: glances bullets away with metal sparks, reduces damage to near zero,
## and boosts the mech forward into melee strike distance.
func trigger_deflect(bullet_pos: Vector3 = Vector3.ZERO) -> void:
	var spark_pos = bullet_pos if bullet_pos != Vector3.ZERO else (mecha.global_position + Vector3(0, 1.4, 0))
	if AudioManager:
		AudioManager.play_sfx("bullet_ricochet", spark_pos, 0.8)
	if EffectManager:
		EffectManager.spawn_hit_spark(spark_pos, Vector3.UP, "pierce")

	# Forward lunge surge on successful deflect
	if mecha and is_instance_valid(mecha):
		var forward := -mecha.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		mecha.velocity += forward * DEFLECT_LUNGE_SPEED

	EventBus.deflect_triggered.emit(spark_pos, true)


## Evaluates damage mitigation factor (multiplier applied to raw incoming damage):
## 0.05 on perfect deflect, 0.35 on active guard, 1.0 when not guarding.
func get_guard_damage_mitigation() -> float:
	if not is_guarding:
		return 1.0
	if is_deflect_active():
		return 0.05 # 95% reduction on Just Deflect
	return 0.35 # 65% reduction on continuous Guard


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_combat_mode") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_2 or event.physical_keycode == KEY_2)):
		toggle_combat_mode()

	# Guard input (only active in Close Combat Mode; normal mode uses Q for shoulder_left)
	if is_close_combat():
		if event.is_action_pressed("guard") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q):
			start_guard()
		elif event.is_action_released("guard") or (event is InputEventKey and not event.pressed and event.keycode == KEY_Q):
			stop_guard()
	elif is_guarding:
		stop_guard()


func _physics_process(delta: float) -> void:
	if is_guarding:
		guard_time += delta

	# While any UI modal (Field Loot, Pause Menu) has the mouse free, freeze combat aim
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		is_aiming = false
		return

	# The mech is ragdolled in its core-breach death window: no aiming either.
	var mecha_hs = mecha.get_node_or_null("HealthSystem")
	if mecha_hs != null and bool(mecha_hs.get("is_destroyed")):
		is_aiming = false
		current_aim_point = Vector3.ZERO
		return
	is_aiming = Input.is_action_pressed("aim")
	current_aim_point = resolve_aim_point()
	if is_aiming or is_close_combat():
		if "strafe_mode" in mecha:
			mecha.strafe_mode = true
		var aim_dir = _aim_from_camera()
		var target_angle = atan2(-aim_dir.x, -aim_dir.z)
		mecha.rotation.y = lerp_angle(mecha.rotation.y, target_angle, 12.0 * delta)


func _aim_from_camera() -> Vector3:
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return -mecha.global_transform.basis.z
	var ray_origin = cam.global_position
	var ray_dir = -cam.global_transform.basis.z
	if lock_on_target and is_instance_valid(lock_on_target):
		ray_dir = (lock_on_target.global_position + Vector3(0, 1.0, 0) - ray_origin).normalized()
	return ray_dir


## Resolves where the guns are pointed this frame: a locked target directly,
## otherwise the crosshair ray against the world (same collision mask the fire
## path uses), falling back 50 m along the camera when nothing is hit.
func resolve_aim_point() -> Vector3:
	if lock_on_target and is_instance_valid(lock_on_target):
		return lock_on_target.global_position + Vector3(0, 1.0, 0)
	if not is_inside_tree():
		return Vector3.ZERO if mecha == null else mecha.global_position
	var vp := get_viewport()
	if vp == null:
		return mecha.global_position + (-mecha.global_transform.basis.z * 50.0) if mecha else Vector3.ZERO
	var cam := vp.get_camera_3d()
	if cam == null:
		return mecha.global_position + (-mecha.global_transform.basis.z * 50.0) if mecha else Vector3.ZERO
	var ray_origin := cam.project_ray_origin(vp.get_visible_rect().size / 2.0)
	var ray_dir := cam.project_ray_normal(vp.get_visible_rect().size / 2.0)

	var world_3d := vp.get_world_3d()
	if world_3d == null:
		return ray_origin + ray_dir * 500.0
	var space_state := world_3d.direct_space_state
	if space_state == null:
		return ray_origin + ray_dir * 500.0

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 500.0)
	query.collision_mask = 10
	var result := space_state.intersect_ray(query)
	if result:
		return result["position"]
	return ray_origin + ray_dir * 500.0


func fire_weapon() -> void:
	var target_pos: Vector3 = resolve_aim_point()
	EventBus.weapon_fired.emit(target_pos)
