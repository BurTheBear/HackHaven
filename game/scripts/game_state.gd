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

## CUTSCENE was added last so the other values never change.
enum State { TITLE, PLAYING, CAUGHT, WON, CUTSCENE }
enum Upgrade { PING_RADIUS, PING_COOLDOWN, MAX_PEBBLES }

const START_PEBBLES := 3
const SAVE_PATH := "user://echo.cfg"
## Checkpoint save (the main menu's Continue).
const RUN_SAVE_PATH := "user://save.cfg"

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

# --- Added by the UI owner (menus, saves, cutscenes) ---
## True once the boot cards and the click gate have been shown this session.
var booted := false
## main.gd starts a run straight away after a scene reload (Play again, Go deeper).
var auto_start := false
## main.gd continues from the saved checkpoint after a scene reload.
var pending_continue := false
## Echo crystal upgrades collected this run (Upgrade values), for the HUD icons.
var upgrades: Array[int] = []
## Voice log texts by index, so they can be re-read from the pause menu.
var log_texts := {}


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
	upgrades.clear()
	log_texts = {}
	_set_state(State.TITLE)
	pebbles_changed.emit(pebbles)


func start() -> void:
	_set_state(State.PLAYING)


## Locks the player for a cutscene (from the title or mid-run).
func begin_cutscene() -> void:
	if state == State.PLAYING or state == State.TITLE:
		_set_state(State.CUTSCENE)


func end_cutscene() -> void:
	if state == State.CUTSCENE:
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
	upgrades.append(kind)
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
	save_checkpoint()


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
	clear_save()
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


# ---------------------------------------------------------------- Checkpoint save

func has_save() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(RUN_SAVE_PATH) == OK and cfg.has_section_key("save", "checkpoint_position")


## Level the save belongs to (0 when there is none).
func saved_level_index() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(RUN_SAVE_PATH) != OK:
		return 0
	return int(cfg.get_value("save", "level_index", 0))


func save_checkpoint() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("save", "level_index", level_index)
	cfg.set_value("save", "checkpoint_position", checkpoint_position)
	cfg.set_value("save", "checkpoint_yaw", checkpoint_yaw)
	cfg.set_value("save", "pebbles", checkpoint_pebbles)
	cfg.set_value("save", "max_pebbles", max_pebbles)
	cfg.set_value("save", "ping_radius", ping_radius)
	cfg.set_value("save", "ping_cooldown", ping_cooldown)
	cfg.set_value("save", "upgrades", Array(upgrades))
	cfg.set_value("save", "logs_found", Array(logs_found))
	cfg.set_value("save", "log_texts", log_texts)
	cfg.set_value("save", "crystals_found", crystals_found)
	cfg.set_value("save", "stats", stats)
	cfg.set_value("save", "times_caught", times_caught)
	cfg.set_value("save", "run_time", run_time)
	cfg.set_value("save", "current_zone", current_zone)
	cfg.save(RUN_SAVE_PATH)


## Applies the saved checkpoint on top of a fresh reset(). False if there is none.
func load_save() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(RUN_SAVE_PATH) != OK or not cfg.has_section_key("save", "checkpoint_position"):
		return false
	level_index = int(cfg.get_value("save", "level_index", 0))
	checkpoint_position = cfg.get_value("save", "checkpoint_position", Vector3.ZERO)
	checkpoint_yaw = float(cfg.get_value("save", "checkpoint_yaw", 0.0))
	checkpoint_pebbles = int(cfg.get_value("save", "pebbles", START_PEBBLES))
	max_pebbles = int(cfg.get_value("save", "max_pebbles", 5))
	ping_radius = float(cfg.get_value("save", "ping_radius", 22.0))
	ping_cooldown = float(cfg.get_value("save", "ping_cooldown", 1.0))
	upgrades.clear()
	for v in cfg.get_value("save", "upgrades", []):
		upgrades.append(int(v))
	logs_found.clear()
	for v in cfg.get_value("save", "logs_found", []):
		logs_found.append(int(v))
	var texts: Variant = cfg.get_value("save", "log_texts", {})
	log_texts = texts if texts is Dictionary else {}
	crystals_found = int(cfg.get_value("save", "crystals_found", 0))
	var saved_stats: Variant = cfg.get_value("save", "stats", {})
	stats = saved_stats if saved_stats is Dictionary else {}
	times_caught = int(cfg.get_value("save", "times_caught", 0))
	run_time = float(cfg.get_value("save", "run_time", 0.0))
	current_zone = str(cfg.get_value("save", "current_zone", ""))
	pebbles = checkpoint_pebbles
	pebbles_changed.emit(pebbles)
	return true


func clear_save() -> void:
	if FileAccess.file_exists(RUN_SAVE_PATH):
		DirAccess.remove_absolute(RUN_SAVE_PATH)
