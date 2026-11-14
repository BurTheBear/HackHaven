extends Control
## Settings screen (from the main menu and the pause menu), split into tabs.
## Every change is applied live (Settings.apply) and written with
## Settings.save() on close and shortly after the last change.
## Keyboard / controller: arrows move, LB / RB or PageUp / PageDown switch tabs.

signal closed

const Style = preload("res://scripts/ui_style.gd")
const TABS := ["GAMEPLAY", "CONTROLS", "VIDEO", "AUDIO", "HUD", "ACCESSIBILITY"]

var _tab_buttons: Array[Button] = []
var _pages: Array[ScrollContainer] = []
var _page_first: Array = []
var _tab := 0
var _list: VBoxContainer  ## Page being built.
var _back: Button
var _reset: Button
var _dirty := 0.0
var _waiting_action := ""
var _waiting_button: Button
var _wait_start := 0
var _key_buttons := {}
var _controls := {}  ## settings key → control, for refreshing after a reset.
var _value_labels := {}  ## settings key → [Label, unit]


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
	panel.offset_left = -440.0
	panel.offset_right = 440.0
	panel.offset_top = 32.0
	panel.offset_bottom = -32.0
	var ps := Style.box(Color(0.02, 0.04, 0.05, 0.92), 6, 24)
	ps.border_color = Color(0.24, 0.96, 1.0, 0.25)
	ps.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	var title := Style.label("SETTINGS", 34, Style.CYAN)
	title.add_theme_font_override("font", Style.spaced_font())
	outer.add_child(title)

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 6)
	outer.add_child(tabs)
	for i in TABS.size():
		var tb := Style.small_button(TABS[i], 15)
		tb.toggle_mode = true
		tb.pressed.connect(_select_tab.bind(i, false))
		tb.focus_entered.connect(_on_focus)
		tabs.add_child(tb)
		_tab_buttons.append(tb)
	var hint := Style.label("LB / RB  ·  PgUp / PgDn  switch tabs", 13, Style.MUTED)
	outer.add_child(hint)

	for i in TABS.size():
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		scroll.visible = false
		outer.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 6)
		scroll.add_child(list)
		_pages.append(scroll)
		_page_first.append(null)
		_list = list
		match i:
			0: _build_gameplay()
			1: _build_controls()
			2: _build_video()
			3: _build_audio()
			4: _build_hud()
			5: _build_access()

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 40)
	outer.add_child(bottom)
	_reset = Style.chalk_button("RESET TO DEFAULTS", 20)
	_reset.pressed.connect(_reset_defaults)
	_reset.focus_entered.connect(_on_focus)
	bottom.add_child(_reset)
	_back = Style.chalk_button("BACK", 28)
	_back.pressed.connect(close)
	_back.focus_entered.connect(_on_focus)
	bottom.add_child(_back)
	_reset.focus_neighbor_right = _reset.get_path_to(_back)
	_back.focus_neighbor_left = _back.get_path_to(_reset)
	_select_tab(0, false)
	visible = false


# ---------------------------------------------------------------- Pages

func _build_gameplay() -> void:
	_section("COMBAT")
	_check("Damage & combat (off: Listeners catch instantly)", "damage_enabled")
	_option("Difficulty", "difficulty", Settings.DIFFICULTIES)
	_section("RUN")
	_check("Speedrun timer", "speedrun_timer")
	_check("Skip intro", "skip_intro")
	_section("MOVEMENT")
	_check("Toggle sneak (instead of hold)", "toggle_sneak")
	_check("Toggle run (instead of hold)", "toggle_run")


func _build_controls() -> void:
	_section("LOOK")
	_slider("Mouse sensitivity", "mouse_sensitivity", 0.2, 3.0, 0.05, "x")
	_check("Invert look (Y axis)", "invert_y")
	_slider("Controller look speed", "controller_look_speed", 0.3, 3.0, 0.05, "x")
	_slider("Mouse smoothing", "mouse_smoothing", 0.0, 1.0, 0.05, "%")
	_check("Controller vibration", "vibration")
	_section("KEYS  (select, then press a key or mouse button · Esc cancels)")
	for action in Style.REBINDABLE:
		if InputMap.has_action(action):
			_key_row(action)
	var reset := Style.small_button("Reset keys to default", 18)
	reset.pressed.connect(_reset_keys)
	reset.focus_entered.connect(_on_focus)
	_list.add_child(reset)


func _build_video() -> void:
	_section("DISPLAY")
	var full := _check("Fullscreen", "fullscreen")
	if OS.has_feature("web"):
		full.disabled = true
		full.tooltip_text = "Use your browser's fullscreen button."
	var vs := _check("V-sync", "vsync")
	if OS.has_feature("web"):
		vs.disabled = true
	var fps_names: Array = []
	for f in Settings.FPS_LIMITS:
		fps_names.append("Unlimited" if int(f) == 0 else str(f))
	_option("FPS limit", "fps_limit", fps_names)
	_check("Show FPS counter", "show_fps")
	_section("IMAGE")
	_slider("Render scale", "render_scale", 0.5, 1.0, 0.05, "%")
	_slider("Brightness", "brightness", 0.5, 1.6, 0.05, "%")
	_slider("Field of view", "fov", 60.0, 100.0, 1.0, "°")
	_check("Particles / dust motes", "particles")


func _build_audio() -> void:
	_section("VOLUME")
	_slider("Master volume", "volume_master", 0.0, 1.0, 0.05, "%")
	_slider("Effects volume", "volume_sfx", 0.0, 1.0, 0.05, "%")
	_slider("Ambience volume", "volume_ambience", 0.0, 1.0, 0.05, "%")
	_slider("Voice volume", "volume_voice", 0.0, 1.0, 0.05, "%")


func _build_hud() -> void:
	_section("LAYOUT")
	_option("Crosshair", "crosshair_style", Settings.CROSSHAIRS)
	_slider("HUD scale", "hud_scale", 0.75, 1.5, 0.05, "x")
	_slider("HUD opacity", "hud_opacity", 0.2, 1.0, 0.05, "%")
	_check("Presence bar", "presence_bar")
	_check("Damage numbers", "damage_numbers")
	_check("Damage vignette", "damage_vignette")
	_section("TEXT")
	_check("Subtitles", "subtitles")
	_option("Subtitle size", "subtitle_size", ["Small", "Medium", "Large"])
	_check("Captions for important sounds", "captions")
	_check("Sound direction indicator", "sound_indicator")


func _build_access() -> void:
	_section("COMFORT")
	_slider("Camera shake", "camera_shake", 0.0, 1.0, 0.05, "%")
	_check("No flashing", "no_flash")
	_check("Head bob", "head_bob")
	_check("Camera dip on landing", "landing_motion")
	_section("ASSISTS")
	_slider("Floor hint glow", "hint_glow", 0.0, 1.0, 0.05, "%")
	_check("Skip the jump scare", "skip_jumpscare")
	_check("Assist mode (slower, forgiving Listeners)", "assist_mode")
	_check("Hard mode", "hard_mode")


# ---------------------------------------------------------------- Open / close

func open() -> void:
	visible = true
	_refresh_keys()
	_refresh_values()
	_select_tab(_tab, true)


func close() -> void:
	if _waiting_action != "":
		_stop_waiting()
	Sfx.play("ui_back", -6.0)
	Settings.save()
	_dirty = 0.0
	visible = false
	closed.emit()


func _select_tab(index: int, focus_tab: bool) -> void:
	_tab = wrapi(index, 0, TABS.size())
	for i in _pages.size():
		_pages[i].visible = i == _tab
		_tab_buttons[i].set_pressed_no_signal(i == _tab)
		_tab_buttons[i].add_theme_color_override("font_color", Style.CYAN if i == _tab else Style.TEXT)
	_pages[_tab].scroll_vertical = 0
	# Tab row ↓ goes into the page; the page's first row ↑ back to its tab.
	var first: Control = _page_first[_tab]
	for tb in _tab_buttons:
		if first != null:
			tb.focus_neighbor_bottom = tb.get_path_to(first)
		tb.focus_neighbor_top = tb.get_path_to(_back)
	if first != null:
		first.focus_neighbor_top = first.get_path_to(_tab_buttons[_tab])
	_back.focus_neighbor_top = _back.get_path_to(_last_control(_tab))
	_reset.focus_neighbor_top = _reset.get_path_to(_last_control(_tab))
	if visible and focus_tab:
		_tab_buttons[_tab].grab_focus()


func _last_control(page: int) -> Control:
	var last: Control = _tab_buttons[page]
	for c in _controls_in(_pages[page]):
		last = c
	return last


func _controls_in(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Control and (child as Control).focus_mode == Control.FOCUS_ALL and not (child is ScrollBar):
			out.append(child)
		out.append_array(_controls_in(child))
	return out


func _process(delta: float) -> void:
	if _dirty > 0.0:
		_dirty -= delta
		if _dirty <= 0.0:
			Settings.save()


func _changed(key: String, value: Variant) -> void:
	if key == "difficulty":
		Settings.set_difficulty(int(value))
	else:
		Settings.set(key, value)
	Settings.apply()
	_dirty = 0.8
	if key in ["difficulty", "assist_mode", "hard_mode"]:
		_refresh_values()


func _reset_defaults() -> void:
	Sfx.play("ui_click", -8.0)
	Settings.reset_to_defaults()
	Settings.save()
	_refresh_values()


func _refresh_values() -> void:
	for key in _controls:
		var c: Control = _controls[key]
		var v: Variant = Settings.get(key)
		if c is HSlider:
			(c as HSlider).set_value_no_signal(float(v))
			if _value_labels.has(key):
				var pair: Array = _value_labels[key]
				(pair[0] as Label).text = _format(float(v), str(pair[1]))
		elif c is CheckButton:
			(c as CheckButton).set_pressed_no_signal(bool(v))
		elif c is OptionButton:
			var o := c as OptionButton
			o.select(clampi(int(v), 0, o.item_count - 1))


# ---------------------------------------------------------------- Rows

func _section(text: String) -> void:
	var l := Style.label(text, 18, Style.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(0, 38)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_list.add_child(l)


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 34)
	var l := Style.label(text, 19, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	_list.add_child(row)
	return row


func _remember(c: Control) -> void:
	var page := _pages.size() - 1
	if page >= 0 and _page_first[page] == null:
		_page_first[page] = c
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
	_controls[key] = s
	_value_labels[key] = [value, unit]
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
	_controls[key] = c
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
	_controls[key] = o
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
	if not visible or _waiting_action != "":
		return
	var step := 0
	var jb := event as InputEventJoypadButton
	if jb != null and jb.pressed:
		if jb.button_index == JOY_BUTTON_LEFT_SHOULDER:
			step = -1
		elif jb.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			step = 1
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_PAGEUP:
			step = -1
		elif key.keycode == KEY_PAGEDOWN:
			step = 1
	if step != 0:
		get_viewport().set_input_as_handled()
		Sfx.play("ui_click", -10.0)
		_select_tab(_tab + step, true)
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
