class_name RunEventCatalogData
extends Resource

## Run event catalog database.
## Single source of truth for all board random events. Each event can be shared
## across every theme (empty "themes") or restricted to specific theme ids.
##
## Event entry shape:
## {
##   "id": "ambush", "name": "Ambush", "desc": "...",
##   "effect": "damage",            # effect type, see ThemeSystem.apply_event_effect
##   "amount": 20,                  # generic value (credits, damage %, turns, rep...)
##   "params": { ... },             # effect-specific extras (e.g. combat_type)
##   "themes": [],                  # empty = common to all themes
##   "min_reputation": 0,           # minimum run reputation to appear
##   "weight": 10,                  # relative selection weight
## }
##
## Data lives in resources/data/run_events.tres.
@export var events: Array = []
