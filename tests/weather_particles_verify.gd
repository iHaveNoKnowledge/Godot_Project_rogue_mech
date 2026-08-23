extends Node

## Weather Particle Effects — verification tests.
## Run: godot --headless --path . res://tests/weather_particles_verify.tscn

var _checks := 0
var _pass := 0
var _fail := 0

func _ready() -> void:
	var WPE = load("res://scripts/board/weather_particle_effects.gd") as GDScript
	if WPE == null:
		print("FAIL: Could not load WeatherParticleEffects script")
		_quit(1)
		return

	test_particle_creation(WPE)
	test_weather_state_tracking(WPE)
	test_particle_count_constants(WPE)

	print("\n=== RESULTS: %d/%d passed (%d failed) ===" % [_pass, _checks, _fail])
	_quit(1 if _fail > 0 else 0)


func _quit(code: int) -> void:
	get_tree().quit(code)


# 1. Particle creation — all 4 weather particle nodes exist
func test_particle_creation(WPE: GDScript) -> void:
	print("\n[1] Particle Creation")
	var wpe = WPE.new()
	add_child(wpe)

	_check(wpe.has_node("RainParticles"), "RainParticles node created")
	_check(wpe.has_node("SandParticles"), "SandParticles node created")
	_check(wpe.has_node("FogParticles"), "FogParticles node created")
	_check(wpe.has_node("DustParticles"), "DustParticles node created")

	# All start non-emitting
	var rain: GPUParticles3D = wpe.get_node("RainParticles")
	_check(not rain.emitting, "Rain starts non-emitting")
	var sand: GPUParticles3D = wpe.get_node("SandParticles")
	_check(not sand.emitting, "Sand starts non-emitting")
	var fog: GPUParticles3D = wpe.get_node("FogParticles")
	_check(not fog.emitting, "Fog starts non-emitting")
	var dust: GPUParticles3D = wpe.get_node("DustParticles")
	_check(not dust.emitting, "Dust starts non-emitting")

	wpe.queue_free()


# 2. Weather state tracking
func test_weather_state_tracking(WPE: GDScript) -> void:
	print("\n[2] Weather State Tracking")
	var wpe = WPE.new()
	add_child(wpe)

	_check(not wpe.has_active_weather(), "No active weather at start")
	_check(wpe.get_active_weather_type() == "", "Active weather type is empty")

	wpe._current_weather = "rain"
	wpe._transition_progress = 0.5
	_check(wpe.has_active_weather(), "Reports active weather when set")
	_check(wpe.get_active_weather_type() == "rain", "Reports correct weather type")

	wpe._current_weather = ""
	wpe._transition_progress = 0.0
	_check(not wpe.has_active_weather(), "No active weather when cleared")

	wpe.queue_free()


# 3. Particle count constants
func test_particle_count_constants(WPE: GDScript) -> void:
	print("\n[3] Particle Count Constants")
	_check(WPE.RAIN_COUNT == 600, "RAIN_COUNT = 600")
	_check(WPE.SAND_COUNT == 500, "SAND_COUNT = 500")
	_check(WPE.FOG_COUNT == 200, "FOG_COUNT = 200")
	_check(WPE.DUST_COUNT == 300, "DUST_COUNT = 300")


func _check(condition: bool, desc: String) -> void:
	_checks += 1
	if condition:
		_pass += 1
		print("  ✓ %s" % desc)
	else:
		_fail += 1
		print("  ✗ FAIL: %s" % desc)
