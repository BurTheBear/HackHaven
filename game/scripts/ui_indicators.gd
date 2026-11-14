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


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func setup(p: Node3D) -> void:
	player = p
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not Game.listener_alerted.is_connected(_on_alert):
		Game.listener_alerted.connect(_on_alert)
	if not Game.caption.is_connected(_on_caption):
		Game.caption.connect(_on_caption)
	if not Game.state_changed.is_connected(_on_state):
		Game.state_changed.connect(_on_state)


func _on_state(s: int) -> void:
	if s == Game.State.TITLE:
		_arcs.clear()
		_caps.clear()


func _on_alert(pos: Vector3) -> void:
	if not Settings.sound_indicator:
		return
	var d := 10.0
	if player != null:
		d = player.global_position.distance_to(pos)
	var near := clampf(1.0 - (d - NEAR) / (FAR - NEAR), 0.0, 1.0)
	_arcs.append({"pos": pos, "age": 0.0, "near": near})
	if _arcs.size() > 8:
		_arcs.pop_front()


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


func _process(delta: float) -> void:
	for a in _arcs:
		a["age"] = float(a["age"]) + delta
	for c in _caps:
		c["age"] = float(c["age"]) + delta
	_arcs.assign(_arcs.filter(func(a: Dictionary) -> bool: return float(a["age"]) < ARC_LIFE))
	_caps.assign(_caps.filter(func(c: Dictionary) -> bool: return float(c["age"]) < CAP_LIFE))
	queue_redraw()


func _arrow_for(a: float) -> String:
	var deg := absf(rad_to_deg(a))
	if deg < 30.0:
		return "\u2191"
	if deg > 150.0:
		return "\u2193"
	return "\u2190" if a > 0.0 else "\u2192"


func _draw() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.42
	for a in _arcs:
		var age: float = a["age"]
		var near: float = a["near"]
		var fade := 1.0 - age / ARC_LIFE
		var pulse := 1.0 + 0.5 * maxf(0.0, 1.0 - age / 0.3)
		var rel := _rel_angle(a["pos"])
		var mid := -PI * 0.5 - rel
		var width := (6.0 + 10.0 * near) * pulse
		var alpha := clampf((0.45 + 0.5 * near) * fade * pulse, 0.0, 1.0)
		var col := Color(Style.RED, alpha)
		draw_arc(centre, radius, mid - ARC_WIDTH * 0.5, mid + ARC_WIDTH * 0.5, 24, col, width, true)
		draw_arc(centre, radius, mid - ARC_WIDTH * 0.25, mid + ARC_WIDTH * 0.25, 12,
				Color(1.0, 0.6, 0.65, alpha * 0.6), width * 0.4, true)
	var font: Font = ThemeDB.fallback_font
	var fsize := int(round(18.0 * [0.85, 1.0, 1.3][clampi(Settings.subtitle_size, 0, 2)]))
	var y := size.y - 120.0
	for i in range(_caps.size() - 1, -1, -1):
		var c: Dictionary = _caps[i]
		var age: float = c["age"]
		var alpha := clampf((CAP_LIFE - age) / 0.5, 0.0, 1.0)
		var line := "%s %s" % [str(c["text"]), _arrow_for(_rel_angle(c["pos"]))]
		var tw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		var h := float(fsize) + 12.0
		var rect := Rect2(Vector2((size.x - tw) * 0.5 - 12.0, y - h), Vector2(tw + 24.0, h))
		draw_rect(rect, Color(0, 0, 0, 0.6 * alpha))
		draw_string(font, Vector2((size.x - tw) * 0.5, y - 9.0), line,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(Style.TEXT, alpha))
		y -= h + 6.0
