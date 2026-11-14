extends RigidBody3D
## Thrown pebble: its first bounces each send out a smaller (loud) ping.

const PING_RADIUS := 10.0
const ECHO_BOUNCES := 2
const LIFETIME := 10.0

@onready var click: AudioStreamPlayer3D = $Click

var _bounces := 0
var _cooldown := 0.0
var _life := LIFETIME


func _ready() -> void:
	if click.stream == null:
		click.stream = Sfx.stream("pebble")
	click.unit_size = 4.0
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_body_entered(_body: Node) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = 0.15
	if click.stream:
		click.play()
	if _bounces < ECHO_BOUNCES:
		_bounces += 1
		Echo.emit_ping(global_position, PING_RADIUS, true, true)
