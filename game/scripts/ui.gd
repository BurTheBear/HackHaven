extends CanvasLayer
## Title, HUD (pebbles + ping cooldown), subtitles, messages and the end screen.

@onready var title: Label = $Root/Title
@onready var crosshair: Label = $Root/Crosshair
@onready var pebbles: Label = $Root/Pebbles
@onready var subtitle_label: Label = $Root/Subtitle
@onready var message: Label = $Root/Message
@onready var paused: Label = $Root/Paused

var _subtitle_time := 0.0
var _message_time := 0.0


func _ready() -> void:
	# Keeps running while the tree is paused, so it can show the pause text
	# and take the click that resumes.
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.state_changed.connect(_on_state_changed)
	Game.pebbles_changed.connect(_on_pebbles_changed)
	Game.subtitle.connect(_on_subtitle)
	Game.player_caught.connect(_on_caught)
	Game.checkpoint_reached.connect(_on_checkpoint)
	Game.game_won.connect(_on_won)
	_on_state_changed(Game.state)
	_on_pebbles_changed(Game.pebbles)


func _process(delta: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	crosshair.modulate.a = 0.3 if player and player.ping_cooldown > 0.0 else 1.0
	# Pause whenever the mouse is unlocked while playing. In a browser, Esc
	# unlocks the mouse without the game ever seeing the key press.
	var should_pause := Game.state == Game.State.PLAYING and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	if get_tree().paused != should_pause:
		get_tree().paused = should_pause
	paused.visible = should_pause
	_subtitle_time -= delta
	if _subtitle_time <= 0.0:
		subtitle_label.text = ""
	if Game.state != Game.State.WON:
		_message_time -= delta
		if _message_time <= 0.0:
			message.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused and event is InputEventMouseButton and event.is_pressed():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _on_state_changed(state: int) -> void:
	title.visible = state == Game.State.TITLE
	crosshair.visible = state == Game.State.PLAYING
	pebbles.visible = state == Game.State.PLAYING or state == Game.State.CAUGHT


func _on_pebbles_changed(count: int) -> void:
	pebbles.text = "Pebbles  " + "● ".repeat(count)


func _on_subtitle(text: String) -> void:
	subtitle_label.text = text
	_subtitle_time = 3.0 + text.length() * 0.06


func _on_caught() -> void:
	_flash("The Hollow heard you.", 1.2)


func _on_checkpoint() -> void:
	_flash("Checkpoint", 1.0)


func _on_won() -> void:
	var t := int(Game.run_time)
	message.text = "You found your way back.\n\nTime %d:%02d    Caught %d\n\nClick to play again" % [t / 60, t % 60, Game.times_caught]


func _flash(text: String, seconds: float) -> void:
	message.text = text
	_message_time = seconds
