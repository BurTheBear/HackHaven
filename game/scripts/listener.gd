extends CharacterBody3D
## Listener: a blind monster that hunts by sound.
## Hears a ping when its ring reaches it, and footsteps inside their (small)
## noise radius. Its head snaps toward the sound first, it pauses in Alert
## (a rising hiss), walks to where the sound came from, searches (head
## sweeping, sniffing), then gives up with a low exhale and patrols again.
## Patrols stop now and then to listen.
## Moves along a navmesh baked at runtime (ai_nav.gd) once it's ready, else in
## straight lines, giving up if a wall blocks it.
## Readable without color: a hunched, long-armed silhouette, and an outline
## that pulses in a heartbeat rhythm (slow while calm, fast while hunting).
## Every sound it makes is 3D: breathing, voice, dragging footsteps, sniffs.

enum Mode { PATROL, LISTEN, ALERT, INVESTIGATE, SEARCH, WANDER, CHASE }

const SOUND_SPEED := 18.0  ## Same as the ping ring speed in the shader.
const BodyRig := preload("res://scripts/ai_listener_body.gd")
const RED := Color(1.0, 0.23, 0.31)
## A director hint never walks it closer to the player than this (meters).
const HINT_STOP_DISTANCE := 6.5
const NEAR_MISS_DIST := 2.0  ## Passing a still / sneaking player this close without catching them.
const HIDE_SNIFF_TIME := 6.0  ## Seconds near a hiding player before it sniffs them out.
## Combat (damage mode): center distance that counts as "touching" (capsules
## can't get closer than ~0.85 m), seconds between hits, and the noise a hit makes.
const ATTACK_RANGE := 1.2
const ATTACK_INTERVAL := 1.0
const ATTACK_NOISE := 14.0
const STAGGER_TIME := 0.4
## Hunting: it locks onto a player it can sense this close (quiet players: closer).
const SIGHT_RANGE := 8.0
const SIGHT_RANGE_QUIET := 3.5
const LOSE_TIME := 3.0  ## Seconds without sight or sound before it loses a chased player.

signal died

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
## Optional patrol route: points relative to the spawn position, walked in a loop.
@export var patrol_points := PackedVector3Array()
## Speed while chasing (the chase listener sprints, but slower than the player's run).
@export var chase_speed := 4.4
## Chase listener: if the player is closer than 9 m when the chase starts, it starts from its home.
@export var chase_reset := false

@export var max_health := 15

@onready var voice: AudioStreamPlayer3D = $Voice
@onready var breath: AudioStreamPlayer3D = $Breath

## Only the very first hunt shows the "run" prompt.
static var _run_prompted := false

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

var _head: Node3D
var _material: ShaderMaterial
var _steps: AudioStreamPlayer3D
var _mouth: AudioStreamPlayer3D
var _agent: NavigationAgent3D
var _nav: Node
var _nav_check := 0.0
var _player: Node3D
var _sounds_ready := false
var _stride := 0.0
var _snap_pause := 0.0
var _gave_chase := false
var _catch_grace := 0.0
var _twitch := 3.0
var _sniff_timer := 1.0
var _sweep_time := 0.0
var _pulse := 0.0
var _hush := 0.0
var _hush_gain := 1.0
var _hush_fade := 0.4
var _hush_boost := 0.0
var _breath_pitch := 1.0
var _breath_db := -6.0
var _uneven_timer := 0.0
var _uneven_pitch := 1.0
var _hold_breath := 0.0
var _wp := 0
var _heard_lure := false
var _lure_thrower := Vector3.ZERO
var _near_pass := false
var _near_cd := 0.0
var _sniff_hide := 0.0
var health := 15
var is_dead := false
## INVESTIGATE: following the player's live position (not just the sound).
var _pursuing := false
var _lose := 0.0
var _sight_check := 0.0
var _seen := false
var _attack_cd := 0.0
var _stagger := 0.0
var _flash := 0.0
## Where it walks this physics step and how fast (set by the mode functions).
var _move_dest := Vector3.ZERO
var _move_speed := 0.0


## Builds the body and sound players, and listens for sounds and game events.
func _ready() -> void:
	health = max_health
	_home = global_position
	# Unpredictable: every Listener moves and breathes a little differently.
	_jitter = randf_range(0.85, 1.15)
	_listen_timer = randf_range(5.0, 11.0)
	_breath_pitch = randf_range(0.8, 1.05)
	_twitch = randf_range(2.0, 5.0)
	_pulse = randf()
	_material = BodyRig.make_material()
	_head = BodyRig.build($Body as Node3D, _material)
	_steps = _make_player(Vector3.ZERO, 18.0, 3.0)
	_mouth = _make_player(Vector3(0.0, 1.5, -0.8), 20.0, 3.0)
	breath.unit_size = 3.0
	breath.max_distance = 22.0
	breath.bus = &"Cave"
	voice.max_distance = 30.0
	voice.unit_size = 4.0
	voice.bus = &"Cave"

	_agent = NavigationAgent3D.new()
	_agent.radius = 0.5
	_agent.height = 2.2
	_agent.path_desired_distance = 0.7
	_agent.target_desired_distance = 0.6
	_agent.avoidance_enabled = false
	add_child(_agent)

	Echo.lures_fooled = 0
	Echo.adapt_announced = false
	Echo.pebble_lure.connect(_on_pebble_lure)
	Game.level_event.connect(_on_level_event)
	Echo.ping_emitted.connect(_on_ping)
	Echo.noise_made.connect(_on_noise)
	Game.player_caught.connect(_on_player_caught)
	Game.game_won.connect(_on_game_won)
	# Sounds are synthesized over the first few frames; start breathing once they exist.
	if Sfx.is_loaded:
		_start_sounds()
	else:
		Sfx.loaded.connect(_start_sounds, CONNECT_ONE_SHOT)


## Makes a 3D sound player attached to the Listener.
func _make_player(pos: Vector3, max_dist: float, unit: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = &"Cave"
	p.max_distance = max_dist
	p.unit_size = unit
	add_child(p)
	p.position = pos
	return p


## Starts the breathing loop once the sounds exist.
func _start_sounds() -> void:
	if _sounds_ready:
		return
	_sounds_ready = true
	breath.stream = Sfx.stream("breath")
	breath.pitch_scale = _breath_pitch
	breath.volume_db = _breath_db
	breath.play(randf() * 2.5)  # out of step with the others
	_steps.stream = Sfx.stream("drag_step")


## True while it is alerted, investigating or chasing.
func is_hunting() -> bool:
	return mode == Mode.ALERT or mode == Mode.INVESTIGATE or mode == Mode.CHASE


## A ping (or noise) happened somewhere: can we hear it?
func _on_ping(origin: Vector3, max_radius: float, loud: bool) -> void:
	if is_dead or not loud:
		return
	if _deaf > 0.0 or mode == Mode.CHASE:
		return
	var d := global_position.distance_to(origin)
	if asleep and d > wake_radius:
		return
	var reach := minf(max_radius, hearing_radius) * _hearing_mult()
	if d > reach:
		return
	# React when the sound actually reaches us, not instantly.
	_heard_origin = origin
	_heard_lure = false
	_hear_delay = d / SOUND_SPEED


## A pebble's ping reached us: remember it was a lure and where it was thrown from.
func _on_pebble_lure(origin: Vector3, thrower: Vector3) -> void:
	if _hear_delay >= 0.0 and _heard_origin.is_equal_approx(origin):
		_heard_lure = true
		_lure_thrower = thrower


## Footsteps and other noises are heard just like pings.
func _on_noise(origin: Vector3, radius: float) -> void:
	_on_ping(origin, radius, true)


## The sound has reached us: turn toward it and start hunting.
func _hear() -> void:
	# Adaptive: after a few fooled hunts, Listeners increasingly ignore the pebble
	# and go to where it was thrown from (where you stand).
	if _heard_lure:
		var ignore_chance := clampf(0.3 * float(Echo.lures_fooled - 2), 0.0, 0.9)
		if Echo.lures_fooled >= 3 and randf() < ignore_chance:
			_heard_origin = _lure_thrower
			if not Echo.adapt_announced:
				Echo.adapt_announced = true
				Game.show_subtitle("They're learning.")
		else:
			Echo.lures_fooled += 1
	_heard_lure = false
	_target = Vector3(_heard_origin.x, global_position.y, _heard_origin.z)
	# The head snaps to the sound before the body moves (a tell for pebble lures).
	_snap_head(_heard_origin)
	var was_asleep := asleep
	asleep = false
	_hold_breath = 0.0
	breath.stream_paused = false
	# Already hunting: retarget after a beat of stillness (no new long pause,
	# or ping spam would freeze it).
	if is_hunting():
		_lose = LOSE_TIME
		if not _pursuing:
			_snap_pause = 0.35
		return
	mode = Mode.ALERT
	_gave_chase = true
	var pause := alert_time * _alert_mult()
	if was_asleep:
		pause *= 1.8
	_alert = pause
	if not hear_lines.is_empty():
		voice.stream = hear_lines.pick_random()
	elif was_asleep:
		voice.stream = Sfx.stream("shriek")
	else:
		voice.stream = Sfx.stream("hiss")
	voice.pitch_scale = randf_range(0.8, 1.0)
	voice.volume_db = 0.0
	voice.play()
	if was_asleep:
		_caption("[a piercing shriek]", 1.5, 40.0)
	else:
		_caption("[a hiss: something heard you]", 1.5, 30.0)
	Game.listener_alerted.emit(global_position)
	_maybe_prompt_run()


## The first time a Listener hunts the player's own noise, teach "run".
func _maybe_prompt_run() -> void:
	if _run_prompted:
		return
	var p := _get_player()
	if p == null or p.global_position.distance_to(_heard_origin) > 4.0:
		return
	_run_prompted = true
	Game.prompt_requested.emit("run")


## Director hint: wander toward the player's rough area (not their exact spot).
func wander_to(p: Vector3) -> bool:
	if asleep or mode != Mode.PATROL:
		return false
	_target = Vector3(p.x, global_position.y, p.z)
	mode = Mode.WANDER
	_gave_chase = false
	return true


## Director release: back off and go deaf for a moment.
func retreat() -> void:
	if asleep or mode == Mode.CHASE:
		return
	mode = Mode.PATROL
	_hear_delay = -1.0
	_deaf = 4.0
	_gave_chase = false


## Director: go quiet (breathing and footsteps) for `seconds`, then fade back
## in over `fade_in` seconds. `boost_db` makes the breathing louder than usual
## for a while afterwards.
func hush(seconds: float, fade_in: float = 2.5, boost_db: float = 0.0) -> void:
	_hush = seconds
	_hush_fade = 1.0 / maxf(fade_in, 0.05)
	_hush_boost = boost_db


## The player was caught: back off and give them time to respawn.
func _on_player_caught() -> void:
	if mode == Mode.CHASE:
		Game.level_event.emit("chase_end")
	_near_pass = false
	_sniff_hide = 0.0
	_pursuing = false
	mode = Mode.PATROL
	_hear_delay = -1.0
	_deaf = 3.0
	_catch_grace = 3.5  # respawn grace
	_gave_chase = false
	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(_clear_checkpoint)


## Respawn grace: don't be waiting at the checkpoint when the player comes back.
func _clear_checkpoint() -> void:
	var cp := Game.checkpoint_position
	var d := global_position.distance_to(cp)
	if d < 8.0 and _home.distance_to(cp) > d:
		global_position = _home
		velocity = Vector3.ZERO


## The game is won: go quiet and stop hunting for good.
func _on_game_won() -> void:
	if mode == Mode.CHASE:
		Game.level_event.emit("chase_end")
	mode = Mode.PATROL
	_hear_delay = -1.0
	_deaf = 9999.0
	hush(9999.0)


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_flash = maxf(_flash - delta * 4.0, 0.0)
	if _stagger > 0.0:
		# Staggered by a stab: rooted for a moment, can't attack.
		_stagger -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		return
	_deaf = maxf(_deaf - delta, 0.0)
	_catch_grace = maxf(_catch_grace - delta, 0.0)
	_snap_pause = maxf(_snap_pause - delta, 0.0)
	if _hear_delay >= 0.0:
		_hear_delay -= delta
		if _hear_delay < 0.0:
			_hear()
	if not is_on_floor():
		velocity.y -= _gravity * delta

	# By default it stands still. Each mode below can change this.
	_move_dest = global_position
	_move_speed = 0.0
	# Difficulty and this Listener's own small speed difference.
	var pace := _speed_mult() * _jitter
	match mode:
		Mode.PATROL:
			_do_patrol(delta, pace)
		Mode.LISTEN:
			_do_listen(delta)
		Mode.ALERT:
			_do_alert(delta)
		Mode.INVESTIGATE:
			_do_investigate(delta, pace)
		Mode.WANDER:
			_do_wander(pace)
		Mode.CHASE:
			_do_chase(pace)
		Mode.SEARCH:
			_do_search(delta)
	_move(_move_dest, _move_speed, delta)
	_check_stuck(delta, _move_speed)
	_update_breath(delta)
	_check_catch()
	_track_hidden_player(delta)
	_track_near_miss(delta)


# ---------------------------------------------------------------- Modes

## PATROL: walk the route (or back and forth), stopping now and then to listen.
func _do_patrol(delta: float, pace: float) -> void:
	if asleep:
		return
	var has_route := patrol_points.size() > 0
	if has_route:
		# Walk the patrol points in a loop.
		var index := _wp % patrol_points.size()
		_move_dest = _home + patrol_points[index]
		if _flat_dist(_move_dest) < 0.6:
			_wp = (_wp + 1) % patrol_points.size()
	else:
		# Walk back and forth between home and home + patrol_offset.
		if _to_far:
			_move_dest = _home + patrol_offset
		else:
			_move_dest = _home
		if _flat_dist(_move_dest) < 0.5:
			_to_far = not _to_far
	_move_speed = patrol_speed * pace

	# Time to stop and listen? (Only Listeners that actually patrol.)
	_listen_timer -= delta
	var does_patrol := patrol_offset != Vector3.ZERO or has_route
	if _listen_timer <= 0.0 and does_patrol:
		mode = Mode.LISTEN
		_search = randf_range(1.2, 2.6)


## LISTEN: stops dead; its head sweeps and it sniffs. Hold your breath.
func _do_listen(delta: float) -> void:
	_search -= delta
	if _search <= 0.0:
		mode = Mode.PATROL
		_listen_timer = randf_range(5.0, 12.0)


## ALERT: turn toward the sound for a moment, then go investigate.
func _do_alert(delta: float) -> void:
	_turn_toward(_target, delta, 4.0)
	_alert -= delta
	if _alert <= 0.0:
		mode = Mode.INVESTIGATE


## INVESTIGATE: walk to the sound (or follow the player if it can sense them).
func _do_investigate(delta: float, pace: float) -> void:
	_update_pursuit(delta)
	_move_dest = _target
	if _snap_pause <= 0.0:
		_move_speed = investigate_speed * pace
	if _pursuing:
		# Closing in: stop pushing once it's in reach.
		if _flat_dist(_move_dest) < ATTACK_RANGE * 0.8:
			_move_speed = 0.0
			_turn_toward(_move_dest, delta, 8.0)
	elif _flat_dist(_move_dest) < 0.8:
		# Reached the spot: look around.
		_begin_search(search_time * randf_range(0.75, 1.5))


## WANDER: a director hint, walking toward the player's rough area.
func _do_wander(pace: float) -> void:
	_move_dest = _target
	_move_speed = patrol_speed * 1.3 * pace
	if _flat_dist(_move_dest) < 1.0:
		_begin_search(2.5)
		return
	# A hint never walks it into the player's face unseen.
	var p := _get_player()
	if p != null and _flat_dist(p.global_position) < HINT_STOP_DISTANCE:
		_begin_search(2.5)


## CHASE: sprint straight at the player until they hide or get far away.
func _do_chase(pace: float) -> void:
	var p := _get_player()
	if p == null:
		mode = Mode.PATROL
		return
	_move_dest = p.global_position
	_move_speed = chase_speed * pace
	var dist := _flat_dist(p.global_position)
	if p.call("is_hidden") == true and dist < 8.0:
		stop_chase(true)
	elif dist > 45.0:
		stop_chase(false)


## SEARCH: turn slowly on the spot; pounce if it senses the player, else give up.
func _do_search(delta: float) -> void:
	_search -= delta
	rotate_y(delta * 0.7)
	if _gave_chase and _can_sense_player():
		_start_pursuit()
	elif _search <= 0.0:
		_end_search()


## Every frame: the pulsing outline color, and the head animation.
func _process(delta: float) -> void:
	# Outline rhythm (readable without color): a double pulse, slow while
	# calm, quick while hunting, very slow while asleep.
	var rate := 0.7
	if asleep:
		rate = 0.35
	elif is_hunting():
		rate = 2.1
	elif mode == Mode.SEARCH or mode == Mode.LISTEN or mode == Mode.WANDER:
		rate = 1.2
	_pulse = fmod(_pulse + delta * rate, 1.0)

	# A heartbeat shape: one strong beat at the start, a smaller one just after.
	var first_beat := exp(-_pulse * 10.0)
	var second_beat := 0.6 * exp(-absf(_pulse - 0.25) * 18.0)
	var beat := minf(first_beat + second_beat, 1.0)
	if is_dead:
		beat = 0.0
	var col := RED * (0.6 + 0.7 * beat)
	if _flash > 0.0:
		# Hurt flash: blend toward white.
		var flash_amount := clampf(_flash, 0.0, 1.0)
		col = col.lerp(Color(1.6, 1.6, 1.6), flash_amount)
	_material.set_shader_parameter("echo_color", col)
	if is_dead:
		return
	_animate_head(delta)


## Stop and look around for `seconds`.
func _begin_search(seconds: float) -> void:
	_pursuing = false
	if is_hunting() and mode != Mode.CHASE:
		_thud()
	mode = Mode.SEARCH
	_search = seconds
	_sniff_timer = randf_range(0.3, 0.8)


## Searching is over: go back to patrolling.
func _end_search() -> void:
	mode = Mode.PATROL
	_pursuing = false
	if not _gave_chase:
		return
	_gave_chase = false
	# Gives up: a low, disappointed exhale (distinct from the hunting hiss).
	if _mouth.stream != Sfx.stream("exhale"):
		_mouth.stream = Sfx.stream("exhale")
	_mouth.pitch_scale = randf_range(0.85, 1.0)
	_mouth.volume_db = -2.0
	_mouth.play()
	_caption("[a low exhale: it gave up]", 2.0, 22.0)


## Walks toward `dest` at `speed` and plays a footstep every stride.
func _move(dest: Vector3, speed: float, delta: float) -> void:
	var goal := dest
	if speed > 0.0:
		goal = _path_point(dest)
	var to := goal - global_position
	to.y = 0.0
	var move := Vector3.ZERO
	if speed > 0.0 and to.length() > 0.1:
		move = to.normalized() * speed
		_turn_toward(goal, delta, 6.0)
	velocity.x = move.x
	velocity.z = move.z
	move_and_slide()
	# Heavy dragging footsteps, one per stride, synced to how far it moved.
	var moved := get_real_velocity()
	var flat_speed := Vector2(moved.x, moved.z).length()
	_stride += flat_speed * delta
	var stride_len := 0.9
	if is_hunting():
		stride_len = 1.2
	if _stride >= stride_len:
		_stride = 0.0
		_footstep()


## Next point to walk toward: along the navmesh when one is ready, else straight.
func _path_point(dest: Vector3) -> Vector3:
	if not _nav_ready():
		return dest
	if _agent.target_position.distance_to(dest) > 0.3:
		_agent.target_position = dest
	if _agent.is_navigation_finished():
		return dest
	return _agent.get_next_path_position()


## True once the navmesh is baked. Looks for the AiNav node about once a second.
func _nav_ready() -> bool:
	if _nav == null or not is_instance_valid(_nav):
		_nav = null
		_nav_check -= get_physics_process_delta_time()
		if _nav_check > 0.0:
			return false
		_nav_check = 1.0
		_nav = get_tree().get_first_node_in_group("ai_nav")
		if _nav == null:
			return false
	return _nav.get("nav_ready") == true


## If a wall blocks it, give up and search.
func _check_stuck(delta: float, speed: float) -> void:
	if mode == Mode.CHASE:
		_stuck = 0.0
		return
	if speed > 0.0 and get_real_velocity().length() < 0.2:
		_stuck += delta
		if _stuck > 1.5:
			_stuck = 0.0
			if mode == Mode.PATROL:
				_to_far = not _to_far
				_wp += 1
			else:
				_begin_search(2.0)
	else:
		_stuck = 0.0


## One heavy dragging footstep (heavier while hunting).
func _footstep() -> void:
	if _steps.stream == null or _hush_gain < 0.05:
		return
	var pitch := randf_range(0.85, 1.05)
	var volume := -7.0
	if is_hunting():
		pitch = pitch * 1.12
		volume = -3.0
	_steps.pitch_scale = pitch
	_steps.volume_db = volume + _hush_db()
	_steps.play()
	_caption("[heavy dragging footsteps]", 6.0, 14.0)


## The hush as a volume change in decibels (0 = normal, very low = silent).
func _hush_db() -> float:
	return linear_to_db(maxf(_hush_gain, 0.001))


## Breathing gets louder and faster as it hunts, slower while asleep.
func _update_breath(delta: float) -> void:
	# Hush (the Hall's sudden silence): fade out fast, then back in slowly.
	if _hush > 0.0:
		_hush -= delta
		_hush_gain = move_toward(_hush_gain, 0.0, delta * 4.0)
	else:
		_hush_gain = move_toward(_hush_gain, 1.0, delta * _hush_fade)
		_hush_boost = move_toward(_hush_boost, 0.0, delta * 0.5)
	var want_db := -6.0
	var want_pitch := _breath_pitch
	var pitch_rate := 2.5
	if asleep:
		var uneven := _sleeper_unease(delta)
		want_db = -11.0 + 5.0 * uneven
		want_pitch = _breath_pitch * 0.85 * _uneven_pitch
		pitch_rate = 8.0
	elif is_hunting():
		# Hunting: louder, faster, ragged.
		want_db = -1.5
		want_pitch = _breath_pitch * 1.4
	elif mode == Mode.SEARCH or mode == Mode.LISTEN:
		want_db = -3.5
		want_pitch = _breath_pitch * 1.15
	_breath_db = lerpf(_breath_db, want_db, minf(delta * 3.0, 1.0))
	breath.volume_db = _breath_db + _hush_db() + _hush_boost
	breath.pitch_scale = lerpf(breath.pitch_scale, want_pitch, minf(delta * pitch_rate, 1.0))
	if not asleep and _hush_gain > 0.5 and _sounds_ready:
		_caption("[heavy breathing nearby]", 10.0, 9.0)


## The Sleeper's breathing turns uneven as the player creeps within ~6 m:
## its pitch wavers and now and then it catches its breath.
func _sleeper_unease(delta: float) -> float:
	var p := _get_player()
	var uneven := 0.0
	if p != null:
		var dist := global_position.distance_to(p.global_position)
		uneven = clampf((6.0 - dist) / 4.0, 0.0, 1.0)
	if _hold_breath > 0.0:
		_hold_breath -= delta
		if _hold_breath <= 0.0:
			breath.stream_paused = false
	_uneven_timer -= delta
	if _uneven_timer <= 0.0:
		_uneven_timer = randf_range(0.3, 0.8)
		_uneven_pitch = 1.0 + randf_range(-0.12, 0.2) * uneven
		if uneven > 0.3 and _hold_breath <= 0.0 and randf() < 0.3 * uneven:
			_hold_breath = randf_range(0.25, 0.7)
			breath.stream_paused = true
		if uneven > 0.4:
			_caption("[uneven breathing, very close]", 8.0, 8.0)
	return uneven


## Turns the head: toward the sound while hunting, sweeping while searching,
## and the odd sudden twitch otherwise.
func _animate_head(delta: float) -> void:
	if _head == null:
		return
	var want := 0.0
	var tilt := 0.0
	var rate := 5.0
	match mode:
		Mode.ALERT, Mode.INVESTIGATE, Mode.CHASE:
			want = _local_yaw(_target)
			rate = 8.0
		Mode.SEARCH, Mode.LISTEN:
			# Visible search: the head sweeps side to side, nose down, sniffing.
			_sweep_time += delta
			want = sin(_sweep_time * 1.9) * 1.1
			tilt = 0.25 + 0.15 * sin(_sweep_time * 3.1)
			rate = 4.0
			_sniff_timer -= delta
			if _sniff_timer <= 0.0:
				_sniff_timer = randf_range(1.1, 2.0)
				_sniff()
		_:
			if not asleep:
				_twitch -= delta
				if _twitch <= 0.0:
					_twitch = randf_range(2.0, 5.0)
					_head.rotation.y = randf_range(-0.6, 0.6)  # a sudden jerk of the head
	var blend := minf(rate * delta, 1.0)
	_head.rotation.y = lerp_angle(_head.rotation.y, want, blend)
	_head.rotation.x = lerpf(_head.rotation.x, -tilt, blend)


## A sniffing sound (if its mouth isn't already busy).
func _sniff() -> void:
	if _mouth.playing or _hush_gain < 0.3:
		return
	_mouth.stream = Sfx.stream("sniff")
	_mouth.pitch_scale = randf_range(0.85, 1.1)
	_mouth.volume_db = -4.0
	_mouth.play()
	_caption("[sniffing]", 5.0, 12.0)


## Instantly turns the head toward world point p.
func _snap_head(p: Vector3) -> void:
	if _head:
		_head.rotation.y = _local_yaw(p)


## Head yaw (relative to the body) that faces world point p, within the neck's reach.
func _local_yaw(p: Vector3) -> float:
	var offset := p - global_position
	var local := global_basis.inverse() * offset
	if Vector2(local.x, local.z).length() < 0.1:
		return 0.0
	return clampf(atan2(-local.x, -local.z), -1.3, 1.3)


## Turns the whole body toward point p, `rate` sets how fast.
func _turn_toward(p: Vector3, delta: float, rate: float) -> void:
	var to := p - global_position
	to.y = 0.0
	if to.length() < 0.1:
		return
	var want := atan2(-to.x, -to.z)
	global_rotation.y = lerp_angle(global_rotation.y, want, minf(rate * delta, 1.0))


## Distance to p, ignoring height.
func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


## The player node (looked up again if it was freed).
func _get_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


## Caption only when the player is close enough to hear it.
func _caption(text: String, gap: float, max_dist: float) -> void:
	var p := _get_player()
	if p != null and p.global_position.distance_to(global_position) <= max_dist:
		Sfx.caption(text, global_position, gap)


## Difficulty: how fast Listeners move.
func _speed_mult() -> float:
	if Settings.assist_mode:
		return 0.8
	if Settings.hard_mode:
		return 1.15
	return 1.0


## Difficulty: how far Listeners hear.
func _hearing_mult() -> float:
	if Settings.assist_mode:
		return 0.75
	return 1.0


## Difficulty: how long Listeners pause before hunting.
func _alert_mult() -> float:
	if Settings.assist_mode:
		return 1.6
	if Settings.hard_mode:
		return 0.65
	return 1.0


## Is the player within reach? Catch them (or attack them in damage mode).
func _check_catch() -> void:
	if Game.state != Game.State.PLAYING or _catch_grace > 0.0:
		return
	var p := _get_player()
	if p == null:
		return
	if p.call("is_hidden") == true:
		return  # hiding and quiet: it can't see or catch you
	if Game.damage_enabled():
		_try_attack(p)
		return
	var reach := catch_distance
	if Settings.assist_mode:
		reach = catch_distance * 0.8
	reach += 0.4
	if _flat_dist(p.global_position) >= reach:
		return
	if absf(p.global_position.y - global_position.y) >= 2.0:
		return
	# Fair catches only: it can't reach you through rock.
	if not _clear_line(p):
		return
	if not Settings.skip_jumpscare:
		voice.stream = Sfx.stream("hiss")
		voice.pitch_scale = 0.7
		voice.volume_db = 0.0
		voice.play()
	Game.catch_player(global_position)


# ---------------------------------------------------------------- Chase, hiding, near misses

## The scripted chase starts or ends.
func _on_level_event(event_name: String) -> void:
	if event_name == "chase" and is_in_group("chase_listener"):
		start_chase()
	elif event_name == "chase_end" and mode == Mode.CHASE:
		stop_chase(true)


## The scripted chase: it wakes, roars and sprints straight at the player.
func start_chase() -> void:
	if mode == Mode.CHASE or Game.state != Game.State.PLAYING:
		return
	var p := _get_player()
	if p == null:
		return
	if chase_reset and _flat_dist(p.global_position) < 9.0:
		global_position = _home
		velocity = Vector3.ZERO
	asleep = false
	mode = Mode.CHASE
	_gave_chase = true
	_hear_delay = -1.0
	_deaf = 0.0
	_catch_grace = 0.6
	_hold_breath = 0.0
	breath.stream_paused = false
	_snap_head(p.global_position)
	voice.stream = Sfx.stream("listener_roar")
	voice.pitch_scale = randf_range(0.85, 0.95)
	voice.volume_db = 3.0
	voice.play()
	_caption("[a roar: it is running at you]", 1.0, 60.0)
	Game.listener_alerted.emit(global_position)
	Game.level_event.emit("chase_start")


## Ends the chase (and searches the area if `search` is true).
func stop_chase(search: bool) -> void:
	if mode != Mode.CHASE:
		return
	mode = Mode.PATROL
	Game.level_event.emit("chase_end")
	if search:
		_begin_search(6.0)


## A hunting Listener stopping near you: one heavy, quiet thud.
func _thud() -> void:
	var p := _get_player()
	if p == null or p.global_position.distance_to(global_position) > 10.0:
		return
	Sfx.play_3d("impact", global_position, -14.0, &"Cave", randf_range(0.7, 0.9), 4.0, 25.0)
	if p.has_method("thump"):
		p.call("thump", 0.5)


## A hiding player is found if it lingers near them for HIDE_SNIFF_TIME seconds.
func _track_hidden_player(delta: float) -> void:
	var p := _get_player()
	if p == null or asleep or Game.state != Game.State.PLAYING:
		return
	var searching := false
	if mode == Mode.SEARCH or mode == Mode.INVESTIGATE:
		searching = true
	if mode == Mode.ALERT or mode == Mode.LISTEN:
		searching = true
	var hidden_close_by: bool = p.call("is_hidden") == true and _flat_dist(p.global_position) < 3.0
	if hidden_close_by and searching:
		# Holding your breath makes it take twice as long.
		var rate := 1.0
		if p.get("holding_breath") == true:
			rate = 0.5
		_sniff_hide += delta * rate
		if _sniff_hide >= HIDE_SNIFF_TIME:
			_sniff_hide = 0.0
			p.call("expose_hidden")
			_sniff()
			_caption("[a long sniff: it found you]", 2.0, 12.0)
			_heard_origin = p.global_position
			_heard_lure = false
			_hear_delay = -1.0
			_hear()
	else:
		_sniff_hide = maxf(_sniff_hide - delta * 0.5, 0.0)


## Walks right past a still / sneaking / hidden player without catching them.
func _track_near_miss(delta: float) -> void:
	_near_cd = maxf(_near_cd - delta, 0.0)
	var p := _get_player()
	if p == null or asleep or Game.state != Game.State.PLAYING:
		_near_pass = false
		return
	var d := _flat_dist(p.global_position)
	var same_level := absf(p.global_position.y - global_position.y) < 2.0
	var walked_away := d > NEAR_MISS_DIST + 1.5 or not same_level
	if d < NEAR_MISS_DIST and same_level and p.call("is_quiet") == true:
		_near_pass = true
	elif _near_pass and walked_away:
		_near_pass = false
		if _near_cd <= 0.0:
			_near_cd = 20.0
			Game.add_stat("near_misses")
			Game.level_event.emit("near_miss")


# ---------------------------------------------------------------- Hunting (sight)

## Can it sense the player right now: close, same floor, nothing in between,
## not hidden. Quiet players (sneaking, still, holding breath) only up close.
func _can_sense_player() -> bool:
	var p := _get_player()
	if p == null or Game.state != Game.State.PLAYING:
		return false
	if p.call("is_hidden") == true:
		return false
	var range_m := SIGHT_RANGE
	if p.call("is_quiet") == true:
		range_m = SIGHT_RANGE_QUIET
	if Settings.assist_mode:
		range_m *= 0.8
	elif Settings.hard_mode:
		range_m *= 1.15
	if _flat_dist(p.global_position) > range_m:
		return false
	if absf(p.global_position.y - global_position.y) > 2.5:
		return false
	return _clear_line(p)


## True if no rock is between its head and the player's chest.
func _clear_line(p: Node3D) -> bool:
	var from := global_position + Vector3.UP * 1.2
	var to := p.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


## Starts following the player's live position.
func _start_pursuit() -> void:
	var p := _get_player()
	if p == null:
		return
	if not _pursuing:
		_snap_head(p.global_position)
	mode = Mode.INVESTIGATE
	_gave_chase = true
	_pursuing = true
	_lose = LOSE_TIME
	_target = Vector3(p.global_position.x, global_position.y, p.global_position.z)


## While hunting: chase the player's live position once it senses them; after
## LOSE_TIME without sight or sound, walk to where they were last and search.
func _update_pursuit(delta: float) -> void:
	_sight_check -= delta
	if _sight_check <= 0.0:
		_sight_check = 0.15
		_seen = _can_sense_player()
		if _seen:
			_start_pursuit()
	if not _pursuing:
		return
	if not _seen:
		_lose -= delta
	var p := _get_player()
	if p == null or p.call("is_hidden") == true:
		_pursuing = false  # last known position stays the target
		return
	if _lose > 0.0:
		_target = Vector3(p.global_position.x, global_position.y, p.global_position.z)
	else:
		_pursuing = false  # lost them: go to the last known spot, then search


# ---------------------------------------------------------------- Combat

## Damage mode: within ~a foot of touching, with a clear line, it hits every
## ATTACK_INTERVAL seconds (2 damage per second, less as the player weakens).
func _try_attack(p: Node3D) -> void:
	if _attack_cd > 0.0 or asleep:
		return
	if _flat_dist(p.global_position) > ATTACK_RANGE:
		return
	if absf(p.global_position.y - global_position.y) >= 2.0:
		return
	if not _clear_line(p):
		return
	_attack_cd = ATTACK_INTERVAL
	var dmg := Game.listener_hit_damage()
	Sfx.play_3d("listener_attack", global_position + Vector3.UP * 1.4, 0.0, &"Cave", randf_range(0.9, 1.05), 5.0, 40.0)
	Sfx.caption("[a slash: it is tearing at you]", global_position, 1.0)
	if p.has_method("thump"):
		p.call("thump", 1.0)
	# Every hit is loud: it draws the others in.
	Echo.make_noise(p.global_position, ATTACK_NOISE)
	_hear_delay = -1.0  # it doesn't need to "hear" its own attack
	if mode != Mode.CHASE:
		_start_pursuit()
	Game.damage_player(dmg, global_position)


## Hurt by the player's dagger: stagger, flash, cry out; dies at 0.
func take_damage(amount: int, from: Vector3 = Vector3.ZERO) -> void:
	if is_dead or amount <= 0:
		return
	health = maxi(health - amount, 0)
	_flash = 1.0
	if health <= 0:
		die()
		return
	_stagger = STAGGER_TIME
	asleep = false
	Sfx.play_3d("listener_hurt", global_position + Vector3.UP * 1.4, 0.0, &"Cave", randf_range(0.9, 1.1), 5.0, 35.0)
	_caption("[a pained screech]", 0.5, 40.0)
	# It knows exactly where you are now.
	if mode != Mode.CHASE:
		_heard_origin = from
		_hear_delay = -1.0
		_start_pursuit()


## Killed: stop everything, tell the game, and collapse into the floor.
func die() -> void:
	if is_dead:
		return
	is_dead = true
	health = 0
	if mode == Mode.CHASE:
		Game.level_event.emit("chase_end")
	mode = Mode.PATROL
	_pursuing = false
	velocity = Vector3.ZERO
	remove_from_group("listener")
	remove_from_group("chase_listener")
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		shape.set_deferred("disabled", true)
	breath.stop()
	voice.stop()
	_steps.stop()
	Sfx.play_3d("listener_death", global_position + Vector3.UP * 1.2, 2.0, &"Cave", randf_range(0.85, 0.95), 6.0, 50.0)
	_caption("[a long dying shriek]", 0.5, 60.0)
	Game.add_stat("kills")
	Game.listener_killed.emit(global_position)
	died.emit()
	# Collapse: the body freezes, pitches over and sinks into the floor.
	var body := get_node_or_null("Body") as Node3D
	if body != null:
		_collapse(body)
	set_physics_process(false)


## The death animation: the body freezes, pitches over and sinks into the floor.
func _collapse(body: Node3D) -> void:
	body.process_mode = Node.PROCESS_MODE_DISABLED
	var tw := create_tween()
	tw.set_parallel(true)

	# These three play at the same time.
	var fall_over: PropertyTweener = tw.tween_property(body, "rotation:x", deg_to_rad(-85.0), 0.7)
	fall_over.set_trans(Tween.TRANS_QUAD)
	fall_over.set_ease(Tween.EASE_IN)
	var drop: PropertyTweener = tw.tween_property(body, "position:y", -0.3, 0.9)
	drop.set_trans(Tween.TRANS_QUAD)
	drop.set_ease(Tween.EASE_IN)
	tw.tween_property(body, "scale", Vector3(1.0, 0.6, 1.0), 0.9)

	# Then, after 3 more seconds, it slowly sinks out of sight.
	tw.chain()
	var sink: PropertyTweener = tw.tween_property(body, "position:y", -1.4, 6.0)
	sink.set_delay(3.0)
