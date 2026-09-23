extends CanvasLayer

@onready var aim_ray: RayCast3D = null

var _crosshair_visible: bool = true
var is_head_destroyed: bool = false
var warning_label: Label = null
var overlay_control: Control = null

# --- Melee reach ring ---
# A soft ground arc at the reachable melee range, drawn on the crosshair
# overlay while aiming so the player can see how close to close before a swing
# connects. Front-facing only (melee hits forward, not 360°).
const MELEE_RANGE_COLOR: Color = Color(1.0, 0.8, 0.25, 0.5)
const MELEE_ARC_STEPS: int = 24
const MELEE_ARC_HALF_ANGLE_DEG: float = 90.0
const FIST_REACH: float = 3.0

# --- Melee impact flash ---
# A quick white flash hugging the screen edges when a melee swing connects,
# drawn as nested screen-edge outlines that fade inward. Decays in ~0.25s.
var _flash_strength: float = 0.0
const FLASH_DECAY_PER_SEC: float = 4.0
const FLASH_COLOR: Color = Color(1.0, 1.0, 1.0)

# --- Jump Charge Radial Gauge ---
var _jump_charge_ratio: float = 0.0
var _jump_gauge_alpha: float = 0.0
const JUMP_ARC_RADIUS: float = 30.0
const JUMP_ARC_SPAN_DEG: float = 130.0


func _ready() -> void:
	await get_tree().process_frame
	var mecha = GameManager.get_player_mecha()
	if mecha:
		aim_ray = mecha.get_node_or_null("AimRay")
		if aim_ray:
			aim_ray.collision_mask = 10
		var wm = mecha.get_node_or_null("WeaponManager")
		if wm and wm.has_signal("melee_hit_landed"):
			wm.melee_hit_landed.connect(_on_melee_hit)
	_setup_warning_label()
	_setup_overlay_control()
	_update_crosshair_position()


func _on_melee_hit() -> void:
	_flash_strength = 1.0


func _draw_impact_flash() -> void:
	if _flash_strength <= 0.001:
		return
	var size := get_viewport().get_visible_rect().size
	var line_w := 4.0
	for i in range(5):
		var alpha := _flash_strength * (0.5 - 0.1 * float(i))
		if alpha <= 0.001:
			break
		var inset := float(i) * 14.0
		overlay_control.draw_rect(
			Rect2(inset, inset, size.x - inset * 2.0, size.y - inset * 2.0),
			Color(FLASH_COLOR, alpha), false, line_w)
		line_w += 2.0


func _setup_warning_label() -> void:
	warning_label = Label.new()
	warning_label.text = "WARNING: SENSORS OFFLINE (MANUAL AIM ONLY)"
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	warning_label.add_theme_font_size_override("font_size", 14)
	warning_label.set_anchors_preset(Control.PRESET_CENTER)
	warning_label.position = Vector2(-180, -40)
	warning_label.visible = false
	add_child(warning_label)


func _setup_overlay_control() -> void:
	overlay_control = Control.new()
	overlay_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_control.draw.connect(_on_overlay_draw)
	add_child(overlay_control)


func _process(delta: float) -> void:
	_check_head_status()
	_update_crosshair_position()
	_update_jump_charge_status(delta)
	if _flash_strength > 0.0:
		_flash_strength = maxf(_flash_strength - delta * FLASH_DECAY_PER_SEC, 0.0)
	if overlay_control:
		overlay_control.queue_redraw()


func _update_jump_charge_status(delta: float) -> void:
	var mecha = GameManager.get_player_mecha()
	if mecha:
		var js = mecha.get("jump_system")
		if js:
			if js.get("is_charging_prejump") == true:
				var ctime: float = float(js.get("prejump_charge_time")) if js.get("prejump_charge_time") != null else 0.0
				_jump_charge_ratio = clampf(ctime / 0.35, 0.0, 1.0)
				_jump_gauge_alpha = move_toward(_jump_gauge_alpha, 1.0, delta * 12.0)
				return
			elif js.get("is_jumping") == true and float(js.get("jump_charge")) > 0.0:
				var jc: float = float(js.get("jump_charge"))
				_jump_charge_ratio = clampf(jc / 0.35, 0.0, 1.0)
				_jump_gauge_alpha = move_toward(_jump_gauge_alpha, 1.0, delta * 12.0)
				return
	_jump_charge_ratio = 0.0
	_jump_gauge_alpha = move_toward(_jump_gauge_alpha, 0.0, delta * 6.0)


func _check_head_status() -> void:
	var mecha = GameManager.get_player_mecha()
	if mecha:
		var health = mecha.get_node_or_null("HealthSystem")
		if health:
			if health.has_method("is_part_destroyed"):
				is_head_destroyed = health.is_part_destroyed("head")
			elif "parts" in health and health.parts is Dictionary and health.parts.has("head"):
				var head_part = health.parts["head"]
				if head_part is Dictionary:
					is_head_destroyed = bool(head_part.get("destroyed", false))
				elif head_part is Object and "destroyed" in head_part:
					is_head_destroyed = bool(head_part.get("destroyed"))

	if warning_label:
		warning_label.visible = is_head_destroyed


func _update_crosshair_position() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	if warning_label:
		warning_label.position = center + Vector2(-180, -40)


# The reachable melee range to draw (0 = none): a held melee weapon's
# range_distance, else the bare-fist reach when a hand is empty, else nothing
# for a fully ranged loadout.
func _get_melee_range() -> float:
	var mecha = GameManager.get_player_mecha()
	if mecha == null:
		return 0.0
	var wm = mecha.get_node_or_null("WeaponManager")
	if wm == null:
		return 0.0
	var left: WeaponPart = wm.left_hand
	var right: WeaponPart = wm.right_hand
	if left != null and left.weapon_type == WeaponPart.WeaponType.MELEE:
		return left.range_distance
	if right != null and right.weapon_type == WeaponPart.WeaponType.MELEE:
		return right.range_distance
	if left == null or right == null:
		return FIST_REACH
	return 0.0


# World-space points of the front arc: radius `radius` around mecha_pos,
# centered on aim_dir, spanning MELEE_ARC_STEPS segments of a 180° front arc.
# Kept separate from the draw call so the geometry is directly testable.
func _compute_melee_arc_world_points(mecha_pos: Vector3, aim_dir: Vector3, radius: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	var half := deg_to_rad(MELEE_ARC_HALF_ANGLE_DEG)
	for i in range(MELEE_ARC_STEPS + 1):
		var a := -half + 2.0 * half * float(i) / float(MELEE_ARC_STEPS)
		var dir := aim_dir.rotated(Vector3.UP, a)
		points.append(mecha_pos + Vector3(dir.x, 0.0, dir.z) * radius)
	return points


func _draw_melee_range() -> void:
	if overlay_control == null:
		return
	var range_val := _get_melee_range()
	if range_val <= 0.0:
		return
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return
	var mecha = GameManager.get_player_mecha()
	if mecha == null:
		return
	var aim_dir := get_aim_direction()
	aim_dir.y = 0.0
	if aim_dir.length() < 0.1:
		return
	aim_dir = aim_dir.normalized()
	var world := _compute_melee_arc_world_points(mecha.global_position, aim_dir, range_val)
	var screen := PackedVector2Array()
	for p in world:
		screen.append(cam.unproject_position(p))
	overlay_control.draw_polyline(screen, MELEE_RANGE_COLOR, 2.0)


func get_aim_point() -> Vector3:
	if aim_ray == null:
		return Vector3.FORWARD

	aim_ray.force_raycast_update()
	if aim_ray.is_colliding():
		return aim_ray.get_collision_point()
	else:
		return aim_ray.global_position + aim_ray.global_transform.basis * aim_ray.target_position


func get_aim_direction() -> Vector3:
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return -Vector3.FORWARD

	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	var ray_origin = cam.project_ray_origin(center)
	var ray_dir = cam.project_ray_normal(center)

	var vp := get_viewport()
	if vp == null:
		return ray_dir
	var world_3d := vp.get_world_3d()
	if world_3d == null or world_3d.direct_space_state == null:
		return ray_dir
	var space_state := world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 200.0)
	query.collision_mask = 10
	var result := space_state.intersect_ray(query)

	if result:
		var parent_node := get_parent()
		var p_pos: Vector3 = parent_node.global_position if (parent_node is Node3D) else ray_origin
		return (result["position"] - p_pos).normalized()
	else:
		return ray_dir


func _on_overlay_draw() -> void:
	if overlay_control == null:
		return
	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0

	# Melee reach ring under the reticle (only when a hand can melee).
	_draw_melee_range()
	# Impact flash on the screen edges from a connected melee swing.
	_draw_impact_flash()
	# Jump charge radial arc gauge beside reticle.
	_draw_jump_charge_gauge(center)
	# Missile Lock-on Reticles & Targets
	_draw_missile_locks(center)

	if is_head_destroyed:
		# Sensors offline: a full + through the center signals manual aim only.
		overlay_control.draw_line(center + Vector2(-10, 0), center + Vector2(10, 0), Color.RED, 2.0)
		overlay_control.draw_line(center + Vector2(0, -10), center + Vector2(0, 10), Color.RED, 2.0)
	else:
		# Compact + with an open center: the empty gap (not a filled square) marks
		# the exact aim point, so the crosshair never blocks what's being shot.
		var gap := 6.0
		var len := 13.0
		var col := Color(0.25, 0.95, 0.3, 0.95)
		overlay_control.draw_line(center + Vector2(-gap - len, 0), center + Vector2(-gap, 0), col, 2.0)
		overlay_control.draw_line(center + Vector2(gap, 0), center + Vector2(gap + len, 0), col, 2.0)
		overlay_control.draw_line(center + Vector2(0, -gap - len), center + Vector2(0, -gap), col, 2.0)
		overlay_control.draw_line(center + Vector2(0, gap), center + Vector2(0, gap + len), col, 2.0)


## Draws a sleek radial arc gauge beside the crosshair indicating pre-jump / thruster charge.
func _draw_jump_charge_gauge(center: Vector2) -> void:
	if _jump_gauge_alpha <= 0.01:
		return

	var radius := JUMP_ARC_RADIUS
	var arc_span := deg_to_rad(JUMP_ARC_SPAN_DEG)
	var start_angle := -arc_span * 0.5
	var end_angle := arc_span * 0.5

	# 1. Background Arc Track
	var bg_color := Color(0.1, 0.22, 0.32, 0.45 * _jump_gauge_alpha)
	overlay_control.draw_arc(center, radius, start_angle, end_angle, 24, bg_color, 4.0, true)

	# 2. Min & Max Notch Ticks
	var tick_start_in := center + Vector2(cos(start_angle), sin(start_angle)) * (radius - 3.5)
	var tick_start_out := center + Vector2(cos(start_angle), sin(start_angle)) * (radius + 3.5)
	overlay_control.draw_line(tick_start_in, tick_start_out, Color(0.3, 0.75, 0.95, 0.65 * _jump_gauge_alpha), 1.5)

	var tick_end_in := center + Vector2(cos(end_angle), sin(end_angle)) * (radius - 3.5)
	var tick_end_out := center + Vector2(cos(end_angle), sin(end_angle)) * (radius + 3.5)
	overlay_control.draw_line(tick_end_in, tick_end_out, Color(0.3, 0.75, 0.95, 0.65 * _jump_gauge_alpha), 1.5)

	# 3. Active Fill Arc
	if _jump_charge_ratio > 0.01:
		var fill_end := start_angle + arc_span * _jump_charge_ratio
		var fill_color: Color
		if _jump_charge_ratio >= 0.99:
			# Fully charged (ง้างสุด): High-voltage electric neon amber / gold
			fill_color = Color(1.0, 0.9, 0.25, 0.98 * _jump_gauge_alpha)
		elif _jump_charge_ratio >= 0.5:
			# Halfway charged: Vibrant cyan-green
			fill_color = Color(0.3, 0.95, 0.65, 0.92 * _jump_gauge_alpha)
		else:
			# Initial charge: Cool tech blue
			fill_color = Color(0.25, 0.8, 1.0, 0.85 * _jump_gauge_alpha)

		overlay_control.draw_arc(center, radius, start_angle, fill_end, 24, fill_color, 3.5, true)

		# Tip Head Pip (bright glowing dot tracking charge)
		var tip_pos := center + Vector2(cos(fill_end), sin(fill_end)) * radius
		overlay_control.draw_circle(tip_pos, 2.5, fill_color)

	# 4. "MAX" Indicator when fully charged (ง้างสุด)
	if _jump_charge_ratio >= 0.99:
		var font: Font = overlay_control.get_theme_default_font()
		if font:
			var text_pos := center + Vector2(radius + 7.0, 4.0)
			overlay_control.draw_string(font, text_pos, "MAX", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.9, 0.3, 0.95 * _jump_gauge_alpha))


var _cached_wm: Node = null

func _draw_missile_locks(center: Vector2) -> void:
	if _cached_wm == null or not is_instance_valid(_cached_wm):
		var mecha = GameManager.get_player_mecha()
		if mecha:
			_cached_wm = mecha.get_node_or_null("WeaponManager")
	if _cached_wm == null:
		return

	var lock_sys = _cached_wm.get("missile_lock_system")
	if lock_sys == null or not is_instance_valid(lock_sys) or not lock_sys.is_locking:
		return

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var font: Font = overlay_control.get_theme_default_font()

	# 1. Central sweeping lock-on radar cone
	var sweep_radius := 65.0
	var radar_col := Color(0.2, 0.82, 1.0, 0.45)
	overlay_control.draw_arc(center, sweep_radius, 0.0, TAU, 36, radar_col, 1.5, true)

	for angle_deg in [45.0, 135.0, 225.0, 315.0]:
		var rad := deg_to_rad(angle_deg)
		var pt := center + Vector2(cos(rad), sin(rad)) * sweep_radius
		overlay_control.draw_circle(pt, 2.5, Color(0.3, 0.88, 1.0, 0.75))

	var total_locks: int = lock_sys.get_total_locks()
	if font:
		var lock_msg := ("SALVO: %d MISSILES" % total_locks) if total_locks > 1 else (("SALVO: 1 MISSILE") if total_locks == 1 else "LOCKING...")
		var col := Color(1.0, 0.25, 0.25, 0.95) if total_locks > 0 else Color(1.0, 0.8, 0.2, 0.85)
		var text_sz := font.get_string_size(lock_msg, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
		overlay_control.draw_string(font, center + Vector2(-text_sz.x * 0.5, sweep_radius + 20.0), lock_msg, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, col)

	# 2. Tactical diamond/square brackets on each locked target
	for target in lock_sys.locked_targets.keys():
		if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion():
			continue
		var count: int = int(lock_sys.locked_targets[target])
		if count <= 0:
			continue
		var tpos: Vector3 = target.global_position + Vector3(0.0, 1.2, 0.0)
		if cam.is_position_behind(tpos):
			continue
		var s_pos: Vector2 = cam.unproject_position(tpos)

		var bracket_sz := 24.0
		var bracket_col := Color(1.0, 0.2, 0.2, 0.95)
		var corner_len := 8.0

		# Top-Left corner
		overlay_control.draw_line(s_pos + Vector2(-bracket_sz, -bracket_sz), s_pos + Vector2(-bracket_sz + corner_len, -bracket_sz), bracket_col, 2.0)
		overlay_control.draw_line(s_pos + Vector2(-bracket_sz, -bracket_sz), s_pos + Vector2(-bracket_sz, -bracket_sz + corner_len), bracket_col, 2.0)
		# Top-Right corner
		overlay_control.draw_line(s_pos + Vector2(bracket_sz, -bracket_sz), s_pos + Vector2(bracket_sz - corner_len, -bracket_sz), bracket_col, 2.0)
		overlay_control.draw_line(s_pos + Vector2(bracket_sz, -bracket_sz), s_pos + Vector2(bracket_sz, -bracket_sz + corner_len), bracket_col, 2.0)
		# Bottom-Left corner
		overlay_control.draw_line(s_pos + Vector2(-bracket_sz, bracket_sz), s_pos + Vector2(-bracket_sz + corner_len, bracket_sz), bracket_col, 2.0)
		overlay_control.draw_line(s_pos + Vector2(-bracket_sz, bracket_sz), s_pos + Vector2(-bracket_sz, -bracket_sz + corner_len), bracket_col, 2.0)
		# Bottom-Right corner
		overlay_control.draw_line(s_pos + Vector2(bracket_sz, bracket_sz), s_pos + Vector2(bracket_sz - corner_len, bracket_sz), bracket_col, 2.0)
		overlay_control.draw_line(s_pos + Vector2(bracket_sz, bracket_sz), s_pos + Vector2(bracket_sz, bracket_sz - corner_len), bracket_col, 2.0)

		# Center pip
		overlay_control.draw_circle(s_pos, 3.0, bracket_col)

		# Number badge e.g. [x2 MSL]
		if font:
			var badge_str := "[x%d MSL]" % count
			overlay_control.draw_string(font, s_pos + Vector2(bracket_sz + 6.0, 5.0), badge_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.9, 0.25, 0.98))
