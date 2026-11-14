extends RefCounted
## Shared UI look and helpers: colors, chalk-style labels and buttons, key
## names for prompts, key rebinding save/load. Use with
## `const Style = preload("res://scripts/ui_style.gd")`.

const FONT: Font = preload("res://assets/fonts/Redaction50-Regular.ttf")
const CYAN := Color(0.239, 0.961, 1.0)
const DIM_CYAN := Color(0.36, 0.62, 0.66, 0.85)
const GOLD := Color(1.0, 0.784, 0.271)
const RED := Color(1.0, 0.231, 0.306)
const CHALK := Color(0.88, 0.9, 0.88)
const TEXT := Color(0.86, 0.88, 0.9)
const MUTED := Color(0.55, 0.6, 0.64)
const KEYS_PATH := "user://keys.cfg"
const REBINDABLE := [
	"move_forward", "move_back", "move_left", "move_right", "ping", "jump", "throw", "whisper",
	"interact", "attack", "sneak", "run", "map", "pause",
]
const ACTION_NAMES := {
	"move_forward": "Move forward", "move_back": "Move back", "move_left": "Move left",
	"move_right": "Move right", "ping": "Ping (call out)", "jump": "Jump", "throw": "Throw pebble",
	"whisper": "Whisper ping", "interact": "Interact / play log", "attack": "Strike",
	"sneak": "Sneak", "run": "Run", "map": "Map", "pause": "Pause",
}

static var _keys_loaded := false
static var _spaced: FontVariation
## True when the last input came from a controller (prompts show pad buttons).
static var using_pad := false

## Letter-spaced version of the default font, for titles and menu items.
static func spaced_font() -> FontVariation:
	if _spaced == null:
		_spaced = FontVariation.new()
		_spaced.base_font = FONT
		_spaced.spacing_glyph = 3
	return _spaced


## Makes a text label with the game font, a size, a color and a dark outline.
static func label(text: String, size: int, color: Color = TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	var outline: int = size / 8
	if outline < 2:
		outline = 2
	l.add_theme_constant_override("outline_size", outline)
	return l


## Makes a control fill its whole parent. Returns the same control.
static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


## A rounded, filled background box with padding.
static func box(color: Color, radius: int = 4, pad: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s


## Flat, chalk-looking menu button (no box). Focus = white, idle = dim cyan.
static func chalk_button(text: String, size: int = 30) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_override("font", spaced_font())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", DIM_CYAN)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", CYAN)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color(0.24, 0.96, 1.0, 0.18))
	b.add_theme_constant_override("outline_size", 6)
	# No background box in any state.
	var empty := StyleBoxEmpty.new()
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", empty)
	b.add_theme_stylebox_override("pressed", empty)
	b.add_theme_stylebox_override("hover_pressed", empty)
	b.add_theme_stylebox_override("disabled", empty)
	# Focus: a thin chalk underline instead of Godot's default box.
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	focus.border_color = Color(1.0, 1.0, 1.0, 0.35)
	focus.border_width_bottom = 2
	focus.draw_center = false
	b.add_theme_stylebox_override("focus", focus)
	return b


## Smaller boxed button for settings rows and dialogs.
static func small_button(text: String, size: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", FONT)

	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	var normal := box(Color(0.1, 0.14, 0.16, 0.9), 3, 10)
	var hover := box(Color(0.14, 0.26, 0.3, 0.95), 3, 10)
	var focus := box(Color(0.14, 0.3, 0.34, 0.95), 3, 10)
	focus.border_color = CYAN
	focus.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", focus)
	return b


## Chains focus neighbours top-to-bottom (wrapping) for keyboard / controller.
static func link_focus(controls: Array) -> void:
	# Only visible controls take part.
	var list: Array[Control] = []
	for item in controls:
		if not (item is Control):
			continue
		var control: Control = item
		if control.visible:
			list.append(control)
	var count: int = list.size()
	for i in range(count):
		# The one above the first is the last, and the one below the last is the first.
		var prev_index: int = i - 1
		if prev_index < 0:
			prev_index = count - 1
		var next_index: int = i + 1
		if next_index >= count:
			next_index = 0
		var current: Control = list[i]
		var prev: Control = list[prev_index]
		var next: Control = list[next_index]
		current.focus_neighbor_top = current.get_path_to(prev)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_previous = current.get_path_to(prev)
		current.focus_next = current.get_path_to(next)


## "3:07", or "3:07.4" with tenths.
static func format_time(seconds: float, tenths: bool = false) -> String:
	var t: float = maxf(seconds, 0.0)
	var whole_seconds: int = int(t)
	var minutes: int = whole_seconds / 60
	var secs: int = whole_seconds % 60
	if tenths:
		var tenth: int = int(t * 10.0) % 10
		return "%d:%02d.%d" % [minutes, secs, tenth]
	return "%d:%02d" % [minutes, secs]


# ---------------------------------------------------------------- Key names

## Short readable name of one input event ("Q", "LMB", "A", "LT", ...).
static func event_name(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var key: InputEventKey = ev
		var code: int = _key_code(key)
		var text: String = OS.get_keycode_string(code as Key)
		if text == "":
			return "?"
		return text
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev
		match mb.button_index:
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel down"
		return "Mouse %d" % mb.button_index
	if ev is InputEventJoypadButton:
		var jb: InputEventJoypadButton = ev
		match jb.button_index:
			JOY_BUTTON_A: return "A"
			JOY_BUTTON_B: return "B"
			JOY_BUTTON_X: return "X"
			JOY_BUTTON_Y: return "Y"
			JOY_BUTTON_BACK: return "View"
			JOY_BUTTON_START: return "Menu"
			JOY_BUTTON_LEFT_STICK: return "L3"
			JOY_BUTTON_RIGHT_STICK: return "R3"
			JOY_BUTTON_LEFT_SHOULDER: return "LB"
			JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		return "Pad %d" % jb.button_index
	if ev is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = ev
		match jm.axis:
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
		return "Stick"
	return "?"


## "[Q]" or "[LMB / Space]" for the current device.
static func key_name(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	var names := PackedStringArray()
	for ev in InputMap.action_get_events(action):
		# Only show buttons for the device the player is using.
		if _is_pad(ev) != using_pad:
			continue
		var event_text: String = event_name(ev)
		if not names.has(event_text):
			names.append(event_text)
		if names.size() >= 2:
			break
	if names.is_empty():
		return ""
	return "[" + " / ".join(names) + "]"


# ---------------------------------------------------------------- Rebinding

## True for controller buttons and sticks.
static func _is_pad(ev: InputEvent) -> bool:
	if ev is InputEventJoypadButton:
		return true
	if ev is InputEventJoypadMotion:
		return true
	return false


## The key's physical code, or its normal keycode if it has no physical one.
static func _key_code(key: InputEventKey) -> int:
	if key.physical_keycode != 0:
		return int(key.physical_keycode)
	return int(key.keycode)


## Turns a key / mouse event into a small dictionary for the save file.
static func _encode(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var key: InputEventKey = ev
		return {"type": "key", "code": _key_code(key)}
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev
		return {"type": "mouse", "button": int(mb.button_index)}
	return {}


## Turns a saved dictionary back into an input event (null if unknown).
static func _decode(d: Dictionary) -> InputEvent:
	match str(d.get("type", "")):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.get("code", 0)) as Key
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(d.get("button", 1)) as MouseButton
			return m
	return null


## Loads user://keys.cfg once per session (keyboard / mouse only; pad stays).
static func load_keys() -> void:
	if _keys_loaded:
		return
	_keys_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(KEYS_PATH) != OK:
		return
	for action in REBINDABLE:
		if not InputMap.has_action(action):
			continue
		if not cfg.has_section_key("keys", action):
			continue
		var list: Variant = cfg.get_value("keys", action, [])
		if not (list is Array):
			continue
		# Remove the old keyboard / mouse bindings (controller ones stay).
		for ev in InputMap.action_get_events(action):
			if not _is_pad(ev):
				InputMap.action_erase_event(action, ev)
		# Add the saved ones.
		for saved in list:
			if not (saved is Dictionary):
				continue
			var new_event: InputEvent = _decode(saved)
			if new_event != null:
				InputMap.action_add_event(action, new_event)


## Writes every keyboard / mouse binding to user://keys.cfg.
static func save_keys() -> void:
	var cfg := ConfigFile.new()
	for action in REBINDABLE:
		if not InputMap.has_action(action):
			continue
		var list: Array = []
		for ev in InputMap.action_get_events(action):
			if _is_pad(ev):
				continue
			var data: Dictionary = _encode(ev)
			if not data.is_empty():
				list.append(data)
		cfg.set_value("keys", action, list)
	cfg.save(KEYS_PATH)


## Replaces the action's first keyboard / mouse binding with `ev`.
static func rebind(action: String, ev: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	# Make a clean copy of the event (only the key or mouse button).
	var encoded: Dictionary = _encode(ev)
	var fresh: InputEvent = _decode(encoded)
	if fresh == null:
		return
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	var kept: Array[InputEvent] = []
	var replaced: bool = false
	for old_event in events:
		if not replaced and not _is_pad(old_event):
			replaced = true
			kept.append(fresh)
		else:
			kept.append(old_event)
	if not replaced:
		kept.push_front(fresh)
	InputMap.action_erase_events(action)
	for new_event in kept:
		InputMap.action_add_event(action, new_event)
	save_keys()


## Back to the key bindings from project.godot.
static func reset_keys() -> void:
	InputMap.load_from_project_settings()
	save_keys()


## First keyboard / mouse binding, for the settings list.
static func primary_name(action: String) -> String:
	if not InputMap.has_action(action):
		return "-"
	for ev in InputMap.action_get_events(action):
		if not _is_pad(ev):
			return event_name(ev)
	return "-"
