extends Node3D

var specimen: Node3D
var animation_player: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var camera: Camera3D
var echo_material: ShaderMaterial
var age := -1.0
var echo_mode := false
var orbit := 0.38
var dragging := false
var clips: Array[StringName] = []
var clip_index := 0
var status: Label
var studio_lights: Array[Light3D] = []

func _ready() -> void:
 var packed := load("res://Listener.glb") as PackedScene
 specimen = packed.instantiate()
 add_child(specimen)
 _collect(specimen)
 echo_material = ShaderMaterial.new()
 echo_material.shader = load("res://review_echo.gdshader")
 var environment := WorldEnvironment.new()
 environment.environment = Environment.new()
 environment.environment.background_mode = Environment.BG_COLOR
 environment.environment.background_color = Color("10171c")
 environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 environment.environment.ambient_light_color = Color("8b9da0")
 environment.environment.ambient_light_energy = 0.35
 add_child(environment)
 _light(Vector3(-3, 5, 4), Color("ffe1b2"), 1.8)
 _light(Vector3(3, 3, 2), Color("82bddb"), 0.9)
 _light(Vector3(2, 4, -3), Color("ff5449"), 2.4)
 camera = Camera3D.new()
 camera.fov = 34
 add_child(camera)
 _camera_update()
 var floor_mesh := MeshInstance3D.new()
 var plane := PlaneMesh.new()
 plane.size = Vector2(20, 20)
 floor_mesh.mesh = plane
 var mat := StandardMaterial3D.new()
 mat.albedo_color = Color("151c20")
 mat.roughness = 0.9
 floor_mesh.material_override = mat
 floor_mesh.position.y = -0.025
 add_child(floor_mesh)
 var canvas := CanvasLayer.new()
 add_child(canvas)
 var title := Label.new()
 title.text = "ECHO  /  THE HOLLOW CHOIR\nLISTENER — ORIGINAL CREATURE ASSET"
 title.position = Vector2(30, 25)
 title.add_theme_font_size_override("font_size", 23)
 canvas.add_child(title)
 status = Label.new()
 status.position = Vector2(30, 815)
 status.add_theme_font_size_override("font_size", 17)
 canvas.add_child(status)
 if animation_player:
  for anim_name in animation_player.get_animation_list():
   if anim_name != "RESET":
    clips.append(anim_name)
    var anim := animation_player.get_animation(anim_name)
    if not "Alert" in str(anim_name):
     anim.loop_mode = Animation.LOOP_LINEAR
  if not clips.is_empty():
   clip_index = max(0, clips.find("Idle_Breathe"))
   animation_player.play(clips[clip_index])
 _status_update()
 if "--smoke-test" in OS.get_cmdline_user_args():
  _set_echo(true)
 print("REVIEW_READY meshes=", meshes.size(), " clips=", clips)

func _collect(node: Node) -> void:
 if node is MeshInstance3D:
  meshes.append(node)
 if node is AnimationPlayer:
  animation_player = node
 for child in node.get_children():
  _collect(child)

func _light(pos: Vector3, color: Color, power: float) -> void:
 var lamp := OmniLight3D.new()
 lamp.position = pos
 lamp.light_color = color
 lamp.light_energy = power
 lamp.omni_range = 12
 add_child(lamp)
 studio_lights.append(lamp)

func _camera_update() -> void:
 camera.position = Vector3(sin(orbit) * 7.5, 2.5, cos(orbit) * 7.5)
 camera.look_at(Vector3(0, 1.65, 0))

func _status_update() -> void:
 var clip_name := str(clips[clip_index]) if not clips.is_empty() else "none"
 status.text = "SPACE  echo pulse     TAB  studio / echo     N  next animation     Drag  orbit\n" + ("ECHO" if echo_mode else "STUDIO") + "  /  " + clip_name

func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and not event.echo:
  if event.keycode == KEY_SPACE:
   if not echo_mode:
    _set_echo(true)
   age = 0.0
  elif event.keycode == KEY_TAB:
   _set_echo(not echo_mode)
  elif event.keycode == KEY_N and not clips.is_empty():
   clip_index = (clip_index + 1) % clips.size()
   animation_player.play(clips[clip_index], 0.2)
  _status_update()
 if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
  dragging = event.pressed
 if event is InputEventMouseMotion and dragging:
  orbit -= event.relative.x * 0.007
  _camera_update()

func _set_echo(value: bool) -> void:
 echo_mode = value
 for mesh in meshes:
  mesh.material_override = echo_material if value else null
 age = 0.0 if value else -1.0

func _process(delta: float) -> void:
 if "--smoke-test" in OS.get_cmdline_user_args() and not clips.is_empty():
  var next_clip := int(Engine.get_process_frames() / 30) % clips.size()
  if next_clip != clip_index:
   clip_index = next_clip
   animation_player.play(clips[clip_index])
 if age >= 0:
  age += delta
 echo_material.set_shader_parameter("ping_age", age)
