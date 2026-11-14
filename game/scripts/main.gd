extends Node3D
## Wires the game together: loads the level for Game.level_index, the menu
## flow (Begin / Continue / Play again / Go deeper / Quit to title), the
## cutscenes, the catch-and-respawn sequence and the color ending.

const Style = preload("res://scripts/ui_style.gd")
const LEVELS := ["res://scenes/level.tscn", "res://scenes/level2.tscn"]
const CUTSCENE_PATH := "res://scripts/ui_cutscene.gd"

@onready var player = $Player
@onready var level: Node3D = $Level
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var ui = $UI

## ui_cutscene.gd instance (null if that script isn't there).
var cutscene = null
var _spawn := Vector3.ZERO
var _spawn_yaw := 0.0
var _hall_done := false
var _busy := false
var _revealed := false


## Sets up the level, player, director and cutscenes, then shows the menu
## (or starts / continues a run straight away after a scene reload).
func _ready() -> void:
	Style.load_keys()
	world_env.environment = world_env.environment.duplicate()
	_load_level()
	_find_spawn_point()
	player.respawn(_spawn, _spawn_yaw)
	Game.reset(_spawn)
	Game.checkpoint_yaw = _spawn_yaw
	Echo.clear()
	sun.visible = false
	Game.player_caught.connect(_on_caught)
	Game.game_won.connect(_on_won)
	Game.level_event.connect(_on_level_event)
	_add_director()
	_add_cutscene()
	if Game.pending_continue:
		Game.pending_continue = false
		_continue_after_reload.call_deferred()
	elif Game.auto_start:
		Game.auto_start = false
		_start_after_reload.call_deferred()
	else:
		ui.show_title()


## Spawn point: the level's "PlayerSpawn" marker, or the level origin.
func _find_spawn_point() -> void:
	_spawn = level.global_position
	var marker: Node3D = level.get_node_or_null("PlayerSpawn") as Node3D
	if marker != null:
		_spawn = marker.global_position
		_spawn_yaw = marker.global_rotation.y


## Creates the Director node (scripted scares and events).
func _add_director() -> void:
	var director_script: GDScript = preload("res://scripts/director.gd")
	var director = director_script.new()
	director.name = "Director"
	add_child(director)
	director.setup(player, ui)


## Creates the Cutscene node, if the cutscene script exists.
func _add_cutscene() -> void:
	if not ResourceLoader.exists(CUTSCENE_PATH):
		return
	var cutscene_script = load(CUTSCENE_PATH)
	if cutscene_script == null:
		return
	cutscene = cutscene_script.new()
	cutscene.name = "Cutscene"
	add_child(cutscene)
	cutscene.setup(player, ui)


## Swaps the Level instance from main.tscn for level2.tscn when asked to.
func _load_level() -> void:
	var last_index: int = LEVELS.size() - 1
	var index: int = clampi(Game.level_index, 0, last_index)
	if index == 0:
		Game.level_index = 0
		return
	var path: String = LEVELS[index]
	var packed: PackedScene = null
	if ResourceLoader.exists(path):
		packed = load(path) as PackedScene
	if packed == null:
		# Level 2 is missing: stay on level 1.
		Game.level_index = 0
		return
	var fresh: Node = packed.instantiate()
	# Give the new level the same script and material as the old one if it has none.
	if fresh.get_script() == null and level.get_script() != null:
		fresh.set_script(level.get_script())
	if "reveal_material" in fresh:
		if fresh.get("reveal_material") == null:
			fresh.set("reveal_material", level.get("reveal_material"))
	# Put the new level where the old one was in the scene tree.
	var at: int = level.get_index()
	remove_child(level)
	level.queue_free()
	fresh.name = "Level"
	add_child(fresh)
	move_child(fresh, at)
	level = fresh as Node3D


## Pause key while playing: free the mouse (ui.gd then pauses).
func _unhandled_input(event: InputEvent) -> void:
	# Unlocking the mouse pauses the game (see ui.gd), which also handles
	# the click that resumes it.
	if Game.state == Game.State.PLAYING and event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------------- Menu actions (called by ui.gd)

## Main menu "Begin": fade, the two opening lines, the intro cutscene, play.
func begin_new_run() -> void:
	if _busy:
		return
	if Game.level_index != 0:
		Game.level_index = 0
		Game.auto_start = true
		_reload()
		return
	_busy = true
	# This click is the user gesture browsers need for pointer lock.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ui.hide_title()
	await ui.fade_to_black(0.8)
	await _intro_sequence()
	_busy = false


## Main menu "Continue": load the checkpoint save (reloads first if it is on another level).
func continue_run() -> void:
	if _busy or not Game.has_save():
		return
	var saved: int = Game.saved_level_index()
	if saved != Game.level_index:
		Game.level_index = saved
		Game.pending_continue = true
		_reload()
		return
	_busy = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ui.hide_title()
	await ui.fade_to_black(0.6)
	_resume_from_save()
	_busy = false


## New run right after a scene reload (Play again / Go deeper).
func _start_after_reload() -> void:
	_busy = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ui.hide_title(true)
	ui.set_black(1.0)
	await _intro_sequence()
	_busy = false


## Continue right after a scene reload.
func _continue_after_reload() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ui.hide_title(true)
	ui.set_black(1.0)
	_resume_from_save()


## Puts the player at the saved checkpoint and starts playing.
func _resume_from_save() -> void:
	if not Game.load_save():
		Game.reset(_spawn)
		Game.checkpoint_yaw = _spawn_yaw
	player.respawn(Game.checkpoint_position, Game.checkpoint_yaw)
	Echo.clear()
	Game.start()
	ui.fade_from_black(1.2)
	if Game.current_zone != "":
		Game.zone_entered.emit(Game.current_zone)


## Opening text and intro cutscene (or a simple fade), then the run starts.
func _intro_sequence() -> void:
	Echo.clear()
	var use_cutscene: bool = false
	if cutscene != null and not Settings.skip_intro:
		use_cutscene = true
	if Game.level_index == 1:
		if use_cutscene:
			ui.set_black(0.0)
			await cutscene.play_level2_intro()
		else:
			ui.fade_from_black(1.2)
	else:
		if not Settings.skip_intro:
			await ui.play_opening_text()
		if use_cutscene:
			ui.set_black(0.0)
			await cutscene.play_intro()
		else:
			ui.fade_from_black(1.5)
	if Game.state != Game.State.PLAYING:
		Game.start()
	Game.prompt_requested.emit("ping")


## Pause menu "Restart from checkpoint".
func restart_from_checkpoint() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.respawn(Game.checkpoint_position, Game.checkpoint_yaw)
	Echo.clear()
	Game.respawned()
	ui.dip_black(0.7)


## Back to the main menu (reloads the scene).
func quit_to_title() -> void:
	Game.level_index = 0
	Game.auto_start = false
	Game.pending_continue = false
	_reload()


## End screen "Play again": a new run on level 1.
func play_again() -> void:
	Game.level_index = 0
	Game.auto_start = true
	_reload()


## End screen "Go deeper": a new run on level 2.
func go_deeper() -> void:
	Game.level_index = 1
	Game.auto_start = true
	_reload()


## True on level 1 when level 2 exists.
func can_go_deeper() -> bool:
	if Game.level_index != 0:
		return false
	return ResourceLoader.exists(LEVELS[1])


## Closes the game (desktop only).
func quit_game() -> void:
	get_tree().quit()


## Reloads main.tscn with a clean slate.
func _reload() -> void:
	get_tree().paused = false
	Sfx.set_muffled(false)
	_stop_ending_loops()
	Echo.clear()
	get_tree().reload_current_scene()


## The ending cutscene starts the wind and birdsong loops on Sfx's shared
## players, which outlive the scene: stop them before leaving.
func _stop_ending_loops() -> void:
	var loops: Array = [Sfx.stream("wind"), Sfx.stream("birdsong")]
	for child in Sfx.get_children():
		if not (child is AudioStreamPlayer):
			continue
		var audio_player: AudioStreamPlayer = child
		if audio_player.playing and loops.has(audio_player.stream):
			audio_player.stop()


# ---------------------------------------------------------------- Caught / level events / ending

## Caught: the caught effect, then respawn at the checkpoint.
func _on_caught() -> void:
	await ui.caught_out()
	if not is_inside_tree():
		return
	player.respawn(Game.checkpoint_position, Game.checkpoint_yaw)
	Echo.clear()
	Game.respawned()
	ui.caught_in()


## The "hall_silence" level event plays the hall reveal cutscene once.
func _on_level_event(event_name: String) -> void:
	if event_name != "hall_silence":
		return
	if _hall_done:
		return
	if cutscene == null:
		return
	if Game.state != Game.State.PLAYING:
		return
	_hall_done = true
	cutscene.play_hall_reveal()


## The run is won: ending cutscene, color reveal, then the end screen.
func _on_won() -> void:
	if cutscene != null:
		# The world turns to color while the camera rises into daylight.
		get_tree().create_timer(2.5).timeout.connect(reveal_world)
		await cutscene.play_ending()
	reveal_world()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_end_screen(can_go_deeper())


## The color reveal: shader off, sun on, sky and warm light. Safe to call twice.
func reveal_world() -> void:
	if _revealed or not is_inside_tree():
		return
	_revealed = true
	if level.has_method("reveal_colors"):
		level.reveal_colors()
	sun.visible = true
	var env: Environment = world_env.environment
	env.background_color = Color(0.55, 0.75, 0.95)
	env.ambient_light_color = Color(1.0, 0.95, 0.85)
	env.ambient_light_energy = 0.9
