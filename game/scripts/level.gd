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

@export var reveal_material: Material

var _world_material: ShaderMaterial
var _chalk_material: ShaderMaterial
var _landmark_material: ShaderMaterial
var _variants := {}
var _daylights: Array[GeometryInstance3D] = []
var _day_colors: Array[Color] = []
var _motes: CPUParticles3D
var _mote_material: StandardMaterial3D


func _ready() -> void:
	_make_materials()
	_build_arrows()
	_apply(true)
	_find_daylights()
	_make_motes()


func reveal_colors() -> void:
	_apply(false)
	if _motes:
		_motes.visible = false


func _make_materials() -> void:
	var base := reveal_material as ShaderMaterial
	if base == null:
		base = ShaderMaterial.new()
		base.shader = preload("res://shaders/reveal.gdshader")
	_world_material = base.duplicate() as ShaderMaterial
	_set_params(_world_material, WORLD_PARAMS)
	_chalk_material = _world_material.duplicate() as ShaderMaterial
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
			gi.material_override = null


func _material_for(node: Node) -> Material:
	if node.has_meta("reveal_params"):
		return _variant(node.get_meta("reveal_params"))
	if _tagged(node, "chalk"):
		return _chalk_material
	if _tagged(node, "landmark"):
		return _landmark_material
	return _world_material


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
