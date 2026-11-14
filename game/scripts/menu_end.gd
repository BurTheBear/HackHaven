extends Control
## End screen, after the color reveal: the line first, stats fade in after a
## beat, then the rank, challenges and buttons, while the credits roll.

signal play_again_pressed
signal menu_pressed
signal deeper_pressed

const Style = preload("res://scripts/ui_style.gd")
const Credits = preload("res://scripts/menu_credits.gd")
const SHADE := """
shader_type canvas_item;
void fragment() {
	COLOR = vec4(0.0, 0.0, 0.0, 0.72 * (1.0 - smoothstep(0.25, 0.7, UV.x)));
}
"""

var _column: VBoxContainer
var _title: Label
var _reveal: Array[Control] = []
var _buttons: Array[Button] = []
var _credits: Control


func _ready() -> void:
	Style.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func show_end(can_go_deeper: bool, total_logs: int, total_crystals: int) -> void:
	for c in get_children():
		c.queue_free()
	_reveal.clear()
	_buttons.clear()
	visible = true

	var shade := Style.full_rect(ColorRect.new()) as ColorRect
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	shade.material = mat
	add_child(shade)

	_column = VBoxContainer.new()
	_column.anchor_left = 0.07
	_column.anchor_right = 0.55
	_column.anchor_top = 0.08
	_column.anchor_bottom = 0.95
	_column.add_theme_constant_override("separation", 6)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)

	_title = Style.label("You found your way back.", 46, Color(1.0, 0.97, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.modulate.a = 0.0
	_column.add_child(_title)
	var twist := Style.label("Mara never left. She just stopped needing her eyes.", 17, Color(0.75, 0.82, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	twist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(twist)
	_gap(10)

	var pings := Game.get_stat("pings")
	var caught := Game.times_caught
	var journals := Game.journal_found.size()
	var journal_total := Game.journal_total()
	_stat("Time", Style.format_time(Game.run_time, true))
	_stat("Caught", str(caught))
	_stat("Pings", str(pings))
	_stat("Pebbles thrown", str(Game.get_stat("pebbles_thrown")))
	_stat("Near misses", str(Game.get_stat("near_misses")))
	_stat("Hides", str(Game.get_stat("hides")))
	if total_crystals > 0:
		_stat("Echo crystals", "%d / %d" % [Game.crystals_found, total_crystals])
	_stat("Mara's logs", "%d / %d" % [Game.logs_found.size(), total_logs])
	_stat("Journal pages", "%d / %d" % [journals, journal_total])
	var secrets := Game.logs_found.size() + journals + Game.crystals_found
	var secrets_total := total_logs + journal_total + total_crystals
	var full := secrets_total > 0 and secrets >= secrets_total
	_stat("Secrets", "%d / %d%s" % [secrets, secrets_total, "    100%" if full else ""])
	if Game.best_time > 0.0:
		_stat("Best time", Style.format_time(Game.best_time, true) + ("    NEW BEST" if Game.new_best else ""))
	if Game.challenge != "":
		_stat("Challenge", Game.challenge_name())
	_gap(10)

	var rank := Game.compute_rank()
	var best := Game.record_rank(rank)
	var why := "You made it. That's what matters."
	match rank:
		"GHOST":
			why = "Never caught, barely a sound. They never knew you were there."
		"SILENT":
			why = "Never caught. The dark never got its hands on you."
		"ECHO":
			why = "Three catches or fewer. You listened more than you ran."
		"LOUD":
			why = "The whole Hollow knows your voice now."
	var rank_label := Style.label("RANK   " + rank, 34, Style.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	rank_label.add_theme_font_override("font", Style.spaced_font())
	_add_reveal(rank_label)
	var why_label := Style.label(why, 17, Style.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	_add_reveal(why_label)
	_add_reveal(Style.label("Best rank: %s    ·    Replay for a better rank" % best, 16, Style.CYAN, HORIZONTAL_ALIGNMENT_LEFT))
	_gap(10)

	_add_reveal(Style.label("CHALLENGES", 16, Style.CYAN, HORIZONTAL_ALIGNMENT_LEFT))
	_challenge("Ghost: never caught", caught == 0)
	_challenge("Quiet: under 10 pings", pings < 10)
	_challenge("Steady: never ran", Game.get_stat("ran") == 0)
	_challenge("Collector: 100% secrets", full)
	_challenge("Archivist: every one of Mara's logs", Game.logs_found.size() >= total_logs)
	if total_crystals > 0:
		_challenge("Resonant: every echo crystal", Game.crystals_found >= total_crystals)
	_challenge("Swift: under 6 minutes", Game.run_time < 360.0)
	_gap(16)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_reveal(row)
	_button(row, "PLAY AGAIN", func(): play_again_pressed.emit())
	if can_go_deeper:
		_button(row, "GO DEEPER", func(): deeper_pressed.emit())
	_button(row, "MAIN MENU", func(): menu_pressed.emit())
	for i in _buttons.size():
		var b := _buttons[i]
		var prev := _buttons[(i - 1 + _buttons.size()) % _buttons.size()]
		var next := _buttons[(i + 1) % _buttons.size()]
		b.focus_neighbor_left = b.get_path_to(prev)
		b.focus_neighbor_right = b.get_path_to(next)

	_credits = Credits.new()
	_credits.set("embedded", true)
	_credits.set("speed", 26.0)
	add_child(_credits)
	_credits.anchor_left = 0.62
	_credits.anchor_right = 0.94
	_credits.anchor_top = 0.08
	_credits.anchor_bottom = 0.92
	_credits.offset_left = 0.0
	_credits.offset_right = 0.0
	_credits.offset_top = 0.0
	_credits.offset_bottom = 0.0
	_credits.modulate.a = 0.0

	_play()


func _gap(h: float) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(c)


func _add_reveal(c: Control) -> void:
	c.modulate.a = 0.0
	_column.add_child(c)
	_reveal.append(c)


func _stat(name_text: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := Style.label(name_text, 21, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	n.custom_minimum_size = Vector2(230, 0)
	row.add_child(n)
	row.add_child(Style.label(value, 21, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
	_add_reveal(row)


func _challenge(text: String, done: bool) -> void:
	var l := Style.label(("•  " if done else "·  ") + text, 18, Style.GOLD if done else Color(0.5, 0.53, 0.56), HORIZONTAL_ALIGNMENT_LEFT)
	_add_reveal(l)


func _button(row: HBoxContainer, text: String, action: Callable) -> void:
	var b := Style.chalk_button(text, 24)
	b.pressed.connect(_on_pressed.bind(action))
	b.mouse_entered.connect(b.grab_focus)
	b.focus_entered.connect(_on_hover)
	row.add_child(b)
	_buttons.append(b)


func _on_pressed(action: Callable) -> void:
	Sfx.play("ui_click", -6.0)
	action.call()


func _on_hover() -> void:
	Sfx.play("ui_hover", -12.0)


func _play() -> void:
	var tw := create_tween()
	tw.tween_property(_title, "modulate:a", 1.0, 1.8)
	tw.tween_interval(1.2)
	for c in _reveal:
		tw.tween_property(c, "modulate:a", 1.0, 0.35)
		tw.tween_interval(0.08)
	tw.tween_callback(_focus_first)
	tw.tween_property(_credits, "modulate:a", 1.0, 1.5)


func _focus_first() -> void:
	if not _buttons.is_empty():
		_buttons[0].grab_focus()
