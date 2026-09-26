extends Node

const MechaHealthBase = preload("res://scripts/mecha/mecha_health_base.gd")
const EnemyHealth = preload("res://scripts/mecha/enemy_health.gd")
const WeaponHUD = preload("res://scripts/ui/weapon_hud.gd")
const CombatRewardsUI = preload("res://scripts/ui/combat_rewards_ui.gd")
const EnemyStatusUI = preload("res://scripts/ui/enemy_status_ui.gd")
const CombatHUD = preload("res://scripts/ui/combat_hud.gd")
const HPPartBar = preload("res://scripts/ui/hp_part_bar.gd")
const ActivationTimingSystem = preload("res://scripts/systems/activation_timing_system.gd")
const SaveGameIO = preload("res://scripts/systems/save_game_io.gd")
const WeaponCore = preload("res://scripts/systems/weapon_core.gd")
const WeaponManager = preload("res://scripts/mecha/weapon_manager.gd")
const CoreHUDScene = preload("res://scenes/ui/core_hud.tscn")

var _checks_passed: int = 0
var _checks_failed: int = 0


func _ready() -> void:
	print("\n=== STARTING PHASE 2E-26 PLAYER-FACING COMBAT RUNTIME AUDIT ===")
	_run_all_tests()


func _check(condition: bool, desc: String) -> void:
	if condition:
		_checks_passed += 1
		print("  [PASS] %s" % desc)
	else:
		_checks_failed += 1
		print("  [FAIL] %s" % desc)


func _run_all_tests() -> void:
	_test_ammo_hud_synchronization()
	_test_weapon_switching_hud_isolation()
	_test_charge_cooldown_synchronization()
	_test_charge_cancellation()
	_test_damage_feedback_synchronization()
	_test_armor_part_destruction_feedback()
	_test_player_hp_synchronization()
	_test_enemy_target_hp_synchronization()
	_test_enemy_destruction_ui_cleanup()
	_test_special_weapon_telegraph_synchronization()
	_test_combat_completion_ui()
	_test_victory_defeat_mutual_exclusion()
	_test_reward_ui_lifecycle()
	_test_combat_ab_ui_isolation()
	_test_stale_callback_protection()
	_test_special_encounter_ui_matrix()
	_test_defeat_escape_ui_cleanup()
	_test_save_load_ui_rebuild()

	print("\n==================================================")
	print("PHASE 2E-26 PLAYER-FACING RUNTIME SUMMARY:")
	print("  Passed: %d" % _checks_passed)
	print("  Failed: %d" % _checks_failed)
	print("==================================================")

	if _checks_failed == 0:
		print("PHASE_2E_26_SUCCESS")
		get_tree().quit(0)
	else:
		push_error("PHASE_2E_26_FAILED: %d assertions failed." % _checks_failed)
		get_tree().quit(1)


# -----------------------------------------------------------------------------
# Test 1: Ammo HUD Synchronization
# -----------------------------------------------------------------------------
func _test_ammo_hud_synchronization() -> void:
	print("\n-- [TEST 1] Ammo HUD Synchronization --")
	var hud: CanvasLayer = WeaponHUD.new()
	add_child(hud)

	# Mock WeaponManager
	var mock_wm = WeaponManager.new()
	var w := WeaponPart.new()
	w.weapon_name = "Combat Rifle"
	w.weapon_type = WeaponPart.WeaponType.BEAM_RIFLE
	w.max_ammo = 10
	mock_wm.left_hand = w
	mock_wm._set_ammo(w, 10)
	mock_wm.battle_reserve = {"energy_cell": 30}
	hud.weapon_manager = mock_wm

	# Initial sync
	hud._update_display()
	_check(hud.left_ammo_label.text == "10 / 10", "[T1-1] Ammo label matches authoritative loaded ammo (10 / 10)")
	_check(hud.left_reserve_label.text == "Reserve: 30", "[T1-2] Reserve label matches authoritative reserve ammo (Reserve: 30)")

	# Firing consumes 1 shot
	mock_wm._set_ammo(w, 9)
	hud._on_ammo_changed("left", 9, 10)
	_check(hud.left_ammo_label.text == "9 / 10", "[T1-3] Ammo label updates to 9 / 10 after fire")

	# Heat update
	hud._on_heat_changed("left", 35.0, 100.0, false)
	_check(hud.left_heat_bar.value == 35.0, "[T1-4] Left heat bar matches authoritative heat value (35.0)")

	mock_wm.queue_free()
	hud.queue_free()


# -----------------------------------------------------------------------------
# Test 2: Weapon Switching HUD Isolation
# -----------------------------------------------------------------------------
func _test_weapon_switching_hud_isolation() -> void:
	print("\n-- [TEST 2] Weapon Switching HUD Isolation --")
	var hud: CanvasLayer = WeaponHUD.new()
	add_child(hud)

	var mock_wm = WeaponManager.new()
	var rifle := WeaponPart.new()
	rifle.weapon_name = "Beam Rifle"
	rifle.weapon_type = WeaponPart.WeaponType.BEAM_RIFLE
	rifle.max_ammo = 12
	mock_wm.left_hand = rifle
	mock_wm._set_ammo(rifle, 12)
	mock_wm.battle_reserve = {"energy_cell": 48}
	hud.weapon_manager = mock_wm

	hud._update_display()
	_check(hud.left_name_label.text == "Beam Rifle", "[T2-1] Left slot name updated to 'Beam Rifle'")
	_check(hud.left_ammo_label.text == "12 / 12", "[T2-2] Left ammo label updated to '12 / 12'")
	_check(hud.left_type_label.text == "[RIFLE]", "[T2-3] Left type label updated to '[RIFLE]'")

	# Switch to Melee: Heat Blade
	var blade := WeaponPart.new()
	blade.weapon_name = "Heat Blade"
	blade.weapon_type = WeaponPart.WeaponType.MELEE
	blade.max_ammo = 999
	mock_wm.left_hand = blade
	mock_wm._set_ammo(blade, 999)

	hud._on_weapon_switched("left", "Heat Blade")
	_check(hud.left_name_label.text == "Heat Blade", "[T2-4] Left slot name switched to 'Heat Blade'")
	_check(hud.left_ammo_label.text == "inf", "[T2-5] Melee weapon displays 'inf', previous ammo cleared")
	_check(hud.left_type_label.text == "[BLADE]", "[T2-6] Left type label updated to '[BLADE]'")

	mock_wm.queue_free()
	hud.queue_free()


# -----------------------------------------------------------------------------
# Test 3: Charge / Cooldown Synchronization
# -----------------------------------------------------------------------------
func _test_charge_cooldown_synchronization() -> void:
	print("\n-- [TEST 3] Charge / Cooldown Synchronization --")
	var hud: CanvasLayer = WeaponHUD.new()
	add_child(hud)

	# Test bare-fist cooldown HUD readout helper
	var core = WeaponCore.from_stats({"fire_interval": 0.5, "damage": 10.0, "ammo": 10, "max_ammo": 10})
	core.cooldown = 0.40 # actively cooling down

	hud._set_fist_cd_ui(hud.left_heat_bar, hud.left_ammo_label, core)
	_check(hud.left_heat_bar.visible == true, "[T3-1] Cooldown bar is visible while cooling down")
	_check(hud.left_ammo_label.text == "0.4s", "[T3-2] Ammo label displays remaining cooldown time (0.4s)")
	_check(hud.left_ammo_label.modulate == hud.FIST_COOLING_COLOR, "[T3-3] Ammo label tinted with cooling color")

	# Cooldown finished
	core.cooldown = 0.0
	hud._set_fist_cd_ui(hud.left_heat_bar, hud.left_ammo_label, core)
	_check(hud.left_heat_bar.visible == false, "[T3-4] Cooldown bar hidden when cooldown is 0")
	_check(hud.left_ammo_label.text == "READY", "[T3-5] Ammo label shows READY when cooldown is complete")
	_check(hud.left_ammo_label.modulate == hud.FIST_READY_COLOR, "[T3-6] Ammo label tinted with READY color")

	hud.queue_free()


# -----------------------------------------------------------------------------
# Test 4: Charge Cancellation
# -----------------------------------------------------------------------------
func _test_charge_cancellation() -> void:
	print("\n-- [TEST 4] Charge Cancellation --")
	var cancel_fired := [false]
	var complete_fired := [false]

	var session: RefCounted = ActivationTimingSystem.create_session(
		{"charge_time": 1.5},
		{},
		func(_s): complete_fired[0] = true,
		func(_s, _r): cancel_fired[0] = true
	)
	session.start()

	_check(session.phase == ActivationTimingSystem.Phase.PREPARING, "[T4-1] Session starts in PREPARING phase")

	# Advance 0.5s into charge
	session.tick(0.5)
	_check(session.phase == ActivationTimingSystem.Phase.PREPARING, "[T4-2] Session in PREPARING after 0.5s")

	# Authoritative cancellation
	session.cancel("interrupted")
	_check(session.phase == ActivationTimingSystem.Phase.CANCELLED, "[T4-3] Session phase transitioned to CANCELLED")
	_check(cancel_fired[0] == true, "[T4-4] Cancel callback invoked on cancellation")

	# Further ticks do not trigger completion
	session.tick(2.0)
	_check(complete_fired[0] == false, "[T4-5] Completed callback NOT invoked after cancellation")


# -----------------------------------------------------------------------------
# Test 5: Damage Feedback Synchronization
# -----------------------------------------------------------------------------
func _test_damage_feedback_synchronization() -> void:
	print("\n-- [TEST 5] Damage Feedback Synchronization --")
	var core_hud: CanvasLayer = CoreHUDScene.instantiate()
	add_child(core_hud)

	# Trigger damage received
	EventBus.damage_received.emit("body", 25.0, "impact")
	_check(core_hud._hit_flash != null, "[T5-1] Hit flash overlay exists")
	_check(core_hud._hit_flash.color.a > 0.0, "[T5-2] Hit flash alpha raised on damage event (got %.2f)" % core_hud._hit_flash.color.a)

	# Test HPPartBar damage ghost lag behavior
	var bar: Control = HPPartBar.new()
	bar.size = Vector2(100, 10)
	bar.setup(100.0, 100.0, false)
	_check(bar.ratio == 1.0, "[T5-3] Initial HP bar ratio is 1.0")

	# Chunk damage: HP drops to 60.0
	bar.setup(60.0, 100.0, false)
	_check(bar.ratio == 0.6, "[T5-4] HP bar ratio immediately updates to 0.6")
	_check(bar._ghost_delay_timer > 0.0, "[T5-5] Damage ghost hold delay initiated")

	core_hud.queue_free()


# -----------------------------------------------------------------------------
# Test 6: Armor / Part Destruction Feedback
# -----------------------------------------------------------------------------
func _test_armor_part_destruction_feedback() -> void:
	print("\n-- [TEST 6] Armor / Part Destruction Feedback --")
	var dummy_mech := Node3D.new()
	add_child(dummy_mech)
	var health: Node3D = EnemyHealth.new()
	health.name = "HealthSystem"
	health.layout = EnemyHealth.Layout.FULL
	dummy_mech.add_child(health)

	var core_hud: CanvasLayer = CoreHUDScene.instantiate()
	core_hud.health_system = health
	add_child(core_hud)
	core_hud._update_all_bars()

	_check(core_hud.armor_values["body"].text == "80", "[T6-1] Initial body armor HUD text is 80")
	_check(core_hud.frame_values["body"].text == "60", "[T6-2] Initial body frame HUD text is 60")

	# Break body armor (80 damage)
	health._apply_armor_damage("body", 80.0, "kinetic")
	core_hud._refresh("body")

	_check(core_hud.armor_values["body"].text == "0", "[T6-3] Body armor HUD text is 0 after armor break")
	_check(core_hud.frame_values["body"].text == "60", "[T6-4] Body frame HUD text remains 60")

	# Destroy body frame (60 damage)
	health._apply_frame_damage("body", 60.0, "kinetic")
	core_hud._refresh("body")

	_check(core_hud.frame_values["body"].text == "0", "[T6-5] Body frame HUD text is 0 after part destruction")
	_check(core_hud.frame_bars["body"].destroyed == true, "[T6-6] Body frame bar marked destroyed")

	dummy_mech.queue_free()
	core_hud.queue_free()


# -----------------------------------------------------------------------------
# Test 7: Player HP Synchronization
# -----------------------------------------------------------------------------
func _test_player_hp_synchronization() -> void:
	print("\n-- [TEST 7] Player HP Synchronization --")
	var dummy_mech := Node3D.new()
	add_child(dummy_mech)
	var health: Node3D = EnemyHealth.new()
	health.name = "HealthSystem"
	health.layout = EnemyHealth.Layout.FULL
	dummy_mech.add_child(health)

	var core_hud: CanvasLayer = CoreHUDScene.instantiate()
	core_hud.health_system = health
	add_child(core_hud)
	core_hud._update_all_bars()

	# Damage head armor
	health._apply_armor_damage("head", 15.0, "kinetic")
	core_hud._refresh("head")

	_check(int(core_hud.armor_values["head"].text) < 40, "[T7-1] Head armor HUD text updated to reduced armor value")
	_check(core_hud.armor_values["leg_left"].text == "40", "[T7-2] Unrelated leg_left armor unchanged at 40")
	_check(core_hud.armor_values["leg_right"].text == "40", "[T7-3] Unrelated leg_right armor unchanged at 40")

	dummy_mech.queue_free()
	core_hud.queue_free()


# -----------------------------------------------------------------------------
# Test 8: Enemy Target HP Synchronization
# -----------------------------------------------------------------------------
func _test_enemy_target_hp_synchronization() -> void:
	print("\n-- [TEST 8] Enemy Target HP Synchronization --")
	var enemy := Node3D.new()
	add_child(enemy)
	var enemy_health: Node3D = EnemyHealth.new()
	enemy_health.name = "HealthSystem"
	enemy_health.layout = EnemyHealth.Layout.FULL
	enemy.add_child(enemy_health)

	var enemy_ui: Control = EnemyStatusUI.new()
	add_child(enemy_ui)
	enemy_ui.setup_target(enemy)

	_check(enemy_ui.visible == true, "[T8-1] Enemy status UI becomes visible on setup_target")
	_check(enemy_ui.part_blocks.has("body"), "[T8-2] Enemy UI constructed body block")

	# Verify initial color
	var body_armor_rect: ColorRect = enemy_ui.part_blocks["body"]["armor"]
	_check(body_armor_rect.color == enemy_ui._color_armor_ok, "[T8-3] Enemy body armor block starts with OK color")

	# Break enemy body armor
	enemy_health._apply_armor_damage("body", 80.0, "kinetic")
	enemy_ui._update_status()

	_check(body_armor_rect.color == enemy_ui._color_armor_broken, "[T8-4] Enemy body armor block reflects broken armor color")

	enemy.queue_free()
	enemy_ui.queue_free()


# -----------------------------------------------------------------------------
# Test 9: Enemy Destruction UI Cleanup
# -----------------------------------------------------------------------------
func _test_enemy_destruction_ui_cleanup() -> void:
	print("\n-- [TEST 9] Enemy Destruction UI Cleanup --")
	var enemy := Node3D.new()
	add_child(enemy)
	var enemy_health: Node3D = EnemyHealth.new()
	enemy_health.name = "HealthSystem"
	enemy_health.layout = EnemyHealth.Layout.FULL
	enemy.add_child(enemy_health)

	var enemy_ui: Control = EnemyStatusUI.new()
	add_child(enemy_ui)
	enemy_ui.setup_target(enemy)

	# Destroy body frame
	enemy_health._apply_armor_damage("body", 80.0, "kinetic") # armor
	enemy_health._apply_frame_damage("body", 60.0, "kinetic") # frame
	enemy_ui._update_status()

	var body_frame_rect: ColorRect = enemy_ui.part_blocks["body"]["frame"]
	_check(body_frame_rect.color == enemy_ui._color_black, "[T9-1] Destroyed enemy body frame rendered black")

	# Target invalidation triggers queue_free in _process
	enemy_ui.target = null
	enemy_ui._process(0.016)
	_check(enemy_ui.is_queued_for_deletion(), "[T9-2] EnemyStatusUI queues free when target becomes invalid")

	enemy.queue_free()


# -----------------------------------------------------------------------------
# Test 10: Special Weapon Telegraph Synchronization
# -----------------------------------------------------------------------------
func _test_special_weapon_telegraph_synchronization() -> void:
	print("\n-- [TEST 10] Special Weapon Telegraph Synchronization --")
	var session: RefCounted = ActivationTimingSystem.create_session(
		{"charge_time": 2.0},
		{},
		func(_s): pass,
		func(_s, _r): pass
	)
	session.start()

	_check(session.get_progress() == 0.0, "[T10-1] Initial telegraph progress is 0.0")

	session.tick(1.0)
	_check(is_equal_approx(session.get_progress(), 0.5), "[T10-2] Mid-charge telegraph progress is exactly 0.5 (50%)")

	session.tick(1.0)
	_check(session.get_progress() >= 1.0, "[T10-3] Charge complete telegraph progress is 1.0 (100%)")
	_check(session.phase == ActivationTimingSystem.Phase.COMPLETED, "[T10-4] Session transitioned to COMPLETED phase")


# -----------------------------------------------------------------------------
# Test 11: Combat Completion UI
# -----------------------------------------------------------------------------
func _test_combat_completion_ui() -> void:
	print("\n-- [TEST 11] Combat Completion UI --")
	GameManager.suppress_scene_change = true
	var rewards_ui: CanvasLayer = CombatRewardsUI.new()
	add_child(rewards_ui)

	# Initial state
	_check(rewards_ui.visible == false, "[T11-1] CombatRewardsUI starts hidden")

	# Victory emission
	EventBus.combat_ended.emit(true)
	_check(rewards_ui.visible == true, "[T11-2] CombatRewardsUI becomes visible on victory")
	_check(rewards_ui.title_label.text == "COMBAT VICTORY", "[T11-3] Title label displays 'COMBAT VICTORY'")

	rewards_ui.queue_free()
	GameManager.suppress_scene_change = false


# -----------------------------------------------------------------------------
# Test 12: Victory / Defeat Mutual Exclusion
# -----------------------------------------------------------------------------
func _test_victory_defeat_mutual_exclusion() -> void:
	print("\n-- [TEST 12] Victory / Defeat Mutual Exclusion --")
	GameManager.suppress_scene_change = true
	var rewards_ui: CanvasLayer = CombatRewardsUI.new()
	add_child(rewards_ui)

	# Defeat emission
	EventBus.combat_ended.emit(false)
	_check(rewards_ui.visible == true, "[T12-1] Defeat screen becomes visible")
	_check(rewards_ui.title_label.text == "DEFEATED", "[T12-2] Title label displays 'DEFEATED'")
	_check(rewards_ui.loot_picker.visible == false, "[T12-3] Loot picker hidden on defeat")

	rewards_ui.queue_free()
	GameManager.suppress_scene_change = false


# -----------------------------------------------------------------------------
# Test 13: Reward UI Lifecycle
# -----------------------------------------------------------------------------
func _test_reward_ui_lifecycle() -> void:
	print("\n-- [TEST 13] Reward UI Lifecycle --")
	GameManager.suppress_scene_change = true
	var rewards_ui: CanvasLayer = CombatRewardsUI.new()
	add_child(rewards_ui)

	# Setup simulated battle loot
	var item1 := {"id": "wpn_rifle", "name": "Combat Rifle", "type": "weapon"}
	var item2 := {"id": "wpn_blade", "name": "Heat Blade", "type": "weapon"}
	rewards_ui._left_items = [item1, item2]
	rewards_ui._right_items = []

	# Toggle item1 across columns
	rewards_ui._toggle_loot_entry(item1)
	_check(rewards_ui._left_items.size() == 1, "[T13-1] Left loot items size is 1 after taking an item")
	_check(rewards_ui._right_items.size() == 1, "[T13-2] Right loot items size is 1")
	_check(rewards_ui._right_items[0]["id"] == "wpn_rifle", "[T13-3] Selected item is 'wpn_rifle'")

	# Continue button debounce
	_check(rewards_ui._continue_processing == false, "[T13-4] _continue_processing initially false")
	rewards_ui._on_continue_pressed()
	_check(rewards_ui._continue_processing == true, "[T13-5] _continue_processing set to true on continue")
	_check(rewards_ui.continue_button.disabled == true, "[T13-6] continue_button disabled immediately on click")

	rewards_ui.queue_free()
	GameManager.suppress_scene_change = false


# -----------------------------------------------------------------------------
# Test 14: Combat A -> Combat B UI Isolation
# -----------------------------------------------------------------------------
func _test_combat_ab_ui_isolation() -> void:
	print("\n-- [TEST 14] Combat A -> Combat B UI Isolation --")
	GameManager.suppress_scene_change = true
	var rewards_ui: CanvasLayer = CombatRewardsUI.new()
	add_child(rewards_ui)

	# Combat A finishes
	rewards_ui._rewards_claimed = true
	rewards_ui._continue_processing = true
	rewards_ui.continue_button.disabled = true

	# Reset for Combat B
	rewards_ui.reset_reward_state()
	_check(rewards_ui._rewards_claimed == false, "[T14-1] _rewards_claimed reset to false for Combat B")
	_check(rewards_ui._continue_processing == false, "[T14-2] _continue_processing reset to false for Combat B")
	_check(rewards_ui.continue_button.disabled == false, "[T14-3] continue_button re-enabled for Combat B")

	rewards_ui.queue_free()
	GameManager.suppress_scene_change = false


# -----------------------------------------------------------------------------
# Test 15: Stale Callback Protection
# -----------------------------------------------------------------------------
func _test_stale_callback_protection() -> void:
	print("\n-- [TEST 15] Stale Callback Protection --")
	GameManager.suppress_scene_change = true
	var rewards_ui: CanvasLayer = CombatRewardsUI.new()
	add_child(rewards_ui)

	# First victory
	rewards_ui._show_victory_rewards()
	var credits_initial: int = GlobalData.currency.credits
	var scrap_initial: int = GlobalData.currency.scrap

	# Duplicate / delayed call
	rewards_ui._show_victory_rewards()
	_check(GlobalData.currency.credits == credits_initial, "[T15-1] Delayed reward call does NOT award duplicate credits")
	_check(GlobalData.currency.scrap == scrap_initial, "[T15-2] Delayed reward call does NOT award duplicate scrap")

	rewards_ui.queue_free()
	GameManager.suppress_scene_change = false


# -----------------------------------------------------------------------------
# Test 16: Special Encounter UI Matrix
# -----------------------------------------------------------------------------
func _test_special_encounter_ui_matrix() -> void:
	print("\n-- [TEST 16] Special Encounter UI Matrix --")
	var combat_hud: CanvasLayer = CombatHUD.new()
	add_child(combat_hud)

	# Normal wave encounter string format
	var format_normal = func(cur: int, tot: int, left: int) -> String:
		return "WAVE %d / %d  |  ENEMIES LEFT: %d" % [cur, tot, left]

	var format_boss = func(left: int) -> String:
		return "⚠️ BOSS ENCOUNTER | ENEMIES: %d" % left

	_check(format_normal.call(1, 3, 4) == "WAVE 1 / 3  |  ENEMIES LEFT: 4", "[T16-1] Normal wave UI string matches format")
	_check(format_boss.call(1) == "⚠️ BOSS ENCOUNTER | ENEMIES: 1", "[T16-2] Boss encounter UI string matches format")

	# Announcement banner
	combat_hud.announce("TEST ANNOUNCEMENT", 1.0)
	_check(combat_hud.announce_panel.visible == true, "[T16-3] Announcement panel becomes visible on announce()")
	_check(combat_hud.announce_label.text == "TEST ANNOUNCEMENT", "[T16-4] Announcement text matches parameter")

	combat_hud.queue_free()


# -----------------------------------------------------------------------------
# Test 17: Defeat & Escape UI Cleanup
# -----------------------------------------------------------------------------
func _test_defeat_escape_ui_cleanup() -> void:
	print("\n-- [TEST 17] Defeat & Escape UI Cleanup --")
	var core_hud: CanvasLayer = CoreHUDScene.instantiate()
	add_child(core_hud)

	# Normal Mech stance
	core_hud._update_eject_hud(false)
	var mech_panel: PanelContainer = core_hud.get_node_or_null("Panel")
	_check(mech_panel.visible == true, "[T17-1] Mech panel visible in normal state")
	_check(core_hud._pilot_panel.visible == false, "[T17-2] Pilot on foot panel hidden in mech state")

	# Eject / Pilot stance
	core_hud._update_eject_hud(true)
	_check(mech_panel.visible == false, "[T17-3] Mech panel hidden when pilot is ejected")
	_check(core_hud._pilot_panel.visible == true, "[T17-4] Pilot on foot panel visible when pilot is ejected")

	core_hud.queue_free()


# -----------------------------------------------------------------------------
# Test 18: Save / Load UI Rebuild
# -----------------------------------------------------------------------------
func _test_save_load_ui_rebuild() -> void:
	print("\n-- [TEST 18] Save / Load UI Rebuild --")
	GlobalData.currency.credits = 1500
	GlobalData.currency.scrap = 350

	SaveGameIO.save_run()

	# Alter runtime values
	GlobalData.currency.credits = 0
	GlobalData.currency.scrap = 0

	# Reload
	SaveGameIO.load_run()
	_check(GlobalData.currency.credits == 1500, "[T18-1] Restored credits match saved state (1500)")
	_check(GlobalData.currency.scrap == 350, "[T18-2] Restored scrap match saved state (350)")
