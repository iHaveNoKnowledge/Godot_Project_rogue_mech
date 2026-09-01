extends RefCounted
class_name WarDeploymentManager

## Deploy Cap + Stock Cooldown — per PLAN.md 6.2
## แยกจาก war_god_mech_system.gd (ชั่วคราว) มาเป็นไฟล์เดี่ยว
## Caps: Line 5/5, Strike 3/3, Iron 3/3, Valkyrion 1/1
## Stock Respawn: พังแล้วติด cooldown เติมสต็อก (Valkyrion 3-5 นาที)

const CAPS: Dictionary = {
	"line": 5,
	"strike": 3,
	"iron": 3,
	"valkyrion": 1,
}

const COOLDOWNS: Dictionary = {
	"line": 30.0,
	"strike": 60.0,
	"iron": 60.0,
	"valkyrion": 180.0,
}

## runtime state (instance)
var deployed: Dictionary = {"line": 0, "strike": 0, "iron": 0, "valkyrion": 0}
var pending: Dictionary = {"line": [], "strike": [], "iron": [], "valkyrion": []} # Array[float] remaining


func can_deploy(category: String) -> bool:
	var cat = category.to_lower()
	if not CAPS.has(cat):
		return false
	var cap: int = CAPS[cat]
	var dep: int = int(deployed.get(cat, 0))
	var pend: int = (pending.get(cat, []) as Array).size()
	return (dep + pend) < cap


func available_stock(category: String) -> int:
	var cat = category.to_lower()
	if not CAPS.has(cat):
		return 0
	var cap: int = CAPS[cat]
	var dep: int = int(deployed.get(cat, 0))
	var pend: int = (pending.get(cat, []) as Array).size()
	return cap - dep - pend


func on_deployed(category: String) -> bool:
	if not can_deploy(category):
		return false
	var cat = category.to_lower()
	deployed[cat] = int(deployed.get(cat, 0)) + 1
	return true


func on_destroyed(category: String) -> void:
	var cat = category.to_lower()
	if not CAPS.has(cat):
		return
	deployed[cat] = maxi(0, int(deployed.get(cat, 0)) - 1)
	var cd: float = float(COOLDOWNS.get(cat, 30.0))
	if cat == "valkyrion":
		cd = randf_range(180.0, 300.0)
	(pending[cat] as Array).append(cd)


func on_repaired_no_cooldown(_category: String) -> void:
	# ถอยกลับ Hangar/Carrier ซ่อม 15-30วิ ไม่เสีย cooldown — ไม่ต้องทำอะไร (ไม่เข้า pending)
	pass


func tick(delta: float) -> void:
	for cat in pending.keys():
		var arr: Array = pending[cat]
		var next: Array = []
		for t in arr:
			var rem: float = float(t) - delta
			if rem > 0.0:
				next.append(rem)
		pending[cat] = next


func get_cooldown_remaining(category: String) -> float:
	var cat = category.to_lower()
	var arr: Array = pending.get(cat, []) as Array
	if arr.is_empty():
		return 0.0
	var min_rem: float = float(arr[0])
	for v in arr:
		min_rem = minf(min_rem, float(v))
	return min_rem


func get_status_text() -> String:
	var parts: Array[String] = []
	for cat in CAPS.keys():
		var cap: int = CAPS[cat]
		var dep: int = int(deployed.get(cat, 0))
		var avail: int = available_stock(cat)
		var cd: float = get_cooldown_remaining(cat)
		if cd > 0.0:
			parts.append("%s %d/%d (CD %.0fs)" % [cat, dep, cap, cd])
		else:
			parts.append("%s %d/%d avail %d" % [cat, dep, cap, avail])
	return " | ".join(parts)
