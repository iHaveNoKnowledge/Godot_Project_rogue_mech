extends Node3D

## Verification test for the WIRED Sacrifice Event system (GDD §5):
##   - bond accrual + cap
##   - sacrifice availability gating (bond >= 80, damage >= 2.0)
##   - trigger flag handling (no free Grand Entry on victory)
##   - combat-end resolution: victory bond boost vs defeat grand entry
##   - Safehouse offers the SACRIFICE MISSION button only when available
##   - combat HUD no longer renders a bond bar

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("SACRIFICE_OK: %s" % msg)
	else:
		_fails += 1
		print("SACRIFICE_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Sacrifice Event Wiring Verification ---")

	var narrative = GlobalData.narrative
	var saved_bond: float = narrative.mech_bond
	var saved_battles: int = narrative.mech_battles_survived
	var saved_available: bool = narrative.sacrifice_event_available
	var saved_triggered: bool = narrative.sacrifice_event_triggered
	var saved_pending: bool = narrative.grand_entry_pending

	# 1. Bond accrual caps at 100.
	narrative.mech_bond = 95.0
	narrative.increase_bond(10.0)
	_check(narrative.mech_bond == 100.0, "increase_bond caps at 100 (got %.1f)" % narrative.mech_bond)

	# 2. Availability requires bond >= 80 AND total damage >= 2.0.
	narrative.sacrifice_event_triggered = false
	narrative.sacrifice_event_available = false
	narrative.mech_bond = 50.0
	var newly: bool = narrative.check_sacrifice_availability({"body": 3.0})
	_check(not narrative.sacrifice_event_available and not newly,
		"No sacrifice offer while bond below 80")

	narrative.mech_bond = 85.0
	newly = narrative.check_sacrifice_availability({"body": 1.5})
	_check(not narrative.sacrifice_event_available and not newly,
		"No sacrifice offer while machine barely scratched (damage < 2.0)")

	newly = narrative.check_sacrifice_availability({"body": 2.2, "arm_left": 0.4})
	_check(narrative.sacrifice_event_available and newly,
		"Sacrifice offered once bond >= 80 AND total damage >= 2.0")
	_check(not narrative.check_sacrifice_availability({"body": 2.2}),
		"Second check does not re-announce the same unlock")

	# 3. Triggering arms the one-shot flag but NOT the grand entry — a victory
	# must never hand over the reward mech.
	narrative.trigger_sacrifice_event("")
	_check(narrative.sacrifice_event_triggered and not narrative.sacrifice_event_available,
		"Trigger consumes the sacrifice offer")
	_check(not narrative.grand_entry_pending,
		"Trigger does NOT arm grand_entry_pending (victory keeps the old mech)")

	# 4. Once triggered, availability stays locked off for the rest of the run.
	narrative.mech_bond = 100.0
	_check(not narrative.check_sacrifice_availability({"body": 9.9}),
		"Availability stays locked after the event has been triggered")

	# 5. Live resolution paths on the SacrificeEvent node.
	var se: Node = load("res://scripts/systems/sacrifice_event.gd").new()
	add_child(se)
	await get_tree().process_frame
	_check(se.is_in_group("sacrifice_event"), "SacrificeEvent registers in discovery group")

	var completed_results: Array = []
	se.sacrifice_event_completed.connect(func(v: bool) -> void: completed_results.append(v))

	GameManager.combat_node_type = "grunt"
	se._on_combat_ended(true)  # victory outside a sacrifice combat = no-op
	_check(completed_results.is_empty(),
		"Sacrifice resolution ignored for non-sacrifice combats")

	GameManager.combat_node_type = "sacrifice"
	var bond_before: float = narrative.mech_bond
	se._on_combat_ended(true)
	_check(completed_results == [true], "Sacrifice VICTORY resolves as a win")
	_check(narrative.mech_bond == minf(bond_before + 20.0, 100.0),
		"Sacrifice VICTORY grants the permanent +20 bond deepening")
	_check(not narrative.grand_entry_pending,
		"Sacrifice VICTORY does NOT spawn a replacement mech")

	se.on_sacrifice_ended(false)
	_check(narrative.grand_entry_pending,
		"Sacrifice DEFEAT arms the Grand Entry (replacement mech pending)")
	narrative.grand_entry_pending = false

	# 6. Safehouse UI exposes the mission button ONLY while available.
	var safehouse = load("res://scenes/ui/safehouse_ui.tscn").instantiate()
	add_child(safehouse)
	await get_tree().process_frame
	var btn: Button = safehouse.sacrifice_button
	_check(btn != null, "Safehouse builds a SACRIFICE MISSION button")
	if btn:
		narrative.sacrifice_event_available = true
		narrative.sacrifice_event_triggered = false
		safehouse._refresh_parts_list()
		_check(btn.visible, "Mission button visible while the sacrifice is offered")
		narrative.sacrifice_event_available = false
		safehouse._refresh_parts_list()
		_check(not btn.visible, "Mission button hidden again after the offer lapses")

	# 7. Combat HUD no longer shows any bond indicator.
	var hud_src: String = load("res://scripts/ui/core_hud.gd").source_code
	_check(hud_src.find("_create_bond_row") == -1, "CoreHUD script no longer creates a bond row")
	_check(hud_src.find("mech_bond") == -1, "CoreHUD no longer reads mech_bond during battle")

	# Restore prior state so other systems/tests are unaffected.
	narrative.mech_bond = saved_bond
	narrative.mech_battles_survived = saved_battles
	narrative.sacrifice_event_available = saved_available
	narrative.sacrifice_event_triggered = saved_triggered
	narrative.grand_entry_pending = saved_pending
	GameManager.combat_node_type = "grunt"

	print("--- Sacrifice Event Verification Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_SACRIFICE_WIRING_TESTS_PASSED")
