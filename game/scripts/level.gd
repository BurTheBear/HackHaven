extends Node3D
## Puts the reveal shader on every mesh/CSG under Geometry,
## and takes it off again for the full-color ending.

@export var reveal_material: Material


func _ready() -> void:
	_apply(reveal_material)


func reveal_colors() -> void:
	_apply(null)


func _apply(material: Material) -> void:
	for node in $Geometry.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).material_override = material
