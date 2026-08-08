class_name CombatStatsSystem
extends RefCounted

# -----------------------------------------------------------------------------
# COMBAT DAMAGE TRACKING — measures how "decisive" our victory was.
# - _combat_friendly_total_hp: snapshot of combined max HP of every friendly
#   unit fielded (player mech + allies) taken at combat start.
# - _combat_friendly_damage:   accumulated raw HP lost by friendly units.
# - last_combat_damage_ratio:  damage / total_hp, finalized at combat end.
#   A decisive victory keeps this <= 0.5 (we took <= 50% combined damage).
# Extracted from GlobalData; state vars stay on the singleton (tests read/write
# them directly) and GlobalData keeps thin facades for callers.
# -----------------------------------------------------------------------------


# Snapshot the combined max HP of every friendly unit in the current scene:
# the player mech + all fielded allies. Also resets the damage accumulator.
static func begin_combat_stats() -> void:
	GlobalData._combat_friendly_damage = 0.0
	GlobalData._combat_friendly_total_hp = 0.0
	var scene = GlobalData.get_tree().current_scene
	if scene == null:
		return
	var mecha = scene.get_node_or_null("Mecha")
	if mecha:
		var hs = mecha.get_node_or_null("HealthSystem")
		if hs and hs.has_method("get_health_percent"):
			GlobalData._combat_friendly_total_hp += float(hs.max_total_armor + hs.max_total_frame)
	for ally in GlobalData.get_tree().get_nodes_in_group("ally"):
		if not is_instance_valid(ally):
			continue
		var hs = ally.get_node_or_null("HealthSystem")
		if hs and hs.has_method("get_health_percent"):
			GlobalData._combat_friendly_total_hp += float(hs.max_total_armor + hs.max_total_frame)


# Allow tests / callers to supply the snapshot directly without a live scene.
static func set_combat_hp_snapshot(total_hp: float) -> void:
	GlobalData._combat_friendly_total_hp = maxf(total_hp, 0.0)
	GlobalData._combat_friendly_damage = 0.0


static func get_combat_friendly_total_hp() -> float:
	return GlobalData._combat_friendly_total_hp


static func get_combat_friendly_damage() -> float:
	return GlobalData._combat_friendly_damage


# ratio = friendly damage taken / combined friendly HP. 0 if nothing fielded.
static func compute_last_combat_damage_ratio() -> void:
	if GlobalData._combat_friendly_total_hp <= 0.0:
		GlobalData.last_combat_damage_ratio = 0.0
		return
	GlobalData.last_combat_damage_ratio = clampf(GlobalData._combat_friendly_damage / GlobalData._combat_friendly_total_hp, 0.0, 1.0)


# A victory is "decisive" when we took at most 50% of our combined HP in damage.
static func was_decisive_victory() -> bool:
	return GlobalData.last_combat_damage_ratio <= GlobalData.DECISIVE_VICTORY_RATIO
