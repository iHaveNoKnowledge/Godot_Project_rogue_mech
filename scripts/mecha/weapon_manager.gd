extends Node3D

signal weapon_switched(hand: String, weapon_name: String)
signal ammo_changed(hand: String, current: int, max_ammo: int)
signal reload_progress(hand: String, partial_text: String, reserve_ammo: int, percent: float)
signal carry_updated(carry_list: Array)
signal weapon_dropped(hand: String, weapon: WeaponPart)
signal heat_changed(hand: String, current: float, max_heat: float, overheated: bool)
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
var carry: Array[WeaponPart] = []

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

# --- Input State ---
var holding_left: bool = false
var holding_right: bool = false
var fire_left_holding: bool = false
var fire_right_holding: bool = false
var holding_reload: bool = false
var reloading_left: bool = false
var reloading_right: bool = false
var _hold_time_left: float = 0.0
var _hold_time_right: float = 0.0

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

var _fist_weapon: WeaponPart = null


# How far a melee swing carries the mech toward the target, matched to the
# weapon's range_distance (lunge = range - arm reach, floored at 0.8 so even a
# short weapon still takes a step):
#   fist 3.0 / heat blade 3.0 -> 1.4   combat knife 2.5 -> 0.9   pile 4.0 -> 2.4
func _melee_lunge_dist(weapon: WeaponPart) -> float:
	if weapon == null or weapon.range_distance <= 0.0:
		return 1.4
	return maxf(weapon.range_distance - MELEE_HIT_REACH, 0.8)

# Synthetic unarmed-melee weapon: an empty hand still fights with a punch. It is
# a real MELEE WeaponPart (no ammo, no heat) so it flows through the same
# WeaponCore cooldown and melee-hit pipeline as the heat blade.
func _fist() -> WeaponPart:
	if _fist_weapon == null:
		_fist_weapon = WeaponPart.new()
		_fist_weapon.weapon_name = "Bare Fist"
		_fist_weapon.weapon_type = WeaponPart.WeaponType.MELEE
		_fist_weapon.damage = FIST_DAMAGE
		_fist_weapon.fire_rate = FIST_FIRE_INTERVAL
		_fist_weapon.impact = FIST_IMPACT
		_fist_weapon.max_ammo = 0
		_fist_weapon.ammo_per_shot = 0
		_fist_weapon.range_distance = 3.0
	return _fist_weapon


func _ready() -> void:
	# Load the equipped loadout from the Hangar (GlobalData.weapon_loadout) so the
	# battle mech carries the SAME weapons (hands + back) that were configured in the garage.
	# An empty hand slot in the loadout means "unarmed" — kept as null.
	left_hand = LoadoutSystem.get_equipped_weapon("left")
	right_hand = LoadoutSystem.get_equipped_weapon("right")
	carry = LoadoutSystem.get_carry_weapons()
	# Battle reserve = the ammo the player chose to carry in the loadout.
	# Deduct that from the persistent stash now (what you fire is spent); any
	# leftover returns to the stash when combat ends.
	battle_reserve = LoadoutSystem.get_loadout_ammo_dict()
	# Per-model upgrade multipliers from the loadout instances (hands + pack).
	_register_damage_mult(GlobalData.weapon_loadout.get("left", ""))
	_register_damage_mult(GlobalData.weapon_loadout.get("right", ""))
	var carry_refs = GlobalData.weapon_loadout.get("carry", [])
	if carry_refs is Array:
		for ref in carry_refs:
			_register_damage_mult(ref)
	for ammo_type in battle_reserve:
		var amount: int = battle_reserve[ammo_type]
		if amount > 0:
			LoadoutSystem.consume_reserve_ammo(ammo_type, amount)
	EventBus.combat_ended.connect(_on_combat_ended)
	call_deferred("_emit_initial_state")


func _on_combat_ended(_victory: bool) -> void:
	# Return any unused carried ammo to the persistent stash so nothing is lost.
	for ammo_type in battle_reserve:
		var amount: int = battle_reserve[ammo_type]
		if amount > 0:
			LoadoutSystem.add_reserve_ammo(ammo_type, amount)
	battle_reserve.clear()
	# Persist whatever the mech is actually carrying so the next battle starts
	# with the weapons picked up / swapped during this one. Skip while a hand is
	# still mid-swap (weapon temporarily held out of the hand, not yet committed).
	if not _selecting_left and not _selecting_right:
		sync_loadout_to_global()


# Writes the current hands + back-carry back into GlobalData.weapon_loadout so
# in-battle pickups and swaps survive into the next battle. Runs at combat end
# (and after each commit/drop) since return_to_board() -> save_run() only saves
# the state GlobalData holds at that moment.
func sync_loadout_to_global() -> void:
	# Hands/back are written back by INSTANCE uid (the copy that entered the
	# battle keeps its identity) so the hangar [E] badge stays per-instance.
	LoadoutSystem.set_hand_weapon("left", LoadoutSystem.resolve_hand_uid_for_sync("left", left_hand.resource_path if left_hand else ""))
	LoadoutSystem.set_hand_weapon("right", LoadoutSystem.resolve_hand_uid_for_sync("right", right_hand.resource_path if right_hand else ""))
	var carry_paths: Array = []
	for weapon in carry:
		if weapon:
			carry_paths.append(weapon.resource_path)
	GlobalData.weapon_loadout["carry"] = LoadoutSystem.resolve_carry_uids_for_sync(carry_paths)
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


# Damage multiplier for the weapon currently held in a hand (1.0 when unarmed
# or the model has no upgrade bonus).
func _hand_damage_mult(hand: String) -> float:
	var weapon := left_hand if hand == "left" else right_hand
	if weapon == null:
		return 1.0
	return float(_damage_mult_by_name.get(weapon.weapon_name, 1.0))


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
	call_deferred("_update_weapon_visuals")
	carry_updated.emit(carry)


# Returns the WeaponCore backing a weapon, creating it once per weapon name so a
# swapped-out weapon keeps its ammo/heat/cooldown when re-equipped. The core
# owns cooldown/ammo/heat/reload + projectile spawning; the manager keeps only
# input, aim and presentation.
func _core_for_weapon(weapon: WeaponPart) -> WeaponCore:
	if weapon == null:
		return null
	var name = weapon.weapon_name
	if not _cores.has(name):
		var core := WeaponCore.from_weapon(weapon)
		core.auto_reload = false
		core.manual_reload = true
		core.ammo_changed.connect(_forward_ammo_changed.bind(name))
		core.heat_changed.connect(_forward_heat_changed.bind(name))
		_cores[name] = core
	return _cores[name]


func _forward_ammo_changed(current: int, max_ammo: int, weapon_name: String) -> void:
	var hand = _hand_of_weapon(weapon_name)
	if not hand.is_empty():
		ammo_changed.emit(hand, current, max_ammo)


func _forward_heat_changed(current: float, max_heat: float, overheated: bool, weapon_name: String) -> void:
	var hand = _hand_of_weapon(weapon_name)
	if not hand.is_empty():
		heat_changed.emit(hand, current, max_heat, overheated)


func _hand_of_weapon(weapon_name: String) -> String:
	if left_hand and left_hand.weapon_name == weapon_name:
		return "left"
	if right_hand and right_hand.weapon_name == weapon_name:
		return "right"
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
	if not left_hand or not right_hand:
		_core_for_weapon(_fist()).tick(delta)

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

	if fire_left_holding:
		if left_hand:
			if left_hand.weapon_type != WeaponPart.WeaponType.SHIELD:
				_try_fire("left", left_hand)
		else:
			_try_fire("left", null)
	if fire_right_holding:
		if right_hand:
			if right_hand.weapon_type != WeaponPart.WeaponType.SHIELD:
				_try_fire("right", right_hand)
		else:
			_try_fire("right", null)

	# Physical shield plates never regenerate — a damaged plate stays damaged.


# ====================================================================
# INPUT
# ====================================================================

func _input(event: InputEvent) -> void:
	# The mech is ragdolled in its core-breach death window: the weapons are
	# dead (only the eject seat still works), so ignore every weapon input.
	var mecha = get_parent()
	if mecha != null:
		var hs = mecha.get_node_or_null("HealthSystem")
		if hs != null and bool(hs.get("is_destroyed")):
			return
	# While the F pickup-decision menu is open (real-time mode) the hands must not
	# fire/swap/drop — mouse clicks belong to the menu buttons, not the weapons.
	if get_tree() and get_tree().current_scene:
		var hud = get_tree().current_scene.get_node_or_null("WeaponHUD")
		if hud and hud.get("pickup_menu_open"):
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
			_drop_weapon("left")
		elif holding_right:
			_drop_weapon("right")

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
		if _fire_press("left"):
			return  # deferred for a possible dual charge, or consumed
		_commit_normal_fire("left")
	if event.is_action_released("fire_left"):
		fire_left_holding = false

	# --- FIRE / RELOAD RIGHT ---
	if event.is_action_pressed("fire_right"):
		if _fire_press("right"):
			return  # deferred for a possible dual charge, or consumed
		_commit_normal_fire("right")
	if event.is_action_released("fire_right"):
		fire_right_holding = false


func reload_weapon(hand: String) -> void:
	var is_left = (hand == "left")
	if is_left and reloading_left:
		return
	if not is_left and reloading_right:
		return

	var weapon: WeaponPart = left_hand if is_left else right_hand
	if weapon == null:
		return

	var ammo_type = weapon.get_ammo_type()
	if ammo_type == "none":
		return

	var current_mag = _get_ammo(weapon)
	var needed = weapon.max_ammo - current_mag
	if needed <= 0:
		return

	var reserve = get_battle_reserve(ammo_type)
	if reserve <= 0:
		EffectManager.spawn_damage_number(global_position + Vector3(0, 2.5, 0), 0, Color(1.0, 0.2, 0.2))
		return

	if is_left:
		reloading_left = true
	else:
		reloading_right = true

	var target_word: String = "RELOAD!"
	var char_count = target_word.length()
	var total_reload_time: float = 1.0
	var time_per_char = total_reload_time / float(char_count + 1)

	for i in range(1, char_count + 1):
		var partial_text = target_word.substr(0, i)
		reload_progress.emit(hand, partial_text, reserve, float(i) / float(char_count))
		await get_tree().create_timer(time_per_char).timeout
		var check_weapon = left_hand if is_left else right_hand
		if check_weapon != weapon:
			if is_left: reloading_left = false
			else: reloading_right = false
			return

	var refilled = consume_battle_reserve(ammo_type, needed)
	_core_for_weapon(weapon).ammo = current_mag + refilled

	if is_left:
		reloading_left = false
	else:
		reloading_right = false

	if AudioManager:
		AudioManager.play_reload_complete()

	ammo_changed.emit(hand, _get_ammo(weapon), weapon.max_ammo)
	EffectManager.spawn_damage_number(global_position + Vector3(0, 2.5, 0), refilled, Color(0.2, 1.0, 0.4))


# ====================================================================
# WEAPON SELECTION (1/3 + scroll)
# ====================================================================

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


func _scroll(hand: String, direction: int) -> void:
	if carry.is_empty():
		return

	var is_left = (hand == "left")
	var idx = _select_idx_left if is_left else _select_idx_right
	var new_idx = clampi(idx + direction, 0, carry.size() - 1)

	if new_idx == idx:
		return

	if is_left:
		_select_idx_left = new_idx
		_select_scrolled_left = true
	else:
		_select_idx_right = new_idx
		_select_scrolled_right = true

	# Preview: show highlighted weapon in hand (don't touch carry)
	var preview = carry[new_idx]
	if is_left:
		left_hand = preview
	else:
		right_hand = preview

	weapon_switched.emit(hand, preview.weapon_name)
	ammo_changed.emit(hand, _get_ammo(preview), preview.max_ammo)
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

	# Quick tap without scroll → cycle to next weapon
	if not did_scroll and hold_time < TAP_THRESHOLD and carry.size() > 1:
		var old_weapon = carry[idx]
		carry.remove_at(idx)
		carry.append(old_weapon)
		var new_weapon = carry[0]
		if is_left:
			left_hand = new_weapon
		else:
			right_hand = new_weapon
		carry.remove_at(0)
		_enforce_two_hand_grip()
		# Grip enforcement may holster the cycled weapon — report the real state.
		var w2 = left_hand if is_left else right_hand
		weapon_switched.emit(hand, w2.weapon_name if w2 else "Empty")
		if w2:
			ammo_changed.emit(hand, _get_ammo(w2), w2.max_ammo)
		carry_updated.emit(carry)
		_update_weapon_visuals()
		sync_loadout_to_global()
		return

	# Take the highlighted weapon out of carry into hand
	if idx < carry.size():
		if is_left:
			left_hand = carry[idx]
		else:
			right_hand = carry[idx]
		carry.remove_at(idx)

	_enforce_two_hand_grip()

	# The grip enforcement may have holstered the just-committed weapon when the
	# other hand holds a two-hand weapon — guard against a null hand afterwards.
	var w = left_hand if is_left else right_hand
	weapon_switched.emit(hand, w.weapon_name if w else "Empty")
	if w:
		ammo_changed.emit(hand, _get_ammo(w), w.max_ammo)
	carry_updated.emit(carry)
	_update_weapon_visuals()
	sync_loadout_to_global()


# ====================================================================
# DROP
# ====================================================================

func _drop_weapon(hand: String) -> void:
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
		target_type = "kinetic"

	# Ammo found mid-battle is added to the local battle reserve so it is usable
	# right away; unused leftovers return to the stash when combat ends.
	add_battle_reserve(target_type, amount)

	if target_weapon:
		var current = _get_ammo(target_weapon)
		ammo_changed.emit(hand if not hand.is_empty() else "left", current, target_weapon.max_ammo)


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

func _try_fire(hand: String, weapon: WeaponPart) -> void:
	# A destroyed arm frame cannot hold or fire anything on that hand — not the
	# weapon and not even a bare-fist punch (the arm is gone).
	if not _hand_usable(hand):
		return
	if weapon == null:
		# Empty hand: fall back to a bare-fist punch (unarmed melee). It obeys
		# the shared cooldown core so punches can't exceed the fist cadence.
		var fist := _fist()
		var fist_core := _core_for_weapon(fist)
		if fist_core == null or not fist_core.consume_shot():
			return
		_melee_attack(hand, fist)
		return
	if (hand == "left" and reloading_left) or (hand == "right" and reloading_right):
		return
	if weapon.weapon_type == WeaponPart.WeaponType.SHIELD:
		return

	var core = _core_for_weapon(weapon)
	if core == null or not core.can_fire():
		return

	# Melee keeps its custom lunge/hit animation but obeys the shared rules
	# (cooldown, ammo, heat) through the core.
	if weapon.weapon_type == WeaponPart.WeaponType.MELEE:
		if core.consume_shot():
			_melee_attack(hand, weapon)
		return

	var mecha = get_parent()
	if mecha == null:
		return
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var offset = Vector3(-0.6, 1.5, 0.5) if hand == "left" else Vector3(0.6, 1.5, 0.5)
	var spawn_pos = mecha.global_position + mecha.global_transform.basis * offset

	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	var ray_origin = cam.project_ray_origin(center)
	var ray_dir = cam.project_ray_normal(center)

	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 500.0)
	query.collision_mask = 10
	var result = space_state.intersect_ray(query)

	var target_point: Vector3
	if result:
		target_point = result["position"]
	else:
		target_point = ray_origin + ray_dir * 500.0

	var aim_dir = (target_point - spawn_pos).normalized()

	# Fire through the shared core: it consumes cooldown/ammo/heat and spawns the
	# projectile (bullet/missile/shotgun visuals handled by weapon_type). The
	# core applies this hand's upgrade multiplier to the projectile damage.
	core.damage_multiplier = _hand_damage_mult(hand)
	if core.try_fire(spawn_pos, aim_dir, false, mecha):
		_apply_recoil(weapon)
		AudioManager.play_weapon_sfx_with_override(weapon, spawn_pos)
		if weapon.weapon_type != WeaponPart.WeaponType.MISSILE:
			_spawn_shell_casing(spawn_pos, hand)


func _melee_attack(hand: String, weapon: WeaponPart) -> void:
	var mecha = get_parent()
	var cam = get_viewport().get_camera_3d()
	if cam == null or mecha == null:
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	var ray_origin = cam.project_ray_origin(center)
	var ray_dir = cam.project_ray_normal(center)

	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 500.0)
	query.collision_mask = 10
	var result = space_state.intersect_ray(query)

	var target_point: Vector3
	if result:
		target_point = result["position"]
	else:
		target_point = ray_origin + ray_dir * 500.0

	var dir = (target_point - mecha.global_position).normalized()
	dir.y = 0.0
	dir = dir.normalized()
	if dir.length() > 0.1:
		var target_angle = atan2(-dir.x, -dir.z)
		mecha.rotation.y = lerp_angle(mecha.rotation.y, target_angle, 0.3)

	# Eject spent shell casing for Pile Bunker / kinetic melee
	if weapon and (weapon.ammo_per_shot > 0 or weapon.weapon_name.to_lower().contains("pile") or weapon.get_ammo_type() != "none"):
		var spawn_pos = mecha.global_position + (Vector3(-0.6, 1.5, 0.5) if hand == "left" else Vector3(0.6, 1.5, 0.5))
		_spawn_shell_casing(spawn_pos, hand)
		
	# Execute lunging punch animation (Anticipation -> Thrust -> Camera Shake -> Recovery)
	_perform_pile_bunker_lunge_anim(mecha, dir, weapon)

	_spawn_melee_trail(mecha, dir, weapon)
	_check_melee_hit(mecha, dir, weapon.damage * _hand_damage_mult(hand), weapon)
	if weapon and weapon.weapon_name.to_lower().contains("pile"):
		AudioManager.play_pile_bunker_fire(mecha.global_position)
	else:
		# Per-weapon melee swing voice (fist whoosh / knife slash / blade ring).
		AudioManager.play_melee_swing(weapon, mecha.global_position)

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


# A fire press arrived. When BOTH sides fight melee (melee weapon, bare fist,
# or a destroyed-arm shoulder), the press is DEFERRED briefly: if the other fire
# button lands within DUAL_PRESS_WINDOW_MS, the two presses merge into one
# straight charge instead of two separate swings; otherwise the press commits
# as a normal fire when the window expires. Ranged hands never defer (a gun
# press is always an immediate shot). Returns true when the press was consumed
# by the deferral/charge path.
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
			fire_left_holding = true
			if left_hand:
				if left_hand.weapon_type == WeaponPart.WeaponType.SHIELD:
					_toggle_shield("left")
				else:
					_try_fire("left", left_hand)
			else:
				# Unarmed: bare-fist punch.
				_try_fire("left", null)
	else:
		if holding_reload or Input.is_action_pressed("reload"):
			reload_weapon("right")
		else:
			fire_right_holding = true
			if right_hand:
				if right_hand.weapon_type == WeaponPart.WeaponType.SHIELD:
					_toggle_shield("right")
				else:
					_try_fire("right", right_hand)
			else:
				# Unarmed: bare-fist punch.
				_try_fire("right", null)


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


func _check_melee_hit(mecha: Node3D, direction: Vector3, damage: float, weapon: WeaponPart = null) -> void:
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	var ray_origin = cam.project_ray_origin(center)
	var ray_dir = cam.project_ray_normal(center)

	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 10.0)
	query.collision_mask = 8
	var result = space_state.intersect_ray(query)

	var aim_point: Vector3
	if result:
		aim_point = result["position"]
	else:
		aim_point = ray_origin + ray_dir * 10.0

	var enemies = get_tree().get_nodes_in_group("enemy")
	# Forward auto-aim box: the swing connects to any enemy within the weapon's
	# forward reach (lunge + arm reach == range_distance) and within
	# MELEE_AUTO_AIM_WIDTH of the aim line. Reach uses the FORWARD projection so
	# an enemy at range but off to the side is still at range, and the lateral
	# width covers a mech body so a target filling the crosshair connects even
	# when its center is off the line.
	var lunge_dist = _melee_lunge_dist(weapon)
	var swing_range = lunge_dist + MELEE_HIT_REACH
	var aim2 := Vector2(direction.x, direction.z).normalized()
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var to_h := Vector2(enemy.global_position.x - mecha.global_position.x,
			enemy.global_position.z - mecha.global_position.z)
		var proj := to_h.dot(aim2)
		# A hair of grace past swing_range so an enemy at EXACTLY the weapon's
		# range isn't whiffed by float rounding.
		if proj < 0.1 or proj > swing_range + 0.05:
			continue
		var perp := absf(to_h.cross(aim2))
		if perp > MELEE_AUTO_AIM_WIDTH:
			continue
		# Melee hits carry the weapon's attack type (knife/pile bunker = pierce,
		# heat blade = heat, mace/fist/shoulder = blunt) so armor + shields can
		# match on it like any other attack.
		var melee_type := weapon.get_damage_type() if weapon != null else "blunt"
		if enemy.has_method("take_damage_at_point"):
			enemy.take_damage_at_point(damage, aim_point, melee_type)
		elif enemy.has_method("take_damage"):
			enemy.take_damage(damage, melee_type)
		melee_hit_landed.emit()
		if weapon != null and weapon.weapon_name.to_lower().contains("pile"):
			_apply_pile_hitstop()
		if weapon != null and weapon.impact > 0.0 and enemy.has_method("apply_impact"):
			enemy.apply_impact(weapon.impact, direction)
			EffectManager.spawn_damage_number(enemy.global_position + Vector3(0, 2.5, 0), damage, Color(1, 0.5, 0))
			if weapon and weapon.weapon_name.to_lower().contains("pile"):
				AudioManager.play_pile_bunker_hit(enemy.global_position)
			else:
				# Per-weapon melee hit voice (fist thud / knife crack / blade ring).
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
	if weapon == null or not weapon.two_handed:
		return false
	# Without an explicit hand (callers that only know the weapon), fall back to
	# whichever hand currently holds it.
	if hand == "":
		if left_hand == weapon:
			hand = "left"
		elif right_hand == weapon:
			hand = "right"
	return weapon.requires_two_hand(_hand_power(hand))


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


# ====================================================================
# RECOIL — pushes the shooter's mech back along the weapon's facing
# ====================================================================

func _apply_recoil(weapon: WeaponPart) -> void:
	if weapon == null or weapon.recoil_force <= 0.0:
		return
	var mecha = get_parent()
	if mecha == null:
		return
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	# Pull the mech backward along the camera aim direction.
	var cam_basis = cam.global_transform.basis
	var backward: Vector3 = cam_basis.z  # +Z faces AWAY from aim
	backward.y = 0.0
	if backward.length() > 0.01:
		backward = backward.normalized()
		var impulse: Vector3 = backward * weapon.recoil_force
		# Railguns use the heavy kick: a stronger push plus a stance-recovery
		# beat (decay slowed) so the mech visibly staggers and re-balances.
		if weapon.weapon_type == WeaponPart.WeaponType.RAILGUN \
				and mecha.has_method("apply_heavy_recoil_impulse"):
			mecha.apply_heavy_recoil_impulse(impulse)
		elif mecha.has_method("apply_recoil_impulse"):
			mecha.apply_recoil_impulse(impulse)

	# Camera shake proportional to recoil.
	if weapon.recoil_shake > 0.0:
		var rigs = get_tree().get_nodes_in_group("camera_rig")
		if not rigs.is_empty() and rigs[0].has_method("add_shake"):
			rigs[0].add_shake(weapon.recoil_shake)


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

func _spawn_shell_casing(spawn_pos: Vector3, hand: String) -> void:
	var mecha = get_parent()
	if mecha == null:
		return

	var side = -1.0 if hand == "left" else 1.0
	var right = mecha.global_transform.basis.x * side
	var shell_dir = (right + Vector3(0, 0.5, 0)).normalized()

	var shell = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.06, 0.04, 0.12)
	shell.mesh = box

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.7, 0.2, 1)
	mat.metallic = 0.8
	mat.roughness = 0.3
	shell.material_override = mat

	get_tree().current_scene.add_child(shell)
	shell.global_position = spawn_pos + right * 0.3 + Vector3(0, 0.2, 0)

	var tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(shell, "position",
		shell.position + shell_dir * randf_range(1.5, 3.0) + Vector3(0, randf_range(0.5, 1.5), 0),
		0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(shell, "rotation",
		Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5)),
		0.4)
	tween.chain().tween_property(shell, "position:y", -0.5, 0.4).set_ease(Tween.EASE_IN)
	tween.tween_callback(shell.queue_free).set_delay(0.6)

func _update_weapon_visuals() -> void:
	var mecha = get_parent() as Node3D
	if not mecha:
		return
	_update_hand_weapon_visual(mecha, "left", left_hand)
	_update_hand_weapon_visual(mecha, "right", right_hand)
	_update_carry_visuals(mecha)

func _update_hand_weapon_visual(mecha: Node3D, hand: String, weapon: WeaponPart) -> void:
	WeaponVisualFactory.mount_hand(mecha, hand, weapon, "WeaponMesh_" + hand)

# Renders the weapons carried on the mech's back (from the loadout).
func _update_carry_visuals(mecha: Node3D) -> void:
	WeaponVisualFactory.mount_carry(mecha, carry, "CarryWeapons")
