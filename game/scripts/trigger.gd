extends Area3D
## One trigger script for everything the player walks into: checkpoints,
## pebble piles, voice logs, control prompts (HINT), zone names, echo crystals
## and the exit.
## Pickups build their own glowing shape, so they read by silhouette and not
## just by color: pebbles = a little cluster of stones that twinkles, logs = a
## recorder with an antenna that pulses, crystals = a tall prism that spins and
## bobs, checkpoints = a lantern shard on a stand that lights up for good.
## Voice logs play when the player presses "interact" inside the area.
## Nothing depends on order: every trigger only cares about the player entering it.

## DAGGER (added last so the other values never change): a combat pickup.
enum Kind { CHECKPOINT, PEBBLES, VOICE_LOG, EXIT, CRYSTAL, HINT, ZONE, JOURNAL, DAGGER }

const GOLD := Color(0.8, 0.627451, 0.2164706)
const CRYSTAL_BLUE := Color(0.45, 0.8, 1.0)
const GLINT := Color(1.0, 0.96, 0.8)
const DAGGER_STEEL := Color(0.75, 0.88, 1.0)
const DaggerModel := preload("res://scripts/combat_dagger_model.gd")

@export var kind := Kind.CHECKPOINT
@export var pebble_amount := 2
## Echo crystals only: 0 = ping radius, 1 = ping cooldown, 2 = max pebbles.
@export var upgrade := 0
@export var sound: AudioStream
## Voice logs: the spoken line (the UI shows it via Game.voice_log).
## HINT without a prompt_id, and other kinds: an optional plain subtitle.
@export_multiline var subtitle := ""
## Voice logs: the log's number (1..8).
@export var log_index := 0
## JOURNAL: the page's number; `subtitle` is its text.
@export var journal_index := 0
## HINT: UI prompt to request ("ping", "whisper", "chalk", "throw", "sneak", "run", "interact", "map").
@export var prompt_id := ""
## ZONE: name the UI shows on entry ("THE VEINS").
@export var zone_name := ""
## Optional Game.level_event fired once, on first entry ("hall_silence").
@export var event_name := ""
## CHECKPOINT: facing on respawn, degrees (0 = north/-Z, -90 = east, 90 = west, 180 = south).
@export var yaw_degrees := 0.0
## CHECKPOINT: position along the route. An earlier checkpoint never replaces a later one.
@export var route_order := 0
## Local height of the floor under the trigger; shapes are built standing on it.
@export var floor_offset := -1.0
@export var build_visual := true

var _used := false
var _picked_since_checkpoint := false
var _player_inside := false
var _event_sent := false
var _overlap_checked := false
var _lit := false
var _flare := 0.0
var _time := 0.0
var _replay_wait := 0.0
var _base_color := GOLD
var _visual: Node3D
var _material: StandardMaterial3D
var _glint: MeshInstance3D
var _stone_spots: Array[Vector3] = []
var _voice: AudioStreamPlayer3D


## Connects signals, joins the checkpoint group and builds the shape.
func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	Game.checkpoint_reached.connect(_on_checkpoint_reached)
	Game.player_caught.connect(_on_player_caught)
	Game.state_changed.connect(_on_state_changed)
	if kind == Kind.CHECKPOINT and not is_in_group("checkpoint"):
		add_to_group("checkpoint")
	_time = randf() * 10.0
	if build_visual:
		_build_visual()
	set_process(_visual != null or kind == Kind.VOICE_LOG)
	# Loaded mid-run (second level): the player may already stand in us.
	if Game.state == Game.State.PLAYING:
		_check_overlap()


## When the run starts, check whether the player is already inside.
func _on_state_changed(state: int) -> void:
	# The player spawns inside the first hint / zone areas while on the title
	# screen, so body_entered is ignored then. Re-check once the run starts.
	if state == Game.State.PLAYING and not _overlap_checked:
		_check_overlap()


## Activates this trigger if the player is already standing in it.
func _check_overlap() -> void:
	_overlap_checked = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree() or Game.state != Game.State.PLAYING:
		return
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_player_inside = true
			_activate()
			return


## The player walked in.
func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = true
	if Game.state == Game.State.PLAYING:
		_activate()


## The player walked out.
func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = false


## Called when the player is inside this trigger during play.
func _activate() -> void:
	_send_level_event()

	if kind == Kind.VOICE_LOG:
		# Played with the interact action while standing here (see _process).
		Game.prompt_requested.emit("interact")
		return

	if not _can_use_now():
		return

	_used = true
	_play_sound()
	if subtitle != "" and kind != Kind.HINT:
		Game.show_subtitle(subtitle)

	match kind:
		Kind.CHECKPOINT:
			_use_checkpoint()
		Kind.PEBBLES:
			_use_pebbles()
		Kind.CRYSTAL:
			_use_crystal()
		Kind.EXIT:
			Game.win()
		Kind.HINT:
			_use_hint()
		Kind.ZONE:
			Game.current_zone = zone_name
			Game.zone_entered.emit(zone_name)
		Kind.DAGGER:
			_use_dagger()
		Kind.JOURNAL:
			_use_journal()


## Sends this trigger's level event (once, except chase events, which repeat
## on every entry because the chase can restart after a catch).
func _send_level_event() -> void:
	if event_name == "":
		return
	var is_chase_event := event_name.begins_with("chase")
	if _event_sent and not is_chase_event:
		return
	_event_sent = true
	Game.level_event.emit(event_name)


## False when this trigger should do nothing right now.
func _can_use_now() -> bool:
	if _used:
		return false
	# Full hands: leave the pile for later instead of wasting it.
	if kind == Kind.PEBBLES and Game.pebbles >= Game.max_pebbles:
		return false
	# An earlier checkpoint never replaces a later one.
	if kind == Kind.CHECKPOINT:
		var best_order := int(get_parent().get_meta("checkpoint_order", -1))
		if route_order < best_order:
			return false
	return true


## Lights the lantern and saves this spot as the respawn point.
func _use_checkpoint() -> void:
	get_parent().set_meta("checkpoint_order", route_order)
	_lit = true
	_flare = 1.6
	var spot := global_position + Vector3(0.0, floor_offset + 0.1, 0.0)
	var yaw := deg_to_rad(yaw_degrees)
	Game.reach_checkpoint(spot, yaw)


## Gives the player the pebbles and hides the pile.
func _use_pebbles() -> void:
	_picked_since_checkpoint = true
	Game.add_pebbles(pebble_amount)
	hide()


## Counts the crystal, applies its upgrade and hides it.
func _use_crystal() -> void:
	Game.crystals_found += 1
	Game.add_stat("crystals")
	var upgrade_text: String = Game.apply_upgrade(upgrade)
	Game.show_subtitle(upgrade_text)
	hide()


## Shows a control prompt, or the plain subtitle when there is no prompt.
func _use_hint() -> void:
	if prompt_id != "":
		Game.prompt_requested.emit(prompt_id)
	elif subtitle != "":
		Game.show_subtitle(subtitle)


## Gives the player the dagger and hides it.
func _use_dagger() -> void:
	Game.pick_dagger()
	Sfx.play("dagger_pickup", -6.0)
	if Game.damage_enabled():
		Game.prompt_requested.emit("attack")
		if subtitle == "":
			Game.show_subtitle("A dagger. They can bleed.")
	hide()


## Hands the journal page to the game state and hides it.
func _use_journal() -> void:
	# game_state.gd records the page and the stat.
	if Game.has_signal("journal_page"):
		Game.emit_signal("journal_page", journal_index, subtitle)
	Sfx.play("pickup_pebbles", -12.0, &"Master", 1.6)
	hide()


## Plays this voice log and marks it as found.
func _play_log() -> void:
	_replay_wait = 1.5
	_play_sound()
	Game.voice_log.emit(log_index, subtitle)
	_used = true
	if not Game.logs_found.has(log_index):
		Game.logs_found.append(log_index)
		Game.add_stat("logs")


## A new checkpoint was reached: pickups before it are now kept for good.
func _on_checkpoint_reached() -> void:
	_picked_since_checkpoint = false


## Respawning restores the pebble count from the last checkpoint, so piles
## picked up after it come back too (otherwise those pebbles are lost forever).
func _on_player_caught() -> void:
	if kind == Kind.PEBBLES and _used and _picked_since_checkpoint:
		_used = false
		_picked_since_checkpoint = false
		show()


## Plays this trigger's own sound if it has one, otherwise a stock sound.
func _play_sound() -> void:
	if sound:
		if _voice == null:
			_voice = AudioStreamPlayer3D.new()
			_voice.stream = sound
			if kind == Kind.VOICE_LOG:
				_voice.bus = &"Voice"
			else:
				_voice.bus = &"Master"
			add_child(_voice)
		_voice.play()
		return
	match kind:
		Kind.CHECKPOINT:
			Sfx.play("chime", -6.0)
		Kind.CRYSTAL:
			Sfx.play("crystal", -4.0)
		Kind.PEBBLES:
			Sfx.play("pickup_pebbles", -5.0)
		Kind.VOICE_LOG:
			Sfx.play("click", -6.0)


## Every frame: voice logs listen for "interact", and the shape animates.
func _process(delta: float) -> void:
	_time += delta
	if kind == Kind.VOICE_LOG:
		_replay_wait = maxf(_replay_wait - delta, 0.0)
		if _wants_to_play_log():
			_play_log()
	if _visual != null and visible:
		_animate(delta)


## True when the player is standing here and just pressed "interact".
func _wants_to_play_log() -> bool:
	if not _player_inside:
		return false
	if _replay_wait > 0.0:
		return false
	if Game.state != Game.State.PLAYING:
		return false
	return Input.is_action_just_pressed("interact")


# ---------------------------------------------------------------- Visuals

## Pulses the glow (and spins / bobs some shapes) each frame.
func _animate(delta: float) -> void:
	var glow := 1.0
	var color := _base_color
	match kind:
		Kind.VOICE_LOG:
			# A gentle pulse; slower and dimmer once it's been heard.
			if _used:
				glow = 0.45 + 0.1 * sin(_time * 1.4)
			else:
				glow = 0.7 + 0.3 * sin(_time * 2.6)
		Kind.CHECKPOINT:
			# Dim until reached, then lit for good with a soft shimmer.
			_flare = maxf(_flare - delta * 1.2, 0.0)
			if _lit:
				color = _base_color.lightened(0.3)
				glow = 0.95 + 0.05 * sin(_time * 3.0) + _flare
			else:
				glow = 0.38 + 0.1 * sin(_time * 1.3)
		Kind.CRYSTAL:
			_visual.rotation.y += delta * 1.3
			_visual.position.y = floor_offset + 0.75 + sin(_time * 1.7) * 0.08
			glow = 0.85 + 0.15 * sin(_time * 3.3)
		Kind.PEBBLES:
			glow = 0.8 + 0.06 * sin(_time * 1.9)
			_twinkle()
		Kind.JOURNAL:
			glow = 0.6 + 0.4 * sin(_time * 2.2)
			_visual.rotation.y += delta * 0.6
		Kind.DAGGER:
			glow = 0.75 + 0.25 * sin(_time * 3.0)
			_visual.rotation.y += delta * 0.9
			_visual.position.y = floor_offset + 0.35 + sin(_time * 1.6) * 0.05
	var red := color.r * glow
	var green := color.g * glow
	var blue := color.b * glow
	_material.albedo_color = Color(red, green, blue, 1.0)


## A tiny bright glint hops between the stones of a pile.
func _twinkle() -> void:
	if _glint == null or _stone_spots.is_empty():
		return
	var phase := _time * 2.1
	# Which twinkle we're on (goes up by one every full sine wave).
	var cycle := int(phase / TAU)
	# A short, sharp flash at the top of each sine wave.
	var wave := maxf(sin(phase), 0.0)
	var brightness := pow(wave, 10.0)
	_glint.visible = brightness > 0.03
	# Jump three stones along each time, wrapping around the pile.
	var spot_index := (cycle * 3) % _stone_spots.size()
	_glint.position = _stone_spots[spot_index]
	_glint.scale = Vector3.ONE * maxf(brightness, 0.05)


## True for the kinds of trigger that get a glowing shape.
func _has_shape() -> bool:
	match kind:
		Kind.PEBBLES, Kind.VOICE_LOG, Kind.CRYSTAL, Kind.CHECKPOINT, Kind.JOURNAL, Kind.DAGGER:
			return true
	return false


## Builds the glowing shape for this kind of pickup.
func _build_visual() -> void:
	if not _has_shape():
		return
	_visual = Node3D.new()
	_visual.name = "Shape"
	add_child(_visual)
	_visual.position = Vector3(0.0, floor_offset, 0.0)
	if kind == Kind.CRYSTAL:
		_base_color = CRYSTAL_BLUE
	elif kind == Kind.DAGGER:
		_base_color = DAGGER_STEEL
	else:
		_base_color = GOLD
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = _base_color
	match kind:
		Kind.PEBBLES:
			_build_pebbles()
		Kind.VOICE_LOG:
			_build_recorder()
		Kind.CRYSTAL:
			_build_crystal()
		Kind.CHECKPOINT:
			_build_lantern_stand()
		Kind.JOURNAL:
			_build_page()
		Kind.DAGGER:
			_build_dagger()


## Adds one glowing mesh piece to the shape.
func _part(mesh: Mesh, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(mi)
	return mi


## A low-detail sphere mesh.
func _sphere(radius: float, height: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 6
	return mesh


## A low-detail cylinder mesh.
func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	return mesh


## A box mesh.
func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## A prism (wedge) mesh.
func _prism(size: Vector3) -> PrismMesh:
	var mesh := PrismMesh.new()
	mesh.size = size
	return mesh


## A small heap of flattened stones.
func _build_pebbles() -> void:
	var spots: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0), Vector3(0.17, 0.0, 0.05), Vector3(-0.14, 0.0, 0.1),
		Vector3(0.05, 0.0, -0.16), Vector3(-0.1, 0.0, -0.11), Vector3(0.03, 0.08, 0.02),
	]
	var sizes: Array[float] = [0.1, 0.075, 0.085, 0.07, 0.065, 0.07]
	for i in spots.size():
		var r := sizes[i]
		var p := spots[i] + Vector3(0.0, r * 0.75, 0.0)
		_part(_sphere(r, r * 1.5), p, Vector3(0.0, i * 47.0, 0.0))
		_stone_spots.append(p + Vector3(0.0, r * 0.6, 0.0))
	_glint = MeshInstance3D.new()
	_glint.mesh = _sphere(0.035, 0.07)
	var glint_material := StandardMaterial3D.new()
	glint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint_material.albedo_color = GLINT
	_glint.material_override = glint_material
	_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glint.visible = false
	_visual.add_child(_glint)


## A handheld recorder lying on the floor, its antenna sticking up.
func _build_recorder() -> void:
	_visual.rotation_degrees = Vector3(0.0, 25.0, 0.0)
	_part(_box(Vector3(0.28, 0.1, 0.16)), Vector3(0.0, 0.05, 0.0))
	# Reel window and button on top.
	_part(_cylinder(0.035, 0.035, 0.02), Vector3(-0.06, 0.11, 0.0))
	_part(_box(Vector3(0.05, 0.02, 0.04)), Vector3(0.06, 0.11, 0.035))
	# Antenna: a thin rod leaning out, with a bead on the tip.
	_part(_cylinder(0.006, 0.01, 0.26), Vector3(0.1, 0.23, -0.05), Vector3(0.0, 0.0, -10.0))
	_part(_sphere(0.018, 0.036), Vector3(0.1226, 0.358, -0.05))


## A tall double-ended prism floating above the floor.
func _build_crystal() -> void:
	_visual.position.y = floor_offset + 0.75
	_part(_prism(Vector3(0.22, 0.55, 0.22)), Vector3(0.0, 0.2, 0.0))
	_part(_prism(Vector3(0.22, 0.55, 0.22)), Vector3(0.0, 0.2, 0.0), Vector3(0.0, 90.0, 0.0))
	_part(_prism(Vector3(0.22, 0.3, 0.22)), Vector3(0.0, -0.225, 0.0), Vector3(180.0, 0.0, 0.0))
	_part(_prism(Vector3(0.22, 0.3, 0.22)), Vector3(0.0, -0.225, 0.0), Vector3(180.0, 90.0, 0.0))


## A shard of the broken lantern held up on a little iron stand.
func _build_lantern_stand() -> void:
	_part(_cylinder(0.2, 0.22, 0.05), Vector3(0.0, 0.025, 0.0))
	_part(_cylinder(0.025, 0.03, 0.85), Vector3(0.0, 0.47, 0.0))
	var cradle := TorusMesh.new()
	cradle.inner_radius = 0.06
	cradle.outer_radius = 0.085
	cradle.rings = 12
	cradle.ring_segments = 6
	_part(cradle, Vector3(0.0, 0.9, 0.0))
	_part(_prism(Vector3(0.16, 0.34, 0.05)), Vector3(0.0, 1.08, 0.0), Vector3(0.0, 0.0, 12.0))
	_part(_prism(Vector3(0.1, 0.2, 0.04)), Vector3(0.06, 1.0, 0.02), Vector3(0.0, 40.0, -25.0))


## A torn notebook page lying on the floor, a little tilted, with a bent corner.
func _build_page() -> void:
	_base_color = Color(0.9, 0.82, 0.55)
	_material.albedo_color = _base_color
	_part(_box(Vector3(0.24, 0.012, 0.32)), Vector3(0.0, 0.03, 0.0), Vector3(4.0, 0.0, 3.0))
	_part(_box(Vector3(0.08, 0.012, 0.08)), Vector3(0.09, 0.05, 0.13), Vector3(0.0, 20.0, 12.0))


## A dagger floating just above the floor, blade tilted down, slowly turning.
func _build_dagger() -> void:
	_visual.position.y = floor_offset + 0.35
	var dagger := DaggerModel.build(_material)
	dagger.scale = Vector3.ONE * 1.6
	dagger.rotation_degrees = Vector3(-60.0, 0.0, 0.0)
	_visual.add_child(dagger)
