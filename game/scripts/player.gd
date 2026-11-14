extends CharacterBody3D
## First-person player: walk, mouse look, ping, throw pebbles.

const SPEED := 3.5
const ACCEL := 12.0
const MOUSE_SENS := 0.0025
const PING_COOLDOWN := 1.0
const PING_RADIUS := 22.0
const THROW_SPEED := 9.0
const FALL_LIMIT := -20.0

@export var pebble_scene: PackedScene

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ping_sound: AudioStreamPlayer = $PingSound
@onready var step_sound: AudioStreamPlayer = $StepSound

var ping_cooldown := 0.0
var _step_timer := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


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
	elif event.is_action_pressed("throw"):
		throw_pebble()


func _physics_process(delta: float) -> void:
	Echo.set_player_position(global_position)
	# Don't simulate on the title screen or while caught: the player used to
	# fall and slide around before the game even started.
	if Game.state != Game.State.PLAYING:
		velocity = Vector3.ZERO
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	velocity.x = move_toward(velocity.x, dir.x * SPEED, ACCEL * delta)
	velocity.z = move_toward(velocity.z, dir.z * SPEED, ACCEL * delta)
	move_and_slide()
	ping_cooldown = maxf(ping_cooldown - delta, 0.0)
	_footsteps(delta, input.length() > 0.1 and is_on_floor())
	# Safety net: fell out of the level.
	if global_position.y < FALL_LIMIT:
		respawn(Game.checkpoint_position)


func try_ping() -> void:
	if ping_cooldown > 0.0:
		return
	ping_cooldown = PING_COOLDOWN
	Echo.emit_ping(global_position + Vector3.UP, PING_RADIUS, true)
	if ping_sound.stream:
		ping_sound.play()


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


func respawn(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO


func _footsteps(delta: float, moving: bool) -> void:
	if not moving:
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = 0.45
		Echo.step()
		if step_sound.stream:
			step_sound.play()
