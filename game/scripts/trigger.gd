extends Area3D
## One trigger script for everything the player walks into:
## checkpoints, pebble piles, Mara's voice logs and the exit.

enum Kind { CHECKPOINT, PEBBLES, VOICE_LOG, EXIT }

@export var kind := Kind.CHECKPOINT
@export var pebble_amount := 2
@export var sound: AudioStream
@export_multiline var subtitle := ""

var _used := false
var _picked_since_checkpoint := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	Game.checkpoint_reached.connect(func(): _picked_since_checkpoint = false)
	Game.player_caught.connect(_on_player_caught)


func _on_body_entered(body: Node) -> void:
	if _used or not body.is_in_group("player") or Game.state != Game.State.PLAYING:
		return
	# Full hands: leave the pile for later instead of wasting it.
	if kind == Kind.PEBBLES and Game.pebbles >= Game.MAX_PEBBLES:
		return
	_used = true
	if kind == Kind.PEBBLES:
		_picked_since_checkpoint = true
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


## Respawning restores the pebble count from the last checkpoint, so piles
## picked up after it come back too (otherwise those pebbles are lost forever).
func _on_player_caught() -> void:
	if kind == Kind.PEBBLES and _used and _picked_since_checkpoint:
		_used = false
		_picked_since_checkpoint = false
		show()


func _play_sound() -> void:
	if sound == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = sound
	player.bus = &"Voice" if kind == Kind.VOICE_LOG else &"Master"
	add_child(player)
	player.play()
