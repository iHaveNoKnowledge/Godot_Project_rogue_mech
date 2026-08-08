class_name EnemyFactionSystem
extends RefCounted

# -----------------------------------------------------------------------------
# ENEMY TECH ESCALATION + SPY / DATA THEFT + RESEARCH NODE LIFECYCLE
# Enemy-side progression extracted from GlobalData. The enemy reverse-engineers
# our mech over time, probes us with spies, and spins up a research base node
# the player must destroy. GlobalData keeps thin facades for all callers.
#
# - enemy_tech_tier: the enemy's current standard (new unit tier). It rises one
#   step whenever we win a battle DECISIVELY (we took at most 50% of our
#   combined fielded HP in damage). Decisive wins prove our gear works; the
#   enemy copies it for the next deployment.
# - When enough mech data is stolen, the enemy spins up a research base node on
#   the board. If it completes, the enemy fields one of three upgraded unit
#   types (grunt MKII / special ace / gundam copy). If destroyed first, the
#   player salvages only a partial grunt upgrade.
# -----------------------------------------------------------------------------


# Per-theme escalation tuning; falls back to sensible defaults.
static func get_escalation_config() -> Dictionary:
	var theme = ThemeSystem.get_run_theme()
	var flow: Dictionary = theme.get("flow", {})
	return {
		"max_tier": int(flow.get("escalation_max_tier", 4)),
		"hp_per_tier": float(flow.get("escalation_hp_per_tier", 0.35)),
		"spy_base_chance": float(flow.get("escalation_spy_base_chance", 0.05)),
		"spy_chance_per_tier": float(flow.get("escalation_spy_chance_per_tier", 0.06)),
	}


# Called when a battle ends. The enemy tiers up one step when we win a battle
# DECISIVELY — i.e. we took at most 50% of our combined fielded HP in damage.
# Decisive wins prove our gear works, so the enemy copies it. Non-decisive
# wins or losses don't escalate (our build barely worked / we failed).
static func on_combat_ended_for_tech(victory: bool) -> void:
	if not victory:
		return
	var cfg := get_escalation_config()
	if GlobalData.last_combat_damage_ratio <= GlobalData.DECISIVE_VICTORY_RATIO:
		_try_escalate(cfg)


static func _try_escalate(cfg: Dictionary) -> void:
	var max_tier := int(cfg.get("max_tier", 4))
	if GlobalData.enemy_tech_tier >= max_tier:
		return
	GlobalData.enemy_tech_tier = mini(GlobalData.enemy_tech_tier + 1, max_tier)
	GlobalData.pending_escalation_event = true
	EventBus.enemy_tech_escalated.emit(GlobalData.enemy_tech_tier)


# Returns true once so the board can surface the "enemy upgraded" popup when
# the player returns from combat.
static func consume_pending_escalation_event() -> bool:
	var had_pending := GlobalData.pending_escalation_event
	GlobalData.pending_escalation_event = false
	return had_pending


# Multiplier applied to freshly spawned enemy HP/damage based on tech tier.
static func get_enemy_tech_multiplier() -> float:
	var cfg := get_escalation_config()
	return 1.0 + float(GlobalData.enemy_tech_tier - 1) * float(cfg.get("hp_per_tier", 0.35))


# Combined spawn scaling including the partial grunt upgrades salvaged from
# destroyed research nodes. Grunts get tougher even without a full tier-up.
static func get_enemy_grunt_multiplier() -> float:
	return get_enemy_tech_multiplier() + float(GlobalData.enemy_grunt_upgrade_level) * 0.10


# Probability that the enemy attempts a spy this move (0..1).
static func get_spy_attempt_chance() -> float:
	var cfg := get_escalation_config()
	return clampf(
		float(cfg.get("spy_base_chance", 0.05))
		+ float(GlobalData.enemy_tech_tier - 1) * float(cfg.get("spy_chance_per_tier", 0.06)),
		0.0,
		1.0
	)


# Rolls a full spy event for the current board move. Returns a Dictionary the
# board can surface. On success, enemy_research_progress is bumped.
static func roll_spy_event() -> Dictionary:
	var chance := get_spy_attempt_chance()
	if randf() > chance:
		return {}
	var counter := FleetSystem.get_spy_counter_chance()
	var caught := randf() < counter
	if caught:
		var bounty := 20 + int(randf() * 30)
		GlobalData.credits += bounty
		return {
			"name": "SPY CAUGHT",
			"effect": "none",
			"amount": 0,
			"desc": "Your fleet security intercepted an enemy spy and captured its gear! +%d credits." % bounty,
		}
	GlobalData.enemy_research_progress = minf(GlobalData.enemy_research_progress + 1.0, _get_enemy_research_cap())
	var stolen = {
		"name": "DATA STOLEN",
		"effect": "none",
		"amount": 0,
		"desc": "An enemy spy slipped past your security and stole mech data! The enemy has started researching a counter-unit.",
	}
	if GlobalData.enemy_research_progress >= _get_enemy_research_cap():
		GlobalData.enemy_research_progress = 0.0
		GlobalData.enemy_base_active = true
		GlobalData.enemy_base_progress = 0.0
		GlobalData.pending_enemy_base_spawn = true
		stolen["desc"] = "The enemy's stolen data has coalesced into a research base on the sector map! Destroy it before they finish a counter-unit."
	return stolen


static func _get_enemy_research_cap() -> float:
	return 2.0


# -----------------------------------------------------------------------------
# ENEMY RESEARCH NODE LIFECYCLE — the spawned board node and its outcome.
# -----------------------------------------------------------------------------

# Called by the board once it has physically placed the enemy_base tile.
static func consume_enemy_base_spawn_request() -> bool:
	var was_pending := GlobalData.pending_enemy_base_spawn
	GlobalData.pending_enemy_base_spawn = false
	return was_pending


# Advance the research node's counter-unit progress (1 per board move).
# Returns true when the enemy completes their counter-unit.
static func tick_enemy_base_progress(points: float) -> bool:
	if not GlobalData.enemy_base_active:
		return false
	GlobalData.enemy_base_progress = minf(GlobalData.enemy_base_progress + points, GlobalData.enemy_base_required)
	if GlobalData.enemy_base_progress >= GlobalData.enemy_base_required:
		_enemy_base_completed()
		return true
	return false


static func _enemy_base_completed() -> void:
	GlobalData.enemy_base_active = false
	GlobalData.pending_enemy_base_tile_reset = GlobalData.enemy_base_tile_pos
	GlobalData.enemy_base_tile_pos = Vector2i(-1, -1)
	GlobalData.enemy_copy_outcome = _roll_enemy_base_outcome()
	_apply_enemy_base_outcome(GlobalData.enemy_copy_outcome)
	GlobalData.pending_enemy_base_outcome = true


# The player reached and destroyed the node. The enemy only salvages a partial
# grunt upgrade instead of a full counter-unit.
static func destroy_enemy_base() -> void:
	GlobalData.enemy_base_active = false
	GlobalData.enemy_base_progress = 0.0
	GlobalData.pending_enemy_base_tile_reset = GlobalData.enemy_base_tile_pos
	GlobalData.enemy_base_tile_pos = Vector2i(-1, -1)
	GlobalData.enemy_grunt_upgrade_level += 1
	GlobalData.pending_enemy_base_destroyed = true


# Returns the board tile position that must be reset (consumed once), or
# Vector2i(-1, -1) when there is nothing to reset.
static func consume_enemy_base_tile_reset() -> Vector2i:
	var pos := GlobalData.pending_enemy_base_tile_reset
	GlobalData.pending_enemy_base_tile_reset = Vector2i(-1, -1)
	return pos


static func consume_pending_enemy_base_outcome() -> bool:
	var was_pending := GlobalData.pending_enemy_base_outcome
	GlobalData.pending_enemy_base_outcome = false
	return was_pending


static func consume_pending_enemy_base_destroyed() -> bool:
	var was_pending := GlobalData.pending_enemy_base_destroyed
	GlobalData.pending_enemy_base_destroyed = false
	return was_pending


# Outcome probabilities shift toward stronger copies as the enemy tier rises.
static func _roll_enemy_base_outcome() -> String:
	var cfg := get_escalation_config()
	var max_tier := int(cfg.get("max_tier", 4))
	var tier_factor := clampf(float(GlobalData.enemy_tech_tier) / float(maxf(max_tier, 1)), 0.0, 1.0)
	var mk2_weight := int(lerpf(50.0, 25.0, tier_factor))
	var special_weight := int(lerpf(35.0, 35.0, tier_factor))
	var copy_weight := int(lerpf(15.0, 40.0, tier_factor))
	var total := mk2_weight + special_weight + copy_weight
	var roll := randi() % maxi(total, 1)
	if roll < mk2_weight:
		return "grunt_mk2"
	if roll < mk2_weight + special_weight:
		return "special_ace"
	return "gundam_copy"


static func _apply_enemy_base_outcome(outcome: String) -> void:
	match outcome:
		"grunt_mk2":
			GlobalData.enemy_grunt_upgrade_level += 2
		"special_ace":
			GlobalData.enemy_special_units.append({"kind": "special_ace", "source": "research_node"})
			_add_stalking_ace("special_ace")
		"gundam_copy":
			GlobalData.enemy_special_units.append({"kind": "gundam_copy", "source": "research_node"})
			_add_stalking_ace("gundam_copy")


# A completed research node deploys its counter-unit as a stalking ace that
# hunts the player across the board. Once deployed it starts accumulating
# ambush chance with every move and will force a fight.
static func _add_stalking_ace(ace_kind: String) -> void:
	if not GlobalData.stalking_aces.has(ace_kind):
		GlobalData.stalking_aces.append(ace_kind)
