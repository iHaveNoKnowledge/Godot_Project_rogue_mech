extends Node

@export var heat_decay_rate: int = 1
@export var wanted_thresholds: Array[int] = [4, 7, 11]
@export var max_heat: int = 15


func _ready() -> void:
	EventBus.tile_entered.connect(_on_tile_entered)
	EventBus.combat_ended.connect(_on_combat_ended)


func _on_tile_entered(_pos: Vector2i, _data: Node) -> void:
	modify_heat(-heat_decay_rate)
	decay_notoriety_memory() # สลายความจำความระแวงลงทีละนิดเมื่อเดินตาใหม่


func _on_combat_ended(victory: bool) -> void:
	if victory:
		# คำนวณ Heat เพิ่มตามอัตรากำลังทีมผู้เล่น (Squad size)
		calculate_combat_heat(true)
	else:
		calculate_combat_heat(false)


# คำนวณเพิ่มค่า Heat โดยคำนวณจากขนาดทีมที่พากันไปรุมสู้ล่าสุด
func calculate_combat_heat(victory: bool) -> void:
	var base_gain = 1.0 if victory else 2.0
	var squad_size = GlobalData.last_combat_squad_size
	
	# ยิ่งทีมเราใหญ่ (Squad size มาก) ความโด่งดังและค่า Heat จะยิ่งทวีคูณ
	var squad_multiplier = 1.0 + (squad_size * 0.25)
	var final_heat_gain = base_gain * squad_multiplier
	
	modify_heat(int(final_heat_gain))
	
	# อัปเดต Notoriety Memory บันทึกความหวาดระแวงสูงสุดของศัตรู
	GlobalData.max_notoriety_multiplier = maxf(GlobalData.max_notoriety_multiplier, squad_multiplier)


# ค่อยๆ สลายค่าสเกลความยากสะสม (Notoriety Decay) เผื่อเราเปลี่ยนมาลุยเดี่ยว ศัตรูจะไม่ลดสัดส่วนกองทัพทันที
func decay_notoriety_memory() -> void:
	if GlobalData.max_notoriety_multiplier > 1.0:
		# ค่อยๆ หายตื่นตระหนกตาละ 5% (0.05) จนกว่าจะคืนสู่ค่าปกติ 1.0
		GlobalData.max_notoriety_multiplier = maxf(GlobalData.max_notoriety_multiplier - 0.05, 1.0)


func modify_heat(amount: int) -> void:
	GlobalData.heat = clampi(GlobalData.heat + amount, 0, max_heat)
	EventBus.heat_changed.emit(GlobalData.heat)
	_update_wanted()
	update_enemy_mobilization_capacity() # ขยายหรือล็อกขนาดสัดส่วนทัพสูงสุด


# ล็อกและปลดล็อกการระดมพลตามระบบ Heat (Early/Late Game Gates)
func update_enemy_mobilization_capacity() -> void:
	var heat = GlobalData.heat
	
	if heat < 3:
		# ช่วงต้นเกม (Tutorial Zone): ล็อกกำลังพลศัตรูไว้ระดับต่ำสุดเพื่อฝึกซ้อมฝีมือ
		GlobalData.enemy_forces["grunt_max"] = 20
		GlobalData.enemy_forces["ace_max"] = 2
		GlobalData.enemy_forces["boss_max"] = 1
	elif heat >= 3 and heat < 7:
		GlobalData.enemy_forces["grunt_max"] = 60
		GlobalData.enemy_forces["ace_max"] = 4
		GlobalData.enemy_forces["boss_max"] = 1
	elif heat >= 7 and heat < 11:
		GlobalData.enemy_forces["grunt_max"] = 110
		GlobalData.enemy_forces["ace_max"] = 6
		GlobalData.enemy_forces["boss_max"] = 1
	else: # Heat 11+ (Late Game)
		GlobalData.enemy_forces["grunt_max"] = 150
		GlobalData.enemy_forces["ace_max"] = 8
		GlobalData.enemy_forces["boss_max"] = 2


func add_wave_heat() -> void:
	modify_heat(3)


func _update_wanted() -> void:
	# Heat thresholds push wanted up to 3; sector progression escalates it
	# further via escalate_wanted(). The escalation acts as a floor so a
	# heat cool-down never undoes the run's progression.
	var heat_derived = 0
	for threshold in wanted_thresholds:
		if GlobalData.heat >= threshold:
			heat_derived += 1
	var new_wanted = maxi(heat_derived, GlobalData.wanted_escalation)
	if new_wanted != GlobalData.wanted_level:
		GlobalData.wanted_level = new_wanted
		EventBus.wanted_changed.emit(new_wanted)


# Sector progression: the run gets hotter each sector even after heat cools
# between sectors. Keeps signals and enemy mobilization in sync.
func escalate_wanted(amount: int = 1, max_wanted: int = 5) -> void:
	GlobalData.wanted_escalation = mini(GlobalData.wanted_escalation + amount, max_wanted)
	_update_wanted()
	update_enemy_mobilization_capacity()


# ดึงสัดส่วนตัวคูณความยากตามค่า Heat และ Notoriety Memory ผสมผสานกัน
func get_enemy_force_multiplier() -> float:
	# คำนวณความใหญ่จาก Notoriety Memory เป็นหลักเพื่อให้ศัตรูยังระแวงอยู่
	return GlobalData.max_notoriety_multiplier * (1.0 + (GlobalData.wanted_level * 0.15))
