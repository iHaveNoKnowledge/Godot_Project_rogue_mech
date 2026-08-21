class_name HangarState
extends RefCounted

## ---------------------------------------------------------------------------
## HANGAR STATE — hangar mech roster, fleet, and research.
##
## Extracted from GlobalData.  Owns:
##   • Hangar mech roster (built machines)
##   • Active hangar mech id
##   • Fleet roster
##   • Recruitable characters & pending duel
##   • Research projects & unlocked blueprints
## ---------------------------------------------------------------------------

const HANGAR_HARD_MAX := 12

# --- Hangar Roster ---
var hangar_mechs: Array = []
var active_hangar_mech_id: String = ""

# --- Fleet Roster ---
var fleet_roster: Array = []

# --- Recruitable Characters ---
var recruited_characters: Array = []
var pending_duel: Dictionary = {}
var duel_result_text: String = ""

# --- Research ---
var research_projects: Dictionary = {}
var research_unlocked: Array = []


func reset() -> void:
	hangar_mechs.clear()
	active_hangar_mech_id = ""
	fleet_roster.clear()
	recruited_characters.clear()
	pending_duel.clear()
	duel_result_text = ""
	research_projects.clear()
	research_unlocked.clear()
