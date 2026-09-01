extends Node3D
class_name WarChunkLoader

## Chunk LOD 2000x2000 — 250m = 8x8 = 64 chunks, cull ไกล + ปิด shadow ไกล >150m
## ใช้กับ Ore/Cache/Salvage/Wreckage — ไม่ใช่ MultiMesh (MultiMesh ไม่ต้อง chunk)

const CHUNK_SIZE := 250.0
const CHUNK_COUNT := 8
const HALF := 1000.0
const LOAD_RADIUS := 450.0
const SHADOW_RADIUS := 150.0

var _chunks: Dictionary = {} # Vector2i -> Node3D
var _player: Node3D = null


func _ready() -> void:
	# สร้าง chunk containers 64 อัน
	for x in range(CHUNK_COUNT):
		for z in range(CHUNK_COUNT):
			var key := Vector2i(x, z)
			var c := Node3D.new()
			c.name = "Chunk_%d_%d" % [x, z]
			var cx: float = -HALF + CHUNK_SIZE * (x + 0.5)
			var cz: float = -HALF + CHUNK_SIZE * (z + 0.5)
			c.position = Vector3.ZERO # chunk origin still 0, children use world pos
			c.set_meta("center", Vector2(cx, cz))
			add_child(c)
			_chunks[key] = c


func get_chunk_key(world_x: float, world_z: float) -> Vector2i:
	var ix: int = clampi(int(floor((world_x + HALF) / CHUNK_SIZE)), 0, CHUNK_COUNT - 1)
	var iz: int = clampi(int(floor((world_z + HALF) / CHUNK_SIZE)), 0, CHUNK_COUNT - 1)
	return Vector2i(ix, iz)


func add_to_chunk(node: Node3D) -> void:
	if node == null:
		return
	var key := get_chunk_key(node.position.x, node.position.z)
	var chunk: Node3D = _chunks.get(key, null)
	if chunk == null:
		add_child(node)
		return
	# reparent under chunk (keep world transform)
	var world_pos: Vector3 = node.position
	if node.get_parent():
		node.get_parent().remove_child(node)
	chunk.add_child(node)
	node.position = world_pos - chunk.position


func register_existing_children(root: Node3D) -> void:
	# ย้ายลูกที่มีอยู่แล้วเข้า chunk ตามตำแหน่งโลก (ใช้กับ ore ที่ spawn ก่อน)
	var to_move: Array[Node] = []
	for child in root.get_children():
		if child is Node3D and child.has_meta("chunk_auto"):
			to_move.append(child)
	for n in to_move:
		add_to_chunk(n as Node3D)


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("mecha") as Node3D
		if _player == null:
			return
	var ppos := Vector2(_player.global_position.x, _player.global_position.z)
	for key in _chunks.keys():
		var chunk: Node3D = _chunks[key]
		var center: Vector2 = chunk.get_meta("center")
		var dist: float = ppos.distance_to(center)
		# cull ไกล
		var should_show: bool = dist < LOAD_RADIUS + HALF * 0.7
		# chunk ไกลมาก (>800) ซ่อนเลย, กลางๆ แสดงแต่ปิด shadow
		chunk.visible = should_show
		var shadow_on: bool = dist < SHADOW_RADIUS + 200.0
		if chunk.visible:
			for child in chunk.get_children():
				if child is MeshInstance3D:
					(child as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow_on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				# StaticBody ลูกๆ
				for sub in child.get_children():
					if sub is MeshInstance3D:
						(sub as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow_on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
