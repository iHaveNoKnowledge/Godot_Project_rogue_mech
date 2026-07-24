extends Node

## Procedural combat music using AudioStreamGenerator.
## Generates a simple looping track with bass, mid, and hi layers.

var stream_player: AudioStreamGeneratorPlayback
var audio_stream: AudioStreamGenerator
var is_playing: bool = false
var combat_intensity: float = 0.0

const SAMPLE_RATE = 22050
const BPM = 120.0
const BEAT_DURATION = 60.0 / BPM

var time: float = 0.0
var bar_count: int = 0


func _ready() -> void:
	audio_stream = AudioStreamGenerator.new()
	audio_stream.mix_rate = SAMPLE_RATE
	audio_stream.buffer_length = 0.5

	var player = AudioStreamPlayer.new()
	player.stream = audio_stream
	player.bus = "Music"
	add_child(player)
	player.play()
	stream_player = player.get_stream_playback()
	is_playing = true

	EventBus.combat_intensity_changed.connect(_on_intensity_changed)


func _on_intensity_changed(intensity: float) -> void:
	combat_intensity = intensity


func _process(delta: float) -> void:
	if not is_playing or stream_player == null:
		return

	var frames_available = stream_player.get_frames_available()
	var frame_size = int(SAMPLE_RATE * delta)

	for i in range(min(frames_available, frame_size)):
		var sample = _generate_sample(time)
		stream_player.push_frame(Vector2(sample, sample))
		time += 1.0 / SAMPLE_RATE

		# Track beats
		var new_bar = int(time / BEAT_DURATION)
		if new_bar != bar_count:
			bar_count = new_bar


func _generate_sample(t: float) -> float:
	var sample = 0.0
	var beat = fmod(t, BEAT_DURATION) / BEAT_DURATION
	var bar = fmod(t, BEAT_DURATION * 4) / (BEAT_DURATION * 4)

	# Bass layer - quarter notes (only when intensity > 0.3)
	if combat_intensity > 0.3:
		if beat < 0.1:
			sample += sin(TAU * 55.0 * t) * 0.2 * combat_intensity
		elif beat > 0.25 and beat < 0.35:
			sample += sin(TAU * 55.0 * t) * 0.15 * combat_intensity

	# Mid layer - eighth note arpeggios (only when intensity > 0.5)
	if combat_intensity > 0.5:
		var notes = [220.0, 261.6, 329.6, 392.0]
		var note_idx = int(t / (BEAT_DURATION * 0.5)) % notes.size()
		if fmod(t, BEAT_DURATION * 0.5) / (BEAT_DURATION * 0.5) < 0.3:
			sample += sin(TAU * notes[note_idx] * t) * 0.1 * combat_intensity

	# Hi layer - sixteenth note noise (only when intensity > 0.7)
	if combat_intensity > 0.7:
		if fmod(t, BEAT_DURATION * 0.25) / (BEAT_DURATION * 0.25) < 0.1:
			sample += (randf() * 2.0 - 1.0) * 0.05 * combat_intensity

	# Variation every 8 bars
	if int(bar_count / 8) % 2 == 1:
		sample *= 1.1

	return clampf(sample, -0.5, 0.5)
