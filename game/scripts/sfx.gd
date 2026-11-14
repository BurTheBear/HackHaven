extends Node
## Autoload "Sfx": placeholder sounds synthesized in code, so the game has
## audio with zero files. Each sound is built the first time it's asked for.
## To swap in a recorded or CC0 sound later, set the stream on the player
## instead of calling Sfx.stream().

const RATE := 16000

var _cache := {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


## Fire-and-forget 2D sound.
func play(sound: String, volume_db: float = 0.0, bus: StringName = &"Master", pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer = _players[0]
	for q in _players:
		if not q.playing:
			p = q
			break
	p.stream = stream(sound)
	p.volume_db = volume_db
	p.bus = bus
	p.pitch_scale = pitch
	p.play()


func stream(sound: String) -> AudioStreamWAV:
	if not _cache.has(sound):
		_cache[sound] = _build(sound)
	return _cache[sound]


func _build(sound: String) -> AudioStreamWAV:
	match sound:
		"ping": return _wav(_sweep(0.9, 2200.0, 700.0, 3.0, 7.0, 0.8, 0.3))
		"whisper_ping": return _wav(_sweep(0.6, 1100.0, 500.0, 4.0, 9.0, 0.35, 0.1))
		"step": return _wav(_step())
		"heartbeat": return _wav(_heartbeat())
		"drone": return _wav(_drone(), true, 11025)
		"breath": return _wav(_breath(), true, 11025)
		"sting": return _wav(_sting())
		"hiss": return _wav(_hiss())
		"shriek": return _wav(_shriek())
		"chime": return _wav(_chime())
		"pebble": return _wav(_sweep(0.12, 3400.0, 2600.0, 10.0, 60.0, 0.6, 0.5))
		"drip": return _wav(_sweep(0.35, 1500.0, 650.0, 18.0, 14.0, 0.5, 0.0))
		"scrape": return _wav(_scrape())
		"knock": return _wav(_knock())
		"chalk": return _wav(_chalk())
		"click": return _wav(_sweep(0.08, 900.0, 400.0, 30.0, 70.0, 0.5, 0.6))
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


func _step() -> PackedFloat32Array:
	var s := _buf(0.14)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (_noise() - lp) * 0.25
		s[i] = lp * exp(-t * 35.0) * 1.6 + sin(TAU * 90.0 * t) * exp(-t * 40.0) * 0.5
	return s


func _thump(t: float, start: float, amp: float) -> float:
	var u := t - start
	if u < 0.0:
		return 0.0
	return sin(TAU * 52.0 * u) * exp(-u * 16.0) * minf(u * 300.0, 1.0) * amp


func _heartbeat() -> PackedFloat32Array:
	var s := _buf(0.6)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = _thump(t, 0.0, 1.0) + _thump(t, 0.2, 0.7)
	return s


## Low cave drone. Every frequency fits a whole number of cycles in 6 s so it loops cleanly.
func _drone() -> PackedFloat32Array:
	var r := 11025
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
	var r := 11025
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


## Getting caught: dissonant cluster, noise burst and a low hit.
func _sting() -> PackedFloat32Array:
	var s := _buf(1.4)
	var freqs := [196.0, 207.6, 293.7, 415.3, 587.3]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for f in freqs:
			v += sin(TAU * f * t + sin(TAU * 7.0 * t) * 0.8)
		v = v / 5.0 + _noise() * exp(-t * 6.0) * 0.6 + sin(TAU * 45.0 * t) * exp(-t * 5.0) * 0.8
		s[i] = v * minf(t * 60.0, 1.0) * exp(-t * 2.2)
	return s


## A Listener hearing you: a rasping, fluttering hiss.
func _hiss() -> PackedFloat32Array:
	var s := _buf(0.9)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var x := _noise()
		lp += (x - lp) * 0.3
		var trem := 0.55 + 0.45 * sin(TAU * 14.0 * t)
		s[i] = (x - lp) * sin(PI * t / 0.9) * trem * 0.7
	return s


## A sleeping Listener waking up.
func _shriek() -> PackedFloat32Array:
	var s := _buf(1.2)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		phase += TAU * (950.0 - 300.0 * t) / RATE
		var v := sin(phase + sin(phase * 1.5) * 2.5) + _noise() * 0.3
		s[i] = v * minf(t * 30.0, 1.0) * exp(-t * 2.5) * 0.6
	return s


func _chime() -> PackedFloat32Array:
	var s := _buf(1.5)
	for i in s.size():
		var t := float(i) / RATE
		var v := sin(TAU * 880.0 * t) + sin(TAU * 1318.5 * t) * 0.6 + sin(TAU * 1760.0 * t) * 0.3
		s[i] = v * exp(-t * 2.5) * minf(t * 200.0, 1.0) * 0.35
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
