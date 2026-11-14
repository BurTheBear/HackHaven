extends CanvasLayer
## All 2D UI, built in code: boot cards and the main menu, HUD (crosshair,
## cooldown rings, pebbles, crystal icons, timer), one-at-a-time control
## prompts, zone cards, subtitles / Mara's logs, screen effects (vignette,
## grain, dread, chromatic aberration, ping ripple, checkpoint glow), the
## catch sequence, pause / settings / credits / end screens, plus the map and
## the sound indicators (separate scripts). main.gd drives the flow.

const Style = preload("res://scripts/ui_style.gd")
const TitleMenu = preload("res://scripts/menu_title.gd")
const SettingsMenu = preload("res://scripts/menu_settings.gd")
const PauseMenu = preload("res://scripts/menu_pause.gd")
const CreditsMenu = preload("res://scripts/menu_credits.gd")
const EndMenu = preload("res://scripts/menu_end.gd")
const BootCards = preload("res://scripts/ui_boot.gd")
const MAP_PATH := "res://scripts/ui_map.gd"
const INDICATORS_PATH := "res://scripts/ui_indicators.gd"

const HUD_IDLE := 4.0
const SUB_SIZES := [20, 26, 34]
const CRYSTAL := Color(0.45, 0.8, 1.0)
const OPENING := ["The rope snapped. The lantern's gone.", "Call out. Listen. Find your way back."]
const FIRST_TIP := "They go where the noise is, not where you are."
const TIPS := [
	"Ping, then move. Standing on your own echo is what gets you caught.",
	"Throw a pebble far away. They'll go where it lands.",
	"Sneak and your footsteps go silent.",
	"A whisper shows you a little, and nothing hears it.",
	"Running is loud. They hear your steps from nine metres.",
	"Listen first. You can hear them breathing before you see them.",
	"A sleeping one only wakes if you call out close to it.",
]
## id: [action, text]. The bound key is shown in front: "[Q]  Whisper...".
const PROMPTS := {
	"ping": ["ping", "Call out. The cave answers, and so might something else."],
	"whisper": ["whisper", "Whisper: a small echo nothing can hear."],
	"throw": ["throw", "Throw a pebble. Hold to aim. Its echo lands far away."],
	"jump": ["jump", "Jump. The landing makes a sound."],
	"sneak": ["sneak", "Sneak: your footsteps go silent."],
	"run": ["run", "Run: fast, but loud."],
	"interact": ["interact", "Play the recording."],
	"map": ["map", "Map: everywhere you've heard."],
	"pebbles_empty": ["", "Out of pebbles."],
	"hold_breath": ["hold_breath", "Hold your breath"],
	"hide": ["interact", "Hide"],
	"attack": ["attack", "Strike"],
}
const EXTRA_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float amount = 0.0;
void fragment() {
	float d = length((UV - vec2(0.5)) * vec2(1.0, 0.8)) * 1.6;
	COLOR = vec4(tint.rgb, amount * smoothstep(0.35, 1.05, d));
}
"""
const REPEATABLE := ["interact"]

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float dread = 0.0;
uniform float base_vignette = 0.5;
void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv * vec2(1.0, 0.9)) * 1.4;
	// Plain dark vignette that closes in a little as a Listener nears.
	float vig = smoothstep(0.45 - 0.1 * dread, 1.05, d) * (base_vignette + 0.15 * dread);
	COLOR = vec4(0.0, 0.0, 0.0, clamp(vig, 0.0, 1.0));
}
"""

const GRAIN_SHADER := """
shader_type canvas_item;
uniform float amount = 0.035;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / 2.0);
	float frame = mod(floor(TIME * 24.0), 61.0);
	float n = hash(cell * 0.013 + vec2(frame * 0.731, frame * 0.417));
	COLOR = vec4(vec3(n), amount * (0.4 + 0.6 * n));
}
"""

## Proximity bar: grey-cyan when a Listener is far, amber, then red up close.
const PRESENCE_FAR := Color(0.5, 0.64, 0.68)
const PRESENCE_MID := Color(1.0, 0.7, 0.26)
const PRESENCE_NEAR := Color(0.92, 0.18, 0.12)
const PRESENCE_WIDTH := 220.0

## Reads the screen: chromatic aberration at high dread, and a ripple ring
## when you ping. Only visible while one of them is active.
const FX_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float chroma = 0.0;
uniform float ripple = -1.0;
uniform float ripple_strength = 1.0;
uniform float aspect = 1.7778;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	d.x *= aspect;
	float len = length(d);
	vec2 dir = len > 0.0001 ? d / len : vec2(0.0);
	float band = 0.0;
	if (ripple >= 0.0) {
		band = exp(-pow((len - ripple * 1.1) / 0.05, 2.0)) * (1.0 - ripple) * ripple_strength;
	}
	vec2 off = dir * band * 0.012;
	off.x /= aspect;
	vec2 ca = (uv - 0.5) * chroma;
	float r = texture(screen_tex, uv + off + ca).r;
	float g = texture(screen_tex, uv + off).g;
	float b = texture(screen_tex, uv + off - ca).b;
	float a = clamp(max(band * 3.0, chroma * 400.0), 0.0, 1.0);
	COLOR = vec4(r, g, b, a);
}
"""

const EDGE_SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.78, 0.27, 1.0);
void fragment() {
	vec2 uv = UV - 0.5;
	float e = max(abs(uv.x), abs(uv.y)) * 2.0;
	float g = smoothstep(0.62, 1.0, max(e, length(uv) * 1.25));
	COLOR = vec4(tint.rgb, g * amount * 0.6);
}
"""

static var _prompts_seen := {}

@onready var root: Control = $Root

var _main: Node
var _player: Node3D

var _fx: ColorRect
var _vignette: ColorRect
var _grain: ColorRect
var _edge: ColorRect
var _flash: ColorRect
var _black: ColorRect
var _hud: Control
var _timer_label: Label
var _zone_label: Label
var _prompt_box: PanelContainer
var _prompt_key: Label
var _prompt_text: Label
var _sub_box: PanelContainer
var _sub_speaker: Label
var _sub_text: Label
var _sub_counter: Label
var _center: Label
var _tip: Label
var _opening: Label
var _map: Control
var _indicators: Control
var _title_menu: TitleMenu
var _pause_menu: PauseMenu
var _settings: SettingsMenu
var _credits: CreditsMenu
var _end: EndMenu
var _boot: BootCards

var _dread := 0.0
var _flash_alpha := 0.0
var _ripple := -1.0
var _ripple_strength := 1.0
var _idle := 0.0
var _hud_alpha := 1.0
var _spread := 0.0
var _ready_flash := 0.0
var _last_cooldown := 0.0
var _whisper_max := 2.5
var _last_pebbles := 0
var _slot_pulse: Array[float] = []
var _slot_drop: Array[float] = []
var _empty_shake := 0.0
var _pause_shown := false
var _settings_from := ""
var _prompt_id := ""
var _prompt_age := 0.0
var _prompt_gap := 0.0
var _prompt_queue: Array[String] = []
var _done_actions := {}
var _last_empty := -100.0
var _sub_phase := 0  ## 0 hidden, 1 typing, 2 holding, 3 fading
var _sub_chars := 0.0
var _sub_hold := 0.0
var _caught_busy := false
var _opening_skip := false
var _mouse_hidden := false
var _total_logs := -1
var _time := 0.0
var _extra: ColorRect
var _breath_bg: ColorRect
var _breath_fill: ColorRect
var _toast: Label
var _toast_tween: Tween
var _chase := false
var _presence := 0.0
var _presence_root: Control
var _presence_fill: ColorRect
var _flash_in := 0.0
var _chase_amt := 0.0
var _hide_amt := 0.0
var _black_tween: Tween
var _edge_tween: Tween
var _zone_tween: Tween
var _prompt_tween: Tween
var _sub_tween: Tween
var _center_tween: Tween
# Combat HUD
var _hp := -1.0
var _hp_max := 100.0
var _hp_lag := -1.0  ## Trailing "lost health" segment.
var _hp_hit := 0.0  ## Bar flash after a hit.
var _attack_max := 0.5
var _dmg_numbers: Array = []  ## [{pos: Vector3, text: String, age: float}]
var _fps_label: Label


## Builds every UI layer in code (order = draw order) and connects signals.
func _ready() -> void:
	# Keeps running while the tree is paused (menus, pause screen, fades).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = get_parent()
	if _main != null:
		_player = _main.get_node_or_null("Player") as Node3D
	Style.load_keys()
	for c in root.get_children():
		c.queue_free()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_pulse.resize(8)
	_slot_pulse.fill(0.0)
	_slot_drop.resize(8)
	_slot_drop.fill(0.0)

	_fx = _rect(Color.WHITE, FX_SHADER)
	_fx.visible = false
	_vignette = _rect(Color.WHITE, VIGNETTE_SHADER)
	_grain = _rect(Color.WHITE, GRAIN_SHADER)
	_edge = _rect(Color.WHITE, EDGE_SHADER)
	_build_hud()
	_build_zone()
	_build_prompt()
	if ResourceLoader.exists(INDICATORS_PATH):
		_indicators = _add_script_control(INDICATORS_PATH)
	_build_subtitles()
	_build_extras()
	_flash = _rect(Color(0.0, 0.0, 0.01, 0.0))
	_black = _rect(Color(0.0, 0.0, 0.0, 0.0))
	_center = _center_label(40, Color(0.95, 0.9, 0.9), -20.0)
	_tip = _center_label(19, Style.MUTED, 50.0)
	_opening = _center_label(30, Color(0.88, 0.92, 0.95), 0.0)
	_opening.add_theme_font_override("font", Style.spaced_font())
	if ResourceLoader.exists(MAP_PATH):
		_map = _add_script_control(MAP_PATH)
	_build_menus()
	_connect_game_signals()
	_build_fps_label()
	Settings.apply_scene()
	_last_pebbles = Game.pebbles
	_apply_sub_size()
	if _map != null and _map.has_method("setup"):
		_map.call("setup", _player)
	if _indicators != null and _indicators.has_method("setup"):
		_indicators.call("setup", _player)


## Creates the title, end, pause, settings and credits menus and boot cards.
func _build_menus() -> void:
	_title_menu = TitleMenu.new()
	_title_menu.visible = false
	root.add_child(_title_menu)
	_title_menu.begin_pressed.connect(_on_title_begin)
	_title_menu.continue_pressed.connect(_on_title_continue)
	_title_menu.settings_pressed.connect(_on_title_settings)
	_title_menu.credits_pressed.connect(_open_credits)
	_title_menu.quit_pressed.connect(_on_title_quit)

	_end = EndMenu.new()
	root.add_child(_end)
	_end.play_again_pressed.connect(_on_end_play_again)
	_end.menu_pressed.connect(_on_quit_to_title)
	_end.deeper_pressed.connect(_on_end_deeper)

	_pause_menu = PauseMenu.new()
	root.add_child(_pause_menu)
	_pause_menu.resume_pressed.connect(_resume)
	_pause_menu.restart_pressed.connect(_on_pause_restart)
	_pause_menu.settings_pressed.connect(_on_pause_settings)
	_pause_menu.quit_pressed.connect(_on_quit_to_title)

	_settings = SettingsMenu.new()
	root.add_child(_settings)
	_settings.closed.connect(_on_settings_closed)

	_credits = CreditsMenu.new()
	root.add_child(_credits)
	_credits.closed.connect(_on_credits_closed)

	_boot = BootCards.new()
	root.add_child(_boot)
	_boot.finished.connect(_on_boot_finished)


## Listens to the game signals the UI reacts to.
func _connect_game_signals() -> void:
	Game.pebbles_changed.connect(_on_pebbles_changed)
	Game.subtitle.connect(_on_subtitle)
	Game.voice_log.connect(_on_voice_log)
	Game.zone_entered.connect(_on_zone)
	Game.prompt_requested.connect(_on_prompt)
	Game.player_fell.connect(_on_fell)
	Game.checkpoint_reached.connect(_on_checkpoint)
	Game.stat_changed.connect(_on_stat)
	Game.journal_page.connect(_on_journal_page)
	Game.level_event.connect(_on_level_event_ui)
	Echo.ping_emitted.connect(_on_ping)
	Settings.changed.connect(_apply_sub_size)
	_connect_combat()


## Small FPS counter in the top-left corner (Settings.show_fps).
func _build_fps_label() -> void:
	_fps_label = Style.label("", 16, Color(0.75, 0.95, 0.8, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	_fps_label.offset_left = 12.0
	_fps_label.offset_top = 8.0
	_fps_label.offset_right = 140.0
	_fps_label.offset_bottom = 30.0
	_fps_label.visible = false
	root.add_child(_fps_label)


# ---------------------------------------------------------------- Building

## A full-screen ColorRect, optionally drawn with a shader.
func _rect(color: Color, shader_code: String = "") -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.color = color
	if shader_code != "":
		var sh := Shader.new()
		sh.code = shader_code
		var mat := ShaderMaterial.new()
		mat.shader = sh
		r.material = mat
	root.add_child(r)
	return r


## Loads a Control script (map, indicators), adds it full-screen, or returns null.
func _add_script_control(path: String) -> Control:
	var script = load(path)
	if script == null:
		return null
	var c = script.new()
	var ctl := c as Control
	if ctl == null:
		if c is Node:
			(c as Node).queue_free()
		return null
	ctl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ctl)
	return ctl


## A centred, hidden label used for typed text on black.
func _center_label(font_size: int, color: Color, y: float) -> Label:
	var l := Style.label("", font_size, color)
	l.anchor_right = 1.0
	l.anchor_top = 0.5
	l.anchor_bottom = 0.5
	l.offset_left = 40.0
	l.offset_right = -40.0
	l.offset_top = y - 30.0
	l.offset_bottom = y + 30.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Lay out the whole line up front so typing doesn't shift it around.
	l.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	l.modulate.a = 0.0
	root.add_child(l)
	return l


## The HUD drawing layer and the speedrun timer label.
func _build_hud() -> void:
	_hud = Style.full_rect(Control.new())
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	root.add_child(_hud)
	_timer_label = Style.label("", 22, Color(0.85, 0.92, 0.95, 0.85), HORIZONTAL_ALIGNMENT_RIGHT)
	_timer_label.anchor_left = 1.0
	_timer_label.anchor_right = 1.0
	_timer_label.offset_left = -220.0
	_timer_label.offset_right = -24.0
	_timer_label.offset_top = 18.0
	_timer_label.offset_bottom = 48.0
	_timer_label.visible = false
	root.add_child(_timer_label)


## Hiding / chase overlay, breath bar, toast text and the presence bar.
func _build_extras() -> void:
	_extra = _rect(Color.WHITE, EXTRA_SHADER)
	_extra.visible = false
	_breath_bg = ColorRect.new()
	_breath_bg.color = Color(1, 1, 1, 0.15)
	_breath_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_breath_bg.anchor_left = 0.5
	_breath_bg.anchor_right = 0.5
	_breath_bg.anchor_top = 0.78
	_breath_bg.anchor_bottom = 0.78
	_breath_bg.offset_left = -80.0
	_breath_bg.offset_right = 80.0
	_breath_bg.offset_top = 0.0
	_breath_bg.offset_bottom = 6.0
	_breath_bg.visible = false
	root.add_child(_breath_bg)
	_breath_fill = ColorRect.new()
	_breath_fill.color = Color(0.7, 0.9, 1.0, 0.85)
	_breath_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_breath_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_breath_fill.anchor_right = 1.0
	_breath_bg.add_child(_breath_fill)
	_toast = Style.label("", 20, Style.CYAN)
	_toast.anchor_left = 0.0
	_toast.anchor_right = 1.0
	_toast.anchor_top = 0.0
	_toast.anchor_bottom = 0.0
	_toast.offset_top = 70.0
	_toast.offset_bottom = 100.0
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast)
	_build_presence()


## The PRESENCE bar at the bottom of the screen.
func _build_presence() -> void:
	_presence_root = Control.new()
	_presence_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_presence_root.anchor_left = 0.5
	_presence_root.anchor_right = 0.5
	_presence_root.anchor_top = 1.0
	_presence_root.anchor_bottom = 1.0
	_presence_root.offset_left = -PRESENCE_WIDTH * 0.5
	_presence_root.offset_right = PRESENCE_WIDTH * 0.5
	_presence_root.offset_top = -38.0
	_presence_root.offset_bottom = -35.0
	_presence_root.modulate.a = 0.0
	_presence_root.visible = false
	root.add_child(_presence_root)
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_presence_root.add_child(bg)
	_presence_fill = ColorRect.new()
	_presence_fill.color = PRESENCE_FAR
	_presence_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_presence_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_presence_fill.anchor_right = 0.0
	_presence_root.add_child(_presence_fill)
	var lbl := Style.label("PRESENCE", 12, Color(0.75, 0.8, 0.82, 0.7), HORIZONTAL_ALIGNMENT_RIGHT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.anchor_left = 0.0
	lbl.anchor_right = 0.0
	lbl.anchor_top = 0.5
	lbl.anchor_bottom = 0.5
	lbl.offset_left = -110.0
	lbl.offset_right = -10.0
	lbl.offset_top = -10.0
	lbl.offset_bottom = 10.0
	_presence_root.add_child(lbl)


## Updates the PRESENCE bar: how close the nearest Listener is.
func _update_presence(delta: float, live: bool) -> void:
	var target := 0.0
	if live:
		target = _dread
	# Smoothly follow the target (frame-rate independent).
	var follow := 1.0 - exp(-4.0 * delta)
	_presence = lerpf(_presence, target, follow)
	var vis := smoothstep(0.02, 0.1, _presence)
	_presence_root.visible = vis > 0.001 and Settings.presence_bar
	_presence_root.pivot_offset = _presence_root.size * Vector2(0.5, 1.0)
	_presence_root.scale = Vector2.ONE * clampf(float(Settings.hud_scale), 0.5, 2.0)
	if not _presence_root.visible:
		return
	var col: Color
	if _presence < 0.5:
		col = PRESENCE_FAR.lerp(PRESENCE_MID, smoothstep(0.15, 0.5, _presence))
	else:
		col = PRESENCE_MID.lerp(PRESENCE_NEAR, smoothstep(0.5, 0.9, _presence))
	_presence_fill.color = col
	_presence_fill.anchor_right = clampf(_presence, 0.0, 1.0)
	_presence_fill.offset_right = 0.0
	var pulse := 1.0
	if _presence > 0.8 and not Settings.reduce_shake:
		pulse = 0.8 + 0.2 * sin(_time * 5.0)
	_presence_root.modulate.a = vis * pulse


## Updates the hiding / chase screen darkening and the breath bar.
func _update_extras(delta: float, live: bool) -> void:
	var hiding: bool = live and _pget("is_hiding", false) == true
	var hide_target := 0.0
	if hiding:
		hide_target = 0.75
	_hide_amt = move_toward(_hide_amt, hide_target, delta * 2.0)
	var chase_target := 0.0
	if _chase and live:
		chase_target = 0.6
	_chase_amt = move_toward(_chase_amt, chase_target, delta * 1.5)
	_extra.visible = _hide_amt > 0.01 or _chase_amt > 0.01
	if _extra.visible:
		var m := _extra.material as ShaderMaterial
		if _hide_amt >= _chase_amt:
			m.set_shader_parameter("tint", Color(0.0, 0.02, 0.05))
			m.set_shader_parameter("amount", _hide_amt)
		else:
			m.set_shader_parameter("tint", Color(0.0, 0.0, 0.01))
			m.set_shader_parameter("amount", _chase_amt)
	var breath: float = _pget("breath", 1.0)
	var holding: bool = _pget("holding_breath", false) == true
	_breath_bg.visible = live and (holding or breath < 0.99)
	_breath_fill.anchor_right = clampf(breath, 0.0, 1.0)
	_update_presence(delta, live)


## Shows "Journal page found" briefly.
func _on_journal_page(_index: int, _text: String) -> void:
	_toast.text = "Journal page found"
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.3)
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.8)


## Chase start / end from the level script.
func _on_level_event_ui(event_name: String) -> void:
	if event_name == "chase_start":
		_chase = true
	elif event_name == "chase_end":
		_chase = false


## The big zone name label near the top.
func _build_zone() -> void:
	_zone_label = Style.label("", 40, Color(0.9, 0.95, 1.0))
	_zone_label.add_theme_font_override("font", Style.spaced_font())
	_zone_label.anchor_right = 1.0
	_zone_label.anchor_top = 0.2
	_zone_label.anchor_bottom = 0.2
	_zone_label.offset_bottom = 60.0
	_zone_label.modulate.a = 0.0
	_zone_label.draw.connect(_draw_zone_lines)
	root.add_child(_zone_label)


## Thin lines on both sides of the zone name.
func _draw_zone_lines() -> void:
	if _zone_label.text == "":
		return
	var font := _zone_label.get_theme_font("font")
	var w := font.get_string_size(_zone_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	var mid := _zone_label.size * 0.5 + Vector2(0, 2)
	var col := Color(0.24, 0.96, 1.0, 0.45)
	_zone_label.draw_line(mid - Vector2(w * 0.5 + 150.0, 0), mid - Vector2(w * 0.5 + 24.0, 0), col, 1.0)
	_zone_label.draw_line(mid + Vector2(w * 0.5 + 24.0, 0), mid + Vector2(w * 0.5 + 150.0, 0), col, 1.0)


## The control prompt box: "[key]  text".
func _build_prompt() -> void:
	_prompt_box = PanelContainer.new()
	_prompt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_box.add_theme_stylebox_override("panel", Style.box(Color(0.0, 0.0, 0.0, 0.55), 4, 14))
	_prompt_box.anchor_left = 0.5
	_prompt_box.anchor_right = 0.5
	_prompt_box.anchor_top = 0.66
	_prompt_box.anchor_bottom = 0.66
	_prompt_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_box.modulate.a = 0.0
	_prompt_box.visible = false
	root.add_child(_prompt_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_box.add_child(row)
	_prompt_key = Style.label("", 22, Style.GOLD)
	row.add_child(_prompt_key)
	_prompt_text = Style.label("", 22, Color(0.92, 0.95, 0.97))
	row.add_child(_prompt_text)


## The subtitle box: speaker, log counter and text.
func _build_subtitles() -> void:
	_sub_box = PanelContainer.new()
	_sub_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# High-contrast bar: near-black, so text reads over any echo.
	_sub_box.add_theme_stylebox_override("panel", Style.box(Color(0.0, 0.0, 0.0, 0.82), 6, 22))
	_sub_box.anchor_left = 0.5
	_sub_box.anchor_right = 0.5
	_sub_box.anchor_top = 1.0
	_sub_box.anchor_bottom = 1.0
	_sub_box.offset_left = -460.0
	_sub_box.offset_right = 460.0
	# Captions (ui_indicators.gd) sit near size.y - 120: stay above them.
	_sub_box.offset_top = -160.0
	_sub_box.offset_bottom = -160.0
	_sub_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_sub_box.visible = false
	root.add_child(_sub_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_box.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	_sub_speaker = Style.label("", 16, Style.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	_sub_speaker.add_theme_font_override("font", Style.spaced_font())
	_sub_speaker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_sub_speaker)
	_sub_counter = Style.label("", 14, Color(1.0, 0.85, 0.5, 0.8), HORIZONTAL_ALIGNMENT_RIGHT)
	top.add_child(_sub_counter)
	_sub_text = Style.label("", 26, Color(0.96, 0.96, 0.94), HORIZONTAL_ALIGNMENT_LEFT)
	_sub_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_sub_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_sub_text)


## Applies the subtitle size setting.
func _apply_sub_size() -> void:
	var idx := clampi(int(Settings.subtitle_size), 0, SUB_SIZES.size() - 1)
	var s: int = SUB_SIZES[idx]
	_sub_text.add_theme_font_size_override("font_size", s)
	_sub_speaker.add_theme_font_size_override("font_size", maxi(14, int(s * 0.65)))
	_sub_counter.add_theme_font_size_override("font_size", maxi(13, int(s * 0.55)))
	var half := 380.0 + 40.0 * idx
	_sub_box.offset_left = -half
	_sub_box.offset_right = half


# ---------------------------------------------------------------- Public API (director, main, cutscenes)

## How close danger is (0..1): drives the vignette and screen effects.
func set_dread(v: float) -> void:
	_dread = clampf(v, 0.0, 1.0)
	(_vignette.material as ShaderMaterial).set_shader_parameter("dread", _dread)


## Kept for callers: now a quick fade to dark rather than a red flash.
func flash_red() -> void:
	if Settings.no_flash:
		_pulse_edge(Color(0.0, 0.0, 0.0), 1.0, 1.6)
	else:
		_flash_in = 0.18


## Main menu, after the boot cards on the first visit.
func show_title() -> void:
	if Game.booted:
		set_black(1.0)
		fade_from_black(1.4)
		_title_menu.call("activate")
		_hide_mouse_until_moved()
	else:
		_boot.call("start")


## Hides the title menu and everything opened from it.
func hide_title(_instant: bool = false) -> void:
	_title_menu.call("deactivate")
	_settings.visible = false
	_credits.visible = false
	_boot.visible = false
	_mouse_hidden = false


## Sets the black cover instantly.
func set_black(alpha: float) -> void:
	if _black_tween != null:
		_black_tween.kill()
	_black.color.a = alpha


## Fades to black and waits until done.
func fade_to_black(seconds: float) -> void:
	if _black_tween != null:
		_black_tween.kill()
	_black_tween = create_tween()
	_black_tween.tween_property(_black, "color:a", 1.0, seconds)
	await _black_tween.finished


## Fades the black cover away.
func fade_from_black(seconds: float) -> void:
	if _black_tween != null:
		_black_tween.kill()
	_black_tween = create_tween()
	_black_tween.tween_property(_black, "color:a", 0.0, seconds)


## A short dip to black (restart from checkpoint, falling).
func dip_black(seconds: float) -> void:
	set_black(0.92)
	fade_from_black(seconds)


## The two opening lines, typed on black. Any key skips.
func play_opening_text() -> void:
	set_black(1.0)
	_opening_skip = false
	_opening.text = ""
	_opening.modulate.a = 1.0
	for line in OPENING:
		if _opening_skip:
			break
		_opening.modulate.a = 1.0
		await _type_into(_opening, str(line), 32.0)
		await _wait_or_skip(1.7)
		var tw := create_tween()
		tw.tween_property(_opening, "modulate:a", 0.0, 0.45)
		await tw.finished
	_opening.text = ""
	_opening.modulate.a = 0.0


## Caught, part 1: (flash) → black → "The Hollow heard you." + a tip.
## main.gd respawns the player when this returns, then calls caught_in().
func caught_out() -> void:
	_caught_busy = true
	if Settings.skip_jumpscare:
		# The director skips its flash in this mode: a gentle dark fade instead.
		_pulse_edge(Color(0.0, 0.0, 0.0), 1.0, 1.6)
	await get_tree().create_timer(0.55).timeout
	if _black_tween != null:
		_black_tween.kill()
	_black_tween = create_tween()
	_black_tween.tween_property(_black, "color:a", 1.0, 0.55)
	await _black_tween.finished
	_tip.text = _pick_tip()
	_tip.modulate.a = 0.0
	_center.add_theme_color_override("font_color", Color(1.0, 0.82, 0.84))
	_center.modulate.a = 1.0
	_opening_skip = false
	await _type_into(_center, "The Hollow heard you.", 28.0)
	var tw := create_tween()
	tw.tween_property(_tip, "modulate:a", 1.0, 0.6)
	await get_tree().create_timer(2.0).timeout


## The tip shown after being caught: the first tip the first time, then the
## rest in order, looping.
func _pick_tip() -> String:
	if Game.times_caught <= 1:
		return FIRST_TIP
	var index: int = (Game.times_caught - 2) % TIPS.size()
	return str(TIPS[index])


## Caught, part 2: fades the black and the text away together.
func caught_in() -> void:
	if _black_tween != null:
		_black_tween.kill()
	_black_tween = create_tween()
	# These three fades run at the same time.
	_black_tween.set_parallel(true)
	_black_tween.tween_property(_black, "color:a", 0.0, 1.0)
	_black_tween.tween_property(_center, "modulate:a", 0.0, 0.5)
	_black_tween.tween_property(_tip, "modulate:a", 0.0, 0.5)
	# Then, once all of them are done, mark the catch as over.
	_black_tween.chain()
	_black_tween.tween_callback(_end_caught)


## The catch sequence is over.
func _end_caught() -> void:
	_caught_busy = false


## Shows the end-of-run screen.
func show_end_screen(can_go_deeper: bool = false) -> void:
	_prompt_box.visible = false
	_sub_box.visible = false
	_sub_phase = 0
	set_black(0.0)
	_end.call("show_end", can_go_deeper, _count_logs(), _count_kind(4))


## A spoken line with a speaker tag ("SAM —"), for cutscenes and scripts.
func show_speaker_line(speaker: String, text: String) -> void:
	_show_line(speaker.to_upper() + "  —", text, "")


# ---------------------------------------------------------------- Frame update

## Runs every frame (even while paused) and updates every part of the UI.
func _process(delta: float) -> void:
	_time += delta
	var cut := _cutscene_playing()
	var playing := Game.state == Game.State.PLAYING and not cut
	_update_auto_pause()
	var live := playing and not get_tree().paused
	_update_catch_fade(delta)
	_update_screen_fx(delta)
	_hud.visible = playing
	_update_hud_fade(delta, live)
	_update_hud_anim(delta)
	_update_combat(delta)
	_hud.modulate.a = clampf(float(Settings.hud_opacity), 0.05, 1.0)
	_fps_label.visible = Settings.show_fps
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	if _hud.visible:
		_hud.queue_redraw()
	_timer_label.visible = Settings.speedrun_timer and Game.state != Game.State.TITLE and Game.state != Game.State.WON
	if _timer_label.visible:
		_timer_label.text = Style.format_time(Game.run_time, true)

	# Stat used by the "never ran" challenge.
	if live and _player != null and Game.get_stat("ran") == 0 and _pget("is_running", false):
		Game.add_stat("ran")

	_update_prompt(delta, live)
	_update_subtitle(delta)
	_update_extras(delta, live)


## Pause whenever the mouse is unlocked while playing. In a browser, Esc
## unlocks the mouse without the game ever seeing the key press. The map
## pauses the tree itself while open, so leave it alone then.
func _update_auto_pause() -> void:
	var map_open: bool = _map != null and _map.get("is_open") == true
	var should_pause := false
	if Game.state == Game.State.PLAYING:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not map_open:
			should_pause = true
	if not map_open and get_tree().paused != should_pause:
		get_tree().paused = should_pause
	if should_pause != _pause_shown:
		_set_pause(should_pause)


## Catch fade: darkens quickly, then lifts.
func _update_catch_fade(delta: float) -> void:
	if _flash_in > 0.0:
		_flash_in -= delta
		_flash_alpha = move_toward(_flash_alpha, 0.8, delta * 5.0)
	else:
		_flash_alpha = maxf(_flash_alpha - delta * 0.9, 0.0)
	_flash.color.a = _flash_alpha


## Chromatic aberration at high dread + the ripple of your own ping.
func _update_screen_fx(delta: float) -> void:
	if _ripple >= 0.0:
		_ripple += delta / 0.9
		if _ripple > 1.0:
			_ripple = -1.0
	var chroma := smoothstep(0.45, 1.0, _dread) * 0.006
	_fx.visible = _ripple >= 0.0 or chroma > 0.0003
	if not _fx.visible:
		return
	var fm := _fx.material as ShaderMaterial
	fm.set_shader_parameter("chroma", chroma)
	fm.set_shader_parameter("ripple", _ripple)
	fm.set_shader_parameter("ripple_strength", _ripple_strength)
	var aspect := root.size.x / maxf(root.size.y, 1.0)
	fm.set_shader_parameter("aspect", aspect)


## HUD: fades after a few seconds without input, back on any input
## (and stays up while a cooldown is running).
func _update_hud_fade(delta: float, live: bool) -> void:
	if live:
		_idle += delta
	var ping_cool: float = _pget("ping_cooldown", 0.0)
	var whisper_cool: float = _pget("whisper_cooldown", 0.0)
	var cooling: bool = ping_cool > 0.0 or whisper_cool > 0.0
	var hud_target := 0.0
	if _idle < HUD_IDLE or cooling:
		hud_target = 1.0
	# Fade in fast, fade out slowly.
	var speed := 0.8
	if hud_target > _hud_alpha:
		speed = 3.0
	_hud_alpha = move_toward(_hud_alpha, hud_target, delta * speed)


## True while main.gd's cutscene node is playing one.
func _cutscene_playing() -> bool:
	if _main == null:
		return false
	var cs = _main.get("cutscene")
	if cs == null or not is_instance_valid(cs):
		return false
	return cs.get("playing") == true


## Reads a property from the player, or `fallback` if there is no player
## or the property doesn't exist.
func _pget(prop: String, fallback: Variant) -> Variant:
	if _player == null or not is_instance_valid(_player):
		return fallback
	var v: Variant = _player.get(prop)
	if v == null:
		return fallback
	return v


## Timers for the HUD animations (crosshair spread, ready flash, pebble pulses).
func _update_hud_anim(delta: float) -> void:
	var running: bool = _pget("is_running", false)
	var sneaking: bool = _pget("is_sneaking", false)
	# Crosshair spread: +1 running, -1 sneaking, 0 walking.
	var target := 0.0
	if running:
		target = 1.0
	elif sneaking:
		target = -1.0
	var follow := 1.0 - exp(-10.0 * delta)
	_spread = lerpf(_spread, target, follow)
	var cool: float = _pget("ping_cooldown", 0.0)
	if _last_cooldown > 0.0 and cool <= 0.0:
		_ready_flash = 1.0
	_last_cooldown = cool
	_ready_flash = maxf(_ready_flash - delta / 0.35, 0.0)
	var whisper: float = _pget("whisper_cooldown", 0.0)
	if whisper > _whisper_max:
		_whisper_max = whisper
	for i in _slot_pulse.size():
		_slot_pulse[i] = maxf(_slot_pulse[i] - delta * 2.2, 0.0)
		_slot_drop[i] = maxf(_slot_drop[i] - delta * 1.8, 0.0)
	_empty_shake = maxf(_empty_shake - delta, 0.0)


## Draws the whole HUD. The crosshair group scales around the screen centre,
## the health / pebble group around the bottom-left corner.
func _draw_hud() -> void:
	var size := _hud.size
	var c := size * 0.5
	var a := _hud_alpha
	# The crosshair never fades below 40%.
	var cross_a := maxf(a, 0.4)
	var hs := clampf(float(Settings.hud_scale), 0.5, 2.0)

	# Crosshair group.
	_hud.draw_set_transform(c * (1.0 - hs), 0.0, Vector2(hs, hs))
	_draw_noise_ring(c, cross_a)
	_draw_crosshair(c, cross_a)
	_draw_ping_cooldown(c, cross_a)
	_draw_whisper_cooldown(c, cross_a)
	_draw_stamina(c, cross_a)
	_draw_attack_ring(c, cross_a)

	# Bottom-left group.
	_hud.draw_set_transform(Vector2(0.0, size.y) * (1.0 - hs), 0.0, Vector2(hs, hs))
	# Health stays at least half visible right after a hit or while hurt.
	var health_a := a
	if _hp_hit > 0.0 or _hp < _hp_max:
		health_a = maxf(a, 0.55)
	_draw_health(Vector2(38.0, size.y - 80.0), health_a)
	_draw_pebbles_and_upgrades(size, a)

	_hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_damage_numbers()


## Noise ring while running: how far your footsteps carry.
func _draw_noise_ring(c: Vector2, cross_a: float) -> void:
	var noise: float = _pget("noise_radius", 0.0)
	if not _pget("is_running", false) or noise <= 0.0:
		return
	var nr := 26.0 + noise * 5.0
	var alpha := (0.09 + 0.04 * sin(_time * 9.0)) * cross_a
	_hud.draw_arc(c, nr, 0.0, TAU, 64, Color(1.0, 0.4, 0.4, alpha), 1.5, true)


## Crosshair dot: smaller and dimmer sneaking, ticks spread out running.
func _draw_crosshair(c: Vector2, cross_a: float) -> void:
	var sneak_t := maxf(-_spread, 0.0)
	var run_t := maxf(_spread, 0.0)
	var dot_r := 2.2 - sneak_t * 0.8
	var dot_a := (0.85 - sneak_t * 0.35) * cross_a
	match int(Settings.crosshair_style):
		0:
			_hud.draw_circle(c, dot_r + 1.2, Color(0.0, 0.0, 0.0, 0.45 * dot_a))
			_hud.draw_circle(c, dot_r, Color(1.0, 1.0, 1.0, dot_a))
		1:
			var gap := 3.0 + run_t * 4.0
			for i in 4:
				var d := Vector2.from_angle(i * PI * 0.5)
				_hud.draw_line(c + d * gap, c + d * (gap + 6.0), Color(0.0, 0.0, 0.0, 0.5 * dot_a), 3.5)
				_hud.draw_line(c + d * gap, c + d * (gap + 6.0), Color(1.0, 1.0, 1.0, dot_a), 1.5)
	if run_t > 0.03:
		var r0 := 6.0 + 7.0 * run_t
		for i in 4:
			var dir := Vector2.from_angle(PI * 0.25 + i * PI * 0.5)
			_hud.draw_line(c + dir * r0, c + dir * (r0 + 5.0), Color(1.0, 1.0, 1.0, 0.6 * run_t * cross_a), 1.5, true)


## Ping cooldown ring, and a soft "ready" pulse when it comes back.
func _draw_ping_cooldown(c: Vector2, cross_a: float) -> void:
	var cyan := Style.CYAN
	var cool: float = _pget("ping_cooldown", 0.0)
	if cool > 0.001:
		var full_time := maxf(Game.ping_cooldown, 0.05)
		var frac := clampf(cool / full_time, 0.0, 1.0)
		# Faint full ring behind.
		_hud.draw_arc(c, 16.0, 0.0, TAU, 48, Color(cyan.r, cyan.g, cyan.b, 0.12 * cross_a), 2.0, true)
		# Bright part: the time still left, starting at the top.
		var start := -PI * 0.5
		var end_angle := start + TAU * frac
		_hud.draw_arc(c, 16.0, start, end_angle, 48, Color(cyan.r, cyan.g, cyan.b, 0.85 * cross_a), 2.5, true)
		var tip_pos := c + Vector2.from_angle(end_angle) * 16.0
		_hud.draw_circle(tip_pos, 2.0, Color(1.0, 1.0, 1.0, 0.9 * cross_a))
	if _ready_flash > 0.0:
		var t := 1.0 - _ready_flash
		var ready_a := 0.6 * _ready_flash * cross_a
		_hud.draw_arc(c, 16.0 + t * 10.0, 0.0, TAU, 48, Color(cyan.r, cyan.g, cyan.b, ready_a), 2.0, true)


## Whisper cooldown: thinner inner ring.
func _draw_whisper_cooldown(c: Vector2, cross_a: float) -> void:
	var whisper: float = _pget("whisper_cooldown", 0.0)
	if whisper <= 0.001:
		return
	var wf := clampf(whisper / maxf(_whisper_max, 0.1), 0.0, 1.0)
	var start := -PI * 0.5
	var end_angle := start + TAU * wf
	_hud.draw_arc(c, 9.5, start, end_angle, 32, Color(0.8, 0.95, 1.0, 0.55 * cross_a), 1.5, true)


## Stamina: a thin bar under the crosshair while it drains or refills.
func _draw_stamina(c: Vector2, cross_a: float) -> void:
	var stamina: float = _pget("stamina", 1.0)
	if stamina >= 0.995:
		return
	var winded: bool = _pget("is_winded", false)
	var bar := Rect2(c + Vector2(-24.0, 26.0), Vector2(48.0, 3.0))
	# Red when out of breath, pale blue otherwise.
	var bar_col := Color(0.85, 0.95, 1.0, 0.6)
	if winded:
		bar_col = Color(1.0, 0.3, 0.32, 0.85)
	_hud.draw_rect(bar, Color(0.0, 0.0, 0.0, 0.45 * cross_a))
	var fill_width := bar.size.x * clampf(stamina, 0.0, 1.0)
	var fill := Rect2(bar.position, Vector2(fill_width, bar.size.y))
	_hud.draw_rect(fill, Color(bar_col.r, bar_col.g, bar_col.b, bar_col.a * cross_a))


## Pebbles (gold dots, faint empty slots, pulse on pickup, drop on throw),
## then the echo crystal upgrade icons after them.
func _draw_pebbles_and_upgrades(size: Vector2, a: float) -> void:
	var base := Vector2(44.0, size.y - 46.0)
	if _empty_shake > 0.0:
		base += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 4.0 * _empty_shake
	var slots := clampi(Game.max_pebbles, 0, _slot_pulse.size())
	var gold := Style.GOLD
	for i in slots:
		var p := base + Vector2(i * 24.0, 0.0)
		if i < Game.pebbles:
			var pr := 6.0 * (1.0 + 0.6 * _slot_pulse[i])
			_hud.draw_circle(p, pr + 4.0, Color(gold.r, gold.g, gold.b, 0.12 * a + 0.3 * _slot_pulse[i]))
			_hud.draw_circle(p, pr, Color(gold.r, gold.g, gold.b, 0.95 * maxf(a, _slot_pulse[i])))
		else:
			_hud.draw_arc(p, 6.0, 0.0, TAU, 24, Color(gold.r, gold.g, gold.b, 0.22 * a), 1.2, true)
			if _slot_drop[i] > 0.0:
				# A thrown pebble shrinks and floats up out of its slot.
				var d := _slot_drop[i]
				var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 2.5 * d
				var rise := Vector2(0.0, -(1.0 - d) * 12.0)
				_hud.draw_circle(p + jitter + rise, 6.0 * d, Color(gold.r, gold.g, gold.b, d))
	if Game.pebbles == 0 and _empty_shake > 0.0:
		_hud.draw_string(Style.FONT, base + Vector2(-6.0, -18.0), "OUT OF PEBBLES", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.5, 0.45, _empty_shake))

	# Echo crystal upgrades: small icons after the pebbles.
	var x := base.x + slots * 24.0 + 18.0
	for u in Game.upgrades:
		_draw_upgrade(Vector2(x, base.y), int(u), a)
		x += 24.0


## One small echo crystal upgrade icon.
func _draw_upgrade(p: Vector2, kind: int, a: float) -> void:
	var col := Color(CRYSTAL.r, CRYSTAL.g, CRYSTAL.b, 0.9 * a)
	match kind:
		0:
			# Ping radius: arcs spreading outward.
			_hud.draw_circle(p + Vector2(-5, 0), 1.8, col)
			for r in [4.0, 7.5, 11.0]:
				_hud.draw_arc(p + Vector2(-5, 0), r, -0.8, 0.8, 12, col, 1.4, true)
		1:
			# Cooldown: a small clock.
			_hud.draw_arc(p, 7.0, 0.0, TAU, 24, col, 1.4, true)
			_hud.draw_line(p, p + Vector2(0, -5), col, 1.4, true)
			_hud.draw_line(p, p + Vector2(4, 0), col, 1.4, true)
		_:
			# Max pebbles: a stone and a plus.
			_hud.draw_circle(p + Vector2(-3, 1), 4.0, col)
			_hud.draw_line(p + Vector2(4, -6), p + Vector2(10, -6), col, 1.5)
			_hud.draw_line(p + Vector2(7, -9), p + Vector2(7, -3), col, 1.5)


# ---------------------------------------------------------------- Prompts

## Queues a control prompt (each one shows only once, except "interact").
func _on_prompt(id: String) -> void:
	if not PROMPTS.has(id):
		return
	if id == "pebbles_empty":
		var now := Time.get_ticks_msec() / 1000.0
		_empty_shake = 1.0
		_idle = 0.0
		if now - _last_empty < 4.0:
			return
		_last_empty = now
		if _prompt_id != "" and _prompt_id != "pebbles_empty" and not _prompt_queue.has(_prompt_id):
			_prompt_queue.push_front(_prompt_id)
		_show_prompt(id)
		return
	if _prompt_id == id or _prompt_queue.has(id):
		return
	if not REPEATABLE.has(id):
		if _prompts_seen.has(id):
			return
		# Already did it before being told (areas reached out of order): skip.
		var action: String = PROMPTS[id][0]
		if _done_actions.has(action):
			_prompts_seen[id] = true
			return
	_prompt_queue.append(id)


## Shows one prompt now.
func _show_prompt(id: String) -> void:
	_prompt_id = id
	_prompt_age = 0.0
	_prompts_seen[id] = true
	var action: String = PROMPTS[id][0]
	var text: String = PROMPTS[id][1]
	# Sneak and run text depends on whether they are toggles or holds.
	if id == "sneak":
		if Settings.toggle_sneak:
			text = "Press to sneak: your footsteps go silent."
		else:
			text = "Hold to sneak: your footsteps go silent."
	elif id == "run":
		if Settings.toggle_run:
			text = "Press to run: fast, but loud."
		else:
			text = "Hold to run: fast, but loud."
	var key := ""
	if action != "":
		key = Style.key_name(action)
	_prompt_key.text = key
	_prompt_key.visible = key != ""
	_prompt_text.text = text
	# "Out of pebbles" is shown in red, everything else in white.
	var text_color := Color(0.92, 0.95, 0.97)
	if id == "pebbles_empty":
		text_color = Color(1.0, 0.6, 0.55)
	_prompt_text.add_theme_color_override("font_color", text_color)
	_prompt_box.reset_size()
	if _prompt_tween != null:
		_prompt_tween.kill()
	_prompt_box.visible = true
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt_box, "modulate:a", 1.0, 0.3)


## Fades the prompt out and waits a moment before the next one.
func _hide_prompt() -> void:
	_prompt_id = ""
	_prompt_gap = 0.7
	if _prompt_tween != null:
		_prompt_tween.kill()
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt_box, "modulate:a", 0.0, 0.4)


## Hides the prompt when its action is used or it times out; shows the next.
func _update_prompt(delta: float, live: bool) -> void:
	_prompt_box.visible = live and (_prompt_id != "" or _prompt_box.modulate.a > 0.01)
	# Keep it centred as its text changes width.
	_prompt_box.offset_left = -_prompt_box.size.x * 0.5
	_prompt_box.offset_right = _prompt_box.size.x * 0.5
	if not live:
		return
	if _prompt_id != "":
		_prompt_age += delta
		var action: String = PROMPTS[_prompt_id][0]
		var timeout := 9.0
		if _prompt_id == "pebbles_empty":
			timeout = 2.5
		elif _prompt_id == "interact":
			timeout = 6.0
		var done := action != "" and _prompt_age > 0.4 and Input.is_action_just_pressed(action)
		if done or _prompt_age > timeout:
			_hide_prompt()
	elif _prompt_gap > 0.0:
		_prompt_gap -= delta
	elif not _prompt_queue.is_empty():
		_show_prompt(_prompt_queue.pop_front())


# ---------------------------------------------------------------- Subtitles / voice logs / zone

## A plain subtitle line.
func _on_subtitle(text: String) -> void:
	_show_line("", text, "")


## One of Mara's logs: speaker tag, log counter and (if enabled) text.
func _on_voice_log(index: int, text: String) -> void:
	Game.log_texts[index] = text
	# Count this log as found even if Game hasn't added it to the list yet.
	var found := Game.logs_found.size()
	if not Game.logs_found.has(index):
		found += 1
	var counter := "LOG %d / %d" % [found, _count_logs()]
	if Settings.subtitles:
		_show_line("MARA  —", text, counter)
	else:
		_show_line("MARA  —", "", counter)


## Shows a subtitle line and starts typing it.
func _show_line(speaker: String, text: String, counter: String) -> void:
	_sub_speaker.text = speaker
	_sub_speaker.visible = speaker != "" or counter != ""
	_sub_counter.text = counter
	_sub_text.text = text
	_sub_text.visible = text != ""
	_sub_text.visible_characters = 0
	_sub_chars = 0.0
	_sub_hold = 2.6 + text.length() * 0.055
	# With text: start typing it (1). Without: just hold the header (2).
	if text != "":
		_sub_phase = 1
	else:
		_sub_phase = 2
	if _sub_tween != null:
		_sub_tween.kill()
	_sub_box.visible = true
	_sub_box.reset_size()
	_sub_box.offset_top = _sub_box.offset_bottom
	_sub_tween = create_tween()
	_sub_tween.tween_property(_sub_box, "modulate:a", 1.0, 0.2)


## Subtitle phases: typing (1) -> holding (2) -> fading (3) -> hidden (0).
func _update_subtitle(delta: float) -> void:
	match _sub_phase:
		1:
			_sub_chars += delta * 45.0
			if _sub_chars >= _sub_text.text.length():
				_sub_text.visible_characters = -1
				_sub_phase = 2
			else:
				_sub_text.visible_characters = int(_sub_chars)
		2:
			_sub_hold -= delta
			if _sub_hold <= 0.0:
				_sub_phase = 3
				if _sub_tween != null:
					_sub_tween.kill()
				_sub_tween = create_tween()
				_sub_tween.tween_property(_sub_box, "modulate:a", 0.0, 0.6)
				_sub_tween.tween_callback(_sub_hidden)


## Called when the subtitle fade-out finishes.
func _sub_hidden() -> void:
	if _sub_phase == 3:
		_sub_phase = 0
		_sub_box.visible = false


## Shows the zone name for a few seconds.
func _on_zone(zone_name: String) -> void:
	if zone_name == "":
		return
	_zone_label.text = zone_name.to_upper()
	_zone_label.queue_redraw()
	if _zone_tween != null:
		_zone_tween.kill()
	_zone_tween = create_tween()
	_zone_tween.tween_property(_zone_label, "modulate:a", 1.0, 0.9)
	_zone_tween.tween_interval(2.4)
	_zone_tween.tween_property(_zone_label, "modulate:a", 0.0, 1.3)


# ---------------------------------------------------------------- Game events

## Pulses new pebble slots, or drops thrown ones.
func _on_pebbles_changed(count: int) -> void:
	if count > _last_pebbles:
		for i in range(_last_pebbles, mini(count, _slot_pulse.size())):
			_slot_pulse[i] = 1.0
	elif count < _last_pebbles:
		for i in range(count, mini(_last_pebbles, _slot_drop.size())):
			_slot_drop[i] = 1.0
	_last_pebbles = count
	_idle = 0.0


## Any stat change briefly wakes the HUD.
func _on_stat(_stat_name: String, _value: int) -> void:
	_idle = minf(_idle, HUD_IDLE - 1.5)


## Gold glow at the screen edges.
func _on_checkpoint() -> void:
	# A warm glow at the screen edges instead of a "Checkpoint" message.
	_pulse_edge(Style.GOLD, 1.0, 1.9)
	_idle = 0.0


## Shows "You fell." over a dip to black.
func _on_fell() -> void:
	if _caught_busy:
		return
	dip_black(1.0)
	_center.text = "You fell."
	_center.visible_characters = -1
	_center.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	if _center_tween != null:
		_center_tween.kill()
	_center_tween = create_tween()
	_center.modulate.a = 1.0
	_center_tween.tween_interval(1.0)
	_center_tween.tween_property(_center, "modulate:a", 0.0, 0.6)


## Starts the screen ripple when the player pings.
func _on_ping(origin: Vector3, _radius: float, loud: bool) -> void:
	if _player == null or Game.state != Game.State.PLAYING:
		return
	if origin.distance_to(_player.global_position + Vector3.UP * 0.8) < 2.5:
		_ripple = 0.0
		if loud:
			_ripple_strength = 1.0
		else:
			_ripple_strength = 0.45
		_idle = 0.0


## Glows the screen edges in `color` up to `peak`, then fades.
func _pulse_edge(color: Color, peak: float, seconds: float) -> void:
	var m := _edge.material as ShaderMaterial
	m.set_shader_parameter("tint", color)
	if _edge_tween != null:
		_edge_tween.kill()
	_edge_tween = create_tween()
	_edge_tween.tween_method(_set_edge, 0.0, peak, seconds * 0.25).set_trans(Tween.TRANS_SINE)
	_edge_tween.tween_method(_set_edge, peak, 0.0, seconds * 0.75).set_trans(Tween.TRANS_SINE)


## Tween helper: sets the edge glow amount.
func _set_edge(v: float) -> void:
	(_edge.material as ShaderMaterial).set_shader_parameter("amount", v)


# ---------------------------------------------------------------- Menus

## Calls a function on main.gd by name, if it exists.
func _call_main(method: String) -> void:
	if _main != null and _main.has_method(method):
		_main.call(method)


# Menu button handlers: each just forwards to main.gd or opens a menu.

func _on_title_begin() -> void:
	_call_main("begin_new_run")


func _on_title_continue() -> void:
	_call_main("continue_run")


func _on_title_settings() -> void:
	_open_settings("title")


func _on_title_quit() -> void:
	_call_main("quit_game")


func _on_end_play_again() -> void:
	_call_main("play_again")


func _on_end_deeper() -> void:
	_call_main("go_deeper")


func _on_quit_to_title() -> void:
	_call_main("quit_to_title")


func _on_pause_restart() -> void:
	_call_main("restart_from_checkpoint")


func _on_pause_settings() -> void:
	_open_settings("pause")


## Boot cards are done: show the main menu.
func _on_boot_finished() -> void:
	Game.booted = true
	_title_menu.call("activate")
	_hide_mouse_until_moved()


## Hides the mouse on the title screen until it moves.
func _hide_mouse_until_moved() -> void:
	if Game.state == Game.State.TITLE and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_mouse_hidden = true


## Opens the settings menu from the title or pause menu.
func _open_settings(from: String) -> void:
	_settings_from = from
	if from == "title":
		_title_menu.visible = false
	_settings.call("open")


## Goes back to whichever menu opened settings.
func _on_settings_closed() -> void:
	if _settings_from == "title" and Game.state == Game.State.TITLE:
		_title_menu.visible = true
		_title_menu.call("refresh")
		_title_menu.call("focus_first")
	elif _pause_shown:
		_pause_menu.call("open")
	_settings_from = ""


## Opens the credits from the title menu.
func _open_credits() -> void:
	_title_menu.visible = false
	_credits.call("open")


## Back to the title menu.
func _on_credits_closed() -> void:
	if Game.state == Game.State.TITLE:
		_title_menu.visible = true
		_title_menu.call("focus_first")


## Opens or closes the pause menu (and muffles audio).
func _set_pause(on: bool) -> void:
	_pause_shown = on
	Sfx.set_muffled(on)
	if on:
		_pause_menu.set("total_logs", _count_logs())
		_pause_menu.call("open")
	else:
		_pause_menu.call("close")
		if _settings.visible and _settings_from == "pause":
			_settings.call("close")


## Re-locks the mouse, which unpauses the game.
func _resume() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Counts pickups of a given kind in the current scene.
func _count_kind(kind: int) -> int:
	var scene := get_tree().current_scene
	if scene == null:
		return 0
	var n := 0
	for node in scene.find_children("*", "Area3D", true, false):
		if "kind" in node and "log_index" in node and int(node.get("kind")) == kind:
			n += 1
	return n


## Total number of voice logs in the level (counted once). Falls back to 8.
func _count_logs() -> int:
	if _total_logs < 0:
		_total_logs = _count_kind(2)
	if _total_logs > 0:
		return _total_logs
	return 8


# ---------------------------------------------------------------- Input

## Remembers the last input device, wakes the HUD, tracks which actions
## were used, and lets any key skip the opening lines.
func _input(event: InputEvent) -> void:
	# Last device used (prompts show keys or pad buttons), and HUD wake-up.
	var is_pad := false
	if event is InputEventJoypadButton:
		is_pad = true
	elif event is InputEventJoypadMotion:
		var stick := event as InputEventJoypadMotion
		if absf(stick.axis_value) > 0.5:
			is_pad = true
	if is_pad:
		Style.using_pad = true
		_idle = 0.0
	elif event is InputEventKey or event is InputEventMouseButton:
		Style.using_pad = false
		_idle = 0.0
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() > 2.0:
			_idle = 0.0
			if _mouse_hidden:
				_mouse_hidden = false
				if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if Game.state == Game.State.PLAYING:
		for id in PROMPTS:
			var action: String = PROMPTS[id][0]
			if action != "" and event.is_action_pressed(action):
				_done_actions[action] = true

	# Any key / click / button skips the typed opening lines.
	if _opening.modulate.a > 0.0 and _opening.text != "":
		var pressed := false
		if event is InputEventKey and event.is_pressed() and not event.is_echo():
			pressed = true
		elif event is InputEventMouseButton and event.is_pressed():
			pressed = true
		elif event is InputEventJoypadButton and event.is_pressed():
			pressed = true
		if pressed:
			_opening_skip = true
			get_viewport().set_input_as_handled()


## While paused: a click resumes; Esc goes back a menu or resumes.
func _unhandled_input(event: InputEvent) -> void:
	if not _pause_shown or _settings.visible:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		# Browsers only lock the mouse again on a click.
		_resume()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if not bool(_pause_menu.call("back")):
			_resume()


## Alt-tab / clicking away pauses (the mouse is released first).
func _notification(what: int) -> void:
	# Alt-tab / clicking away pauses (the mouse is released first).
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and Game.state == Game.State.PLAYING:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------------- Helpers

## Types `text` into `label` letter by letter (skippable).
func _type_into(label: Label, text: String, chars_per_second: float) -> void:
	label.text = text
	label.visible_characters = 0
	var shown := 0.0
	while shown < text.length() and not _opening_skip:
		await get_tree().process_frame
		shown += get_process_delta_time() * chars_per_second
		label.visible_characters = int(shown)
	label.visible_characters = -1


## Waits `seconds`, or less if the player skips.
func _wait_or_skip(seconds: float) -> void:
	var t := 0.0
	while t < seconds and not _opening_skip:
		await get_tree().process_frame
		t += get_process_delta_time()


# ---------------------------------------------------------------- Combat HUD
# Everything here reads Game / player defensively: the combat fields and
# signals may not exist in every build.

## Connects to the combat signals that exist in this build.
func _connect_combat() -> void:
	if Game.has_signal("health_changed"):
		Game.connect("health_changed", _on_health_changed)
	if Game.has_signal("player_damaged"):
		Game.connect("player_damaged", _on_player_damaged)
	for sig in ["listener_damaged", "listener_hit", "enemy_damaged"]:
		if Game.has_signal(sig):
			Game.connect(sig, _on_listener_damaged)
			break
	_read_health()


## Reads the player health from Game.
func _read_health() -> void:
	if "player_health" in Game:
		_hp = float(Game.get("player_health"))
	if "player_max_health" in Game:
		_hp_max = maxf(float(Game.get("player_max_health")), 1.0)
	if _hp_lag < 0.0:
		_hp_lag = _hp


## True when damage is on and health is known.
func _combat_on() -> bool:
	return Settings.damage_enabled and _hp >= 0.0


## New health value: flash the bar on a loss.
func _on_health_changed(hp: Variant = null, max_hp: Variant = null) -> void:
	var old := _hp
	if hp != null:
		_hp = float(hp)
	if max_hp != null:
		_hp_max = maxf(float(max_hp), 1.0)
	if old >= 0.0 and _hp < old:
		_hp_hit = 1.0
	elif _hp > _hp_lag:
		_hp_lag = _hp
	_idle = 0.0


## Player got hit: flash the bar and the red screen edge.
func _on_player_damaged(_amount: Variant = null, _from: Variant = null) -> void:
	_hp_hit = 1.0
	_idle = 0.0
	if not Settings.damage_enabled:
		return
	if Settings.damage_vignette and not Settings.no_flash:
		_pulse_edge(Color(0.55, 0.0, 0.02), 1.0, 0.9)
	elif Settings.damage_vignette:
		_pulse_edge(Color(0.25, 0.0, 0.0), 0.5, 1.4)


## A Listener got hit: show a floating damage number.
func _on_listener_damaged(a: Variant = null, b: Variant = null, c: Variant = null) -> void:
	if not Settings.damage_numbers or not Settings.damage_enabled:
		return
	# The signal's arguments can come in any order: look for a position
	# (a Vector3 or a Node3D) and an amount (a number).
	var amount := -1.0
	var pos: Variant = null
	for v in [a, b, c]:
		if v is Vector3 and pos == null:
			pos = v
		elif v is Node3D and pos == null and is_instance_valid(v):
			var node: Node3D = v
			pos = node.global_position + Vector3(0.0, 1.6, 0.0)
		elif (v is float or v is int) and amount < 0.0:
			amount = float(v)
	if pos == null or amount < 0.0:
		return
	# Whole numbers show as "5", others as "2.5".
	var text := "%.1f" % amount
	if absf(amount - roundf(amount)) < 0.05:
		text = str(roundi(amount))
	_dmg_numbers.append({"pos": pos, "text": text, "age": 0.0, "dx": randf_range(-12.0, 12.0)})
	if _dmg_numbers.size() > 12:
		_dmg_numbers.pop_front()


## Health bar animation, strike cooldown and damage number ageing.
func _update_combat(delta: float) -> void:
	if _hp < 0.0 or not Game.has_signal("health_changed"):
		_read_health()
	_hp_hit = maxf(_hp_hit - delta * 2.0, 0.0)
	if _hp_lag > _hp:
		# The "lost health" segment waits a moment after a hit, then drains.
		var drain_speed := 0.6
		if _hp_hit > 0.3:
			drain_speed = 0.15
		_hp_lag = move_toward(_hp_lag, _hp, delta * _hp_max * drain_speed)
	else:
		_hp_lag = _hp
	var cool: float = float(_pget("attack_cooldown", 0.0))
	if cool > _attack_max:
		_attack_max = cool
	for i in range(_dmg_numbers.size() - 1, -1, -1):
		_dmg_numbers[i]["age"] += delta
		if _dmg_numbers[i]["age"] > 1.1:
			_dmg_numbers.remove_at(i)


## Health bar with a trailing "lost health" segment.
func _draw_health(p: Vector2, a: float) -> void:
	if not _combat_on():
		return
	var w := 160.0
	var h := 8.0
	var frac := clampf(_hp / _hp_max, 0.0, 1.0)
	var lag := clampf(_hp_lag / _hp_max, 0.0, 1.0)
	var low := frac <= 0.3
	# Low health: brighter red that pulses (no pulse with flashes off).
	var pulse := 1.0
	if low and not Settings.no_flash:
		pulse = 0.75 + 0.25 * sin(_time * 6.0)
	var col := Color(0.78, 0.2, 0.18).lerp(Color(0.9, 0.85, 0.8), 0.25)
	if low:
		col = Color(0.86, 0.16, 0.14)
	var shake := Vector2.ZERO
	if _hp_hit > 0.0 and Settings.camera_shake > 0.05:
		shake = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 3.0 * _hp_hit * Settings.camera_shake
	var r := Rect2(p + shake, Vector2(w, h))
	_hud.draw_rect(r.grow(2.0), Color(0.0, 0.0, 0.0, 0.5 * a))
	_hud.draw_rect(r, Color(0.25, 0.05, 0.05, 0.55 * a))
	if lag > frac:
		_hud.draw_rect(Rect2(r.position + Vector2(w * frac, 0.0), Vector2(w * (lag - frac), h)), Color(1.0, 0.85, 0.6, 0.7 * a))
	_hud.draw_rect(Rect2(r.position, Vector2(w * frac, h)), Color(col.r, col.g, col.b, 0.92 * a * pulse))
	if _hp_hit > 0.0:
		_hud.draw_rect(r, Color(1.0, 1.0, 1.0, 0.35 * _hp_hit * a), false, 1.5)
	var label := "%d / %d" % [ceili(maxf(_hp, 0.0)), roundi(_hp_max)]
	_hud.draw_string(ThemeDB.fallback_font, r.position + Vector2(0.0, -6.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.85, 0.82, 0.8 * a))
	# Dagger icon next to the bar once the player carries it.
	if _has_dagger():
		_draw_dagger(r.position + Vector2(w + 22.0, h * 0.5), a)


## True once the player has picked up a dagger.
func _has_dagger() -> bool:
	if not ("has_dagger" in Game):
		return false
	return bool(Game.get("has_dagger"))


## Small dagger icon, with its strike cooldown ring.
func _draw_dagger(p: Vector2, a: float) -> void:
	var blade := Color(0.85, 0.9, 0.95, 0.9 * a)
	var grip := Color(0.55, 0.38, 0.22, 0.9 * a)
	var tip := p + Vector2(8.0, -8.0)
	var guard := p + Vector2(-2.0, 2.0)
	# Blade: a thin triangle from the guard to the tip.
	var blade_shape := PackedVector2Array()
	blade_shape.append(tip)
	blade_shape.append(guard + Vector2(-1.5, -1.5))
	blade_shape.append(guard + Vector2(1.5, 1.5))
	_hud.draw_colored_polygon(blade_shape, blade)
	# Cross-guard.
	_hud.draw_line(guard + Vector2(-1.0, 1.0), guard + Vector2(4.0, -2.0), grip, 2.0, true)
	# Handle.
	_hud.draw_line(guard, guard + Vector2(-6.0, 6.0), grip, 2.5, true)
	var cool: float = float(_pget("attack_cooldown", 0.0))
	if cool > 0.001:
		var f := clampf(cool / maxf(_attack_max, 0.05), 0.0, 1.0)
		_hud.draw_arc(p, 12.0, -PI * 0.5, -PI * 0.5 + TAU * f, 24, Color(1.0, 0.6, 0.5, 0.8 * a), 2.0, true)


## Small ring around the crosshair while the strike recovers.
func _draw_attack_ring(c: Vector2, a: float) -> void:
	if not _combat_on():
		return
	if not _has_dagger():
		return
	var cool: float = float(_pget("attack_cooldown", 0.0))
	if cool <= 0.001:
		return
	var f := clampf(cool / maxf(_attack_max, 0.05), 0.0, 1.0)
	_hud.draw_arc(c, 22.0, PI * 0.75, PI * 0.75 + PI * 0.5 * f, 16, Color(1.0, 0.55, 0.45, 0.7 * a), 2.0, true)


## Floating damage numbers above hit Listeners.
func _draw_damage_numbers() -> void:
	if not Game.damage_enabled() or _dmg_numbers.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for n in _dmg_numbers:
		var pos: Vector3 = n["pos"]
		if cam.is_position_behind(pos):
			continue
		var age: float = n["age"]
		# Drift upward over time, with a small random sideways offset.
		var drift := Vector2(float(n["dx"]), -40.0 * age)
		var sp := cam.unproject_position(pos) + drift
		var al := 1.0 - smoothstep(0.6, 1.1, age)
		# Big for the first moment, then normal size.
		var fs := 28
		if age > 0.12:
			fs = 22
		var text := str(n["text"])
		var font := ThemeDB.fallback_font
		_hud.draw_string_outline(font, sp, text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, 4, Color(0.0, 0.0, 0.0, 0.7 * al))
		_hud.draw_string(font, sp, text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1.0, 0.85, 0.4, al))
