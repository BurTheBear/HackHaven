extends Control
## Main menu, drawn over the dark start room. A silent echo leaves the camera
## every few seconds so the cave flickers in behind the chalk-white menu, and
## each item brightens as the ring passes it. Now and then a faint red
## Listener drifts past behind the text.

signal begin_pressed
signal continue_pressed
signal settings_pressed
signal credits_pressed
signal quit_pressed

const Style = preload("res://scripts/ui_style.gd")
const PING_EVERY := 4.5
const RING_TIME := 1.5  ## Seconds for the 2D ring to reach the screen corners.
const TEAM := "Shreyansh Nikam · Elias Chen · Atharv"

var active := false

var _fx: Control
var _title: Label
var _tagline: Label
var _items: Array[Button] = []
var _continue: Button
var _hard: Button
var _chal: Button
## Challenge modes in the order the CHALLENGE item cycles through them.
const CHALLENGES := ["", "no_ping", "one_pebble", "darkness"]
var _quit: Button
var _best: Label
var _ring_age := 99.0
var _ping_timer := 1.2
## Small rings next to a focused item: each is {"pos": Vector2, "age": float}.
var _hover_rings: Array = []
var _ghost_timer := 12.0
var _ghost_t := -1.0
var _ghost_y := 0.6
var _ghost_dir := 1.0
var _drone: AudioStreamPlayer
var _breath: AudioStreamPlayer
var _last_focus: Control


## Builds the title, the menu items, the footer texts and the ambience players.
func _ready() -> void:
	Style.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx = Style.full_rect(Control.new())
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.draw.connect(_draw_fx)
	add_child(_fx)

	_title = Style.label("ECHO", 112, Style.CYAN)
	_title.add_theme_font_override("font", Style.spaced_font())
	_title.add_theme_color_override("font_outline_color", Color(0.24, 0.96, 1.0, 0.25))
	_title.add_theme_constant_override("outline_size", 18)
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_title.anchor_left = 0.0
	_title.anchor_right = 1.0
	_title.offset_left = 0.0
	_title.offset_right = 0.0
	_title.anchor_top = 0.12
	_title.anchor_bottom = 0.12
	_title.offset_top = 0.0
	_title.offset_bottom = 140.0
	add_child(_title)

	_tagline = Style.label("Echolocation, but Monsters like noise. :3\n The noise bounces back", 18, Style.MUTED)
	_tagline.anchor_left = 0.0
	_tagline.anchor_right = 1.0
	_tagline.anchor_top = 0.12
	_tagline.anchor_bottom = 0.12
	_tagline.offset_top = 140.0
	_tagline.offset_bottom = 170.0
	add_child(_tagline)


	var list := VBoxContainer.new()
	list.alignment = BoxContainer.ALIGNMENT_CENTER
	list.add_theme_constant_override("separation", 6)
	list.anchor_left = 0.5
	list.anchor_right = 0.5
	list.anchor_top = 0.42
	list.anchor_bottom = 0.42
	list.offset_left = -220.0
	list.offset_right = 220.0
	list.offset_top = 0.0
	list.offset_bottom = 410.0
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(list)

	_add_item(list, "begin", _emit_begin)
	_continue = _add_item(list, "continue", _emit_continue)
	_add_item(list, "settings", _emit_settings)
	_add_item(list, "credits", _emit_credits)
	_hard = _add_item(list, "", _toggle_hard)
	_hard.add_theme_font_size_override("font_size", 20)
	_chal = _add_item(list, "", _cycle_challenge)
	_chal.add_theme_font_size_override("font_size", 20)
	_quit = _add_item(list, "quit", _emit_quit)
	# There is no "quit" in a browser tab.
	if OS.has_feature("web"):
		_quit.visible = false
	else:
		_quit.visible = true

	_best = Style.label("", 18, Style.GOLD)
	_best.anchor_top = 1.0
	_best.anchor_bottom = 1.0
	_best.offset_left = 20.0
	_best.offset_right = 600.0
	_best.offset_top = -34.0
	_best.offset_bottom = -10.0
	add_child(_best)

	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	if version == "":
		version = "1.0"
	var corner := Style.label("ECHO v%s  -  %s  -  Hack Club Haven" % [version, TEAM], 14, Color(0.5, 0.55, 0.6, 0.8), HORIZONTAL_ALIGNMENT_RIGHT)
	corner.anchor_left = 0.0
	corner.anchor_right = 1.0
	corner.anchor_top = 1.0
	corner.anchor_bottom = 1.0
	corner.offset_left = 16.0
	corner.offset_right = -20.0
	corner.offset_top = -34.0
	corner.offset_bottom = -10.0
	add_child(corner)


	_drone = AudioStreamPlayer.new()
	_drone.bus = &"Ambience"
	_drone.volume_db = -16.0
	add_child(_drone)
	_breath = AudioStreamPlayer.new()
	_breath.bus = &"Ambience"
	_breath.volume_db = -24.0
	_breath.pitch_scale = 0.85
	add_child(_breath)
	refresh()


## What each menu item does when chosen.
func _emit_begin() -> void:
	begin_pressed.emit()


func _emit_continue() -> void:
	continue_pressed.emit()


func _emit_settings() -> void:
	settings_pressed.emit()


func _emit_credits() -> void:
	credits_pressed.emit()


func _emit_quit() -> void:
	quit_pressed.emit()


## Adds one menu item. `action` is the function to run when it is chosen.
func _add_item(list: VBoxContainer, text: String, action: Callable) -> Button:
	var b := Style.chalk_button(text, 30)
	b.custom_minimum_size = Vector2(0, 46)
	b.pressed.connect(_on_item_pressed.bind(action))
	b.mouse_entered.connect(b.grab_focus)
	b.focus_entered.connect(_on_item_focus.bind(b))
	list.add_child(b)
	_items.append(b)
	return b


## Re-reads save / best time / hard mode, and fixes the focus chain.
func refresh() -> void:
	_continue.visible = Game.has_save()
	if Settings.hard_mode:
		_hard.text = "hard mode: ON"
	else:
		_hard.text = "hard mode: OFF"
	# Challenges unlock after the first finished run.
	var unlocked: bool = (Game.best_time >= 0.0)
	_chal.visible = unlocked
	if not unlocked:
		Game.challenge = ""
	_chal.text = "challenge: %s" % Game.challenge_name().to_upper()
	if Game.best_time > 0.0:
		_best.text = "Best time  %s" % Style.format_time(Game.best_time)
	else:
		_best.text = ""
	Style.link_focus(_items)


## Called when the menu is shown (after the click gate or coming back).
func activate() -> void:
	active = true
	visible = true
	refresh()
	_ping_timer = 0.6
	if _drone.stream == null:
		_drone.stream = Sfx.stream("drone")
		_breath.stream = Sfx.stream("breath")
	if not _drone.playing:
		_drone.play()
		_breath.play()
	focus_first()


## Menu gone for good (a run is starting).
func deactivate() -> void:
	active = false
	visible = false
	# Fade both sounds out together, then stop them.
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_drone, "volume_db", -60.0, 1.5)
	tw.tween_property(_breath, "volume_db", -60.0, 1.5)
	tw.chain().tween_callback(_stop_ambience)


## Stops the menu ambience sounds.
func _stop_ambience() -> void:
	_drone.stop()
	_breath.stop()


## Click sound, then the item's action.
func _on_item_pressed(action: Callable) -> void:
	Sfx.play("ui_click", -6.0)
	action.call()


## Focuses the last focused item, or the first visible one.
func focus_first() -> void:
	if _last_focus != null:
		if _last_focus.visible and is_instance_valid(_last_focus):
			_last_focus.grab_focus()
			return
	for b in _items:
		if b.visible:
			b.grab_focus()
			return


## HARD MODE item: switches hard mode on / off.
func _toggle_hard() -> void:
	Settings.hard_mode = not Settings.hard_mode
	Settings.save()
	refresh()


## CHALLENGE item: moves to the next challenge mode (wrapping around).
func _cycle_challenge() -> void:
	var index: int = CHALLENGES.find(Game.challenge)
	var next_index: int = index + 1
	if next_index >= CHALLENGES.size():
		next_index = 0
	Game.challenge = CHALLENGES[next_index]
	refresh()


## An item got focus: hover sound and a small ring left of its text.
func _on_item_focus(b: Button) -> void:
	_last_focus = b
	if not visible:
		return
	Sfx.play("ui_hover", -10.0)
	var item_center: Vector2 = _local_center(b)
	var font: Font = b.get_theme_font("font")
	var font_size: int = b.get_theme_font_size("font_size")
	var text_size: Vector2 = font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_width: float = text_size.x
	var ring_pos: Vector2 = item_center - Vector2(text_width * 0.5 + 26.0, 0.0)
	_hover_rings.append({"pos": ring_pos, "age": 0.0})


## Center of a control, in this menu's own coordinates.
func _local_center(control: Control) -> Vector2:
	var control_center: Vector2 = control.get_global_rect().get_center()
	return control_center - get_global_rect().position


## How brightly the echo ring lights a point: 1 right on the ring, fading to 0
## further away. `width` is how wide the bright band is (in pixels).
func _ring_glow(point: Vector2, width: float) -> float:
	var center: Vector2 = size * 0.5
	var distance_from_ring: float = point.distance_to(center) - _ring_radius()
	var x: float = distance_from_ring / width
	return exp(-(x * x))


## How strong the ring still is (1 just after a ping, 0 after 3 seconds).
func _ring_fade() -> float:
	return clampf(1.0 - _ring_age / 3.0, 0.0, 1.0)


## Every frame: pings, the hover rings, item brightness and the background Listener.
func _process(delta: float) -> void:
	if not active:
		return
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = PING_EVERY
		_ping()
	_ring_age += delta
	_update_hover_rings(delta)
	_update_brightness()
	_update_ghost(delta)
	_fx.queue_redraw()


## Ages the small hover rings and removes the old ones (after 0.6 s).
func _update_hover_rings(delta: float) -> void:
	var still_alive: Array = []
	for ring in _hover_rings:
		var age: float = float(ring["age"]) + delta
		ring["age"] = age
		if age < 0.6:
			still_alive.append(ring)
	_hover_rings = still_alive


## Items and the title brighten as the ring sweeps over them.
func _update_brightness() -> void:
	var fade: float = _ring_fade()
	for b in _items:
		var band: float = _ring_glow(_local_center(b), 70.0) * fade
		var base: float = 0.85
		if b.has_focus():
			base = 1.0
		var bright: float = base + band * 0.9
		b.modulate = Color(bright, bright, bright, 1.0)
	var title_band: float = _ring_glow(_local_center(_title), 120.0) * fade
	var title_light: float = clampf(title_band * 1.4 + fade * 0.35, 0.0, 1.0)
	_title.modulate = Color(1.0, 1.0, 1.0, 0.45 + 0.55 * title_light)


## The Listener behind the text: waits a while, then walks across in 22 s.
func _update_ghost(delta: float) -> void:
	if _ghost_t < 0.0:
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_t = 0.0
			_ghost_y = randf_range(0.62, 0.8)
			if randf() < 0.5:
				_ghost_dir = 1.0
			else:
				_ghost_dir = -1.0
	else:
		_ghost_t += delta / 22.0
		if _ghost_t >= 1.0:
			_ghost_t = -1.0
			_ghost_timer = randf_range(16.0, 34.0)


## A silent echo from the camera, so the cave flickers in behind the menu.
func _ping() -> void:
	_ring_age = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		Echo.emit_ping(cam.global_position, 22.0, false)
	Sfx.play("ping", -20.0, &"Cave", 0.92)


## Current radius of the big 2D ring (it grows over RING_TIME seconds).
func _ring_radius() -> float:
	return _ring_age / RING_TIME * size.length() * 0.5


## Draws the big ring, the hover rings and the Listener on the effects layer.
func _draw_fx() -> void:
	var center: Vector2 = size * 0.5
	var ring_life: float = RING_TIME * 1.6
	if _ring_age < ring_life:
		var radius: float = _ring_radius()
		var alpha: float = clampf(1.0 - _ring_age / ring_life, 0.0, 1.0)
		var glow_color := Color(0.24, 0.96, 1.0, 0.07 * alpha)
		var line_color := Color(0.8, 1.0, 1.0, 0.35 * alpha)
		_fx.draw_arc(center, radius, 0.0, TAU, 96, glow_color, 18.0, true)
		_fx.draw_arc(center, radius, 0.0, TAU, 96, line_color, 1.5, true)
	for ring in _hover_rings:
		var age: float = ring["age"]
		var t: float = age / 0.6
		var ring_pos: Vector2 = ring["pos"]
		var ring_radius: float = 4.0 + t * 18.0
		var ring_color := Color(1.0, 1.0, 1.0, 0.7 * (1.0 - t))
		_fx.draw_arc(ring_pos, ring_radius, 0.0, TAU, 32, ring_color, 1.5, true)
	if _ghost_t >= 0.0:
		_draw_listener(center)


## A thin, hunched, eyeless thing with huge ear-fins. Barely there, and a
## little clearer when the echo ring passes over it.
func _draw_listener(_center: Vector2) -> void:
	var t: float = _ghost_t
	# Screen x from 0 to 1 (a bit past each edge), left-to-right or right-to-left.
	var x: float = 0.0
	if _ghost_dir > 0.0:
		x = lerpf(-0.1, 1.1, t)
	else:
		x = lerpf(1.1, -0.1, t)
	var h: float = size.y * 0.38
	var foot := Vector2(size.x * x, size.y * _ghost_y + h * 0.5)
	var bob: float = sin(t * 60.0) * h * 0.01
	var band: float = _ring_glow(foot, 120.0) * _ring_fade()
	# Fades in and out over the walk, and shows more when the ring passes.
	var alpha: float = (0.035 + 0.16 * band) * sin(t * PI)
	var col := Color(1.0, 0.23, 0.31, alpha)
	var lean := 0.18 * _ghost_dir
	var hip := foot + Vector2(0.0, -h * 0.42 + bob)
	var neck := hip + Vector2(h * lean, -h * 0.4)
	var head := neck + Vector2(h * lean * 0.6, -h * 0.07)
	var step := sin(t * 40.0) * h * 0.06
	# Legs.
	draw_line_on(hip, foot + Vector2(-h * 0.06 + step, 0.0), col, h * 0.035)
	draw_line_on(hip, foot + Vector2(h * 0.06 - step, 0.0), col, h * 0.035)
	# Hunched torso.
	var torso := PackedVector2Array([
		hip + Vector2(-h * 0.07, 0.0), hip + Vector2(h * 0.07, 0.0),
		neck + Vector2(h * 0.08, h * 0.02), neck + Vector2(-h * 0.05, -h * 0.03),
	])
	_fx.draw_colored_polygon(torso, col)
	# Arms that nearly reach the floor.
	var sway := sin(t * 33.0) * h * 0.04
	draw_line_on(neck, neck + Vector2(h * 0.05 + sway, h * 0.55), col, h * 0.025)
	draw_line_on(neck, neck + Vector2(-h * 0.08 - sway, h * 0.58), col, h * 0.025)
	# Head and ear-fins.
	_fx.draw_circle(head, h * 0.05, col)
	var left_fin := PackedVector2Array([
		head + Vector2(-h * 0.02, -h * 0.03),
		head + Vector2(-h * 0.16, -h * 0.14),
		head + Vector2(-h * 0.03, h * 0.02),
	])
	_fx.draw_colored_polygon(left_fin, col)
	var right_fin := PackedVector2Array([
		head + Vector2(h * 0.02, -h * 0.03),
		head + Vector2(h * 0.16, -h * 0.14),
		head + Vector2(h * 0.03, h * 0.02),
	])
	_fx.draw_colored_polygon(right_fin, col)


## Draws a smooth line on the effects layer.
func draw_line_on(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	_fx.draw_line(a, b, col, width, true)
