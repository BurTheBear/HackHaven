extends Node
## The horror director. Created by main.gd. Ideas taken from good horror games:
## - Alien: Isolation: a director that knows roughly where you are and nudges a
##   Listener toward that area, plus a "menace gauge" that backs the Listeners
##   off after too long under pressure (tension, then release).
## - Dead Space "fear emitters": the closer a Listener is, the faster your
##   heartbeat, the redder the screen edges, the more the camera trembles.
## - Amnesia / P.T.: false scares. Sounds in the dark that might be nothing, and
##   phantom red shapes in your echo that are gone on the next ping.

const DREAD_NEAR := 3.0
const DREAD_FAR := 18.0
const MENACE_MAX := 10.0  ## Seconds of high dread before the Listeners back off.
const FALSE_SCARES := ["drip", "scrape", "knock", "drip", "breath"]

var player: Node3D
var ui: Node
var dread := 0.0

var _menace := 0.0
var _beat_timer := 0.0
var _hint_timer := 25.0
var _scare_timer := 12.0
var _quiet_time := 0.0
var _run_time := 0.0
var _phantom_time := 0.0
var _drone: AudioStreamPlayer
var _heart: AudioStreamPlayer
var _phantom: MeshInstance3D


func setup(p: Node3D, u: Node) -> void:
	player = p
	ui = u


func _ready() -> void:
	_drone = AudioStreamPlayer.new()
	_drone.stream = Sfx.stream("drone")
	_drone.bus = &"Ambience"
	_drone.volume_db = -18.0
	add_child(_drone)
	_heart = AudioStreamPlayer.new()
	_heart.stream = Sfx.stream("heartbeat")
	add_child(_heart)

	_phantom = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.height = 2.2
	mesh.radius = 0.5
	_phantom.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/reveal.gdshader")
	mat.set_shader_parameter("echo_color", Color(1.0, 0.23, 0.31))
	mat.set_shader_parameter("grid_scale", 3.0)
	mat.set_shader_parameter("near_glow", 0.0)
	_phantom.material_override = mat
	_phantom.visible = false
	add_child(_phantom)

	Echo.ping_emitted.connect(_on_ping)
	Game.player_caught.connect(_on_caught)
	Game.checkpoint_reached.connect(func(): _menace = 0.0)
	Game.game_won.connect(_on_won)


func _process(delta: float) -> void:
	if player == null or Game.state != Game.State.PLAYING:
		dread = move_toward(dread, 0.0, delta)
		_apply(delta)
		return
	if not _drone.playing:
		_drone.play()
	_run_time += delta
	_quiet_time += delta

	var listeners := get_tree().get_nodes_in_group("listener")
	var nearest := INF
	for l in listeners:
		var d: float = l.global_position.distance_to(player.global_position)
		if l.asleep:
			d *= 1.6  # A sleeping one is less of a threat.
		nearest = minf(nearest, d)
	var target := clampf(1.0 - (nearest - DREAD_NEAR) / (DREAD_FAR - DREAD_NEAR), 0.0, 1.0)
	dread = move_toward(dread, target, delta * 1.5)

	# Menace gauge: too long under high pressure, so ease off for a moment.
	if dread > 0.5:
		_menace += delta * dread
	else:
		_menace = maxf(_menace - delta * 0.5, 0.0)
	if _menace > MENACE_MAX:
		_menace = 0.0
		for l in listeners:
			if l.global_position.distance_to(player.global_position) < 14.0:
				l.retreat()

	# Hints: quiet players get a visitor wandering toward their general area.
	_hint_timer -= delta
	if _hint_timer <= 0.0:
		_hint_timer = randf_range(18.0, 32.0)
		if dread < 0.15 and _quiet_time > 12.0:
			_send_hint(listeners)

	_scare_timer -= delta
	if _scare_timer <= 0.0:
		_scare_timer = randf_range(10.0, 24.0)
		_false_scare()

	if _phantom_time > 0.0:
		_phantom_time -= delta
		if _phantom_time <= 0.0:
			_phantom.visible = false
	_apply(delta)


func _apply(delta: float) -> void:
	if dread > 0.08:
		_beat_timer -= delta
		if _beat_timer <= 0.0:
			_beat_timer = lerpf(1.1, 0.38, dread)
			_heart.volume_db = lerpf(-22.0, 0.0, dread)
			_heart.play()
	else:
		_beat_timer = 0.0
	_drone.volume_db = lerpf(-18.0, -8.0, dread)
	if player:
		player.shake = dread * dread * 0.025
	if ui:
		ui.set_dread(dread)


func _on_ping(origin: Vector3, _radius: float, loud: bool) -> void:
	if player == null or not loud or origin.distance_to(player.global_position) > 2.0:
		return
	_quiet_time = 0.0
	# Phantom: now and then your echo shows a Listener that isn't there.
	if _run_time > 40.0 and dread < 0.3 and randf() < 0.15:
		var p: Variant = _open_point(7.0, 14.0)
		if p != null:
			_phantom.global_position = Vector3(p.x, player.global_position.y + 1.1, p.z)
			_phantom.visible = true
			_phantom_time = 3.0


func _send_hint(listeners: Array) -> void:
	for l in listeners:
		if l.asleep:
			continue
		var dist: float = l.global_position.distance_to(player.global_position)
		if dist < 8.0 or dist > 35.0:
			continue
		var dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
		var p := player.global_position + dir * randf_range(4.0, 7.0)
		if _clear(l.global_position + Vector3.UP, p + Vector3.UP) and l.wander_to(p):
			return


func _false_scare() -> void:
	var p: Variant = _open_point(8.0, 16.0)
	if p == null:
		return
	var s := AudioStreamPlayer3D.new()
	s.stream = Sfx.stream(FALSE_SCARES.pick_random())
	s.bus = &"Cave"
	s.unit_size = 4.0
	s.max_distance = 30.0
	s.volume_db = -4.0
	s.pitch_scale = randf_range(0.8, 1.1)
	get_parent().add_child(s)
	s.global_position = p
	s.finished.connect(s.queue_free)
	s.play()


func _on_caught() -> void:
	_menace = 0.0
	Sfx.play("sting", 2.0)
	# Jump scare: light up the thing that got you, right in your face.
	Echo.emit_ping(Game.catcher_position + Vector3.UP * 1.2, 5.0, false)
	if ui:
		ui.flash_red()


func _on_won() -> void:
	_drone.stop()
	_heart.stop()
	dread = 0.0


## A random open spot min_d..max_d from the player, or null.
func _open_point(min_d: float, max_d: float) -> Variant:
	var from := player.global_position + Vector3.UP * 1.2
	for attempt in 4:
		var a := randf() * TAU
		var dir := Vector3(sin(a), 0.0, cos(a))
		var to := from + dir * max_d
		var hit := player.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, to, 1))
		var end := to
		if hit:
			end = (hit["position"] as Vector3) - dir * 0.8
		if from.distance_to(end) >= min_d:
			return end
	return null


func _clear(a: Vector3, b: Vector3) -> bool:
	var hit := player.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(a, b, 1))
	return hit.is_empty()
