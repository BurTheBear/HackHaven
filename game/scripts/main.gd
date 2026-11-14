extends Node3D
## Wires the game together: title, mouse capture, respawn and the color ending.

@onready var player = $Player
@onready var level = $Level
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun


func _ready() -> void:
	world_env.environment = world_env.environment.duplicate()
	var spawn: Vector3 = level.get_node("PlayerSpawn").global_position
	player.respawn(spawn)
	Game.reset(spawn)
	Echo.clear()
	sun.visible = false
	Game.player_caught.connect(_on_caught)
	Game.game_won.connect(_on_won)
	var director := preload("res://scripts/director.gd").new()
	director.name = "Director"
	add_child(director)
	director.setup(player, $UI)


func _unhandled_input(event: InputEvent) -> void:
	var click := event is InputEventMouseButton and event.is_pressed()
	match Game.state:
		Game.State.TITLE:
			if click:
				start_game()
				get_viewport().set_input_as_handled()
		Game.State.PLAYING:
			# Unlocking the mouse pauses the game (see ui.gd), which also
			# handles the click that resumes it.
			if event.is_action_pressed("pause"):
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Game.State.WON:
			if click:
				get_tree().reload_current_scene()


func start_game() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.start()


func _on_caught() -> void:
	await get_tree().create_timer(1.2).timeout
	player.respawn(Game.checkpoint_position)
	Echo.clear()
	Game.respawned()


func _on_won() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	level.reveal_colors()
	sun.visible = true
	var env := world_env.environment
	env.background_color = Color(0.55, 0.75, 0.95)
	env.ambient_light_color = Color(1.0, 0.95, 0.85)
	env.ambient_light_energy = 0.9
