extends CharacterBody3D
## First-person player: walk / sneak / run, mouse look, ping, whisper ping,
## throw pebbles, drop chalk marks.

const WALK_SPEED := 3.5
const SNEAK_SPEED := 1.6
const RUN_SPEED := 5.5
const ACCEL := 12.0
const MOUSE_SENS := 0.0025
const WHISPER_RADIUS := 6.0
const WHISPER_COOLDOWN := 2.5
const THROW_SPEED := 9.0
const FALL_LIMIT := -3.0
const MAX_MARKS := 6
## How far Listeners hear your footsteps. Sneaking is silent.
const WALK_NOISE := 3.0
const RUN_NOISE := 9.0

@export var pebble_scene: PackedScene

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ping_sound: AudioStreamPlayer = $PingSound
@onready var step_sound: AudioStreamPlayer = $StepSound

var ping_cooldown := 0.0
var whisper_cooldown := 0.0
var shake := 0.0  ## Set every frame by the Director (how close the Listeners are).
var _kick := 0.0  ## Extra shake for a moment (getting caught).
var _step_timer := 0.0
var _marks: Array[Node3D] = []
var _mark_material: StandardMaterial3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	if ping_sound.stream == null:
		ping_sound.stream = Sfx.stream("ping")
	if step_sound.stream == null:
		step_sound.stream = Sfx.stream("step")
	Game.player_caught.connect(_on_caught)


func _unhandled_input(event: InputEvent) -> void:
	if Game.state != Game.State.PLAYING or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion := event as InputEventMouseMotion
	if motion:
		rotate_y(-motion.relative.x * MOUSE_SENS)
		head.rotate_x(-motion.relative.y * MOUSE_SENS)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	elif event.is_action_pressed("ping"):
		try_ping()
	elif event.is_action_pressed("whisper"):
		try_whisper()
	elif event.is_action_pressed("throw"):
		throw_pebble()
	elif event.is_action_pressed("chalk"):
		drop_mark()


func _process(delta: float) -> void:
	_kick = maxf(_kick - delta * 0.15, 0.0)
	var s := shake + _kick
	camera.h_offset = randf_range(-s, s)
	camera.v_offset = randf_range(-s, s)


func _physics_process(delta: float) -> void:
	Echo.set_player_position(global_position)
	# Don't simulate on the title screen or while caught.
	if Game.state != Game.State.PLAYING:
		velocity = Vector3.ZERO
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sneaking := Input.is_action_pressed("sneak")
	var running := Input.is_action_pressed("run") and not sneaking
	var speed := SNEAK_SPEED if sneaking else (RUN_SPEED if running else WALK_SPEED)
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	velocity.x = move_toward(velocity.x, dir.x * speed, ACCEL * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, ACCEL * delta)
	move_and_slide()
	ping_cooldown = maxf(ping_cooldown - delta, 0.0)
	whisper_cooldown = maxf(whisper_cooldown - delta, 0.0)
	var noise := 0.0 if sneaking else (RUN_NOISE if running else WALK_NOISE)
	var interval := 0.6 if sneaking else (0.3 if running else 0.45)
	_footsteps(delta, input.length() > 0.1 and is_on_floor(), noise, interval)
	# Fell into the chasm or out of the level.
	if global_position.y < FALL_LIMIT:
		respawn(Game.checkpoint_position)


func try_ping() -> void:
	if ping_cooldown > 0.0:
		return
	ping_cooldown = Game.ping_cooldown
	Echo.emit_ping(global_position + Vector3.UP, Game.ping_radius, true)
	ping_sound.pitch_scale = randf_range(0.96, 1.04)
	ping_sound.play()


## A small echo nothing can hear. Safe, but it barely shows anything.
func try_whisper() -> void:
	if whisper_cooldown > 0.0:
		return
	whisper_cooldown = WHISPER_COOLDOWN
	Echo.emit_ping(global_position + Vector3.UP * 0.5, WHISPER_RADIUS, false)
	Sfx.play("whisper_ping", -10.0, &"Cave")


func throw_pebble() -> void:
	if pebble_scene == null or not Game.use_pebble():
		return
	var pebble := pebble_scene.instantiate() as RigidBody3D
	get_parent().add_child(pebble)
	var forward := -camera.global_basis.z
	var from := camera.global_position
	var spawn := from + forward * 0.6
	# Facing a wall: spawn in front of it, not inside it.
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, spawn, 1))
	if hit:
		spawn = (hit["position"] as Vector3) - forward * 0.15
	pebble.global_position = spawn
	pebble.linear_velocity = forward * THROW_SPEED + Vector3.UP * 2.0


## Chalk mark on the floor: faint gold, stays after the echo fades. Your own map.
func drop_mark() -> void:
	var from := global_position + Vector3.UP * 0.5
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0, 1))
	if hit.is_empty():
		return
	if _mark_material == null:
		_mark_material = StandardMaterial3D.new()
		_mark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mark_material.albedo_color = Color(0.55, 0.42, 0.12)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.2
	mesh.bottom_radius = 0.2
	mesh.height = 0.02
	var mark := MeshInstance3D.new()
	mark.mesh = mesh
	mark.material_override = _mark_material
	get_parent().add_child(mark)
	mark.global_position = (hit["position"] as Vector3) + Vector3.UP * 0.015
	_marks.append(mark)
	if _marks.size() > MAX_MARKS:
		_marks.pop_front().queue_free()
	Sfx.play("chalk", -8.0)


func respawn(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	ping_cooldown = 0.0


func look_toward(p: Vector3) -> void:
	var to := p - head.global_position
	if to.length() < 0.01:
		return
	rotation.y = atan2(-to.x, -to.z)
	head.rotation.x = clampf(atan2(to.y, Vector2(to.x, to.z).length()), deg_to_rad(-85.0), deg_to_rad(85.0))


## Caught: snap to face the thing that got you.
func _on_caught() -> void:
	_kick = 0.08
	look_toward(Game.catcher_position + Vector3.UP * 1.4)


func _footsteps(delta: float, moving: bool, noise: float, interval: float) -> void:
	if not moving:
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = interval
		Echo.step()
		if noise > 0.0:
			Echo.make_noise(global_position, noise)
		step_sound.volume_db = -16.0 if noise == 0.0 else (-2.0 if noise > WALK_NOISE else -8.0)
		step_sound.pitch_scale = randf_range(0.9, 1.1)
		step_sound.play()
