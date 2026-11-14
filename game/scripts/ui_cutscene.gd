extends Node
## In-engine cutscenes: letterbox, subtitles, hold-to-skip, own camera.
## The player's own camera is rewritten every frame by player.gd, so shots that
## move the camera use a dedicated Camera3D owned by this node.

signal finished(cutscene_name: String)

const BAR_HEIGHT := 96.0
const SKIP_HOLD := 1.0
const EYE_HEIGHT := 1.6

var playing := false

var cam_pos := Vector3.ZERO
var cam_yaw := 0.0
var cam_pitch := 0.0
var cam_roll := 0.0
var cam_fov := 75.0
var shake_amount := 0.0
var overlay_alpha := 0.0

var _player: Node3D
var _ui: Node
var _layer: CanvasLayer
var _top_bar: ColorRect
var _bottom_bar: ColorRect
var _overlay: ColorRect
var _subtitle: Label
var _hint: Label
var _ring: Control
var _cam: Camera3D
var _cam_active := false
var _skip := false
var _held := false
var _hold_time := 0.0
var _tweens: Array[Tween] = []
var _prev_state := 0
var _locked_by_state := false
var _sub_tween: Tween


## Called by main.gd: builds the letterbox bars, subtitle, skip hint and camera.
func setup(player: Node3D, ui: Node) -> void:
	_player = player
	_ui = ui
	if _layer != null:
		return
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)

	_overlay = ColorRect.new()
	_overlay.color = Color.BLACK
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.modulate.a = 0.0
	_layer.add_child(_overlay)

	_top_bar = _make_bar(true)
	_bottom_bar = _make_bar(false)

	_subtitle = Label.new()
	_subtitle.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_subtitle.offset_top = -BAR_HEIGHT
	_subtitle.offset_bottom = 0.0
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_font_size_override("font_size", 22)
	_subtitle.add_theme_color_override("font_color", Color(0.9, 0.93, 0.95))
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.visible_ratio = 0.0
	_layer.add_child(_subtitle)

	_hint = Label.new()
	_hint.text = "Hold any key to skip"
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.75, 0.8))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_right = -56.0
	_hint.offset_bottom = -34.0
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_hint)

	_ring = Control.new()
	_ring.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ring.offset_left = -46.0
	_ring.offset_top = -46.0
	_ring.offset_right = -16.0
	_ring.offset_bottom = -16.0
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	_layer.add_child(_ring)

	_cam = Camera3D.new()
	add_child(_cam)
	_layer.visible = false
	set_process(false)
	set_process_input(false)


## Makes one black letterbox bar (top or bottom), starting at zero height.
func _make_bar(top: bool) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color.BLACK
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if top:
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0
		bar.anchor_bottom = 0.0
		bar.offset_top = 0.0
		bar.offset_bottom = 0.0
	else:
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 1.0
		bar.anchor_bottom = 1.0
		bar.offset_top = 0.0
		bar.offset_bottom = 0.0
	_layer.add_child(bar)
	return bar


## Draws the hold-to-skip progress ring.
func _draw_ring() -> void:
	var c := Vector2(15.0, 15.0)
	_ring.draw_arc(c, 11.0, 0.0, TAU, 32, Color(1, 1, 1, 0.25), 2.0)
	var frac := clampf(_hold_time / SKIP_HOLD, 0.0, 1.0)
	if frac > 0.0:
		_ring.draw_arc(c, 11.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 32, Color(1, 1, 1, 0.95), 3.0)


# ------------------------------------------------------------------ Frame loop

## Tracks whether any key / mouse button / pad button is being held (to skip).
func _input(event: InputEvent) -> void:
	if not playing:
		return
	var pressed := false
	var released := false
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.echo:
			return
		pressed = key.pressed
		released = not key.pressed
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		pressed = mb.pressed
		released = not mb.pressed
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		pressed = jb.pressed
		released = not jb.pressed
	if pressed:
		_held = true
	elif released:
		_held = false


## Per-frame: skip-hold progress, overlay fade and the cutscene camera.
func _process(delta: float) -> void:
	if not playing:
		return
	if _held and not _skip:
		_hold_time += delta
		if _hold_time >= SKIP_HOLD:
			_do_skip()
	elif _hold_time > 0.0:
		_hold_time = maxf(_hold_time - delta * 2.0, 0.0)
	_ring.queue_redraw()
	_overlay.modulate.a = overlay_alpha
	if _cam_active:
		_update_camera()


## Moves the cutscene camera to cam_pos / angles / fov, with shake.
func _update_camera() -> void:
	var angles := Vector3(cam_pitch, cam_yaw, cam_roll)
	var rotation_basis := Basis.from_euler(angles, EULER_ORDER_YXZ)
	_cam.global_transform = Transform3D(rotation_basis, cam_pos)
	_cam.fov = cam_fov
	var s := shake_amount
	if Settings.reduce_shake:
		s = shake_amount * 0.2
	_cam.h_offset = randf_range(-s, s)
	_cam.v_offset = randf_range(-s, s)


## Skips the rest of the cutscene: stops every running animation.
func _do_skip() -> void:
	_skip = true
	for t in _tweens:
		if t != null and t.is_valid():
			t.kill()
	_tweens.clear()
	if _sub_tween != null and _sub_tween.is_valid():
		_sub_tween.kill()
	_subtitle.visible_ratio = 0.0
	shake_amount = 0.0
	_ring.queue_redraw()


# ------------------------------------------------------------------ Helpers

## Creates a tween that will be stopped if the cutscene is skipped.
func _tw() -> Tween:
	var t := create_tween()
	_tweens.append(t)
	return t


## Waits `seconds` of game time, returning early when skipped.
func _wait(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds and not _skip:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


## Plays a sound (unless skipping).
func _sfx(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if _skip:
		return
	Sfx.play(sound, volume_db, &"Master", pitch)


## Shows an echo ping at `pos` (unless skipping).
func _ping(pos: Vector3, radius: float) -> void:
	if _skip:
		return
	Echo.emit_ping(pos, radius, false)


## Types a subtitle line onto the screen.
func _say(text: String) -> void:
	if _skip:
		return
	if _sub_tween != null and _sub_tween.is_valid():
		_sub_tween.kill()
	_subtitle.text = text
	_subtitle.visible_ratio = 0.0
	_sub_tween = create_tween()
	_sub_tween.tween_property(_subtitle, "visible_ratio", 1.0, maxf(0.4, text.length() * 0.045))


## Hides the subtitle line.
func _clear_say() -> void:
	if _sub_tween != null and _sub_tween.is_valid():
		_sub_tween.kill()
	_subtitle.visible_ratio = 0.0


## Adds one property animation to tween `t` with the given curve.
func _eased(t: Tween, property: String, value: Variant, seconds: float, trans: Tween.TransitionType, ease_type: Tween.EaseType) -> void:
	var step := t.tween_property(self, property, value, seconds)
	step.set_trans(trans)
	step.set_ease(ease_type)


## Adds one property animation that starts and ends gently (sine in-out).
func _smooth(t: Tween, property: String, value: Variant, seconds: float) -> void:
	_eased(t, property, value, seconds, Tween.TRANS_SINE, Tween.EASE_IN_OUT)


## Slides the black letterbox bars in (open) or out.
func _bars(open: bool, seconds: float) -> void:
	var h := 0.0
	if open:
		h = BAR_HEIGHT
	if _skip or seconds <= 0.0:
		_top_bar.offset_bottom = h
		_bottom_bar.offset_top = -h
		return
	var t := _tw()
	t.set_parallel(true)
	var top_step := t.tween_property(_top_bar, "offset_bottom", h, seconds)
	top_step.set_trans(Tween.TRANS_SINE)
	top_step.set_ease(Tween.EASE_IN_OUT)
	var bottom_step := t.tween_property(_bottom_bar, "offset_top", -h, seconds)
	bottom_step.set_trans(Tween.TRANS_SINE)
	bottom_step.set_ease(Tween.EASE_IN_OUT)


## Fades the full-screen overlay to `to_alpha`.
func _fade(to_alpha: float, seconds: float) -> void:
	if _skip:
		overlay_alpha = to_alpha
		return
	_tw().tween_property(self, "overlay_alpha", to_alpha, seconds)


## Yaw (x) and pitch (y) for a camera at `from` to look at `to`.
func _angles_to(from: Vector3, to: Vector3) -> Vector2:
	var d := to - from
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	return Vector2(yaw, pitch)


## Finds a "cutscene_marker" node by name, or null.
func _marker(marker_name: String) -> Node3D:
	for n in get_tree().get_nodes_in_group("cutscene_marker"):
		if n.name == marker_name and n is Node3D:
			return n as Node3D
	return null


## Common start for every cutscene: resets state and takes control from the player.
func _begin() -> void:
	playing = true
	_skip = false
	_held = false
	_hold_time = 0.0
	_tweens.clear()
	overlay_alpha = 0.0
	shake_amount = 0.0
	_overlay.color = Color.BLACK
	_clear_say()
	_layer.visible = true
	set_process(true)
	set_process_input(true)
	_prev_state = int(Game.state)
	# The ending keeps WON (the player is already frozen and other systems check it).
	_locked_by_state = Game.state != Game.State.WON
	if _locked_by_state:
		Game.set("state", Game.State.CUTSCENE)


## Switches to the cutscene camera, starting where the player camera is.
func _use_camera() -> void:
	var pc: Camera3D = _player.get("camera") as Camera3D
	if pc != null:
		_cam.global_transform = pc.global_transform
		cam_fov = pc.fov
	_cam_active = true
	_cam.make_current()


## Gives the view back to the player camera.
func _release_camera() -> void:
	_cam_active = false
	_cam.h_offset = 0.0
	_cam.v_offset = 0.0
	var pc: Camera3D = _player.get("camera") as Camera3D
	if pc != null:
		pc.make_current()


## restore_control false: leave the state and camera as they are (ending).
func _end(cutscene_name: String, restore_control: bool) -> void:
	_clear_say()
	_bars(false, 0.6)
	if not _skip:
		await _wait(0.65)
	overlay_alpha = 0.0
	shake_amount = 0.0
	_overlay.modulate.a = 0.0
	_top_bar.offset_bottom = 0.0
	_bottom_bar.offset_top = 0.0
	if restore_control:
		_release_camera()
		if _locked_by_state:
			if Game.state == Game.State.CUTSCENE:
				Game.set("state", _prev_state)
		else:
			_player.set_physics_process(true)
		_layer.visible = false
		set_process(false)
		set_process_input(false)
	else:
		_hint.visible = false
		_ring.visible = false
		_subtitle.visible = false
		set_process_input(false)
	playing = false
	_held = false
	_hold_time = 0.0
	_skip = false
	finished.emit(cutscene_name)


## Shows the skip hint, ring and subtitle (the ending hides them).
func _prepare_ui_for_run() -> void:
	_hint.visible = true
	_ring.visible = true
	_subtitle.visible = true


# ------------------------------------------------------------------ 1. Intro (~20 s)

## The rope snaps and you fall into the cave.
func play_intro() -> void:
	if playing or _player == null:
		return
	_prepare_ui_for_run()
	_begin()
	var floor_pos: Vector3 = _player.global_position
	var yaw: float = _player.global_rotation.y
	var eye := floor_pos + Vector3(0.0, EYE_HEIGHT, 0.0)
	var start := floor_pos + Vector3(0.0, 7.0, 0.0)
	var marker := _marker("IntroCamera")
	if marker != null:
		start = marker.global_position
	_use_camera()
	cam_pos = start
	cam_yaw = yaw
	cam_pitch = -1.0
	cam_roll = 0.0
	cam_fov = 70.0
	overlay_alpha = 1.0
	_bars(true, 0.8)
	_fade(0.0, 1.5)

	# Pre-fall: a slow walk to the lip, looking down the sinkhole.
	if not _skip:
		var walk := _tw()
		walk.set_parallel(true)
		_smooth(walk, "cam_pos", start - Vector3(0.0, 1.8, 0.0), 8.0)
		_smooth(walk, "cam_pitch", -1.25, 8.0)
		walk.tween_property(self, "shake_amount", 0.003, 8.0)
	await _wait(1.0)
	_sfx("rope_creak", -8.0)
	_say("Mara's rope. Forty metres of it, and I trusted every knot.")
	await _wait(3.3)
	_sfx("rope_creak", -5.0, 0.95)
	_say("She came down here first. She said the cave sings back.")
	await _wait(3.2)
	_sfx("rope_creak", -2.0, 0.88)
	_say("The rope groans.")
	await _wait(1.5)
	_sfx("rope_snap")
	_clear_say()
	await _wait(0.3)

	# The fall.
	_fade(0.0, 0.25)
	shake_amount = 0.02
	if not _skip:
		var fall := _tw()
		fall.set_parallel(true)
		_eased(fall, "cam_pos", eye, 1.2, Tween.TRANS_QUAD, Tween.EASE_IN)
		_eased(fall, "cam_fov", 112.0, 1.2, Tween.TRANS_QUAD, Tween.EASE_IN)
		fall.tween_property(self, "cam_pitch", -0.5, 1.2)
		fall.tween_property(self, "shake_amount", 0.07, 1.2)
	await _wait(1.2)

	# Impact: the lantern smashes.
	_sfx("impact")
	_ping(floor_pos, 4.0)
	shake_amount = 0.12
	if not Settings.no_flash and not _skip:
		_overlay.color = Color(0.3, 0.9, 1.0)
		overlay_alpha = 0.55
		_fade(0.0, 0.3)
		var kick := _tw()
		kick.tween_property(self, "cam_fov", 75.0, 0.4)
	await _wait(0.12)
	overlay_alpha = 1.0
	_overlay.color = Color.BLACK
	shake_amount = 0.0
	cam_fov = 75.0

	# A long dark beat: breathing, a slow heartbeat.
	await _wait(0.8)
	_sfx("pant", -8.0, 0.8)
	await _wait(1.4)
	_sfx("heartbeat_slow", -6.0)
	await _wait(1.2)
	_sfx("exhale", -6.0, 0.85)
	await _wait(1.0)

	# Slow wake-up on the floor.
	var floor_eye := Vector3(floor_pos.x, floor_pos.y + 0.3, floor_pos.z)
	cam_pos = floor_eye
	cam_yaw = yaw
	cam_pitch = 0.35
	cam_roll = deg_to_rad(70.0)
	_fade(0.0, 2.2)
	if not _skip:
		var rise := _tw()
		rise.set_parallel(true)
		_smooth(rise, "cam_pos", eye, 4.5)
		_smooth(rise, "cam_roll", 0.0, 4.5)
		_smooth(rise, "cam_pitch", 0.0, 4.5)
	await _wait(1.0)
	_say("The rope snapped. The lantern's gone.")
	await _wait(3.0)
	_say("Call out. Listen. Find your way back.")
	await _wait(3.2)

	await _end("intro", true)


# ------------------------------------------------------------------ 2. Hall reveal (~8 s)

## The camera turns to show the nearest Listener.
func play_hall_reveal() -> void:
	if playing or _player == null:
		return
	_prepare_ui_for_run()
	_begin()
	var head: Node3D = _player.get("head") as Node3D
	var orig_yaw: float = _player.global_rotation.y
	var orig_pitch := 0.0
	var orig_pos: Vector3 = _player.global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
	if head != null:
		orig_pitch = head.rotation.x
		orig_pos = head.global_position
	var orig_fov := 75.0
	var pc: Camera3D = _player.get("camera") as Camera3D
	if pc != null:
		orig_fov = pc.fov
	var target := _closest_listener()
	_use_camera()
	cam_pos = orig_pos
	cam_yaw = orig_yaw
	cam_pitch = orig_pitch
	cam_roll = 0.0
	cam_fov = orig_fov
	_bars(true, 0.7)
	await _wait(0.7)
	if target != null:
		var focus := target.global_position + Vector3(0.0, 1.0, 0.0)
		var ang := _angles_to(orig_pos, focus)
		var yaw_to := orig_yaw + angle_difference(orig_yaw, ang.x)
		var pitch_to := clampf(ang.y, -1.2, 1.2)
		var push_to := orig_pos + (focus - orig_pos).normalized() * 1.2
		push_to.y = orig_pos.y
		if not _skip:
			var turn := _tw()
			turn.set_parallel(true)
			_smooth(turn, "cam_yaw", yaw_to, 2.2)
			_smooth(turn, "cam_pitch", pitch_to, 2.2)
		await _wait(2.4)
		_ping(focus, 8.0)
		_sfx("sting", -10.0)
		# Slow push-in while the echo holds.
		if not _skip:
			var push := _tw()
			push.set_parallel(true)
			_smooth(push, "cam_fov", orig_fov * 0.68, 4.5)
			_smooth(push, "cam_pos", push_to, 4.5)
		await _wait(1.0)
		_say("...it hasn't heard you. Yet.")
		await _wait(2.6)
		_say("Don't make a sound.")
		await _wait(1.6)
		if not _skip:
			var back := _tw()
			back.set_parallel(true)
			_smooth(back, "cam_yaw", orig_yaw, 1.2)
			_smooth(back, "cam_pitch", orig_pitch, 1.2)
			back.tween_property(self, "cam_fov", orig_fov, 1.2)
			back.tween_property(self, "cam_pos", orig_pos, 1.2)
		await _wait(1.2)
	else:
		await _wait(1.0)
	await _end("hall_reveal", true)


## The Listener nearest to the player, or null if there are none.
func _closest_listener() -> Node3D:
	var target: Node3D = null
	var best := INF
	for n in get_tree().get_nodes_in_group("listener"):
		var n3 := n as Node3D
		if n3 == null:
			continue
		var d: float = n3.global_position.distance_squared_to(_player.global_position)
		if d < best:
			best = d
			target = n3
	return target


# ------------------------------------------------------------------ 3. Ending (~25 s)

## Where the ending camera rises to: the ShaftTop marker, else 12 m above
## the exit, else 12 m above `from_pos`.
func _find_shaft_top(from_pos: Vector3) -> Vector3:
	var shaft := _marker("ShaftTop")
	if shaft != null:
		return shaft.global_position
	var exits := get_tree().get_nodes_in_group("exit")
	if exits.size() > 0 and exits[0] is Node3D:
		var exit_node: Node3D = exits[0]
		return exit_node.global_position + Vector3(0.0, 12.0, 0.0)
	return from_pos + Vector3(0.0, 12.0, 0.0)


## You climb out into daylight, then something answers from below.
func play_ending() -> void:
	if playing or _player == null:
		return
	_prepare_ui_for_run()
	_begin()
	var head: Node3D = _player.get("head") as Node3D
	var from_pos: Vector3 = _player.global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
	if head != null:
		from_pos = head.global_position
	var top := _find_shaft_top(from_pos)
	_use_camera()
	cam_pos = from_pos
	cam_yaw = _player.global_rotation.y
	cam_pitch = 0.0
	cam_roll = 0.0
	# How bright the warm daylight gets (dimmer with flashes turned off).
	var warm_peak := 0.95
	if Settings.no_flash:
		warm_peak = 0.55
	_overlay.color = Color(1.0, 0.93, 0.78)
	overlay_alpha = 0.0
	_bars(true, 0.9)

	# Rise through the shaft toward the light.
	_sfx("wind", -6.0)
	if not _skip:
		var rise := _tw()
		rise.set_parallel(true)
		_smooth(rise, "cam_pos", top, 7.0)
		_smooth(rise, "cam_pitch", 1.25, 3.0)
		rise.tween_property(self, "cam_fov", 85.0, 7.0)
		rise.tween_property(self, "shake_amount", 0.004, 7.0)
	await _wait(3.8)
	if not _skip:
		var glow := _tw()
		_eased(glow, "overlay_alpha", warm_peak, 3.0, Tween.TRANS_SINE, Tween.EASE_IN)
	await _wait(3.4)
	cam_pos = top
	shake_amount = 0.0
	await _wait(0.6)

	# The lip: turn and look back down into the colored cave.
	_fade(0.0, 2.2)
	if not _skip:
		var look := _tw()
		look.set_parallel(true)
		_smooth(look, "cam_pitch", -1.0, 3.2)
		look.tween_property(self, "cam_fov", 70.0, 3.2)
	await _wait(2.0)
	_say("You found your way back.")
	await _wait(3.6)

	# Then the sky.
	_sfx("birdsong", -8.0)
	if not _skip:
		var sky := _tw()
		sky.set_parallel(true)
		_smooth(sky, "cam_pitch", 1.2, 3.5)
		sky.tween_property(self, "cam_fov", 80.0, 3.5)
	await _wait(1.0)
	_say("Daylight. Real, ordinary daylight.")
	await _wait(4.0)

	# The twist: something answers from far below.
	_clear_say()
	_fade(0.0, 0.1)
	if not _skip:
		var dim := _tw()
		_smooth(dim, "cam_pitch", -1.2, 2.0)
	_sfx("drag_step", -14.0, 0.7)
	await _wait(1.2)
	_sfx("hiss", -12.0, 0.6)
	await _wait(1.2)
	_say("Mara never left. She just stopped needing her eyes.")
	await _wait(5.0)

	cam_pos = top
	cam_pitch = -1.2
	overlay_alpha = 0.0
	await _end("ending", false)


# ------------------------------------------------------------------ 4. Level 2 intro (~12 s)

## The camera sinks down into level 2.
func play_level2_intro() -> void:
	if playing or _player == null:
		return
	_prepare_ui_for_run()
	_begin()
	var head: Node3D = _player.get("head") as Node3D
	var eye: Vector3 = _player.global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
	if head != null:
		eye = head.global_position
	var yaw: float = _player.global_rotation.y
	_use_camera()
	cam_pos = eye + Vector3(0.0, 16.0, 0.0)
	cam_yaw = yaw
	cam_pitch = -1.35
	cam_roll = 0.0
	cam_fov = 62.0
	overlay_alpha = 1.0
	_bars(true, 0.8)
	_fade(0.0, 1.6)
	_sfx("drip", -6.0)
	if not _skip:
		var sink := _tw()
		sink.set_parallel(true)
		_eased(sink, "cam_pos", eye, 9.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
		_smooth(sink, "cam_pitch", 0.0, 9.0)
		sink.tween_property(self, "cam_fov", 75.0, 9.0)
		sink.tween_property(self, "shake_amount", 0.003, 9.0)
	await _wait(1.8)
	_sfx("drip", -4.0, 0.9)
	await _wait(1.4)
	_say("Jonah's notebook, last page: She went deeper. So do I.")
	await _wait(1.6)
	_sfx("drip", -3.0, 1.1)
	await _wait(2.2)
	_sfx("drag_step", -16.0, 0.8)
	_say("Something down here is still listening.")
	await _wait(2.0)
	_sfx("drip", -5.0, 0.8)
	await _wait(1.6)
	shake_amount = 0.0
	await _end("level2_intro", true)
