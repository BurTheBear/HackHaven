extends SceneTree
## Exercise the real Game.catch_player -> Main -> UI -> respawn path.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = root.get_node("Game")
	var settings = root.get_node("Settings")
	game.booted = true
	settings.skip_intro = true
	settings.seen_warning = true
	settings.damage_enabled = false
	for skip in [false, true]:
		settings.skip_jumpscare = skip
		var scene = load("res://scenes/main.tscn").instantiate()
		root.add_child(scene)
		current_scene = scene
		var ui = scene.get_node("UI")
		ui.set_process(false) # Headless display cannot lock the pointer.
		paused = false
		game.start()
		game.checkpoint_pebbles = 2
		game.pebbles = 0
		game.catch_player(scene.get_node("Player").position + Vector3(0, 0, -1))
		await process_frame
		var scare = ui.root.get_node_or_null("CaughtJumpscare")
		assert((scare == null) == skip, "Skip setting controls the real attack")
		if not skip:
			assert(scare.texture is AtlasTexture)
			assert(scare.get_child(0).playing, "Attack audio starts")
			await create_timer(0.4).timeout
			assert(scare.texture.region.position != Vector2.ZERO, "Attack frames advance")
		var deadline := Time.get_ticks_msec() + 10000
		while game.state == game.State.CAUGHT and Time.get_ticks_msec() < deadline:
			await process_frame
		assert(game.state == game.State.PLAYING, "Catch completes and respawns")
		assert(game.pebbles == 2, "Respawn inventory restored")
		await process_frame
		assert(ui.root.get_node_or_null("CaughtJumpscare") == null, "Overlay is cleaned up")
		print("JUMPSCARE_CHECK: skip=", skip, " attack/respawn OK")
		scene.queue_free()
		current_scene = null
		for i in 3: await process_frame
	print("JUMPSCARE_CHECKS PASSED")
	quit()
