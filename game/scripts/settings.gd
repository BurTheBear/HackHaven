extends Node
## Autoload "Settings": every player option, saved to user://settings.cfg.
## Read values directly (Settings.mouse_sensitivity). After changing one, call
## Settings.save() — that also re-applies volumes / video and emits `changed`.

signal changed

const PATH := "user://settings.cfg"
const FPS_LIMITS := [30, 60, 120, 0]  ## Index → Engine.max_fps (0 = unlimited).
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const CROSSHAIRS := ["Dot", "Cross", "None"]

# Gameplay
var damage_enabled := true  ## Combat on. Off: Listeners catch instantly (old rules).
var difficulty := 1  ## 0 Easy (assist_mode), 1 Normal, 2 Hard (hard_mode). Synced in apply().

# Controls
var mouse_sensitivity := 1.0  ## Multiplier on the base sensitivity (0.2 – 3.0).
var invert_y := false
var toggle_sneak := false
var toggle_run := false
var controller_look_speed := 1.0
var mouse_smoothing := 0.0  ## 0 = raw, 1 = heavy smoothing. Player code may read it.
var vibration := true  ## Controller rumble. Use Settings.vibrate().

# Display / video
var fov := 75.0
var fullscreen := false
var vsync := true
var fps_limit := 3  ## Index into FPS_LIMITS.
var show_fps := false
var render_scale := 1.0  ## 0.5 – 1.0, viewport scaling_3d_scale.
var brightness := 1.0  ## 0.6 – 1.6, WorldEnvironment adjustment.
var particles := true  ## Dust motes / particle effects. Level code reads it.
var head_bob := false
var landing_motion := true  ## Camera dip when landing from a jump or fall.

# HUD
var crosshair_style := 0  ## 0 dot, 1 cross, 2 none.
var hud_scale := 1.0  ## 0.75 – 1.5
var hud_opacity := 1.0  ## 0.2 – 1.0
var presence_bar := true
var damage_numbers := true
var damage_vignette := true

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
var camera_shake := 1.0  ## 0 – 1 shake intensity. Use shake_scale().
var reduce_shake := false  ## Legacy flag, kept in sync: true when camera_shake <= 0.4.
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
	"damage_enabled", "difficulty",
	"mouse_sensitivity", "invert_y", "toggle_sneak", "toggle_run", "controller_look_speed",
	"mouse_smoothing", "vibration",
	"fov", "fullscreen", "vsync", "fps_limit", "show_fps", "render_scale", "brightness",
	"particles", "head_bob", "landing_motion",
	"crosshair_style", "hud_scale", "hud_opacity", "presence_bar", "damage_numbers", "damage_vignette",
	"volume_master", "volume_sfx", "volume_ambience", "volume_voice",
	"subtitles", "subtitle_size", "captions", "sound_indicator", "camera_shake", "reduce_shake",
	"no_flash", "skip_jumpscare", "hint_glow", "assist_mode",
	"hard_mode", "speedrun_timer", "skip_intro", "seen_warning",
]

## Defaults captured at startup, for "Reset to defaults".
var _defaults := {}


func _ready() -> void:
	for key in KEYS:
		_defaults[key] = get(key)
	load_settings()
	apply()
	var tree := get_tree()
	if tree.has_signal("scene_changed"):
		tree.connect("scene_changed", apply_scene)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in KEYS:
		set(key, cfg.get_value("settings", key, get(key)))
	# Old saves: only reduce_shake existed.
	if not cfg.has_section_key("settings", "camera_shake") and reduce_shake:
		camera_shake = 0.3


func save() -> void:
	var cfg := ConfigFile.new()
	for key in KEYS:
		cfg.set_value("settings", key, get(key))
	cfg.save(PATH)
	apply()


## Restores every option except seen_warning to its default (not saved).
func reset_to_defaults() -> void:
	for key in KEYS:
		if key != "seen_warning" and _defaults.has(key):
			set(key, _defaults[key])
	apply()


## Difficulty preset: sets assist_mode / hard_mode.
func set_difficulty(index: int) -> void:
	difficulty = clampi(index, 0, 2)
	assist_mode = difficulty == 0
	hard_mode = difficulty == 2


## Camera shake multiplier (0 – 1) for shake code.
func shake_scale() -> float:
	return clampf(camera_shake, 0.0, 1.0)


## Controller rumble, respecting the vibration setting.
func vibrate(weak: float, strong: float, seconds: float, device: int = 0) -> void:
	if vibration:
		Input.start_joy_vibration(device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), seconds)


## Pushes volumes, window / video options to the engine and tells everyone else.
func apply() -> void:
	reduce_shake = camera_shake <= 0.4
	difficulty = 2 if hard_mode else (0 if assist_mode else 1)
	_set_bus("Master", volume_master)
	_set_bus("Cave", volume_sfx)
	_set_bus("Ambience", volume_ambience)
	_set_bus("Voice", volume_voice)
	if OS.get_name() != "Web" and DisplayServer.get_name() != "headless":
		var want_full := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want_full:
			DisplayServer.window_set_mode(want_full)
		var want_vsync := DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
		if DisplayServer.window_get_vsync_mode() != want_vsync:
			DisplayServer.window_set_vsync_mode(want_vsync)
	Engine.max_fps = int(FPS_LIMITS[clampi(fps_limit, 0, FPS_LIMITS.size() - 1)])
	apply_scene()
	changed.emit()


## Viewport render scale and brightness on the current scene's WorldEnvironment.
func apply_scene(_scene: Variant = null) -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = clampf(render_scale, 0.5, 1.0)
	var scene := get_tree().current_scene
	if scene == null:
		return
	var we := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment
	var b := clampf(brightness, 0.5, 2.0)
	if absf(b - 1.0) < 0.001 and not env.adjustment_enabled:
		return
	env.adjustment_enabled = true
	env.adjustment_brightness = b


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
