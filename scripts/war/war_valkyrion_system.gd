extends RefCounted
class_name WarValkyrionSystem

## Valkyrion — full blueprint 8% + whole mech 2% + Mass Product 75% (per PLAN.md 5,7)

const VALKYRION_POOL: Array[String] = [
	"res://resources/mech/stock/mech_valkyrion.tres",
	"res://resources/mech/stock/mech_ace.tres",
]

static func roll_data_reward() -> String:
	var r = randf()
	if r < 0.02:
		return "whole_mech"
	elif r < 0.10:
		return "full_blueprint"
	elif r < 0.40:
		return "part"
	elif r < 0.60:
		return "frame"
	elif r < 0.80:
		return "module"
	else:
		return "weapon"


static func grant_whole_mech(parent: Node, pos: Vector3) -> Node3D:
	var scene = load("res://scenes/mecha/mecha_base.tscn")
	if scene == null:
		return null
	var mech = scene.instantiate()
	mech.name = "Valkyrion_Wreck"
	mech.position = pos
	mech.add_to_group("valkyrion_wreck")
	mech.add_to_group("valkyrion_wreck")
	mech.set_meta("is_valkyrion", true)
	mech.set_meta("is_valkyrion", true)
	mech.set_meta("is_unoccupied", true)
	var lbl = Label3D.new()
	lbl.text = "VALKYRION\n[F] BOARD"
	lbl.font_size = 22
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0, 3, 0)
	mech.add_child(lbl)
	parent.add_child(mech)
	return mech


static func grant_blueprint(carrier: Node) -> void:
	carrier.set_meta("valkyrion_blueprint", true)
	carrier.set_meta("valkyrion_blueprint", true)
	GlobalData.save_run()


static func craft_mass_product(blueprint_id: String) -> bool:
	# 75% stats, 40% cost — per PLAN.md 7
	if GlobalData.currency.credits < 400 or GlobalData.currency.scrap < 80:
		return false
	GlobalData.currency.try_spend_credits(400)
	GlobalData.currency.try_spend_scrap(80)
	return true


static func craft_original(blueprint_id: String) -> bool:
	if GlobalData.currency.credits < 800 or GlobalData.currency.scrap < 200:
		return false
	GlobalData.currency.try_spend_credits(800)
	GlobalData.currency.try_spend_scrap(200)
	return true
