extends CharacterBody3D
## Listener: a blind monster that hunts by sound.
## Patrols between its start point and start + patrol_offset, walks to any loud
## ping within hearing_radius, searches for a while, then goes back to patrolling.
## It moves in straight lines (no navmesh), so keep rooms open.

enum Mode { PATROL, INVESTIGATE, SEARCH }

@export var patrol_offset := Vector3(0, 0, 6)
@export var patrol_speed := 1.5
@export var investigate_speed := 3.2
@export var hearing_radius := 25.0
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
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	_home = global_position
	Echo.ping_emitted.connect(_on_ping)


func _on_ping(origin: Vector3, _max_radius: float, loud: bool) -> void:
	if not loud:
		return
	var d := global_position.distance_to(origin)
	if asleep:
		if d > wake_radius:
			return
		asleep = false
	if d > hearing_radius:
		return
	mode = Mode.INVESTIGATE
	_target = Vector3(origin.x, global_position.y, origin.z)
	if not hear_lines.is_empty():
		voice.stream = hear_lines.pick_random()
		voice.play()


func _physics_process(delta: float) -> void:
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
		look_at(global_position + to, Vector3.UP)
	velocity.x = move.x
	velocity.z = move.z
	move_and_slide()
	_check_catch()


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
