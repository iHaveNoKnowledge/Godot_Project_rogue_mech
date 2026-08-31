extends Node
class_name WarManager

## War Mode controller — battlefield state for the new War Mode.
## Keeps Board/Campaign save isolated (user request: no cross-save).

const SAVE_WAR_PATH := "user://save_war.json"

var is_active: bool = false
