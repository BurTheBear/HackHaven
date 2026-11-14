extends CharacterBody3D
## Listener: a blind monster that hunts by sound.
## Hears a ping when its ring reaches it (so anything that hears you was also
## outlined by that ping), pauses in Alert, then walks to where the sound came
## from, searches for a while, and goes back to patrolling.
## It moves in straight lines (no navmesh), so keep rooms open.

enum Mode { PATROL, ALERT, INVESTIGATE, SEARCH }

const SOUND_SPEED := 18.0  ## Same as the ping ring speed in the shader.

@export var patrol_offset := Vector3(0, 0, 6)
@export var patrol_speed := 1.5
@export var investigate_speed := 3.2
## Upper limit; a ping is only heard inside its own radius (22 m, pebbles 10 m).
@export var hearing_radius := 22.0
@export var alert_time := 0.75
@export var catch_distance := 1.0
@export var search_time := 4.0
@export var asleep := false
@export var wake_radius := 10.0
@export var hear_lines: Array[AudioStream] = []

@onready var voice: AudioStreamPlayer3D = $Voice

var mode := Mode.PATROL
var _home := Vector3.ZERO
var _to_far := true
var _target := Vector3.ZERO
var _search := 0.0
var _alert := 0.0
var _hear_delay := -1.0
var _heard_origin := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	_home = global_position
	Echo.ping_emitted.connect(_on_ping)
	Game.player_caught.connect(_on_player_caught)


func _on_ping(origin: Vector3, max_radius: float, loud: bool) -> void:
	if not loud:
		return
	var d := global_position.distance_to(origin)
	if asleep and d > wake_radius:
		return
	if d > minf(max_radius, hearing_radius):
		return
	# React when the ring actually reaches us, not instantly.
	_heard_origin = origin
	_hear_delay = d / SOUND_SPEED


func _hear() -> void:
	_target = Vector3(_heard_origin.x, global_position.y, _heard_origin.z)
	asleep = false
	# Already hunting: just retarget (no new pause, or ping spam would freeze it).
	if mode == Mode.ALERT or mode == Mode.INVESTIGATE:
		return
	mode = Mode.ALERT
	_alert = alert_time
	if not hear_lines.is_empty():
		voice.stream = hear_lines.pick_random()
		voice.play()


func _on_player_caught() -> void:
	mode = Mode.PATROL
	_hear_delay = -1.0


func _physics_process(delta: float) -> void:
	if _hear_delay >= 0.0:
		_hear_delay -= delta
		if _hear_delay < 0.0:
			_hear()
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var dest := global_position
	var speed := 0.0
	match mode:
		Mode.PATROL:
			if not asleep:
				dest = _home + patrol_offset if _to_far else _home
				speed = patrol_speed
				if _flat_dist(dest) < 0.5:
					_to_far = not _to_far
		Mode.ALERT:
			_face(_target)
			_alert -= delta
			if _alert <= 0.0:
				mode = Mode.INVESTIGATE
		Mode.INVESTIGATE:
			dest = _target
			speed = investigate_speed
			if _flat_dist(dest) < 0.8:
				mode = Mode.SEARCH
				_search = search_time
		Mode.SEARCH:
			_search -= delta
			rotate_y(delta * 1.5)
			if _search <= 0.0:
				mode = Mode.PATROL
	var to := dest - global_position
	to.y = 0.0
	var move := Vector3.ZERO
	if to.length() > 0.1:
		move = to.normalized() * speed
		_face(dest)
	velocity.x = move.x
	velocity.z = move.z
	move_and_slide()
	_check_catch()


func _face(p: Vector3) -> void:
	var to := p - global_position
	to.y = 0.0
	if to.length() > 0.1:
		look_at(global_position + to, Vector3.UP)


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func _check_catch() -> void:
	if Game.state != Game.State.PLAYING:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var close := _flat_dist(player.global_position) < catch_distance + 0.4
	if close and absf(player.global_position.y - global_position.y) < 2.0:
		Game.catch_player()
