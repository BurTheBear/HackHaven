extends Node
## Autoload "Echo": tracks live pings and feeds them to the reveal shader.
## Anything that makes noise calls Echo.emit_ping(); Listeners connect to ping_emitted.
## Slots 0-3 are for the player's pings, 4-7 for pebble pings, so a pebble
## never wipes out the player's ping mid-afterglow.

signal ping_emitted(origin: Vector3, max_radius: float, loud: bool)
## A sound with no echo (footsteps): Listeners inside radius hear it, nothing lights up.
signal noise_made(origin: Vector3, radius: float)

## A pebble pinged: `origin` is where it landed, `thrower` where it was thrown from.
signal pebble_lure(origin: Vector3, thrower: Vector3)

const GROUP_SIZE := 4
const SLOTS := 8
## The ring reaches 22 m in ~1.2 s, then 2 s of afterglow (longer on landmarks
## and water). A slot then stays alive up to 15 s so the shader can draw the
## very faint "echo memory" trace. A new ping still takes a free slot first,
## else the oldest one in its own group.
const MAX_AGE := 15.0
const STEP_FADE := 0.5

var _origins: Array[Vector3] = []
var _ages: Array[float] = []
var _radii: Array[float] = []
var _step_glow := 0.0
var _since_player_ping := 99.0
var _player_ping_radius := 22.0
## Pebble lures that fooled a Listener this run (Listeners start to adapt after 3).
var lures_fooled := 0
var adapt_announced := false


## Fill every slot with "empty" values (age -1 means the slot is free).
func _ready() -> void:
	_origins.resize(SLOTS)
	_origins.fill(Vector3.ZERO)
	_ages.resize(SLOTS)
	_ages.fill(-1.0)
	_radii.resize(SLOTS)
	_radii.fill(22.0)


## Starts a new echo ring at `origin` and tells everyone who listens for sounds.
func emit_ping(origin: Vector3, max_radius: float = 22.0, loud: bool = true, is_pebble: bool = false) -> void:
	# Player pings use slots 0-3, pebble pings use slots 4-7.
	var first := 0
	if is_pebble:
		first = GROUP_SIZE
	var last := first + GROUP_SIZE

	# Take the first free slot; if none is free, reuse the oldest one.
	var slot := first
	var oldest := -1.0
	for i in range(first, last):
		if _ages[i] < 0.0:
			slot = i
			break
		if _ages[i] > oldest:
			oldest = _ages[i]
			slot = i

	_origins[slot] = origin
	_ages[slot] = 0.0
	_radii[slot] = max_radius
	if not is_pebble:
		_since_player_ping = 0.0
		_player_ping_radius = max_radius
	ping_emitted.emit(origin, max_radius, loud)


## Challenge mode picked on the menu ("", "no_ping", "one_pebble", "darkness").
func challenge() -> String:
	var c: Variant = Game.get("challenge")
	if c == null:
		return ""
	return str(c)


## Called on every footstep: briefly lights the floor around the player.
func step() -> void:
	if challenge() == "darkness":
		return
	_step_glow = 1.0


## A sound with no light (footsteps, gasps, hits): only Listeners hear it.
func make_noise(origin: Vector3, radius: float) -> void:
	noise_made.emit(origin, radius)


## Removes every ping (used on respawn / restart).
func clear() -> void:
	for i in SLOTS:
		_ages[i] = -1.0
	_step_glow = 0.0
	_since_player_ping = 99.0


## Tells the shaders where the player is.
func set_player_position(p: Vector3) -> void:
	RenderingServer.global_shader_parameter_set("player_pos", p)


## Seconds since the player's last ping or whisper (dust motes, UI).
func time_since_player_ping() -> float:
	return _since_player_ping


## Radius of the player's last ping (6 for a whisper).
func last_player_ping_radius() -> float:
	return _player_ping_radius


## Every frame: age the pings and send all of them to the reveal shader.
func _process(delta: float) -> void:
	for i in SLOTS:
		# Age the ping in this slot; free the slot once it is too old.
		if _ages[i] >= 0.0:
			_ages[i] += delta
			if _ages[i] > MAX_AGE:
				_ages[i] = -1.0
		var origin := _origins[i]
		var ping_value := Vector4(origin.x, origin.y, origin.z, _ages[i])
		RenderingServer.global_shader_parameter_set("ping_" + str(i), ping_value)
		RenderingServer.global_shader_parameter_set("ping_radius_" + str(i), _radii[i])

	# The footstep glow fades out over STEP_FADE seconds.
	_step_glow = _step_glow - delta / STEP_FADE
	if _step_glow < 0.0:
		_step_glow = 0.0
	_since_player_ping += delta
	RenderingServer.global_shader_parameter_set("step_glow", _step_glow)

	# Assist: always-on floor outline near the player (0 = off).
	var hint := 0.0
	if challenge() != "darkness":
		hint = clampf(float(Settings.hint_glow), 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("hint_glow", hint)
