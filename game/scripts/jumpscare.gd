extends TextureRect
## The rendered Blender attack, packed as an atlas for native and web builds.
## Starts at the recoil so a catch does not replay the quiet two-second setup.
signal finished
const SHEET = preload("res://assets/jumpscare/listener_attack.png")
const SOUND = preload("res://assets/jumpscare/listener_attack.wav")
const FRAME_SIZE := Vector2(640, 360)
const COLUMNS := 6
const FRAMES := 38
const FPS := 24.0
var _elapsed := 0.0
var _atlas := AtlasTexture.new()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_atlas.atlas = SHEET
	_atlas.filter_clip = true
	texture = _atlas
	_show_frame(0)
	var audio := AudioStreamPlayer.new()
	audio.stream = SOUND
	audio.bus = &"Cave"
	add_child(audio)
	audio.play()

func _process(delta: float) -> void:
	_elapsed += delta
	_show_frame(mini(int(_elapsed * FPS), FRAMES - 1))
	if _elapsed >= FRAMES / FPS:
		set_process(false)
		finished.emit()

func _show_frame(index: int) -> void:
	var cell := Vector2(index % COLUMNS, floori(float(index) / COLUMNS))
	_atlas.region = Rect2(cell * FRAME_SIZE, FRAME_SIZE)
