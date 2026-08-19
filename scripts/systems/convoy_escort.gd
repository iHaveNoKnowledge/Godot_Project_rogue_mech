extends Node

## Convoy Escort & Defense System (GDD §7.4)
##
## Handles three convoy-related events:
## 1. Convoy Ambush — enemies attack the convoy on the board, triggers defense combat
## 2. Vehicle Breakdown — convoy breaks down, must defend in waves
## 3. Failure Consequence — if convoy is destroyed, lose all backups + forced pilot mode

signal convoy_damaged(hp: float, max_hp: float)
signal convoy_destroyed()
signal defense_wave_started(wave: int, total: int)


func _ready() -> void:
	EventBus.combat_ended.connect(_on_combat_ended)


func _on_combat_ended(victory: bool) -> void:
	# If defense combat ends, check if more waves remain.
	if GlobalData.convoy_defense_active:
		if victory:
			GlobalData.convoy_defense_current_wave += 1
			if GlobalData.convoy_defense_current_wave >= GlobalData.convoy_defense_waves:
				# Defense complete — convoy survives.
				GlobalData.convoy_defense_active = false
				GlobalData.run_notice = "Convoy defense successful! The truck is safe."
			else:
				# More waves to go.
				defense_wave_started.emit(
					GlobalData.convoy_defense_current_wave + 1,
					GlobalData.convoy_defense_waves
				)
				# Trigger next defense wave after a short delay.
				await get_tree().create_timer(2.0).timeout
				_start_defense_combat()
		else:
			# Defense failed — convoy takes damage.
			GlobalData.convoy_defense_active = false
			_damage_convoy(30.0)


## Triggers a convoy ambush event on the board.
func trigger_convoy_ambush() -> void:
	if GlobalData.convoy_destroyed:
		return
	# Announce the ambush.
	EventBus.event_triggered.emit({
		"name": "⚠ CONVOY AMBUSH",
		"effect": "none",
		"amount": 0,
		"desc": "Hostiles are attacking the supply truck! Defend the convoy!",
	})
	# Start defense combat with 2 waves.
	GlobalData.convoy_defense_waves = 2
	GlobalData.convoy_defense_current_wave = 0
	GlobalData.convoy_defense_active = true
	defense_wave_started.emit(1, 2)
	# Trigger defense combat after a short delay.
	await get_tree().create_timer(1.5).timeout
	_start_defense_combat()


## Triggers a vehicle breakdown event on the board.
func trigger_vehicle_breakdown() -> void:
	if GlobalData.convoy_destroyed:
		return
	# Announce the breakdown.
	EventBus.event_triggered.emit({
		"name": "🔧 VEHICLE BREAKDOWN",
		"effect": "none",
		"amount": 0,
		"desc": "The supply truck has broken down! Defend it from incoming hostiles!",
	})
	# Start defense combat with 3 waves (harder than ambush).
	GlobalData.convoy_defense_waves = 3
	GlobalData.convoy_defense_current_wave = 0
	GlobalData.convoy_defense_active = true
	defense_wave_started.emit(1, 3)
	# Trigger defense combat after a short delay.
	await get_tree().create_timer(1.5).timeout
	_start_defense_combat()


## Damages the convoy. If HP reaches 0, the convoy is destroyed.
func _damage_convoy(amount: float) -> void:
	GlobalData.convoy_hp = maxf(GlobalData.convoy_hp - amount, 0.0)
	convoy_damaged.emit(GlobalData.convoy_hp, GlobalData.convoy_hp_max)
	if GlobalData.convoy_hp <= 0.0:
		_destroy_convoy()


## Destroys the convoy — all backup mechs lost, forced pilot mode.
func _destroy_convoy() -> void:
	GlobalData.convoy_destroyed = true
	GlobalData.mech_less = true
	# Remove all backup mechs from hangar.
	var backups_to_remove = []
	for mech in GlobalData.hangar_mechs:
		if str(mech.get("id", "")) != GlobalData.active_hangar_mech_id:
			backups_to_remove.append(mech)
	for mech in backups_to_remove:
		GlobalData.hangar_mechs.erase(mech)
	convoy_destroyed.emit()
	GlobalData.run_notice = "The convoy has been destroyed! All backup mechs lost. You are on foot."


func _start_defense_combat() -> void:
	# Set the combat type and enter combat.
	GameManager.combat_node_type = "defense"
	GameManager.enter_combat("grunt")
