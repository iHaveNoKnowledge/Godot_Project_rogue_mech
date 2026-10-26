#!/bin/sh
set -e
GODOT_EXE="${GODOT_EXE:-h:/hack/project/godot/Godot_v4.6.2-stable_win64.exe}"
if [ ! -f "$GODOT_EXE" ] && [ -f "D:/godot/Godot_v4.6.2-stable_win64_console.exe" ]; then
	GODOT_EXE="D:/godot/Godot_v4.6.2-stable_win64_console.exe"
fi
"$GODOT_EXE" --headless "res://test/unit/unified_ai_obstacle_jump_verify.tscn"
"$GODOT_EXE" --headless "res://test/unit/dynamic_encounter_director_verify.tscn"
"$GODOT_EXE" --headless "res://test/unit/missile_lock_cap_verify.tscn"
"$GODOT_EXE" --headless "res://test/unit/missile_lock_release_verify.tscn"
"$GODOT_EXE" --headless "res://test/unit/missile_salvo_execution_verify.tscn"
"$GODOT_EXE" --headless "res://test/unit/missile_lock_cone_sweep_verify.tscn"
"$GODOT_EXE" --headless "res://test/unit/missile_dual_trigger_contention_verify.tscn"
"$GODOT_EXE" --headless "res://test/unit/weapon_drop_side_effects_verify.tscn"
"$GODOT_EXE" --headless "res://test/unit/salvo_recoil_routing_verify.tscn"
"$GODOT_EXE" --headless "res://test/unit/melee_combat_pacing_and_telegraph_verify.tscn"
"$GODOT_EXE" --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/unit/ -gexit "$@"
