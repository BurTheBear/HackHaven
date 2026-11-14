extends Node3D
## Puts the reveal shader on every mesh/CSG under Geometry, builds the chalk
## arrows, and takes the shader off again for the full-color ending.
## Chalk arrows: add a Marker3D under Geometry/Arrows, lying on the floor.
## Its "yaw" metadata (degrees) sets the direction: 0 = north (-Z),
## -90 = east (+X), 90 = west (-X), 180 = south (+Z).

@export var reveal_material: Material

var _chalk_material: Material


func _ready() -> void:
	var chalk: ShaderMaterial = null
	if reveal_material:
		chalk = reveal_material.duplicate() as ShaderMaterial
	if chalk:
		chalk.set_shader_parameter("echo_color", Color(1.0, 1.0, 1.0))
	_chalk_material = chalk
	_build_arrows()
	_apply(reveal_material)


func reveal_colors() -> void:
	_apply(null)


func _apply(material: Material) -> void:
	for node in $Geometry.find_children("*", "GeometryInstance3D", true, false):
		var chalk: bool = material != null and node.is_in_group("chalk")
		(node as GeometryInstance3D).material_override = _chalk_material if chalk else material


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
