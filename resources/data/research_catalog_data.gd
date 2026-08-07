class_name ResearchCatalogData
extends Resource

## Fleet / research catalog database.
## Single source of truth for:
##   - research_projects: blueprint research definitions. Each project consumes
##     data_cores (blueprints) to start, then takes research time (board moves +
##     combats) to complete and unlock a reward.
##   - ally_unit_templates: allied mech templates (our side) that can be added to
##     the fleet roster and fielded in combat as squadmates.
##
## Data lives in resources/data/research_catalogs.tres.

## Research project entry shape:
## {
##   "id": "bp_ally_gm", "name": "GM-II Blueprint",
##   "desc": "Standard-issue allied mobile suit (our side).",
##   "data_cores": 3,           # cores consumed when research starts
##   "research_time": 8,        # research points needed (board move = 1, combat = 2)
##   "reward_type": "unit",     # "unit" -> ally unit template, "frame"/"armor" -> gear
##   "reward_id": "ally_gm",
##   "reward_name": "GM-II",
## }
@export var research_projects: Array = []

## Ally unit template shape:
## {
##   "id": "ally_gm", "name": "GM-II",
##   "role": "Ranged Support",
##   "archetype": 1,             # reuse enemy archetypes (0=Rusher melee, 1=Ranged, 2=Heavy, 3=Support)
##   "move_speed": 4.0, "attack_range": 60.0,
##   "attack_damage": 14.0, "attack_cooldown": 0.8,
##   "armor_hp": 45.0, "frame_hp": 55.0,
##   "color": Color(0.3, 0.6, 0.9, 1),
##   "scene_path": "res://scenes/mecha/ally_dummy.tscn",
##   "fielded": true,            # whether this unit tags along into battle
## }
@export var ally_unit_templates: Array = []
