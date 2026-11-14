extends Node
## Autoload "Echo": tracks live pings and feeds them to the reveal shader.
## Anything that makes noise calls Echo.emit_ping(); Listeners connect to ping_emitted.
## Slots 0-3 are for the player's pings, 4-7 for pebble pings, so a pebble
## never wipes out the player's ping mid-afterglow.

signal ping_emitted(origin: Vector3, max_radius: float, loud: bool)

const GROUP_SIZE := 4
const SLOTS := 8
## Ring reaches 22 m in ~1.2 s, then 2 s of afterglow.
const MAX_AGE := 3.5
const STEP_FADE := 0.5

var _origins: Array[Vector3] = []
var _ages: Array[float] = []
var _radii: Array[float] = []
var _step_glow := 0.0


func _ready() -> void:
	_origins.resize(SLOTS)
	_origins.fill(Vector3.ZERO)
	_ages.resize(SLOTS)
	_ages.fill(-1.0)
	_radii.resize(SLOTS)
	_radii.fill(22.0)


func emit_ping(origin: Vector3, max_radius: float = 22.0, loud: bool = true, is_pebble: bool = false) -> void:
	var first := GROUP_SIZE if is_pebble else 0
	var slot := first
	var oldest := -1.0
	for i in range(first, first + GROUP_SIZE):
		if _ages[i] < 0.0:
			slot = i
			break
		if _ages[i] > oldest:
			oldest = _ages[i]
			slot = i
	_origins[slot] = origin
	_ages[slot] = 0.0
	_radii[slot] = max_radius
	ping_emitted.emit(origin, max_radius, loud)


## Called on every footstep: briefly lights the floor around the player.
func step() -> void:
	_step_glow = 1.0


func clear() -> void:
	for i in SLOTS:
		_ages[i] = -1.0
	_step_glow = 0.0


func set_player_position(p: Vector3) -> void:
	RenderingServer.global_shader_parameter_set("player_pos", p)


func _process(delta: float) -> void:
	for i in SLOTS:
		if _ages[i] >= 0.0:
			_ages[i] += delta
			if _ages[i] > MAX_AGE:
				_ages[i] = -1.0
		var o := _origins[i]
		RenderingServer.global_shader_parameter_set("ping_%d" % i, Vector4(o.x, o.y, o.z, _ages[i]))
		RenderingServer.global_shader_parameter_set("ping_radius_%d" % i, _radii[i])
	_step_glow = maxf(_step_glow - delta / STEP_FADE, 0.0)
	RenderingServer.global_shader_parameter_set("step_glow", _step_glow)
