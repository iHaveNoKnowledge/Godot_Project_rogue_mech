class_name RunThemeCatalogData
extends Resource

## Run theme catalog database. Each theme defines the identity of a run:
## how the run starts (start), which events it can see (event ids), how it
## ends (ending) and global flow modifiers (flow).
##
## Theme entry shape:
## {
##   "id": "soldier", "name": "Fleet Soldier", "flavor": "...",
##   "start": {
##     "chassis_weights": { "standard": 50, "vanguard": 20, "titan": 15, "brawler": 10, "aegis": 5 },
##     "part_tier_weights": { "standard": 60, "medium": 25, "heavy": 10, "valkyrion": 5 },
##     "weapon_pool": [ "res://.../weapon_beam_rifle.tres", ... ],
##     "allies": { "templates": ["ally_gm", "ally_gunner"], "min": 1, "max": 2 },
##     "credits": [80, 200], "scrap": [0, 15], "data_cores": [0, 1]
##   },
##   "events": ["supply_drop", "political_ceasefire", ...],  # optional ids to force
##   "ending": {
##     "name": "Siege of the Capital",
##     "boss_waves": "soldier",      # matches spawn_manager wave-def key
##     "victory_text": "...",
##     "defeat_text": "..."
##   },
##   "flow": { "heat_rate": 1.0, "ceasefire_chance": 0.3 }
## }
##
## Data lives in resources/data/run_theme_catalogs.tres.
@export var themes: Array = []
