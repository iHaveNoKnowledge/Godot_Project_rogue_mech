extends Node
## MISSILE LOCK CAP VERIFY — pod maximum governs locks, salvo launches them all.
## 1. max_total_locks = min(current mag, pod max_ammo); max_locks_per_target = pod max_ammo (per model, not hardcoded 8).
## 2. Salvo pricing: 1 lock = 1 missile = 1 ammo (Swarm's volley x3 stays on the dumbfire path).
## 3. Salvo pacing: zeroed cooldown between 0.065s-spaced shots lets every lock fly (fire_interval must not gate a single trigger pull).

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("MSL-CAP OK: " + name)
	else:
		_fails += 1
		printerr("MSL-CAP FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	var lock_script: Script = load("res://scripts/systems/missile_lock_on_system.gd")

	# --- 1. per-model caps ---
	var pods := {
		"res://resources/mech/stock/weapon_missile.tres": 8,
		"res://resources/mech/stock/weapon_micro_missile.tres": 24,
		"res://resources/mech/stock/weapon_swarm_missile.tres": 30,
		"res://resources/mech/stock/weapon_heavy_missile.tres": 5,
	}
	for path in pods.keys():
		var expected: int = pods[path]
		var w: WeaponPart = load(path)
		var sys: Node = Node.new()
		sys.set_script(lock_script)
		add_child(sys)
		sys.start_locking("left", w, expected)
		_check(sys.max_total_locks == expected, "%s total capped at pod max %d" % [w.weapon_name, expected])
		_check(sys.max_locks_per_target == expected, "%s per-target capped at pod max %d (not hardcoded 8)" % [w.weapon_name, expected])
		sys.queue_free()

	# Partial magazine: total follows current ammo, per-target still allows the full pod.
	var launcher: WeaponPart = load("res://resources/mech/stock/weapon_missile.tres")
	var psys: Node = Node.new()
	psys.set_script(lock_script)
	add_child(psys)
	psys.start_locking("left", launcher, 3)
	_check(psys.max_total_locks == 3, "partial mag (3/8): total follows current ammo")
	_check(psys.max_locks_per_target == 8, "partial mag (3/8): per-target still pod max 8")
	psys.queue_free()

	# --- 2+3. salvo: every lock flies at 0.065s spacing, 1 ammo each ---
	var swarm: WeaponPart = load("res://resources/mech/stock/weapon_swarm_missile.tres")
	var core := WeaponCore.from_weapon(swarm)
	core.unlimited_ammo = false
	core.ammo_per_shot = 1 # manager salvo pricing: 1 lock = 1 missile
	core.ammo = core.max_ammo
	var fired := 0
	for i in range(core.max_ammo):
		if i > 0:
			core.tick(0.065)
		core.cooldown = 0.0 # manager zeroes cooldown between salvo shots
		if core.consume_shot():
			fired += 1
	_check(fired == 30, "Swarm salvo launches all 30 locks (got %d)" % fired)
	_check(core.ammo == 0, "Swarm salvo costs exactly 30 ammo for 30 locks (1:1)")

	var ml: WeaponPart = load("res://resources/mech/stock/weapon_missile.tres")
	var core2 := WeaponCore.from_weapon(ml)
	core2.unlimited_ammo = false
	core2.ammo_per_shot = 1
	core2.ammo = core2.max_ammo
	var fired2 := 0
	for i in range(8):
		if i > 0:
			core2.tick(0.065)
		core2.cooldown = 0.0
		if core2.consume_shot():
			fired2 += 1
	_check(fired2 == 8, "Launcher salvo launches all 8 locks despite 2.0s interval (got %d)" % fired2)

	print("MISSILE_LOCK_CAP_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
