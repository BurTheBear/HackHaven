extends Node
## Ambient sound bed, created by director.gd:
## - the cave drone (keeps playing, muffled, under the pause menu)
## - drips at the level's "drip_source" markers
## - wind from the "exit", audible in the last zone and growing as you approach
## - a slowly rising Shepard tone in the last zone (or when dread is high)
## - tape hiss under Mara's voice logs, with the ambience ducked; her last log
##   cuts off dead and is followed by two seconds of near silence
## - reverb that changes per zone (tunnels small, the Listening Hall huge)
## - the Hall's sudden silence (level_event "hall_silence")
## - birdsong and daylight wind at the ending

const WIND_RANGE := 45.0  ## Wind from the exit grows over this many meters.
const DRIP_RANGE := 28.0
const LAST_ZONE_WORDS := ["CLIMB", "FINAL", "SURFACE", "EXIT", "ZONE 4"]
const HALL_SILENCE := 1.5
const LAST_LOG_SILENCE := 2.0

var director: Node
var player: Node3D

var _drone: AudioStreamPlayer
var _shepard: AudioStreamPlayer
var _tape: AudioStreamPlayer
var _birds: AudioStreamPlayer
var _day_wind: AudioStreamPlayer
var _wind: AudioStreamPlayer3D
var _exit: Node3D
var _drips: Array[AudioStreamPlayer3D] = []
var _drip_wait: Array[float] = []
var _streams_ready := false
var _waited := 0.0
var _duck_db := 0.0
var _voice_left := 0.0
var _silence_left := 0.0
var _cut_pending := false
var _hall_breath_in := -1.0
var _hall_listener: Node3D
var _last_zone := false
var _shepard_rise := 0.0
var _won := false
var _wind_captioned := false


func _ready() -> void:
	_drone = _loop_player(&"Ambience", true)
	_shepard = _loop_player(&"Ambience", false)
	_shepard.pitch_scale = 0.6  # one octave every ~13 s: a slow, endless climb
	_tape = _loop_player(&"Voice", false)
	_birds = _loop_player(&"Ambience", true)
	_day_wind = _loop_player(&"Ambience", true)

	_wind = AudioStreamPlayer3D.new()
	_wind.bus = &"Ambience"
	# Loudness is set by hand from the distance (below); the 3D player only pans.
	_wind.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	_wind.volume_db = -80.0
	add_child(_wind)
	var exits := get_tree().get_nodes_in_group("exit")
	if not exits.is_empty():
		_exit = exits[0] as Node3D
	if _exit:
		_wind.global_position = _exit.global_position + Vector3.UP * 3.0

	for m in get_tree().get_nodes_in_group("drip_source"):
		var marker := m as Node3D
		if marker == null:
			continue
		var d := AudioStreamPlayer3D.new()
		d.bus = &"Ambience"
		d.unit_size = 3.0
		d.max_distance = DRIP_RANGE
		add_child(d)
		d.global_position = marker.global_position
		_drips.append(d)
		_drip_wait.append(randf_range(0.5, 4.0))

	Game.zone_entered.connect(_on_zone)
	Game.level_event.connect(_on_level_event)
	Game.voice_log.connect(_on_voice_log)
	Game.game_won.connect(_on_won)
	Sfx.set_ambience_gain(0.0)
	Sfx.set_reverb("drop", 0.05)


func _loop_player(bus: StringName, keep_during_pause: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = -80.0
	if keep_during_pause:
		p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p


## True during the Hall's silence or after Mara's last words (no false scares then).
func is_silent() -> bool:
	return _silence_left > 0.0


func _assign_streams() -> void:
	_streams_ready = true
	_drone.stream = Sfx.stream("drone")
	_shepard.stream = Sfx.stream("shepard")
	_tape.stream = Sfx.stream("tape_hiss")
	_birds.stream = Sfx.stream("birdsong")
	_day_wind.stream = Sfx.stream("wind")
	_wind.stream = Sfx.stream("wind")
	var drip := Sfx.stream("drip")
	for d in _drips:
		d.stream = drip


func _process(delta: float) -> void:
	if not _streams_ready:
		# Sounds are synthesized over the first frames; wait for them, then start.
		_waited += delta
		if Sfx.is_loaded or _waited > 6.0:
			_assign_streams()
		else:
			return
	var playing := Game.state == Game.State.PLAYING
	var dread := 0.0
	if director != null:
		dread = float(director.get("dread"))
	_update_duck(delta)
	_update_drone(delta, playing, dread)
	_update_drips(delta, playing)
	_update_wind(delta)
	_update_shepard(delta, playing, dread)
	_update_voice(delta)
	_update_hall(delta)
	_update_ending(delta)


func _update_duck(delta: float) -> void:
	_silence_left = maxf(_silence_left - delta, 0.0)
	var want := 0.0
	if _silence_left > 0.0:
		want = -80.0
	elif _voice_left > 0.0:
		want = -11.0
	var rate := 20.0
	if want <= -79.0:
		rate = 400.0  # silence falls like a cut
	elif want < _duck_db:
		rate = 25.0
	_duck_db = move_toward(_duck_db, want, rate * delta)
	Sfx.set_ambience_gain(_duck_db)


func _update_drone(delta: float, playing: bool, dread: float) -> void:
	if _won:
		_drone.volume_db = move_toward(_drone.volume_db, -80.0, delta * 15.0)
		if _drone.playing and _drone.volume_db <= -79.0:
			_drone.stop()
		return
	if playing and not _drone.playing:
		_drone.play()
	_drone.volume_db = move_toward(_drone.volume_db, lerpf(-21.0, -11.0, dread), delta * 12.0)


func _update_drips(delta: float, playing: bool) -> void:
	if not playing or _silence_left > 0.0 or player == null:
		return
	for i in _drips.size():
		_drip_wait[i] -= delta
		if _drip_wait[i] > 0.0:
			continue
		_drip_wait[i] = randf_range(1.8, 6.5)
		var d := _drips[i]
		if d.global_position.distance_to(player.global_position) < DRIP_RANGE:
			d.pitch_scale = randf_range(0.8, 1.25)
			d.volume_db = randf_range(-13.0, -7.0)
			d.play()


func _update_wind(delta: float) -> void:
	if _exit == null or player == null:
		return
	var dist := player.global_position.distance_to(_exit.global_position)
	var near := clampf(1.0 - dist / WIND_RANGE, 0.0, 1.0)
	var want := -80.0
	if not _won and (_last_zone or near > 0.0):
		want = lerpf(-30.0, -7.0, near)
	_wind.volume_db = move_toward(_wind.volume_db, want, delta * 10.0)
	if _wind.volume_db > -70.0 and not _wind.playing and _wind.stream != null:
		_wind.play()
		if not _wind_captioned:
			_wind_captioned = true
			Sfx.caption("[faint wind, far ahead]", _exit.global_position, 0.0)
	elif _wind.playing and _wind.volume_db <= -79.0:
		_wind.stop()


func _update_shepard(delta: float, playing: bool, dread: float) -> void:
	var active := playing and not _won and (_last_zone or dread > 0.65)
	var want := -80.0
	if active:
		if _last_zone:
			_shepard_rise = minf(_shepard_rise + delta / 90.0, 1.0)
		var level := maxf(_shepard_rise, clampf((dread - 0.65) / 0.35, 0.0, 1.0) * 0.6)
		want = lerpf(-30.0, -17.0, level)
	_shepard.volume_db = move_toward(_shepard.volume_db, want, delta * 6.0)
	if _shepard.volume_db > -70.0 and not _shepard.playing and _shepard.stream != null:
		_shepard.play()
	elif _shepard.playing and _shepard.volume_db <= -79.0:
		_shepard.stop()


func _update_voice(delta: float) -> void:
	if _voice_left <= 0.0:
		_tape.volume_db = move_toward(_tape.volume_db, -80.0, delta * 40.0)
		if _tape.playing and _tape.volume_db <= -79.0:
			_tape.stop()
		return
	_voice_left -= delta
	_tape.volume_db = move_toward(_tape.volume_db, -21.0, delta * 60.0)
	if _voice_left > 0.0 or not _cut_pending:
		return
	# Mara's last log cuts off mid-word: hard stop, then near silence.
	_cut_pending = false
	_tape.stop()
	_tape.volume_db = -80.0
	_silence_left = LAST_LOG_SILENCE
	for l in get_tree().get_nodes_in_group("listener"):
		if l.has_method("hush"):
			l.hush(LAST_LOG_SILENCE, 3.0)
	if player:
		Sfx.caption("[the recording cuts off]", player.global_position, 0.0)


func _update_hall(delta: float) -> void:
	if _hall_breath_in < 0.0:
		return
	_hall_breath_in -= delta
	if _hall_breath_in < 0.0 and _hall_listener != null and is_instance_valid(_hall_listener):
		Sfx.caption("[slow breathing, somewhere ahead]", _hall_listener.global_position, 0.0)


func _update_ending(delta: float) -> void:
	if not _won:
		return
	_birds.volume_db = move_toward(_birds.volume_db, -9.0, delta * 8.0)
	_day_wind.volume_db = move_toward(_day_wind.volume_db, -15.0, delta * 8.0)


func _on_zone(zone_name: String) -> void:
	var z := zone_name.to_upper()
	_last_zone = false
	for w in LAST_ZONE_WORDS:
		if str(w) in z:
			_last_zone = true
	Sfx.set_reverb(_preset_for(z), 2.5)


func _preset_for(z: String) -> String:
	if "HALL" in z:
		return "hall"
	if _last_zone or "CHASM" in z or "BRIDGE" in z:
		return "climb"
	if "DROP" in z:
		return "drop"
	return "tunnel"


func _on_level_event(event_name: String) -> void:
	if event_name == "hall_silence":
		_hall_silence()


## The Hall entrance scare: drone, drips and breathing all drop out at once.
## Then, out of the silence, the Hall Listener's breathing fades in.
func _hall_silence() -> void:
	_silence_left = HALL_SILENCE
	_hall_listener = _nearest_awake_listener()
	for l in get_tree().get_nodes_in_group("listener"):
		if l.has_method("hush"):
			l.hush(HALL_SILENCE, 2.5)
	if _hall_listener != null and _hall_listener.has_method("hush"):
		_hall_listener.call("hush", HALL_SILENCE, 3.0, 5.0)
	_hall_breath_in = HALL_SILENCE
	if player:
		Sfx.caption("[sudden silence]", player.global_position, 0.0)


func _nearest_awake_listener() -> Node3D:
	if player == null:
		return null
	var best: Node3D = null
	var best_d := INF
	for l in get_tree().get_nodes_in_group("listener"):
		var n := l as Node3D
		if n == null or n.get("asleep") == true:
			continue
		var d := n.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _on_voice_log(index: int, text: String) -> void:
	# Logs play elsewhere; estimate their length from the subtitle text.
	_voice_left = clampf(1.5 + text.length() * 0.07, 3.0, 25.0)
	if _tape.stream != null and not _tape.playing:
		_tape.play(randf() * 3.0)
	var t := text.strip_edges()
	_cut_pending = index == 8 or t.ends_with("-")


func _on_won() -> void:
	_won = true
	_voice_left = 0.0
	_cut_pending = false
	_silence_left = 0.0
	if not _streams_ready:
		_assign_streams()
	Sfx.set_reverb("open", 4.0)
	_birds.volume_db = -50.0
	_day_wind.volume_db = -50.0
	_birds.play()
	_day_wind.play()
