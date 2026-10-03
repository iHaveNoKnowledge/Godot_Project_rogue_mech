extends Node3D

const PartPenaltySystem = preload("res://scripts/systems/part_penalty_system.gd")

signal weapon_switched(hand: String, weapon_name: String)
signal ammo_changed(hand: String, current: int, max_ammo: int)
signal reload_progress(hand: String, partial_text: String, reserve_ammo: int, percent: float)
signal reload_failed(hand: String, reason: String)
signal carry_updated(carry_list: Array)
signal weapon_dropped(hand: String, weapon: WeaponPart)
signal heat_changed(hand: String, current: float, max_heat: float, overheated: bool)
signal shoulder_ammo_changed(side: String, current: int, max_ammo: int)
signal shoulder_heat_changed(side: String, current: float, max_heat: float, overheated: bool)
signal shoulder_switched(side: String, weapon_name: String)
# Fired when a melee swing actually connects (damage applied). The HUD listens
# for it to flash the screen edge as impact feedback.
signal melee_hit_landed

# --- Pile bunker hit-stop ---
# A freeze-frame when the pile bunker connects: the whole game briefly runs at
# near-zero Engine.time_scale so the impact lands with weight. Restored by a
# SceneTreeTimer that ignores time_scale (real-time countdown), so the freeze
# always ends even at scale ~0.
const PILE_HITSTOP_SCALE: float = 0.05
const PILE_HITSTOP_DURATION: float = 0.1
var _hitstop_timer: SceneTreeTimer = null

# --- Slots ---
var left_hand: WeaponPart = null
var right_hand: WeaponPart = null
var shoulder_left: WeaponPart = null
var shoulder_right: WeaponPart = null
var carry: Array[WeaponPart] = []
const MissileLockOnSystemClass = preload("res://scripts/systems/missile_lock_on_system.gd")
var missile_lock_system: Node = null

# --- Ammo ---
# Ammo brought into this battle from the Hangar loadout. Reload consumes from
# this local pool (NOT the persistent stash) so "how much ammo you carry" is the
# ammo loadout choice. Leftover ammo returns to the stash when combat ends.
var battle_reserve: Dictionary = {}

# --- Firing cores ---
# Each equipped weapon runs through a WeaponCore (cached by weapon name so a
# swapped weapon keeps its ammo/heat/cooldown). Cooldown, ammo and heat live in
# the core; the manager only adds input, aim and presentation.
var _cores: Dictionary = {}

func instant_reload_all() -> void:
	for core in _cores.values():
		if core is WeaponCore:
			core.ammo = core.max_ammo
			core.reloading = false
			core.reload_timer = 0.0
			core.heat = 0.0
			core.overheated = false
			core.ammo_changed.emit(core.ammo, core.max_ammo)
			core.heat_changed.emit(0.0, core.heat_capacity, false)

# --- Input State ---
var holding_left: bool = false
var holding_right: bool = false
var fire_left_holding: bool = false
var fire_right_holding: bool = false
var fire_shoulder_left_holding: bool = false
var fire_shoulder_right_holding: bool = false
var holding_reload: bool = false
var reloading_left: bool = false
var reloading_right: bool = false
var reloading_shoulder_left: bool = false
var reloading_shoulder_right: bool = false
var _hold_time_left: float = 0.0
var _hold_time_right: float = 0.0
# Per-slot trigger discipline (AUTO/SEMI/BURST from the gun's own data).
var trigger_left := TriggerState.new()
var trigger_right := TriggerState.new()
var trigger_shoulder_left := TriggerState.new()
var trigger_shoulder_right := TriggerState.new()

# --- Shield State ---
# Shields are PHYSICAL plates held on one arm (no energy barrier, no
# regeneration): while raised they fully block attacks and drain their own HP
# — 40% cost against the plate's own damage type, 100% against the other two
# (see absorb_damage_with_shield). A broken plate stays broken for the battle.
var shield_active: bool = false
var shield_current_hp: float = 0.0
var shield_max_hp: float = 0.0
# The exact plate the current HP belongs to (the WeaponPart resource armed in
# the hand). Re-raising the same broken plate stays broken; swapping in a
# different plate treats it as fresh.
var _armed_shield: WeaponPart = null

# --- Weapon Scroll State (per hand) ---
var _selecting_left: bool = false
var _selecting_right: bool = false
var _select_idx_left: int = 0
var _select_idx_right: int = 0
var _select_scrolled_left: bool = false
var _select_scrolled_right: bool = false
var _tap_time_left: float = 0.0
var _tap_time_right: float = 0.0
const TAP_THRESHOLD: float = 0.25

# --- Default Weapons (used only when GlobalData has nothing equipped) ---
var default_left: WeaponPart = preload("res://resources/mech/stock/weapon_beam_rifle.tres")
var default_right: WeaponPart = preload("res://resources/mech/stock/weapon_heat_blade.tres")

# --- Bare-fist unarmed melee (used when a hand is empty) ---
const FIST_DAMAGE: float = 8.0
const FIST_FIRE_INTERVAL: float = 0.5
const FIST_IMPACT: float = 2.0

# Per-model damage multiplier from the loadout instances' upgrade levels
# (1.0 + 10% per tier step). Built at battle start from the loadout refs so an
# upgraded weapon hits harder; picked-up / swapped weapons default to 1.0.
var _damage_mult_by_name: Dictionary = {}


# A melee swing's arm/weapon extension at the thrust peak (the mech body
# occupies ~1.5m and the fist/blade reaches out the rest). The lunge carries the
# mech the remainder, so lunge + reach == the weapon's range_distance exactly:
# the thrust visual and the hit check agree at every distance.
# Standard reference value; live geometry resolves per frame through
# FrameVariantResolver.melee_hit_reach_for() (longer arms reach further and
# lunge less). Do not retune here without touching the resolver contract.
const MELEE_HIT_REACH: float = 1.6

# Lateral auto-aim width of a melee swing. An enemy mech's body is ~1m wide, so
# an off-center enemy whose body fills the crosshair must still connect even
# though its CENTER is off the aim line (center-based checks miss it). The swing
# catches any enemy within this distance of the aim line, up to the weapon's
# forward reach.
const MELEE_AUTO_AIM_WIDTH: float = 1.2

# Shoulder bash: the fallback melee a mech still has when its arm frame is
# destroyed (the arm is gone, but the shoulder can still ram the enemy). Press
# fire on a broken side to bash with that shoulder.
const SHOULDER_DAMAGE: float = 12.0

# Active special capability activation / charge sessions (ActivationTimingSystem)
var _active_timing_sessions: Array = []
var telegraph_presentation: Node3D = null

# A dual melee charge: pressing BOTH fire buttons together (within the window)
# when both sides fight melee (weapon, fist or shoulder) lunges the mech deep
# toward the target for a heavy combined hit instead of two separate swings.
const DUAL_PRESS_WINDOW_MS: int = 120

var _shoulder_weapon: WeaponPart = null
var _charge_weapon: WeaponPart = null
var _last_left_press_ms: int = 0
var _last_right_press_ms: int = 0

# A melee fire press held back while watching for the second button of a dual
# charge (see _fire_press / _commit_normal_fire). Cleared when the window
# expires (normal fire) or the other button arrives (charge).
var _pending_fire: String = ""
var _pending_fire_ms: int = 0

# A melee swing whose damage waits for the animation's strike moment instead
# of landing on the input frame. Set by _melee_attack (swing start: facing,
# lunge, trail, swing SFX all stay immediate), executed once per strike via
# poll_strike() below, cleared on completion. Restarting the swing (combo
# chain) overwrites it, so a retired swing can never deal a late hit:
# 1 input = 1 lifecycle = strikes of THIS swing only.
var _pending_melee: Dictionary = {}

var _fist_weapon: WeaponPart = null

# Heat smoke timers — throttles 3D smoke puffs rising from hot barrels
var _heat_smoke_timer_left: float = 0.0
var _heat_smoke_timer_right: float = 0.0
var _heat_smoke_timer_shoulder_left: float = 0.0
var _heat_smoke_timer_shoulder_right: float = 0.0


# How far a melee swing carries the mech toward the target, matched to the
# weapon's range_distance (lunge = range - arm reach, floored at 0.9):
#   fist 4.5 -> 2.9   knife 4.2 -> 2.6   heat blade 5.2 -> 3.6   mace 5.0 -> 3.4   pile 6.0 -> 4.4
# Arm reach is variant-resolved (longer arms reach further, so the mech
# lunges less); Standard resolves exactly MELEE_HIT_REACH.
func _melee_lunge_dist(weapon: WeaponPart) -> float:
	if weapon == null or weapon.range_distance <= 0.0:
		return 2.9
	return maxf(weapon.range_distance - FrameVariantResolver.melee_hit_reach_for(get_parent()), 0.9)

# Synthetic unarmed-melee weapon: an empty hand still fights with a punch. It is
# a real MELEE WeaponPart (no ammo, no heat) so it flows through the same
# WeaponCore cooldown and melee-hit pipeline as the heat blade.
func _fist() -> WeaponPart:
	if _fist_weapon == null:
		_fist_weapon = WeaponPart.new()
		_fist_weapon.weapon_name = "Bare Fist"
		_fist_weapon.weapon_type = WeaponPart.WeaponType.MELEE
		_fist_weapon.range_distance = 4.5
		_fist_weapon.damage = 18.0
		_fist_weapon.damage = FIST_DAMAGE
		_fist_weapon.fire_rate = FIST_FIRE_INTERVAL
		_fist_weapon.impact = FIST_IMPACT
		_fist_weapon.max_ammo = 0
		_fist_weapon.ammo_per_shot = 0
		_fist_weapon.range_distance = 3.0
	return _fist_weapon


func _ready() -> void:
	# Load the equipped loadout from the Hangar (GlobalData.weapons.weapon_loadout) so the
	# battle mech carries the SAME weapons (hands + back) that were configured in the garage.
	# An empty hand slot in the loadout means "unarmed" — kept as null.
	left_hand = LoadoutSystem.get_equipped_weapon("left")
	right_hand = LoadoutSystem.get_equipped_weapon("right")
	shoulder_left = LoadoutSystem.get_equipped_shoulder("left")
	shoulder_right = LoadoutSystem.get_equipped_shoulder("right")
	carry = LoadoutSystem.get_carry_weapons()
	print("[LOADOUT] battle ready: refs=(%s,%s,carry=%s) resolved_hands=(%s,%s) carry=%d" % [
		str(GlobalData.weapons.weapon_loadout.get("left", "")),
		str(GlobalData.weapons.weapon_loadout.get("right", "")),
		str(GlobalData.weapons.weapon_loadout.get("carry", [])),
		"null" if left_hand == null else left_hand.resource_path,
		"null" if right_hand == null else right_hand.resource_path,
		carry.size()])
	# Battle reserve = the ammo the player chose to carry in the loadout.
	# Deduct that from the persistent stash now (what you fire is spent); any
	# leftover returns to the stash when combat ends.
	battle_reserve = LoadoutSystem.get_loadout_ammo_dict()
	# Per-model upgrade multipliers from the loadout instances (hands + shoulders + pack).
	_register_damage_mult(GlobalData.weapons.weapon_loadout.get("left", ""))
	_register_damage_mult(GlobalData.weapons.weapon_loadout.get("right", ""))
	_register_damage_mult(GlobalData.weapons.weapon_loadout.get("shoulder_left", ""))
	_register_damage_mult(GlobalData.weapons.weapon_loadout.get("shoulder_right", ""))
	var carry_refs = GlobalData.weapons.weapon_loadout.get("carry", [])
	if carry_refs is Array:
		for ref in carry_refs:
			_register_damage_mult(ref)
	for ammo_type in battle_reserve:
		var amount: int = battle_reserve[ammo_type]
		if amount > 0:
			LoadoutSystem.consume_reserve_ammo(ammo_type, amount)
	EventBus.combat_ended.connect(_on_combat_ended)
	missile_lock_system = MissileLockOnSystemClass.new()
	missile_lock_system.name = "MissileLockOnSystem"
	missile_lock_system.weapon_manager = self
	add_child(missile_lock_system)

	var telegraph_cls = load("res://scripts/effects/telegraph_presentation.gd")
	if telegraph_cls:
		telegraph_presentation = telegraph_cls.new()
		telegraph_presentation.name = "TelegraphPresentation"
		telegraph_presentation.weapon_manager = self
		add_child(telegraph_presentation)

	call_deferred("_emit_initial_state")


func _on_combat_ended(_victory: bool) -> void:
	# Return any unused carried ammo to the persistent stash so nothing is lost.
	for ammo_type in battle_reserve:
		var amount: int = battle_reserve[ammo_type]
		if amount > 0:
			LoadoutSystem.add_reserve_ammo(ammo_type, amount)
	battle_reserve.clear()

	# If mid-selection, cancel selection state and restore weapon in hand so hands are never left empty
	if _selecting_left or _selecting_right:
		_selecting_left = false
		_selecting_right = false
		holding_left = false
		holding_right = false
		if left_hand == null and not carry.is_empty():
			left_hand = carry.pop_front()
		if right_hand == null and not carry.is_empty():
			right_hand = carry.pop_front()
		_enforce_two_hand_grip()
		_update_weapon_visuals()

	sync_loadout_to_global()
	HangarManager.save_active()


func _get_weapon_path(w: WeaponPart) -> String:
	if w == null:
		return ""
	if not w.resource_path.is_empty():
		return w.resource_path
	if "source_path" in w and not str(w.source_path).is_empty():
		return str(w.source_path)
	return ""

# Writes the current hands + shoulders + back-carry back into GlobalData.weapons.weapon_loadout so
# in-battle pickups and swaps survive into the next battle. Runs at combat end
# (and after each commit/drop) since return_to_board() -> save_run() only saves
# the state GlobalData holds at that moment.
func sync_loadout_to_global() -> void:
	# Hands/shoulders/back are written back by INSTANCE uid (the copy that entered the
	# battle keeps its identity) so the hangar [E] badge stays per-instance.
	var _pre_l := str(GlobalData.weapons.weapon_loadout.get("left", ""))
	var _pre_r := str(GlobalData.weapons.weapon_loadout.get("right", ""))
	var _pre_c: Array = GlobalData.weapons.weapon_loadout.get("carry", [])
	LoadoutSystem.set_hand_weapon("left", LoadoutSystem.resolve_hand_uid_for_sync("left", _get_weapon_path(left_hand)))
	LoadoutSystem.set_hand_weapon("right", LoadoutSystem.resolve_hand_uid_for_sync("right", _get_weapon_path(right_hand)))
	LoadoutSystem.set_shoulder_weapon("left", LoadoutSystem.resolve_shoulder_uid_for_sync("left", _get_weapon_path(shoulder_left)))
	LoadoutSystem.set_shoulder_weapon("right", LoadoutSystem.resolve_shoulder_uid_for_sync("right", _get_weapon_path(shoulder_right)))
	var carry_paths: Array = []
	for weapon in carry:
		if weapon:
			carry_paths.append(_get_weapon_path(weapon))
	GlobalData.weapons.weapon_loadout["carry"] = LoadoutSystem.resolve_carry_uids_for_sync(carry_paths)

	# [LOADOUT] wipe tracer: pinpoints the exact sync that empties a slot that
	# was filled before (live hands null with no drop, unexpected clear, ...).
	var _post_l := str(GlobalData.weapons.weapon_loadout.get("left", ""))
	var _post_r := str(GlobalData.weapons.weapon_loadout.get("right", ""))
	var _post_c: Array = GlobalData.weapons.weapon_loadout.get("carry", [])
	if (_pre_l != "" and _post_l == "") or (_pre_r != "" and _post_r == ""):
		print("[LOADOUT] slot emptied by sync: pre=(%s,%s) live_hands=(%s,%s) live_carry=%d post=(%s,%s)" % [
			_pre_l, _pre_r,
			"null" if left_hand == null else left_hand.resource_path,
			"null" if right_hand == null else right_hand.resource_path,
			carry.size(), _post_l, _post_r])
	if _pre_c is Array and not (_pre_c as Array).is_empty() and (_post_c is Array and (_post_c as Array).is_empty()):
		print("[LOADOUT] carry emptied by sync: pre=%s live_carry=%d" % [str(_pre_c), carry.size()])
	# The mech's total weight now includes the loadout weapons, so a pickup/drop
	# must re-trigger the live weight calculation (speed/turn) right away.
	EventBus.weight_changed.emit(0.0)


# Records the upgrade-based damage multiplier for one loadout ref (uid).
func _register_damage_mult(ref) -> void:
	var inst := LoadoutSystem.get_weapon_instance(str(ref))
	if inst.is_empty():
		return
	var path := str(inst.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return
	var res = load(path)
	if res == null or not ("weapon_name" in res):
		return
	var upg := int(inst.get("upgrade_level", 1))
	_damage_mult_by_name[str(res.weapon_name)] = 1.0 + 0.10 * float(maxi(upg - 1, 0))


# Damage multiplier for the weapon in a slot (1.0 when unarmed
# or the model has no upgrade bonus).
func _slot_damage_mult(slot: String) -> float:
	var weapon := _get_weapon_for_slot(slot)
	if weapon == null:
		return 1.0
	return float(_damage_mult_by_name.get(weapon.weapon_name, 1.0))


func _hand_damage_mult(hand: String) -> float:
	return _slot_damage_mult(hand)


func _get_weapon_for_slot(slot: String) -> WeaponPart:
	match slot:
		"left": return left_hand
		"right": return right_hand
		"shoulder_left", "left_shoulder": return shoulder_left
		"shoulder_right", "right_shoulder": return shoulder_right
		_: return null


func _get_trigger(slot: String) -> TriggerState:
	match slot:
		"left": return trigger_left
		"right": return trigger_right
		"shoulder_left", "left_shoulder": return trigger_shoulder_left
		"shoulder_right", "right_shoulder": return trigger_shoulder_right
		_: return trigger_left


func _is_shoulder_slot(slot: String) -> bool:
	return slot == "shoulder_left" or slot == "shoulder_right" or slot == "left_shoulder" or slot == "right_shoulder"


func _is_reloading(slot: String) -> bool:
	match slot:
		"left": return reloading_left
		"right": return reloading_right
		"shoulder_left", "left_shoulder": return reloading_shoulder_left
		"shoulder_right", "right_shoulder": return reloading_shoulder_right
		_: return false


func _set_reloading(slot: String, val: bool) -> void:
	match slot:
		"left": reloading_left = val
		"right": reloading_right = val
		"shoulder_left", "left_shoulder": reloading_shoulder_left = val
		"shoulder_right", "right_shoulder": reloading_shoulder_right = val


func get_battle_reserve(ammo_type: String) -> int:
	return battle_reserve.get(ammo_type.to_lower(), 0)


func add_battle_reserve(ammo_type: String, amount: int) -> void:
	var type = ammo_type.to_lower()
	if type == "" or type == "none":
		return
	battle_reserve[type] = battle_reserve.get(type, 0) + amount


func consume_battle_reserve(ammo_type: String, amount: int) -> int:
	var type = ammo_type.to_lower()
	var current = battle_reserve.get(type, 0)
	var taken = mini(current, amount)
	battle_reserve[type] = current - taken
	return taken


func _emit_initial_state() -> void:
	_enforce_two_hand_grip()
	if left_hand == null and right_hand == null:
		return
	if left_hand:
		weapon_switched.emit("left", left_hand.weapon_name)
		ammo_changed.emit("left", _get_ammo(left_hand), left_hand.max_ammo)
	if right_hand:
		weapon_switched.emit("right", right_hand.weapon_name)
		ammo_changed.emit("right", _get_ammo(right_hand), right_hand.max_ammo)
	if shoulder_left:
		shoulder_switched.emit("left", shoulder_left.weapon_name)
		shoulder_ammo_changed.emit("left", _get_ammo(shoulder_left), shoulder_left.max_ammo)
	if shoulder_right:
		shoulder_switched.emit("right", shoulder_right.weapon_name)
		shoulder_ammo_changed.emit("right", _get_ammo(shoulder_right), shoulder_right.max_ammo)
	call_deferred("_update_weapon_visuals")
	carry_updated.emit(carry)


func _set_ammo(weapon: WeaponPart, amount: int) -> void:
	if weapon == null:
		return
	var core := _core_for_weapon(weapon)
	if core:
		core.ammo = amount


# Returns the WeaponCore backing a weapon, creating it once per weapon name so a
# swapped-out weapon keeps its ammo/heat/cooldown when re-equipped. The core
# owns cooldown/ammo/heat/reload + projectile spawning; the manager keeps only
# input, aim and presentation.
func _core_for_weapon(weapon: WeaponPart) -> WeaponCore:
	if weapon == null:
		return null
	var key = str(weapon.get_instance_id())
	if not _cores.has(key):
		var core := WeaponCore.from_weapon(weapon)
		core.auto_reload = false
		core.manual_reload = true
		core.ammo_changed.connect(_forward_ammo_changed.bind(key))
		core.heat_changed.connect(_forward_heat_changed.bind(key))
		_cores[key] = core
	return _cores[key]


func _forward_ammo_changed(current: int, max_ammo: int, key: String) -> void:
	var slot = _hand_of_weapon(key)
	if slot == "left" or slot == "right":
		ammo_changed.emit(slot, current, max_ammo)
	elif slot == "shoulder_left":
		shoulder_ammo_changed.emit("left", current, max_ammo)
	elif slot == "shoulder_right":
		shoulder_ammo_changed.emit("right", current, max_ammo)


func _forward_heat_changed(current: float, max_heat: float, overheated: bool, key: String) -> void:
	var slot = _hand_of_weapon(key)
	if slot == "left" or slot == "right":
		heat_changed.emit(slot, current, max_heat, overheated)
	elif slot == "shoulder_left":
		shoulder_heat_changed.emit("left", current, max_heat, overheated)
	elif slot == "shoulder_right":
		shoulder_heat_changed.emit("right", current, max_heat, overheated)


func _hand_of_weapon(key: String) -> String:
	if left_hand and str(left_hand.get_instance_id()) == key:
		return "left"
	if right_hand and str(right_hand.get_instance_id()) == key:
		return "right"
	if shoulder_left and str(shoulder_left.get_instance_id()) == key:
		return "shoulder_left"
	if shoulder_right and str(shoulder_right.get_instance_id()) == key:
		return "shoulder_right"
	return ""


func _physics_process(delta: float) -> void:
	# Tick the firing cores (cooldown + heat cooling + auto reloads). Empty
	# hands tick the shared bare-fist core so its punch cooldown keeps running.
	# The fist core is shared across both hands, so tick it at most once per
	# frame even when both hands are empty (otherwise its cooldown drains 2x).
	if left_hand:
		_core_for_weapon(left_hand).tick(delta)
	if right_hand:
		_core_for_weapon(right_hand).tick(delta)
	# Shoulders run the SAME WeaponCore rules as hands (cooldown/ammo/heat).
	# They must be ticked too — otherwise cooldown never clears (fires once
	# then locks) and heat never cools.
	if shoulder_left:
		_core_for_weapon(shoulder_left).tick(delta)
	if shoulder_right:
		_core_for_weapon(shoulder_right).tick(delta)
	if not left_hand or not right_hand:
		_core_for_weapon(_fist()).tick(delta)

	# Tick active special weapon activation/charge sessions
	var s_idx := _active_timing_sessions.size() - 1
	while s_idx >= 0:
		var session = _active_timing_sessions[s_idx]
		if session and session.has_method("is_preparing") and session.is_preparing():
			session.tick(delta)
		if session == null or not session.has_method("is_preparing") or session.is_completed() or session.is_cancelled():
			_active_timing_sessions.remove_at(s_idx)
		s_idx -= 1

	if telegraph_presentation and is_instance_valid(telegraph_presentation):
		telegraph_presentation.sync_descriptors(get_active_telegraph_descriptors())

	_update_heat_smoke(delta)

	if holding_left:
		_hold_time_left += delta
	if holding_right:
		_hold_time_right += delta

	# A deferred melee press: when the other fire button lands within the
	# window the pair becomes a dual charge (handled by _fire_press on that
	# second press); when the window expires alone, commit as a normal fire.
	if _pending_fire != "":
		var now := Time.get_ticks_msec()
		if now - _pending_fire_ms > DUAL_PRESS_WINDOW_MS:
			var hand := _pending_fire
			_pending_fire = ""
			_commit_normal_fire(hand)

	_process_pending_melee()

	if fire_left_holding:
		if not Input.is_action_pressed("fire_left"):
			fire_left_holding = false
			trigger_left.release()
		else:
			_hold_fire("left", left_hand)
	if fire_right_holding:
		if not Input.is_action_pressed("fire_right"):
			fire_right_holding = false
			trigger_right.release()
		else:
			_hold_fire("right", right_hand)
	if fire_shoulder_left_holding:
		var q_down: bool = Input.is_action_pressed("shoulder_left") or Input.is_key_pressed(KEY_Q)
		if not q_down:
			fire_shoulder_left_holding = false
			trigger_shoulder_left.release()
		else:
			_hold_fire("shoulder_left", shoulder_left)
	if fire_shoulder_right_holding:
		var e_down: bool = Input.is_action_pressed("shoulder_right") or Input.is_key_pressed(KEY_E)
		if not e_down:
			fire_shoulder_right_holding = false
			trigger_shoulder_right.release()
		else:
			_hold_fire("shoulder_right", shoulder_right)

	# Physical shield plates never regenerate — a damaged plate stays damaged.


## One held-frame of trigger discipline for a slot: AUTO sprays, SEMI stays
## silent until the next press, BURST spends its remaining pull. Only shots
## that consumed ammo count down a burst.
func _hold_fire(slot: String, weapon: WeaponPart) -> void:
	var trig := _get_trigger(slot)
	if weapon == null:
		trig.sync(null)
		_try_fire(slot, null)
		return
	if weapon.weapon_type == WeaponPart.WeaponType.SHIELD:
		return
	trig.sync(weapon)
	if not trig.allow_hold_shot():
		return
	var before := _get_ammo(weapon)
	_try_fire(slot, weapon)
	if _get_ammo(weapon) < before:
		trig.on_hold_shot_fired()


## Ammo-diff wrapper for the commit-press immediate shot: arms the trigger
## (BURST loads its count) and counts the press shot when it consumed ammo.
func _commit_fire(slot: String, weapon: WeaponPart) -> void:
	var trig := _get_trigger(slot)
	if weapon == null:
		trig.sync(null)
		_try_fire(slot, null)
		return
	trig.sync(weapon)
	trig.press()
	var before := _get_ammo(weapon)
	_try_fire(slot, weapon)
	if _get_ammo(weapon) < before:
		trig.on_hold_shot_fired()


func _update_heat_smoke(delta: float) -> void:
	for hand in ["left", "right"]:
		var weapon: WeaponPart = left_hand if hand == "left" else right_hand
		if weapon == null or not weapon.uses_heat():
			continue
		var core := _core_for_weapon(weapon)
		if core == null or core.heat_capacity <= 0.0:
			continue
		var ratio: float = clampf(core.heat / core.heat_capacity, 0.0, 1.0)
		if ratio < 0.35:
			continue
		var timer: float = _heat_smoke_timer_left if hand == "left" else _heat_smoke_timer_right
		timer -= delta
		# More frequent smoke as it gets hotter
		var interval: float = lerp(0.45, 0.12, (ratio - 0.35) / 0.65)
		if timer > 0.0:
			if hand == "left":
				_heat_smoke_timer_left = timer
			else:
				_heat_smoke_timer_right = timer
			continue
		if hand == "left":
			_heat_smoke_timer_left = interval
		else:
			_heat_smoke_timer_right = interval
		var muzzle: Vector3 = _get_muzzle_world_pos(hand)
		if muzzle == Vector3.INF:
			var mecha := get_parent() as Node3D
			if mecha == null:
				continue
			var side := "left" if hand == "left" else "right"
			muzzle = mecha.global_position + mecha.global_transform.basis * FrameVariantResolver.hand_fallback_for(mecha, side)
		# Smoke color: light grey at 35-60%heat, orange-grey when overheated
		var is_overheated: bool = core.overheated
		if is_overheated:
			# Overheated: thick dark smoke + small ember
			EffectFactory.spawn_smoke_plume(get_tree(), muzzle + Vector3(0,0.12,0), 3, 0.20, 0.40, 0.95)
			EffectManager.spawn_hit_spark(muzzle + Vector3(0,0.10,0), Vector3.UP, "heat")
		elif ratio > 0.65:
			EffectFactory.spawn_smoke_plume(get_tree(), muzzle + Vector3(0,0.08,0), 1, 0.14, 0.28, 0.7)
		else:
			EffectFactory.spawn_smoke_plume(get_tree(), muzzle + Vector3(0,0.06,0), 1, 0.10, 0.22, 0.55)
	for side in ["left", "right"]:
		var sweapon: WeaponPart = shoulder_left if side == "left" else shoulder_right
		if sweapon == null or not sweapon.uses_heat():
			continue
		var score := _core_for_weapon(sweapon)
		if score == null or score.heat_capacity <= 0.0:
			continue
		var sratio: float = clampf(score.heat / score.heat_capacity, 0.0, 1.0)
		if sratio < 0.35:
			continue
		var stimer: float = _heat_smoke_timer_shoulder_left if side == "left" else _heat_smoke_timer_shoulder_right
		stimer -= delta
		var sinterval: float = lerp(0.45, 0.12, (sratio - 0.35) / 0.65)
		if stimer > 0.0:
			if side == "left":
				_heat_smoke_timer_shoulder_left = stimer
			else:
				_heat_smoke_timer_shoulder_right = stimer
			continue
		if side == "left":
			_heat_smoke_timer_shoulder_left = sinterval
		else:
			_heat_smoke_timer_shoulder_right = sinterval
		var smuzzle: Vector3 = _get_shoulder_muzzle_world_pos(side)
		if smuzzle == Vector3.INF:
			var smecha := get_parent() as Node3D
			if smecha == null:
				continue
			smuzzle = smecha.global_position + smecha.global_transform.basis * FrameVariantResolver.shoulder_fallback_for(smecha, side)
		if score.overheated:
			EffectFactory.spawn_smoke_plume(get_tree(), smuzzle + Vector3(0,0.12,0), 3, 0.20, 0.40, 0.95)
			EffectManager.spawn_hit_spark(smuzzle + Vector3(0,0.10,0), Vector3.UP, "heat")
		elif sratio > 0.65:
			EffectFactory.spawn_smoke_plume(get_tree(), smuzzle + Vector3(0,0.08,0), 1, 0.14, 0.28, 0.7)
		else:
			EffectFactory.spawn_smoke_plume(get_tree(), smuzzle + Vector3(0,0.06,0), 1, 0.10, 0.22, 0.55)


# ====================================================================
# INPUT
# ====================================================================

func _input(event: InputEvent) -> void:
	# While any UI modal (Field Loot, Pause Menu, Tab Menu) has the mouse free, ignore weapon firing & weapon swaps
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	# The mech is ragdolled in its core-breach death window: the weapons are
	# dead (only the eject seat still works), so ignore every weapon input.
	var mecha = get_parent()
	if mecha != null:
		var hs = mecha.get_node_or_null("HealthSystem")
		if hs != null and bool(hs.get("is_destroyed")):
			return
	# The pilot has LEFT the mech: fire buttons belong to the pilot's own body
	# weapons, not the parked mech's loadout.
	if GameManager.current_state == GameManager.State.EJECT:
		return
	# --- LEFT HAND SWAP (key 1) ---
	if event.is_action_pressed("weapon_left"):
		if _hand_usable("left"):
			_start_selection("left")
		# A destroyed arm cannot swap/drop weapons — there is no hand to grip.
	if event.is_action_released("weapon_left"):
		_commit_selection("left")

	# --- RIGHT HAND SWAP (key 3) ---
	if event.is_action_pressed("weapon_right"):
		if _hand_usable("right"):
			_start_selection("right")
		# A destroyed arm cannot swap/drop weapons — there is no hand to grip.
	if event.is_action_released("weapon_right"):
		_commit_selection("right")

	# --- DROP (key X) ---
	if event.is_action_pressed("weapon_drop"):
		if holding_left:
			_drop_weapon_from_selection("left")
		elif holding_right:
			_drop_weapon_from_selection("right")
		else:
			if right_hand:
				_drop_equipped_weapon("right")
			elif left_hand:
				_drop_equipped_weapon("left")

	# --- SCROLL while selecting ---
	if event is InputEventMouseButton and event.pressed:
		var dir = 0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dir = -1 # up = lower index
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dir = 1 # down = higher index
		if dir != 0:
			if holding_left:
				_scroll("left", dir)
			elif holding_right:
				_scroll("right", dir)

	# --- RELOAD (key R) ---
	if event.is_action_pressed("reload"):
		holding_reload = true
	if event.is_action_released("reload"):
		holding_reload = false

	# --- FIRE / RELOAD LEFT ---
	if event.is_action_pressed("fire_left"):
		if _is_missile_weapon(left_hand) and not holding_reload and not Input.is_action_pressed("reload"):
			var core = _core_for_weapon(left_hand)
			var ammo_cnt: int = core.ammo if core else (left_hand.max_ammo if left_hand else 0)
			if missile_lock_system:
				missile_lock_system.start_locking("left", left_hand, ammo_cnt)
		else:
			if _fire_press("left"):
				return  # deferred for a possible dual charge, or consumed
			_commit_normal_fire("left")
	if event.is_action_released("fire_left"):
		fire_left_holding = false
		trigger_left.release()
		if _is_missile_weapon(left_hand):
			_handle_missile_release("left")

	# --- FIRE / RELOAD RIGHT ---
	if event.is_action_pressed("fire_right"):
		if _is_missile_weapon(right_hand) and not holding_reload and not Input.is_action_pressed("reload"):
			var core = _core_for_weapon(right_hand)
			var ammo_cnt: int = core.ammo if core else (right_hand.max_ammo if right_hand else 0)
			if missile_lock_system:
				missile_lock_system.start_locking("right", right_hand, ammo_cnt)
		else:
			if _fire_press("right"):
				return  # deferred for a possible dual charge, or consumed
			_commit_normal_fire("right")
	if event.is_action_released("fire_right"):
		fire_right_holding = false
		trigger_right.release()
		if _is_missile_weapon(right_hand):
			_handle_missile_release("right")

	# --- SHOULDER WEAPONS (Q = left shoulder in normal mode / E = right shoulder) ---
	var q_pressed: bool = event.is_action_pressed("shoulder_left") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q)
	var q_released: bool = event.is_action_released("shoulder_left") or (event is InputEventKey and not event.pressed and event.keycode == KEY_Q)
	var e_pressed: bool = event.is_action_pressed("shoulder_right") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E)
	var e_released: bool = event.is_action_released("shoulder_right") or (event is InputEventKey and not event.pressed and event.keycode == KEY_E)

	if q_pressed:
		if not _is_close_combat_mode():
			if holding_reload or Input.is_action_pressed("reload"):
				reload_weapon("shoulder_left")
			elif _is_missile_weapon(shoulder_left):
				var core = _core_for_weapon(shoulder_left)
				var ammo_cnt: int = core.ammo if core else (shoulder_left.max_ammo if shoulder_left else 0)
				if missile_lock_system:
					missile_lock_system.start_locking("shoulder_left", shoulder_left, ammo_cnt)
			else:
				fire_shoulder_left_holding = true
				_commit_fire("shoulder_left", shoulder_left)
	if q_released:
		fire_shoulder_left_holding = false
		trigger_shoulder_left.release()
		if _is_missile_weapon(shoulder_left):
			_handle_missile_release("shoulder_left")

	if e_pressed:
		if holding_reload or Input.is_action_pressed("reload"):
			reload_weapon("shoulder_right")
		elif _is_missile_weapon(shoulder_right):
			var core = _core_for_weapon(shoulder_right)
			var ammo_cnt: int = core.ammo if core else (shoulder_right.max_ammo if shoulder_right else 0)
			if missile_lock_system:
				missile_lock_system.start_locking("shoulder_right", shoulder_right, ammo_cnt)
		else:
			fire_shoulder_right_holding = true
			_commit_fire("shoulder_right", shoulder_right)
	if e_released:
		fire_shoulder_right_holding = false
		trigger_shoulder_right.release()
		if _is_missile_weapon(shoulder_right):
			_handle_missile_release("shoulder_right")


func reload_weapon(slot: String) -> void:
	if _is_reloading(slot):
		return

	var weapon: WeaponPart = _get_weapon_for_slot(slot)
	if weapon == null:
		_emit_reload_failed(slot, "NO WEAPON")
		return

	var ammo_type = weapon.get_ammo_type()
	if ammo_type == "none":
		_emit_reload_failed(slot, "NO AMMO TYPE")
		return

	var current_mag = _get_ammo(weapon)
	var needed = weapon.max_ammo - current_mag
	if needed <= 0:
		_emit_reload_failed(slot, "FULL")
		_spawn_jam_effect(slot)
		return

	var reserve = get_battle_reserve(ammo_type)
	if reserve <= 0:
		_emit_reload_failed(slot, "NO RESERVE")
		_spawn_jam_effect(slot)
		return

	var reload_amount = mini(needed, reserve)
	_set_reloading(slot, true)

	var reload_time = weapon.reload_time
	var steps = int(reload_time * 10)
	var step_delay = reload_time / float(maxi(steps, 1))

	AudioManager.play_reload_start()

	for i in range(steps):
		await get_tree().create_timer(step_delay).timeout
		if not is_instance_valid(self):
			return
		# Abort reload if the weapon was swapped or dropped mid-reload.
		var current_w = _get_weapon_for_slot(slot)
		if current_w != weapon:
			_set_reloading(slot, false)
			return
		var pct = float(i + 1) / float(steps)
		var partial = int(current_mag + reload_amount * pct)
		_emit_reload_progress(slot, "%d" % partial, reserve, pct)

	var refilled = consume_battle_reserve(ammo_type, reload_amount)
	_set_ammo(weapon, current_mag + refilled)
	_set_reloading(slot, false)

	# Play weapon-specific reload sound if available, otherwise default
	if weapon.sfx_reload and weapon.sfx_reload != "":
		AudioManager.play_sfx_by_name(weapon.sfx_reload, global_position)
	else:
		AudioManager.play_reload_complete()

	_emit_ammo_changed(slot, _get_ammo(weapon), weapon.max_ammo)
	EffectManager.spawn_damage_number(global_position + Vector3(0, 2.5, 0), refilled, Color(0.2, 1.0, 0.4))


func _emit_ammo_changed(slot: String, current: int, max_ammo: int) -> void:
	if slot == "left" or slot == "right":
		ammo_changed.emit(slot, current, max_ammo)
	elif slot == "shoulder_left" or slot == "left_shoulder":
		shoulder_ammo_changed.emit("left", current, max_ammo)
	elif slot == "shoulder_right" or slot == "right_shoulder":
		shoulder_ammo_changed.emit("right", current, max_ammo)


func _emit_reload_progress(slot: String, partial_text: String, reserve_ammo: int, percent: float) -> void:
	var hand := "left" if (slot == "left" or slot == "shoulder_left" or slot == "left_shoulder") else "right"
	reload_progress.emit(slot, partial_text, reserve_ammo, percent)
	if slot != hand:
		reload_progress.emit(hand, partial_text, reserve_ammo, percent)


func _emit_reload_failed(slot: String, reason: String) -> void:
	var hand := "left" if (slot == "left" or slot == "shoulder_left" or slot == "left_shoulder") else "right"
	reload_failed.emit(slot, reason)
	if slot != hand:
		reload_failed.emit(hand, reason)


# Spawns a small spark + smoke burst at the weapon barrel when reload fails.
# Anchored at the mounted model's Muzzle marker when available (mirrors the
# fire path), falling back to the mount offset.
func _spawn_jam_effect(slot: String) -> void:
	var mecha = get_parent()
	if mecha == null:
		return
	var jam_pos := get_muzzle_world_pos(slot)
	if jam_pos == Vector3.INF:
		if _is_shoulder_slot(slot):
			var side := "left" if (slot == "shoulder_left" or slot == "left_shoulder") else "right"
			jam_pos = mecha.global_position + mecha.global_transform.basis * FrameVariantResolver.shoulder_fallback_for(mecha, side)
		else:
			# Jam sparks bloom at the receiver/breach (close-forward), a
			# distinct presentation point from the fire-path muzzle fallback:
			# intentionally frame-independent, left byte-identical.
			var offset := Vector3(-0.6, 1.5, 0.5) if slot == "left" else Vector3(0.6, 1.5, 0.5)
			jam_pos = mecha.global_position + mecha.global_transform.basis * offset + Vector3(0, 0.3, 0)
	EffectManager.spawn_jam_sparks(jam_pos)


func get_muzzle_world_pos(slot: String) -> Vector3:
	if slot == "left" or slot == "right":
		return _get_muzzle_world_pos(slot)
	elif slot == "shoulder_left" or slot == "shoulder_right" or slot == "left_shoulder" or slot == "right_shoulder":
		var side := "left" if (slot == "shoulder_left" or slot == "left_shoulder") else "right"
		return _get_shoulder_muzzle_world_pos(side)
	return Vector3.INF


# World-space position of the weapon model's barrel-tip Muzzle marker for a
# hand. The marker is placed per weapon type by WeaponVisualFactory.build(), so
# every model fires from its own muzzle. Returns Vector3.INF when nothing is
# mounted there (bare fist / destroyed arm) and callers fall back to hip offsets.
func _get_muzzle_world_pos(hand: String) -> Vector3:
	var mecha = get_parent() as Node3D
	if mecha == null or not mecha.is_inside_tree():
		return Vector3.INF
	var side := "Left" if hand == "left" else "Right"
	var mount := mecha.get_node_or_null("Arm%s/Forearm%s/WeaponMesh_%s" % [side, side, hand])
	if mount == null or not is_instance_valid(mount):
		mount = mecha.get_node_or_null("WeaponMesh_" + hand)  # legacy root mount
	if mount == null or not is_instance_valid(mount):
		return Vector3.INF
	var muzzle := WeaponVisualFactory.find_muzzle_node(mount)
	if muzzle == null or not is_instance_valid(muzzle):
		return Vector3.INF
	return muzzle.global_position


func _get_shoulder_muzzle_world_pos(side: String) -> Vector3:
	var mecha = get_parent() as Node3D
	if mecha == null or not mecha.is_inside_tree():
		return Vector3.INF
	var side_cap := "Left" if side == "left" else "Right"
	var mount := mecha.get_node_or_null("Arm%s/ShoulderMesh_%s" % [side_cap, side])
	if mount == null or not is_instance_valid(mount):
		mount = mecha.get_node_or_null("ShoulderMesh_" + side)  # legacy root mount
	if mount == null or not is_instance_valid(mount):
		return Vector3.INF
	var muzzle := WeaponVisualFactory.find_muzzle_node(mount)
	if muzzle != null and is_instance_valid(muzzle):
		return muzzle.global_position
	return mount.global_position


# ====================================================================
# WEAPON SELECTION (1/3 + scroll)
# ====================================================================

func _is_close_combat_mode() -> bool:
	var mecha = get_parent()
	if mecha:
		var combat = mecha.get_node_or_null("CombatSystem")
		if combat == null:
			combat = mecha.get_node_or_null("MechaCombat")
		if combat and combat.has_method("is_close_combat"):
			return bool(combat.is_close_combat())
	return false


func _start_selection(hand: String) -> void:
	# A destroyed arm cannot swap weapons — there is no hand to grip the next
	# one. Blocked here (not just in _input) so every caller is covered.
	if not _hand_usable(hand):
		return
	var is_left = (hand == "left")

	if is_left:
		_hold_time_left = 0.0
		_tap_time_left = 0.0
	else:
		_hold_time_right = 0.0
		_tap_time_right = 0.0

	var hw = left_hand if is_left else right_hand
	if hw:
		carry.insert(0, hw)

	if _is_close_combat_mode():
		# In Close Combat Mode, prioritize Melee weapons
		carry.sort_custom(func(a: WeaponPart, b: WeaponPart):
			var a_m = (a != null and a.weapon_type == WeaponPart.WeaponType.MELEE)
			var b_m = (b != null and b.weapon_type == WeaponPart.WeaponType.MELEE)
			if a_m and not b_m:
				return true
			return false
		)
	else:
		# In Ranged Mode, prioritize Ranged firearms
		carry.sort_custom(func(a: WeaponPart, b: WeaponPart):
			var a_r = (a != null and a.weapon_type != WeaponPart.WeaponType.MELEE)
			var b_r = (b != null and b.weapon_type != WeaponPart.WeaponType.MELEE)
			if a_r and not b_r:
				return true
			return false
		)

	if is_left:
		holding_left = true
		_selecting_left = true
		_select_idx_left = 0
		_select_scrolled_left = false
		left_hand = null
	else:
		holding_right = true
		_selecting_right = true
		_select_idx_right = 0
		_select_scrolled_right = false
		right_hand = null

	carry_updated.emit(carry)
	_update_weapon_visuals()


func _scroll(hand: String, direction: int) -> void:
	var is_left = (hand == "left")
	var idx = _select_idx_left if is_left else _select_idx_right
	var max_idx = carry.size() # Index carry.size() represents BARE FISTS (unarmed)
	var new_idx = clampi(idx + direction, 0, max_idx)

	if new_idx == idx:
		return

	if is_left:
		_select_idx_left = new_idx
		_select_scrolled_left = true
	else:
		_select_idx_right = new_idx
		_select_scrolled_right = true

	# Preview: show highlighted weapon in hand, or bare fists at max_idx
	if new_idx < carry.size():
		var preview = carry[new_idx]
		if is_left:
			left_hand = preview
		else:
			right_hand = preview
		weapon_switched.emit(hand, preview.weapon_name)
		ammo_changed.emit(hand, _get_ammo(preview), preview.max_ammo)
	else:
		if is_left:
			left_hand = null
		else:
			right_hand = null
		weapon_switched.emit(hand, "BARE FIST — punch")
		ammo_changed.emit(hand, 0, 0)

	carry_updated.emit(carry)
	_update_weapon_visuals()


func _commit_selection(hand: String) -> void:
	var is_left = (hand == "left")
	var selecting = _selecting_left if is_left else _selecting_right
	if not selecting:
		return

	var did_scroll = _select_scrolled_left if is_left else _select_scrolled_right
	var idx = _select_idx_left if is_left else _select_idx_right
	var hold_time = _hold_time_left if is_left else _hold_time_right

	if is_left:
		holding_left = false
		_selecting_left = false
	else:
		holding_right = false
		_selecting_right = false

	# Quick tap without scroll → cycle to next weapon from carry
	if not did_scroll and hold_time < TAP_THRESHOLD:
		if not carry.is_empty():
			# The current hand weapon was already inserted at carry[0] in _start_selection.
			# To cycle to the NEXT weapon: rotate the first element to the end and pick the new front.
			var old_weapon = carry.pop_front()
			carry.append(old_weapon)
			var new_weapon = carry.pop_front()
			if is_left:
				left_hand = new_weapon
			else:
				right_hand = new_weapon
		else:
			if is_left:
				left_hand = null
			else:
				right_hand = null

		_enforce_two_hand_grip()
		var w2 = left_hand if is_left else right_hand
		weapon_switched.emit(hand, w2.weapon_name if w2 else "BARE FIST — punch")
		if w2:
			ammo_changed.emit(hand, _get_ammo(w2), w2.max_ammo)
		carry_updated.emit(carry)
		_update_weapon_visuals()
		sync_loadout_to_global()
		return

	# Held selection (with scroll or released on chosen index)
	if idx < carry.size():
		if is_left:
			left_hand = carry[idx]
		else:
			right_hand = carry[idx]
		carry.remove_at(idx)
	else:
		# Index carry.size() selected -> BARE FISTS (hand empty, weapons stored in carry)
		if is_left:
			left_hand = null
		else:
			right_hand = null

	_enforce_two_hand_grip()

	var w = left_hand if is_left else right_hand
	weapon_switched.emit(hand, w.weapon_name if w else "BARE FIST — punch")
	if w:
		ammo_changed.emit(hand, _get_ammo(w), w.max_ammo)
	carry_updated.emit(carry)
	_update_weapon_visuals()
	sync_loadout_to_global()


# ====================================================================
# DROP
# ====================================================================

func _drop_weapon_from_selection(hand: String) -> void:
	var is_left = (hand == "left")
	var idx = _select_idx_left if is_left else _select_idx_right
	if idx < carry.size():
		var weapon: WeaponPart = carry[idx]
		carry.remove_at(idx)
		if is_left:
			left_hand = null
			_select_idx_left = clampi(_select_idx_left, 0, carry.size())
		else:
			right_hand = null
			_select_idx_right = clampi(_select_idx_right, 0, carry.size())

		if weapon:
			weapon_dropped.emit(hand, weapon)
			weapon_switched.emit(hand, "BARE FIST — punch")
			_update_weapon_visuals()
			sync_loadout_to_global()
			carry_updated.emit(carry)


func _drop_equipped_weapon(hand: String) -> void:
	var weapon: WeaponPart = null
	if hand == "left":
		weapon = left_hand
		left_hand = null
	elif hand == "right":
		weapon = right_hand
		right_hand = null
	if weapon:
		weapon_dropped.emit(hand, weapon)
		weapon_switched.emit(hand, "BARE FIST — punch")
		_update_weapon_visuals()
		sync_loadout_to_global()
		carry_updated.emit(carry)


func _drop_weapon(hand: String) -> void:
	if (hand == "left" and holding_left) or (hand == "right" and holding_right):
		_drop_weapon_from_selection(hand)
	else:
		_drop_equipped_weapon(hand)
	sync_loadout_to_global()


# Called by HealthSystem when the arm frame on this hand is destroyed.
# The weapon itself is NOT destroyed (only the frame holding it broke), so it is
# removed from the hand and returned so the caller can spawn a recoverable pickup.
func drop_weapon_from_destroyed_arm(hand: String) -> WeaponPart:
	var weapon: WeaponPart = null
	if hand == "left":
		weapon = left_hand
		left_hand = null
	elif hand == "right":
		weapon = right_hand
		right_hand = null
	if weapon:
		weapon_dropped.emit(hand, weapon)
		weapon_switched.emit(hand, "Empty")
		_update_weapon_visuals()
		sync_loadout_to_global()
	return weapon


# ====================================================================
# WEAPON MANAGEMENT
# ====================================================================

# Weight of weapons physically carried in this battle (back + hands).
func get_battle_field_pack_weight() -> float:
	var total := 0.0
	for w in carry:
		if w:
			total += float(w.weight)
	if left_hand:
		total += float(left_hand.weight)
	if right_hand:
		total += float(right_hand.weight)
	return total


func add_weapon(weapon: WeaponPart) -> bool:
	# Same catalog model = separate physical items: a second pickup of a weapon
	# you already carry adds another copy (hands + back + pack can hold several).
	if weapon == null:
		return false
	var path := weapon.resource_path
	# Registers the weapon in the central stash. Each pickup is its own instance
	# (same-model copies are separate entries), so owning the same weapon twice
	# enables equipping both hands with it.
	LoadoutSystem.register_weapon(path, weapon.weapon_name)
	# The ammo the weapon carries is usable immediately in this battle.
	add_battle_reserve(weapon.get_ammo_type(), weapon.max_ammo)

	carry.append(weapon)
	_core_for_weapon(weapon).ammo = weapon.max_ammo
	carry_updated.emit(carry)
	_update_weapon_visuals()
	sync_loadout_to_global()
	return true


# True when a weapon of this model is already held in a hand or on the back.
func is_weapon_model_carried(path: String) -> bool:
	if path == "":
		return false
	if left_hand and left_hand.resource_path == path:
		return true
	if right_hand and right_hand.resource_path == path:
		return true
	for w in carry:
		if w and w.resource_path == path:
			return true
	return false


func add_ammo(amount: int, hand: String = "", ammo_type: String = "") -> void:
	var target_type = ammo_type
	var target_weapon: WeaponPart = null
	if hand == "left":
		target_weapon = left_hand
	elif hand == "right":
		target_weapon = right_hand
	else:
		target_weapon = left_hand if left_hand else right_hand

	if target_type.is_empty() and target_weapon:
		target_type = target_weapon.get_ammo_type()
	if target_type.is_empty():
		target_type = "bullet"

	# Ammo found mid-battle is added to the local battle reserve so it is usable right away
	add_battle_reserve(target_type, amount)
	# Also persist into GlobalData ammo inventory
	LoadoutSystem.add_reserve_ammo(target_type, amount)

	# If the weapon currently in hand uses this ammo type and magazine has space, top it off directly
	if target_weapon and target_weapon.get_ammo_type() == target_type:
		var cur_mag := _get_ammo(target_weapon)
		var max_mag := target_weapon.max_ammo
		if cur_mag < max_mag:
			var needed := max_mag - cur_mag
			var take := mini(needed, amount)
			consume_battle_reserve(target_type, take)
			_set_ammo(target_weapon, cur_mag + take)
		ammo_changed.emit(hand if not hand.is_empty() else "left", _get_ammo(target_weapon), target_weapon.max_ammo)


# ====================================================================
# FIRING
# ====================================================================

# True when the arm frame on this hand is still intact. A destroyed arm means
# that hand can't fire, reload, or raise its shield — same rule the enemies
# follow.
func _hand_usable(hand: String) -> bool:
	var mecha = get_parent()
	if mecha == null:
		return true
	var hs = mecha.get_node_or_null("HealthSystem")
	if hs == null or not hs.has_method("is_part_destroyed"):
		return true
	return not hs.is_part_destroyed("arm_left" if hand == "left" else "arm_right")

func _try_fire(slot: String, weapon: WeaponPart) -> void:
	if not _is_shoulder_slot(slot):
		# A destroyed arm frame cannot hold or fire anything on that hand — not the
		# weapon and not even a bare-fist punch (the arm is gone).
		if not _hand_usable(slot):
			return
		if weapon == null:
			# Empty hand: fall back to a bare-fist punch (unarmed melee). It obeys
			# the shared cooldown core so punches can't exceed the fist cadence.
			var fist := _fist()
			var fist_core := _core_for_weapon(fist)
			if fist_core == null or not fist_core.consume_shot():
				return
			_melee_attack(slot, fist)
			return
	else:
		if weapon == null:
			return

	# Single weapon-action gate: capability + runtime permission BEFORE any
	# combat/animation/lifecycle side effect. Covers commit/hold/shoulder/
	# dumbfire/AI/test paths uniformly (all funnel here). The unarmed-fist
	# fallback above stays execution-owned and ungated; bash/dual-charge
	# enter through _melee_attack directly and are likewise untouched.
	# NOTE: _commit_fire arms per-hand trigger edge state before calling in;
	# that bookkeeping is side-effect-free w.r.t. ammo/heat/cooldown/damage.
	var requested := WeaponGameplayCapability.ACTION_FIRE
	if weapon.weapon_type == WeaponPart.WeaponType.MELEE:
		requested = WeaponGameplayCapability.ACTION_MELEE
	if not bool(_request_gate(slot, requested).get("allowed", false)):
		return

	if _is_reloading(slot):
		return
	if weapon.weapon_type == WeaponPart.WeaponType.SHIELD:
		return

	var core = _core_for_weapon(weapon)
	if core == null or not core.can_fire():
		return

	# Advanced Special Weapon Capability (Phase 2E-6)
	if weapon.has_special_capability():
		var mecha_node = get_parent() as Node3D
		var frame_slot := "torso" if _is_shoulder_slot(slot) else ("arm_" + slot)
		var user_ctx: Dictionary = {
			"frame_data": FrameSystem.get_equipped_frame(frame_slot) if FrameSystem else {},
			"installed_bridges": [],
			"current_energy": mecha_node.energy if (mecha_node and "energy" in mecha_node) else 100.0,
			"energy_system": mecha_node.energy_system if (mecha_node and "energy_system" in mecha_node) else null,
			"cooldown_remaining": core.cooldown,
			"core": core,
			"origin": get_muzzle_world_pos(slot) if get_muzzle_world_pos(slot) != Vector3.INF else (mecha_node.global_position if mecha_node else Vector3.ZERO)
		}
		var special_res := SpecialWeaponSystem.activate_special_weapon(weapon, mecha_node, user_ctx)
		if special_res.get("success", false):
			if bool(special_res.get("is_charging", false)) and special_res.get("timing_session") != null:
				_active_timing_sessions.append(special_res["timing_session"])
			_apply_recoil(weapon)
			AudioManager.play_weapon_sfx_with_override(weapon, user_ctx["origin"])
		return

	# Melee keeps its custom lunge/hit animation but obeys the shared rules
	# (cooldown, ammo, heat) through the core.
	if weapon.weapon_type == WeaponPart.WeaponType.MELEE:
		var is_pile := weapon.weapon_name.to_lower().contains("pile")
		if is_pile:
			var ammo_val := _get_ammo(weapon)
			if ammo_val > 0 and core.can_fire():
				if core.consume_shot():
					_melee_attack(slot, weapon, true)
				return
			elif core.cooldown <= 0.0:
				core.cooldown = 0.45 # Fast combo hammer cadence when empty/reloading
				_melee_attack(slot, weapon, false)
				return
			return
		if core.consume_shot():
			_melee_attack(slot, weapon, true)
		return

	var mecha = get_parent()
	if mecha == null:
		return
	var cam = get_viewport().get_camera_3d() if get_viewport() else null

	# Align mech facing immediately towards camera aim direction so the mech faces
	# where it shoots, even if backpedaling or moving in another direction.
	if cam != null:
		var cam_fwd = -cam.global_transform.basis.z
		cam_fwd.y = 0.0
		if cam_fwd.length() > 0.01:
			mecha.rotation.y = atan2(-cam_fwd.x, -cam_fwd.z)

	var spawn_pos = get_muzzle_world_pos(slot)
	if spawn_pos == Vector3.INF:
		# No visual mounted (bare fist / destroyed arm / missing model): fall
		# back to variant-resolved geometry, NOT Standard constants. Mounted
		# visuals always use their own muzzle markers (untouched path above).
		if _is_shoulder_slot(slot):
			var side := "left" if (slot == "shoulder_left" or slot == "left") else "right"
			spawn_pos = mecha.global_position + mecha.global_transform.basis * FrameVariantResolver.shoulder_fallback_for(mecha, side)
		else:
			var fside := "left" if slot == "left" else "right"
			spawn_pos = mecha.global_position + mecha.global_transform.basis * FrameVariantResolver.hand_fallback_for(mecha, fside)

	var target_point: Vector3
	if cam != null and get_viewport():
		var viewport_size = get_viewport().get_visible_rect().size
		var center = viewport_size / 2.0
		var ray_origin = cam.project_ray_origin(center)
		var ray_dir = cam.project_ray_normal(center)
		target_point = ray_origin + ray_dir * 500.0
		var vp := get_viewport()
		if vp and vp.get_world_3d() and vp.get_world_3d().direct_space_state:
			var space_state := vp.get_world_3d().direct_space_state
			var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 500.0)
			query.collision_mask = 1 | 2 | 4 | 8 # Ground (1), solid obstacles/buildings (2), hitboxes (4), enemies (8)
			var result := space_state.intersect_ray(query)
			if result:
				target_point = result["position"]
	else:
		var fwd = -mecha.global_transform.basis.z.normalized()
		target_point = spawn_pos + fwd * 500.0

	# Precise crosshair convergence: trajectory points directly from the weapon muzzle
	# to the exact 3D world collision point targeted by the crosshair center.
	var aim_dir: Vector3 = (target_point - spawn_pos).normalized()

	# Fire through the shared core: it consumes cooldown/ammo/heat and spawns the
	# projectile (bullet/missile/shotgun visuals handled by weapon_type). The
	# core applies this slot's upgrade multiplier to the projectile damage.
	core.damage_multiplier = _slot_damage_mult(slot)
	if core.try_fire(spawn_pos, aim_dir, false, mecha):
		_apply_recoil(weapon)
		AudioManager.play_weapon_sfx_with_override(weapon, spawn_pos)
		# Brass only for kinetic firearms — energy bolts and missiles eject nothing.
		if weapon.ejects_shell_casing():
			_spawn_shell_casing(spawn_pos, slot)

		# Trigger 3D Action Animations (Shoot recoil or Shoulder launch)
		var anim = mecha.get_node_or_null("MechaAnimation")
		if anim == null:
			anim = mecha.get_node_or_null("AnimationSystem")
		if anim and anim.get("action_animator") != null:
			if weapon.weapon_type == WeaponPart.WeaponType.MISSILE or _is_shoulder_slot(slot):
				anim.action_animator.play_shoulder_shoot()
			else:
				var is_heavy: bool = weapon.damage >= 55.0 or weapon.weapon_name.to_lower().contains("cannon") or weapon.weapon_name.to_lower().contains("heavy") or weapon.weapon_name.to_lower().contains("sniper")
				anim.action_animator.play_shoot(slot, is_heavy)
		
		# Durability wear: firing wears weapon lifespan; firing at high heat accelerates wear.
		# Scaled with fire_rate so high-RPM weapons wear proportionately per minute with heavy single-shot weapons.
		var rate_scale: float = clampf(float(weapon.fire_rate) / 0.2, 0.25, 2.0) if ("fire_rate" in weapon and weapon.fire_rate > 0.0) else 1.0
		var wear: float = 0.00004 * rate_scale
		if core.heat > (core.max_heat * 0.75):
			wear += 0.00015 * rate_scale
		GlobalData.degrade_weapon_durability(slot, wear)
		_emit_ammo_changed(slot, core.ammo, weapon.max_ammo)


func _try_fire_shoulder(side: String) -> void:
	var slot := "shoulder_" + side if not side.begins_with("shoulder") else side
	var weapon := _get_weapon_for_slot(slot)
	_commit_fire(slot, weapon)


func _is_missile_weapon(weapon: WeaponPart) -> bool:
	if weapon == null:
		return false
	return weapon.weapon_type == WeaponPart.WeaponType.MISSILE or weapon.weapon_name.to_lower().contains("missile")


func _handle_missile_release(slot: String) -> void:
	if missile_lock_system == null or not missile_lock_system.is_locking:
		return
	if missile_lock_system.active_slot != slot:
		return

	var result: Dictionary = missile_lock_system.stop_locking()
	var weapon: WeaponPart = result.get("weapon")
	if weapon == null:
		return

	var targets: Dictionary = result.get("targets", {})
	var is_tap: bool = bool(result.get("is_tap", false))
	var total_locks: int = int(result.get("total_locks", 0))

	if is_tap or total_locks <= 0 or targets.is_empty():
		_fire_dumbfire_missile(slot, weapon)
	else:
		_fire_missile_salvo(slot, weapon, targets)


func _fire_dumbfire_missile(slot: String, weapon: WeaponPart) -> void:
	if slot == "left":
		_try_fire("left", weapon)
	elif slot == "right":
		_try_fire("right", weapon)
	elif slot == "shoulder_left":
		_try_fire_shoulder("left")
	elif slot == "shoulder_right":
		_try_fire_shoulder("right")


func _fire_missile_salvo(slot: String, weapon: WeaponPart, targets_dict: Dictionary) -> void:
	var core := _core_for_weapon(weapon)
	if core == null:
		return

	# Salvo branch of a lock release: one gate decision here (the tap branch
	# is decided inside _try_fire, and only one branch executes per release).
	if not bool(_request_gate(slot, WeaponGameplayCapability.ACTION_FIRE).get("allowed", false)):
		return

	var is_shoulder := slot.begins_with("shoulder")
	var side := "left" if (slot == "left" or slot == "shoulder_left") else "right"
	var mecha := get_parent() as Node3D
	if mecha == null:
		return

	var cam := get_viewport().get_camera_3d()
	var aim_dir := -cam.global_transform.basis.z.normalized() if cam else -mecha.global_transform.basis.z.normalized()

	# Flatten target queue according to missile count
	var queue: Array[Node3D] = []
	for target in targets_dict.keys():
		var count: int = int(targets_dict[target])
		for i in range(count):
			queue.append(target)

	if is_shoulder:
		var ammo_type: String = weapon.get_ammo_type()
		if ammo_type != "none" and core.ammo <= 0:
			var available := consume_battle_reserve(ammo_type, queue.size())
			if available > 0:
				core.ammo = available

	# A salvo is ONE trigger pull: the weapon's fire_interval must not gate
	# individual missiles (0.065s spacing << interval would drop every lock
	# after the first). Heat/ammo/overheat rules still apply per missile.
	# Pricing is 1 lock = 1 missile = 1 ammo; volley pricing (e.g. Swarm's
	# ammo_per_shot 3 for 3 dumbfire projectiles) stays on the dumbfire path.
	var saved_aps := core.ammo_per_shot
	core.ammo_per_shot = 1
	for i in range(queue.size()):
		var target_node: Node3D = queue[i]
		if i > 0:
			await get_tree().create_timer(0.065).timeout
		if not is_instance_valid(mecha) or not mecha.is_inside_tree():
			core.ammo_per_shot = saved_aps
			return
		if core.ammo <= 0 and core.max_ammo > 0:
			break

		var spawn_pos: Vector3
		if is_shoulder:
			spawn_pos = _get_shoulder_muzzle_world_pos(side)
			if spawn_pos == Vector3.INF:
				spawn_pos = mecha.global_position + mecha.global_transform.basis * FrameVariantResolver.shoulder_fallback_for(mecha, side)
		else:
			spawn_pos = _get_muzzle_world_pos(side)

		core.damage_multiplier = float(_damage_mult_by_name.get(weapon.weapon_name, 1.0))
		core.cooldown = 0.0
		if core.try_fire_homing(spawn_pos, aim_dir, target_node, false, mecha, 0.45):
			AudioManager.play_weapon_sfx_with_override(weapon, spawn_pos)
			var anim = mecha.get_node_or_null("MechaAnimation")
			if anim == null:
				anim = mecha.get_node_or_null("AnimationSystem")
			if anim and anim.get("action_animator") != null:
				if is_shoulder:
					anim.action_animator.play_shoulder_shoot()
				else:
					anim.action_animator.play_shoot_recoil(side)
			GlobalData.degrade_weapon_durability("shoulder_" + side if is_shoulder else side, 0.002)
			if is_shoulder:
				shoulder_ammo_changed.emit(side, core.ammo, weapon.max_ammo)
			else:
				ammo_changed.emit(side, core.ammo, weapon.max_ammo)
	core.ammo_per_shot = saved_aps


func _melee_attack(hand: String, weapon: WeaponPart, is_loaded_blast: bool = true) -> void:
	var mecha = get_parent()
	var cam = get_viewport().get_camera_3d()
	if cam == null or mecha == null:
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	var ray_origin = cam.project_ray_origin(center)
	var ray_dir = cam.project_ray_normal(center)

	var target_point: Vector3 = ray_origin + ray_dir * 500.0
	var vp := get_viewport()
	if vp and vp.get_world_3d() and vp.get_world_3d().direct_space_state:
		var space_state := vp.get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 500.0)
		query.collision_mask = 1 | 2 | 4 | 8
		# Never aim at our own hull: without this the center ray clips the
		# backpack/head on high camera angles, target_point lands on our own
		# body behind the facing direction, and the mech spins AWAY from the
		# enemy it is trying to hit.
		if mecha != null:
			query.exclude = [mecha.get_rid()]
		var result := space_state.intersect_ray(query)
		if result:
			target_point = result["position"]
	else:
		target_point = ray_origin + ray_dir * 500.0

	var dir = (target_point - mecha.global_position).normalized()
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = -cam.global_transform.basis.z
		dir.y = 0.0
	dir = dir.normalized()
	if dir.length() > 0.01:
		var target_angle = atan2(-dir.x, -dir.z)
		mecha.rotation.y = target_angle

	var is_pile := weapon != null and weapon.weapon_name.to_lower().contains("pile")
	var hit_damage := (weapon.damage if weapon else FIST_DAMAGE) * _hand_damage_mult(hand)
	if is_pile:
		if is_loaded_blast:
			hit_damage = weapon.damage * 2.2 * _hand_damage_mult(hand)
		else:
			hit_damage = 45.0 * _hand_damage_mult(hand)

	# Eject a spent casing only for the Pile Bunker's loaded spike blast —
	# blades and fists never fling brass.
	if weapon and is_pile and is_loaded_blast:
		var spawn_pos = mecha.global_position + (Vector3(-0.6, 1.5, 0.5) if hand == "left" else Vector3(0.6, 1.5, 0.5))
		_spawn_shell_casing(spawn_pos, hand)
		
	# Execute lunging punch animation + Keyframed 3-Step Combo Attack Animation.
	# One-handed MELEE (heat blade / knife / mace / fist) uses the ActionForge
	# sword takes (single slash -> 3-hit combo); pile bunker keeps its thrust.
	_perform_pile_bunker_lunge_anim(mecha, dir, weapon)
	var anim = mecha.get_node_or_null("MechaAnimation")
	if anim == null:
		anim = mecha.get_node_or_null("AnimationSystem")
	if anim and anim.get("action_animator") != null:
		var played_af := false
		if not is_pile and anim.action_animator.has_method("play_af_melee"):
			played_af = anim.action_animator.play_af_melee(hand)
		if not played_af:
			anim.action_animator.play_melee(hand)

	_spawn_melee_trail(mecha, dir, weapon)
	# Damage is NOT dealt here: the swing animation owns the hit window (see
	# _process_pending_melee). The pending hit below executes exactly when
	# the blade visually reaches contact; restarting the swing (combo chain)
	# replaces it, so one input can never produce more hits than its swing's
	# own strikes.
	_pending_melee = {
		"hand": hand, "weapon": weapon, "damage": hit_damage,
		"dir": dir, "blast": is_loaded_blast,
	}
	if is_pile:
		if is_loaded_blast:
			AudioManager.play_pile_bunker_fire(mecha.global_position)
		else:
			AudioManager.play_sfx("bullet_ricochet", mecha.global_position, 0.5)
	else:
		AudioManager.play_melee_swing(weapon, mecha.global_position)

	if is_pile:
		EventBus.pile_bunker_fired.emit(is_loaded_blast, target_point)


## Executes the pending melee hit at the animation's strike moment. Called
## every physics frame: each strike of the live swing deals exactly one hit
## with the parameters captured at swing start; completion (or a restarted
## swing, which overwrites _pending_melee) clears it. Mechs without an
## animator keep the legacy immediate behavior.
func _process_pending_melee() -> void:
	if _pending_melee.is_empty():
		return
	var mecha := get_parent() as Node3D
	if mecha == null:
		_pending_melee = {}
		return
	var anim = mecha.get_node_or_null("MechaAnimation")
	if anim == null:
		anim = mecha.get_node_or_null("AnimationSystem")
	var animator = null
	if anim != null and anim.get("action_animator") != null:
		animator = anim.get("action_animator")
	if animator == null or not animator.has_method("poll_strike"):
		_execute_pending_melee_hit()
		return
	if animator.poll_strike():
		_execute_pending_melee_hit()
	if animator.has_method("poll_attack_complete") and animator.poll_attack_complete():
		_pending_melee = {}


func _execute_pending_melee_hit() -> void:
	var mecha := get_parent() as Node3D
	if mecha == null or _pending_melee.is_empty():
		_pending_melee = {}
		return
	var weapon: WeaponPart = _pending_melee.get("weapon")
	_check_melee_hit(mecha, _pending_melee.get("dir", Vector3.ZERO),
		float(_pending_melee.get("damage", 0.0)), weapon,
		bool(_pending_melee.get("blast", true)))

# --- SHOULDER BASH / DUAL CHARGE (destroyed arms still fight) ---

# Synthetic melee weapon for a shoulder ram. A destroyed arm cannot hold a gun,
# but the mech still fights back with the shoulder on that side — a short blunt
# melee hit that flows through the same lunge/hit pipeline as every other swing.
func _shoulder_weapon_resource() -> WeaponPart:
	if _shoulder_weapon == null:
		_shoulder_weapon = WeaponPart.new()
		_shoulder_weapon.weapon_name = "Shoulder Bash"
		_shoulder_weapon.weapon_type = WeaponPart.WeaponType.MELEE
		_shoulder_weapon.damage = SHOULDER_DAMAGE
		_shoulder_weapon.fire_rate = FIST_FIRE_INTERVAL
		_shoulder_weapon.impact = FIST_IMPACT
		_shoulder_weapon.max_ammo = 0
		_shoulder_weapon.ammo_per_shot = 0
		_shoulder_weapon.range_distance = 2.2
	return _shoulder_weapon


# Synthetic melee weapon for the dual-press charge: a long, heavy ram that
# drives the mech deep at the target (bigger lunge than any single swing) and
# hits harder than either side alone.
func _charge_weapon_resource() -> WeaponPart:
	if _charge_weapon == null:
		_charge_weapon = WeaponPart.new()
		_charge_weapon.weapon_name = "Dual Charge"
		_charge_weapon.weapon_type = WeaponPart.WeaponType.MELEE
		_charge_weapon.damage = SHOULDER_DAMAGE * 2.2
		_charge_weapon.fire_rate = FIST_FIRE_INTERVAL
		_charge_weapon.impact = FIST_IMPACT * 2.0
		_charge_weapon.max_ammo = 0
		_charge_weapon.ammo_per_shot = 0
		_charge_weapon.range_distance = 5.0
	return _charge_weapon


# The player pressed fire on a hand whose arm is destroyed: ram with that
# shoulder. Short lunge + blunt hit, driven by the shared melee pipeline so
# cooldown, hit ray, trail and shake all behave like a real swing.
func _shoulder_bash(hand: String) -> void:
	var shoulder := _shoulder_weapon_resource()
	var core := _core_for_weapon(shoulder)
	if core == null or not core.consume_shot():
		return
	_melee_attack(hand, shoulder)


# A fire press arrived. When BOTH sides hold a real melee weapon (not a bare
# fist), the press is DEFERRED briefly: if the other fire button lands within
# DUAL_PRESS_WINDOW_MS, the two presses merge into one straight charge; otherwise
# the press commits as a normal fire when the window expires.  Ranged hands and
# bare fists always fire immediately — the dual charge only needs both actual
# melee weapons or both destroyed-arm shoulders.  Returns true when the press
# was consumed by the deferral/charge path.
func _fire_press(hand: String) -> bool:
	var now := Time.get_ticks_msec()
	if hand == "left":
		_last_left_press_ms = now
	else:
		_last_right_press_ms = now
	# Not both melee -> no charge is possible, fire immediately.
	if not _hand_is_melee_capable("left") or not _hand_is_melee_capable("right"):
		return false
	# The other button ALREADY landed within the window -> this press completes
	# a dual charge (the deferred first press is resolved in _physics_process).
	var other_ms := _last_right_press_ms if hand == "left" else _last_left_press_ms
	if now - other_ms <= DUAL_PRESS_WINDOW_MS and other_ms > 0:
		_do_dual_charge()
		return true
	# This is (potentially) the first button of a pair: hold the press back and
	# watch for the second button for a brief window.
	_pending_fire = hand
	_pending_fire_ms = now
	return true


# Commits the deferred first press as a NORMAL fire once the dual-press window
# expires without the second button arriving: reload / shield / shoot / shoulder
# bash exactly as an immediate press would have.
func _commit_normal_fire(hand: String) -> void:
	if not _hand_usable(hand):
		_shoulder_bash(hand)
		return
	if hand == "left":
		if holding_reload or Input.is_action_pressed("reload"):
			reload_weapon("left")
		else:
			fire_left_holding = Input.is_action_pressed("fire_left")
			if left_hand:
				if left_hand.weapon_type == WeaponPart.WeaponType.SHIELD:
					# GUARD request: capability + gate BEFORE the toggle.
					if bool(_request_gate("left", WeaponGameplayCapability.ACTION_GUARD).get("allowed", false)):
						_toggle_shield("left")
				else:
					_commit_fire("left", left_hand)
			else:
				# Unarmed: bare-fist punch.
				_commit_fire("left", null)
	else:
		if holding_reload or Input.is_action_pressed("reload"):
			reload_weapon("right")
		else:
			fire_right_holding = Input.is_action_pressed("fire_right")
			if right_hand:
				if right_hand.weapon_type == WeaponPart.WeaponType.SHIELD:
					# GUARD request: capability + gate BEFORE the toggle.
					if bool(_request_gate("right", WeaponGameplayCapability.ACTION_GUARD).get("allowed", false)):
						_toggle_shield("right")
				else:
					_commit_fire("right", right_hand)
			else:
				# Unarmed: bare-fist punch.
				_commit_fire("right", null)


# Fires the straight dual charge: one heavy combined ram (both shoulders / both
# melee weapons) straight at the target, driven by the shared melee pipeline.
func _do_dual_charge() -> void:
	_pending_fire = ""
	var charge := _charge_weapon_resource()
	var core := _core_for_weapon(charge)
	if core == null or not core.consume_shot():
		return
	_melee_attack("left", charge)


# True when the given side can fight as melee: it holds a melee weapon, is
# empty-handed (bare fist), or its arm is destroyed (shoulder bash).
func _hand_is_melee_capable(hand: String) -> bool:
	if not _hand_usable(hand):
		return true  # destroyed arm -> shoulder bash
	var weapon := left_hand if hand == "left" else right_hand
	if weapon == null:
		return true  # empty hand -> bare fist
	return weapon.weapon_type == WeaponPart.WeaponType.MELEE


func _perform_pile_bunker_lunge_anim(mecha: Node3D, dir: Vector3, weapon: WeaponPart) -> void:
	if not mecha:
		return
	# Kill any in-flight lunge before starting a new one: two tweens animating
	# global_position simultaneously (rapid consecutive melee swings) fight over
	# the same property and fling the mecha around, breaking the swing hit ray.
	if _lunge_tween != null and _lunge_tween.is_valid():
		_lunge_tween.kill()
	var orig_pos = mecha.global_position
	var lunge_dist = _melee_lunge_dist(weapon)
	
	_lunge_tween = mecha.create_tween().set_parallel(false)
	var tween: Tween = _lunge_tween
	# 1. Anticipation: Pull back slightly & crouch
	tween.tween_property(mecha, "global_position", orig_pos - dir * 0.4, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 2. Explosive Forward Thrust
	tween.tween_property(mecha, "global_position", orig_pos + dir * lunge_dist, 0.07).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	
	# Screen shake on impact, scaled to the weapon's punch so EVERY melee hit
	# lands with feedback — not just the pile bunker's charge. Damage-scaled so
	# the pile (120) still kicks at ~0.35 (unchanged), the heat blade (50) lands
	# ~0.2, the knife (25) a firm 0.15, and a bare fist (8) a light 0.11 tap.
	var shake_strength := 0.0
	if weapon != null:
		shake_strength = clampf(0.09 + weapon.damage * 0.0022, 0.1, 0.4)
	var camera_rig = get_tree().get_nodes_in_group("camera_rig")
	if shake_strength > 0.0 and not camera_rig.is_empty() and camera_rig[0].has_method("add_shake"):
		camera_rig[0].add_shake(shake_strength)
		
	# 3. Recovery
	tween.tween_property(mecha, "global_position", orig_pos, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


var _melee_combo: int = 0
# The melee lunge tween currently moving the mecha (killed before a new swing
# starts so consecutive swings never animate global_position concurrently).
var _lunge_tween: Tween = null

func _apply_pile_hitstop() -> void:
	if _hitstop_timer != null:
		return  # time is already frozen from an earlier pile connect
	Engine.time_scale = PILE_HITSTOP_SCALE
	_hitstop_timer = get_tree().create_timer(PILE_HITSTOP_DURATION, true, false, true)
	_hitstop_timer.timeout.connect(_end_pile_hitstop)


func _end_pile_hitstop() -> void:
	_hitstop_timer = null
	Engine.time_scale = 1.0


func _spawn_melee_trail(mecha: Node3D, direction: Vector3, weapon: WeaponPart = null) -> void:
	var is_first_swing = (_melee_combo % 2 == 0)
	_melee_combo += 1
	var color := Color(0.8, 0.9, 1.0)
	var emission := Color(0.3, 0.5, 1.0)
	var forward_start := 1.5
	var forward_step := 1.0
	# Subtle per-weapon trail colors matched to each weapon's audio identity:
	# the fist's muted steel-white, the knife's cool silver slash, the heat
	# blade's warm ember, and the pile's heavy gunmetal iron. All kept muted so
	# the trails stay readable against enemy (red) and ally (cyan) swings.
	if weapon == _fist_weapon:
		# Bare-fist punch: a short, muted steel-white sweep.
		color = Color(0.9, 0.92, 0.96)
		emission = Color(0.55, 0.6, 0.7)
		forward_start = 1.0
		forward_step = 0.7
	elif weapon == _shoulder_weapon:
		# Shoulder bash: a short, heavy amber-orange slam (blunt shoulder ram).
		color = Color(1.0, 0.72, 0.35)
		emission = Color(0.95, 0.55, 0.2)
		forward_start = 0.8
		forward_step = 0.7
	elif weapon == _charge_weapon:
		# Dual charge: a long, wide hot-amber streak (deep combined ram).
		color = Color(1.0, 0.65, 0.25)
		emission = Color(1.0, 0.45, 0.15)
		forward_start = 2.6
		forward_step = 1.8
	elif weapon != null:
		var wname := weapon.weapon_name.to_lower()
		if wname.contains("knife"):
			# Combat knife: a short, cold silver slash (matches its sharp high
			# slash voice).
			color = Color(0.78, 0.87, 0.97)
			emission = Color(0.45, 0.62, 0.85)
			forward_start = 1.2
			forward_step = 0.8
		elif wname.contains("blade"):
			# Heat blade: a warm ember sweep (matches its ringing tone).
			color = Color(1.0, 0.76, 0.42)
			emission = Color(0.92, 0.5, 0.18)
		elif wname.contains("pile"):
			# Pile bunker: a heavy gunmetal iron sweep (matches its deep sub-
			# bass impact).
			color = Color(0.72, 0.66, 0.6)
			emission = Color(0.52, 0.38, 0.32)
	# Shared trail renderer; the combo alternates the sweep direction between
	# swings (and this weapon's arcs reach slightly further than AI swings).
	EffectManager.spawn_melee_trail(
		mecha.global_position,
		direction,
		color,
		emission,
		forward_start,
		forward_step,
		1.0 if is_first_swing else -1.0,
	)


func _check_melee_hit(mecha: Node3D, direction: Vector3, damage: float, weapon: WeaponPart = null, is_loaded_blast: bool = true) -> void:
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	var ray_origin = cam.project_ray_origin(center)
	var ray_dir = cam.project_ray_normal(center)

	var aim_point: Vector3 = ray_origin + ray_dir * 10.0
	var vp := get_viewport()
	if vp and vp.get_world_3d() and vp.get_world_3d().direct_space_state:
		var space_state := vp.get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 10.0)
		query.collision_mask = 8
		if mecha != null:
			query.exclude = [mecha.get_rid()]
		var result := space_state.intersect_ray(query)
		if result:
			aim_point = result["position"]

	var enemies = get_tree().get_nodes_in_group("enemy")
	var lunge_dist = _melee_lunge_dist(weapon)
	var swing_range = lunge_dist + FrameVariantResolver.melee_hit_reach_for(mecha)
	var aim2 := Vector2(direction.x, direction.z).normalized()
	var is_pile := weapon != null and weapon.weapon_name.to_lower().contains("pile")

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var to_h := Vector2(enemy.global_position.x - mecha.global_position.x,
			enemy.global_position.z - mecha.global_position.z)
		var proj := to_h.dot(aim2)
		if proj < 0.1 or proj > swing_range + 0.05:
			continue
		var perp := absf(to_h.cross(aim2))
		if perp > MELEE_AUTO_AIM_WIDTH:
			continue

		var melee_type := weapon.get_damage_type() if weapon != null else "blunt"
		if is_pile and is_loaded_blast:
			melee_type = "heat" # Explosive heat burst on loaded shell ignition

		if enemy.has_method("take_damage_at_point"):
			enemy.take_damage_at_point(damage, aim_point, melee_type)
		elif enemy.has_method("take_damage"):
			enemy.take_damage(damage, melee_type)
		melee_hit_landed.emit()

		if is_pile and is_loaded_blast:
			_apply_pile_hitstop()
			if EffectManager:
				EffectManager.spawn_hit_spark(enemy.global_position + Vector3(0, 1.5, 0), Vector3.UP, "heat")
			EffectManager.spawn_damage_number(enemy.global_position + Vector3(0, 2.5, 0), damage, Color(1, 0.2, 0))
			AudioManager.play_pile_bunker_hit(enemy.global_position)
		elif is_pile:
			# Empty mechanical hammer hit
			if EffectManager:
				EffectManager.spawn_hit_spark(enemy.global_position + Vector3(0, 1.5, 0), Vector3.UP, "pierce")
			EffectManager.spawn_damage_number(enemy.global_position + Vector3(0, 2.5, 0), damage, Color(0.9, 0.9, 0.9))
			AudioManager.play_melee_hit(weapon, enemy.global_position)
		else:
			if weapon != null and weapon.impact > 0.0 and enemy.has_method("apply_impact"):
				enemy.apply_impact(weapon.impact, direction)
			EffectManager.spawn_damage_number(enemy.global_position + Vector3(0, 2.5, 0), damage, Color(1, 0.5, 0))
			AudioManager.play_melee_hit(weapon, enemy.global_position)


# ====================================================================
# TWO-HAND GRIP — big weapons need both hands without enough mech Power
# ====================================================================

func _mech_power() -> float:
	return GlobalData.get_mech_power()


# Power of the arm actually holding the weapon. Two-hand weapons check THIS arm:
# a strong arm can one-hand a railgun while a weak arm still needs the other
# hand to brace it.
func _hand_power(hand: String) -> float:
	return GlobalData.get_arm_power(hand)


func weapon_needs_both_hands(weapon: WeaponPart, hand: String = "") -> bool:
	if weapon == null:
		return false
	# Without an explicit hand (callers that only know the weapon), fall back to
	# whichever hand currently holds it.
	if hand == "":
		if left_hand == weapon:
			hand = "left"
		elif right_hand == weapon:
			hand = "right"
	if weapon.two_handed:
		return weapon.requires_two_hand(_hand_power(hand))
	# Capability-based grip (HandlingResolver): a heavy arm_load forces the
	# second hand even without the explicit two_handed flag. Defaults
	# (arm_load == 0) resolve ONE_HAND, preserving current behavior.
	var res := HandlingResolver.resolve(weapon, "hand", _handling_powers(hand))
	return str(res.get("grip_mode", HandlingResolver.GRIP_ONE_HAND)) in [HandlingResolver.GRIP_TWO_HAND, HandlingResolver.GRIP_BRACED]


## Caller-gathered capability state for HandlingResolver (arm/leg/mech power,
## frame recoil resistance, destroyed-arm state). Pure data, no side effects.
func _handling_powers(hand: String) -> Dictionary:
	var resistance: float = FrameSystem.get_total_recoil_resistance()
	var destroyed := false
	if hand == "left" or hand == "right":
		destroyed = not _hand_usable(hand)
	return {
		"arm_power": _hand_power(hand),
		"leg_power": GlobalData.get_leg_power(),
		"mech_power": GlobalData.get_mech_power(),
		"recoil_resistance": resistance,
		"arm_destroyed": destroyed,
	}


## Resolved handling state for the weapon currently held in a hand (or a
## shoulder slot). Empty when nothing is held. For tests, HUD and telemetry —
## grip enforcement itself flows through weapon_needs_both_hands().
func get_handling(slot: String) -> Dictionary:
	var weapon: WeaponPart = null
	var mount := "hand"
	if slot == "left" or slot == "right":
		weapon = left_hand if slot == "left" else right_hand
		mount = "hand"
	elif slot == "shoulder_left" or slot == "shoulder_right":
		weapon = shoulder_left if slot == "shoulder_left" else shoulder_right
		mount = slot
	else:
		return {}
	if weapon == null:
		return {}
	var hand := slot if (slot == "left" or slot == "right") else ""
	return HandlingResolver.resolve(weapon, mount, _handling_powers(hand))


## Capability query for the weapon in a slot (or a shoulder slot): "is this
## action permitted?" Read-only. Consulted by the request gate below and by
## tests/HUD/telemetry — never executes anything itself.
func get_capability(slot: String, action: String) -> Dictionary:
	var weapon: WeaponPart = null
	var mount := "hand"
	var hand := ""
	if slot == "left" or slot == "right":
		weapon = left_hand if slot == "left" else right_hand
		mount = "hand"
		hand = slot
	elif slot == "shoulder_left" or slot == "shoulder_right":
		weapon = shoulder_left if slot == "shoulder_left" else shoulder_right
		mount = slot
	else:
		return WeaponGameplayCapability.query(null, action, "hand", _handling_powers(""))
	if weapon == null:
		return WeaponGameplayCapability.query(null, action, mount, _handling_powers(hand))
	return WeaponGameplayCapability.query(weapon, action, mount, _handling_powers(hand))


## Runtime liveness for the action gate, gathered from authoritative owners.
## Destroyed is universal (own HealthSystem). Eject is scoped to mechs that
## can be the operator's: the player group or parked/unoccupied player mechs
## (eject sets those metas) — allies/enemies never carry them, so shared
## dispatch paths (AI _try_fire) keep their current behavior during EJECT.
func _gate_runtime() -> Dictionary:
	var destroyed := false
	var absent := false
	var mecha := get_parent()
	if mecha != null:
		var hs = mecha.get_node_or_null("HealthSystem")
		if hs != null:
			destroyed = bool(hs.get("is_destroyed"))
		if GameManager.current_state == GameManager.State.EJECT:
			absent = mecha.is_in_group("player") or mecha.has_meta("is_parked") or mecha.has_meta("is_unoccupied")
	return {"mech_destroyed": destroyed, "operator_absent": absent}


## Single request-gate decision: structural capability, then runtime gate.
## Read-only; consults nothing that mutates combat, animation or lifecycle.
func _request_gate(slot: String, action: String) -> Dictionary:
	return WeaponActionGate.query(get_capability(slot, action), _gate_runtime())


# Returns the hand that currently holds a weapon needing a two-hand grip.
func _two_hand_hand() -> String:
	if left_hand and weapon_needs_both_hands(left_hand, "left"):
		return "left"
	if right_hand and weapon_needs_both_hands(right_hand, "right"):
		return "right"
	return ""


# When a two-hand weapon is gripped, the other hand is holstered (returned to
# the pack carry) so both arms support the weapon and it can't be dual-wielded.
func _enforce_two_hand_grip() -> void:
	var grip = _two_hand_hand()
	if grip == "":
		return
	var other := "right" if grip == "left" else "left"
	var other_weapon: WeaponPart = right_hand if other == "right" else left_hand
	if other_weapon == null:
		return
	# Holster: put the other weapon first in the carry pack and free the hand.
	carry.insert(0, other_weapon)
	if other == "left":
		left_hand = null
	else:
		right_hand = null
	weapon_switched.emit(other, "Empty")
	carry_updated.emit(carry)
	_update_weapon_visuals()


func is_two_hand_gripped_hand(hand: String) -> bool:
	return _two_hand_hand() == hand


# ====================================================================
# HELPERS
# ====================================================================

func _get_ammo(weapon: WeaponPart) -> int:
	var core = _core_for_weapon(weapon)
	return core.ammo if core else 0


# ====================================================================
# HEAT SYSTEM (every weapon with heat_capacity > 0)
# State + cooling live in WeaponCore; the manager only exposes it read-only.
# ====================================================================

func _get_heat(weapon: WeaponPart) -> float:
	var core = _core_for_weapon(weapon)
	return core.heat if core else 0.0


func get_heat(hand: String) -> float:
	var weapon = left_hand if hand == "left" else right_hand
	if weapon == null:
		return 0.0
	return _get_heat(weapon)


func get_heat_percent(hand: String) -> float:
	var weapon = left_hand if hand == "left" else right_hand
	if weapon == null or not weapon.uses_heat():
		return 0.0
	var core = _core_for_weapon(weapon)
	return core.get_heat_percent() if core else 0.0


func is_overheated(hand: String) -> bool:
	var weapon = left_hand if hand == "left" else right_hand
	if weapon == null:
		return false
	var core = _core_for_weapon(weapon)
	return core.is_overheated() if core else false


func get_shoulder_heat(side: String) -> float:
	var weapon: WeaponPart = shoulder_left if side == "left" else shoulder_right
	if weapon == null:
		return 0.0
	return _get_heat(weapon)


func get_shoulder_heat_percent(side: String) -> float:
	var weapon: WeaponPart = shoulder_left if side == "left" else shoulder_right
	if weapon == null or not weapon.uses_heat():
		return 0.0
	var core = _core_for_weapon(weapon)
	return core.get_heat_percent() if core else 0.0


func is_shoulder_overheated(side: String) -> bool:
	var weapon: WeaponPart = shoulder_left if side == "left" else shoulder_right
	if weapon == null:
		return false
	var core = _core_for_weapon(weapon)
	return core.is_overheated() if core else false


# ====================================================================
# RECOIL — pushes the shooter's mech back along the weapon's facing
# ====================================================================

func _apply_recoil(weapon: WeaponPart) -> void:
	if weapon == null:
		return
	var mecha = get_parent()
	var cam = get_viewport().get_camera_3d() if get_viewport() else null

	# Pull the mech backward along the camera aim direction if recoil_force configured.
	if mecha != null and cam != null and weapon.recoil_force > 0.0:
		var cam_basis = cam.global_transform.basis
		var backward: Vector3 = cam_basis.z  # +Z faces AWAY from aim
		backward.y = 0.0
		if backward.length() > 0.01:
			backward = backward.normalized()
			# GDD §6.1: Arm damage increases recoil
			var recoil_mult: float = PartPenaltySystem.total_recoil_multiplier()
			# Frame capability: recoil_resistance damps the impulse (0.0 → ×1.0,
			# byte-identical current behavior; set bonuses reduce the kick).
			var resistance: float = FrameSystem.get_total_recoil_resistance()
			recoil_mult *= HandlingResolver.recoil_multiplier(resistance)
			var impulse: Vector3 = backward * weapon.recoil_force * recoil_mult
			# Railguns use the heavy kick: a stronger push plus a stance-recovery
			# beat (decay slowed) so the mech visibly staggers and re-balances.
			if weapon.weapon_type == WeaponPart.WeaponType.RAILGUN \
					and mecha.has_method("apply_heavy_recoil_impulse"):
				mecha.apply_heavy_recoil_impulse(impulse)
			elif mecha.has_method("apply_recoil_impulse"):
				mecha.apply_recoil_impulse(impulse)

	# Camera shake proportional to recoil / weapon firepower.
	var shake_val: float = weapon.recoil_shake
	if shake_val <= 0.0:
		match weapon.weapon_type:
			WeaponPart.WeaponType.MISSILE:
				shake_val = 0.35
			WeaponPart.WeaponType.SHOTGUN:
				shake_val = 0.22
			WeaponPart.WeaponType.RAILGUN:
				shake_val = 0.45
			WeaponPart.WeaponType.BEAM_RIFLE:
				shake_val = 0.14
			WeaponPart.WeaponType.MACHINE_GUN, WeaponPart.WeaponType.MINIGUN:
				shake_val = 0.07
			_:
				shake_val = clampf(weapon.damage * 0.005, 0.05, 0.4)

	if shake_val > 0.0:
		var rigs = get_tree().get_nodes_in_group("camera_rig")
		if not rigs.is_empty() and rigs[0].has_method("add_shake"):
			rigs[0].add_shake(shake_val)


# Applies a weapon's impact/stagger to a target enemy after a hit.
func apply_impact_to_target(target: Node3D, weapon: WeaponPart, from_dir: Vector3) -> void:
	if weapon == null or weapon.impact <= 0.0:
		return
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("apply_impact"):
		target.apply_impact(weapon.impact, from_dir)


# ====================================================================
# SHIELD
# ====================================================================

func _toggle_shield(hand: String) -> void:
	var weapon = left_hand if hand == "left" else right_hand
	if weapon == null or weapon.weapon_type != WeaponPart.WeaponType.SHIELD:
		return

	if shield_active:
		shield_active = false
		weapon_switched.emit(hand, weapon.weapon_name + " [DOWN]")
	else:
		# A plate that broke this battle stays broken — re-raising the SAME
		# plate does not bring its HP back (physical plates never regenerate).
		# Only a fresh plate (different from the one currently armed) starts
		# at full HP.
		if shield_current_hp <= 0.0 and _armed_shield == weapon:
			return
		if _armed_shield != weapon:
			# New plate in hand: arm it at full HP and forget the old one.
			_armed_shield = weapon
			shield_current_hp = weapon.shield_hp
		shield_active = true
		shield_max_hp = weapon.shield_hp
		weapon_switched.emit(hand, weapon.weapon_name + " [UP]")


# The raised plate fully stops the attack (0.0 leaks through); it just pays
# the damage from its own HP. The plate's anti-type drains at 40% — an
# anti-pierce plate soaks pierce for ages but melts against heat/blunt.
func absorb_damage_with_shield(amount: float, damage_type: String = "") -> float:
	if not shield_active or shield_current_hp <= 0.0:
		return amount
	var weapon := _active_shield_weapon()
	var attack: String = MechaHealthBase.normalize_damage_type(damage_type)
	var drain_mult := 1.0
	if weapon != null and weapon.get_shield_type() == attack:
		drain_mult = 0.4
	shield_current_hp = maxf(shield_current_hp - amount * drain_mult, 0.0)
	if shield_current_hp <= 0.0:
		shield_current_hp = 0.0
		shield_active = false
		var hand = "left" if left_hand and left_hand.weapon_type == WeaponPart.WeaponType.SHIELD else "right"
		weapon_switched.emit(hand, "Shield BROKEN")
	return 0.0


func is_shield_active() -> bool:
	return shield_active


# Which hand currently holds a shield plate ("left" / "right"), or "" when
# no shield is equipped. The mech animation uses this to raise the right arm.
func get_shield_hand() -> String:
	if left_hand and left_hand.weapon_type == WeaponPart.WeaponType.SHIELD:
		return "left"
	if right_hand and right_hand.weapon_type == WeaponPart.WeaponType.SHIELD:
		return "right"
	return ""


# The shield weapon currently held (the SHIELD-type weapon in a hand), used to
# read its anti-type plating. Null when nothing shield-like is equipped.
func _active_shield_weapon() -> WeaponPart:
	if left_hand and left_hand.weapon_type == WeaponPart.WeaponType.SHIELD:
		return left_hand
	if right_hand and right_hand.weapon_type == WeaponPart.WeaponType.SHIELD:
		return right_hand
	return null


# ====================================================================
# SHELL EJECTION
# ====================================================================

func _spawn_shell_casing(spawn_pos: Vector3, slot: String) -> void:
	var mecha = get_parent() as Node3D
	if mecha == null or not mecha.is_inside_tree() or get_tree().current_scene == null:
		return

	# Realistic ejection: right + up + slight forward/back, with mech velocity influence
	var is_left: bool = (slot == "left" or slot == "shoulder_left" or slot == "left_shoulder")
	var side: float = -1.0 if is_left else 1.0
	var basis: Basis = mecha.global_transform.basis
	var right: Vector3 = basis.x * side
	var up: Vector3 = basis.y
	var fwd: Vector3 = -basis.z
	# Ejector port is on the side of the breech: strong sideways, up, slight rearward
	var eject_dir: Vector3 = (right * randf_range(0.85, 1.15) + up * randf_range(0.45, 0.75) + fwd * randf_range(-0.25, 0.15)).normalized()
	var speed: float = randf_range(4.2, 6.8) # m/s — brisk brass, not floating

	var shell_body := RigidBody3D.new()
	shell_body.name = "ShellCasing"
	shell_body.collision_layer = 0
	shell_body.collision_mask = 1 << 1 # Environment (2) — bounce on ground, not on mecha
	shell_body.mass = 0.02
	shell_body.gravity_scale = 1.0
	shell_body.linear_damp = 0.06
	shell_body.angular_damp = 0.18
	shell_body.contact_monitor = true
	shell_body.max_contacts_reported = 2
	shell_body.continuous_cd = true

	var phys_mat := PhysicsMaterial.new()
	phys_mat.friction = 0.62
	phys_mat.bounce = 0.32
	shell_body.physics_material_override = phys_mat

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.06, 0.04, 0.10)
	col.shape = shape
	shell_body.add_child(col)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.04, 0.10)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.82, 0.68, 0.22, 1.0)
	mat.metallic = 0.85
	mat.roughness = 0.28
	mesh.material_override = mat
	shell_body.add_child(mesh)

	# Add a tiny brass glint
	var glint := OmniLight3D.new()
	glint.light_color = Color(1.0, 0.85, 0.4)
	glint.light_energy = 0.7
	glint.omni_range = 0.6
	glint.position = Vector3.ZERO
	shell_body.add_child(glint)
	var glint_tw := shell_body.create_tween()
	glint_tw.tween_property(glint, "light_energy", 0.0, 0.35).set_delay(0.25)

	get_tree().current_scene.add_child(shell_body)
	shell_body.global_position = spawn_pos + right * 0.28 + up * 0.18 + fwd * randf_range(-0.05, 0.10)

	# Inherit a bit of mech velocity so it doesn't look detached when dashing
	var inherit_vel: Vector3 = Vector3.ZERO
	if mecha is CharacterBody3D:
		inherit_vel = (mecha as CharacterBody3D).velocity * 0.28
	shell_body.linear_velocity = eject_dir * speed + inherit_vel + Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.35), randf_range(-0.5, 0.5))
	shell_body.angular_velocity = Vector3(
		randf_range(-18, 18),
		randf_range(-22, 22) + side * 12.0, # bias spin outward
		randf_range(-20, 20)
	)

	# Auto-fade and free after 2.5-3.5s (or on rest)
	var life := randf_range(2.6, 3.4)
	var t := shell_body.create_tween()
	t.tween_interval(life)
	t.tween_property(mesh, "transparency", 0.2, 0.3)
	t.tween_callback(shell_body.queue_free)

	# Safety: free even if stuck forever — capture ID not Node to avoid freed lambda capture
	var shell_id := shell_body.get_instance_id()
	get_tree().create_timer(5.0).timeout.connect(func():
		var node = instance_from_id(shell_id)
		if is_instance_valid(node):
			node.queue_free()
	, CONNECT_ONE_SHOT)

func _update_weapon_visuals() -> void:
	var mecha = get_parent() as Node3D
	if not mecha:
		return
	_update_hand_weapon_visual(mecha, "left", left_hand)
	_update_hand_weapon_visual(mecha, "right", right_hand)
	_update_shoulder_weapon_visual(mecha, "left", shoulder_left)
	_update_shoulder_weapon_visual(mecha, "right", shoulder_right)
	_update_carry_visuals(mecha)
	# Backpack equipment visual (derived-only projection of Loadout.equipped_backpack).
	BackpackVisualFactory.mount_backpack(mecha, BackpackSystem.get_equipped_backpack())

func _update_hand_weapon_visual(mecha: Node3D, hand: String, weapon: WeaponPart) -> void:
	WeaponVisualFactory.mount_hand(mecha, hand, weapon, "WeaponMesh_" + hand)

func _update_shoulder_weapon_visual(mecha: Node3D, side: String, weapon: WeaponPart) -> void:
	WeaponVisualFactory.mount_shoulder(mecha, side, weapon, "ShoulderMesh_" + side)

# Renders the weapons carried on the mech's back (from the loadout).
func _update_carry_visuals(mecha: Node3D) -> void:
	WeaponVisualFactory.mount_carry(mecha, carry, "CarryWeapons")


## Returns an array of active telegraph descriptor dictionaries from currently charging special weapons.
func get_active_telegraph_descriptors() -> Array:
	var list: Array = []
	for session in _active_timing_sessions:
		if session and session.has_method("is_preparing") and session.is_preparing():
			list.append(session.get_telegraph_descriptor())
	return list
