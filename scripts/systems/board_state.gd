class_name BoardState
extends RefCounted

## ---------------------------------------------------------------------------
## BOARD STATE — open-grid board progression, movement points, and sector data.
##
## Extracted from GlobalData.  Owns:
##   • Board grid, current tile, seed
##   • Movement points (MP) and day counter
##   • Board theme, objectives, patrols
##   • Heat / Wanted level
##   • Sector progression
##   • Tactical pressure (patrol alert, ambush, bait)
##   • Hazard state
##   • Mid-battle injection timers
##   • Convoy escort / defense
##   • Run notice
## ---------------------------------------------------------------------------

# --- Grid & Position ---
var board_grid: Array = []
var current_tile: Vector2i = Vector2i.ZERO
var board_seed: int = 0
var player_last_dir: Vector2i = Vector2i(1, 0)

# --- Movement Points & Day ---
var board_mp_max: int = 8
var board_mp: int = 8
var board_day: int = 1
var time_hour: float = 8.0  # GDD §3.1: 24-hour clock (0-23)

# --- Theme, Objective & Extraction Contract ---
var board_theme_id: String = "suburb"
var board_objective_id: String = ""
var board_objective_progress: int = 0
var board_objective_required: int = 0
var board_objective_intro_consumed: bool = false
var active_contract: Dictionary = {}
var primary_objective_done: bool = false
var secondary_objectives_status: Dictionary = {} # id -> bool
var extraction_zone_pos: Vector2i = Vector2i(-1, -1)
var extraction_unlocked: bool = false
var extraction_min_heat: int = 1
var extraction_max_heat: int = 5
var mission_step_count: int = 0
var abandoned_mech_wrecks: Dictionary = {} # Vector2i (serialized as "x,y") -> Dictionary of mech data

# --- Patrols ---
var board_patrols: Array = []
var board_patrol_engagement: int = -1
var pending_tile_clear: Vector2i = Vector2i(-1, -1)

# --- Heat & Wanted (1-5 Star System) ---
var heat: int = 0
var wanted_level: int = 1
var wanted_escalation: int = 0

# --- Sector Progression ---
var current_sector: int = 1
var max_sectors: int = 3

# --- Hazard ---
var current_hazard: String = ""
var combat_tile_terrain: String = "plain"
var combat_tile_sub_zone: String = ""
const HAZARD_DUST_STORM: String = "dust_storm"
const HAZARD_TACTICAL_SMOG: String = "tactical_smog"
const HAZARD_EMP_ZONE: String = "emp_zone"
# Weather hazards (GDD extended)
const HAZARD_RAIN: String = "rain"
const HAZARD_SANDSTORM: String = "sandstorm"
const HAZARD_FOG: String = "fog"
const DUST_STORM_ROLLER_DRAIN_MULT: float = 1.5
const DUST_STORM_SPEED_MULT: float = 0.85
const SMOG_HEAT_COOL_PENALTY: float = 0.5
const EMP_LOCK_ON_DISABLED: bool = true
const EMP_BACKUP_BLOCKED: bool = true
# Weather movement penalties
const RAIN_SPEED_MULT: float = 0.80          # Wet ground, reduced traction
const RAIN_FUEL_DRAIN_MULT: float = 1.3       # Engine works harder in rain
const RAIN_EWAR_JAM_PENALTY: float = 0.5      # Rain dampens EWar signal range
const SANDSTORM_SPEED_MULT: float = 0.65      # Heavy sand resistance
const SANDSTORM_FUEL_DRAIN_MULT: float = 1.6   # Extreme engine strain
const SANDSTORM_VISIBILITY_MULT: float = 0.5   # Half visibility range
const FOG_SPEED_MULT: float = 0.90            # Slight slowdown from caution
const FOG_VISIBILITY_MULT: float = 0.35       # Very low visibility
const FOG_STEALTH_BONUS: float = 0.4          # Patrols harder to detect you

# --- Arena ---
var current_arena_size: float = 240.0

# --- Tactical Pressure ---
var patrol_last_seen: Vector2i = Vector2i(-1, -1)
var patrol_alert: int = 0
var ambush_pincer: bool = false
var consumed_bait: Array = []

# --- Mid-Battle Injection ---
var mid_battle_reinforcements_active: bool = false
var mid_battle_reinforcements_timer: float = 0.0
var mid_battle_reinforcements_delay: float = 20.0
var mid_battle_countdown_active: bool = false
var mid_battle_countdown_timer: float = 0.0
var mid_battle_countdown_max: float = 45.0

# --- Convoy Escort & Defense ---
var convoy_hp: float = 100.0
var convoy_hp_max: float = 100.0
var convoy_defense_waves: int = 0
var convoy_defense_current_wave: int = 0
var convoy_defense_active: bool = false
var convoy_destroyed: bool = false
var convoy_breakdown_turns: int = 0

# --- Run Notice ---
var run_notice: String = ""

# --- Safehouse ---
var safehouse_upgrades: Array = []


func reset() -> void:
	board_grid.clear()
	current_tile = Vector2i.ZERO
	board_seed = randi()
	player_last_dir = Vector2i(1, 0)
	board_mp_max = 8
	board_mp = 8
	board_day = 1
	time_hour = 8.0
	board_theme_id = "suburb"
	var default_obj = BoardConfig.get_objective("suburb")
	board_objective_id = default_obj["id"]
	board_objective_progress = 0
	board_objective_required = default_obj["required"]
	board_objective_intro_consumed = false
	active_contract.clear()
	primary_objective_done = false
	secondary_objectives_status.clear()
	extraction_zone_pos = Vector2i(-1, -1)
	extraction_unlocked = false
	extraction_min_heat = 1
	extraction_max_heat = 5
	mission_step_count = 0
	abandoned_mech_wrecks.clear()
	board_patrols.clear()
	board_patrol_engagement = -1
	pending_tile_clear = Vector2i(-1, -1)
	heat = 0
	wanted_level = 1
	wanted_escalation = 0
	current_sector = 1
	current_hazard = ""
	combat_tile_terrain = "plain"
	combat_tile_sub_zone = ""
	current_arena_size = 240.0
	patrol_last_seen = Vector2i(-1, -1)
	patrol_alert = 0
	ambush_pincer = false
	consumed_bait.clear()
	mid_battle_reinforcements_active = false
	mid_battle_reinforcements_timer = 0.0
	mid_battle_countdown_active = false
	mid_battle_countdown_timer = 0.0
	convoy_hp = 100.0
	convoy_hp_max = 100.0
	convoy_defense_waves = 0
	convoy_defense_current_wave = 0
	convoy_defense_active = false
	convoy_destroyed = false
	convoy_breakdown_turns = 0
	run_notice = ""
	safehouse_upgrades.clear()
