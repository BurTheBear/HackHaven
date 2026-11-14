extends Node
## Drives the Listener model's AnimationPlayer from the Listener that owns it
## (reads its `mode` and `asleep`, and how fast it is moving). Phantoms have no
## such properties, so they just idle (or walk, if they are moving bodies).

const MODE_LISTEN := 1
const MODE_ALERT := 2
const LOOPED := ["Idle_Breathe", "Walk_Stalk", "Sleep_Dormant"]

var _player: AnimationPlayer
var _host: Node
var _current := ""


func setup(player: AnimationPlayer, host: Node) -> void:
	_player = player
	_host = host
	for anim_name in LOOPED:
		if _player.has_animation(anim_name):
			_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	if _player.has_animation("Alert_Listen"):
		_player.get_animation("Alert_Listen").loop_mode = Animation.LOOP_NONE
	_play("Idle_Breathe", 1.0)


func _process(_delta: float) -> void:
	if _player == null or _host == null:
		return
	var sleeping = _host.get("asleep")
	var mode_value = _host.get("mode")
	var mode_i := -1
	if mode_value != null:
		mode_i = int(mode_value)
	var speed := 0.0
	if _host is CharacterBody3D:
		speed = (_host as CharacterBody3D).get_real_velocity().length()
	if sleeping == true:
		_play("Sleep_Dormant", 1.0)
	elif mode_i == MODE_ALERT or mode_i == MODE_LISTEN:
		_play("Alert_Listen", 1.0)
	elif speed > 0.3:
		_play("Walk_Stalk", clampf(speed / 1.5, 0.5, 2.2))
	else:
		_play("Idle_Breathe", 1.0)


func _play(anim_name: String, speed_scale: float) -> void:
	if not _player.has_animation(anim_name):
		return
	_player.speed_scale = speed_scale
	if anim_name != _current:
		_current = anim_name
		_player.play(anim_name, 0.25)
