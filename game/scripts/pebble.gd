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

var _bounces := 0
var _cooldown := 0.0
var _life := LIFETIME
var _rest := 0.0
var _fading := false
var _trail: CPUParticles3D


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


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	_life -= delta
	if global_position.y < KILL_Y:
		queue_free()
		return
	if _fading:
		return
	var speed := linear_velocity.length()
	var want_trail := speed > TRAIL_MIN_SPEED
	if _trail.emitting != want_trail:
		_trail.emitting = want_trail
	if sleeping or speed < 0.1:
		_rest += delta
	else:
		_rest = 0.0
	if _rest >= REST_TIME or _life <= 0.0:
		_fade_out()


func _on_body_entered(_body: Node) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = 0.15
	if click.stream:
		click.play()
	if _bounces < ECHO_BOUNCES:
		_bounces += 1
		Echo.emit_ping(global_position, PING_RADIUS, true, true)


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
	ramp.set_color(1, Color(TRAIL_COLOR.r, TRAIL_COLOR.g * 0.75, TRAIL_COLOR.b * 0.5, 0.0))
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
