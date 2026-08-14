extends Node

## Verifies the WeaponHUD bare-fist cadence indicator: an empty hand shows the
## SHARED fist cooldown on its panel — a draining gold bar in the heat-bar slot
## plus a READY / "0.x s" countdown on the ammo label. Both empty hands show the
## same cooldown (they punch on the same cadence).
## The test is driven by a _process state machine (polling) because in headless
## runs `await` inside while loops / timer timeouts may never resume.
## Run: godot --headless --path . res://tests/weapon_hud_fist_verify.tscn

var _fails := 0
var _checks := 0
var _stage := 0
var _settle := 0

var _hud: Node = null
var _wm: Node = null
var _left_bar: ProgressBar = null
var _right_bar: ProgressBar = null
var _left_ammo: Label = null
var _right_ammo: Label = null


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("HUD_FIST OK: " + name)
	else:
		_fails += 1
		print("HUD_FIST FAIL: " + name)


func _finish() -> void:
	print("HUD_FIST_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _process(_delta: float) -> void:
	match _stage:
		0:
			_stage = 1
			_build_scene()
		1:
			# Wait until the HUD has found and connected to the WeaponManager.
			if _hud.weapon_manager != null:
				_stage = 2
				_settle = 0
		2:
			if _settle >= 2:
				_settle = 0
				_stage = 3
				# Ready state: both fists show READY and no cooldown bar.
				_check(_left_ammo.text == "READY", "ready fist shows READY on the left panel")
				_check(_right_ammo.text == "READY", "ready fist shows READY on the right panel")
				_check(not _left_bar.visible, "ready fist hides the cooldown bar (left)")
				_check(not _right_bar.visible, "ready fist hides the cooldown bar (right)")
				# Punch with the left fist -> shared core goes on cooldown.
				_wm._try_fire("left", null)
		3:
			if _settle >= 2:
				_settle = 0
				_stage = 4
				var cd: float = _wm._core_for_weapon(_wm._fist()).cooldown
				_check(cd > 0.3, "punch put the shared fist core on cooldown (%.2f)" % cd)
				_check(_left_bar.visible, "cooling fist shows the cooldown bar (left)")
				_check(_right_bar.visible, "other empty hand shows the SAME shared cooldown bar (right)")
				_check(absf(_left_bar.value - _right_bar.value) < 0.001, "both panels show the same cooldown value")
				_check(_left_ammo.text != "READY" and _left_ammo.text.ends_with("s"), "left panel shows a countdown (%s)" % _left_ammo.text)
				_check(_right_ammo.text != "READY" and _right_ammo.text.ends_with("s"), "right panel shows a countdown (%s)" % _right_ammo.text)
				# Force-advance the shared core past the cooldown.
				_wm._core_for_weapon(_wm._fist()).tick(1.0)
		4:
			if _settle >= 2:
				_stage = 5
				_check(_wm._core_for_weapon(_wm._fist()).cooldown == 0.0, "shared core recharged")
				_check(not _left_bar.visible, "recharged fist hides the cooldown bar again (left)")
				_check(not _right_bar.visible, "recharged fist hides the cooldown bar again (right)")
				_check(_left_ammo.text == "READY", "recharged fist shows READY again (left)")
				_check(_right_ammo.text == "READY", "recharged fist shows READY again (right)")
				_finish()


func _build_scene() -> void:
	# Player mecha with an empty-handed WeaponManager, exactly like the real HUD
	# expects (GameManager.get_player_mecha() looks up a node named "Mecha").
	var mecha := CharacterBody3D.new()
	mecha.name = "Mecha"
	add_child(mecha)

	_wm = Node3D.new()
	_wm.name = "WeaponManager"
	_wm.set_script(preload("res://scripts/mecha/weapon_manager.gd"))
	mecha.add_child(_wm)
	_wm.left_hand = null
	_wm.right_hand = null

	var hud_scene: PackedScene = preload("res://scenes/ui/weapon_hud.tscn")
	_hud = hud_scene.instantiate()
	add_child(_hud)

	_left_bar = _hud.left_heat_bar
	_right_bar = _hud.right_heat_bar
	_left_ammo = _hud.left_ammo_label
	_right_ammo = _hud.right_ammo_label


func _physics_process(_delta: float) -> void:
	_settle += 1
