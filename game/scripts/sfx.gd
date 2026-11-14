extends Node
## Autoload "Sfx": every sound in ECHO, synthesized in code, so the game has
## audio with zero files.
##
## DROP-IN RECORDINGS (no code needed): before synthesizing a sound,
## stream(name) looks for res://audio/<name>.ogg, then .wav, then .mp3, and
## uses that file instead if it exists. To replace the drip, save a recording
## as game/audio/drip.ogg. Every sound name is listed in PRIORITY below.
## Names in LOOPS are set to loop automatically for .ogg / .mp3 files; for a
## looping .wav, set Loop Mode to Forward in Godot's Import dock.
##
## Sounds are built over several frames after startup, most important first,
## so the game never freezes. `loaded` fires (and is_loaded turns true) once
## all of them exist. stream(name) always works: a sound that isn't built yet
## is built on the spot.
##
## Buses (default_bus_layout.tres): Master (pause muffle low-pass + limiter),
## Cave (reverb, switched per zone with set_reverb), Voice (dry),
## Ambience (an amplifier the ambience uses to duck itself).
## Mix rule: the ping is always the loudest sound. Everything else is
## normalized below it and played at negative volumes.

## Emitted once every sound is built (UI can show "Listening..." until then).
signal loaded

const RATE := 16000
const LOW_RATE := 11025
const BIRD_RATE := 12000
const SHEPARD_RATE := 6000
const AUDIO_DIR := "res://audio/"
const EXTENSIONS := ["ogg", "wav", "mp3"]
## Keep building more sounds in the same frame only while under this budget.
const FRAME_BUDGET_USEC := 4000
const LOOPS := ["drone", "breath", "wind", "birdsong", "tape_hiss", "shepard"]
## Every sound name, in the order they're built after startup.
const PRIORITY := [
	"ping", "ui_hover", "ui_click", "ui_back", "step", "ready", "whisper_ping",
	"pebble", "chalk", "click", "land", "bump", "pant", "breath", "drone", "heartbeat",
	"hiss", "shriek", "drag_step", "sniff", "exhale", "sting", "chime",
	"pickup_pebbles", "crystal", "drip", "scrape", "knock", "step_wood",
	"step_gravel", "step_water", "heartbeat_slow", "dust", "whisper_name",
	"rope_creak", "rope_snap", "impact",
	"tape_hiss", "wind", "shepard", "birdsong",
]
## Cave-bus reverb per kind of space: room_size, damping, wet, predelay (ms).
const REVERB_PRESETS := {
	"drop": [0.38, 0.6, 0.24, 25.0],
	"tunnel": [0.5, 0.55, 0.3, 35.0],
	"hall": [0.97, 0.18, 0.58, 120.0],
	"climb": [0.75, 0.35, 0.42, 70.0],
	"open": [0.2, 0.8, 0.06, 10.0],
}

var is_loaded := false

var _cache := {}
var _queue_index := 0
var _players: Array[AudioStreamPlayer] = []
var _ui_players: Array[AudioStreamPlayer] = []
var _caption_times := {}
var _reverb_tween: Tween
var _duck: AudioEffectAmplify


func _ready() -> void:
	# Keeps building sounds, and playing UI clicks, while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(p)
		_players.append(p)
	for i in 4:
		var u := AudioStreamPlayer.new()
		add_child(u)
		_ui_players.append(u)


## Builds the sound bank a little at a time: at least one sound per frame,
## more only while the frame budget allows.
func _process(_delta: float) -> void:
	if is_loaded:
		set_process(false)
		return
	var start := Time.get_ticks_usec()
	while _queue_index < PRIORITY.size():
		var sound: String = PRIORITY[_queue_index]
		_queue_index += 1
		if not _cache.has(sound):
			stream(sound)
			if Time.get_ticks_usec() - start > FRAME_BUDGET_USEC:
				return
	is_loaded = true
	set_process(false)
	loaded.emit()


## Fire-and-forget 2D sound. Names starting with "ui_" also play while paused.
func play(sound: String, volume_db: float = 0.0, bus: StringName = &"Master", pitch: float = 1.0) -> void:
	var pool: Array[AudioStreamPlayer] = _players
	if sound.begins_with("ui_"):
		pool = _ui_players
	var p: AudioStreamPlayer = pool[0]
	var longest := -1.0
	for q in pool:
		if not q.playing:
			p = q
			break
		var at := q.get_playback_position()
		if at > longest:
			longest = at
			p = q
	p.stream = stream(sound)
	p.volume_db = volume_db
	p.bus = bus
	p.pitch_scale = pitch
	p.play()


## Fire-and-forget positional sound in the current scene. Frees itself when
## done (a looping sound never finishes: free the returned node yourself).
func play_3d(sound: String, pos: Vector3, volume_db: float = 0.0, bus: StringName = &"Cave", pitch: float = 1.0, unit: float = 4.0, max_dist: float = 30.0) -> AudioStreamPlayer3D:
	var parent: Node = get_tree().current_scene
	if parent == null:
		parent = self
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(sound)
	p.volume_db = volume_db
	p.bus = bus
	p.pitch_scale = pitch
	p.unit_size = unit
	p.max_distance = max_dist
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	return p


## The stream for a sound name: a file from res://audio/ if there is one,
## else synthesized (and cached).
func stream(sound: String) -> AudioStream:
	if _cache.has(sound):
		return _cache[sound]
	var s: AudioStream = _load_file(sound)
	if s == null:
		s = _build(sound)
	_cache[sound] = s
	return s


func is_built(sound: String) -> bool:
	return _cache.has(sound)


## Caption for an important sound (only when the player turned captions on).
## The same text is not repeated within `min_gap` seconds.
func caption(text: String, world_position: Vector3, min_gap: float = 3.0) -> void:
	if not Settings.captions:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_caption_times.get(text, -1000.0)) < min_gap:
		return
	_caption_times[text] = now
	Game.caption.emit(text, world_position)


## Muffle all audio (low-pass on Master) while paused.
func set_muffled(on: bool) -> void:
	var idx := AudioServer.get_bus_index("Master")
	if idx < 0:
		return
	var i := _effect_index(idx, "AudioEffectLowPassFilter")
	if i < 0:
		if not on:
			return
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 900.0
		AudioServer.add_bus_effect(idx, lp, 0)
		i = 0
	AudioServer.set_bus_effect_enabled(idx, i, on)


## Glides the Cave bus reverb to a preset ("drop", "tunnel", "hall", "climb", "open").
func set_reverb(preset: String, seconds: float = 2.0) -> void:
	var reverb := _bus_effect("Cave", "AudioEffectReverb") as AudioEffectReverb
	if reverb == null or not REVERB_PRESETS.has(preset):
		return
	var v: Array = REVERB_PRESETS[preset]
	if _reverb_tween:
		_reverb_tween.kill()
	_reverb_tween = create_tween().set_parallel(true)
	_reverb_tween.tween_property(reverb, "room_size", v[0], maxf(seconds, 0.01))
	_reverb_tween.tween_property(reverb, "damping", v[1], maxf(seconds, 0.01))
	_reverb_tween.tween_property(reverb, "wet", v[2], maxf(seconds, 0.01))
	_reverb_tween.tween_property(reverb, "predelay_msec", v[3], maxf(seconds, 0.01))


## Gain of the whole Ambience bus (ducking). Doesn't touch the player's volume setting.
func set_ambience_gain(db: float) -> void:
	if _duck == null:
		_duck = _bus_effect("Ambience", "AudioEffectAmplify") as AudioEffectAmplify
		if _duck == null:
			var idx := AudioServer.get_bus_index("Ambience")
			if idx < 0:
				return
			_duck = AudioEffectAmplify.new()
			AudioServer.add_bus_effect(idx, _duck)
	_duck.volume_db = clampf(db, -80.0, 24.0)


func _effect_index(bus_idx: int, cls: String) -> int:
	if bus_idx < 0:
		return -1
	for i in AudioServer.get_bus_effect_count(bus_idx):
		var e := AudioServer.get_bus_effect(bus_idx, i)
		if e != null and e.is_class(cls):
			return i
	return -1


func _bus_effect(bus_name: String, cls: String) -> AudioEffect:
	var idx := AudioServer.get_bus_index(bus_name)
	var i := _effect_index(idx, cls)
	if i < 0:
		return null
	return AudioServer.get_bus_effect(idx, i)


func _load_file(sound: String) -> AudioStream:
	for ext in EXTENSIONS:
		var path: String = AUDIO_DIR + sound + "." + str(ext)
		if ResourceLoader.exists(path):
			var res := load(path) as AudioStream
			if res != null:
				if sound in LOOPS:
					_set_loop(res)
				return res
	return null


func _set_loop(res: AudioStream) -> void:
	if res is AudioStreamOggVorbis:
		(res as AudioStreamOggVorbis).loop = true
	elif res is AudioStreamMP3:
		(res as AudioStreamMP3).loop = true


func _build(sound: String) -> AudioStream:
	match sound:
		"ping": return _wav(_ping())
		"whisper_ping": return _wav(_sweep(0.6, 1100.0, 500.0, 4.0, 9.0, 0.35, 0.1))
		"ready": return _wav(_sweep(0.07, 2600.0, 2100.0, 40.0, 70.0, 0.2, 0.1))
		"step": return _wav(_step())
		"step_wood": return _wav(_normalize(_step_wood(), 0.55))
		"step_gravel": return _wav(_normalize(_step_gravel(), 0.55))
		"step_water": return _wav(_normalize(_step_water(), 0.55))
		"land": return _wav(_normalize(_thud(0.4, 58.0, 12.0), 0.7))
		"bump": return _wav(_normalize(_thud(0.22, 95.0, 22.0), 0.45))
		"ui_hover": return _wav(_ui_hover())
		"ui_click": return _wav(_ui_click())
		"ui_back": return _wav(_ui_back())
		"heartbeat": return _wav(_heartbeat())
		"heartbeat_slow": return _wav(_normalize(_heartbeat_slow(), 0.7))
		"drone": return _wav(_drone(), true, LOW_RATE)
		"breath": return _wav(_normalize(_breath(), 0.55), true, LOW_RATE)
		"wind": return _wav(_normalize(_wind(), 0.5), true, LOW_RATE)
		"birdsong": return _wav(_normalize(_birdsong(), 0.45), true, BIRD_RATE)
		"tape_hiss": return _wav(_normalize(_tape_hiss(), 0.4), true)
		"shepard": return _wav(_shepard(), true, SHEPARD_RATE)
		"sting": return _wav(_normalize(_sting(), 0.8))
		"hiss": return _wav(_normalize(_hiss(), 0.68))
		"shriek": return _wav(_normalize(_shriek(), 0.72))
		"exhale": return _wav(_normalize(_exhale(), 0.6), false, LOW_RATE)
		"sniff": return _wav(_normalize(_sniff(), 0.5))
		"drag_step": return _wav(_normalize(_drag_step(), 0.72), false, LOW_RATE)
		"whisper_name": return _wav(_normalize(_whisper_name(), 0.5))
		"pant": return _wav(_normalize(_pant(), 0.45))
		"rope_creak": return _wav(_normalize(_rope_creak(), 0.5))
		"rope_snap": return _wav(_normalize(_rope_snap(), 0.75))
		"impact": return _wav(_normalize(_impact(), 0.78))
		"dust": return _wav(_normalize(_dust(), 0.42))
		"chime": return _wav(_normalize(_chime(), 0.55))
		"crystal": return _wav(_normalize(_crystal(), 0.5))
		"pebble": return _wav(_normalize(_pebble(), 0.6))
		"pickup_pebbles": return _wav(_normalize(_pickup_pebbles(), 0.55))
		"click": return _wav(_normalize(_recorder_click(), 0.55))
		"drip": return _wav(_sweep(0.35, 1500.0, 650.0, 18.0, 14.0, 0.5, 0.0))
		"scrape": return _wav(_normalize(_scrape(), 0.6))
		"knock": return _wav(_normalize(_knock(), 0.6))
		"chalk": return _wav(_chalk())
	push_warning("Sfx: unknown sound '%s'" % sound)
	return _wav(PackedFloat32Array([0.0]))


func _wav(s: PackedFloat32Array, loop: bool = false, rate: int = RATE) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


func _buf(seconds: float, rate: int = RATE) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * rate))
	return s


func _noise() -> float:
	return randf() * 2.0 - 1.0


## Scales a sound so its loudest sample is `peak` (keeps the mix predictable).
func _normalize(s: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0
	for v in s:
		m = maxf(m, absf(v))
	if m > 0.0001:
		var k := peak / m
		for i in s.size():
			s[i] *= k
	return s


## Crossfades the last `fade` samples into the start so a noise loop has no click.
func _loopify(s: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var n := s.size() - fade
	var out := s.slice(0, n)
	for i in fade:
		var w := float(i) / fade
		out[i] = s[i] * w + s[n + i] * (1.0 - w)
	return out


## A small Schroeder reverb baked into a sound: 4 damped combs, 2 allpasses.
func _reverb(dry: PackedFloat32Array, tail: float, wet: float, rate: int = RATE) -> PackedFloat32Array:
	var dn := dry.size()
	var n := dn + int(tail * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var l1 := int(0.0297 * rate)
	var l2 := int(0.0371 * rate)
	var l3 := int(0.0411 * rate)
	var l4 := int(0.0437 * rate)
	var la := int(0.0050 * rate)
	var lb := int(0.0017 * rate)
	var c1 := PackedFloat32Array()
	c1.resize(l1)
	var c2 := PackedFloat32Array()
	c2.resize(l2)
	var c3 := PackedFloat32Array()
	c3.resize(l3)
	var c4 := PackedFloat32Array()
	c4.resize(l4)
	var a1 := PackedFloat32Array()
	a1.resize(la)
	var a2 := PackedFloat32Array()
	a2.resize(lb)
	var d1 := 0.0
	var d2 := 0.0
	var d3 := 0.0
	var d4 := 0.0
	var fb := 0.84
	var damp := 0.3
	for i in n:
		var x := 0.0
		if i < dn:
			x = dry[i]
		var y1 := c1[i % l1]
		d1 = y1 * (1.0 - damp) + d1 * damp
		c1[i % l1] = x + d1 * fb
		var y2 := c2[i % l2]
		d2 = y2 * (1.0 - damp) + d2 * damp
		c2[i % l2] = x + d2 * fb
		var y3 := c3[i % l3]
		d3 = y3 * (1.0 - damp) + d3 * damp
		c3[i % l3] = x + d3 * fb
		var y4 := c4[i % l4]
		d4 = y4 * (1.0 - damp) + d4 * damp
		c4[i % l4] = x + d4 * fb
		var sum := (y1 + y2 + y3 + y4) * 0.25
		var ba := a1[i % la]
		var ya := ba - sum
		a1[i % la] = sum + ba * 0.5
		var bb := a2[i % lb]
		var yb := bb - ya
		a2[i % lb] = ya + bb * 0.5
		out[i] = x + yb * wet
	return out


## Pitch sweep with exponential decay plus a noise click: pings, drips, clicks.
func _sweep(sec: float, f0: float, f1: float, sweep: float, decay: float, amp: float, click: float) -> PackedFloat32Array:
	var s := _buf(sec)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := (f0 - f1) * exp(-t * sweep) + f1
		phase += TAU * f / RATE
		var env := exp(-t * decay) * minf(t * 400.0, 1.0)
		s[i] = sin(phase) * env * amp + _noise() * exp(-t * 90.0) * click
	return s


## The hero sound: a bright falling sonar ping with a shimmer and a soft body.
func _ping() -> PackedFloat32Array:
	var s := _sweep(0.9, 2200.0, 700.0, 3.0, 7.0, 0.7, 0.28)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 3000.0 * exp(-t * 3.0) + 1400.0
		phase += TAU * f / RATE
		s[i] += sin(phase) * exp(-t * 11.0) * minf(t * 400.0, 1.0) * 0.08
		s[i] += sin(TAU * 140.0 * t) * exp(-t * 25.0) * minf(t * 300.0, 1.0) * 0.1
	return s


func _step() -> PackedFloat32Array:
	var s := _buf(0.14)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (_noise() - lp) * 0.25
		s[i] = lp * exp(-t * 35.0) * 1.6 + sin(TAU * 90.0 * t) * exp(-t * 40.0) * 0.5
	return s


## Hollow knock of a boot on old planks.
func _step_wood() -> PackedFloat32Array:
	var s := _buf(0.2)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (_noise() - lp) * 0.35
		var body := sin(TAU * 170.0 * t) * exp(-t * 26.0) * 0.55 + sin(TAU * 395.0 * t) * exp(-t * 48.0) * 0.25
		s[i] = (body + lp * exp(-t * 90.0) * 0.9) * minf(t * 800.0, 1.0)
	return s


## Crunchy gravel: a cluster of tiny grains.
func _step_gravel() -> PackedFloat32Array:
	var s := _buf(0.22)
	var grain := 0.0
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var env := exp(-t * 14.0)
		if randf() < 0.012 * env:
			grain = randf_range(0.5, 1.0)
		grain *= 0.992
		var x := _noise()
		lp += (x - lp) * 0.5
		s[i] = (x - lp) * grain * 1.1 + lp * exp(-t * 40.0) * 0.5
	return s


## A foot in shallow water: splash plus a rising bloop.
func _step_water() -> PackedFloat32Array:
	var s := _buf(0.32)
	var lp := 0.0
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var x := _noise()
		lp += (x - lp) * 0.25
		phase += TAU * (280.0 + 900.0 * t) / RATE
		var splash := (x - lp) * exp(-t * 16.0) * 0.55 + lp * exp(-t * 22.0) * 0.6
		var bloop := sin(phase) * exp(-t * 18.0) * minf(t * 200.0, 1.0) * 0.3
		s[i] = splash + bloop
	return s


## A body hitting stone: landing, bumping into a wall.
func _thud(sec: float, freq: float, decay: float) -> PackedFloat32Array:
	var s := _buf(sec)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (_noise() - lp) * 0.08
		var v := sin(TAU * freq * t * (1.0 + 0.6 * exp(-t * 30.0))) * exp(-t * decay)
		s[i] = (v + lp * 2.5 * exp(-t * decay * 1.5)) * minf(t * 500.0, 1.0)
	return s


func _ui_hover() -> PackedFloat32Array:
	var s := _buf(0.06)
	for i in s.size():
		var t := float(i) / RATE
		var env := exp(-t * 70.0) * minf(t * 600.0, 1.0)
		s[i] = (sin(TAU * 1100.0 * t) * 0.16 + sin(TAU * 2200.0 * t) * 0.05) * env
	return s


func _ui_click() -> PackedFloat32Array:
	var s := _buf(0.3)
	for i in s.size():
		var t := float(i) / RATE
		var click := sin(TAU * (500.0 + 500.0 * exp(-t * 60.0)) * t) * exp(-t * 70.0) * 0.4
		var tail := sin(TAU * 1180.0 * t) * exp(-t * 14.0) * minf(t * 300.0, 1.0) * 0.12
		s[i] = click + tail + _noise() * exp(-t * 300.0) * 0.12
	return s


## Two soft falling tones.
func _ui_back() -> PackedFloat32Array:
	var s := _buf(0.24)
	for i in s.size():
		var t := float(i) / RATE
		var f := 760.0
		var u := t
		if t >= 0.08:
			f = 520.0
			u = t - 0.08
		s[i] = sin(TAU * f * t) * exp(-u * 30.0) * minf(u * 500.0, 1.0) * 0.25
	return s


func _thump(t: float, start: float, amp: float) -> float:
	return _thump_at(t, start, amp, 52.0, 16.0)


func _thump_at(t: float, start: float, amp: float, freq: float, decay: float) -> float:
	var u := t - start
	if u < 0.0:
		return 0.0
	return sin(TAU * freq * u) * exp(-u * decay) * minf(u * 300.0, 1.0) * amp


func _heartbeat() -> PackedFloat32Array:
	var s := _buf(0.6)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = (_thump(t, 0.0, 1.0) + _thump(t, 0.2, 0.7)) * 0.8
	return s


## After a near miss: deeper, softer, slower.
func _heartbeat_slow() -> PackedFloat32Array:
	var s := _buf(1.0)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = _thump_at(t, 0.0, 1.0, 44.0, 10.0) + _thump_at(t, 0.3, 0.6, 40.0, 11.0)
	return s


## Low cave drone. Every frequency fits a whole number of cycles in 6 s so it loops cleanly.
func _drone() -> PackedFloat32Array:
	var r := LOW_RATE
	var s := _buf(6.0, r)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / r
		var v := sin(TAU * 41.0 * t) * 0.35 + sin(TAU * 41.5 * t) * 0.3
		v += sin(TAU * 61.5 * t) * 0.12 + sin(TAU * 82.0 * t) * 0.06
		lp += (_noise() - lp) * 0.03
		v += lp * 2.0 * (0.6 + 0.4 * sin(TAU * 0.5 * t))
		s[i] = v * 0.5
	return s


## Slow, wet creature breathing: inhale, pause, growling exhale. Silent at both ends so it loops.
func _breath() -> PackedFloat32Array:
	var r := LOW_RATE
	var s := _buf(3.0, r)
	var lp := 0.0
	var lp2 := 0.0
	for i in s.size():
		var t := float(i) / r
		lp += (_noise() - lp) * 0.12
		lp2 += (lp - lp2) * 0.35
		var env := 0.0
		var growl := 0.0
		if t < 1.2:
			env = sin(PI * t / 1.2) * 0.6
		elif t > 1.5 and t < 2.8:
			env = sin(PI * (t - 1.5) / 1.3)
			growl = sin(TAU * 68.0 * t + sin(TAU * 9.0 * t) * 2.0) * 0.3
		s[i] = (lp2 * 3.0 + growl) * env * 0.8
	return s


## Wind moaning down the exit shaft: resonant noise with slow gusts.
func _wind() -> PackedFloat32Array:
	var r := LOW_RATE
	var s := _buf(8.0, r)
	var low := 0.0
	var band := 0.0
	for i in s.size():
		var t := float(i) / r
		var gust := 0.55 + 0.3 * sin(TAU * 0.13 * t) + 0.15 * sin(TAU * 0.37 * t + 1.3)
		var f := 2.0 * sin(PI * (380.0 + 520.0 * gust) / r)
		low += f * band
		var high := _noise() - low - 0.35 * band
		band += f * high
		s[i] = (band * 0.22 + low * 0.08) * gust
	return _loopify(s, int(0.6 * r))


## Morning birds for the ending: short chirpy phrases over soft air.
func _birdsong() -> PackedFloat32Array:
	var r := BIRD_RATE
	var s := _buf(9.0, r)
	var lp := 0.0
	for i in s.size():
		lp += (_noise() - lp) * 0.05
		s[i] = lp * 0.08
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var t0 := 0.7
	while t0 < 7.6:
		var notes := rng.randi_range(2, 5)
		var base := rng.randf_range(2000.0, 3600.0)
		var amp := rng.randf_range(0.08, 0.2)
		for _n in notes:
			var dur := rng.randf_range(0.05, 0.12)
			var f0 := base * rng.randf_range(0.9, 1.15)
			var glide := rng.randf_range(-1200.0, 1200.0)
			var first := int(t0 * r)
			var count := int(dur * r)
			if first + count >= s.size():
				break
			var phase := 0.0
			for j in count:
				var u := float(j) / count
				phase += TAU * (f0 + glide * u + 180.0 * sin(TAU * 4.0 * u)) / r
				s[first + j] += sin(phase) * sin(PI * u) * amp
			t0 += dur + rng.randf_range(0.03, 0.1)
		t0 += rng.randf_range(0.5, 1.4)
	return _loopify(s, int(0.6 * r))


## Old cassette: hiss, flutter, faint mains hum and the odd crackle.
func _tape_hiss() -> PackedFloat32Array:
	var s := _buf(4.5)
	var lp := 0.0
	var lp2 := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var x := _noise()
		lp += (x - lp) * 0.6
		lp2 += (x - lp2) * 0.02
		var flutter := 1.0 + 0.15 * sin(TAU * 5.5 * t) * sin(TAU * 0.7 * t)
		var v := (x - lp2) * 0.1 * flutter + lp * 0.04 + sin(TAU * 60.0 * t) * 0.012
		if randf() < 0.0004:
			v += _noise() * 0.35
		s[i] = v
	return _loopify(s, int(0.5 * RATE))


## Shepard tone: octave-spaced partials that rise forever under a fixed bell
## curve. Each partial rises exactly one octave per period and `cycles`
## (f_min * period / ln 2) is a whole number, so the loop is seamless.
func _shepard() -> PackedFloat32Array:
	var r := SHEPARD_RATE
	var period := 8.0
	var octaves := 6
	var cycles := 317.0  # f_min ~27.5 Hz
	var s := _buf(period, r)
	var speeds: Array[float] = []
	for k in octaves:
		speeds.append(TAU * cycles * pow(2.0, k))
	var amps: Array[float] = []
	amps.resize(octaves)
	amps.fill(0.0)
	for i in s.size():
		var rise := float(i) / r / period
		if i % 64 == 0:
			for k in octaves:
				amps[k] = 0.5 - 0.5 * cos(TAU * (float(k) + rise) / octaves)
		var u := pow(2.0, rise) - 1.0
		var v := 0.0
		for k in octaves:
			v += sin(speeds[k] * u) * amps[k]
		s[i] = v * 0.17
	return s


## Getting caught: dissonant cluster, noise burst and a low hit.
func _sting() -> PackedFloat32Array:
	var s := _buf(1.4)
	var freqs: Array[float] = [196.0, 207.6, 293.7, 415.3, 587.3]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for f in freqs:
			v += sin(TAU * f * t + sin(TAU * 7.0 * t) * 0.8)
		v = v / 5.0 + _noise() * exp(-t * 6.0) * 0.6 + sin(TAU * 45.0 * t) * exp(-t * 5.0) * 0.8
		s[i] = v * minf(t * 60.0, 1.0) * exp(-t * 2.2)
	return s


## Starts hunting: a sharp intake, then a fluttering rasp over a rising snarl.
func _hiss() -> PackedFloat32Array:
	var s := _buf(1.1)
	var lp := 0.0
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var x := _noise()
		lp += (x - lp) * 0.3
		var intake := 0.0
		if t < 0.12:
			intake = sin(PI * t / 0.12) * 0.45
		var env := intake + smoothstep(0.1, 0.25, t) * exp(-maxf(t - 0.25, 0.0) * 1.6)
		var trem := 0.55 + 0.45 * sin(TAU * (14.0 + 10.0 * t) * t)
		phase += TAU * (85.0 + 70.0 * t) / RATE
		var growl := sin(phase + 1.8 * sin(phase * 0.5)) * 0.35 * minf(t * 4.0, 1.0)
		s[i] = ((x - lp) * trem * 0.75 + growl * trem) * env * (1.0 - smoothstep(0.95, 1.1, t))
	return s


## A sleeping Listener waking up.
func _shriek() -> PackedFloat32Array:
	var s := _buf(1.2)
	var phase := 0.0
	var phase2 := 0.0
	for i in s.size():
		var t := float(i) / RATE
		phase += TAU * (950.0 - 300.0 * t) / RATE
		phase2 += TAU * (1430.0 - 520.0 * t) / RATE
		var v := sin(phase + sin(phase * 1.5) * 2.5) + sin(phase2 + sin(phase2 * 0.7) * 1.5) * 0.35 + _noise() * 0.3
		s[i] = v * minf(t * 30.0, 1.0) * exp(-t * 2.5)
	return s


## Gives up: a long, low, disappointed exhale.
func _exhale() -> PackedFloat32Array:
	var r := LOW_RATE
	var s := _buf(1.8, r)
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	for i in s.size():
		var t := float(i) / r
		lp += (_noise() - lp) * 0.18
		lp2 += (lp - lp2) * 0.3
		var env := smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(0.6, 1.8, t))
		phase += TAU * (62.0 - 18.0 * t) / r
		var growl := sin(phase + sin(phase * 0.5) * 1.2) * 0.4 * (1.0 - smoothstep(0.3, 1.4, t))
		s[i] = (lp2 * 3.0 + growl) * env
	return s


## Searching: three quick wet sniffs.
func _sniff() -> PackedFloat32Array:
	var s := _buf(0.75)
	var lp := 0.0
	var lp2 := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var x := _noise()
		lp += (x - lp) * 0.45
		lp2 += (x - lp2) * 0.06
		var env := 0.0
		for k in 3:
			var u := t - float(k) * 0.19
			if u >= 0.0 and u < 0.12:
				env += sin(PI * u / 0.12) * (0.7 + 0.15 * k)
		s[i] = (lp - lp2) * env
	return s


## A Listener's footstep: a heavy thud, then the foot drags across stone.
func _drag_step() -> PackedFloat32Array:
	var r := LOW_RATE
	var s := _buf(0.6, r)
	var lp := 0.0
	var lp2 := 0.0
	for i in s.size():
		var t := float(i) / r
		var x := _noise()
		lp += (x - lp) * 0.2
		lp2 += (x - lp2) * 0.05
		var thud := sin(TAU * 48.0 * t * (1.0 + 0.5 * exp(-t * 25.0))) * exp(-t * 14.0) * minf(t * 400.0, 1.0)
		var drag := 0.0
		var u := t - 0.07
		if u > 0.0:
			var grit := 0.4 + 0.6 * absf(sin(TAU * 23.0 * u) * sin(TAU * 7.0 * u + 0.6))
			drag = lp * grit * sin(PI * minf(u / 0.48, 1.0)) * 1.2
		s[i] = thud * 0.9 + lp2 * 3.0 * exp(-t * 30.0) + drag
	return s


## "...you..." whispered: formant-filtered breath gliding from "y" to "oo".
func _whisper_name() -> PackedFloat32Array:
	var s := _buf(1.4)
	var l1 := 0.0
	var b1 := 0.0
	var l2 := 0.0
	var b2 := 0.0
	var hp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var glide := smoothstep(0.15, 0.5, t)
		var k1 := 2.0 * sin(PI * lerpf(280.0, 330.0, glide) / RATE)
		var k2 := 2.0 * sin(PI * lerpf(2200.0, 800.0, glide) / RATE)
		var x := _noise()
		l1 += k1 * b1
		var h1 := x - l1 - 0.25 * b1
		b1 += k1 * h1
		l2 += k2 * b2
		var h2 := x - l2 - 0.2 * b2
		b2 += k2 * h2
		hp += (x - hp) * 0.5
		var env := smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.75, 1.35, t))
		var flutter := 0.85 + 0.15 * sin(TAU * 7.0 * t)
		s[i] = (b1 * 0.5 + b2 * 0.6 + (x - hp) * 0.08) * env * flutter
	return s


## The player out of breath: a quick ragged "hih" inhale, then a heavy "haa"
## exhale through an open human mouth (vowel formants, no growl).
func _pant() -> PackedFloat32Array:
	var s := _buf(0.55)
	var l1 := 0.0
	var b1 := 0.0
	var l2 := 0.0
	var b2 := 0.0
	var hp := 0.0
	var rag := 1.0
	for i in s.size():
		var t := float(i) / RATE
		var exhaling := smoothstep(0.17, 0.24, t)
		# Inhale is a tighter, higher "hih"; exhale opens up into "haa".
		var k1 := 2.0 * sin(PI * lerpf(420.0, 760.0, exhaling) / RATE)
		var k2 := 2.0 * sin(PI * lerpf(2000.0, 1250.0, exhaling) / RATE)
		var x := _noise()
		l1 += k1 * b1
		var h1 := x - l1 - 0.3 * b1
		b1 += k1 * h1
		l2 += k2 * b2
		var h2 := x - l2 - 0.3 * b2
		b2 += k2 * h2
		hp += (x - hp) * 0.55
		if i % 160 == 0:
			rag = randf_range(0.7, 1.0)  # ragged, uneven airflow
		var inhale := 0.0
		if t < 0.17:
			inhale = sin(PI * t / 0.17) * 0.45
		var exhale := smoothstep(0.2, 0.26, t) * (1.0 - smoothstep(0.3, 0.55, t))
		s[i] = (b1 * 0.5 + b2 * 0.45 + (x - hp) * 0.12) * (inhale + exhale) * rag
	return s


## A rope under strain: irregular stick-slip pulses ringing a woody resonance.
func _rope_creak() -> PackedFloat32Array:
	var s := _buf(1.3)
	var low := 0.0
	var band := 0.0
	var next_pulse := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var x := 0.0
		if t >= next_pulse:
			x = randf_range(0.6, 1.0)
			# Stick-slip: the pulse rate wanders between ~25 and ~70 per second.
			next_pulse = t + 1.0 / (25.0 + 45.0 * absf(sin(TAU * 0.8 * t + 0.4)) + randf_range(-6.0, 6.0))
		x += _noise() * 0.04
		var f := 2.0 * sin(PI * (380.0 + 160.0 * sin(TAU * 0.6 * t)) / RATE)
		low += f * band
		var high := x - low - 0.12 * band
		band += f * high
		var env := smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(0.85, 1.3, t))
		s[i] = (band * 0.5 + high * 0.05) * env
	return s


## The rope giving way: a sharp crack, a whip-like falling whine, fibres fraying.
func _rope_snap() -> PackedFloat32Array:
	var s := _buf(0.8)
	var lp := 0.0
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var x := _noise()
		lp += (x - lp) * 0.3
		var crack := x * exp(-t * 160.0) * 1.2 + sin(TAU * 220.0 * t) * exp(-t * 40.0) * 0.4
		phase += TAU * (2400.0 * exp(-t * 9.0) + 300.0) / RATE
		var whip := sin(phase) * exp(-t * 7.0) * minf(t * 300.0, 1.0) * 0.25
		var fray := (x - lp) * exp(-t * 6.0) * smoothstep(0.01, 0.05, t) * 0.35 * (0.5 + 0.5 * absf(sin(TAU * 31.0 * t)))
		s[i] = crack + whip + fray
	return s


## A heavy body (and the lantern) hitting stone: deep thud, crack, debris and
## the tinkle of broken lantern glass, with a short baked-in cave tail.
func _impact() -> PackedFloat32Array:
	var s := _buf(1.3)
	var lp := 0.0
	var grain := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var x := _noise()
		lp += (x - lp) * 0.06
		var thud := sin(TAU * 42.0 * t * (1.0 + 0.8 * exp(-t * 20.0))) * exp(-t * 7.0) * minf(t * 600.0, 1.0)
		var crack := x * exp(-t * 70.0) * 0.6 + lp * 3.0 * exp(-t * 10.0)
		var density := exp(-t * 4.0) * smoothstep(0.03, 0.1, t)
		if randf() < 0.004 * density:
			grain = randf_range(0.3, 0.9)
		grain *= 0.99
		var debris := x * grain * 0.35
		var glass := 0.0
		var u := t - 0.12
		if u > 0.0:
			glass = sin(TAU * 3150.0 * u) * exp(-u * 18.0) + sin(TAU * 2480.0 * u) * exp(-u * 12.0) * 0.6
			if u > 0.09:
				glass += sin(TAU * 4720.0 * u + 1.0) * exp(-(u - 0.09) * 22.0)
			glass *= 0.12
		s[i] = thud * 1.1 + crack + debris + glass
	return _reverb(s, 0.9, 0.35)


## Grit trickling down from the ceiling.
func _dust() -> PackedFloat32Array:
	var s := _buf(1.6)
	var lp := 0.0
	var grain := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var density := exp(-t * 2.2) * smoothstep(0.0, 0.08, t)
		if randf() < 0.006 * density:
			grain = randf_range(0.3, 1.0)
		grain *= 0.985
		var x := _noise()
		lp += (x - lp) * 0.08
		s[i] = x * grain * 0.6 + lp * density * 0.9
	return s


## Checkpoint: a warm bell chord with a baked-in reverb tail.
func _chime() -> PackedFloat32Array:
	var s := _buf(1.2)
	var notes: Array[float] = [523.25, 659.25, 783.99, 1046.5]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in notes.size():
			var u := t - float(k) * 0.07
			if u > 0.0:
				var f := notes[k]
				v += (sin(TAU * f * u) + sin(TAU * f * 2.76 * u) * 0.25 * exp(-u * 6.0)) * exp(-u * 2.8) * minf(u * 300.0, 1.0)
		s[i] = v * 0.16 * (1.0 - smoothstep(1.0, 1.2, t))
	return _reverb(s, 1.6, 0.6)


## Echo crystal: a glassy, shimmering arpeggio.
func _crystal() -> PackedFloat32Array:
	var s := _buf(1.0)
	var notes: Array[float] = [1318.5, 1760.0, 2093.0, 2637.0]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in notes.size():
			var u := t - float(k) * 0.05
			if u > 0.0:
				var f := notes[k]
				v += (sin(TAU * f * u) + sin(TAU * f * 1.003 * u)) * exp(-u * 4.0) * minf(u * 400.0, 1.0)
		s[i] = v * 0.1 * (1.0 - smoothstep(0.85, 1.0, t))
	return _reverb(s, 1.2, 0.7)


## A pebble bouncing off stone.
func _pebble() -> PackedFloat32Array:
	var s := _buf(0.16)
	for i in s.size():
		var t := float(i) / RATE
		var v := sin(TAU * 2900.0 * t) * exp(-t * 55.0) * 0.45 + sin(TAU * 4300.0 * t) * exp(-t * 80.0) * 0.25
		v += sin(TAU * 1200.0 * t) * exp(-t * 70.0) * 0.2 + _noise() * exp(-t * 400.0) * 0.5
		s[i] = v
	return s


## Scooping up a handful of stones.
func _pickup_pebbles() -> PackedFloat32Array:
	var s := _buf(0.5)
	var starts: Array[float] = [0.0, 0.07, 0.12, 0.2, 0.27]
	var pitches: Array[float] = [1.0, 0.82, 1.15, 0.9, 1.25]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in starts.size():
			var u := t - starts[k]
			if u >= 0.0:
				var p := pitches[k]
				var clack := sin(TAU * 2600.0 * p * u) * exp(-u * 60.0) * 0.4 + sin(TAU * 900.0 * p * u) * exp(-u * 45.0) * 0.25
				v += (clack + _noise() * exp(-u * 500.0) * 0.4) * (1.0 - 0.12 * k)
		s[i] = v
	return s


## Voice log recorder: two mechanical clicks, then the tape motor spins up.
func _recorder_click() -> PackedFloat32Array:
	var s := _buf(0.55)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var v := sin(TAU * 1150.0 * t) * exp(-t * 90.0) * 0.5 + _noise() * exp(-t * 350.0) * 0.5
		var u := t - 0.09
		if u >= 0.0:
			v += sin(TAU * 700.0 * u) * exp(-u * 70.0) * 0.45 + _noise() * exp(-u * 300.0) * 0.35
		lp += (_noise() - lp) * 0.1
		var whir := (sin(TAU * 118.0 * t + sin(TAU * 6.0 * t) * 0.6) * 0.12 + lp * 0.15)
		s[i] = v + whir * smoothstep(0.12, 0.3, t) * (1.0 - smoothstep(0.38, 0.55, t))
	return s


## Something dragging across stone, somewhere in the dark.
func _scrape() -> PackedFloat32Array:
	var s := _buf(1.2)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var x := _noise()
		lp += (x - lp) * 0.15
		var grit := absf(sin(TAU * 3.0 * t) * sin(TAU * 7.0 * t + 1.0) * sin(TAU * 11.0 * t))
		s[i] = lp * grit * sin(PI * t / 1.2) * 2.5
	return s


func _knock() -> PackedFloat32Array:
	var s := _buf(0.6)
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for start in [0.0, 0.24]:
			var u: float = t - start
			if u >= 0.0:
				v += sin(TAU * 120.0 * u) * exp(-u * 30.0) + _noise() * exp(-u * 120.0) * 0.4
		s[i] = v * 0.7
	return s


func _chalk() -> PackedFloat32Array:
	var s := _buf(0.25)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var x := _noise()
		lp += (x - lp) * 0.5
		s[i] = (x - lp) * (0.5 + 0.5 * sin(TAU * 40.0 * t)) * sin(PI * t / 0.25) * 0.5
	return s
