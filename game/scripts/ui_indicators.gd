extends Control
## Accessibility overlays: red sound-direction arcs when a Listener heard you,
## and directional sound captions above the subtitles.

const Style = preload("res://scripts/ui_style.gd")
const ARC_LIFE := 2.0
const ARC_WIDTH := 0.7  ## Radians (~40 degrees).
const CAP_LIFE := 2.5
const CAP_MAX := 3
const NEAR := 6.0
const FAR := 30.0

var player: Node3D
var _arcs: Array[Dictionary] = []  ## pos: Vector3, age: float, near: float
var _caps: Array[Dictionary] = []  ## text: String, pos: Vector3, age: float


## Covers the whole screen and never blocks the mouse.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Called by ui.gd: remembers the player and listens to game signals.
func setup(p: Node3D) -> void:
	player = p
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not Game.listener_alerted.is_connected(_on_alert):
		Game.listener_alerted.connect(_on_alert)
	if not Game.caption.is_connected(_on_caption):
		Game.caption.connect(_on_caption)
	if not Game.state_changed.is_connected(_on_state):
		Game.state_changed.connect(_on_state)


## Back on the title screen: forget everything on screen.
func _on_state(s: int) -> void:
	if s == Game.State.TITLE:
		_arcs.clear()
		_caps.clear()


## A Listener heard something at `pos`: add a red arc pointing at it.
func _on_alert(pos: Vector3) -> void:
	if not Settings.sound_indicator:
		return
	var distance := 10.0
	if player != null:
		distance = player.global_position.distance_to(pos)
	# 1.0 when closer than NEAR, 0.0 when further than FAR.
	var near := 1.0 - (distance - NEAR) / (FAR - NEAR)
	near = clampf(near, 0.0, 1.0)
	_arcs.append({"pos": pos, "age": 0.0, "near": near})
	if _arcs.size() > 8:
		_arcs.pop_front()


## A sound caption: refresh it if it is already shown, otherwise add it.
func _on_caption(text: String, pos: Vector3) -> void:
	if not Settings.captions:
		return
	for c in _caps:
		if c["text"] == text:
			c["pos"] = pos
			c["age"] = 0.0
			return
	_caps.append({"text": text, "pos": pos, "age": 0.0})
	if _caps.size() > CAP_MAX:
		_caps.pop_front()


## Angle of a world point relative to where the camera looks: 0 ahead,
## positive to the left, +-PI behind. Returns 0 with no camera.
func _rel_angle(pos: Vector3) -> float:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	var to := pos - cam.global_position
	to.y = 0.0
	if fwd.length() < 0.001 or to.length() < 0.01:
		return 0.0
	return fwd.normalized().signed_angle_to(to.normalized(), Vector3.UP)


## Ages every arc and caption, drops the old ones, then redraws.
func _process(delta: float) -> void:
	for a in _arcs:
		a["age"] = float(a["age"]) + delta
	for c in _caps:
		c["age"] = float(c["age"]) + delta
	_remove_old(_arcs, ARC_LIFE)
	_remove_old(_caps, CAP_LIFE)
	queue_redraw()


## Removes every entry whose "age" has reached `max_age` (keeps the order).
func _remove_old(list: Array[Dictionary], max_age: float) -> void:
	var i := list.size() - 1
	while i >= 0:
		var age: float = list[i]["age"]
		if age >= max_age:
			list.remove_at(i)
		i -= 1


## An arrow character pointing toward a relative angle.
func _arrow_for(a: float) -> String:
	var deg := absf(rad_to_deg(a))
	if deg < 30.0:
		return "↑"  # Ahead.
	if deg > 150.0:
		return "↓"  # Behind.
	if a > 0.0:
		return "←"  # Left.
	return "→"  # Right.


## Caption text scale for the subtitle size setting (small / normal / large).
func _caption_scale() -> float:
	var setting := clampi(Settings.subtitle_size, 0, 2)
	if setting == 0:
		return 0.85
	if setting == 1:
		return 1.0
	return 1.3


func _draw() -> void:
	_draw_arcs()
	_draw_captions()


## Red arcs on a ring around the screen centre, pointing at each sound.
func _draw_arcs() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.42
	for a in _arcs:
		var age: float = a["age"]
		var near: float = a["near"]
		var fade := 1.0 - age / ARC_LIFE
		# Brief swell right after the alert.
		var pulse := 1.0 + 0.5 * maxf(0.0, 1.0 - age / 0.3)
		var rel := _rel_angle(a["pos"])
		# Up on screen is straight ahead.
		var mid := -PI * 0.5 - rel
		var width := (6.0 + 10.0 * near) * pulse
		var alpha := (0.45 + 0.5 * near) * fade * pulse
		alpha = clampf(alpha, 0.0, 1.0)
		var col := Color(Style.RED, alpha)
		var half := ARC_WIDTH * 0.5
		draw_arc(centre, radius, mid - half, mid + half, 24, col, width, true)
		var quarter := ARC_WIDTH * 0.25
		var inner_col := Color(1.0, 0.6, 0.65, alpha * 0.6)
		draw_arc(centre, radius, mid - quarter, mid + quarter, 12, inner_col, width * 0.4, true)


## Caption boxes stacked upward from near the bottom, newest at the bottom.
func _draw_captions() -> void:
	var font: Font = ThemeDB.fallback_font
	var fsize := int(round(18.0 * _caption_scale()))
	var y := size.y - 120.0
	for i in range(_caps.size() - 1, -1, -1):
		var c: Dictionary = _caps[i]
		var age: float = c["age"]
		# Fully visible until the last half second.
		var alpha := clampf((CAP_LIFE - age) / 0.5, 0.0, 1.0)
		var arrow := _arrow_for(_rel_angle(c["pos"]))
		var line := str(c["text"]) + " " + arrow
		var text_width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		var h := float(fsize) + 12.0
		var left := (size.x - text_width) * 0.5
		var rect := Rect2(Vector2(left - 12.0, y - h), Vector2(text_width + 24.0, h))
		draw_rect(rect, Color(0, 0, 0, 0.6 * alpha))
		draw_string(font, Vector2(left, y - 9.0), line,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(Style.TEXT, alpha))
		y -= h + 6.0
