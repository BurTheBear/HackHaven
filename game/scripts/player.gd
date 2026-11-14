extends CharacterBody3D
## First-person player: walk / sneak / run (with stamina), mouse and controller
## look, ping, whisper ping, pebbles (hold to aim, release to throw), stealth
## and optional dagger combat.
## Camera feel: sneak crouch, opt-in head bob, landing dip, wall bumps, a
## little extra FOV at a sprint and a slow roll when the dread is high.

const WALK_SPEED := 3.5
const SNEAK_SPEED := 1.6
const RUN_SPEED := 5.5
const ACCEL := 22.0  ## Ground acceleration: a snappy start.
const DECEL := 13.0  ## Ground braking with no input: a short slide on stop.
const AIR_ACCEL := 3.0
const MOUSE_SENS := 0.0025
const PAD_LOOK_SPEED := 2.6  ## Radians per second at full stick.
const PAD_LOOK_CURVE := 2.0  ## Stick response curve: fine aim near the centre.
const PAD_PITCH_RATIO := 0.75
const PITCH_LIMIT := 85.0
const WHISPER_RADIUS := 6.0
const WHISPER_COOLDOWN := 2.5
const PING_BUFFER := 0.25  ## A ping pressed this close to the end of the cooldown fires when it ends.
const THROW_SPEED := 9.0
const THROW_LIFT := 2.0
const AIM_SHOW_DELAY := 0.12  ## Hold throw this long to see the arc. A quick tap just throws.
const ARC_DOTS := 30
const ARC_SUBSTEPS := 3  ## Physics steps between two arc dots.
const FALL_LIMIT := -3.0
## How far Listeners hear your footsteps. Sneaking is silent.
const WALK_NOISE := 3.0
const RUN_NOISE := 9.0
## Stamina: seconds of full sprint, and seconds to refill from empty.
const STAMINA_TIME := 4.0
const STAMINA_REFILL := 5.0
const STAMINA_REGEN_DELAY := 0.7
const WINDED_RECOVER := 0.35  ## Out of breath (walk only) until stamina is back to this.
## Camera feel.
const SNEAK_DROP := 0.42  ## How much lower the head sits while sneaking.
const SNEAK_DIP := 0.8  ## Extra spring dip when you start sneaking.
const BOB_RATE := 2.2  ## Bob phase per metre walked.
const BOB_HEIGHT := 0.035
const BOB_SWAY := 0.025
const RUN_FOV := 7.0
const ROLL_MAX := 0.045  ## Radians of camera roll at very high shake.
const SHAKE_REDUCED := 0.15  ## Shake multiplier with Settings.reduce_shake.
const DIP_STIFF := 140.0
const DIP_DAMP := 18.0
const JUMP_VELOCITY := 3.3  ## ~0.55 m apex with the default gravity.
const JUMP_COOLDOWN := 0.6
const JUMP_NOISE := 5.0  ## Landing from a jump (silent while sneaking).
const LAND_MIN_SPEED := 4.0  ## Falls slower than this (small steps) make no thud.
const WALL_DRAG := 0.45  ## Up to this much slower while scraping along a wall.
const BUMP_SPEED := 2.0
const BUMP_COOLDOWN := 0.8
const SURFACES := ["wood", "gravel", "water"]
const ARC_COLOR := Color(1.0, 0.8, 0.32, 0.85)
## Holding your breath: seconds it lasts, seconds to refill, and the gasp when it runs out.
const BREATH_TIME := 6.0
const BREATH_REGEN := 4.0
const GASP_NOISE := 8.0
## Noisy floors (area group "noise_floor", meta "noise"): footstep radius and sound.
const FLOOR_NOISE := 6.0
## Combat (damage mode only, with a dagger).
const ATTACK_COOLDOWN := 1.0
const ATTACK_RANGE := 1.8  ## From the player to the Listener's body surface.
const ATTACK_CONE := 0.6  ## Cosine of the half-angle in front that a swing covers (~53 deg).
const ATTACK_NOISE := 4.0
const LISTENER_RADIUS := 0.5
const VIEWMODEL_REST := Vector3(0.24, -0.22, -0.42)
const DaggerModel := preload("res://scripts/combat_dagger_model.gd")
const VIEWMODEL_REST_ROT := Vector3(10.0, 12.0, -8.0)

@export var pebble_scene: PackedScene

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ping_sound: AudioStreamPlayer = $PingSound
@onready var step_sound: AudioStreamPlayer = $StepSound

# --- Read by the UI / other systems ---
var ping_cooldown := 0.0
var whisper_cooldown := 0.0
var is_sneaking := false
var is_running := false
var noise_radius := 0.0  ## How far Listeners can hear your footsteps right now (0 = silent).
var stamina := 1.0  ## 0 – 1.
var is_winded := false  ## Out of stamina: forced to walk until it refills a bit.
var shake := 0.0  ## Set every frame by the Director (how close the Listeners are).
var breath := 1.0  ## 0 - 1: how much held breath is left (HUD).
var holding_breath := false  ## Silent while true (footsteps and floors make no noise).
var is_hiding := false  ## Inside a hiding spot (group "hiding_spot"): can't move.
var attack_cooldown := 0.0  ## Seconds until the dagger can swing again (HUD).
var hide_exposed := false  ## Hiding but found / noisy: Listeners can catch you again.

var _kick := 0.0  ## Extra shake for a moment (getting caught).
var _step_timer := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _pebble_damp: float = ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.1)
# Input state.
var _last_frame := 0
var _act_blocked := true
var _sneak_on := false
var _run_on := false
var _run_moved := false
var _run_idle := 0.0
var _ping_buffered := false
var _aiming := false
var _aim_time := 0.0
var _arc_root: Node3D
var _arc_dots: Array[MeshInstance3D] = []
# Movement state.
var _was_on_floor := true
var _fall_speed := 0.0
var _jump_cooldown := 0.0
var _jumped := false
var _wall_slow := 1.0
var _bump_cooldown := 0.0
var _regen_delay := 0.0
var _breath_timer := 0.0
var _breath_locked := false
var _hide_return := Vector3.ZERO
var _hide_hinted := false
var _floor_kind := ""
# Camera state.
var _stand_height := 1.6
var _head_h := 1.6
var _dip := 0.0
var _dip_vel := 0.0
var _nudge := 0.0
var _bob_phase := 0.0
var _bob_amount := 0.0
var _roll_time := 0.0
var _viewmodel: Node3D
var _swing_tween: Tween
var _look_pending := Vector2.ZERO


## Sets up sounds, the throw arc, the dagger, and listens for game events.
func _ready() -> void:
	if ping_sound.stream == null:
		ping_sound.stream = Sfx.stream("ping")
	if step_sound.stream == null:
		step_sound.stream = Sfx.stream("step")
	_stand_height = head.position.y
	_head_h = _stand_height
	_build_arc()
	_build_viewmodel()
	Game.player_caught.connect(_on_caught)
	Game.player_damaged.connect(_on_damaged)
	Settings.changed.connect(_apply_settings)
	_apply_settings()


## Settings apply live (also while paused, so the FOV slider previews).
func _apply_settings() -> void:
	var fov: float = Settings.fov
	camera.fov = fov
	if not Settings.toggle_sneak:
		_sneak_on = false
	if not Settings.toggle_run:
		_run_on = false


## Mouse look.
func _unhandled_input(event: InputEvent) -> void:
	if Game.state != Game.State.PLAYING or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	var sens: float = MOUSE_SENS * Settings.mouse_sensitivity
	var dy: float = motion.relative.y * sens
	if Settings.invert_y:
		dy = -dy
	var dx: float = motion.relative.x * sens
	if float(Settings.mouse_smoothing) > 0.0:
		# Save it up; _apply_smoothed_look() eases it in over a few frames.
		_look_pending += Vector2(-dx, -dy)
		return
	rotate_y(-dx)
	_pitch(-dy)


## Settings.mouse_smoothing: eases the queued mouse look in over a few frames.
func _apply_smoothed_look(delta: float) -> void:
	if _look_pending == Vector2.ZERO:
		return
	var smooth := clampf(float(Settings.mouse_smoothing), 0.0, 1.0)
	# How much of the saved-up look to use this frame (more smoothing = less).
	var k := 1.0
	if smooth > 0.0:
		var speed := lerpf(60.0, 8.0, smooth)
		k = 1.0 - exp(-speed * delta)
	var step := _look_pending * k
	_look_pending -= step
	if _look_pending.length() < 0.00001:
		step += _look_pending
		_look_pending = Vector2.ZERO
	rotate_y(step.x)
	_pitch(step.y)


## Every frame: controller look, smoothed mouse look and the camera feel.
func _process(delta: float) -> void:
	if Game.state == Game.State.PLAYING and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_controller_look(delta)
		_apply_smoothed_look(delta)
	else:
		_look_pending = Vector2.ZERO
	_update_camera(delta)


## Every physics step: input, movement, noise, footsteps and actions.
func _physics_process(delta: float) -> void:
	Echo.set_player_position(global_position)
	# A gap in physics frames means the tree was paused.
	var frame := Engine.get_physics_frames()
	var resumed := frame - _last_frame > 1
	_last_frame = frame
	# Don't simulate on the title screen or while caught.
	if Game.state != Game.State.PLAYING:
		_stop_while_not_playing()
		return
	# Swallow presses on the first tick after starting / resuming, so the
	# click that locked the mouse doesn't also ping.
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var can_act := captured and not resumed and not _act_blocked
	_act_blocked = not captured
	if not can_act:
		_cancel_aim()
		_ping_buffered = false

	_enforce_one_pebble()
	_update_breath(can_act, delta)
	_update_hiding(can_act)
	if is_hiding:
		velocity = Vector3.ZERO
		is_running = false
		noise_radius = 0.0
		_floor_kind = ""
		_footsteps(delta, false)
		_actions(delta, can_act)
		return

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var has_input := input.length() > 0.1
	_update_modes(can_act, has_input, delta)
	_jump_cooldown = maxf(_jump_cooldown - delta, 0.0)
	if can_act and _jump_cooldown <= 0.0 and is_on_floor() and Input.is_action_just_pressed("jump"):
		_jump()
	_move(input, has_input, delta)
	var moving := has_input and is_on_floor()
	var sprinting := is_running and moving
	_update_stamina(delta, sprinting, has_input)
	_update_noise_radius(moving)
	_footsteps(delta, moving)
	_actions(delta, can_act)
	# Fell into the chasm or out of the level.
	if global_position.y < FALL_LIMIT:
		Game.player_fell.emit()
		respawn(Game.checkpoint_position, Game.checkpoint_yaw)


## On the title screen or while caught: stand still and drop any action.
func _stop_while_not_playing() -> void:
	velocity = Vector3.ZERO
	_act_blocked = true
	_cancel_aim()
	_ping_buffered = false
	is_running = false
	holding_breath = false
	noise_radius = 0.0


## Challenge "one_pebble": you can never carry more than one pebble.
func _enforce_one_pebble() -> void:
	if Echo.challenge() != "one_pebble":
		return
	if Game.max_pebbles == 1 and Game.pebbles <= 1:
		return
	Game.max_pebbles = 1
	Game.pebbles = mini(Game.pebbles, 1)
	Game.pebbles_changed.emit(Game.pebbles)


## How far Listeners can hear your footsteps right now.
func _update_noise_radius(moving: bool) -> void:
	if not moving or is_sneaking or holding_breath:
		noise_radius = 0.0
	elif is_running:
		noise_radius = RUN_NOISE
	else:
		noise_radius = WALK_NOISE

	# Noisy floors (puddles, bones, planks): loud under a walk, half as loud
	# when sneaking.
	_floor_kind = ""
	if moving and not holding_breath:
		_floor_kind = _noise_floor_kind()
		if _floor_kind != "":
			var floor_noise := FLOOR_NOISE
			if is_sneaking:
				floor_noise = FLOOR_NOISE * 0.5
			if floor_noise > noise_radius:
				noise_radius = floor_noise


# ---------------------------------------------------------------- Look

## Tilts the head up or down, never past PITCH_LIMIT.
func _pitch(amount: float) -> void:
	var limit := deg_to_rad(PITCH_LIMIT)
	head.rotation.x = clampf(head.rotation.x + amount, -limit, limit)


## Right stick, with a response curve so small tilts give fine aim.
func _controller_look(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var mag := look.length()
	if mag < 0.001:
		return
	var direction := look / mag
	var strength := pow(minf(mag, 1.0), PAD_LOOK_CURVE)
	var curved := direction * strength
	var speed: float = PAD_LOOK_SPEED * Settings.controller_look_speed
	rotate_y(-curved.x * speed * delta)
	var dy := curved.y * speed * PAD_PITCH_RATIO * delta
	if Settings.invert_y:
		dy = -dy
	_pitch(-dy)


## Turns the body and head to face point p.
func look_toward(p: Vector3) -> void:
	var to := p - head.global_position
	if to.length() < 0.01:
		return
	rotation.y = atan2(-to.x, -to.z)
	var flat_length := Vector2(to.x, to.z).length()
	var pitch := atan2(to.y, flat_length)
	var limit := deg_to_rad(PITCH_LIMIT)
	head.rotation.x = clampf(pitch, -limit, limit)


# ---------------------------------------------------------------- Movement

## Sneak / run, as hold or toggle (Settings), plus stamina limits.
func _update_modes(can_act: bool, has_input: bool, delta: float) -> void:
	var was_sneaking := is_sneaking
	if Settings.toggle_sneak:
		if can_act and Input.is_action_just_pressed("sneak"):
			_sneak_on = not _sneak_on
			if _sneak_on:
				_run_on = false
	else:
		_sneak_on = Input.is_action_pressed("sneak")
	if Settings.toggle_run:
		if can_act and Input.is_action_just_pressed("run"):
			_run_on = not _run_on
			_run_moved = false
			_run_idle = 0.0
			if _run_on and Settings.toggle_sneak:
				_sneak_on = false
		# A toggled sprint ends when you stop moving.
		if has_input:
			_run_moved = true
			_run_idle = 0.0
		elif _run_on and _run_moved:
			_run_idle += delta
			if _run_idle > 0.3:
				_run_on = false
	else:
		_run_on = Input.is_action_pressed("run")
	is_sneaking = _sneak_on
	# Running needs: run on, not sneaking, moving, not out of breath,
	# on the floor and not holding your breath.
	is_running = false
	if _run_on and not is_sneaking and has_input:
		if not is_winded and is_on_floor() and not holding_breath:
			is_running = true
	if is_sneaking and not was_sneaking:
		_dip_vel += SNEAK_DIP * _motion_scale()


## Speeds up / slows down toward the wanted speed, applies gravity and moves.
func _move(input: Vector2, has_input: bool, delta: float) -> void:
	var speed := WALK_SPEED
	if is_sneaking:
		speed = SNEAK_SPEED
	elif is_running:
		speed = RUN_SPEED
	speed *= _wall_slow
	var wish := transform.basis * Vector3(input.x, 0.0, input.y)
	wish.y = 0.0
	wish = wish.limit_length(1.0)
	var on_floor := is_on_floor()
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var rate := AIR_ACCEL
	if on_floor and has_input:
		rate = ACCEL
	elif on_floor:
		rate = DECEL
	flat = flat.move_toward(wish * speed, rate * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	if not on_floor:
		velocity.y -= _gravity * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
	move_and_slide()
	var grounded := is_on_floor()
	if grounded and not _was_on_floor:
		_on_landed(_fall_speed)
	if grounded:
		_fall_speed = 0.0
	_was_on_floor = grounded
	_wall_contact(wish, flat, delta)


## Scraping along a wall slows you (so corners read in the dark); walking
## into one bumps: a thud, a tiny camera nudge and a flash of floor glow.
func _wall_contact(wish: Vector3, pre: Vector3, delta: float) -> void:
	_bump_cooldown = maxf(_bump_cooldown - delta, 0.0)
	var target := 1.0
	if is_on_wall():
		var n := get_wall_normal()
		n.y = 0.0
		if n.length_squared() > 0.0001:
			n = n.normalized()
			if wish.length_squared() > 0.01:
				var into := -wish.normalized().dot(n)
				target = 1.0 - WALL_DRAG * smoothstep(0.05, 0.6, into)
			var impact := -pre.dot(n)
			if impact > BUMP_SPEED and _bump_cooldown <= 0.0:
				_bump(impact)
	# Slow down fast, recover slowly.
	var rate := 3.0
	if target < _wall_slow:
		rate = 12.0
	_wall_slow = move_toward(_wall_slow, target, rate * delta)


## Walked into a wall: a thud and a small camera knock.
func _bump(impact: float) -> void:
	_bump_cooldown = BUMP_COOLDOWN
	var t := clampf((impact - BUMP_SPEED) / (RUN_SPEED - BUMP_SPEED), 0.0, 1.0)
	Sfx.play("bump", lerpf(-14.0, -5.0, t), &"Cave", randf_range(0.9, 1.1))
	var k := _motion_scale()
	_nudge += lerpf(0.012, 0.035, t) * k
	_dip_vel += lerpf(0.2, 0.5, t) * k
	Echo.step()


## Jump up (with a small camera dip).
func _jump() -> void:
	_jump_cooldown = JUMP_COOLDOWN
	_jumped = true
	velocity.y = JUMP_VELOCITY
	_fall_speed = 0.0
	_dip_vel += 0.45 * _motion_scale()


## Landed: a thud and a camera dip, bigger for longer falls.
func _on_landed(fall_speed: float) -> void:
	var from_jump := _jumped
	_jumped = false
	if from_jump and not is_sneaking:
		Echo.make_noise(global_position, JUMP_NOISE)
	if fall_speed < LAND_MIN_SPEED:
		if from_jump:
			Sfx.play("land", -14.0, &"Cave", randf_range(0.95, 1.08))
			if Settings.landing_motion:
				_dip_vel += 0.7 * _motion_scale()
		return
	var t := clampf((fall_speed - LAND_MIN_SPEED) / 8.0, 0.0, 1.0)
	Sfx.play("land", lerpf(-10.0, 0.0, t), &"Cave", randf_range(0.92, 1.05))
	if Settings.landing_motion:
		_dip_vel += lerpf(0.9, 2.6, t) * _motion_scale()
	Echo.step()


## Sprinting uses stamina; it refills after a short pause. At 0 you're winded.
func _update_stamina(delta: float, sprinting: bool, has_input: bool) -> void:
	var sprint_time := STAMINA_TIME
	var refill_time := STAMINA_REFILL
	if Settings.assist_mode:
		sprint_time = 6.0
		refill_time = 3.5
	elif Settings.hard_mode:
		sprint_time = 3.0
		refill_time = 6.5
	if sprinting:
		stamina = maxf(stamina - delta / sprint_time, 0.0)
		_regen_delay = STAMINA_REGEN_DELAY
		if stamina <= 0.0 and not is_winded:
			is_winded = true
			_run_on = false
			_breath_timer = 0.0
	else:
		_regen_delay = maxf(_regen_delay - delta, 0.0)
		if _regen_delay <= 0.0:
			var rate := 1.0 / refill_time
			if not has_input:
				rate *= 1.5
			stamina = minf(stamina + rate * delta, 1.0)
	if not is_winded:
		return
	if stamina >= WINDED_RECOVER:
		is_winded = false
		return
	# Heavy breathing while out of breath, easing off as you recover.
	_breath_timer -= delta
	if _breath_timer <= 0.0:
		_breath_timer = 0.8
		var recovered := stamina / WINDED_RECOVER
		var volume := lerpf(-6.0, -14.0, recovered)
		Sfx.play("pant", volume, &"Cave", randf_range(0.95, 1.05))


## Plays a footstep every so often while moving (and makes noise for Listeners).
func _footsteps(delta: float, moving: bool) -> void:
	if not moving:
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer > 0.0:
		return
	if is_sneaking:
		_step_timer = 0.6
	elif is_running:
		_step_timer = 0.3
	else:
		_step_timer = 0.45
	Echo.step()
	if noise_radius > 0.0:
		Echo.make_noise(global_position, noise_radius)
	if holding_breath:
		return
	# Noisy floor: an extra splash / crunch / creak.
	var floor_sound := _floor_sound(_floor_kind)
	if floor_sound != "":
		var floor_volume := -4.0
		if is_sneaking:
			floor_volume = -14.0
		Sfx.play(floor_sound, floor_volume, &"Cave", randf_range(0.9, 1.1))
	# The step itself sounds different on wood, gravel and water.
	var surface := _surface()
	var sound := "step"
	if surface in SURFACES:
		sound = "step_" + surface
	step_sound.stream = Sfx.stream(sound)
	if is_sneaking:
		step_sound.volume_db = -16.0
	elif is_running:
		step_sound.volume_db = -2.0
	else:
		step_sound.volume_db = -8.0
	step_sound.pitch_scale = randf_range(0.9, 1.1)
	step_sound.play()


## The extra sound a noisy floor makes ("" = none).
func _floor_sound(kind: String) -> String:
	match kind:
		"puddle":
			return "splash"
		"bones":
			return "bone_crunch"
		"plank":
			return "plank_creak"
	return ""


## Floor type under the player, from the level's "surface" areas ("" = stone).
func _surface() -> String:
	var areas: Array[Node] = get_tree().get_nodes_in_group("surface")
	for node in areas:
		var area := node as Area3D
		if area != null and area.overlaps_body(self):
			return str(area.get_meta("surface", ""))
	return ""


# ---------------------------------------------------------------- Actions

## Dagger, ping, whisper and throw buttons.
func _actions(delta: float, can_act: bool) -> void:
	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	_update_viewmodel()
	if can_act and Input.is_action_just_pressed("attack"):
		try_attack()
	var was_cooling := ping_cooldown > 0.0
	ping_cooldown = maxf(ping_cooldown - delta, 0.0)
	whisper_cooldown = maxf(whisper_cooldown - delta, 0.0)
	if can_act:
		if Input.is_action_just_pressed("ping"):
			if ping_cooldown <= 0.0:
				try_ping()
			elif ping_cooldown <= PING_BUFFER:
				_ping_buffered = true
		if Input.is_action_just_pressed("whisper"):
			try_whisper()
		if Input.is_action_just_pressed("throw") and not is_hiding:
			_begin_aim()
	if was_cooling and ping_cooldown <= 0.0:
		if _ping_buffered:
			try_ping()
		else:
			Sfx.play("ready", -18.0, &"Cave")
	_update_aim(delta)


## The main ping: a loud echo that lights up the cave (and Listeners hear it).
func try_ping() -> void:
	if ping_cooldown > 0.0 or Echo.challenge() == "no_ping":
		return
	if is_hiding:
		hide_exposed = true  # a loud call gives you away
	_nudge += 0.012 * _motion_scale()
	_dip_vel += 0.3 * _motion_scale()
	ping_cooldown = Game.ping_cooldown
	_ping_buffered = false
	Echo.emit_ping(global_position + Vector3.UP, Game.ping_radius, true)
	ping_sound.pitch_scale = randf_range(0.96, 1.04)
	ping_sound.play()
	Game.add_stat("pings")


## A small echo nothing can hear. Safe, but it barely shows anything.
func try_whisper() -> void:
	if whisper_cooldown > 0.0:
		return
	whisper_cooldown = WHISPER_COOLDOWN
	Echo.emit_ping(global_position + Vector3.UP * 0.5, WHISPER_RADIUS, false)
	Sfx.play("whisper_ping", -10.0, &"Cave")
	Game.add_stat("whispers")


## Throw pressed: start aiming (or say there are no pebbles left).
func _begin_aim() -> void:
	if Game.pebbles <= 0:
		Game.prompt_requested.emit("pebbles_empty")
		Sfx.play("click", -14.0, &"Cave", 0.7)
		return
	_aiming = true
	_aim_time = 0.0


## While throw is held: show the arc. On release: throw.
func _update_aim(delta: float) -> void:
	if not _aiming:
		return
	if not Input.is_action_pressed("throw"):
		_cancel_aim()
		throw_pebble()
		return
	_aim_time += delta
	if _aim_time >= AIM_SHOW_DELAY:
		_draw_arc()


## Stop aiming and hide the arc.
func _cancel_aim() -> void:
	_aiming = false
	if _arc_root != null:
		_arc_root.visible = false


## Throws a pebble forward (if you have one).
func throw_pebble() -> void:
	if pebble_scene == null:
		return
	if not Game.use_pebble():
		Game.prompt_requested.emit("pebbles_empty")
		return
	var pebble := pebble_scene.instantiate() as RigidBody3D
	get_parent().add_child(pebble)
	pebble.global_position = _throw_origin()
	pebble.linear_velocity = _throw_velocity()
	pebble.set("throw_origin", global_position)
	Game.add_stat("pebbles_thrown")


## The direction you look in.
func _throw_forward() -> Vector3:
	return -head.global_basis.z


## Where a thrown pebble appears: a little in front of the camera.
func _throw_origin() -> Vector3:
	var forward := _throw_forward()
	var from := camera.global_position
	var spawn := from + forward * 0.6
	# Facing a wall: spawn in front of it, not inside it.
	var hit := _ray(from, spawn)
	if not hit.is_empty():
		var wall: Vector3 = hit["position"]
		spawn = wall - forward * 0.15
	return spawn


## How fast (and which way) a thrown pebble flies.
func _throw_velocity() -> Vector3:
	return _throw_forward() * THROW_SPEED + Vector3.UP * THROW_LIFT


## Dotted gold arc: steps the same gravity and damping the pebble will feel
## and stops at the first wall or floor it would hit.
func _draw_arc() -> void:
	_arc_root.visible = true
	var p := _throw_origin()
	var v := _throw_velocity()
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var damp := clampf(1.0 - dt * _pebble_damp, 0.0, 1.0)
	var space := get_world_3d().direct_space_state
	var shown := 0
	for i in ARC_DOTS:
		var prev := p
		for _s in ARC_SUBSTEPS:
			v.y -= _gravity * dt
			v *= damp
			p += v * dt
		var dot := _arc_dots[i]
		shown = i + 1
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(prev, p, 1))
		if not hit.is_empty():
			# It would hit something here: show a bigger dot and stop.
			var hit_pos: Vector3 = hit["position"]
			dot.position = hit_pos
			dot.scale = Vector3.ONE * 2.4
			break
		dot.position = p
		# Dots get smaller along the arc.
		var along := float(i) / float(ARC_DOTS)
		dot.scale = Vector3.ONE * lerpf(1.0, 0.55, along)
	# Only show the dots we used.
	for j in ARC_DOTS:
		if j < shown:
			_arc_dots[j].visible = true
		else:
			_arc_dots[j].visible = false


## Makes the (hidden) dots used to draw the throw arc.
func _build_arc() -> void:
	_arc_root = Node3D.new()
	_arc_root.name = "ThrowArc"
	_arc_root.top_level = true
	_arc_root.visible = false
	add_child(_arc_root)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = ARC_COLOR
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.022
	dot_mesh.height = 0.044
	dot_mesh.radial_segments = 8
	dot_mesh.rings = 4
	for _i in ARC_DOTS:
		var dot := MeshInstance3D.new()
		dot.mesh = dot_mesh
		dot.material_override = mat
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_arc_root.add_child(dot)
		_arc_dots.append(dot)


# ---------------------------------------------------------------- Breath and hiding

## Hold "hold_breath": silent, but only for BREATH_TIME. Running out is a loud gasp.
func _update_breath(can_act: bool, delta: float) -> void:
	var want := false
	if can_act and Input.is_action_pressed("hold_breath"):
		if not _breath_locked and breath > 0.0:
			want = true
	if want and not holding_breath:
		holding_breath = true
		Sfx.play("breath_hold", -8.0, &"Cave")
	elif not want and holding_breath:
		holding_breath = false
	if holding_breath:
		breath = maxf(breath - delta / BREATH_TIME, 0.0)
		if breath <= 0.0:
			holding_breath = false
			_breath_locked = true
			Sfx.play("breath_release", -2.0, &"Cave")
			Sfx.caption("[a loud gasp for air]", global_position, 3.0)
			Echo.make_noise(global_position, GASP_NOISE)
			if is_hiding:
				hide_exposed = true
	else:
		breath = minf(breath + delta / BREATH_REGEN, 1.0)
		if _breath_locked and breath >= 0.4:
			_breath_locked = false


## "interact" inside a hiding spot hides you; pressed again it lets you out.
func _update_hiding(can_act: bool) -> void:
	if not can_act:
		return
	if not Input.is_action_just_pressed("interact"):
		_maybe_show_hide_hint()
		return
	if is_hiding:
		is_hiding = false
		hide_exposed = false
		global_position = _hide_return
		velocity = Vector3.ZERO
		Sfx.play("click", -12.0, &"Cave", 0.8)
		return
	var spot := _find_hiding_spot()
	if spot == null:
		return
	_hide_return = global_position
	# The spot's origin sits 1 m above the alcove floor.
	global_position = spot.global_position - Vector3.UP * 1.0
	velocity = Vector3.ZERO
	rotation.y = deg_to_rad(float(spot.get_meta("yaw", 0.0)))
	head.rotation.x = 0.0
	is_hiding = true
	hide_exposed = false
	_hide_hinted = true
	_cancel_aim()
	_ping_buffered = false
	Game.add_stat("hides")
	Sfx.play("click", -12.0, &"Cave", 0.8)


## The first time you stand in a hiding spot, explain how to hide.
func _maybe_show_hide_hint() -> void:
	if is_hiding or _hide_hinted:
		return
	# Only check every 6th physics frame (it's a little expensive).
	if Engine.get_physics_frames() % 6 != 0:
		return
	if _find_hiding_spot() == null:
		return
	_hide_hinted = true
	Game.show_subtitle("A crevice. Press interact to hide in it. Again to come out.")


## The hiding spot you are standing in (or null).
func _find_hiding_spot() -> Area3D:
	var areas: Array[Node] = get_tree().get_nodes_in_group("hiding_spot")
	for node in areas:
		var area := node as Area3D
		if area != null and area.overlaps_body(self):
			return area
	return null


## Floor kind under the player from the level's "noise_floor" areas ("" = quiet).
func _noise_floor_kind() -> String:
	if not is_on_floor():
		return ""
	var areas: Array[Node] = get_tree().get_nodes_in_group("noise_floor")
	for node in areas:
		var area := node as Area3D
		if area != null and area.overlaps_body(self):
			return str(area.get_meta("noise", ""))
	return ""


## Hidden and not found: Listeners can't see or catch you.
func is_hidden() -> bool:
	return is_hiding and not hide_exposed


## Still, sneaking, holding your breath or hidden: a Listener passing is a near miss.
func is_quiet() -> bool:
	if is_hidden() or holding_breath or is_sneaking:
		return true
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	return flat_speed < 0.5


## A Listener found you in your hiding spot.
func expose_hidden() -> void:
	if is_hiding:
		hide_exposed = true


## A heavy thud nearby: a small camera kick.
func thump(strength: float) -> void:
	_nudge += 0.02 * strength * _motion_scale()
	_dip_vel += 0.6 * strength * _motion_scale()


# ---------------------------------------------------------------- Respawn / caught

## Called by main.gd. yaw sets the facing (and levels the head); NAN keeps it.
func respawn(pos: Vector3, yaw: float = NAN) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	ping_cooldown = 0.0
	attack_cooldown = 0.0
	_ping_buffered = false
	_fall_speed = 0.0
	_was_on_floor = true
	_jumped = false
	_jump_cooldown = 0.0
	_wall_slow = 1.0
	_dip = 0.0
	_dip_vel = 0.0
	_nudge = 0.0
	_run_on = false
	stamina = 1.0
	is_winded = false
	is_hiding = false
	hide_exposed = false
	holding_breath = false
	breath = 1.0
	_breath_locked = false
	_cancel_aim()
	if not is_nan(yaw):
		rotation.y = yaw
		head.rotation.x = 0.0


## Hurt by a Listener (damage mode): a jolt and a rumble.
func _on_damaged(amount: int, _from: Vector3) -> void:
	_kick = maxf(_kick, 0.012 * amount)
	_nudge += 0.02 * amount * _motion_scale()
	Settings.vibrate(0.4, 0.3 + 0.15 * amount, 0.25)


## Caught: snap to face the thing that got you.
func _on_caught() -> void:
	_kick = 0.08
	_cancel_aim()
	_ping_buffered = false
	look_toward(Game.catcher_position + Vector3.UP * 1.4)


# ---------------------------------------------------------------- Camera

## Camera knocks are smaller with the "reduce shake" setting.
func _motion_scale() -> float:
	if Settings.reduce_shake:
		return 0.4
	return 1.0


## A smooth-follow amount for this frame: higher `speed` catches up faster.
func _smooth(speed: float, dt: float) -> float:
	return 1.0 - exp(-speed * dt)


## Every frame: shake, head height, bob, roll and FOV.
func _update_camera(delta: float) -> void:
	var dt := minf(delta, 0.05)  # don't jump after a long frame
	var raw_shake := _update_shake(delta)
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	_update_head_position(dt, flat_speed)
	_update_camera_tilt(dt, raw_shake)
	_update_fov(dt, flat_speed)


## Random camera jitter from the dread and from getting hit.
## Returns the shake strength (before "reduce shake") for the roll.
func _update_shake(delta: float) -> float:
	_kick = maxf(_kick - delta * 0.15, 0.0)
	var raw: float = (shake + _kick) * Settings.shake_scale()
	var s := raw
	if Settings.reduce_shake:
		s = raw * SHAKE_REDUCED
	camera.h_offset = randf_range(-s, s)
	camera.v_offset = randf_range(-s, s)
	return raw


## Head height: lower while sneaking, a springy dip on landings and bumps,
## and the optional head bob.
func _update_head_position(dt: float, flat_speed: float) -> void:
	var stand := _stand_height
	if is_sneaking or is_hiding:
		stand = _stand_height - SNEAK_DROP
	_head_h = lerpf(_head_h, stand, _smooth(8.0, dt))

	# The dip is a spring: it is pulled back to 0 and slowed down by damping.
	var spring_force := -DIP_STIFF * _dip - DIP_DAMP * _dip_vel
	_dip_vel += spring_force * dt
	_dip = clampf(_dip + _dip_vel * dt, -0.1, 0.3)

	# Head bob (only with the setting on).
	var bob_target := 0.0
	if Settings.head_bob and is_on_floor() and Game.state == Game.State.PLAYING:
		bob_target = clampf(flat_speed / WALK_SPEED, 0.0, 1.5)
	_bob_amount = lerpf(_bob_amount, bob_target, _smooth(6.0, dt))
	_bob_phase = fmod(_bob_phase + flat_speed * BOB_RATE * dt, TAU)
	var bob_y := sin(_bob_phase * 2.0) * BOB_HEIGHT * _bob_amount
	var bob_x := sin(_bob_phase) * BOB_SWAY * _bob_amount
	head.position = Vector3(bob_x, _head_h + bob_y - _dip, 0.0)


## Bump nudge (pitch) and a slow uneasy roll when the shake is high.
func _update_camera_tilt(dt: float, raw_shake: float) -> void:
	_nudge = lerpf(_nudge, 0.0, _smooth(9.0, dt))
	camera.rotation.x = _nudge
	var roll := 0.0
	if not Settings.reduce_shake:
		_roll_time += dt
		var amount := clampf((raw_shake - 0.006) / 0.03, 0.0, 1.0) * ROLL_MAX
		# Two slow waves mixed together, so the roll doesn't look regular.
		var wave_a := sin(_roll_time * 1.7) * 0.7
		var wave_b := sin(_roll_time * 4.3 + 1.0) * 0.3
		roll = amount * (wave_a + wave_b)
	camera.rotation.z = lerpf(camera.rotation.z, roll, _smooth(5.0, dt))


## FOV from the settings, a little wider at a sprint.
func _update_fov(dt: float, flat_speed: float) -> void:
	var run_t := 0.0
	if is_running:
		run_t = clampf((flat_speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0)
	var base_fov: float = Settings.fov
	var want_fov := base_fov + RUN_FOV * run_t
	camera.fov = lerpf(camera.fov, want_fov, _smooth(6.0, dt))


# ---------------------------------------------------------------- Dagger (damage mode)

## True if you have the dagger and damage mode is on.
func can_attack() -> bool:
	return Game.has_dagger and Game.damage_enabled()


## Swing the dagger: hits the nearest Listener in a short cone in front.
func try_attack() -> void:
	if not can_attack() or attack_cooldown > 0.0 or is_hiding:
		return
	attack_cooldown = ATTACK_COOLDOWN
	_swing()
	Sfx.play("dagger_swing", -4.0, &"Master", randf_range(0.95, 1.08))
	Echo.make_noise(global_position, ATTACK_NOISE)
	Game.add_stat("swings")
	var target := _attack_target()
	if target == null:
		return
	Sfx.play_3d("dagger_hit", target.global_position + Vector3.UP * 1.2, 0.0, &"Cave", randf_range(0.9, 1.1), 4.0, 25.0)
	_nudge += 0.015 * _motion_scale()
	var dmg := Game.dagger_damage()
	target.call("take_damage", dmg, global_position)
	Game.listener_damaged.emit(dmg, target.global_position + Vector3.UP * 1.8)
	Game.add_stat("hits")
	Settings.vibrate(0.3, 0.5, 0.15)


## The closest living Listener in front of you and in reach (or null).
func _attack_target() -> Node3D:
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var best: Node3D = null
	var best_d := INF
	var listeners: Array[Node] = get_tree().get_nodes_in_group("listener")
	for node in listeners:
		var l := node as Node3D
		if l == null:
			continue
		if l.get("is_dead") == true or not l.has_method("take_damage"):
			continue
		var to := l.global_position - global_position
		if absf(to.y) > 2.0:
			continue  # on another floor
		to.y = 0.0
		var d := to.length()
		if d > ATTACK_RANGE + LISTENER_RADIUS:
			continue  # too far
		if d > 0.6:
			var facing := forward.dot(to / d)
			if facing < ATTACK_CONE:
				continue  # not in front of you
		if not _can_reach(l):
			continue
		if d < best_d:
			best_d = d
			best = l
	return best


## True if nothing solid (world geometry only) is between your eyes and the Listener.
func _can_reach(l: Node3D) -> bool:
	var eye := camera.global_position
	var target := l.global_position + Vector3.UP * 1.2
	var query := PhysicsRayQueryParameters3D.create(eye, target, 1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


## Casts a ray against the world (layer 1). Empty if it hit nothing.
func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(query)


## First-person dagger, lower right of the view.
func _build_viewmodel() -> void:
	var blade := DaggerModel.make_material(DaggerModel.STEEL, 0.55)
	var grip := DaggerModel.make_material(DaggerModel.GRIP, 0.6)
	_viewmodel = DaggerModel.build(blade, grip)
	_viewmodel.name = "DaggerViewmodel"
	camera.add_child(_viewmodel)
	_viewmodel.position = VIEWMODEL_REST
	_viewmodel.rotation_degrees = VIEWMODEL_REST_ROT
	_viewmodel.visible = false


## Shows the dagger only when you can use it.
func _update_viewmodel() -> void:
	if _viewmodel != null:
		_viewmodel.visible = can_attack() and not is_hiding


## The dagger swing animation.
func _swing() -> void:
	if _viewmodel == null:
		return
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_viewmodel.position = VIEWMODEL_REST
	_viewmodel.rotation_degrees = VIEWMODEL_REST_ROT
	_swing_tween = create_tween()

	# Step 1 (0.08 s): wind up, pulling back and up.
	var windup_pos := VIEWMODEL_REST + Vector3(0.06, 0.06, 0.1)
	_swing_tween.tween_property(_viewmodel, "position", windup_pos, 0.08)
	_swing_tween.parallel().tween_property(_viewmodel, "rotation_degrees", Vector3(25.0, 25.0, -20.0), 0.08)

	# Step 2 (0.1 s): stab forward and across.
	var stab_pos := VIEWMODEL_REST + Vector3(-0.14, 0.04, -0.28)
	var stab: PropertyTweener = _swing_tween.tween_property(_viewmodel, "position", stab_pos, 0.1)
	stab.set_trans(Tween.TRANS_QUAD)
	stab.set_ease(Tween.EASE_OUT)
	_swing_tween.parallel().tween_property(_viewmodel, "rotation_degrees", Vector3(-10.0, -10.0, 15.0), 0.1)

	# Step 3 (0.3 s): back to rest.
	var back: PropertyTweener = _swing_tween.tween_property(_viewmodel, "position", VIEWMODEL_REST, 0.3)
	back.set_trans(Tween.TRANS_SINE)
	_swing_tween.parallel().tween_property(_viewmodel, "rotation_degrees", VIEWMODEL_REST_ROT, 0.3)
