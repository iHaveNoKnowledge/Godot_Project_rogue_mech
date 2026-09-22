#!/bin/sh
GODOT_EXE="h:/hack/project/godot/Godot_v4.6.2-stable_win64.exe"
"$GODOT_EXE" --headless "res://test/unit/unified_ai_obstacle_jump_verify.tscn"
"$GODOT_EXE" --headless "res://test/unit/dynamic_encounter_director_verify.tscn"
"$GODOT_EXE" --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/unit/ -gexit "$@"
