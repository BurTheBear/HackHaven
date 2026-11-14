extends RefCounted
## Builds a dagger out of primitives: a long tapered blade, a crossguard, a
## wrapped handle and a pommel. Readable by silhouette at a glance.
## The blade points along -Z (forward) and the handle sits at the origin.

const STEEL := Color(0.78, 0.86, 0.95)
const GRIP := Color(0.42, 0.3, 0.18)


## Makes a flat (unshaded) material. `energy` makes the color brighter or darker.
static func make_material(color: Color, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var red := color.r * energy
	var green := color.g * energy
	var blue := color.b * energy
	m.albedo_color = Color(red, green, blue, 1.0)
	return m


## `blade_mat` colors the blade and guard, `grip_mat` the handle and pommel.
static func build(blade_mat: Material, grip_mat: Material = null) -> Node3D:
	if grip_mat == null:
		grip_mat = blade_mat
	var root := Node3D.new()
	root.name = "Dagger"
	# Blade: a flat box plus a pointed prism tip.
	var blade := BoxMesh.new()
	blade.size = Vector3(0.05, 0.012, 0.2)
	_part(root, blade, Vector3(0.0, 0.0, -0.16), Vector3.ZERO, blade_mat)
	var tip := PrismMesh.new()
	tip.size = Vector3(0.05, 0.08, 0.012)
	_part(root, tip, Vector3(0.0, 0.0, -0.3), Vector3(-90.0, 0.0, 0.0), blade_mat)
	# Crossguard.
	var guard := BoxMesh.new()
	guard.size = Vector3(0.14, 0.025, 0.025)
	_part(root, guard, Vector3(0.0, 0.0, -0.05), Vector3.ZERO, blade_mat)
	# Handle.
	var handle := CylinderMesh.new()
	handle.top_radius = 0.016
	handle.bottom_radius = 0.018
	handle.height = 0.1
	handle.radial_segments = 8
	handle.rings = 1
	_part(root, handle, Vector3(0.0, 0.0, 0.01), Vector3(90.0, 0.0, 0.0), grip_mat)
	# Pommel.
	var pommel := SphereMesh.new()
	pommel.radius = 0.024
	pommel.height = 0.048
	pommel.radial_segments = 8
	pommel.rings = 4
	_part(root, pommel, Vector3(0.0, 0.0, 0.07), Vector3.ZERO, blade_mat)
	return root


## Adds one piece of the dagger (a mesh) to `root` at a position and rotation.
static func _part(root: Node3D, mesh: Mesh, pos: Vector3, rot_deg: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi
