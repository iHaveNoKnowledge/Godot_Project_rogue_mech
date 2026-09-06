extends Node

@export var heat_decay_rate: int = 1
@export var wanted_thresholds: Array[int] = [4, 7, 11]
@export var max_heat: int = 15


func _ready() -> void:
	EventBus.tile_entered.connect(_on_tile_entered)
	EventBus.board_day_ended.connect(_on_board_day_ended)
	EventBus.combat_ended.connect(_on_combat_ended)


func _on_tile_entered(_pos: Vector2i, _data: Node) -> void:
	pass


# The open grid is walked cell-by-cell; heat and notoriety cool down once per
# day (a day = many cells) instead of on every single cell step.
func _on_board_day_ended() -> void:
	modify_heat(-heat_decay_rate)
	decay_notoriety_memory() # สลายความจำความระแวงลงทีละนิดเมื่อจบวัน


func _on_combat_ended(victory: bool) -> void:
	if victory:
		# คำนวณ Heat เพิ่มตามอัตรากำลังทีมผู้เล่น (Squad size)
		calculate_combat_heat(true)
	else:
		calculate_combat_heat(false)


# คำนวณเพิ่มค่า Heat โดยคำนวณจากขนาดทีมที่พากันไปรุมสู้ล่าสุด
func calculate_combat_heat(victory: bool) -> void:
	var base_gain = 1.0 if victory else 2.0
	var squad_size = GlobalData.narrative.last_combat_squad_size
	
	# ยิ่งทีมเราใหญ่ (Squad size มาก) ความโด่งดังและค่า Heat จะยิ่งทวีคูณ
	var squad_multiplier = 1.0 + (squad_size * 0.25)
	var final_heat_gain = base_gain * squad_multiplier
	
	modify_heat(int(final_heat_gain))
	
	# อัปเดต Notoriety Memory บันทึกความหวาดระแวงสูงสุดของศัตรู
	GlobalData.narrative.max_notoriety_multiplier = maxf(GlobalData.narrative.max_notoriety_multiplier, squad_multiplier)


# ค่อยๆ สลายค่าสเกลความยากสะสม (Notoriety Decay) เผื่อเราเปลี่ยนมาลุยเดี่ยว ศัตรูจะไม่ลดสัดส่วนกองทัพทันที
func decay_notoriety_memory() -> void:
	if GlobalData.narrative.max_notoriety_multiplier > 1.0:
		# ค่อยๆ หายตื่นตระหนกตาละ 5% (0.05) จนกว่าจะคืนสู่ค่าปกติ 1.0
		GlobalData.narrative.max_notoriety_multiplier = maxf(GlobalData.narrative.max_notoriety_multiplier - 0.05, 1.0)


## Initializes heat for an extraction contract based on min/max heat settings.
func init_contract_heat(min_stars: int, max_stars: int) -> void:
	GlobalData.board.extraction_min_heat = min_stars
	GlobalData.board.extraction_max_heat = max_stars
	# 1 star = ~2 heat points, 2 stars = ~5 heat points, etc.
	var initial_heat = min_stars * 3
	GlobalData.board.heat = initial_heat
	_update_wanted()
	update_enemy_mobilization_capacity()


## Called on each player move step in extraction mode
func on_player_step_heat() -> void:
	GlobalData.board.mission_step_count += 1
	# Accumulate 1 heat point every 4 movement steps
	if GlobalData.board.mission_step_count % 4 == 0:
		modify_heat(1)


func modify_heat(amount: int) -> void:
	var min_h := GlobalData.board.extraction_min_heat * 3
	var max_h := GlobalData.board.extraction_max_heat * 3
	GlobalData.board.heat = clampi(GlobalData.board.heat + amount, min_h, max_h)
	EventBus.heat_changed.emit(GlobalData.board.heat)
	_update_wanted()
	update_enemy_mobilization_capacity()
	if ResourceLoader.exists("res://scripts/systems/faction_system.gd"):
		var FS2 = load("res://scripts/systems/faction_system.gd")
		FS2.evaluate_triggers()


func _update_wanted() -> void:
	# Calculate 1 to 5 Stars (GTA-style)
	var stars: int = 1
	var h: int = GlobalData.board.heat
	if h >= 14:
		stars = 5
	elif h >= 11:
		stars = 4
	elif h >= 8:
		stars = 3
	elif h >= 5:
		stars = 2
	else:
		stars = 1

	stars = clampi(stars, GlobalData.board.extraction_min_heat, GlobalData.board.extraction_max_heat)
	if stars != GlobalData.board.wanted_level:
		GlobalData.board.wanted_level = stars
		EventBus.wanted_changed.emit(stars)


# Sector progression: the run gets hotter each sector even after heat cools
# between sectors. Keeps signals and enemy mobilization in sync.
func escalate_wanted(amount: int = 1, max_wanted: int = 5) -> void:
	GlobalData.board.wanted_escalation = mini(GlobalData.board.wanted_escalation + amount, max_wanted)
	_update_wanted()
	update_enemy_mobilization_capacity()


# ดึงสัดส่วนตัวคูณความยากตามค่า Heat และ Notoriety Memory ผสมผสานกัน
func get_enemy_force_multiplier() -> float:
	# คำนวณความใหญ่จาก Notoriety Memory เป็นหลักเพื่อให้ศัตรูยังระแวงอยู่
	return GlobalData.narrative.max_notoriety_multiplier * (1.0 + (GlobalData.board.wanted_level * 0.15))


## Updates enemy mobilization capacity based on current wanted/heat level and sector progression
func update_enemy_mobilization_capacity() -> void:
	var wanted := GlobalData.board.wanted_level
	var sector := GlobalData.board.current_sector
	var base_grunts := 10 + (sector - 1) * 5 + wanted * 3
	var base_aces := 1 + (sector - 1) + (1 if wanted >= 3 else 0)
	GlobalData.narrative.enemy_forces["grunt_max"] = base_grunts
	GlobalData.narrative.enemy_forces["ace_max"] = base_aces
	GlobalData.narrative.enemy_forces["grunt_current"] = mini(
		int(GlobalData.narrative.enemy_forces.get("grunt_current", base_grunts)),
		base_grunts
	)
	GlobalData.narrative.enemy_forces["ace_current"] = mini(
		int(GlobalData.narrative.enemy_forces.get("ace_current", base_aces)),
		base_aces
	)
