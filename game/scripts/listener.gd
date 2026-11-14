extends CharacterBody3D
## Listener: a blind monster that hunts by sound.
## Hears a ping when its ring reaches it, and footsteps inside their (small)
## noise radius. Pauses in Alert, walks to where the sound came from, searches,
## then patrols again. Patrols stop now and then to listen. It moves in
## straight lines (no navmesh) and gives up if a wall blocks it.

enum Mode { PATROL, LISTEN, ALERT, INVESTIGATE, SEARCH, WANDER }

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
@onready var breath: AudioStreamPlayer3D = $Breath

var mode := Mode.PATROL
var _home := Vector3.ZERO
var _to_far := true
var _target := Vector3.ZERO
var _search := 0.0
var _alert := 0.0
var _listen_timer := 8.0
var _hear_delay := -1.0
var _heard_origin := Vector3.ZERO
var _deaf := 0.0
var _stuck := 0.0
var _jitter := 1.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	_home = global_position
	# Unpredictable: every Listener moves a little differently.
	_jitter = randf_range(0.85, 1.15)
	_listen_timer = randf_range(5.0, 11.0)
	Echo.ping_emitted.connect(_on_ping)
	Echo.noise_made.connect(_on_noise)
	Game.player_caught.connect(_on_player_caught)
	breath.stream = Sfx.stream("breath")
	breath.pitch_scale = randf_range(0.8, 1.05)
	breath.unit_size = 3.0
	breath.max_distance = 22.0
	breath.bus = &"Cave"
	breath.play()
	voice.max_distance = 30.0
	voice.unit_size = 4.0


func is_hunting() -> bool:
	return mode == Mode.ALERT or mode == Mode.INVESTIGATE


func _on_ping(origin: Vector3, max_radius: float, loud: bool) -> void:
	if not loud or _deaf > 0.0:
		return
	var d := global_position.distance_to(origin)
	if asleep and d > wake_radius:
		return
	if d > minf(max_radius, hearing_radius):
		return
	# React when the sound actually reaches us, not instantly.
	_heard_origin = origin
	_hear_delay = d / SOUND_SPEED


func _on_noise(origin: Vector3, radius: float) -> void:
	_on_ping(origin, radius, true)


func _hear() -> void:
	_target = Vector3(_heard_origin.x, global_position.y, _heard_origin.z)
	var was_asleep := asleep
	asleep = false
	# Already hunting: just retarget (no new pause, or ping spam would freeze it).
	if is_hunting():
		return
	mode = Mode.ALERT
	_alert = alert_time * (1.8 if was_asleep else 1.0)
	if not hear_lines.is_empty():
		voice.stream = hear_lines.pick_random()
	else:
		voice.stream = Sfx.stream("shriek" if was_asleep else "hiss")
	voice.pitch_scale = randf_range(0.8, 1.0)
	voice.play()


## Director hint: wander toward the player's rough area (not their exact spot).
func wander_to(p: Vector3) -> bool:
	if asleep or mode != Mode.PATROL:
		return false
	_target = Vector3(p.x, global_position.y, p.z)
	mode = Mode.WANDER
	return true


## Director release: back off and go deaf for a moment.
func retreat() -> void:
	if asleep:
		return
	mode = Mode.PATROL
	_hear_delay = -1.0
	_deaf = 4.0


func _on_player_caught() -> void:
	mode = Mode.PATROL
	_hear_delay = -1.0
	_deaf = 2.0


func _physics_process(delta: float) -> void:
	_deaf = maxf(_deaf - delta, 0.0)
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
				speed = patrol_speed * _jitter
				if _flat_dist(dest) < 0.5:
					_to_far = not _to_far
				_listen_timer -= delta
				if _listen_timer <= 0.0 and patrol_offset != Vector3.ZERO:
					mode = Mode.LISTEN
					_search = randf_range(1.2, 2.6)
		Mode.LISTEN:
			# Stops dead and turns its head. Hold your breath.
			_search -= delta
			rotate_y(sin(Time.get_ticks_msec() * 0.003) * delta * 1.5)
			if _search <= 0.0:
				mode = Mode.PATROL
				_listen_timer = randf_range(5.0, 12.0)
		Mode.ALERT:
			_face(_target)
			_alert -= delta
			if _alert <= 0.0:
				mode = Mode.INVESTIGATE
		Mode.INVESTIGATE:
			dest = _target
			speed = investigate_speed * _jitter
			if _flat_dist(dest) < 0.8:
				mode = Mode.SEARCH
				_search = search_time * randf_range(0.75, 1.5)
		Mode.WANDER:
			dest = _target
			speed = patrol_speed * 1.3 * _jitter
			if _flat_dist(dest) < 1.0:
				mode = Mode.SEARCH
				_search = 2.5
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
	_check_stuck(delta, speed)
	breath.volume_db = 0.0 if is_hunting() else (-10.0 if asleep else -4.0)
	_check_catch()


## Straight-line movement: if a wall blocks it, give up and search.
func _check_stuck(delta: float, speed: float) -> void:
	if speed > 0.0 and get_real_velocity().length() < 0.2:
		_stuck += delta
		if _stuck > 1.5:
			_stuck = 0.0
			if mode == Mode.PATROL:
				_to_far = not _to_far
			else:
				mode = Mode.SEARCH
				_search = 2.0
	else:
		_stuck = 0.0


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
		Game.catch_player(global_position)
