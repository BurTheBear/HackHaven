extends RigidBody3D
## Thrown pebble: its first bounces each send out a smaller (loud) ping.
## Leaves a short gold trail in flight and tidies itself up once it has come
## to rest (or fallen out of the level).

const PING_RADIUS := 10.0
const ECHO_BOUNCES := 2
const LIFETIME := 10.0  ## Upper bound: always gone after this long.
const KILL_Y := -3.0
const REST_TIME := 3.0  ## Seconds lying still before it's cleaned up.
const FADE_TIME := 0.4
const TRAIL_MIN_SPEED := 1.0
const TRAIL_COLOR := Color(1.0, 0.82, 0.35, 0.9)

@onready var click: AudioStreamPlayer3D = $Click
@onready var _mesh: Node3D = $Mesh

## Where the player stood when throwing (Listeners that have learned go there).
var throw_origin := Vector3.ZERO
var _bounces := 0
var _roll_timer := 0.0
var _cooldown := 0.0
var _life := LIFETIME
var _rest := 0.0
var _fading := false
var _trail: CPUParticles3D


## Sets up the click sound, collision reporting and the trail.
func _ready() -> void:
	if click.stream == null:
		click.stream = Sfx.stream("pebble")
	click.unit_size = 4.0
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	body_entered.connect(_on_body_entered)
	_trail = _make_trail()
	add_child(_trail)


## Every physics step: rolling clicks, the trail, and cleaning up when done.
func _physics_process(delta: float) -> void:
	_cooldown -= delta
	_life -= delta

	# Fell out of the level: remove it right away.
	if global_position.y < KILL_Y:
		queue_free()
		return
	if _fading:
		return

	var speed := linear_velocity.length()
	_play_roll_click(speed, delta)

	# Only show the trail while it is flying fast.
	var want_trail := false
	if speed > TRAIL_MIN_SPEED:
		want_trail = true
	if _trail.emitting != want_trail:
		_trail.emitting = want_trail

	# Count how long it has been lying still.
	if sleeping or speed < 0.1:
		_rest += delta
	else:
		_rest = 0.0
	if _rest >= REST_TIME or _life <= 0.0:
		_fade_out()


## Soft, quick clicks while it rolls slowly along the floor.
func _play_roll_click(speed: float, delta: float) -> void:
	_roll_timer -= delta
	if speed <= 0.35 or speed >= 3.0:
		return
	if get_contact_count() == 0:
		return
	if _roll_timer > 0.0:
		return
	_roll_timer = randf_range(0.1, 0.18)
	click.pitch_scale = randf_range(1.4, 1.9)
	click.volume_db = -24.0
	click.play()


## Hit something: click (louder for harder hits), and the first bounces ping.
func _on_body_entered(_body: Node) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = 0.07
	var hit := clampf(linear_velocity.length() / 8.0, 0.0, 1.0)
	if click.stream:
		click.pitch_scale = randf_range(0.75, 1.35)
		click.volume_db = lerpf(-16.0, -2.0, hit)
		click.play()
	if _bounces < ECHO_BOUNCES:
		_bounces += 1
		Echo.emit_ping(global_position, PING_RADIUS, true, true)
		Echo.pebble_lure.emit(global_position, throw_origin)


## Shrink away, then free.
func _fade_out() -> void:
	_fading = true
	_trail.emitting = false
	var tween := create_tween()
	tween.tween_property(_mesh, "scale", Vector3.ZERO, FADE_TIME)
	tween.tween_callback(queue_free)


## Tiny fading gold specks left behind in world space while the pebble flies.
func _make_trail() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Trail"
	p.emitting = false
	p.amount = 28
	p.lifetime = 0.45
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0.0, -0.4, 0.0)
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.15
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, TRAIL_COLOR)
	var end_color := Color(TRAIL_COLOR.r, TRAIL_COLOR.g * 0.75, TRAIL_COLOR.b * 0.5, 0.0)
	ramp.set_color(1, end_color)
	p.color_ramp = ramp
	var speck := SphereMesh.new()
	speck.radius = 0.022
	speck.height = 0.044
	speck.radial_segments = 6
	speck.rings = 3
	p.mesh = speck
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
