extends Node

## ---------------------------------------------------------------------------
## WEATHER TILE COLORING — applies weather-specific tints to board tiles.
##
## Each weather type applies a color tint and roughness modifier to the
## terrain shader for visual atmosphere:
##   - Fog:      blue-grey tint + increased roughness (matte, damp look)
##   - Rain:     cool blue tint + reduced roughness (wet sheen)
##   - Sandstorm: warm amber tint + slight roughness increase
##   - Dust:     warm haze tint + moderate roughness increase
##
## Tint strength scales with transition_progress for smooth visual blending.
## ---------------------------------------------------------------------------

## Weather tint configurations: { weather_id: { tint_color, tint_strength, roughness_mod } }
const WEATHER_TINTS: Dictionary = {
	"rain": {
		"color": Color(0.35, 0.45, 0.65),    # Cool blue (wet surfaces)
		"strength": 0.65,                       # Moderate tint
		"roughness": -0.25,                     # Smoother = wet sheen
	},
	"sandstorm": {
		"color": Color(0.75, 0.55, 0.25),    # Warm amber (sand particles)
		"strength": 0.55,                       # Moderate tint
		"roughness": 0.15,                      # Slightly rougher (dust coating)
	},
	"fog": {
		"color": Color(0.45, 0.52, 0.62),    # Blue-grey (fog blanket)
		"strength": 0.70,                       # Strong tint (dense fog)
		"roughness": 0.20,                      # Matte, damp look
	},
	"dust_storm": {
		"color": Color(0.65, 0.50, 0.30),    # Warm haze (dust)
		"strength": 0.45,                       # Light tint
		"roughness": 0.10,                      # Slight roughness
	},
}

var _current_weather: String = ""
var _current_progress: float = 0.0


func _process(_delta: float) -> void:
	if GlobalData.weather_transition == null:
		return

	var new_weather: String = GlobalData.weather_transition.current_weather
	var new_progress: float = GlobalData.weather_transition.transition_progress

	# Only update tiles if weather or progress changed significantly
	if new_weather == _current_weather and absf(new_progress - _current_progress) < 0.05:
		return

	_current_weather = new_weather
	_current_progress = new_progress
	_apply_weather_tint()


func _apply_weather_tint() -> void:
	var tiles := get_tree().get_nodes_in_group("board_tile")
	if tiles.is_empty():
		return

	var tint_data: Dictionary = WEATHER_TINTS.get(_current_weather, {})
	var has_tint: bool = not tint_data.is_empty() and _current_progress > 0.05

	for tile in tiles:
		if not tile.is_revealed:
			continue
		if not tile.has_node("MeshInstance3D"):
			continue
		var mesh_inst: MeshInstance3D = tile.get_node("MeshInstance3D")
		var mat = mesh_inst.get_surface_override_material(0)
		if mat == null or not (mat is ShaderMaterial):
			continue

		if has_tint:
			var tint_color: Color = tint_data.get("color", Color.BLACK)
			var tint_strength: float = tint_data.get("strength", 0.0) * _current_progress
			var rough_mod: float = tint_data.get("roughness", 0.0)
			mat.set_shader_parameter("weather_tint_color", tint_color)
			mat.set_shader_parameter("weather_tint_strength", tint_strength)
			mat.set_shader_parameter("weather_roughness_mod", rough_mod)
		else:
			# Clear weather tint
			mat.set_shader_parameter("weather_tint_color", Color.BLACK)
			mat.set_shader_parameter("weather_tint_strength", 0.0)
			mat.set_shader_parameter("weather_roughness_mod", 0.0)


# ===========================================================================
# PUBLIC API
# ===========================================================================

## Returns the tint config for the given weather type (or empty dict).
func get_weather_tint(weather_type: String) -> Dictionary:
	return WEATHER_TINTS.get(weather_type, {})


## Returns the current effective tint strength for the given weather.
func get_effective_tint_strength(weather_type: String) -> float:
	var tint = WEATHER_TINTS.get(weather_type, {})
	if tint.is_empty():
		return 0.0
	return float(tint.get("strength", 0.0)) * _current_progress


## Force-refresh all tiles (call after board generation).
func refresh() -> void:
	_current_weather = ""
	_current_progress = 0.0
	_apply_weather_tint()


## Returns the current weather being applied.
func get_current_weather() -> String:
	return _current_weather


## Returns the current transition progress.
func get_current_progress() -> float:
	return _current_progress
