extends Control
## Settings screen (from the main menu and the pause menu). Every change is
## applied live (Settings.apply) and written with Settings.save() on close and
## shortly after the last change. Keyboard / controller friendly.

signal closed

const Style = preload("res://scripts/ui_style.gd")

var _list: VBoxContainer
var _scroll: ScrollContainer
var _first: Control
var _back: Button
var _dirty := 0.0
var _waiting_action := ""
var _waiting_button: Button
var _wait_start := 0
var _key_buttons := {}


func _ready() -> void:
	Style.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := Style.full_rect(ColorRect.new()) as ColorRect
	dim.color = Color(0.0, 0.0, 0.0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -400.0
	panel.offset_right = 400.0
	panel.offset_top = 40.0
	panel.offset_bottom = -40.0
	var ps := Style.box(Color(0.02, 0.04, 0.05, 0.92), 6, 24)
	ps.border_color = Color(0.24, 0.96, 1.0, 0.25)
	ps.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)
	var title := Style.label("SETTINGS", 34, Style.CYAN)
	title.add_theme_font_override("font", Style.spaced_font())
	outer.add_child(title)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	outer.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)

	_section("CONTROLS")
	_slider("Mouse sensitivity", "mouse_sensitivity", 0.2, 3.0, 0.05, "x")
	_check("Invert look (Y axis)", "invert_y")
	_slider("Controller look speed", "controller_look_speed", 0.3, 3.0, 0.05, "x")
	_check("Toggle sneak (instead of hold)", "toggle_sneak")
	_check("Toggle run (instead of hold)", "toggle_run")
	_section("DISPLAY")
	_slider("Field of view", "fov", 60.0, 100.0, 1.0, "°")
	var full := _check("Fullscreen", "fullscreen")
	if OS.has_feature("web"):
		full.disabled = true
		full.tooltip_text = "Use your browser's fullscreen button."
	_check("Head bob", "head_bob")
	_section("AUDIO")
	_slider("Master volume", "volume_master", 0.0, 1.0, 0.05, "%")
	_slider("Effects volume", "volume_sfx", 0.0, 1.0, 0.05, "%")
	_slider("Ambience volume", "volume_ambience", 0.0, 1.0, 0.05, "%")
	_slider("Voice volume", "volume_voice", 0.0, 1.0, 0.05, "%")
	_section("ACCESSIBILITY")
	_check("Subtitles", "subtitles")
	_option("Subtitle size", "subtitle_size", ["Small", "Medium", "Large"])
	_check("Captions for important sounds", "captions")
	_check("Sound direction indicator", "sound_indicator")
	_check("Reduce camera shake", "reduce_shake")
	_check("No flashing", "no_flash")
	_check("Skip the jump scare", "skip_jumpscare")
	_slider("Floor hint glow", "hint_glow", 0.0, 1.0, 0.05, "%")
	_check("Assist mode (slower, forgiving Listeners)", "assist_mode")
	_section("GAME")
	_check("Hard mode", "hard_mode")
	_check("Speedrun timer", "speedrun_timer")
	_check("Skip intro", "skip_intro")
	_section("KEYS  (click, then press a key or mouse button · Esc cancels)")
	for action in Style.REBINDABLE:
		_key_row(action)
	var reset := Style.small_button("Reset keys to default", 18)
	reset.pressed.connect(_reset_keys)
	_list.add_child(reset)

	_back = Style.chalk_button("BACK", 28)
	_back.pressed.connect(close)
	outer.add_child(_back)
	visible = false


func open() -> void:
	visible = true
	_refresh_keys()
	_scroll.scroll_vertical = 0
	if _first != null:
		_first.grab_focus()


func close() -> void:
	if _waiting_action != "":
		_stop_waiting()
	Sfx.play("ui_back", -6.0)
	Settings.save()
	_dirty = 0.0
	visible = false
	closed.emit()


func _process(delta: float) -> void:
	if _dirty > 0.0:
		_dirty -= delta
		if _dirty <= 0.0:
			Settings.save()


func _changed(key: String, value: Variant) -> void:
	Settings.set(key, value)
	Settings.apply()
	_dirty = 0.8


# ---------------------------------------------------------------- Rows

func _section(text: String) -> void:
	var l := Style.label(text, 18, Style.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(0, 40)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_list.add_child(l)


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 34)
	var l := Style.label(text, 19, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	_list.add_child(row)
	return row


func _remember(c: Control) -> void:
	if _first == null:
		_first = c
	c.focus_entered.connect(_on_focus)


func _on_focus() -> void:
	if visible:
		Sfx.play("ui_hover", -14.0)


func _slider(text: String, key: String, lo: float, hi: float, step: float, unit: String) -> HSlider:
	var row := _row(text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(240, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	s.value = float(Settings.get(key))
	var value := Style.label("", 17, Style.CYAN, HORIZONTAL_ALIGNMENT_RIGHT)
	value.custom_minimum_size = Vector2(64, 0)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.text = _format(s.value, unit)
	s.value_changed.connect(_on_slider.bind(key, unit, value))
	row.add_child(s)
	row.add_child(value)
	_remember(s)
	return s


func _on_slider(v: float, key: String, unit: String, value_label: Label) -> void:
	value_label.text = _format(v, unit)
	_changed(key, v)


func _format(v: float, unit: String) -> String:
	match unit:
		"%": return "%d%%" % roundi(v * 100.0)
		"°": return "%d°" % roundi(v)
	return "%.2f%s" % [v, unit]


func _check(text: String, key: String) -> CheckButton:
	var row := _row(text)
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.get(key))
	c.focus_mode = Control.FOCUS_ALL
	c.toggled.connect(_on_check.bind(key))
	row.add_child(c)
	_remember(c)
	return c


func _on_check(on: bool, key: String) -> void:
	Sfx.play("ui_click", -10.0)
	_changed(key, on)


func _option(text: String, key: String, options: Array) -> OptionButton:
	var row := _row(text)
	var o := OptionButton.new()
	for item in options:
		o.add_item(str(item))
	o.custom_minimum_size = Vector2(160, 0)
	o.focus_mode = Control.FOCUS_ALL
	o.selected = clampi(int(Settings.get(key)), 0, options.size() - 1)
	o.item_selected.connect(_on_option.bind(key))
	row.add_child(o)
	_remember(o)
	return o


func _on_option(index: int, key: String) -> void:
	Sfx.play("ui_click", -10.0)
	_changed(key, index)


# ---------------------------------------------------------------- Key rebinding

func _key_row(action: String) -> void:
	var row := _row(str(Style.ACTION_NAMES.get(action, action)))
	var b := Style.small_button(Style.primary_name(action), 18)
	b.custom_minimum_size = Vector2(180, 0)
	b.pressed.connect(_start_waiting.bind(action, b))
	row.add_child(b)
	_key_buttons[action] = b
	_remember(b)


func _refresh_keys() -> void:
	for action in _key_buttons:
		var b: Button = _key_buttons[action]
		b.text = Style.primary_name(action)


func _start_waiting(action: String, b: Button) -> void:
	if _waiting_action != "":
		_stop_waiting()
	_waiting_action = action
	_waiting_button = b
	_wait_start = Time.get_ticks_msec()
	b.text = "Press a key..."


func _stop_waiting() -> void:
	_waiting_action = ""
	_waiting_button = null
	_refresh_keys()


func _reset_keys() -> void:
	Sfx.play("ui_click", -8.0)
	Style.reset_keys()
	_refresh_keys()


func _input(event: InputEvent) -> void:
	if not visible or _waiting_action == "":
		return
	if Time.get_ticks_msec() - _wait_start < 180:
		return
	var key := event as InputEventKey
	var mb := event as InputEventMouseButton
	if key != null and key.pressed and not key.echo:
		get_viewport().set_input_as_handled()
		var code: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if code != KEY_ESCAPE:
			Style.rebind(_waiting_action, key)
			Sfx.play("ui_click", -6.0)
		var b := _waiting_button
		_stop_waiting()
		if b != null:
			b.grab_focus()
	elif mb != null and mb.pressed:
		get_viewport().set_input_as_handled()
		Style.rebind(_waiting_action, mb)
		Sfx.play("ui_click", -6.0)
		var b2 := _waiting_button
		_stop_waiting()
		if b2 != null:
			b2.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
