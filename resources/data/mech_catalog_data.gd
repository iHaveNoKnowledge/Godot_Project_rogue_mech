class_name CatalogData
extends Resource

## Static catalog database — single source of truth for all stock items.
## Data lives in resources/data/mech_catalogs.tres.
##
## Shape (mirrors the old inline dictionaries in code):
##   armor_catalog:   { slot_name: [ {id, name, path, hp, armor, weight, color, type}, ... ] }
##   chassis_catalog: { chassis_id: {name, speed, max_weight, color} }
##   frame_catalog:   { slot_name: [ {id, name, hp, weight, type, carry_bonus}, ... ] }
##   attachment_catalog: [ {id, name, weight, power_cost, size, color}, ... ]

@export var armor_catalog: Dictionary = {}
@export var chassis_catalog: Dictionary = {}
@export var frame_catalog: Dictionary = {}
@export var attachment_catalog: Array = []
