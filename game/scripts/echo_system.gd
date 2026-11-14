extends Node
## Autoload "Echo": tracks the last 4 pings and feeds them to the reveal shader.
## Anything that makes noise calls Echo.emit_ping(); Listeners connect to ping_emitted.

signal ping_emitted(origin: Vector3, max_radius: float, loud: bool)

const SLOTS := 4
const MAX_AGE := 6.0

var _origins: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _ages: Array[float] = [-1.0, -1.0, -1.0, -1.0]
var _radii: Array[float] = [22.0, 22.0, 22.0, 22.0]
var _next := 0


func emit_ping(origin: Vector3, max_radius: float = 22.0, loud: bool = true) -> void:
	_origins[_next] = origin
	_ages[_next] = 0.0
	_radii[_next] = max_radius
	_next = (_next + 1) % SLOTS
	ping_emitted.emit(origin, max_radius, loud)


func clear() -> void:
	for i in SLOTS:
		_ages[i] = -1.0


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
