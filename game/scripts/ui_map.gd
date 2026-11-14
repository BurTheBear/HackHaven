extends Control
## Explored-only map (action "map"): the path you walked, where you pinged,
## and you. No level geometry. Pauses the tree while open.

const Style = preload("res://scripts/ui_style.gd")
const SAMPLE_EVERY := 0.5
const MIN_MOVE := 0.75
const PING_NEAR := 2.0
const MAX_POINTS := 4000
const MAX_PINGS := 300
const MAX_SCALE := 30.0
const MIN_SCALE := 2.0
const MARGIN_M := 4.0

## Kinds of ping marks on the map.
const KIND_LOUD := 0
const KIND_WHISPER := 1
const KIND_PEBBLE := 2

var player: Node3D
var is_open := false

var _points: Array[Vector2] = []
var _pings: Array[Dictionary] = []  ## pos: Vector2, r: float, kind: int (0 loud, 1 whisper, 2 pebble)
var _timer := 0.0
var _was_paused := false
var _tween: Tween


## Starts hidden; keeps running while the game is paused.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	modulate.a = 0.0
	if not Game.state_changed.is_connected(_on_state):
		Game.state_changed.connect(_on_state)


## Called by ui.gd: remembers the player and listens for pings.
func setup(p: Node3D) -> void:
	player = p
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not Echo.ping_emitted.is_connected(_on_ping):
		Echo.ping_emitted.connect(_on_ping)
	if not Game.state_changed.is_connected(_on_state):
		Game.state_changed.connect(_on_state)


## Back on the title screen: wipe the map and close it.
func _on_state(s: int) -> void:
	if s == Game.State.TITLE:
		_points.clear()
		_pings.clear()
		_timer = 0.0
		if is_open:
			_close(true)


## Remembers where a ping happened. Pings near the player are their own
## call (loud) or whisper; pings further away came from a pebble.
func _on_ping(origin: Vector3, radius: float, loud: bool) -> void:
	if player == null or Game.state != Game.State.PLAYING:
		return
	var flat := Vector2(origin.x, origin.z)
	var player_flat := _player_flat()
	var kind := KIND_PEBBLE
	if flat.distance_to(player_flat) <= PING_NEAR:
		if loud:
			kind = KIND_LOUD
		else:
			kind = KIND_WHISPER
	_pings.append({"pos": flat, "r": radius, "kind": kind})
	if _pings.size() > MAX_PINGS:
		_pings.pop_front()


## The player's position seen from above (x, z).
func _player_flat() -> Vector2:
	return Vector2(player.global_position.x, player.global_position.z)


## Opens / closes on the map key and records the walked path.
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
			_record_point()
	if visible:
		queue_redraw()


## Adds the player's position to the path if they moved far enough.
func _record_point() -> void:
	var here := _player_flat()
	if not _points.is_empty():
		var last: Vector2 = _points[_points.size() - 1]
		if last.distance_to(here) < MIN_MOVE:
			return
	_points.append(here)
	if _points.size() > MAX_POINTS:
		_points.pop_front()


## While open, swallow gameplay input (but let "map" and "pause" through).
func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action("map") or event.is_action("pause"):
		return
	var block := false
	if event is InputEventKey:
		block = true
	elif event is InputEventMouseButton:
		block = true
	elif event is InputEventJoypadButton:
		block = true
	elif event is InputEventMouseMotion:
		block = true
	elif event is InputEventJoypadMotion:
		block = true
	if block:
		get_viewport().set_input_as_handled()


func _open() -> void:
	is_open = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	_fade(1.0)


## Closes the map. `instant` skips the fade.
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


## Fades the map to alpha `to` (works while paused).
func _fade(to: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "modulate:a", to, 0.2)
	if to <= 0.0:
		_tween.tween_callback(_hide_if_closed)


## Called after the fade out finishes.
func _hide_if_closed() -> void:
	if not is_open:
		visible = false


func _draw() -> void:
	if player == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.88))
	var player_pos := _player_flat()
	var scale_px := _map_scale(player_pos)
	var centre := size * 0.5 + Vector2(0, 6)
	_draw_pings(centre, player_pos, scale_px)
	_draw_path(centre, player_pos, scale_px)
	_draw_player_arrow(centre)
	_draw_labels()


## Pixels per metre, chosen so everything seen so far fits on screen.
func _map_scale(player_pos: Vector2) -> float:
	# Collect every point that should fit.
	var pts: Array[Vector2] = _points.duplicate()
	for pg in _pings:
		var pv: Vector2 = pg["pos"]
		pts.append(pv)
	# Half-width and half-height (metres) around the player.
	var half_x := MARGIN_M
	var half_y := MARGIN_M
	for v in pts:
		half_x = maxf(half_x, absf(v.x - player_pos.x) + MARGIN_M)
		half_y = maxf(half_y, absf(v.y - player_pos.y) + MARGIN_M)
	var scale_x := size.x * 0.42 / half_x
	var scale_y := size.y * 0.40 / half_y
	var result := minf(scale_x, scale_y)
	return clampf(result, MIN_SCALE, MAX_SCALE)


## Ping marks: a ring plus an expanding ripple. Pebbles are gold.
func _draw_pings(centre: Vector2, player_pos: Vector2, scale_px: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for pg in _pings:
		var pv: Vector2 = pg["pos"]
		var kind: int = pg["kind"]
		var p := centre + (pv - player_pos) * scale_px
		var col := Style.CYAN
		var rad := 9.0
		if kind == KIND_WHISPER:
			rad = 5.0
		elif kind == KIND_PEBBLE:
			col = Style.GOLD
			rad = 6.0
		# Ripple phase 0..1, offset by position so marks don't pulse together.
		var ph := fposmod(t * 0.5 + pv.x * 0.13 + pv.y * 0.07, 1.0)
		draw_arc(p, rad * 0.5, 0.0, TAU, 24, Color(col, 0.35), 1.0, true)
		draw_arc(p, rad * (0.5 + ph), 0.0, TAU, 28, Color(col, 0.28 * (1.0 - ph)), 1.5, true)
		draw_circle(p, 1.5, Color(col, 0.6))


## The walked path, ending at the player.
func _draw_path(centre: Vector2, player_pos: Vector2, scale_px: float) -> void:
	if _points.size() <= 1:
		return
	var line := PackedVector2Array()
	for v in _points:
		line.append(centre + (v - player_pos) * scale_px)
	line.append(centre)
	draw_polyline(line, Color(Style.CYAN, 0.75), 1.5, true)


## White arrow for the player (yaw 0 faces -Z, i.e. up the map).
func _draw_player_arrow(centre: Vector2) -> void:
	var yaw: float = player.rotation.y
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-fwd.y, fwd.x)
	var arrow := PackedVector2Array()
	arrow.append(centre + fwd * 11.0)
	arrow.append(centre - fwd * 7.0 + side * 7.0)
	arrow.append(centre - fwd * 3.0)
	arrow.append(centre - fwd * 7.0 - side * 7.0)
	draw_colored_polygon(arrow, Color.WHITE)


## Title, north marker, legend and the close hint.
func _draw_labels() -> void:
	var font: Font = ThemeDB.fallback_font
	var sz := size
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
	draw_string(font, Vector2(0, sz.y - 36), "[M] close", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 18, Style.MUTED)
