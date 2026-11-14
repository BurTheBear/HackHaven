extends Node
## Autoload "Settings": every player option, saved to user://settings.cfg.
## Read values directly (Settings.mouse_sensitivity). After changing one, call
## Settings.save() — that also re-applies volumes and emits `changed`.

signal changed

const PATH := "user://settings.cfg"

# Controls
var mouse_sensitivity := 1.0  ## Multiplier on the base sensitivity (0.2 – 3.0).
var invert_y := false
var toggle_sneak := false
var toggle_run := false
var controller_look_speed := 1.0

# Display
var fov := 75.0
var fullscreen := false
var head_bob := false

# Audio (linear 0.0 – 1.0)
var volume_master := 1.0
var volume_sfx := 1.0
var volume_ambience := 1.0
var volume_voice := 1.0

# Accessibility
var subtitles := true
var subtitle_size := 1  ## 0 small, 1 medium, 2 large
var captions := false  ## Captions for important sounds ("[breathing, left]").
var sound_indicator := true  ## Red edge arc toward a Listener that heard you.
var reduce_shake := false
var no_flash := false
var skip_jumpscare := false
var hint_glow := 0.0  ## Always-on floor outline strength near the player (0 – 1).
var assist_mode := false  ## Slower Listeners, more forgiving catches.

# Game
var hard_mode := false
var speedrun_timer := false
var skip_intro := false
var seen_warning := false


const KEYS := [
	"mouse_sensitivity", "invert_y", "toggle_sneak", "toggle_run", "controller_look_speed",
	"fov", "fullscreen", "head_bob",
	"volume_master", "volume_sfx", "volume_ambience", "volume_voice",
	"subtitles", "subtitle_size", "captions", "sound_indicator", "reduce_shake",
	"no_flash", "skip_jumpscare", "hint_glow", "assist_mode",
	"hard_mode", "speedrun_timer", "skip_intro", "seen_warning",
]


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in KEYS:
		set(key, cfg.get_value("settings", key, get(key)))


func save() -> void:
	var cfg := ConfigFile.new()
	for key in KEYS:
		cfg.set_value("settings", key, get(key))
	cfg.save(PATH)
	apply()


## Pushes volumes and window mode to the engine and tells everyone else.
func apply() -> void:
	_set_bus("Master", volume_master)
	_set_bus("Cave", volume_sfx)
	_set_bus("Ambience", volume_ambience)
	_set_bus("Voice", volume_voice)
	var want_full := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want_full and OS.get_name() != "Web":
		DisplayServer.window_set_mode(want_full)
	changed.emit()


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
