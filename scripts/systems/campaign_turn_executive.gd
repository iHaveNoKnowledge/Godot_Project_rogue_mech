class_name CampaignTurnExecutive
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN TURN EXECUTIVE — authoritative entry point for one world turn.
##
## Phase 1 (Campaign V2): establishes the architectural authority
## "one campaign turn = one controlled world progression transaction".
##
## Distinct concepts (NOT merged here — see task §4):
##   Campaign Turn  — this counter + deterministic world-tick sequence.
##   Board Day      — GlobalData.board.board_day / time_hour calendar.
##   Player Step    — a single board cell move (PatrolSystem.advance_step_turn).
##   MP Enemy Turn  — BoardManager._end_turn (PatrolSystem.advance_day).
##   Combat Turn    — GlobalData._on_combat_ended resolution path.
##
## In Phase 1 a campaign turn corresponds to one calendar-day world tick and is
## invoked from BoardManager._advance_calendar_day. Step-scale, MP-scale and
## combat-scale progression keep their existing entries (documented below) and
## must NOT be routed through here unless existing rules require it.
##
## Turn entry-point map (audited):
##   _try_step            -> on_player_step_heat + advance_step_turn (STEP — kept)
##   _end_turn (MP spent) -> PatrolSystem.advance_day (MP-TURN — kept)
##   _advance_calendar_day -> THIS EXECUTIVE (DAY — migrated, Phase 1)
##   _on_combat_ended     -> faction 0.5d + victory research (COMBAT — kept)
##   advance_breakdown_turn (breakdown repair — kept)
##
## Execution contract: re-entry guarded, exactly-once per invocation, fixed
## phase order mirroring the pre-migration call order in _advance_calendar_day
## (economy -> spy/base -> board_day_ended fan-out -> rival -> era -> scavenger)
## so gameplay semantics are preserved bit-for-bit.
## ---------------------------------------------------------------------------

const PHASE_BEGIN := "begin_turn"
const PHASE_FACTION_ECONOMY := "faction_economy"
const PHASE_SPY := "spy"
const PHASE_ENEMY_BASE := "enemy_base"
const PHASE_COMPATIBILITY := "board_day_compatibility"
const PHASE_RIVAL := "rival"
const PHASE_ERA := "era"
const PHASE_SCAVENGER := "scavenger"
const PHASE_END := "end_turn"

const PHASE_ORDER: Array[String] = [
	PHASE_BEGIN,
	PHASE_FACTION_ECONOMY,
	PHASE_SPY,
	PHASE_ENEMY_BASE,
	PHASE_COMPATIBILITY,
	PHASE_RIVAL,
	PHASE_ERA,
	PHASE_SCAVENGER,
	PHASE_END,
]

static var _campaign_turn: int = 0
static var _executing: bool = false
static var _last_receipt: Dictionary = {}
static var _phase_call_counts: Dictionary = {}


## Monotonic world-turn counter. Independent from board_day / time_hour.
static func get_turn() -> int:
	return _campaign_turn


## True while a turn is executing (re-entry guard window).
static func is_executing() -> bool:
	return _executing


## Receipt of the most recently completed turn ({} before the first turn).
static func get_last_receipt() -> Dictionary:
	return _last_receipt.duplicate(true)


## How many times a phase has executed (exactly-once instrumentation).
static func get_phase_call_count(phase: String) -> int:
	return int(_phase_call_counts.get(phase, 0))


## Advances one campaign turn through every applicable world-tick phase.
##
## reason: metadata recorded in the receipt (e.g. "board_day").
## opts:
##   "day_boundary" (bool, default true) — run day-scale phases (economy,
##       board_day_ended fan-out). False = counter-only turn that never forces
##       board_day semantics (finer-grained future use).
##   "world_turns" (int, default 1) — turns passed to rival/era simulation.
##   "enemy_base_points" (float, default 1.0) — progress points for the
##       enemy research node (mirrors the pre-migration tick of 1.0/day).
##   "spy_roll" (bool, default true) — roll the enemy spy event.
##   "board_tiles" (Dictionary, default {}) — board nodes for the scavenger
##       phase; empty means the phase is reported skipped (headless/tests).
##
## Returns a receipt: {ok, turn, reason, phases, spy_event,
## enemy_base_spawn_requested, enemy_base_completed, rival, era,
## scavenger_events, ...}. A nested call while executing returns
## {ok:false, error:"reentrant"} WITHOUT incrementing the counter.
static func advance_campaign_turn(reason: String = "", opts: Dictionary = {}) -> Dictionary:
	if _executing:
		return {
			"ok": false,
			"error": "reentrant",
			"turn": _campaign_turn,
			"reason": reason,
			"phases": [],
		}
	_executing = true
	_campaign_turn += 1
	var turn := _campaign_turn
	var day_boundary := bool(opts.get("day_boundary", true))
	var world_turns := maxi(int(opts.get("world_turns", 1)), 1)

	var phases: Array = []
	var receipt := {
		"ok": true,
		"turn": turn,
		"reason": reason,
		"phases": phases,
	}

	_count_phase(PHASE_BEGIN)
	phases.append(PHASE_BEGIN)

	# Faction/world economy (pre-migration: BoardManager._advance_calendar_day).
	if day_boundary:
		FactionEconomySystem.advance_day_economy()
		_count_phase(PHASE_FACTION_ECONOMY)
		phases.append(PHASE_FACTION_ECONOMY)
	else:
		receipt["faction_economy_skipped"] = true

	# Enemy spy roll (pre-migration: same caller, emitted as event there).
	var spy_event := {}
	if day_boundary and bool(opts.get("spy_roll", true)):
		spy_event = EnemyFactionSystem.roll_spy_event()
		_count_phase(PHASE_SPY)
		phases.append(PHASE_SPY)
	else:
		receipt["spy_skipped"] = true
	receipt["spy_event"] = spy_event

	# Enemy research-node lifecycle (pre-migration: same caller).
	var base_spawned := false
	var base_completed := false
	if day_boundary:
		base_spawned = EnemyFactionSystem.consume_enemy_base_spawn_request()
		base_completed = EnemyFactionSystem.tick_enemy_base_progress(
			float(opts.get("enemy_base_points", 1.0))
		)
		_count_phase(PHASE_ENEMY_BASE)
		phases.append(PHASE_ENEMY_BASE)
	else:
		receipt["enemy_base_skipped"] = true
	receipt["enemy_base_spawn_requested"] = base_spawned
	receipt["enemy_base_completed"] = base_completed

	# Compatibility fan-out. Existing subscribers keep their bodies unchanged:
	# GlobalData (fuel day tick, research dispatch, recruit recovery, faction
	# research tick) and HeatWantedSystem (heat/notoriety decay).
	if day_boundary:
		EventBus.board_day_ended.emit()
		_count_phase(PHASE_COMPATIBILITY)
		phases.append(PHASE_COMPATIBILITY)
	else:
		receipt["compatibility_skipped"] = true

	# Rival behind-the-scenes simulation (pre-migration: after the emit).
	var rival_result := {}
	if day_boundary:
		rival_result = RivalProgressionSystem.advance_rival_turn(world_turns)
		_count_phase(PHASE_RIVAL)
		phases.append(PHASE_RIVAL)
	else:
		receipt["rival_skipped"] = true
	receipt["rival"] = rival_result

	# War era progression (pre-migration: after the emit).
	var era_result := {}
	if day_boundary:
		era_result = EraProgressionSystem.advance_war_turn(world_turns)
		_count_phase(PHASE_ERA)
		phases.append(PHASE_ERA)
	else:
		receipt["era_skipped"] = true
	receipt["era"] = era_result

	# Scavenger outpost growth / fleet dispatches (pre-migration: after era).
	# Needs live board tiles; without them the phase is skipped, not faked.
	var scav_events: Array = []
	var tiles = opts.get("board_tiles", {})
	if day_boundary and tiles is Dictionary and not (tiles as Dictionary).is_empty():
		scav_events = ScavengerSystem.advance_turn(tiles)
		_count_phase(PHASE_SCAVENGER)
		phases.append(PHASE_SCAVENGER)
	else:
		receipt["scavenger_skipped"] = true
	receipt["scavenger_events"] = scav_events

	_count_phase(PHASE_END)
	phases.append(PHASE_END)

	_last_receipt = receipt.duplicate(true)
	_executing = false
	if EventBus.has_signal("campaign_turn_completed"):
		EventBus.campaign_turn_completed.emit(turn, reason)
	return receipt


## Persists the counter. SaveGameIO stores it as a plain int field.
static func serialize_turn() -> int:
	return _campaign_turn


## Restores the counter (missing/invalid values reset to 0 — legacy saves
## carry no field and load as turn 0, same as a fresh run).
static func deserialize_campaign_turn(value: Variant) -> void:
	reset()
	if value is int and not (value is bool):
		_campaign_turn = maxi(int(value), 0)
	elif value is float:
		_campaign_turn = maxi(int(value), 0)


## Full reset: new runs, test isolation, and guard recovery. Idempotent.
static func reset() -> void:
	_campaign_turn = 0
	_executing = false
	_last_receipt = {}
	_phase_call_counts = {}


static func _count_phase(phase: String) -> void:
	_phase_call_counts[phase] = int(_phase_call_counts.get(phase, 0)) + 1
