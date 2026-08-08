extends BoneAttachment3D

@export var slot_name: String = ""

var part_resource: ArmorPart = null
var current_hp: float = 0.0
var current_frame_hp: float = 0.0
var is_armor_broken: bool = false
var is_frame_destroyed: bool = false
var hitbox: Area3D


func _ready() -> void:
	hitbox = get_node("Area3D")
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	_initialize_part()


func _initialize_part() -> void:
	if GlobalData.equipped_parts.has(slot_name):
		part_resource = GlobalData.equipped_parts[slot_name]
	else:
		part_resource = _get_default_part()
	if part_resource:
		current_hp = part_resource.max_hp * (1.0 - GlobalData.part_damage.get(slot_name, 0.0))
		current_frame_hp = part_resource.max_frame_hp * (1.0 - GlobalData.part_damage.get(slot_name + "_frame", 0.0))
		is_armor_broken = current_hp <= 0.0
		is_frame_destroyed = current_frame_hp <= 0.0


func _get_default_part() -> ArmorPart:
	var path = "res://resources/mech/stock/%s_standard.tres" % slot_name
	return load(path) as ArmorPart


func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if is_frame_destroyed or part_resource == null:
		return

	# ถ้ายังมีเกราะ → รับดาเมจที่เกราะก่อน
	if not is_armor_broken:
		var result = DamageCalculator.calculate_damage(amount, part_resource.armor_class, current_hp, is_armor_broken)
		current_hp = result["remaining"]
		var armor_damage_pct = 1.0 - (current_hp / part_resource.max_hp)
		GlobalData.part_damage[slot_name] = clampf(armor_damage_pct, 0.0, 1.0)
		EventBus.damage_received.emit(slot_name, result["reduced"], damage_type)
		EventBus.armor_degraded.emit(slot_name, current_hp, part_resource.max_hp)
		if result["destroyed"]:
			_on_armor_broken()
	# ถ้าเกราะแตกแล้ว → ดาเมจตรงไปที่ frame
	else:
		current_frame_hp -= amount
		var frame_damage_pct = 1.0 - (current_frame_hp / part_resource.max_frame_hp)
		GlobalData.part_damage[slot_name + "_frame"] = clampf(frame_damage_pct, 0.0, 1.0)
		EventBus.damage_received.emit(slot_name, amount, damage_type)
		if current_frame_hp <= 0.0:
			_on_frame_destroyed()


func _on_armor_broken() -> void:
	is_armor_broken = true
	current_hp = 0.0
	GlobalData.part_damage[slot_name] = 1.0
	EventBus.part_destroyed.emit(slot_name)
	EventBus.weight_changed.emit(0.0)
	hitbox.set_deferred("monitoring", false)


func _on_frame_destroyed() -> void:
	is_frame_destroyed = true
	current_frame_hp = 0.0
	GlobalData.part_damage[slot_name + "_frame"] = 1.0
	# ปลด collision ออก ชิ้นส่วนหายไปจริงๆ
	set_deferred("monitoring", false)
	visible = false
	EventBus.weight_changed.emit(0.0)


func _on_hitbox_area_entered(area: Area3D) -> void:
	if area.is_in_group("projectile"):
		take_damage(25.0, "kinetic")
