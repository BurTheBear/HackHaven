extends Node3D
## Builds a Listener's body out of primitives: a hunched torso with a ridge of
## vertebrae, a small head pushed forward on a long neck, a hanging jaw, and
## long thin arms whose fingers almost drag on the floor. Every part uses the
## red reveal material, so it only exists in echoes. Feet at the root's
## origin, facing -Z. Used by listener.gd and by the director's phantoms.
## build() also attaches this script to the root it builds under (if that
## root has no script), so callers can use root.flash_hurt() / set_dying().

const RED := Color(1.0, 0.23, 0.31)
const MODEL_PATH := "res://assets/models/listener.glb"
const MODEL_SCALE := 0.72
const AnimDriver := preload("res://scripts/ai_listener_anim.gd")
const ALBEDO_PATH := "res://assets/models/listener_Listener_Albedo_2K.png"
const NORMAL_PATH := "res://assets/models/listener_Listener_Normal_2K.png"
const SELF_PATH := "res://scripts/ai_listener_body.gd"

var _mat: ShaderMaterial
var _model: Node3D
var _flash := 0.0
var _flash_tween: Tween
var _jolt_tween: Tween
var _rest_pos := Vector3.ZERO
var _rest_rot := Vector3.ZERO


## Briefly flashes the Listener white-hot and jolts it back (a stagger).
func flash_hurt() -> void:
	if _mat == null:
		return
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_method(_set_flash, 1.0, 0.0, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	var target: Node3D = _model if _model != null else self
	if _jolt_tween and _jolt_tween.is_valid():
		_jolt_tween.kill()
		target.position = _rest_pos
		target.rotation = _rest_rot
	_rest_pos = target.position
	_rest_rot = target.rotation
	var back := Vector3(0.0, 0.0, 0.12)
	_jolt_tween = create_tween()
	_jolt_tween.tween_property(target, "position", _rest_pos + back, 0.06).set_ease(Tween.EASE_OUT)
	_jolt_tween.parallel().tween_property(target, "rotation:x", _rest_rot.x - 0.18, 0.06)
	_jolt_tween.tween_property(target, "position", _rest_pos, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	_jolt_tween.parallel().tween_property(target, "rotation:x", _rest_rot.x, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)


## 0..1: darkens the Listener and dissolves it away.
func set_dying(t: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("dying", clampf(t, 0.0, 1.0))


func _set_flash(v: float) -> void:
	_flash = v
	if _mat != null:
		_mat.set_shader_parameter("hurt_flash", v)


## Red reveal material. Its afterglow is longer than the cave's, so a
## Listener's outline lingers after the walls around it have faded.
static func make_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/reveal.gdshader") as Shader
	mat.set_shader_parameter("echo_color", RED)
	mat.set_shader_parameter("grid_scale", 3.0)
	mat.set_shader_parameter("near_glow", 0.0)
	mat.set_shader_parameter("afterglow", 3.2)
	mat.set_shader_parameter("use_grid", 0.0)
	mat.set_shader_parameter("listener_look", 1.0)
	return mat


## Builds the body under `root` and returns the head pivot (rotate it to look
## around). Uses the Listener model (listener.glb, red reveal material, animated
## by the parent Listener); falls back to the primitive body if it won't load.
static func build(root: Node3D, mat: Material) -> Node3D:
	if root.get_script() == null:
		root.set_script(load(SELF_PATH))
	if root.has_method("_attach"):
		root.call("_attach", mat)
	var head := _build_model(root, mat)
	if head == null:
		head = _build_primitive(root, mat)
	return head


func _attach(mat: Material) -> void:
	_mat = mat as ShaderMaterial


static func _set_textures(mat: Material, albedo: Texture2D, normal: Texture2D) -> void:
	var sm := mat as ShaderMaterial
	if sm == null:
		return
	sm.set_shader_parameter("albedo_tex", albedo)
	if normal != null:
		sm.set_shader_parameter("listener_normal", normal)


static func _build_model(root: Node3D, mat: Material) -> Node3D:
	if not ResourceLoader.exists(MODEL_PATH):
		return null
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null
	# About 3.36 m tall at 1.0; 0.72 gives ~2.4 m. The model faces +Z.
	inst.scale = Vector3.ONE * MODEL_SCALE
	inst.rotation.y = PI
	root.add_child(inst)
	if root.has_method("_attach"):
		root.set("_model", inst)
	var albedo: Texture2D = null
	if ResourceLoader.exists(ALBEDO_PATH):
		albedo = load(ALBEDO_PATH) as Texture2D
	var normal: Texture2D = null
	if ResourceLoader.exists(NORMAL_PATH):
		normal = load(NORMAL_PATH) as Texture2D
	if albedo != null:
		_set_textures(mat, albedo, normal)
	else:
		_set_textures(mat, _flat_texture(), null)
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		part.material_override = mat
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.extra_cull_margin = 1.0
	var player := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		var driver := AnimDriver.new()
		driver.name = "AnimDriver"
		root.add_child(driver)
		var host: Node = root.get_parent()
		if host == null:
			host = root
		driver.setup(player, host)
	# The model animates its own head; this pivot is only here for the callers.
	var head := Node3D.new()
	head.name = "Head"
	root.add_child(head)
	head.position = Vector3(0.0, 2.2, -0.3)
	return head


## A 1x1 dark flesh texture for bodies without the model's albedo.
static func _flat_texture() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
	img.fill(Color(0.24, 0.07, 0.07))
	return ImageTexture.create_from_image(img)


static func _build_primitive(root: Node3D, mat: Material) -> Node3D:
	_set_textures(mat, _flat_texture(), null)
	var lean := deg_to_rad(-52.0)
	var spine := Vector3(0.0, cos(lean), sin(lean))  # torso axis, leaning forward
	var back := Vector3(0.0, -sin(lean), cos(lean))  # out of the hunched back
	var hips := Vector3(0.0, 0.95, 0.08)
	var chest := hips + spine * 0.85
	var sides: Array[float] = [-1.0, 1.0]

	# Bent, bony legs with long feet.
	for side in sides:
		var hip := hips + Vector3(0.16 * side, 0.0, 0.0)
		var knee := Vector3(0.2 * side, 0.5, -0.12)
		var foot := Vector3(0.22 * side, 0.06, 0.05)
		_limb(root, hip, knee, 0.085, mat)
		_limb(root, knee, foot, 0.07, mat)
		_ball(root, foot + Vector3(0.0, 0.0, -0.08), 0.07, Vector3(1.0, 0.6, 1.8), mat)

	# Hunched torso and pelvis.
	_limb(root, hips, chest, 0.24, mat)
	_ball(root, hips, 0.2, Vector3(1.2, 0.9, 1.0), mat)
	# A ridge of vertebrae along the curved back.
	for k in 6:
		var u := float(k) / 5.0
		var p := hips.lerp(chest, u) + back * (0.22 + 0.05 * sin(u * PI))
		_ball(root, p, 0.055, Vector3.ONE, mat)
	# Wide, bony shoulders.
	var shoulders := chest + back * 0.05
	_limb(root, shoulders + Vector3(-0.34, -0.02, 0.0), shoulders + Vector3(0.34, -0.02, 0.0), 0.08, mat)

	# Long neck reaching forward, and a small head pushed out in front.
	var neck_end := chest + Vector3(0.0, 0.02, -0.3)
	_limb(root, chest, neck_end, 0.06, mat)
	var head := Node3D.new()
	head.name = "Head"
	root.add_child(head)
	head.position = neck_end
	_ball(head, Vector3(0.0, 0.02, -0.1), 0.12, Vector3(0.85, 0.9, 1.35), mat)
	var jaw := _ball(head, Vector3(0.0, -0.08, -0.15), 0.07, Vector3(0.9, 0.45, 1.6), mat)
	jaw.rotation.x = deg_to_rad(-18.0)  # hanging open

	# Long thin arms; three splayed fingers each, almost touching the floor.
	for side in sides:
		var shoulder := shoulders + Vector3(0.36 * side, -0.04, 0.0)
		var elbow := Vector3(0.46 * side, 0.85, -0.55)
		var wrist := Vector3(0.42 * side, 0.2, -0.72)
		_limb(root, shoulder, elbow, 0.055, mat)
		_limb(root, elbow, wrist, 0.045, mat)
		for f in 3:
			var spread := (float(f) - 1.0) * 0.07
			var tip := wrist + Vector3(spread + 0.03 * side, -0.17, -0.06 + absf(spread) * 0.3)
			_limb(root, wrist, tip, 0.016, mat)
	return head


## A capsule from a to b.
static func _limb(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = a.distance_to(b) + radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 3
	var part := _part(parent, mesh, mat)
	part.position = (a + b) * 0.5
	part.basis = _y_to(b - a)
	return part


## A (squashed) sphere.
static func _ball(parent: Node3D, pos: Vector3, radius: float, squash: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var part := _part(parent, mesh, mat)
	part.position = pos
	part.scale = squash
	return part


static func _part(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = mat
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


## A rotation that turns +Y onto `dir` (capsules are built along +Y).
static func _y_to(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD
	if absf(y.dot(ref)) > 0.95:
		ref = Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
