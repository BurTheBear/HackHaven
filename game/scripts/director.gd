extends Node
## The horror director. Created by main.gd. Ideas taken from good horror games:
## - Alien: Isolation: a director that knows roughly where you are and nudges a
##   Listener toward that area, plus a "menace gauge" that backs the Listeners
##   off after too long under pressure (tension, then release).
## - Dead Space "fear emitters": the closer a Listener is, the faster your
##   heartbeat, the redder the screen edges, the more the camera trembles.
##   After a near miss the heart keeps pounding, then slowly calms.
## - Amnesia / P.T.: false scares. Sounds in the dark that might be nothing,
##   phantom red shapes in your echo that are gone on the next ping, props
##   that have moved when you look back, and (rarely) a whisper behind you.
## Children it creates: Ambience (audio_ambience.gd: drone, drips, wind,
## reverb, voice-log ducking, the Hall's silence, the ending) and AiNav
## (ai_nav.gd: a navmesh baked at runtime for the Listeners).

const DREAD_NEAR := 3.0
const DREAD_FAR := 18.0
const MENACE_MAX := 10.0  ## Seconds of high dread before the Listeners back off.
const FALSE_SCARES := ["drip", "scrape", "knock", "drip", "breath"]
const PHANTOM_GAP := 45.0  ## At most one phantom this often (seconds).
const AFTER_BEAT := 14.0  ## Seconds the heart takes to calm after a near miss.
const BodyRig := preload("res://scripts/ai_listener_body.gd")
const AmbienceScript := preload("res://scripts/audio_ambience.gd")
const NavScript := preload("res://scripts/ai_nav.gd")

var player: Node3D
var ui: Node
var dread := 0.0

var _menace := 0.0
var _beat_timer := 0.0
var _hint_timer := 25.0
var _scare_timer := 12.0
var _quiet_time := 0.0
var _run_time := 0.0
var _phantom_time := 0.0
var _last_phantom_time := -1000.0
var _last_phantom_pos := Vector3.ZERO
var _last_phantom_zone := ""
var _peak := 0.0
var _after_beat := 0.0
var _shift_timer := 20.0
var _whisper_timer := 75.0
var _dust_cooldown := 0.0
var _heart: AudioStreamPlayer
var _heart_slow: AudioStreamPlayer
var _phantom: Node3D
var _ambience: Node
var _nav: Node
var _chase := false
var _chase_music: AudioStreamPlayer
var _heart_spike: AudioStreamPlayer
var _spike := 0.0
var _music_tween: Tween
var _spike_timer := 0.0


## Called by main.gd once the player and the UI exist.
func setup(p: Node3D, u: Node) -> void:
	player = p
	ui = u
	if _ambience:
		_ambience.set("player", p)


## Creates the sound players, the phantom, the ambience and the navmesh baker,
## and listens to the game's signals.
func _ready() -> void:
	_heart = AudioStreamPlayer.new()
	add_child(_heart)
	_heart_slow = AudioStreamPlayer.new()
	add_child(_heart_slow)
	_heart_spike = AudioStreamPlayer.new()
	add_child(_heart_spike)
	_chase_music = AudioStreamPlayer.new()
	_chase_music.volume_db = -6.0
	_chase_music.finished.connect(_on_chase_music_finished)
	add_child(_chase_music)

	# Phantom: the same creepy silhouette as a real Listener, shown in an echo.
	_phantom = Node3D.new()
	_phantom.name = "Phantom"
	add_child(_phantom)
	BodyRig.build(_phantom, BodyRig.make_material())
	_phantom.visible = false

	_ambience = AmbienceScript.new()
	_ambience.name = "Ambience"
	_ambience.set("director", self)
	add_child(_ambience)
	_nav = NavScript.new()
	_nav.name = "AiNav"
	add_child(_nav)

	Echo.ping_emitted.connect(_on_ping)
	Echo.noise_made.connect(_on_noise)
	Game.player_caught.connect(_on_caught)
	Game.checkpoint_reached.connect(_on_checkpoint)
	Game.game_won.connect(_on_won)
	Game.level_event.connect(_on_level_event)


## Every frame: work out the dread, then run all the scare timers.
func _process(delta: float) -> void:
	# Not playing (menu, caught, won): let the dread calm down and stop there.
	if player == null or Game.state != Game.State.PLAYING:
		dread = move_toward(dread, 0.0, delta)
		_apply(delta)
		return
	_run_time += delta
	_quiet_time += delta
	_dust_cooldown = maxf(_dust_cooldown - delta, 0.0)

	var listeners: Array = get_tree().get_nodes_in_group("listener")
	_update_dread(listeners, delta)
	_update_menace(listeners, delta)
	_update_hints(listeners, delta)
	_update_false_scares(delta)
	_update_phantom(delta)
	_update_shifting_props(delta)
	_whisper(delta)
	_apply(delta)


## How close the nearest Listener is (a sleeping one counts as farther away).
func _nearest_listener_distance(listeners: Array) -> float:
	var nearest := INF
	for l in listeners:
		var d: float = l.global_position.distance_to(player.global_position)
		if l.asleep:
			d *= 1.6  # A sleeping one is less of a threat.
		if d < nearest:
			nearest = d
	return nearest


## Dread goes from 0 (Listeners far away) to 1 (one right next to you).
func _update_dread(listeners: Array, delta: float) -> void:
	var nearest := _nearest_listener_distance(listeners)
	# 1 at DREAD_NEAR meters or closer, 0 at DREAD_FAR meters or farther.
	var how_far := (nearest - DREAD_NEAR) / (DREAD_FAR - DREAD_NEAR)
	var target := clampf(1.0 - how_far, 0.0, 1.0)
	var rate := 1.5
	if _chase:
		target = 1.0  # a chase maxes the dread
		rate = 3.0
	dread = move_toward(dread, target, delta * rate)

	# Near miss: dread spiked, then the thing moved off without catching you.
	if dread > _peak:
		_peak = dread
	if _peak > 0.6 and dread < 0.2:
		_peak = 0.0
		_after_beat = AFTER_BEAT


## Menace gauge: too long under high pressure, so the Listeners ease off.
func _update_menace(listeners: Array, delta: float) -> void:
	if dread > 0.5 and not _chase:
		_menace += delta * dread
	else:
		_menace = maxf(_menace - delta * 0.5, 0.0)
	if _menace > MENACE_MAX:
		_menace = 0.0
		for l in listeners:
			if l.global_position.distance_to(player.global_position) < 14.0:
				l.retreat()


## Hints: quiet players get a visitor wandering toward their general area.
func _update_hints(listeners: Array, delta: float) -> void:
	_hint_timer -= delta
	if _hint_timer > 0.0:
		return
	_hint_timer = randf_range(18.0, 32.0)
	if dread < 0.15 and _quiet_time > 12.0:
		_send_hint(listeners)


## False scares: rarer the higher the dread (the real thing is scary enough).
func _update_false_scares(delta: float) -> void:
	var speed := 1.0 - 0.7 * dread
	_scare_timer -= delta * speed
	if _scare_timer > 0.0:
		return
	_scare_timer = randf_range(12.0, 26.0)
	if dread < 0.5 and not _is_silent():
		_false_scare()


## Hides the phantom again once its time is up.
func _update_phantom(delta: float) -> void:
	if _phantom_time <= 0.0:
		return
	_phantom_time -= delta
	if _phantom_time <= 0.0:
		_phantom.visible = false


## Now and then, try to move a prop while you aren't looking.
func _update_shifting_props(delta: float) -> void:
	_shift_timer -= delta
	if _shift_timer > 0.0:
		return
	_shift_timer = randf_range(15.0, 30.0)
	if randf() < 0.6:
		_try_shift()


## Heartbeat sounds, camera shake and the red screen edges, from the dread.
func _apply(delta: float) -> void:
	_play_spike_beats(delta)
	_play_heartbeat(delta)
	if player:
		player.set("shake", dread * dread * 0.025)
	if ui:
		ui.call("set_dread", dread)


## Near miss: a few sharp, fast heartbeats on top of everything.
func _play_spike_beats(delta: float) -> void:
	if _spike <= 0.0 or Game.state != Game.State.PLAYING:
		return
	_spike -= delta
	_spike_timer -= delta
	if _spike_timer <= 0.0:
		_spike_timer = 0.3
		_heart_spike.stream = Sfx.stream("heartbeat")
		_heart_spike.volume_db = -1.0
		_heart_spike.pitch_scale = 1.15
		_heart_spike.play()


## The normal heartbeat (faster and louder with dread), or the slow calming
## heartbeat after a near miss.
func _play_heartbeat(delta: float) -> void:
	if dread > 0.08:
		_beat_timer -= delta
		if _beat_timer <= 0.0:
			_beat_timer = lerpf(1.1, 0.38, dread)
			_heart.stream = Sfx.stream("heartbeat")
			_heart.volume_db = lerpf(-22.0, -3.0, dread)  # always under the ping
			_heart.play()
	elif _after_beat > 0.0 and Game.state == Game.State.PLAYING:
		# After a near miss: the heart keeps going, quieter and slower each beat.
		_after_beat -= delta
		_beat_timer -= delta
		if _beat_timer <= 0.0:
			var calm := 1.0 - _after_beat / AFTER_BEAT
			_beat_timer = lerpf(0.7, 1.6, calm)
			_heart_slow.stream = Sfx.stream("heartbeat_slow")
			_heart_slow.volume_db = lerpf(-11.0, -30.0, calm)
			_heart_slow.play()
	else:
		_beat_timer = 0.0


## True during the Hall's sudden silence (no false scares then).
func _is_silent() -> bool:
	if _ambience == null:
		return false
	return _ambience.call("is_silent") == true


## The player pinged: maybe show a phantom Listener in the echo.
func _on_ping(origin: Vector3, _radius: float, loud: bool) -> void:
	if player == null or not loud:
		return
	# Only the player's own pings (not pebbles far away).
	if origin.distance_to(player.global_position) > 2.0:
		return
	_quiet_time = 0.0
	# Phantom: now and then your echo shows a Listener that isn't there.
	# At most one per PHANTOM_GAP seconds, never twice in a row in the same area,
	# rarer as the menace builds.
	if _run_time < 40.0 or dread >= 0.3:
		return
	if _run_time - _last_phantom_time < PHANTOM_GAP:
		return
	var menace_part := _menace / MENACE_MAX
	var chance := 0.15 * (1.0 - 0.6 * menace_part)
	if randf() >= chance:
		return
	var zone := Game.current_zone
	if zone != "" and zone == _last_phantom_zone:
		return
	if _last_phantom_time > 0.0 and player.global_position.distance_to(_last_phantom_pos) < 25.0:
		return
	var p: Variant = _phantom_spot()
	if p == null:
		return
	var feet: Vector3 = p
	_phantom.global_position = feet
	var look := Vector3(player.global_position.x, feet.y, player.global_position.z)
	if look.distance_to(feet) > 0.5:
		_phantom.look_at(look, Vector3.UP)
	_phantom.visible = true
	_phantom_time = 3.0
	_last_phantom_time = _run_time
	_last_phantom_pos = player.global_position
	_last_phantom_zone = zone


## A spot for a phantom, verified with raycasts on the world layer: 7-14 m
## away, roughly where the player is looking, with a body's width of clear
## space from walls and pillars, solid floor near the player's height (not
## over the chasm) and headroom above. Returns the feet position or null.
func _phantom_spot() -> Variant:
	var eye := player.global_position + Vector3.UP * 1.2
	var forward := _flat_view_forward()
	for attempt in 6:
		var angle := randf_range(-0.9, 0.9)
		var dir := forward.rotated(Vector3.UP, angle)
		var want := randf_range(7.0, 14.0)

		# How far can we go that way? Stop a body's width short of any wall.
		var dist := want
		var hit := _ray(eye, eye + dir * (want + 1.0))
		if not hit.is_empty():
			var hit_pos: Vector3 = hit["position"]
			dist = eye.distance_to(hit_pos) - 1.0
		if dist < 7.0:
			continue
		var spot := eye + dir * dist

		# There must be floor below, close to the player's height.
		var down := _ray(spot, spot + Vector3.DOWN * 3.0)
		if down.is_empty():
			continue
		var floor_pos: Vector3 = down["position"]
		var floor_y := floor_pos.y
		if absf(floor_y - player.global_position.y) > 1.5:
			continue
		var feet := Vector3(spot.x, floor_y, spot.z)

		# Headroom above it.
		if not _clear(feet + Vector3.UP * 0.2, feet + Vector3.UP * 2.3):
			continue

		# Room on both sides.
		var side := dir.cross(Vector3.UP).normalized()
		var mid := feet + Vector3.UP * 1.1
		if not _clear(mid, mid + side * 0.6):
			continue
		if not _clear(mid, mid - side * 0.6):
			continue
		return feet
	return null


## The direction the camera looks, flattened onto the floor.
func _flat_view_forward() -> Vector3:
	var forward := -player.global_basis.z
	var cam := get_viewport().get_camera_3d()
	if cam:
		forward = -cam.global_basis.z
	forward.y = 0.0
	if forward.length() < 0.1:
		forward = Vector3.FORWARD
	return forward.normalized()


## Sends one Listener wandering toward the player's rough area. The spot is
## 7-10 m from the player (it also stops 6.5 m short of them on the way), in
## open floor the player has line of sight to, and reachable without going
## through rock (a navmesh path, or a clear straight line without one).
func _send_hint(listeners: Array) -> void:
	for l in listeners:
		if l.asleep:
			continue
		var dist: float = l.global_position.distance_to(player.global_position)
		if dist < 10.0 or dist > 35.0:
			continue
		for attempt in 4:
			var a := randf() * TAU
			var dir := Vector3(sin(a), 0.0, cos(a))
			var p := player.global_position + dir * randf_range(7.0, 10.0)
			if not _open_floor(p):
				continue
			if not _route_ok(l.global_position, p):
				continue
			if l.wander_to(p):
				return
			break


## True if the player can see spot `p` and there is floor under it.
func _open_floor(p: Vector3) -> bool:
	var eye := player.global_position + Vector3.UP * 1.2
	var spot := p + Vector3.UP * 1.2
	if not _clear(eye, spot):
		return false
	var has_floor := not _clear(spot, spot + Vector3.DOWN * 2.5)
	return has_floor


## True if a Listener can walk from a to b without a long detour.
func _route_ok(a: Vector3, b: Vector3) -> bool:
	var nav_ready: bool = _nav != null and _nav.get("nav_ready") == true
	if not nav_ready:
		# No navmesh: just check for a clear straight line.
		return _clear(a + Vector3.UP, b + Vector3.UP)

	var path: PackedVector3Array = _nav.call("find_path", a, b)
	if path.size() < 2:
		return false
	var path_end: Vector3 = path[path.size() - 1]
	if path_end.distance_to(b) > 1.5:
		return false  # can't actually get there

	# Add up the length of the path.
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	var longest_ok := a.distance_to(b) * 2.5 + 8.0
	return length < longest_ok


## A sound in the dark that might be nothing.
func _false_scare() -> void:
	var p: Variant = _open_point(8.0, 16.0)
	if p == null:
		return
	var spot: Vector3 = p
	var sound: String = FALSE_SCARES.pick_random()
	var node := Sfx.play_3d(sound, spot, -6.0, &"Cave", randf_range(0.8, 1.1), 4.0, 30.0)
	if sound == "breath" and node != null:
		# The breathing loop never ends on its own: one breath, then gone.
		var timer := get_tree().create_timer(2.9)
		timer.timeout.connect(node.queue_free)
	Sfx.caption(_scare_caption(sound), spot, 6.0)


## The subtitle text for a false scare sound.
func _scare_caption(sound: String) -> String:
	match sound:
		"drip":
			return "[dripping in the dark]"
		"scrape":
			return "[something scrapes across stone]"
		"knock":
			return "[a knock in the dark]"
		"breath":
			return "[breathing?]"
	return "[a sound in the dark]"


## Running kicks dust loose from the ceiling now and then.
func _on_noise(origin: Vector3, radius: float) -> void:
	if player == null or Game.state != Game.State.PLAYING:
		return
	if radius < 9.0:
		return  # only running is loud enough
	if origin.distance_to(player.global_position) > 2.0:
		return  # only the player's own noise
	if _dust_cooldown > 0.0 or randf() > 0.18:
		return
	_dust_cooldown = randf_range(6.0, 12.0)

	# Find the ceiling above the player.
	var from := player.global_position + Vector3.UP * 1.5
	var hit := _ray(from, from + Vector3.UP * 8.0)
	var spot := from + Vector3.UP * 2.0
	if not hit.is_empty():
		var ceiling: Vector3 = hit["position"]
		spot = ceiling + Vector3.DOWN * 0.2
	spot += Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
	Sfx.play_3d("dust", spot, -7.0, &"Cave", randf_range(0.85, 1.15), 3.0, 20.0)
	Sfx.caption("[dust trickles from above]", spot, 4.0)


## At high menace, very rarely, something whispers "...you..." right behind you.
func _whisper(delta: float) -> void:
	_whisper_timer -= delta
	if _whisper_timer > 0.0:
		return
	if _menace < MENACE_MAX * 0.5 or dread < 0.3:
		return
	_whisper_timer = randf_range(25.0, 40.0)
	if randf() > 0.4:
		return
	_whisper_timer = randf_range(110.0, 170.0)
	var back := player.global_basis.z
	var cam := get_viewport().get_camera_3d()
	if cam:
		back = cam.global_basis.z
	back.y = 0.0
	if back.length() < 0.1:
		return
	var pos := player.global_position + Vector3.UP * 1.6 + back.normalized() * 1.3
	Sfx.play_3d("whisper_name", pos, -9.0, &"Cave", randf_range(0.92, 1.02), 1.2, 10.0)
	Sfx.caption("[a whisper right behind you: \"...you...\"]", pos, 0.0)


## "Shifting" props: while one is out of view and you're 6 m+ away, it turns
## or slides a little. Each prop moves at most once.
func _try_shift() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var props: Array = get_tree().get_nodes_in_group("shifting")
	props.shuffle()
	for n in props:
		var prop := n as Node3D
		if prop == null or prop.has_meta("ai_shifted"):
			continue
		# A CSG piece inside a combiner would rebuild the whole cave: skip those.
		if prop is CSGShape3D:
			var csg: CSGShape3D = prop
			if not csg.is_root_shape():
				continue
		var pos := prop.global_position
		if pos.distance_to(player.global_position) < 6.0 or _in_view(cam, pos):
			continue
		prop.set_meta("ai_shifted", true)
		var turn := deg_to_rad(randf_range(8.0, 20.0))
		if randf() < 0.5:
			turn = -turn
		prop.rotate_y(turn)
		prop.global_position = pos + Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
		return


## True if the camera can see `pos` (or anything within a meter of it).
func _in_view(cam: Camera3D, pos: Vector3) -> bool:
	var offsets: Array[Vector3] = [Vector3.ZERO, Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for o in offsets:
		if cam.is_position_in_frustum(pos + o):
			return true
	return false


## Reacts to near misses and to the scripted chase starting / ending.
func _on_level_event(event_name: String) -> void:
	match event_name:
		"near_miss":
			_spike = 2.4
			_spike_timer = 0.0
			_after_beat = AFTER_BEAT
			_peak = 0.0
		"chase_start":
			_chase = true
			if _music_tween:
				_music_tween.kill()
			_menace = 0.0
			_chase_music.stream = Sfx.stream("chase_music")
			_chase_music.volume_db = -6.0
			_chase_music.play()
		"chase_end":
			_stop_chase()


## Loops the chase music while the chase lasts.
func _on_chase_music_finished() -> void:
	if _chase and Game.state == Game.State.PLAYING:
		_chase_music.play()  # loop


## Ends the chase and fades the music out.
func _stop_chase() -> void:
	if not _chase:
		return
	_chase = false
	_music_tween = create_tween()
	_music_tween.tween_property(_chase_music, "volume_db", -40.0, 1.5)
	_music_tween.tween_callback(_chase_music.stop)  # stop once faded


## Caught: reset the tension and play the jump scare (unless it's turned off).
func _on_caught() -> void:
	_stop_chase()
	_spike = 0.0
	_menace = 0.0
	_after_beat = 0.0
	_peak = 0.0
	if Settings.skip_jumpscare:
		# Gentler: no echo in your face and a quiet sting; the UI just fades.
		Sfx.play("sting", -14.0)
		return
	# The UI plays the Blender attack and its synchronized sound mix.



## Reaching a checkpoint resets the menace gauge.
func _on_checkpoint() -> void:
	_menace = 0.0


## Game won: silence the heart and clear the scares.
func _on_won() -> void:
	_stop_chase()
	_spike = 0.0
	_heart.stop()
	_heart_slow.stop()
	_after_beat = 0.0
	_phantom.visible = false
	dread = 0.0


## A random open spot min_d..max_d from the player, or null.
func _open_point(min_d: float, max_d: float) -> Variant:
	var from := player.global_position + Vector3.UP * 1.2
	for attempt in 4:
		var a := randf() * TAU
		var dir := Vector3(sin(a), 0.0, cos(a))
		var to := from + dir * max_d
		var hit := _ray(from, to)
		var end := to
		if not hit.is_empty():
			var hit_pos: Vector3 = hit["position"]
			end = hit_pos - dir * 0.8
		if from.distance_to(end) >= min_d:
			return end
	return null


## Casts a ray against the world (layer 1). Empty if it hit nothing.
func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return space.intersect_ray(query)


## True if nothing solid is between a and b.
func _clear(a: Vector3, b: Vector3) -> bool:
	var hit := _ray(a, b)
	return hit.is_empty()
