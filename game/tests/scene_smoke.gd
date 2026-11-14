extends SceneTree
## Loads each complete level in a disposable project, including menus and UI.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = root.get_node("Game")
	var settings = root.get_node("Settings")
	settings.damage_enabled = false
	settings.skip_intro = true
	settings.seen_warning = true
	game.booted = true
	for index in 2:
		game.level_index = index
		var scene = load("res://scenes/main.tscn").instantiate()
		root.add_child(scene)
		current_scene = scene
		for i in 12: await process_frame
		var ui = scene.get_node("UI")
		# A headless display cannot capture the pointer; skip only its auto-pause.
		ui.set_process(false)
		paused = false
		game.start()
		var player = scene.get_node("Player")
		var start: Vector3 = player.position
		player.try_ping()
		player.try_whisper()
		for i in 20: await physics_frame
		assert(player.position.y > -3.0, "Player remains in level")
		assert(scene.get_node("Level") != null)
		assert(not InputMap.has_action("chalk"))
		var daggers := 0
		for node in scene.find_children("*", "Area3D", true, false):
			if node.get_script() == load("res://scripts/trigger.gd") and node.kind == node.Kind.DAGGER:
				daggers += 1
				assert(not node.visible, "Combat-off level hides every dagger")
		print("SCENE_SMOKE level=", index, " hidden_daggers=", daggers, " spawn=", start, " pings=", game.get_stat("pings"))
		scene.queue_free()
		current_scene = null
		paused = false
		for i in 4: await process_frame
	print("SCENE_SMOKE: both levels loaded, pinged and simulated")
	quit()
