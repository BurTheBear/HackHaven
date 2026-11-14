extends Area3D
## One trigger script for everything the player walks into:
## checkpoints, pebble piles, Mara's voice logs, hints, echo crystals and the exit.

enum Kind { CHECKPOINT, PEBBLES, VOICE_LOG, EXIT, CRYSTAL, HINT }

@export var kind := Kind.CHECKPOINT
@export var pebble_amount := 2
## Echo crystals only: 0 = ping radius, 1 = ping cooldown, 2 = max pebbles.
@export var upgrade := 0
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
	if kind == Kind.PEBBLES and Game.pebbles >= Game.max_pebbles:
		return
	_used = true
	_play_sound()
	if subtitle != "":
		Game.show_subtitle(subtitle)
	match kind:
		Kind.CHECKPOINT:
			Game.reach_checkpoint(global_position)
		Kind.PEBBLES:
			_picked_since_checkpoint = true
			Game.add_pebbles(pebble_amount)
			hide()
		Kind.CRYSTAL:
			Game.show_subtitle(Game.apply_upgrade(upgrade))
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
	if sound:
		var player := AudioStreamPlayer3D.new()
		player.stream = sound
		player.bus = &"Voice" if kind == Kind.VOICE_LOG else &"Master"
		add_child(player)
		player.play()
		return
	match kind:
		Kind.CHECKPOINT, Kind.CRYSTAL:
			Sfx.play("chime", -6.0)
		Kind.PEBBLES:
			Sfx.play("pebble", -6.0, &"Master", 0.7)
		Kind.VOICE_LOG:
			Sfx.play("click", -6.0)
