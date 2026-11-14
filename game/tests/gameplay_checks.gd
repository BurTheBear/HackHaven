extends SceneTree
## Run in a disposable project copy; never overwrites the player's saves.
var game: Node
var settings: Node
var echo_system: Node
var failures: Array[String] = []
var checks := 0
var baseline := false

func _initialize() -> void:
	baseline = OS.get_cmdline_user_args().has("--baseline")
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func run() -> void:
	game = root.get_node("Game")
	settings = root.get_node("Settings")
	echo_system = root.get_node("Echo")
	settings.reset_to_defaults()
	check(settings.damage_enabled == false or baseline, "Combat defaults off")
	settings.damage_enabled = false
	game.reset(Vector3.ZERO)
	game.start()
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160, 1, 160)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	world.add_child(floor_body)
	var player = load("res://scenes/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.position = Vector3(60, 0, 60)
	var monster = load("res://scenes/listener.tscn").instantiate()
	world.add_child(monster)
	monster.set_physics_process(false)
	monster.set_process(false)
	monster.patrol_offset = Vector3.ZERO
	await physics_frame
	await physics_frame
	# Loud ripple: no second emission before the full cooldown expires.
	echo_system.clear()
	player.ping_cooldown = 0.0
	player.try_ping()
	var first_count: int = game.get_stat("pings")
	check(first_count == 1, "First ripple emits")
	player.try_ping()
	check(game.get_stat("pings") == first_count, "Immediate repeat blocked")
	player._actions(game.ping_cooldown - 0.01, false)
	player.try_ping()
	check(game.get_stat("pings") == first_count, "Repeat blocked just before cooldown boundary")
	player._actions(0.02, false)
	player.try_ping()
	check(game.get_stat("pings") == first_count + 1, "Ripple ready after cooldown boundary")
	player.ping_cooldown = 0.05
	player._ping_buffered = true
	player._actions(0.06, true)
	check(game.get_stat("pings") == first_count + 2, "Buffered ripple fires once when ready")
	player._actions(0.0, true)
	check(game.get_stat("pings") == first_count + 2, "Buffered ripple cannot repeat")
	# Upgraded cooldown must be used; whisper remains independently rate-limited.
	game.ping_cooldown = 0.8
	player.ping_cooldown = 0.0
	player.try_ping()
	check(is_equal_approx(player.ping_cooldown, 0.8), "Ripple uses upgraded cooldown")
	player.whisper_cooldown = 0.0
	player.try_whisper()
	player.try_whisper()
	check(game.get_stat("whispers") == 1, "Whisper cooldown blocks repeats")
	game.challenge = "no_ping"
	player.ping_cooldown = 0.0
	var count: int = game.get_stat("pings")
	player.try_ping()
	check(game.get_stat("pings") == count, "No-ping challenge remains enforced")
	game.challenge = ""
	# Pebble slots cannot overwrite the player's active ripple slots.
	echo_system.clear()
	echo_system.emit_ping(Vector3(1, 0, 1))
	for i in 6: echo_system.emit_ping(Vector3(i, 0, 2), 10.0, true, true)
	check(echo_system._origins[0] == Vector3(1, 0, 1), "Pebble echoes preserve player ripple")
	# A later sound cannot postpone one that is already about to arrive.
	monster._hear_delay = -1.0
	monster._deaf = 0.0
	monster._on_ping(Vector3(0, 0, -18), 22.0, true)
	check(is_equal_approx(monster._hear_delay, 1.0), "Hearing respects ripple travel time")
	monster._hear_delay = 0.4
	monster._on_ping(Vector3(10, 0, -12), 22.0, true)
	print("PENDING_DELAY=", monster._hear_delay)
	check(monster._hear_delay <= 0.4 or baseline, "Repeated sounds cannot postpone hearing")
	# Sound target drives actual movement, then search on arrival.
	monster._heard_origin = Vector3(-10, 0, -8)
	monster._heard_lure = false
	monster._hear_delay = -1.0
	monster._hear()
	check(monster._target.is_equal_approx(Vector3(-10, 0, -8)), "Investigates the sound's origin")
	monster._alert = 0.0
	monster._do_alert(0.01)
	var initial_distance: float = monster.position.distance_to(monster._target)
	for i in 90:
		monster._physics_process(1.0 / 60.0)
		await physics_frame
	check(monster.position.distance_to(monster._target) < initial_distance - 2.0, "Monster walks toward the sound")
	monster.position = monster._target
	monster._do_investigate(0.01, 1.0)
	check(monster.mode == monster.Mode.SEARCH, "Searches after reaching sound")
	# Lost sight: retain the last known spot rather than track through rock.
	monster._pursuing = true
	monster._seen = false
	monster._sight_check = 99.0
	monster._lose = 3.0
	monster._target = Vector3(-4, 0, -3)
	monster._update_pursuit(0.1)
	print("LOST_SIGHT_TARGET=", monster._target)
	check(monster._target == Vector3(-4, 0, -3) or baseline, "No live tracking after losing sight")
	monster._update_pursuit(3.1)
	check(not monster._pursuing, "Pursuit gives up after existing grace period")
	# Combat off blocks pickups, player damage, strikes and monster damage.
	game.has_dagger = false
	game.pick_dagger()
	check(not game.has_dagger or baseline, "No dagger pickup with combat off")
	game.has_dagger = true
	check(not player.can_attack(), "No dagger strike with combat off")
	var hp: int = game.player_health
	game.damage_player(5)
	check(game.player_health == hp or baseline, "No health damage with combat off")
	hp = monster.health
	monster.take_damage(5)
	check(monster.health == hp or baseline, "No monster damage with combat off")
	var pickup = load("res://scripts/trigger.gd").new()
	pickup.kind = pickup.Kind.DAGGER
	world.add_child(pickup)
	check(not pickup.visible or baseline, "Dagger pickup hidden with combat off")
	check(not pickup._can_use_now() or baseline, "Dagger pickup inactive with combat off")
	settings.damage_enabled = true
	settings.changed.emit()
	check(pickup.visible, "Combat toggle restores uncollected dagger")
	check(player.can_attack(), "Dagger strike available with combat on")
	game.player_health = game.player_max_health
	game.damage_player(2)
	check(game.player_health == game.player_max_health - 2, "Damage mode still applies player damage")
	monster.health = monster.max_health
	monster.take_damage(5)
	check(monster.health == 10, "Dagger still deals five damage")
	monster.take_damage(5)
	monster.take_damage(5)
	check(monster.is_dead, "Three five-damage hits still kill Listener")
	# With combat disabled, close contact still catches and respawn restores pebbles.
	settings.damage_enabled = false
	game.start()
	player.position = monster.position + Vector3(0.7, 0, 0)
	monster._catch_grace = 0.0
	monster._check_catch()
	check(game.state == game.State.CAUGHT, "Stealth mode retains instant catch")
	game.checkpoint_pebbles = 2
	game.pebbles = 0
	game.respawned()
	check(game.pebbles == 2 and game.state == game.State.PLAYING, "Respawn restores checkpoint inventory")
	check(not InputMap.has_action("chalk") or baseline, "Chalk/F action removed")
	world.queue_free()
	await process_frame
	await process_frame
	print("GAMEPLAY_CHECKS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
