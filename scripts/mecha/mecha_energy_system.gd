extends Node

## ---------------------------------------------------------------------------
## MECHA ENERGY SYSTEM — energy pool, roller drain, regen, and external drop
## tanks.  Extracted from mecha_controller.gd for single-responsibility.
##
## The roller's drain ramps up the longer it is held; releasing it restarts
## regen immediately.  Drop tanks extend the pool but are fragile — enemy fire
## can detonate them.
## ---------------------------------------------------------------------------

var max_energy: float = 200.0
var energy: float = 200.0

const ENERGY_REGEN_RATE := 10.0
const ROLLER_BASE_DRAIN := 2.0
const ROLLER_RAMP_DRAIN := 3.0
const ROLLER_MAX_DRAIN := 20.0
var roller_drain_ramp: float = 0.0

# Drop tanks (GDD §2.4).
var _drop_tank_active: bool = false
var _drop_tank_hp: float = 30.0
var _drop_tank_detonating: bool = false
var _drop_tank_timer: float = 0.0
const DROP_TANK_DET_DELAY := 1.5
const DROP_TANK_HP_PER_TANK := 30.0

## Must be set by the parent controller before calling process().
var is_roller_dashing: bool = false
var input_dir: Vector2 = Vector2.ZERO
var is_on_floor: bool = true


func initialize_from_global() -> void:
	## Load persisted energy from GlobalData (survives combat/board transitions).
	max_energy = GlobalData.fuel.mech_max_energy
	energy = clampf(GlobalData.fuel.mech_energy, 0.0, max_energy)
	if GlobalData.fuel.drop_tanks_attached > 0 and GlobalData.fuel.drop_tank_fuel > 0.0:
		_drop_tank_active = true
		_drop_tank_hp = GlobalData.fuel.drop_tanks_attached * DROP_TANK_HP_PER_TANK
		max_energy += GlobalData.fuel.drop_tank_fuel
		energy += GlobalData.fuel.drop_tank_fuel
	var dtv = get_parent().get_node_or_null("DropTankVisuals") if get_parent() else null
	if dtv and dtv.has_method("_refresh"):
		dtv._refresh()


func persist_to_global() -> void:
	GlobalData.fuel.mech_energy = energy
	GlobalData.fuel.mech_max_energy = max_energy


func process_energy(delta: float) -> void:
	var parent = get_parent()
	var pos: Vector3 = parent.global_position if parent else Vector3.ZERO

	if is_roller_dashing and is_on_floor and input_dir.length() > 0.0:
		roller_drain_ramp = minf(roller_drain_ramp + ROLLER_RAMP_DRAIN * delta, ROLLER_MAX_DRAIN)
		var drain_mult := GlobalData.DUST_STORM_ROLLER_DRAIN_MULT if GlobalData.board.current_hazard == GlobalData.HAZARD_DUST_STORM else 1.0
		energy = maxf(energy - (ROLLER_BASE_DRAIN + roller_drain_ramp) * drain_mult * delta, 0.0)
		if energy <= 0.0:
			is_roller_dashing = false
			roller_drain_ramp = 0.0
			if AudioManager:
				AudioManager.play_mecha_actuator(pos)
	else:
		roller_drain_ramp = 0.0
		# No passive energy regen in battle — the boost pool only refills from
		# specific recharge sources (energy pickups, support allies, etc.).


func process_drop_tanks(delta: float) -> void:
	if not _drop_tank_active:
		return
	if _drop_tank_detonating:
		_drop_tank_timer -= delta
		if _drop_tank_timer <= 0.0:
			_drop_tank_explode()
		return


func apply_drop_tank_damage(amount: float) -> void:
	if not _drop_tank_active or _drop_tank_detonating:
		return
	_drop_tank_hp -= amount
	var parent = get_parent()
	if parent:
		var dtv = parent.get_node_or_null("DropTankVisuals")
		if dtv and dtv.has_method("on_drop_tank_damaged"):
			dtv.on_drop_tank_damaged()
	if _drop_tank_hp <= 0.0:
		_drop_tank_detonating = true
		_drop_tank_timer = DROP_TANK_DET_DELAY
		if AudioManager:
			AudioManager.play_mecha_actuator(get_parent().global_position if get_parent() else Vector3.ZERO)


func purge_drop_tanks() -> void:
	if not _drop_tank_active:
		return
	var parent = get_parent()
	var pos: Vector3 = parent.global_position if parent else Vector3.ZERO
	var tank_fuel := GlobalData.fuel.drop_tank_fuel
	energy = maxf(energy - tank_fuel, 0.0)
	max_energy -= tank_fuel
	_drop_tank_active = false
	_drop_tank_hp = 0.0
	_drop_tank_detonating = false
	_drop_tank_timer = 0.0
	GlobalData.fuel.drop_tanks_attached = 0
	GlobalData.fuel.drop_tank_fuel = 0.0
	if parent:
		var dtv = parent.get_node_or_null("DropTankVisuals")
		if dtv and dtv.has_method("on_drop_tank_purged"):
			dtv.on_drop_tank_purged()
	EffectFactory.spawn_flash(get_tree(), pos + Vector3(0, 1.0, 0),
		Color(0.4, 0.7, 1.0), 0.6, 0.3, 4.0, false, 3.0)
	if AudioManager:
		AudioManager.play_mecha_actuator(pos)


func _drop_tank_explode() -> void:
	var parent = get_parent()
	var pos: Vector3 = parent.global_position if parent else Vector3.ZERO
	_drop_tank_active = false
	_drop_tank_detonating = false
	_drop_tank_timer = 0.0
	var tank_fuel := GlobalData.fuel.drop_tank_fuel
	energy = maxf(energy - tank_fuel, 0.0)
	max_energy -= tank_fuel
	GlobalData.fuel.drop_tanks_attached = 0
	GlobalData.fuel.drop_tank_fuel = 0.0
	if parent:
		var dtv = parent.get_node_or_null("DropTankVisuals")
		if dtv and dtv.has_method("on_drop_tank_destroyed"):
			dtv.on_drop_tank_destroyed()
		if dtv and dtv.has_method("_clear_tanks"):
			dtv._clear_tanks()
		var hs = parent.get_node_or_null("HealthSystem")
		if hs and hs.has_method("take_damage"):
			hs.take_damage(GlobalData.DROP_TANK_PURGE_DAMAGE, "explosive")
	if AudioManager:
		AudioManager.play_mecha_hit(pos)
	for i in range(4):
		var offset := Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 1.5), randf_range(-1.0, 1.0))
		EffectFactory.spawn_box_spark(get_tree(), pos + offset,
			Vector3(0.8, 0.3, 0.8), Color(1.0, 0.6, 0.1), 0.4, 6.0)


func stop_roller_audio() -> void:
	if AudioManager:
		AudioManager.stop_roller_dash()
