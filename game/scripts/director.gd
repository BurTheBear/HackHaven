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
const SCARE_CAPTIONS := {
	"drip": "[dripping in the dark]",
	"scrape": "[something scrapes across stone]",
	"knock": "[a knock in the dark]",
	"breath": "[breathing?]",
}
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


func setup(p: Node3D, u: Node) -> void:
	player = p
	ui = u
	if _ambience:
		_ambience.set("player", p)


func _ready() -> void:
	_heart = AudioStreamPlayer.new()
	add_child(_heart)
	_heart_slow = AudioStreamPlayer.new()
	add_child(_heart_slow)

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


func _process(delta: float) -> void:
	if player == null or Game.state != Game.State.PLAYING:
		dread = move_toward(dread, 0.0, delta)
		_apply(delta)
		return
	_run_time += delta
	_quiet_time += delta
	_dust_cooldown = maxf(_dust_cooldown - delta, 0.0)

	var listeners: Array = get_tree().get_nodes_in_group("listener")
	var nearest := INF
	for l in listeners:
		var d: float = l.global_position.distance_to(player.global_position)
		if l.asleep:
			d *= 1.6  # A sleeping one is less of a threat.
		nearest = minf(nearest, d)
	var target := clampf(1.0 - (nearest - DREAD_NEAR) / (DREAD_FAR - DREAD_NEAR), 0.0, 1.0)
	dread = move_toward(dread, target, delta * 1.5)

	# Near miss: dread spiked, then the thing moved off without catching you.
	_peak = maxf(_peak, dread)
	if _peak > 0.6 and dread < 0.2:
		_peak = 0.0
		_after_beat = AFTER_BEAT

	# Menace gauge: too long under high pressure, so ease off for a moment.
	if dread > 0.5:
		_menace += delta * dread
	else:
		_menace = maxf(_menace - delta * 0.5, 0.0)
	if _menace > MENACE_MAX:
		_menace = 0.0
		for l in listeners:
			if l.global_position.distance_to(player.global_position) < 14.0:
				l.retreat()

	# Hints: quiet players get a visitor wandering toward their general area.
	_hint_timer -= delta
	if _hint_timer <= 0.0:
		_hint_timer = randf_range(18.0, 32.0)
		if dread < 0.15 and _quiet_time > 12.0:
			_send_hint(listeners)

	# False scares: rarer the higher the dread (the real thing is scary enough).
	_scare_timer -= delta * (1.0 - 0.7 * dread)
	if _scare_timer <= 0.0:
		_scare_timer = randf_range(12.0, 26.0)
		if dread < 0.5 and not _is_silent():
			_false_scare()

	if _phantom_time > 0.0:
		_phantom_time -= delta
		if _phantom_time <= 0.0:
			_phantom.visible = false

	_shift_timer -= delta
	if _shift_timer <= 0.0:
		_shift_timer = randf_range(15.0, 30.0)
		if randf() < 0.6:
			_try_shift()

	_whisper(delta)
	_apply(delta)


func _apply(delta: float) -> void:
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
	if player:
		player.set("shake", dread * dread * 0.025)
	if ui:
		ui.call("set_dread", dread)


func _is_silent() -> bool:
	return _ambience != null and _ambience.call("is_silent") == true


func _on_ping(origin: Vector3, _radius: float, loud: bool) -> void:
	if player == null or not loud or origin.distance_to(player.global_position) > 2.0:
		return
	_quiet_time = 0.0
	# Phantom: now and then your echo shows a Listener that isn't there.
	# At most one per PHANTOM_GAP seconds, never twice in a row in the same area,
	# rarer as the menace builds.
	if _run_time < 40.0 or dread >= 0.3 or _run_time - _last_phantom_time < PHANTOM_GAP:
		return
	if randf() >= 0.15 * (1.0 - 0.6 * _menace / MENACE_MAX):
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
	var space := player.get_world_3d().direct_space_state
	var eye := player.global_position + Vector3.UP * 1.2
	var fwd := -player.global_basis.z
	var cam := get_viewport().get_camera_3d()
	if cam:
		fwd = -cam.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	for attempt in 6:
		var dir := fwd.rotated(Vector3.UP, randf_range(-0.9, 0.9))
		var want := randf_range(7.0, 14.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + dir * (want + 1.0), 1))
		var dist := want
		if not hit.is_empty():
			# Stop a body's width short of whatever the ray hit.
			dist = eye.distance_to(hit["position"]) - 1.0
		if dist < 7.0:
			continue
		var spot := eye + dir * dist
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(spot, spot + Vector3.DOWN * 3.0, 1))
		if down.is_empty():
			continue
		var floor_y: float = (down["position"] as Vector3).y
		if absf(floor_y - player.global_position.y) > 1.5:
			continue
		var feet := Vector3(spot.x, floor_y, spot.z)
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.2, feet + Vector3.UP * 2.3, 1)).is_empty():
			continue
		var side := dir.cross(Vector3.UP).normalized()
		var mid := feet + Vector3.UP * 1.1
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(mid, mid + side * 0.6, 1)).is_empty():
			continue
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(mid, mid - side * 0.6, 1)).is_empty():
			continue
		return feet
	return null


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
			var p := player.global_position + Vector3(sin(a), 0.0, cos(a)) * randf_range(7.0, 10.0)
			if not _open_floor(p):
				continue
			if not _route_ok(l.global_position, p):
				continue
			if l.wander_to(p):
				return
			break


func _open_floor(p: Vector3) -> bool:
	var space := player.get_world_3d().direct_space_state
	var eye := player.global_position + Vector3.UP * 1.2
	var spot := p + Vector3.UP * 1.2
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, spot, 1)).is_empty():
		return false
	return not space.intersect_ray(PhysicsRayQueryParameters3D.create(spot, spot + Vector3.DOWN * 2.5, 1)).is_empty()


func _route_ok(a: Vector3, b: Vector3) -> bool:
	if _nav != null and _nav.get("nav_ready") == true:
		var path: PackedVector3Array = _nav.call("find_path", a, b)
		if path.size() < 2:
			return false
		if path[path.size() - 1].distance_to(b) > 1.5:
			return false  # can't actually get there
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		return length < a.distance_to(b) * 2.5 + 8.0
	return _clear(a + Vector3.UP, b + Vector3.UP)


func _false_scare() -> void:
	var p: Variant = _open_point(8.0, 16.0)
	if p == null:
		return
	var spot: Vector3 = p
	var sound: String = FALSE_SCARES.pick_random()
	var node := Sfx.play_3d(sound, spot, -6.0, &"Cave", randf_range(0.8, 1.1), 4.0, 30.0)
	if sound == "breath" and node != null:
		# The breathing loop never ends on its own: one breath, then gone.
		get_tree().create_timer(2.9).timeout.connect(node.queue_free)
	Sfx.caption(str(SCARE_CAPTIONS.get(sound, "[a sound in the dark]")), spot, 6.0)


## Running kicks dust loose from the ceiling now and then.
func _on_noise(origin: Vector3, radius: float) -> void:
	if player == null or Game.state != Game.State.PLAYING or radius < 9.0:
		return
	if origin.distance_to(player.global_position) > 2.0 or _dust_cooldown > 0.0 or randf() > 0.18:
		return
	_dust_cooldown = randf_range(6.0, 12.0)
	var from := player.global_position + Vector3.UP * 1.5
	var hit := player.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 8.0, 1))
	var spot := from + Vector3.UP * 2.0
	if not hit.is_empty():
		spot = (hit["position"] as Vector3) + Vector3.DOWN * 0.2
	spot += Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
	Sfx.play_3d("dust", spot, -7.0, &"Cave", randf_range(0.85, 1.15), 3.0, 20.0)
	Sfx.caption("[dust trickles from above]", spot, 4.0)


## At high menace, very rarely, something whispers "...you..." right behind you.
func _whisper(delta: float) -> void:
	_whisper_timer -= delta
	if _whisper_timer > 0.0 or _menace < MENACE_MAX * 0.5 or dread < 0.3:
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
		if prop is CSGShape3D and not (prop as CSGShape3D).is_root_shape():
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


func _in_view(cam: Camera3D, pos: Vector3) -> bool:
	var offsets: Array[Vector3] = [Vector3.ZERO, Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for o in offsets:
		if cam.is_position_in_frustum(pos + o):
			return true
	return false


func _on_caught() -> void:
	_menace = 0.0
	_after_beat = 0.0
	_peak = 0.0
	if Settings.skip_jumpscare:
		# Gentler: no echo in your face and a quiet sting; the UI just fades.
		Sfx.play("sting", -14.0)
		return
	Sfx.play("sting", -2.0)
	# Jump scare: light up the thing that got you, right in your face.
	Echo.emit_ping(Game.catcher_position + Vector3.UP * 1.2, 5.0, false)
	if ui and not Settings.no_flash:
		ui.call("flash_red")


func _on_checkpoint() -> void:
	_menace = 0.0


func _on_won() -> void:
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
		var hit := player.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, to, 1))
		var end := to
		if hit:
			end = (hit["position"] as Vector3) - dir * 0.8
		if from.distance_to(end) >= min_d:
			return end
	return null


func _clear(a: Vector3, b: Vector3) -> bool:
	var hit := player.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(a, b, 1))
	return hit.is_empty()
