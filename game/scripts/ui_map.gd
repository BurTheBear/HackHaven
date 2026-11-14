extends Control
## Explored-only map (action "map"): the path you walked, where you pinged,
## chalk marks and you. No level geometry. Pauses the tree while open.

const Style = preload("res://scripts/ui_style.gd")
const SAMPLE_EVERY := 0.5
const MIN_MOVE := 0.75
const PING_NEAR := 2.0
const MAX_POINTS := 4000
const MAX_PINGS := 300
const MAX_SCALE := 30.0
const MIN_SCALE := 2.0
const MARGIN_M := 4.0

var player: Node3D
var is_open := false

var _points: Array[Vector2] = []
var _pings: Array[Dictionary] = []  ## pos: Vector2, r: float, kind: int (0 loud, 1 whisper, 2 pebble)
var _timer := 0.0
var _was_paused := false
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	modulate.a = 0.0
	if not Game.state_changed.is_connected(_on_state):
		Game.state_changed.connect(_on_state)


func setup(p: Node3D) -> void:
	player = p
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not Echo.ping_emitted.is_connected(_on_ping):
		Echo.ping_emitted.connect(_on_ping)
	if not Game.state_changed.is_connected(_on_state):
		Game.state_changed.connect(_on_state)


func _on_state(s: int) -> void:
	if s == Game.State.TITLE:
		_points.clear()
		_pings.clear()
		_timer = 0.0
		if is_open:
			_close(true)


func _on_ping(origin: Vector3, radius: float, loud: bool) -> void:
	if player == null or Game.state != Game.State.PLAYING:
		return
	var flat := Vector2(origin.x, origin.z)
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var kind := 2
	if flat.distance_to(pp) <= PING_NEAR:
		kind = 0 if loud else 1
	_pings.append({"pos": flat, "r": radius, "kind": kind})
	if _pings.size() > MAX_PINGS:
		_pings.pop_front()


func _process(delta: float) -> void:
	if player == null:
		return
	if Input.is_action_just_pressed("map"):
		if is_open:
			_close(false)
		elif Game.state == Game.State.PLAYING and not get_tree().paused:
			_open()
	if is_open and Game.state != Game.State.PLAYING:
		_close(true)
	if Game.state == Game.State.PLAYING and not get_tree().paused:
		_timer += delta
		if _timer >= SAMPLE_EVERY:
			_timer = 0.0
			var pp := Vector2(player.global_position.x, player.global_position.z)
			if _points.is_empty() or _points[_points.size() - 1].distance_to(pp) >= MIN_MOVE:
				_points.append(pp)
				if _points.size() > MAX_POINTS:
					_points.pop_front()
	if visible:
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action("map") or event.is_action("pause"):
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton \
			or event is InputEventMouseMotion or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()


func _open() -> void:
	is_open = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	_fade(1.0)


func _close(instant: bool) -> void:
	is_open = false
	get_tree().paused = _was_paused
	if instant:
		if _tween != null:
			_tween.kill()
		modulate.a = 0.0
		visible = false
	else:
		_fade(0.0)


func _fade(to: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "modulate:a", to, 0.2)
	if to <= 0.0:
		_tween.tween_callback(func() -> void:
			if not is_open:
				visible = false)


func _draw() -> void:
	if player == null:
		return
	var font: Font = ThemeDB.fallback_font
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.88))
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var chalks: Array[Node] = get_tree().get_nodes_in_group("chalk_mark")
	# Extent around the player.
	var hx := MARGIN_M
	var hy := MARGIN_M
	var pts: Array[Vector2] = _points.duplicate()
	for pg in _pings:
		var pv: Vector2 = pg["pos"]
		pts.append(pv)
	for c in chalks:
		var c3 := c as Node3D
		if c3 != null:
			pts.append(Vector2(c3.global_position.x, c3.global_position.z))
	for v in pts:
		hx = maxf(hx, absf(v.x - pp.x) + MARGIN_M)
		hy = maxf(hy, absf(v.y - pp.y) + MARGIN_M)
	var sc := clampf(minf(sz.x * 0.42 / hx, (sz.y * 0.40) / hy), MIN_SCALE, MAX_SCALE)
	var centre := sz * 0.5 + Vector2(0, 6)
	var t := Time.get_ticks_msec() / 1000.0
	# Ping glyphs.
	for pg in _pings:
		var pv: Vector2 = pg["pos"]
		var kind: int = pg["kind"]
		var p := centre + (pv - pp) * sc
		var col := Style.CYAN
		var rad := 9.0
		if kind == 1:
			rad = 5.0
		elif kind == 2:
			col = Style.GOLD
			rad = 6.0
		var ph := fposmod(t * 0.5 + pv.x * 0.13 + pv.y * 0.07, 1.0)
		draw_arc(p, rad * 0.5, 0.0, TAU, 24, Color(col, 0.35), 1.0, true)
		draw_arc(p, rad * (0.5 + ph), 0.0, TAU, 28, Color(col, 0.28 * (1.0 - ph)), 1.5, true)
		draw_circle(p, 1.5, Color(col, 0.6))
	# Path.
	if _points.size() > 1:
		var line := PackedVector2Array()
		for v in _points:
			line.append(centre + (v - pp) * sc)
		line.append(centre)
		draw_polyline(line, Color(Style.CYAN, 0.75), 1.5, true)
	# Chalk marks.
	for c in chalks:
		var c3 := c as Node3D
		if c3 == null:
			continue
		var cp := centre + (Vector2(c3.global_position.x, c3.global_position.z) - pp) * sc
		var cc: Color = Style.GOLD
		if c3.has_meta("color"):
			var mc: Variant = c3.get_meta("color")
			if mc is Color:
				cc = mc
				cc.a = 1.0
				cc = cc.lightened(0.35)
		draw_circle(cp, 5.0, cc)
		if c3.has_meta("number"):
			var num: String = str(c3.get_meta("number"))
			draw_string(font, cp + Vector2(8, 5), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, cc)
	# Player arrow (yaw 0 faces -Z, i.e. up the map).
	var yaw: float = player.rotation.y
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-fwd.y, fwd.x)
	var arrow := PackedVector2Array([
		centre + fwd * 11.0,
		centre - fwd * 7.0 + side * 7.0,
		centre - fwd * 3.0,
		centre - fwd * 7.0 - side * 7.0,
	])
	draw_colored_polygon(arrow, Color.WHITE)
	# Text.
	draw_string(font, Vector2(0, 52), "EXPLORED", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 26, Style.CYAN)
	draw_string(font, Vector2(sz.x - 60, 36), "N", HORIZONTAL_ALIGNMENT_CENTER, 24, 18, Style.MUTED)
	draw_line(Vector2(sz.x - 48, 46), Vector2(sz.x - 48, 70), Style.MUTED, 1.5)
	var ly := sz.y - 70.0
	var lx := 40.0
	draw_line(Vector2(lx, ly), Vector2(lx + 22, ly), Style.CYAN, 2.0)
	draw_string(font, Vector2(lx + 30, ly + 5), "Path", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Style.TEXT)
	draw_arc(Vector2(lx + 11, ly + 24), 7.0, 0.0, TAU, 20, Style.CYAN, 1.5, true)
	draw_string(font, Vector2(lx + 30, ly + 29), "Ping", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Style.TEXT)
	draw_arc(Vector2(lx + 11, ly + 48), 5.0, 0.0, TAU, 20, Style.GOLD, 1.5, true)
	draw_string(font, Vector2(lx + 30, ly + 53), "Pebble", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Style.TEXT)
	draw_circle(Vector2(lx + 110, ly), 5.0, Style.GOLD)
	draw_string(font, Vector2(lx + 122, ly + 5), "Chalk", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Style.TEXT)
	draw_string(font, Vector2(0, sz.y - 36), "[M] close", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 18, Style.MUTED)
