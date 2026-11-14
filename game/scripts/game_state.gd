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
## A journal page was found (gameplay emits; this script records it once).
signal journal_page(index: int, text: String)
# --- Combat (damage mode, Settings.damage_enabled) ---
## Player health changed (damage, respawn, new run).
signal health_changed(hp: int, max_hp: int)
## The player was hurt by `amount` from a Listener at `from`.
signal player_damaged(amount: int, from: Vector3)
## A dagger was picked up (Game.has_dagger is now true).
signal dagger_picked
## A Listener was killed.
signal listener_killed(listener_position: Vector3)
## The player's dagger hurt a Listener (HUD floating damage numbers).
signal listener_damaged(amount: int, world_position: Vector3)

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
var ping_cooldown := 2.0
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
## Combat: health (only used while damage mode is on) and the dagger.
var player_max_health := 20
var player_health := 20
var has_dagger := false

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
## Challenge mode: "" | "no_ping" | "one_pebble" | "darkness". Survives reset().
var challenge := ""
var journal_found: Array[int] = []
var journal_texts := {}
## Totals for the 100% badge (journals per level; logs/crystals are counted at runtime).
const JOURNALS_PER_LEVEL := [5, 4]
const LOGS_PER_LEVEL := [8, 7]
const RANK_ORDER := ["LOUD", "SURVIVOR", "ECHO", "SILENT", "GHOST"]
const CHALLENGE_NAMES := {"": "None", "no_ping": "No pings", "one_pebble": "One pebble", "darkness": "Total darkness"}


func add_stat(stat_name: String, amount: int = 1) -> void:
	stats[stat_name] = int(stats.get(stat_name, 0)) + amount
	stat_changed.emit(stat_name, stats[stat_name])


func _on_journal_page(index: int, text: String) -> void:
	journal_texts[index] = text
	if not journal_found.has(index):
		journal_found.append(index)
		add_stat("journals")


func journal_total() -> int:
	return int(JOURNALS_PER_LEVEL[clampi(level_index, 0, JOURNALS_PER_LEVEL.size() - 1)])


func challenge_name() -> String:
	return str(CHALLENGE_NAMES.get(challenge, "None"))


## GHOST / SILENT / ECHO / LOUD / SURVIVOR from this run's stats.
func compute_rank() -> String:
	var pings := get_stat("pings")
	if times_caught == 0 and pings <= 10:
		return "GHOST"
	if times_caught == 0:
		return "SILENT"
	if pings >= 50 or times_caught >= 6:
		return "LOUD"
	if times_caught <= 3:
		return "ECHO"
	return "SURVIVOR"


func _rank_key() -> String:
	return "L%d_%s" % [level_index, challenge if challenge != "" else "none"]


func best_rank() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return ""
	return str(cfg.get_value("ranks", _rank_key(), ""))


## Saves the rank if it beats the stored one; returns the best rank afterwards.
func record_rank(rank: String) -> String:
	var old := best_rank()
	var best := old
	if old == "" or RANK_ORDER.find(rank) > RANK_ORDER.find(old):
		best = rank
		var cfg := ConfigFile.new()
		cfg.load(SAVE_PATH)
		cfg.set_value("ranks", _rank_key(), rank)
		cfg.save(SAVE_PATH)
	return best


func get_stat(stat_name: String) -> int:
	return int(stats.get(stat_name, 0))


func _ready() -> void:
	journal_page.connect(_on_journal_page)
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_time = cfg.get_value("run", "best_time", -1.0)


func reset(spawn: Vector3) -> void:
	pebbles = START_PEBBLES
	max_pebbles = 5
	ping_radius = 22.0
	ping_cooldown = 2.0
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
	journal_found.clear()
	journal_texts = {}
	has_dagger = false
	player_health = player_max_health
	health_changed.emit(player_health, player_max_health)
	if challenge == "one_pebble":
		max_pebbles = 1
		pebbles = 1
		checkpoint_pebbles = 1
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
			ping_cooldown = maxf(ping_cooldown - 0.4, 0.8)
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
	player_health = player_max_health
	health_changed.emit(player_health, player_max_health)
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


# ---------------------------------------------------------------- Combat

## Damage mode (Settings.damage_enabled, default on). Off = instant catch.
func damage_enabled() -> bool:
	return Settings.get("damage_enabled") != false


func health_fraction() -> float:
	return float(player_health) / float(maxi(player_max_health, 1))


## Damage of one Listener hit (1 s apart): 2 above half health, less as you
## weaken (1 at 30% or lower), halved in assist mode. Never 0.
func listener_hit_damage() -> int:
	var f := health_fraction()
	var dmg := 2.0
	if f <= 0.3:
		dmg = 1.0
	elif f <= 0.5:
		dmg = 1.0 + (f - 0.3) / 0.2  # 1..2, rounded down
	var d := int(floor(dmg))
	if Settings.assist_mode:
		d = int(d * 0.5)
	return maxi(d, 1)


## Damage of one dagger stab: 5, or 4 while the player is at 30% health or lower.
func dagger_damage() -> int:
	return 4 if health_fraction() <= 0.3 else 5


## Hurts the player; at 0 HP this is the usual catch (and respawn).
func damage_player(amount: int, from: Vector3 = Vector3.ZERO) -> void:
	if state != State.PLAYING or amount <= 0:
		return
	player_health = maxi(player_health - amount, 0)
	add_stat("damage_taken", amount)
	player_damaged.emit(amount, from)
	health_changed.emit(player_health, player_max_health)
	if player_health <= 0:
		catch_player(from)


func pick_dagger() -> void:
	has_dagger = true
	add_stat("daggers_found")
	dagger_picked.emit()


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
	cfg.set_value("save", "journal_found", Array(journal_found))
	cfg.set_value("save", "journal_texts", journal_texts)
	cfg.set_value("save", "stats", stats)
	cfg.set_value("save", "times_caught", times_caught)
	cfg.set_value("save", "run_time", run_time)
	cfg.set_value("save", "current_zone", current_zone)
	cfg.set_value("save", "has_dagger", has_dagger)
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
	ping_cooldown = float(cfg.get_value("save", "ping_cooldown", 2.0))
	upgrades.clear()
	for v in cfg.get_value("save", "upgrades", []):
		upgrades.append(int(v))
	logs_found.clear()
	for v in cfg.get_value("save", "logs_found", []):
		logs_found.append(int(v))
	var texts: Variant = cfg.get_value("save", "log_texts", {})
	log_texts = texts if texts is Dictionary else {}
	crystals_found = int(cfg.get_value("save", "crystals_found", 0))
	journal_found.clear()
	for v in cfg.get_value("save", "journal_found", []):
		journal_found.append(int(v))
	var jt: Variant = cfg.get_value("save", "journal_texts", {})
	journal_texts = jt if jt is Dictionary else {}
	var saved_stats: Variant = cfg.get_value("save", "stats", {})
	stats = saved_stats if saved_stats is Dictionary else {}
	times_caught = int(cfg.get_value("save", "times_caught", 0))
	run_time = float(cfg.get_value("save", "run_time", 0.0))
	current_zone = str(cfg.get_value("save", "current_zone", ""))
	has_dagger = bool(cfg.get_value("save", "has_dagger", false))
	pebbles = checkpoint_pebbles
	pebbles_changed.emit(pebbles)
	return true


func clear_save() -> void:
	if FileAccess.file_exists(RUN_SAVE_PATH):
		DirAccess.remove_absolute(RUN_SAVE_PATH)
