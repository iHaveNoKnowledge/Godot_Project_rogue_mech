# UI Sound Files

Drop audio files here to replace the procedurally generated UI tones.

| File name         | Used for                                    | Default                   |
|-------------------|---------------------------------------------|---------------------------|
| `click.wav`       | Every button press (ui_click)               | generated 800Hz sine tone |
| `confirm.wav`     | Menu open / confirm (play_menu_open)        | generated 1200Hz tone     |

Supported formats: `.wav`, `.ogg`, `.mp3`.

AudioManager (`scripts/autoload/audio_manager.gd`) looks for a file whose base
name matches `click` or `confirm` in this folder. If the folder is empty or the
file is missing, the built-in generated tone plays instead, so you never need to
delete files to revert.

Example: drop `click.wav` here, run the game, and every interface button press
will use your file. To add a brand-new UI sound effect, add a new line in
`AudioManager._generate_sounds()` (e.g. `_sound_cache["hover"] = _gen_sine_tone(...)`)
and play it with `AudioManager.play_sfx_2d("hover")`.
