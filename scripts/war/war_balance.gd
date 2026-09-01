extends RefCounted
class_name WarBalance

## Balance constants for War Mode (Phase3 Polish) — per PLAN.md 11

const ORIGINAL_COST_CREDITS: int = 800
const ORIGINAL_COST_SCRAP: int = 200
const MASS_COST_CREDITS: int = 400
const MASS_COST_SCRAP: int = 80
const MASS_STAT_RATIO: float = 0.75

const DROP_RATES: Dictionary = {
	"part": 0.30,
	"frame": 0.20,
	"module": 0.20,
	"weapon": 0.15,
	"full_blueprint": 0.08,
	"whole_mech": 0.02,
}

const BARRACKS_CAPACITY: Dictionary = {
	1: 4,
	2: 8,
	3: 12,
}

const CARRIER_CAPACITY: int = 2
const HQ_SHIELD_REDUCTION: float = 0.9
const HQ_SHIELD_RADIUS: float = 100.0
const HQ_SHIELD_TIME: float = 600.0 # 10 min

const SALVAGE_DROP_CHANCE: float = 0.45
const MERCHANT_INTERVAL: Vector2 = Vector2(120, 180)
const PRODUCTION_TIME: Vector2 = Vector2(60, 180)

const DEPLOY_CAPS: Dictionary = {"line": 5, "strike": 3, "iron": 3, "valkyrion": 1}
const DEPLOY_COOLDOWNS: Dictionary = {"line": 30.0, "strike": 60.0, "iron": 60.0, "valkyrion": 180.0}
const ACE_RIGHT_TIMEOUT: float = 30.0
