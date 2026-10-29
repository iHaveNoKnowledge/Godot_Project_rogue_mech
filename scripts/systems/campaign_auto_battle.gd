class_name CampaignAutoBattle
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN AUTO-BATTLE RESOLVER — Phase C8-D (single source of the formula).
##
## Audit evidence: the attrition loop was duplicated verbatim in
## `CampaignBaseDefense._try_player_force_resolution` and
## `CampaignPlayerForceAssault.attack`. Two copies of a balance formula drift
## the moment one side is tuned, so the loop now lives here once and both
## callers delegate. This module is PURE: no registries, no mutation, no
## signals, no turn state — it only turns two strengths into an outcome.
##
## Balance constants are the tuning surface (spec §44 keeps exact numbers
## PROPOSED). Values are locked by `campaign_auto_battle_verify` and tuned
## against a scripted campaign playthrough (tools/campaign_balance_sim).
## ---------------------------------------------------------------------------

## Each round, a side loses this share of the OPPONENT's current strength
## (rounded up, minimum 1) — simultaneous, so no side gets a first-strike edge.
const ATTRITION_RATIO := 0.2

## Hard cap on rounds; a fight that survives this many rounds is decided by
## whoever has more strength left (ties favour the defender).
const MAX_ROUNDS := 5


## Simulates one engagement. Deterministic: identical inputs give identical
## outputs, with no RNG and no hidden state.
##   defender_strength / attacker_strength: non-negative integers.
## Returns {rounds, defender_remaining, attacker_remaining, defender_loss,
## attacker_loss, winner} where winner is "defender", "attacker",
## "mutual_destruction" or "stalemate".
static func simulate(defender_strength: int, attacker_strength: int,
		ratio: float = ATTRITION_RATIO, max_rounds: int = MAX_ROUNDS) -> Dictionary:
	var defender := maxi(defender_strength, 0)
	var attacker := maxi(attacker_strength, 0)
	var def_start := defender
	var att_start := attacker
	var rounds := 0
	var effective_ratio := clampf(ratio, 0.01, 1.0)
	var cap := maxi(max_rounds, 1)
	while rounds < cap and defender > 0 and attacker > 0:
		var attacker_loss := maxi(1, int(ceil(float(defender) * effective_ratio)))
		var defender_loss := maxi(1, int(ceil(float(attacker) * effective_ratio)))
		attacker = maxi(attacker - attacker_loss, 0)
		defender = maxi(defender - defender_loss, 0)
		rounds += 1

	var winner := "stalemate"
	if defender == 0 and attacker == 0:
		winner = "mutual_destruction"
	elif attacker == 0:
		winner = "defender"
	elif defender == 0:
		winner = "attacker"
	elif defender > attacker:
		winner = "defender"
	elif attacker > defender:
		winner = "attacker"
	return {
		"rounds": rounds,
		"defender_remaining": defender,
		"attacker_remaining": attacker,
		"defender_loss": def_start - defender,
		"attacker_loss": att_start - attacker,
		"winner": winner,
	}


## Proportional unit losses for a force that lost `strength_loss` of
## `start_strength`. Losing everything loses every unit; otherwise the loss is
## floored (never invents survivors).
static func unit_loss(units: int, start_strength: int, strength_loss: int) -> int:
	var total_units := maxi(units, 0)
	var total_strength := maxi(start_strength, 1)
	var loss := clampi(strength_loss, 0, total_strength)
	if loss == 0:
		return 0
	if loss >= total_strength:
		return total_units
	return clampi(int(floor(float(total_units) * float(loss) / float(total_strength))), 0, total_units)
