extends Node3D
## Puts the reveal shader on every mesh/CSG under Geometry, builds the chalk
## arrows, brightens the daylight as the player gets closer, floats dust motes
## that catch your echo, and takes the shader off again for the color ending.
##
## Materials (all made from reveal_material):
## - world: the cave. Switches on the shader's echo memory, assist floor
##   outline, gold pebble pings and close-up afterglow boost (they default to
##   off in the shader so Listener materials don't get them).
## - chalk: the arrows (group "chalk"), drawn in white.
## - landmark: anything in group "landmark" (the node or a parent under
##   Geometry) keeps its afterglow longer, so players can get their bearings.
## - any GeometryInstance3D with a "reveal_params" metadata Dictionary gets its
##   own variant with those shader parameters (water: slow, rippling echoes).
## Chalk arrows: add a Marker3D under Geometry/Arrows, lying on the floor.
## Its "yaw" metadata (degrees) sets the direction: 0 = north (-Z),
## -90 = east (+X), 90 = west (-X), 180 = south (+Z).
## Textures: the cave CSG is triplanar-textured in the shader (wet stone on
## floor-facing surfaces, rock on walls/ceiling). Props are instanced from
## res://scenes/<this scene's name>_props.tscn under Geometry. Imported props
## use their own albedo texture; primitive props pick a look with a "surf"
## metadata string ("wood", "rock", "metal", "rust").
## Daylight: MeshInstance3D nodes in group "daylight" with an unshaded
## StandardMaterial3D override; they glow brighter the closer the player is.

const WORLD_PARAMS := {
	"echo_memory": 0.07,
	"floor_hint": 1.0,
	"pebble_tint": 0.5,
	"close_boost": 0.9,
}
const LANDMARK_PARAMS := {
	"afterglow": 4.5,
	"echo_memory": 0.16,
}
## Daylight is dim from DAY_FAR meters away and full strength at DAY_NEAR.
const DAY_NEAR := 6.0
const DAY_FAR := 50.0
const DAY_MIN := 0.18

const TEX_DIR := "res://assets/textures/"
const SKY_HDRI := "res://assets/hdri/sky.hdr"
const WALL_TEX := {"level": "dark_rock_02", "level2": "mossy_rock"}
const DEFAULT_WALL_TEX := "dark_rock_02"
const FLOOR_TEX := "brown_mud_03"
const PROP_ROCK_TEX := "rock_face_04"
const WOOD_TEX := "weathered_planks"
const WOOD_COLOR := Color(0.46, 0.31, 0.17)
const TEX_SCALE := 0.3
## Color ending: darker, wetter PBR (albedo tint, roughness multiplier).
const ENDING_TINT := {
	"cave": Color(0.62, 0.62, 0.66),
	"floor": Color(0.55, 0.52, 0.5),
	"rock": Color(0.6, 0.6, 0.63),
	"wood": Color(0.58, 0.52, 0.47),
}
const ENDING_ROUGH := {"cave": 0.75, "floor": 0.55, "rock": 0.8, "wood": 0.95}
const SURF_COLORS := {
	"metal": Color(0.36, 0.37, 0.4),
	"rust": Color(0.43, 0.22, 0.12),
	"rope": Color(0.72, 0.62, 0.42),
	"cloth": Color(0.2, 0.27, 0.36),
}

## Color-ending floor pass: world-space planar mapping on surfaces facing up,
## faded out on walls so the wall set shows there.
const FLOOR_OVERLAY_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
uniform sampler2D tex_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rough : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_ao : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.55);
uniform float rough_mul = 0.55;
uniform float tex_scale = 0.3;
varying vec3 wpos;
varying vec3 wnor;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnor = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec2 uv = wpos.xz * tex_scale;
	float up = smoothstep(0.55, 0.8, wnor.y);
	ALBEDO = texture(tex_albedo, uv).rgb * tint;
	NORMAL_MAP = texture(tex_normal, uv).rgb;
	NORMAL_MAP_DEPTH = 1.3;
	ROUGHNESS = texture(tex_rough, uv).r * rough_mul;
	AO = texture(tex_ao, uv).r;
	AO_LIGHT_AFFECT = 0.6;
	ALPHA = up;
}
"""

@export var reveal_material: Material

var _world_material: ShaderMaterial
var _chalk_material: ShaderMaterial
var _landmark_material: ShaderMaterial
var _variants := {}
var _std_cache := {}
var _daylights: Array[GeometryInstance3D] = []
var _day_colors: Array[Color] = []
var _motes: CPUParticles3D
var _mote_material: StandardMaterial3D


func _ready() -> void:
	_add_props()
	_make_materials()
	_build_arrows()
	_apply(true)
	_find_daylights()
	_make_motes()


func reveal_colors() -> void:
	_apply(false)
	_set_ending_sky()
	if _motes:
		_motes.visible = false


## Instances scenes/<this scene's file name>_props.tscn under Geometry.
func _add_props() -> void:
	if not has_node("Geometry"):
		return
	var path := "res://scenes/%s_props.tscn" % scene_file_path.get_file().get_basename()
	if not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var props := packed.instantiate()
	props.name = "DressingProps"
	$Geometry.add_child(props)
	_add_prop_collision(props)


## Gives every prop a simple box collider (world layer 1) so the player,
## pebbles, Listeners and raycasts treat it as solid. Tiny or flat pieces
## (bones, rope, puddles, scraps) stay walk-through so nobody snags on them.
## Opt out per node with the group "no_collision".
const PROP_MIN_SIZE := 0.3
const PROP_MIN_HEIGHT := 0.12


func _add_prop_collision(root: Node) -> void:
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		if _tagged(node, "no_collision"):
			continue
		var csg := node as CSGShape3D
		if csg != null:
			if csg.is_root_shape():
				csg.use_collision = true
			continue
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box := mi.get_aabb()
		var world_size := box.size * mi.global_transform.basis.get_scale().abs()
		if maxf(world_size.x, maxf(world_size.y, world_size.z)) < PROP_MIN_SIZE or world_size.y < PROP_MIN_HEIGHT:
			continue
		var body := StaticBody3D.new()
		body.name = "PropCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var cube := BoxShape3D.new()
		cube.size = Vector3(maxf(box.size.x, 0.01), maxf(box.size.y, 0.01), maxf(box.size.z, 0.01))
		shape.shape = cube
		shape.position = box.get_center()
		body.add_child(shape)
		mi.add_child(body)


## Daylight sky from the HDRI for the color ending.
func _set_ending_sky() -> void:
	var scene := get_tree().current_scene
	if scene == null or not ResourceLoader.exists(SKY_HDRI):
		return
	var we := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load(SKY_HDRI) as Texture2D
	var sky := Sky.new()
	sky.sky_material = pano
	var env := we.environment
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY


func _tex(tex_name: String, suffix: String) -> Texture2D:
	var path := "%s%s_%s.jpg" % [TEX_DIR, tex_name, suffix]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## Switches a reveal material to triplanar sampling of the given texture sets.
func _set_triplanar(mat: ShaderMaterial, wall: String, floor_name: String, tile: float = TEX_SCALE) -> void:
	var wall_tex := _tex(wall, "diff")
	var floor_tex := _tex(floor_name, "diff")
	if wall_tex == null or floor_tex == null:
		return
	mat.set_shader_parameter("tex_wall", wall_tex)
	mat.set_shader_parameter("tex_floor", floor_tex)
	var wall_nor := _tex(wall, "nor")
	var floor_nor := _tex(floor_name, "nor")
	if wall_nor != null:
		mat.set_shader_parameter("nor_wall", wall_nor)
	if floor_nor != null:
		mat.set_shader_parameter("nor_floor", floor_nor)
	mat.set_shader_parameter("tex_scale", tile)
	mat.set_shader_parameter("use_triplanar", 1.0)


func _set_flat(mat: ShaderMaterial, color: Color) -> void:
	mat.set_shader_parameter("use_triplanar", 0.0)
	mat.set_shader_parameter("use_albedo_tex", 0.0)
	mat.set_shader_parameter("use_flat", 1.0)
	mat.set_shader_parameter("albedo_color", color)


func _make_materials() -> void:
	var base := reveal_material as ShaderMaterial
	if base == null:
		base = ShaderMaterial.new()
		base.shader = preload("res://shaders/reveal.gdshader")
	_world_material = base.duplicate() as ShaderMaterial
	_set_params(_world_material, WORLD_PARAMS)
	var wall := str(WALL_TEX.get(scene_file_path.get_file().get_basename(), DEFAULT_WALL_TEX))
	_set_triplanar(_world_material, wall, FLOOR_TEX)
	_chalk_material = _world_material.duplicate() as ShaderMaterial
	_set_flat(_chalk_material, Color(0.85, 0.85, 0.85))
	_chalk_material.set_shader_parameter("echo_color", Color(1.0, 1.0, 1.0))
	_landmark_material = _world_material.duplicate() as ShaderMaterial
	_set_params(_landmark_material, LANDMARK_PARAMS)


func _set_params(mat: ShaderMaterial, params: Dictionary) -> void:
	for key in params:
		mat.set_shader_parameter(key, params[key])


func _apply(on: bool) -> void:
	if not has_node("Geometry"):
		return
	for node in $Geometry.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		if on:
			gi.material_override = _material_for(gi)
		else:
			gi.material_override = _color_material(gi)


func _material_for(node: Node) -> Material:
	if node.has_meta("reveal_params"):
		return _variant(node.get_meta("reveal_params"))
	if _tagged(node, "chalk"):
		return _chalk_material
	if _tagged(node, "landmark"):
		return _landmark_material
	var cave := get_node_or_null("Geometry/Cave")
	if cave != null and (node == cave or cave.is_ancestor_of(node)):
		return _world_material
	if node.has_meta("surf"):
		return _surf_material(str(node.get_meta("surf")))
	var bm := _source_material(node) as BaseMaterial3D
	if bm != null:
		return _from_standard(bm)
	return _world_material


## The material a node was authored with (CSG primitive or mesh surface).
func _source_material(node: Node) -> Material:
	if node is CSGPrimitive3D:
		return (node as CSGPrimitive3D).material
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.get_surface_override_material_count() > 0:
			var over := mi.get_surface_override_material(0)
			if over != null:
				return over
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			return mi.mesh.surface_get_material(0)
	return null


## Reveal variant for an authored StandardMaterial3D: its albedo texture, a
## wood texture for wood-colored ones, or just its flat color.
func _from_standard(bm: BaseMaterial3D) -> ShaderMaterial:
	var tex := bm.albedo_texture
	var color := bm.albedo_color
	var key := "std:%d:%s" % [tex.get_instance_id() if tex != null else 0, str(color)]
	if _variants.has(key):
		return _variants[key] as ShaderMaterial
	var mat: ShaderMaterial
	if tex != null:
		mat = _world_material.duplicate() as ShaderMaterial
		mat.set_shader_parameter("use_triplanar", 0.0)
		mat.set_shader_parameter("use_flat", 0.0)
		mat.set_shader_parameter("use_albedo_tex", 1.0)
		mat.set_shader_parameter("albedo_tex", tex)
		mat.set_shader_parameter("albedo_color", Color(color.r, color.g, color.b))
	elif absf(color.r - WOOD_COLOR.r) + absf(color.g - WOOD_COLOR.g) + absf(color.b - WOOD_COLOR.b) < 0.2:
		mat = _surf_material("wood")
	else:
		mat = _world_material.duplicate() as ShaderMaterial
		_set_flat(mat, color)
	_variants[key] = mat
	return mat


## Look for primitive props with a "surf" metadata string.
func _surf_material(kind: String) -> ShaderMaterial:
	var key := "surf:" + kind
	if _variants.has(key):
		return _variants[key] as ShaderMaterial
	var mat := _world_material.duplicate() as ShaderMaterial
	if kind == "wood":
		_set_triplanar(mat, WOOD_TEX, WOOD_TEX, 0.6)
	elif kind == "rock":
		_set_triplanar(mat, PROP_ROCK_TEX, PROP_ROCK_TEX)
	else:
		_set_flat(mat, SURF_COLORS.get(kind, Color(0.5, 0.5, 0.5)))
	_variants[key] = mat
	return mat


## Lit, textured material for the color ending (null = keep the authored one).
func _color_material(node: Node) -> Material:
	if _tagged(node, "chalk"):
		return null
	var cave := get_node_or_null("Geometry/Cave")
	if cave != null and (node == cave or cave.is_ancestor_of(node)):
		return _std_material("cave")
	if node.has_meta("surf"):
		return _std_material(str(node.get_meta("surf")))
	if _source_material(node) == null:
		return _std_material("rock")
	return null


func _std_material(kind: String) -> StandardMaterial3D:
	if _std_cache.has(kind):
		return _std_cache[kind] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.9
	var tex_name := ""
	if kind == "cave":
		tex_name = str(WALL_TEX.get(scene_file_path.get_file().get_basename(), DEFAULT_WALL_TEX))
	elif kind == "rock":
		tex_name = PROP_ROCK_TEX
	elif kind == "wood":
		tex_name = WOOD_TEX
	else:
		mat.albedo_color = SURF_COLORS.get(kind, Color(0.5, 0.5, 0.5))
	if tex_name != "":
		_apply_pbr(mat, tex_name, kind)
		var k := 0.6 if kind == "wood" else TEX_SCALE
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_triplanar_sharpness = 4.0
		mat.uv1_scale = Vector3(k, k, k)
	if kind == "cave":
		# StandardMaterial3D has one texture set: the cave's walls/ceiling get
		# the wall set; floors get a second, wetter pass via next_pass.
		mat.next_pass = _floor_overlay()
	_std_cache[kind] = mat
	return mat


## Albedo, normal, roughness and AO from a texture set, darkened for the ending.
func _apply_pbr(mat: StandardMaterial3D, tex_name: String, kind: String) -> void:
	mat.albedo_texture = _tex(tex_name, "diff")
	mat.albedo_color = ENDING_TINT.get(kind, Color(0.6, 0.6, 0.6))
	var nor := _tex(tex_name, "nor")
	if nor != null:
		mat.normal_enabled = true
		mat.normal_texture = nor
		mat.normal_scale = 1.4
	var rough := _tex(tex_name, "rough")
	if rough != null:
		mat.roughness_texture = rough
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.roughness = float(ENDING_ROUGH.get(kind, 0.9))
	var ao := _tex(tex_name, "ao")
	if ao != null:
		mat.ao_enabled = true
		mat.ao_texture = ao
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.ao_light_affect = 0.6


## Wet mud drawn over upward-facing cave surfaces in the color ending.
func _floor_overlay() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = FLOOR_OVERLAY_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.render_priority = 1
	mat.set_shader_parameter("tex_albedo", _tex(FLOOR_TEX, "diff"))
	mat.set_shader_parameter("tex_normal", _tex(FLOOR_TEX, "nor"))
	mat.set_shader_parameter("tex_rough", _tex(FLOOR_TEX, "rough"))
	mat.set_shader_parameter("tex_ao", _tex(FLOOR_TEX, "ao"))
	mat.set_shader_parameter("tint", ENDING_TINT["floor"])
	mat.set_shader_parameter("rough_mul", ENDING_ROUGH["floor"])
	mat.set_shader_parameter("tex_scale", TEX_SCALE)
	return mat


## The node or one of its parents (below this level) is in the group.
func _tagged(node: Node, group: String) -> bool:
	var n := node
	while n != null and n != self:
		if n.is_in_group(group):
			return true
		n = n.get_parent()
	return false


## A world-material copy with extra parameters, shared by identical requests.
func _variant(params: Dictionary) -> ShaderMaterial:
	var key := str(params)
	if _variants.has(key):
		return _variants[key] as ShaderMaterial
	var mat := _world_material.duplicate() as ShaderMaterial
	if params.has("ripple"):
		# Water: no rock texture.
		_set_flat(mat, Color(0.3, 0.36, 0.42))
	_set_params(mat, params)
	_variants[key] = mat
	return mat


## Arrows only show up in echoes (they use the reveal shader, drawn in white).
func _build_arrows() -> void:
	if not has_node("Geometry/Arrows"):
		return
	for marker in $Geometry/Arrows.get_children():
		if not (marker is Node3D):
			continue
		var arrow := Node3D.new()
		arrow.rotation.y = deg_to_rad(float(marker.get_meta("yaw", 0.0)))
		# Shaft from the tip back, then two head strokes.
		_stroke(arrow, Vector3(0.0, 0.0, 0.15), 0.0, 0.7)
		_stroke(arrow, Vector3(0.11, 0.0, -0.07), 40.0, 0.34)
		_stroke(arrow, Vector3(-0.11, 0.0, -0.07), -40.0, 0.34)
		marker.add_child(arrow)


func _stroke(parent: Node3D, pos: Vector3, yaw_deg: float, length: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.09, 0.02, length)
	var stroke := MeshInstance3D.new()
	stroke.mesh = mesh
	stroke.position = pos
	stroke.rotation.y = deg_to_rad(yaw_deg)
	stroke.add_to_group("chalk")
	parent.add_child(stroke)


# ---------------------------------------------------------------- Daylight

func _find_daylights() -> void:
	for node in get_tree().get_nodes_in_group("daylight"):
		var gi := node as GeometryInstance3D
		if gi == null or not is_ancestor_of(gi):
			continue
		var mat := gi.material_override as StandardMaterial3D
		if mat == null:
			continue
		mat = mat.duplicate() as StandardMaterial3D
		gi.material_override = mat
		_daylights.append(gi)
		_day_colors.append(mat.albedo_color)


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var won := Game.state == Game.State.WON
	for i in _daylights.size():
		var gi := _daylights[i]
		var t := 1.0
		if not won:
			var d := gi.global_position.distance_to(player.global_position)
			t = clampf((DAY_FAR - d) / (DAY_FAR - DAY_NEAR), 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
		var k := lerpf(DAY_MIN, 1.0, t)
		var c := _day_colors[i]
		var mat := gi.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(c.r * k, c.g * k, c.b * k, c.a)
	_update_motes(player, won)


# ---------------------------------------------------------------- Dust motes

## Dust hanging in the air around the player. Unshaded and invisible, except
## for a moment after each ping, when the ring catches it.
func _make_motes() -> void:
	_motes = CPUParticles3D.new()
	_motes.name = "DustMotes"
	_motes.amount = 90
	_motes.lifetime = 7.0
	_motes.preprocess = 7.0
	_motes.local_coords = false
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(5.0, 1.6, 5.0)
	_motes.direction = Vector3.UP
	_motes.spread = 180.0
	_motes.gravity = Vector3(0.0, -0.025, 0.0)
	_motes.initial_velocity_min = 0.02
	_motes.initial_velocity_max = 0.1
	_motes.scale_amount_min = 0.6
	_motes.scale_amount_max = 1.4
	var mesh := SphereMesh.new()
	mesh.radius = 0.012
	mesh.height = 0.024
	mesh.radial_segments = 4
	mesh.rings = 2
	_motes.mesh = mesh
	_mote_material = StandardMaterial3D.new()
	_mote_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mote_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mote_material.albedo_color = Color(0.8, 0.97, 1.0, 0.0)
	_motes.material_override = _mote_material
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.visible = false
	add_child(_motes)
	if has_node("PlayerSpawn"):
		_motes.global_position = ($PlayerSpawn as Node3D).global_position + Vector3.UP * 1.3


func _update_motes(player: Node3D, won: bool) -> void:
	if _motes == null:
		return
	_motes.global_position = player.global_position + Vector3.UP * 1.3
	var age := Echo.time_since_player_ping()
	var a := clampf(age * 8.0, 0.0, 1.0) * (1.0 - clampf((age - 0.3) / 1.8, 0.0, 1.0))
	# A whisper only stirs a few of them.
	a *= clampf(Echo.last_player_ping_radius() / 22.0, 0.35, 1.0)
	if won:
		a = 0.0
	_motes.visible = a > 0.01
	var c := _mote_material.albedo_color
	c.a = a * 0.7
	_mote_material.albedo_color = c
