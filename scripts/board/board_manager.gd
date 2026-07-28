extends Node3D

@onready var tile_container: Node3D = $TileContainer
@onready var player_token: MeshInstance3D = $PlayerToken

var current_pos: Vector2i = Vector2i.ZERO
var board: Array = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var generator = get_node_or_null("BoardGenerator")
	if generator:
		board = generator.generate_board()
		for row in board:
			for tile in row:
				tile_container.add_child(tile)
	current_pos = GlobalData.current_tile
	_update_token_position()
	_highlight_adjacent()


func move_to_tile(target: Vector2i) -> bool:
	if not _is_adjacent(current_pos, target):
		return false
	if not _is_in_bounds(target):
		return false
		
	current_pos = target
	GlobalData.current_tile = target
	_update_token_position()
	_clear_highlights()
	_highlight_adjacent()
	
	var tile_data = board[target.y][target.x]
	var tile_type = tile_data.get_meta("tile_type", "empty")
	
	# --- ระบบคำนวณเสริมความคืบหน้าของศัตรูในแต่ละก้าวเดิน ---
	process_turn_mobilization() # ศัตรูเรียกกองกำลังหนุนเสริมพล
	accumulate_stalker_chance() # เพิ่มโอกาสซุ่มโจมตีของ Stalking Ace
	# --------------------------------------------------
	
	EventBus.tile_entered.emit(target, tile_data)
	_process_tile_effect(tile_type)
	
	if tile_type != "combat":
		var intermission = get_node_or_null("IntermissionUI")
		if intermission:
			intermission.visible = true
			intermission.status_label.text = intermission._get_status_text()
	return true


# การเรียกระดมพลเสริมเข้ามาในกองทัพศัตรู (เติมกำลังพลเข้าหาความจุสูงสุด)
func process_turn_mobilization() -> void:
	if GlobalData.heat >= 3:
		# สุ่มเติมลูกน้อง Grunt เข้ามา 10% ถึง 20% ของกรอบ Max Capacity
		var grunt_recruit = int(GlobalData.enemy_forces["grunt_max"] * randf_range(0.10, 0.20))
		GlobalData.enemy_forces["grunt_current"] = clampi(
			GlobalData.enemy_forces["grunt_current"] + grunt_recruit, 
			0, GlobalData.enemy_forces["grunt_max"]
		)
		
		# โอกาส 30% ที่กองทัพศัตรูจะจัดกำลังพลระดับ Ace มาประจำการเพิ่ม 1 ลำต่อ Turn
		if randf() < 0.30:
			GlobalData.enemy_forces["ace_current"] = clampi(
				GlobalData.enemy_forces["ace_current"] + 1, 
				0, GlobalData.enemy_forces["ace_max"]
			)


# เพิ่มพูนโอกาสที่ Ace ที่เราเคยหนีมาจะจับพิกัดกบดานเราพบ
func accumulate_stalker_chance() -> void:
	if not GlobalData.stalking_aces.is_empty():
		# ยิ่งเดินบ่อยโดยไม่เคลียร์ ยิ่งแกะรอยง่ายขึ้นรอบละ 20%
		GlobalData.stalking_chance = minf(GlobalData.stalking_chance + 0.20, 1.0)


func _process_tile_effect(tile_type: String) -> void:
	match tile_type:
		"combat":
			# เช็คเหตุการณ์สุ่มโดนเซอร์ไพรส์จาก Stalking Ace
			if not GlobalData.stalking_aces.is_empty() and randf() < GlobalData.stalking_chance:
				_trigger_stalker_surprise_ambush()
			else:
				GameManager.enter_combat()
		"event":
			_trigger_random_event()
		"safehouse":
			HeatWantedSystem.modify_heat(-4)
			var safehouse = get_node_or_null("../SafehouseUI")
			if safehouse:
				safehouse.visible = true
				get_tree().paused = true
		_:
			pass


# ทำการท้าชนเซอร์ไพรส์ด่านพิเศษ โดยบีบให้ปะทะ Ace ทันที
func _trigger_stalker_surprise_ambush() -> void:
	# ดึง Ace ตัวแรกสุดที่จับพิกัดเราได้ออกมาต่อสู้
	var active_stalker = GlobalData.stalking_aces[0]
	GlobalData.stalking_chance = 0.0 # รีเซ็ตความคืบหน้าแกะรอย
	
	# แสดงข้อความแจ้งเตือนสีแดงเซอร์ไพรส์
	var safehouse_ui = get_node_or_null("../SafehouseUI")
	if safehouse_ui:
		safehouse_ui.status_label.text = "⚠️ สัญญาณเตือนภัยพิบัติ! Ace: " + active_stalker + " ดักโจมตีระหว่างทาง!"
	
	# พาผู้เล่นเข้าสู่ฉากการสู้รบทันที
	GameManager.enter_combat()


func _trigger_random_event() -> void:
	var events = [
		{"name": "Abandoned Cache", "effect": "credits", "amount": 50, "desc": "พบตู้เสบียงถูกทิ้งร้าง! +50 credits"},
		{"name": "Salvage Parts", "effect": "spare_parts", "amount": 5, "desc": "กู้ซากพาร์ทเก่าสำเร็จ! +5 spare parts"},
		{"name": "Ambush", "effect": "damage", "amount": 20, "desc": "โดนกองโจรซุ่มยิงระหว่างเดินทัพ! หุ่นเสียหาย 20 หน่วย"},
		{"name": "Friendly Trader", "effect": "credits", "amount": 30, "desc": "พบเจอกองคาราวานค้าขายพาร์ทที่เป็นมิตร +30 credits"},
		{"name": "Data Terminal", "effect": "data_cores", "amount": 1, "desc": "แฮกขุดข้อมูลเก่าได้พิมพ์เขียวการวิจัย! +1 data core"},
	]
	var event = events[randi() % events.size()]
	EventBus.event_triggered.emit(event)
	
	match event["effect"]:
		"credits":
			GlobalData.credits += event["amount"]
		"spare_parts":
			GlobalData.spare_parts += event["amount"]
		"data_cores":
			GlobalData.data_cores += event["amount"]
		"damage":
			# ส่งผลดาเมจตรงไปยังชิ้นส่วนแบบสุ่มของผู้เล่น
			if not GlobalData.equipped_parts.is_empty():
				var keys = GlobalData.equipped_parts.keys()
				var rand_part = keys[randi() % keys.size()]
				var cur_dmg = GlobalData.part_damage.get(rand_part, 0.0)
				GlobalData.part_damage[rand_part] = minf(cur_dmg + 0.25, 1.0) # สร้างความเสียหายสัดส่วน 25%


func get_tile_type(pos: Vector2i) -> String:
	if _is_in_bounds(pos):
		return board[pos.y][pos.x].get_meta("tile_type", "empty")
	return "empty"


func _update_token_position() -> void:
	player_token.position = Vector3(current_pos.x * 2.5, 0.5, current_pos.y * 2.5)


func _highlight_adjacent() -> void:
	var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for dir in directions:
		var pos = current_pos + dir
		if _is_in_bounds(pos):
			var tile = board[pos.y][pos.x]
			tile.highlight(true)


func _clear_highlights() -> void:
	for row in board:
		for tile in row:
			tile.highlight(false)


func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return abs(a.x - b.x) + abs(a.y - b.y) == 1


func _is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < board.size() and pos.y >= 0 and pos.y < board[0].size()
