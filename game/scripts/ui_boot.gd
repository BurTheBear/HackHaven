extends Control
## Boot cards, shown once per session before the main menu:
## (phones: "needs a keyboard and mouse") → photosensitivity / loud sound
## warning (only until it has been seen once) → "Best played with headphones,
## in the dark." → the click gate ("Listening..." until the sounds are built).
## The gate click is the user gesture browsers need before audio can start.
## Then the black fades away to reveal the menu.

signal finished

const Style = preload("res://scripts/ui_style.gd")

var _black: ColorRect
var _card: VBoxContainer
var _head: Label
var _body: Label
var _foot: Label
var _stage := ""
var _stage_time := 0.0
var _icon_alpha := 0.0
var _ready_to_click := false


## Builds the black background and the centred text card.
func _ready() -> void:
	Style.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_black = Style.full_rect(ColorRect.new()) as ColorRect
	_black.color = Color.BLACK
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_card = VBoxContainer.new()
	_card.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 0.5
	_card.anchor_bottom = 0.5
	_card.offset_left = -420.0
	_card.offset_right = 420.0
	_card.offset_top = -180.0
	_card.offset_bottom = 180.0
	_card.add_theme_constant_override("separation", 18)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	_head = Style.label("", 30, Style.CYAN)
	_head.add_theme_font_override("font", Style.spaced_font())
	_card.add_child(_head)
	_body = Style.label("", 21, Style.TEXT)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(_body)
	_foot = Style.label("", 16, Style.MUTED)
	_card.add_child(_foot)
	_card.modulate.a = 0.0
	visible = false


## Shows the first boot card (phone notice, warning, or headphones).
func start() -> void:
	visible = true
	_black.color.a = 1.0
	if _is_phone():
		_show("mobile")
	elif not Settings.seen_warning:
		_show("warning")
	else:
		_show("headphones")


## True when running in a phone or tablet browser.
## Touch laptops still have a keyboard, so a touch screen alone doesn't count.
func _is_phone() -> bool:
	if OS.has_feature("web_android"):
		return true
	if OS.has_feature("web_ios"):
		return true
	return false


## Fills the card with the text for one stage and fades it in.
func _show(stage: String) -> void:
	_stage = stage
	_stage_time = 0.0
	_ready_to_click = false
	_head.add_theme_color_override("font_color", Style.CYAN)
	_head.add_theme_font_size_override("font_size", 30)
	match stage:
		"mobile":
			_head.text = "NEEDS A KEYBOARD AND MOUSE"
			_head.add_theme_color_override("font_color", Style.RED)
			_body.text = "ECHO is a first-person game played with a keyboard and mouse (or a controller). It won't play well on a phone or tablet. Please come back on a computer."
			_foot.text = "Tap to try anyway"
		"warning":
			_head.text = "WARNING"
			_head.add_theme_color_override("font_color", Style.RED)
			_body.text = "This game contains flashing lights, sudden loud sounds and a jump scare.\nFlashes, camera shake and the jump scare can be turned off in Settings."
			_foot.text = ""
		"headphones":
			_head.text = ""
			_body.text = "Best played with headphones, in the dark :p"
			_foot.text = ""
		"gate":
			_head.text = "ECHO"
			_head.add_theme_font_size_override("font_size", 72)
			_body.text = ""
			_foot.text = ""
	var tw := create_tween()
	tw.tween_property(_card, "modulate:a", 1.0, 0.7)
	queue_redraw()


## Fades the current card out, then shows the next one.
func _next() -> void:
	var from := _stage
	_stage = ""
	var tw := create_tween()
	tw.tween_property(_card, "modulate:a", 0.0, 0.45)
	tw.tween_callback(_after.bind(from))


## Picks which card comes after the one called `from`.
func _after(from: String) -> void:
	match from:
		"mobile":
			if Settings.seen_warning:
				_show("headphones")
			else:
				_show("warning")
		"warning":
			Settings.seen_warning = true
			Settings.save()
			_show("headphones")
		"headphones":
			_show("gate")
		"gate":
			pass


## Per-frame card timing: when clicks are allowed, auto-advance, pulsing text.
func _process(delta: float) -> void:
	if not visible:
		return
	_stage_time += delta
	match _stage:
		"warning":
			if _stage_time > 1.5 and not _ready_to_click:
				_ready_to_click = true
				_foot.text = "Click or press any key to continue"
		"mobile":
			_ready_to_click = _stage_time > 0.8
		"headphones":
			_icon_alpha = minf(_stage_time / 0.8, 1.0)
			_ready_to_click = _stage_time > 0.6
			if _stage_time > 3.2:
				_next()
		"gate":
			if Sfx.is_loaded:
				_ready_to_click = true
				_body.text = "Click to begin"
				var click_alpha := 0.55 + 0.45 * sin(_stage_time * 2.4)
				_body.add_theme_color_override("font_color", Color(1, 1, 1, click_alpha))
			else:
				_body.text = "Listening..."
				var wait_alpha := 0.4 + 0.3 * sin(_stage_time * 4.0)
				_body.add_theme_color_override("font_color", Color(0.6, 0.66, 0.7, wait_alpha))
	if _stage != "headphones":
		_icon_alpha = maxf(_icon_alpha - delta * 2.0, 0.0)
	queue_redraw()


## Any key, click, button or tap moves to the next card (once allowed).
func _input(event: InputEvent) -> void:
	if not visible or _stage == "":
		return
	var pressed := false
	if event is InputEventMouseButton and event.is_pressed():
		pressed = true
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		pressed = true
	elif event is InputEventJoypadButton and event.is_pressed():
		pressed = true
	elif event is InputEventScreenTouch and event.is_pressed():
		pressed = true
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if not _ready_to_click:
		return
	if _stage == "gate":
		_stage = ""
		# This click is the user gesture that lets the browser start audio.
		Sfx.play("ui_click", -4.0)
		var tw := create_tween()
		tw.tween_property(_card, "modulate:a", 0.0, 0.5)
		tw.tween_callback(_emit_finished)
		tw.tween_property(_black, "color:a", 0.0, 1.8)
		tw.tween_callback(hide)
	else:
		Sfx.play("ui_click", -8.0)
		_next()


## Lets clicks through to the menu and tells ui.gd the boot cards are done.
func _emit_finished() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	finished.emit()


## Draws the headphones icon on the headphones card.
func _draw() -> void:
	if _icon_alpha <= 0.0:
		return
	# Headphones, drawn in thin cyan lines above the card text.
	var c := size * 0.5 + Vector2(0, -90)
	var col := Color(0.24, 0.96, 1.0, 0.8 * _icon_alpha)
	draw_arc(c, 34.0, PI, TAU, 32, col, 3.0, true)
	draw_rect(Rect2(c + Vector2(-42, -4), Vector2(14, 30)), col, false, 3.0)
	draw_rect(Rect2(c + Vector2(28, -4), Vector2(14, 30)), col, false, 3.0)
