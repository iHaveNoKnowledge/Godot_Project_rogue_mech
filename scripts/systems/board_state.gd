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

# --- Theme & Objective ---
var board_theme_id: String = "suburb"
var board_objective_id: String = ""
var board_objective_progress: int = 0
var board_objective_required: int = 0
var board_objective_intro_consumed: bool = false

# --- Patrols ---
var board_patrols: Array = []
var board_patrol_engagement: int = -1
var pending_tile_clear: Vector2i = Vector2i(-1, -1)

# --- Heat & Wanted ---
var heat: int = 0
var wanted_level: int = 0
var wanted_escalation: int = 0

# --- Sector Progression ---
var current_sector: int = 1
var max_sectors: int = 3

# --- Hazard ---
var current_hazard: String = ""
var combat_tile_terrain: String = "plain"
const HAZARD_DUST_STORM: String = "dust_storm"
const HAZARD_TACTICAL_SMOG: String = "tactical_smog"
const HAZARD_EMP_ZONE: String = "emp_zone"
const DUST_STORM_ROLLER_DRAIN_MULT: float = 1.5
const DUST_STORM_SPEED_MULT: float = 0.85
const SMOG_HEAT_COOL_PENALTY: float = 0.5
const EMP_LOCK_ON_DISABLED: bool = true
const EMP_BACKUP_BLOCKED: bool = true

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
	board_patrols.clear()
	board_patrol_engagement = -1
	pending_tile_clear = Vector2i(-1, -1)
	heat = 0
	wanted_level = 0
	wanted_escalation = 0
	current_sector = 1
	current_hazard = ""
	combat_tile_terrain = "plain"
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
	run_notice = ""
	safehouse_upgrades.clear()
