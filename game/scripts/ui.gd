extends CanvasLayer
## Title, HUD (pebbles + ping cooldown ring), subtitles, messages, dread
## vignette, red catch flash, pause and the end screen.

const CONTROLS := "WASD move   ·   hold C sneak   ·   hold Shift run\nClick ping   ·   Q whisper   ·   Right click throw   ·   F chalk mark"

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float dread = 0.0;
void fragment() {
	float v = smoothstep(0.3, 0.85, length(UV - 0.5) * 1.3);
	float pulse = 0.8 + 0.2 * sin(TIME * mix(2.0, 9.0, dread));
	COLOR = vec4(0.35, 0.0, 0.02, v * dread * pulse);
}
"""

const RING_SHADER := """
shader_type canvas_item;
uniform float age = 0.0;
void fragment() {
	vec2 p = UV - 0.5;
	p.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float ring = 1.0 - smoothstep(0.0, 0.015, abs(length(p) - age * 0.55));
	COLOR = vec4(0.24, 0.96, 1.0, ring * (1.0 - clamp(age / 1.6, 0.0, 1.0)) * 0.8);
}
"""

@onready var root: Control = $Root
@onready var title: Label = $Root/Title
@onready var crosshair: Label = $Root/Crosshair
@onready var pebbles: Label = $Root/Pebbles
@onready var subtitle_label: Label = $Root/Subtitle
@onready var message: Label = $Root/Message
@onready var paused: Label = $Root/Paused

var _subtitle_time := 0.0
var _message_time := 0.0
var _title_age := 0.0
var _flash_alpha := 0.0
var _started_once := false
var _vignette: ColorRect
var _flash_rect: ColorRect
var _title_ring: ColorRect
var _cooldown: Control
var _controls: Label


func _ready() -> void:
	# Keeps running while the tree is paused, so it can show the pause text
	# and take the click that resumes.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_vignette = _overlay(VIGNETTE_SHADER)
	_title_ring = _overlay(RING_SHADER)
	_flash_rect = _overlay("")
	_flash_rect.color = Color(0.6, 0.0, 0.03, 0.0)
	_cooldown = Control.new()
	_cooldown.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cooldown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cooldown.draw.connect(_draw_cooldown)
	root.add_child(_cooldown)
	_controls = Label.new()
	_controls.text = CONTROLS
	_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_controls.offset_bottom = -60.0
	_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_controls.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_controls.add_theme_font_size_override("font_size", 18)
	_controls.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	root.add_child(_controls)

	Game.state_changed.connect(_on_state_changed)
	Game.pebbles_changed.connect(_on_pebbles_changed)
	Game.subtitle.connect(_on_subtitle)
	Game.player_caught.connect(_on_caught)
	Game.checkpoint_reached.connect(_on_checkpoint)
	Game.game_won.connect(_on_won)
	_on_state_changed(Game.state)
	_on_pebbles_changed(Game.pebbles)


## Full-screen overlay under the labels. Empty shader code = plain ColorRect.
func _overlay(code: String) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if code != "":
		var shader := Shader.new()
		shader.code = code
		var mat := ShaderMaterial.new()
		mat.shader = shader
		rect.material = mat
	root.add_child(rect)
	root.move_child(rect, 0)
	return rect


func set_dread(v: float) -> void:
	(_vignette.material as ShaderMaterial).set_shader_parameter("dread", v)


func flash_red() -> void:
	_flash_alpha = 0.75


func _process(delta: float) -> void:
	# Pause whenever the mouse is unlocked while playing. In a browser, Esc
	# unlocks the mouse without the game ever seeing the key press.
	var should_pause := Game.state == Game.State.PLAYING and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	if get_tree().paused != should_pause:
		get_tree().paused = should_pause
	paused.visible = should_pause

	_flash_alpha = maxf(_flash_alpha - delta * 0.6, 0.0)
	_flash_rect.color.a = _flash_alpha
	_cooldown.queue_redraw()

	# Title: a ping ripples out every few seconds and the word ECHO glows, then fades.
	var on_title := Game.state == Game.State.TITLE
	_title_ring.visible = on_title
	_controls.visible = on_title or should_pause
	if on_title:
		_title_age += delta
		if _title_age > 3.0:
			_title_age = 0.0
			Sfx.play("ping", -12.0, &"Cave")
		(_title_ring.material as ShaderMaterial).set_shader_parameter("age", _title_age)
		title.modulate.a = 0.1 + 0.9 * clampf(1.0 - (_title_age - 0.15) / 2.2, 0.0, 1.0) * clampf(_title_age * 8.0, 0.0, 1.0)

	_subtitle_time -= delta
	if _subtitle_time <= 0.0:
		subtitle_label.text = ""
	if Game.state != Game.State.WON:
		_message_time -= delta
		if _message_time <= 0.0:
			message.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused and event is InputEventMouseButton and event.is_pressed():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


## Ping cooldown ring around the crosshair.
func _draw_cooldown() -> void:
	if Game.state != Game.State.PLAYING:
		return
	var player = get_tree().get_first_node_in_group("player")
	if player == null or player.ping_cooldown <= 0.0:
		return
	var left: float = player.ping_cooldown / Game.ping_cooldown
	var c := _cooldown.size / 2.0
	_cooldown.draw_arc(c, 16.0, -PI / 2.0, -PI / 2.0 + TAU * left, 32, Color(0.24, 0.96, 1.0, 0.6), 2.0, true)


func _on_state_changed(state: int) -> void:
	title.visible = state == Game.State.TITLE
	title.modulate.a = 1.0
	crosshair.visible = state == Game.State.PLAYING
	pebbles.visible = state == Game.State.PLAYING or state == Game.State.CAUGHT
	if state == Game.State.TITLE:
		_started_once = false
	elif state == Game.State.PLAYING and not _started_once:
		_started_once = true
		_on_subtitle("The rope snapped. The lantern's gone.\nCall out. Listen. Find your way back.  [Left click]")


func _on_pebbles_changed(count: int) -> void:
	pebbles.text = "Pebbles  " + "● ".repeat(count)


func _on_subtitle(text: String) -> void:
	subtitle_label.text = text
	_subtitle_time = 3.0 + text.length() * 0.06


func _on_caught() -> void:
	_flash("The Hollow heard you.", 1.2)


func _on_checkpoint() -> void:
	_flash("Checkpoint", 1.0)


func _on_won() -> void:
	var t := int(Game.run_time)
	var best := int(Game.best_time)
	var record := "New best time!" if Game.new_best else "Best %d:%02d" % [best / 60, best % 60]
	message.text = "You found your way back.\n\nTime %d:%02d    Caught %d\n%s\n\nClick to play again" % [t / 60, t % 60, Game.times_caught, record]


func _flash(text: String, seconds: float) -> void:
	message.text = text
	_message_time = seconds
