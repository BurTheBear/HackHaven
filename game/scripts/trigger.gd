extends Area3D
## One trigger script for everything the player walks into:
## checkpoints, pebble piles, Mara's voice logs and the exit.

enum Kind { CHECKPOINT, PEBBLES, VOICE_LOG, EXIT }

@export var kind := Kind.CHECKPOINT
@export var pebble_amount := 2
@export var sound: AudioStream
@export_multiline var subtitle := ""

var _used := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _used or not body.is_in_group("player") or Game.state != Game.State.PLAYING:
		return
	_used = true
	_play_sound()
	if subtitle != "":
		Game.show_subtitle(subtitle)
	match kind:
		Kind.CHECKPOINT:
			Game.reach_checkpoint(global_position)
		Kind.PEBBLES:
			Game.add_pebbles(pebble_amount)
			hide()
		Kind.EXIT:
			Game.win()


func _play_sound() -> void:
	if sound == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = sound
	player.bus = &"Voice" if kind == Kind.VOICE_LOG else &"Master"
	add_child(player)
	player.play()
