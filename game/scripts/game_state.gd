extends Node
## Autoload "Game": run state, checkpoint, pebbles and stats.

signal state_changed(state: int)
signal pebbles_changed(count: int)
signal player_caught
signal checkpoint_reached
signal game_won
signal subtitle(text: String)

enum State { TITLE, PLAYING, CAUGHT, WON }

const START_PEBBLES := 3
const MAX_PEBBLES := 5

var state: State = State.TITLE
var pebbles := START_PEBBLES
var checkpoint_position := Vector3.ZERO
var checkpoint_pebbles := START_PEBBLES
var times_caught := 0
var run_time := 0.0


func reset(spawn: Vector3) -> void:
	pebbles = START_PEBBLES
	checkpoint_position = spawn
	checkpoint_pebbles = START_PEBBLES
	times_caught = 0
	run_time = 0.0
	_set_state(State.TITLE)
	pebbles_changed.emit(pebbles)


func start() -> void:
	_set_state(State.PLAYING)


func use_pebble() -> bool:
	if pebbles <= 0:
		return false
	pebbles -= 1
	pebbles_changed.emit(pebbles)
	return true


func add_pebbles(amount: int) -> void:
	pebbles = mini(pebbles + amount, MAX_PEBBLES)
	pebbles_changed.emit(pebbles)


func reach_checkpoint(pos: Vector3) -> void:
	checkpoint_position = pos
	checkpoint_pebbles = pebbles
	checkpoint_reached.emit()


func catch_player() -> void:
	if state != State.PLAYING:
		return
	times_caught += 1
	_set_state(State.CAUGHT)
	player_caught.emit()


func respawned() -> void:
	pebbles = checkpoint_pebbles
	pebbles_changed.emit(pebbles)
	_set_state(State.PLAYING)


func win() -> void:
	if state != State.PLAYING:
		return
	_set_state(State.WON)
	game_won.emit()


func show_subtitle(text: String) -> void:
	subtitle.emit(text)


func _process(delta: float) -> void:
	if state == State.PLAYING:
		run_time += delta


func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)
