extends Node
## Autoload "Game": run state, checkpoint, pebbles, upgrades and stats.

signal state_changed(state: int)
signal pebbles_changed(count: int)
signal player_caught
signal checkpoint_reached
signal game_won
signal subtitle(text: String)
# --- Shared contract between systems (UI, player, audio/AI, level) ---
## A voice log was picked up (UI shows "MARA —" subtitle, log counter).
signal voice_log(index: int, text: String)
## Entered a named zone ("THE VEINS"). Level triggers emit, UI shows a card.
signal zone_entered(zone_name: String)
## Ask the UI to show a one-time control prompt by id (see ui prompt table).
signal prompt_requested(id: String)
## A Listener started hunting because it heard something at `origin`.
signal listener_alerted(listener_position: Vector3)
## Caption for an important sound, for deaf / hard-of-hearing players.
signal caption(text: String, world_position: Vector3)
## Scripted level event by name ("hall_silence"). Level emits, director reacts.
signal level_event(event_name: String)
## Player fell into the chasm / out of the level (not caught).
signal player_fell
## A run stat changed (UI may show it).
signal stat_changed(stat_name: String, value: int)

enum State { TITLE, PLAYING, CAUGHT, WON }
enum Upgrade { PING_RADIUS, PING_COOLDOWN, MAX_PEBBLES }

const START_PEBBLES := 3
const SAVE_PATH := "user://echo.cfg"

var state: State = State.TITLE
var pebbles := START_PEBBLES
var max_pebbles := 5
var ping_radius := 22.0
var ping_cooldown := 1.0
var checkpoint_position := Vector3.ZERO
var checkpoint_pebbles := START_PEBBLES
var catcher_position := Vector3.ZERO
var times_caught := 0
var run_time := 0.0
var best_time := -1.0
var new_best := false
## Facing (radians, player rotation.y) to respawn with at the checkpoint.
var checkpoint_yaw := 0.0
## Which level main.gd loads: 0 = level.tscn, 1 = level2.tscn.
var level_index := 0
var current_zone := ""
## Run stats: "pings", "whispers", "pebbles_thrown", "logs", "crystals", "chalk".
var stats := {}
var logs_found: Array[int] = []
var crystals_found := 0


func add_stat(stat_name: String, amount: int = 1) -> void:
	stats[stat_name] = int(stats.get(stat_name, 0)) + amount
	stat_changed.emit(stat_name, stats[stat_name])


func get_stat(stat_name: String) -> int:
	return int(stats.get(stat_name, 0))


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_time = cfg.get_value("run", "best_time", -1.0)


func reset(spawn: Vector3) -> void:
	pebbles = START_PEBBLES
	max_pebbles = 5
	ping_radius = 22.0
	ping_cooldown = 1.0
	checkpoint_position = spawn
	checkpoint_pebbles = START_PEBBLES
	times_caught = 0
	run_time = 0.0
	new_best = false
	checkpoint_yaw = 0.0
	current_zone = ""
	stats = {}
	logs_found.clear()
	crystals_found = 0
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
	pebbles = mini(pebbles + amount, max_pebbles)
	pebbles_changed.emit(pebbles)


## Echo crystals.
func apply_upgrade(kind: int) -> String:
	match kind:
		Upgrade.PING_RADIUS:
			ping_radius *= 1.2
			return "Echo crystal: your call carries further."
		Upgrade.PING_COOLDOWN:
			ping_cooldown = maxf(ping_cooldown - 0.2, 0.4)
			return "Echo crystal: you can call again sooner."
		_:
			max_pebbles += 1
			add_pebbles(1)
			return "Echo crystal: you can carry one more stone."


func reach_checkpoint(pos: Vector3, yaw: float = NAN) -> void:
	checkpoint_position = pos
	if not is_nan(yaw):
		checkpoint_yaw = yaw
	checkpoint_pebbles = pebbles
	checkpoint_reached.emit()


func catch_player(from: Vector3 = Vector3.ZERO) -> void:
	if state != State.PLAYING:
		return
	catcher_position = from
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
	if best_time < 0.0 or run_time < best_time:
		best_time = run_time
		new_best = true
		var cfg := ConfigFile.new()
		cfg.set_value("run", "best_time", best_time)
		cfg.save(SAVE_PATH)
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
