extends CharacterBody3D
## First-person player: walk / sneak / run (with stamina), mouse and controller
## look, ping, whisper ping, throw pebbles (hold to aim, release to throw) and
## numbered chalk marks.
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
const MAX_MARKS := 6
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
const CHALK_GOLD := Color(0.55, 0.42, 0.12)
const CHALK_WHITE := Color(0.62, 0.62, 0.58)
const LABEL_GOLD := Color(1.0, 0.78, 0.3, 0.5)
const LABEL_WHITE := Color(0.92, 0.92, 0.9, 0.5)
const ARC_COLOR := Color(1.0, 0.8, 0.32, 0.85)
## Holding your breath: seconds it lasts, seconds to refill, and the gasp when it runs out.
const BREATH_TIME := 6.0
const BREATH_REGEN := 4.0
const GASP_NOISE := 8.0
## Noisy floors (area group "noise_floor", meta "noise"): footstep radius and sound.
const FLOOR_NOISE := 6.0
const FLOOR_SOUNDS := {"puddle": "splash", "bones": "bone_crunch", "plank": "plank_creak"}

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
var chalk_white := false  ## Next chalk marks are white instead of gold.
var shake := 0.0  ## Set every frame by the Director (how close the Listeners are).
var breath := 1.0  ## 0 - 1: how much held breath is left (HUD).
var holding_breath := false  ## Silent while true (footsteps and floors make no noise).
var is_hiding := false  ## Inside a hiding spot (group "hiding_spot"): can't move.
var hide_exposed := false  ## Hiding but found / noisy: Listeners can catch you again.

var _kick := 0.0  ## Extra shake for a moment (getting caught).
var _step_timer := 0.0
var _marks: Array[Node3D] = []
var _mark_count := 0
var _mark_mesh: CylinderMesh
var _mark_gold: StandardMaterial3D
var _mark_white: StandardMaterial3D
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


func _ready() -> void:
	if ping_sound.stream == null:
		ping_sound.stream = Sfx.stream("ping")
	if step_sound.stream == null:
		step_sound.stream = Sfx.stream("step")
	_stand_height = head.position.y
	_head_h = _stand_height
	_build_arc()
	Game.player_caught.connect(_on_caught)
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


func _unhandled_input(event: InputEvent) -> void:
	if Game.state != Game.State.PLAYING or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	var sens: float = MOUSE_SENS * Settings.mouse_sensitivity
	rotate_y(-motion.relative.x * sens)
	var dy: float = motion.relative.y * sens
	if Settings.invert_y:
		dy = -dy
	_pitch(-dy)


func _process(delta: float) -> void:
	if Game.state == Game.State.PLAYING and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_controller_look(delta)
	_update_camera(delta)


func _physics_process(delta: float) -> void:
	Echo.set_player_position(global_position)
	# A gap in physics frames means the tree was paused.
	var frame := Engine.get_physics_frames()
	var resumed := frame - _last_frame > 1
	_last_frame = frame
	# Don't simulate on the title screen or while caught.
	if Game.state != Game.State.PLAYING:
		velocity = Vector3.ZERO
		_act_blocked = true
		_cancel_aim()
		_ping_buffered = false
		is_running = false
		holding_breath = false
		noise_radius = 0.0
		return
	# Swallow presses on the first tick after starting / resuming, so the
	# click that locked the mouse doesn't also ping.
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var can_act := captured and not resumed and not _act_blocked
	_act_blocked = not captured
	if not can_act:
		_cancel_aim()
		_ping_buffered = false

	# Challenge: one pebble at most.
	if Echo.challenge() == "one_pebble" and (Game.max_pebbles != 1 or Game.pebbles > 1):
		Game.max_pebbles = 1
		Game.pebbles = mini(Game.pebbles, 1)
		Game.pebbles_changed.emit(Game.pebbles)
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
	_update_stamina(delta, is_running and moving, has_input)
	if not moving or is_sneaking or holding_breath:
		noise_radius = 0.0
	elif is_running:
		noise_radius = RUN_NOISE
	else:
		noise_radius = WALK_NOISE
	_floor_kind = ""
	if moving and not holding_breath:
		_floor_kind = _noise_floor_kind()
		if _floor_kind != "":
			# Puddles, bones, planks: loud under a walk, half as loud when sneaking.
			noise_radius = maxf(noise_radius, FLOOR_NOISE * (0.5 if is_sneaking else 1.0))
	_footsteps(delta, moving)
	_actions(delta, can_act)
	# Fell into the chasm or out of the level.
	if global_position.y < FALL_LIMIT:
		Game.player_fell.emit()
		respawn(Game.checkpoint_position, Game.checkpoint_yaw)


# ---------------------------------------------------------------- Look

func _pitch(amount: float) -> void:
	var limit := deg_to_rad(PITCH_LIMIT)
	head.rotation.x = clampf(head.rotation.x + amount, -limit, limit)


## Right stick, with a response curve so small tilts give fine aim.
func _controller_look(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var mag := look.length()
	if mag < 0.001:
		return
	var curved := look / mag * pow(minf(mag, 1.0), PAD_LOOK_CURVE)
	var speed: float = PAD_LOOK_SPEED * Settings.controller_look_speed
	rotate_y(-curved.x * speed * delta)
	var dy := curved.y * speed * PAD_PITCH_RATIO * delta
	if Settings.invert_y:
		dy = -dy
	_pitch(-dy)


func look_toward(p: Vector3) -> void:
	var to := p - head.global_position
	if to.length() < 0.01:
		return
	rotation.y = atan2(-to.x, -to.z)
	head.rotation.x = clampf(atan2(to.y, Vector2(to.x, to.z).length()), deg_to_rad(-PITCH_LIMIT), deg_to_rad(PITCH_LIMIT))


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
	is_running = _run_on and not is_sneaking and has_input and not is_winded and is_on_floor() and not holding_breath
	if is_sneaking and not was_sneaking:
		_dip_vel += SNEAK_DIP * _motion_scale()


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
	if on_floor:
		rate = ACCEL if has_input else DECEL
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
	var rate := 12.0 if target < _wall_slow else 3.0
	_wall_slow = move_toward(_wall_slow, target, rate * delta)


func _bump(impact: float) -> void:
	_bump_cooldown = BUMP_COOLDOWN
	var t := clampf((impact - BUMP_SPEED) / (RUN_SPEED - BUMP_SPEED), 0.0, 1.0)
	Sfx.play("bump", lerpf(-14.0, -5.0, t), &"Cave", randf_range(0.9, 1.1))
	var k := _motion_scale()
	_nudge += lerpf(0.012, 0.035, t) * k
	_dip_vel += lerpf(0.2, 0.5, t) * k
	Echo.step()


func _jump() -> void:
	_jump_cooldown = JUMP_COOLDOWN
	_jumped = true
	velocity.y = JUMP_VELOCITY
	_fall_speed = 0.0
	_dip_vel += 0.45 * _motion_scale()


func _on_landed(fall_speed: float) -> void:
	var from_jump := _jumped
	_jumped = false
	if from_jump and not is_sneaking:
		Echo.make_noise(global_position, JUMP_NOISE)
	if fall_speed < LAND_MIN_SPEED:
		if from_jump:
			Sfx.play("land", -14.0, &"Cave", randf_range(0.95, 1.08))
			_dip_vel += 0.7 * _motion_scale()
		return
	var t := clampf((fall_speed - LAND_MIN_SPEED) / 8.0, 0.0, 1.0)
	Sfx.play("land", lerpf(-10.0, 0.0, t), &"Cave", randf_range(0.92, 1.05))
	_dip_vel += lerpf(0.9, 2.6, t) * _motion_scale()
	Echo.step()


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
		Sfx.play("pant", lerpf(-6.0, -14.0, stamina / WINDED_RECOVER), &"Cave", randf_range(0.95, 1.05))


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
	if _floor_kind != "":
		var floor_sound: String = str(FLOOR_SOUNDS.get(_floor_kind, ""))
		if floor_sound != "":
			Sfx.play(floor_sound, -14.0 if is_sneaking else -4.0, &"Cave", randf_range(0.9, 1.1))
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


## Floor type under the player, from the level's "surface" areas ("" = stone).
func _surface() -> String:
	for node in (get_tree().get_nodes_in_group("surface") as Array):
		var area := node as Area3D
		if area != null and area.overlaps_body(self):
			return str(area.get_meta("surface", ""))
	return ""


# ---------------------------------------------------------------- Actions

func _actions(delta: float, can_act: bool) -> void:
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
		if Input.is_action_just_pressed("chalk") and not is_hiding:
			# Chalk while holding sneak: switch gold / white for the next marks.
			if Input.is_action_pressed("sneak"):
				chalk_white = not chalk_white
			drop_mark()
		if Input.is_action_just_pressed("throw") and not is_hiding:
			_begin_aim()
	if was_cooling and ping_cooldown <= 0.0:
		if _ping_buffered:
			try_ping()
		else:
			Sfx.play("ready", -18.0, &"Cave")
	_update_aim(delta)


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


func _cancel_aim() -> void:
	_aiming = false
	if _arc_root != null:
		_arc_root.visible = false


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


func _throw_forward() -> Vector3:
	return -head.global_basis.z


func _throw_origin() -> Vector3:
	var forward := _throw_forward()
	var from := camera.global_position
	var spawn := from + forward * 0.6
	# Facing a wall: spawn in front of it, not inside it.
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, spawn, 1))
	if hit:
		spawn = (hit["position"] as Vector3) - forward * 0.15
	return spawn


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
		if hit:
			dot.position = hit["position"] as Vector3
			dot.scale = Vector3.ONE * 2.4
			break
		dot.position = p
		dot.scale = Vector3.ONE * lerpf(1.0, 0.55, float(i) / float(ARC_DOTS))
	for j in ARC_DOTS:
		_arc_dots[j].visible = j < shown


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


## Chalk mark on the floor: faint gold (or white), numbered, stays after the
## echo fades. Your own map.
func drop_mark() -> void:
	var from := global_position + Vector3.UP * 0.5
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0, 1))
	if hit.is_empty():
		return
	if _mark_mesh == null:
		_mark_mesh = CylinderMesh.new()
		_mark_mesh.top_radius = 0.2
		_mark_mesh.bottom_radius = 0.2
		_mark_mesh.height = 0.02
		_mark_gold = _chalk_material(CHALK_GOLD)
		_mark_white = _chalk_material(CHALK_WHITE)
	_mark_count += 1
	var mark := MeshInstance3D.new()
	mark.mesh = _mark_mesh
	mark.material_override = _mark_white if chalk_white else _mark_gold
	mark.add_to_group("chalk_mark")
	mark.set_meta("number", _mark_count)
	mark.set_meta("color", CHALK_WHITE if chalk_white else CHALK_GOLD)
	var label := Label3D.new()
	label.text = str(_mark_count)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 48
	label.pixel_size = 0.004
	label.outline_size = 6
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.6)
	label.modulate = LABEL_WHITE if chalk_white else LABEL_GOLD
	label.visibility_range_end = 30.0
	label.position = Vector3(0.0, 0.3, 0.0)
	mark.add_child(label)
	get_parent().add_child(mark)
	mark.global_position = (hit["position"] as Vector3) + Vector3.UP * 0.015
	_marks.append(mark)
	if _marks.size() > MAX_MARKS:
		var old: Node3D = _marks.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	Sfx.play("chalk", -8.0, &"Cave", 1.15 if chalk_white else 1.0)
	Game.add_stat("chalk")


func _chalk_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat


# ---------------------------------------------------------------- Breath and hiding

## Hold "hold_breath": silent, but only for BREATH_TIME. Running out is a loud gasp.
func _update_breath(can_act: bool, delta: float) -> void:
	var want := can_act and Input.is_action_pressed("hold_breath") and not _breath_locked and breath > 0.0
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
		if not is_hiding and not _hide_hinted and Engine.get_physics_frames() % 6 == 0 and _find_hiding_spot() != null:
			_hide_hinted = true
			Game.show_subtitle("A crevice. Press interact to hide in it. Again to come out.")
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


func _find_hiding_spot() -> Area3D:
	for node in (get_tree().get_nodes_in_group("hiding_spot") as Array):
		var area := node as Area3D
		if area != null and area.overlaps_body(self):
			return area
	return null


## Floor kind under the player from the level's "noise_floor" areas ("" = quiet).
func _noise_floor_kind() -> String:
	if not is_on_floor():
		return ""
	for node in (get_tree().get_nodes_in_group("noise_floor") as Array):
		var area := node as Area3D
		if area != null and area.overlaps_body(self):
			return str(area.get_meta("noise", ""))
	return ""


## Hidden and not found: Listeners can't see or catch you.
func is_hidden() -> bool:
	return is_hiding and not hide_exposed


## Still, sneaking, holding your breath or hidden: a Listener passing is a near miss.
func is_quiet() -> bool:
	return is_hidden() or holding_breath or is_sneaking or Vector2(velocity.x, velocity.z).length() < 0.5


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


## Caught: snap to face the thing that got you.
func _on_caught() -> void:
	_kick = 0.08
	_cancel_aim()
	_ping_buffered = false
	look_toward(Game.catcher_position + Vector3.UP * 1.4)


# ---------------------------------------------------------------- Camera

func _motion_scale() -> float:
	return 0.4 if Settings.reduce_shake else 1.0


func _update_camera(delta: float) -> void:
	var dt := minf(delta, 0.05)
	var gentle: bool = Settings.reduce_shake
	_kick = maxf(_kick - delta * 0.15, 0.0)
	var raw := shake + _kick
	var s := raw * (SHAKE_REDUCED if gentle else 1.0)
	camera.h_offset = randf_range(-s, s)
	camera.v_offset = randf_range(-s, s)

	# Sneaking lowers the head; landings, bumps and crouching dip it on a spring.
	var stand := _stand_height - (SNEAK_DROP if is_sneaking or is_hiding else 0.0)
	_head_h = lerpf(_head_h, stand, 1.0 - exp(-8.0 * dt))
	_dip_vel += (-DIP_STIFF * _dip - DIP_DAMP * _dip_vel) * dt
	_dip = clampf(_dip + _dip_vel * dt, -0.1, 0.3)

	# Head bob (only with the setting on).
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var bob_target := 0.0
	if Settings.head_bob and is_on_floor() and Game.state == Game.State.PLAYING:
		bob_target = clampf(flat_speed / WALK_SPEED, 0.0, 1.5)
	_bob_amount = lerpf(_bob_amount, bob_target, 1.0 - exp(-6.0 * dt))
	_bob_phase = fmod(_bob_phase + flat_speed * BOB_RATE * dt, TAU)
	var bob_y := sin(_bob_phase * 2.0) * BOB_HEIGHT * _bob_amount
	var bob_x := sin(_bob_phase) * BOB_SWAY * _bob_amount
	head.position = Vector3(bob_x, _head_h + bob_y - _dip, 0.0)

	# Bump nudge (pitch) and a slow uneasy roll when the shake is high.
	_nudge = lerpf(_nudge, 0.0, 1.0 - exp(-9.0 * dt))
	camera.rotation.x = _nudge
	var roll := 0.0
	if not gentle:
		_roll_time += dt
		var amount := clampf((raw - 0.006) / 0.03, 0.0, 1.0) * ROLL_MAX
		roll = amount * (sin(_roll_time * 1.7) * 0.7 + sin(_roll_time * 4.3 + 1.0) * 0.3)
	camera.rotation.z = lerpf(camera.rotation.z, roll, 1.0 - exp(-5.0 * dt))

	# FOV from the settings, a little wider at a sprint.
	var run_t := 0.0
	if is_running:
		run_t = clampf((flat_speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0)
	var base_fov: float = Settings.fov
	camera.fov = lerpf(camera.fov, base_fov + RUN_FOV * run_t, 1.0 - exp(-6.0 * dt))
