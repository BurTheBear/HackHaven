extends Control
## Pause menu: Resume / Restart from checkpoint / Settings / Logs / Quit to
## title, over a darkened game, with the zone, logs found and a controls
## reminder. Clicking the empty background also resumes (browsers only lock
## the mouse again on a click). The Logs page re-reads collected voice logs.

signal resume_pressed
signal restart_pressed
signal settings_pressed
signal quit_pressed

const Style = preload("res://scripts/ui_style.gd")

var total_logs := 8

var _main: Control
var _info: Label
var _controls: Label
var _buttons: Array[Button] = []
var _logs_page: Control
var _logs_list: VBoxContainer
var _logs_back: Button
var _logs_button: Button


## Builds the pause screen: title, info line, buttons, controls help and the logs page.
func _ready() -> void:
	Style.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := Style.full_rect(ColorRect.new()) as ColorRect
	dim.color = Color(0.0, 0.01, 0.02, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_main = Style.full_rect(Control.new())
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_main)
	var title := Style.label("PAUSED", 44, Style.CYAN)
	title.add_theme_font_override("font", Style.spaced_font())
	title.anchor_right = 1.0
	title.anchor_top = 0.16
	title.anchor_bottom = 0.16
	title.offset_bottom = 60.0
	_main.add_child(title)
	_info = Style.label("", 18, Style.GOLD)
	_info.anchor_right = 1.0
	_info.anchor_top = 0.16
	_info.anchor_bottom = 0.16
	_info.offset_top = 64.0
	_info.offset_bottom = 92.0
	_main.add_child(_info)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.anchor_left = 0.5
	list.anchor_right = 0.5
	list.anchor_top = 0.36
	list.anchor_bottom = 0.36
	list.offset_left = -260.0
	list.offset_right = 260.0
	list.offset_bottom = 280.0
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main.add_child(list)
	_add(list, "RESUME", _emit_resume)
	_add(list, "RESTART FROM CHECKPOINT", _emit_restart)
	_add(list, "SETTINGS", _emit_settings)
	_logs_button = _add(list, "LOGS", show_logs)
	_add(list, "QUIT TO TITLE", _emit_quit)
	Style.link_focus(_buttons)

	_controls = Style.label("", 16, Style.MUTED)
	_controls.anchor_right = 1.0
	_controls.anchor_top = 1.0
	_controls.anchor_bottom = 1.0
	_controls.offset_top = -120.0
	_controls.offset_bottom = -20.0
	_controls.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_main.add_child(_controls)

	_build_logs_page()
	visible = false


## What each button does when chosen.
func _emit_resume() -> void:
	resume_pressed.emit()


func _emit_restart() -> void:
	restart_pressed.emit()


func _emit_settings() -> void:
	settings_pressed.emit()


func _emit_quit() -> void:
	quit_pressed.emit()


## Adds one menu button. `action` is the function to run when it is chosen.
func _add(list: VBoxContainer, text: String, action: Callable) -> Button:
	var b := Style.chalk_button(text, 26)
	b.custom_minimum_size = Vector2(0, 42)
	b.pressed.connect(_on_pressed.bind(action))
	b.mouse_entered.connect(b.grab_focus)
	b.focus_entered.connect(_on_hover)
	list.add_child(b)
	_buttons.append(b)
	return b


## Click sound, then the button's action.
func _on_pressed(action: Callable) -> void:
	Sfx.play("ui_click", -6.0)
	action.call()


## Hover / focus sound.
func _on_hover() -> void:
	if visible:
		Sfx.play("ui_hover", -12.0)


## Shows the pause menu with the current zone and log count.
func open() -> void:
	visible = true
	_main.visible = true
	_logs_page.visible = false
	var zone: String = Game.current_zone
	if zone == "":
		zone = "THE HOLLOW"
	var logs_count: int = Game.logs_found.size()
	_info.text = "%s     ·     Logs %d / %d" % [zone.to_upper(), logs_count, total_logs]
	# Nothing to read yet: the LOGS button is greyed out.
	var nothing_found: bool = Game.logs_found.is_empty() and Game.journal_found.is_empty()
	_logs_button.disabled = nothing_found
	_controls.text = _controls_text()
	_buttons[0].grab_focus()


## Hides the pause menu.
func close() -> void:
	visible = false


## The two lines of control reminders at the bottom.
func _controls_text() -> String:
	var move_keys: String = "[WASD]"
	if Style.using_pad:
		move_keys = "[Left stick]"
	var parts := [
		"Move %s" % move_keys,
		"Ping %s" % Style.key_name("ping"),
		"Jump %s" % Style.key_name("jump"),
		"Whisper %s" % Style.key_name("whisper"),
		"Throw %s" % Style.key_name("throw"),
	]
	var parts2 := [
		"Sneak %s" % Style.key_name("sneak"),
		"Run %s" % Style.key_name("run"),
		"Chalk %s" % Style.key_name("chalk"),
		"Play log %s" % Style.key_name("interact"),
		"Map %s" % Style.key_name("map"),
	]
	var line1: String = "   ·   ".join(PackedStringArray(parts))
	var line2: String = "   ·   ".join(PackedStringArray(parts2))
	return line1 + "\n" + line2 + "\n\nClick anywhere to resume"


# ---------------------------------------------------------------- Logs

## Builds the (hidden) page that lists found logs and journal pages.
func _build_logs_page() -> void:
	_logs_page = Style.full_rect(Control.new())
	_logs_page.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_logs_page)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 1.0
	panel.offset_left = -420.0
	panel.offset_right = 420.0
	panel.offset_top = 50.0
	panel.offset_bottom = -50.0
	panel.add_theme_stylebox_override("panel", Style.box(Color(0.02, 0.03, 0.04, 0.94), 6, 26))
	_logs_page.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var t := Style.label("MARA'S LOGS", 30, Style.GOLD)
	t.add_theme_font_override("font", Style.spaced_font())
	v.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	v.add_child(scroll)
	_logs_list = VBoxContainer.new()
	_logs_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_logs_list.add_theme_constant_override("separation", 18)
	scroll.add_child(_logs_list)
	_logs_back = Style.chalk_button("BACK", 26)
	_logs_back.pressed.connect(hide_logs)
	v.add_child(_logs_back)
	_logs_page.visible = false


## Fills the logs page with every found log and journal page, then shows it.
func show_logs() -> void:
	for child in _logs_list.get_children():
		child.queue_free()
	var found: Array = Game.logs_found.duplicate()
	found.sort()
	for idx in found:
		var head := Style.label("LOG %d" % int(idx), 16, Style.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
		_logs_list.add_child(head)
		var text: String = _log_text(int(idx))
		var body := Style.label("MARA —  " + text, 20, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(700, 0)
		_logs_list.add_child(body)
	var pages: Array = Game.journal_found.duplicate()
	pages.sort()
	for idx in pages:
		var page_number: int = int(idx) + 1
		var page_head := Style.label("JOURNAL PAGE %d" % page_number, 16, Style.CYAN, HORIZONTAL_ALIGNMENT_LEFT)
		_logs_list.add_child(page_head)
		var page_text: String = str(Game.journal_texts.get(int(idx), "(The ink has run.)"))
		var page_body := Style.label(page_text, 20, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		page_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		page_body.custom_minimum_size = Vector2(700, 0)
		_logs_list.add_child(page_body)
	if found.is_empty() and pages.is_empty():
		_logs_list.add_child(Style.label("No recordings found yet.", 20, Style.MUTED))
	_main.visible = false
	_logs_page.visible = true
	_logs_back.grab_focus()


## Text of one voice log. Saved games may store the index as a number or a string.
func _log_text(index: int) -> String:
	if Game.log_texts.has(index):
		return str(Game.log_texts[index])
	var key_as_text: String = str(index)
	if Game.log_texts.has(key_as_text):
		return str(Game.log_texts[key_as_text])
	return "(The recording is too damaged to replay.)"


## Back from the logs page to the pause buttons.
func hide_logs() -> void:
	Sfx.play("ui_back", -6.0)
	_logs_page.visible = false
	_main.visible = true
	_logs_button.grab_focus()


## Esc / B: back out of the logs page. Returns true if it handled it.
func back() -> bool:
	if _logs_page.visible:
		hide_logs()
		return true
	return false
