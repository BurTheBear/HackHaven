extends Control
## Credits: a slow roll. Full screen with a Back button from the main menu, or
## `embedded` (no background, no button) in a column of the end screen.

signal closed

const Style = preload("res://scripts/ui_style.gd")
## [text, font size, color]. Asset credits are placeholders: fill them in
## alongside the README's Credits section.
const LINES := [
	["ECHO", 60, "cyan"],
	["A game about echolocation i guess", 20, "muted"],
	["", 30, "text"],
	["TEAM", 20, "gold"],
	["Shreyansh Nikam", 30, "text"],
	["Elias Chen", 30, "text"],
	["Atharv", 30, "text"],
	
	["Built with Godot 4", 20, "cyan"],
	["Made for Hack Club Haven - Theme: Bounce Back", 20, "muted"],
	["", 20, "text"],
	["Thank you for listening. (haha get it)", 10, "gold"],
]

var embedded := false
var speed := 32.0

var _clip: Control
var _content: VBoxContainer
var _back: Button
var _offset := 0.0


func _ready() -> void:
	Style.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE if embedded else Control.MOUSE_FILTER_STOP
	if not embedded:
		var dim := Style.full_rect(ColorRect.new()) as ColorRect
		dim.color = Color(0.0, 0.0, 0.0, 0.82)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.anchor_left = 0.0 if embedded else 0.5
	_clip.anchor_right = 1.0 if embedded else 0.5
	_clip.anchor_bottom = 1.0
	_clip.offset_left = 0.0 if embedded else -380.0
	_clip.offset_right = 0.0 if embedded else 380.0
	_clip.offset_top = 0.0 if embedded else 40.0
	_clip.offset_bottom = 0.0 if embedded else -100.0
	add_child(_clip)
	_content = VBoxContainer.new()
	_content.anchor_right = 1.0
	_content.add_theme_constant_override("separation", 6)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_content)
	for line in LINES:
		var col := Style.TEXT
		match str(line[2]):
			"cyan": col = Style.CYAN
			"gold": col = Style.GOLD
			"muted": col = Style.MUTED
		var l := Style.label(str(line[0]), int(line[1]), col)
		if int(line[1]) >= 20:
			l.add_theme_font_override("font", Style.spaced_font())
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(l)
	if not embedded:
		_back = Style.chalk_button("BACK", 28)
		_back.anchor_left = 0.5
		_back.anchor_right = 0.5
		_back.anchor_top = 1.0
		_back.anchor_bottom = 1.0
		_back.offset_left = -120.0
		_back.offset_right = 120.0
		_back.offset_top = -86.0
		_back.offset_bottom = -40.0
		_back.pressed.connect(close)
		add_child(_back)
		visible = false


func open() -> void:
	visible = true
	_offset = 0.0
	if _back != null:
		_back.grab_focus()


func close() -> void:
	Sfx.play("ui_back", -6.0)
	visible = false
	closed.emit()


func _process(delta: float) -> void:
	if not visible or _clip == null:
		return
	_offset += speed * delta
	_content.position.y = _clip.size.y - _offset
	if _content.position.y + _content.size.y < 0.0:
		_offset = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if embedded or not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
