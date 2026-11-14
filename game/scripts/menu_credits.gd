extends Control
## Credits: a slow roll. Full screen with a Back button from the main menu, or
## `embedded` (no background, no button) in a column of the end screen.

signal closed

const Style = preload("res://scripts/ui_style.gd")
## [text, font size, color]. Asset credits mirror game/CREDITS.md: keep both
## in sync when adding a sound, model or texture.
const LINES := [
	["ECHO", 60, "cyan"],
	["A game about echolocation i guess", 20, "muted"],
	["", 30, "text"],
	["TEAM", 20, "gold"],
	["Shreyansh Nikam", 30, "text"],
	["Elias Chen", 30, "text"],
	["Atharv", 30, "text"],
	["", 30, "text"],
	["SOUND", 20, "gold"],
	["Freesound.org, CC0", 16, "muted"],
	["Sonar ping - SamsterBirdies", 16, "text"],
	["Stone footsteps - SecureSubset", 16, "text"],
	["Wood footsteps - Nox_Sound", 16, "text"],
	["Gravel footsteps - Anilan", 16, "text"],
	["Water footsteps - Adielees9", 16, "text"],
	["Pebble impacts - kevinklang", 16, "text"],
	["Pebble pickup - EricsSoundschmiede", 16, "text"],
	["Cave ambience - fonografico", 16, "text"],
	["Listener breathing - mucky_pete7", 16, "text"],
	["Water drips - paespedro", 16, "text"],
	["Heartbeat - loudernoises", 16, "text"],
	["Wind - BaDoink", 16, "text"],
	["Listener shriek - Darsycho", 16, "text"],
	["Stone scrape - alegemaate", 16, "text"],
	["Rope creaks - Rmutt", 16, "text"],
	["Rope snap - zepurple", 16, "text"],
	["Chalk - Breviceps", 16, "text"],
	["Rock knocks - mateozugi19", 16, "text"],
	["Horror sting - shelbyshark", 16, "text"],
	["Chimes - plasterbrain", 16, "text"],
	["Menu clicks - cabled_mess", 16, "text"],
	["Tape recorder - ACPascal", 16, "text"],
	["Tape hiss - kijjaz", 16, "text"],
	["Breathing - Nox_Sound", 16, "text"],
	["Rockfall - iwanPlays (adamgryu, AlanCat, spookymodem)", 16, "text"],
	["Birdsong - AMichaelWilson", 16, "text"],
	["Hiss and jumpscare - qubodup", 16, "text"],
	["Whispers - geoneo0", 16, "text"],
	["", 16, "text"],
	["OpenGameArt.org, CC0", 16, "muted"],
	["Sonar ping - Spiceman", 16, "text"],
	["Footstep - GboxMikeFozzy", 16, "text"],
	["Heartbeats - bart", 16, "text"],
	["Wind loop - SketchMan3", 16, "text"],
	["Dungeon ambience - JaggedStone", 16, "text"],
	["Birds - isaiah658", 16, "text"],
	["Tired breathing - mikeask", 16, "text"],
	["Alien hiss - EZduzziteh", 16, "text"],
	["", 30, "text"],
	["ART", 20, "gold"],
	["All CC0 unless noted", 16, "muted"],
	["Cave rock, moss, mud and plank textures - Poly Haven", 16, "text"],
	["Rock and boulder models - Poly Haven", 16, "text"],
	["Ending sky (Kloofendal HDRI) - Greg Zaal / Poly Haven", 16, "text"],
	["Barrels, crates, rubble, chest, candles (KayKit Dungeon Remastered) - Kay Lousberg", 16, "text"],
	["Skull, bones, lantern (KayKit Halloween Bits) - Kay Lousberg", 16, "text"],
	["Redaction typeface - Titus Kaphar, Reginald Dwayne Betts and Jeremy Mickel (SIL Open Font License)", 16, "text"],
	["The Listener creature and jumpscare - made for this project in Blender with AI-assisted scripting", 16, "text"],
	["Mine supports, rails, cart and backpack - built in Godot", 16, "text"],
	["", 30, "text"],
	
	["Built with Godot 4", 20, "cyan"],
	["Made for Hack Club Haven - Theme: Bounce Back", 20, "muted"],
	["", 20, "text"],
	["Thank you for listening. (haha get it)", 10, "gold"],
]

var embedded := false
var speed := 32.0

var _clip: Control
var _content: VBoxContainer
var _back: Button
var _offset := 0.0


## Builds the scrolling text (and the background and Back button when not embedded).
func _ready() -> void:
	Style.full_rect(self)
	if embedded:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		mouse_filter = Control.MOUSE_FILTER_STOP
	if not embedded:
		var dim := Style.full_rect(ColorRect.new()) as ColorRect
		dim.color = Color(0.0, 0.0, 0.0, 0.82)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.anchor_bottom = 1.0
	if embedded:
		# Fill the whole column.
		_clip.anchor_left = 0.0
		_clip.anchor_right = 1.0
		_clip.offset_left = 0.0
		_clip.offset_right = 0.0
		_clip.offset_top = 0.0
		_clip.offset_bottom = 0.0
	else:
		# A centered strip, 760 px wide.
		_clip.anchor_left = 0.5
		_clip.anchor_right = 0.5
		_clip.offset_left = -380.0
		_clip.offset_right = 380.0
		_clip.offset_top = 40.0
		_clip.offset_bottom = -100.0
	add_child(_clip)
	_content = VBoxContainer.new()
	_content.anchor_right = 1.0
	_content.add_theme_constant_override("separation", 6)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_content)
	for line in LINES:
		var line_text: String = str(line[0])
		var font_size: int = int(line[1])
		var color_name: String = str(line[2])
		var col: Color = Style.TEXT
		if color_name == "cyan":
			col = Style.CYAN
		elif color_name == "gold":
			col = Style.GOLD
		elif color_name == "muted":
			col = Style.MUTED
		var l := Style.label(line_text, font_size, col)
		if font_size >= 20:
			l.add_theme_font_override("font", Style.spaced_font())
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(l)
	if not embedded:
		_back = Style.chalk_button("BACK", 28)
		_back.anchor_left = 0.5
		_back.anchor_right = 0.5
		_back.anchor_top = 1.0
		_back.anchor_bottom = 1.0
		_back.offset_left = -120.0
		_back.offset_right = 120.0
		_back.offset_top = -86.0
		_back.offset_bottom = -40.0
		_back.pressed.connect(close)
		add_child(_back)
		visible = false


## Shows the credits from the start.
func open() -> void:
	visible = true
	_offset = 0.0
	if _back != null:
		_back.grab_focus()


## Hides the credits.
func close() -> void:
	Sfx.play("ui_back", -6.0)
	visible = false
	closed.emit()


## Scrolls the text up, and starts again once it has all gone past.
func _process(delta: float) -> void:
	if not visible or _clip == null:
		return
	_offset += speed * delta
	_content.position.y = _clip.size.y - _offset
	if _content.position.y + _content.size.y < 0.0:
		_offset = 0.0


## Esc / pause closes the full-screen credits.
func _unhandled_input(event: InputEvent) -> void:
	if embedded or not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
