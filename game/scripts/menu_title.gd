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
const TEAM := "Shreyansh Nikam · Elias Chen · Atharv · Ritesh"

var active := false

var _fx: Control
var _title: Label
var _tagline: Label
var _items: Array[Button] = []
var _continue: Button
var _hard: Button
var _quit: Button
var _best: Label
var _ring_age := 99.0
var _ping_timer := 1.2
var _hover_rings: Array = []
var _ghost_timer := 12.0
var _ghost_t := -1.0
var _ghost_y := 0.6
var _ghost_dir := 1.0
var _drone: AudioStreamPlayer
var _breath: AudioStreamPlayer
var _last_focus: Control


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

	_tagline = Style.label("Every sound shows you the cave. Every sound gives you away.", 18, Style.MUTED)
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
	list.offset_bottom = 330.0
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(list)

	var begin := _add_item(list, "BEGIN", func(): begin_pressed.emit())
	_continue = _add_item(list, "CONTINUE", func(): continue_pressed.emit())
	_add_item(list, "SETTINGS", func(): settings_pressed.emit())
	_add_item(list, "CREDITS", func(): credits_pressed.emit())
	_hard = _add_item(list, "", _toggle_hard)
	_hard.add_theme_font_size_override("font_size", 20)
	_quit = _add_item(list, "QUIT", func(): quit_pressed.emit())
	_quit.visible = not OS.has_feature("web")
	begin.text = "BEGIN"

	_best = Style.label("", 18, Style.GOLD)
	_best.anchor_left = 0.0
	_best.anchor_right = 1.0
	_best.anchor_top = 1.0
	_best.anchor_bottom = 1.0
	_best.offset_top = -92.0
	_best.offset_bottom = -64.0
	add_child(_best)

	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	if version == "":
		version = "1.0"
	var corner := Style.label("ECHO v%s  ·  %s  ·  Hack Club Haven" % [version, TEAM], 14, Color(0.5, 0.55, 0.6, 0.8), HORIZONTAL_ALIGNMENT_RIGHT)
	corner.anchor_left = 0.0
	corner.anchor_right = 1.0
	corner.anchor_top = 1.0
	corner.anchor_bottom = 1.0
	corner.offset_left = 16.0
	corner.offset_right = -20.0
	corner.offset_top = -34.0
	corner.offset_bottom = -10.0
	add_child(corner)

	var nav := Style.label("Mouse, arrows or a controller  ·  Enter / A to choose", 14, Color(0.45, 0.5, 0.55, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
	nav.anchor_top = 1.0
	nav.anchor_bottom = 1.0
	nav.offset_left = 20.0
	nav.offset_right = 600.0
	nav.offset_top = -34.0
	nav.offset_bottom = -10.0
	add_child(nav)

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
	_hard.text = "HARD MODE: %s" % ("ON" if Settings.hard_mode else "OFF")
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
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_drone, "volume_db", -60.0, 1.5)
	tw.tween_property(_breath, "volume_db", -60.0, 1.5)
	tw.chain().tween_callback(_stop_ambience)


func _stop_ambience() -> void:
	_drone.stop()
	_breath.stop()


func _on_item_pressed(action: Callable) -> void:
	Sfx.play("ui_click", -6.0)
	action.call()


func focus_first() -> void:
	if _last_focus != null and _last_focus.visible and is_instance_valid(_last_focus):
		_last_focus.grab_focus()
		return
	for b in _items:
		if b.visible:
			b.grab_focus()
			return


func _toggle_hard() -> void:
	Settings.hard_mode = not Settings.hard_mode
	Settings.save()
	refresh()


func _on_item_focus(b: Button) -> void:
	_last_focus = b
	if not visible:
		return
	Sfx.play("ui_hover", -10.0)
	var c := b.get_global_rect().get_center() - get_global_rect().position
	var font := b.get_theme_font("font")
	var w := font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
	_hover_rings.append({"pos": c - Vector2(w * 0.5 + 26.0, 0.0), "age": 0.0})


func _process(delta: float) -> void:
	if not active:
		return
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = PING_EVERY
		_ping()
	_ring_age += delta
	for r in _hover_rings:
		r["age"] = float(r["age"]) + delta
	_hover_rings = _hover_rings.filter(func(r): return float(r["age"]) < 0.6)

	# Items and the title brighten as the ring sweeps over them.
	var center := size * 0.5
	var radius := _ring_radius()
	var fade := clampf(1.0 - _ring_age / 3.0, 0.0, 1.0)
	for b in _items:
		var c := b.get_global_rect().get_center() - get_global_rect().position
		var band := exp(-pow((c.distance_to(center) - radius) / 70.0, 2.0)) * fade
		var base := 1.0 if b.has_focus() else 0.85
		b.modulate = Color(base + band * 0.9, base + band * 0.9, base + band * 0.9, 1.0)
	var tc := _title.get_global_rect().get_center() - get_global_rect().position
	var tb := exp(-pow((tc.distance_to(center) - radius) / 120.0, 2.0)) * fade
	_title.modulate = Color(1.0, 1.0, 1.0, 0.45 + 0.55 * clampf(tb * 1.4 + fade * 0.35, 0.0, 1.0))

	# The Listener behind the text.
	if _ghost_t < 0.0:
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_t = 0.0
			_ghost_y = randf_range(0.62, 0.8)
			_ghost_dir = 1.0 if randf() < 0.5 else -1.0
	else:
		_ghost_t += delta / 22.0
		if _ghost_t >= 1.0:
			_ghost_t = -1.0
			_ghost_timer = randf_range(16.0, 34.0)
	_fx.queue_redraw()


func _ping() -> void:
	_ring_age = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		Echo.emit_ping(cam.global_position, 22.0, false)
	Sfx.play("ping", -20.0, &"Cave", 0.92)


func _ring_radius() -> float:
	return _ring_age / RING_TIME * size.length() * 0.5


func _draw_fx() -> void:
	var center := size * 0.5
	if _ring_age < RING_TIME * 1.6:
		var r := _ring_radius()
		var a := clampf(1.0 - _ring_age / (RING_TIME * 1.6), 0.0, 1.0)
		_fx.draw_arc(center, r, 0.0, TAU, 96, Color(0.24, 0.96, 1.0, 0.07 * a), 18.0, true)
		_fx.draw_arc(center, r, 0.0, TAU, 96, Color(0.8, 1.0, 1.0, 0.35 * a), 1.5, true)
	for h in _hover_rings:
		var age: float = h["age"]
		var t := age / 0.6
		_fx.draw_arc(h["pos"], 4.0 + t * 18.0, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.7 * (1.0 - t)), 1.5, true)
	if _ghost_t >= 0.0:
		_draw_listener(center)


## A thin, hunched, eyeless thing with huge ear-fins. Barely there, and a
## little clearer when the echo ring passes over it.
func _draw_listener(center: Vector2) -> void:
	var t := _ghost_t
	var x := lerpf(-0.1, 1.1, t) if _ghost_dir > 0.0 else lerpf(1.1, -0.1, t)
	var h := size.y * 0.38
	var foot := Vector2(size.x * x, size.y * _ghost_y + h * 0.5)
	var bob := sin(t * 60.0) * h * 0.01
	var radius := _ring_radius()
	var band := exp(-pow((foot.distance_to(center) - radius) / 120.0, 2.0)) * clampf(1.0 - _ring_age / 3.0, 0.0, 1.0)
	var alpha := (0.035 + 0.16 * band) * sin(t * PI)
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
	_fx.draw_colored_polygon(PackedVector2Array([
		head + Vector2(-h * 0.02, -h * 0.03), head + Vector2(-h * 0.16, -h * 0.14), head + Vector2(-h * 0.03, h * 0.02)]), col)
	_fx.draw_colored_polygon(PackedVector2Array([
		head + Vector2(h * 0.02, -h * 0.03), head + Vector2(h * 0.16, -h * 0.14), head + Vector2(h * 0.03, h * 0.02)]), col)


func draw_line_on(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	_fx.draw_line(a, b, col, width, true)
