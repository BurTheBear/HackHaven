extends Node
## Bakes a navigation mesh at runtime from the level's CSG cave (the "Cave"
## CSGCombiner3D under Geometry), so Listeners can walk around rock with a
## NavigationAgent3D. Created by the director. The bake is synchronous (the
## web build is single-threaded) and runs once, a moment after the level
## loads (on the title screen). If anything is missing or fails, `nav_ready`
## stays false and Listeners fall back to straight-line movement.

const AGENT_RADIUS := 0.5
const AGENT_HEIGHT := 2.0
## Give up waiting for the CSG to build its mesh after this many frames.
const WAIT_FRAMES := 240

var nav_ready := false

var _region: NavigationRegion3D


func _ready() -> void:
	add_to_group("ai_nav")
	# Bake a moment later, once the rest of the level is in the tree.
	call_deferred("_bake")


## A walkable path from `from` to `to` (empty until the navmesh is ready).
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not nav_ready:
		return PackedVector3Array()
	if _region == null or not is_instance_valid(_region):
		return PackedVector3Array()
	var map: RID = _region.get_navigation_map()
	return NavigationServer3D.map_get_path(map, from, to, true)


## Finds the cave, waits for its mesh, bakes the navmesh and adds it to the level.
func _bake() -> void:
	var cave := _find_cave()
	if cave == null:
		push_warning("AiNav: no 'Cave' CSGCombiner3D found; Listeners move in straight lines.")
		return

	# CSG builds its mesh a frame or two after entering the tree, so wait for it.
	var frames := 0
	while cave.get_meshes().is_empty() and frames < WAIT_FRAMES:
		await get_tree().process_frame
		frames += 1
		if not is_instance_valid(cave):
			return
	if cave.get_meshes().is_empty():
		push_warning("AiNav: the cave CSG has no mesh; Listeners move in straight lines.")
		return

	var mesh := _bake_mesh(cave)
	if mesh == null:
		return

	# Put the baked mesh into the level as a navigation region.
	var map: RID = cave.get_world_3d().navigation_map
	var before := NavigationServer3D.map_get_iteration_id(map)
	_region = NavigationRegion3D.new()
	_region.name = "AiNavRegion"
	_region.navigation_mesh = mesh
	cave.get_parent().add_child(_region)
	_region.transform = cave.transform

	# Wait until the navigation map has synced with the new region.
	for i in 180:
		await get_tree().physics_frame
		if not is_instance_valid(_region):
			return
		var now := NavigationServer3D.map_get_iteration_id(map)
		if now != before:
			break
	await get_tree().physics_frame
	nav_ready = is_instance_valid(_region)


## Builds the navigation mesh from the cave's shape. Returns null on failure.
func _bake_mesh(cave: CSGShape3D) -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.agent_radius = AGENT_RADIUS
	mesh.agent_height = AGENT_HEIGHT
	mesh.agent_max_climb = 0.5
	mesh.agent_max_slope = 46.0
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25

	# Use the cave's collision faces (CPU data) instead of parsing its visual mesh:
	# reading render meshes back from the GPU is slow and stalls the web build.
	# Faces are in the cave's local space, so the region copies its transform.
	var source := NavigationMeshSourceGeometryData3D.new()
	var shape := cave.bake_collision_shape()
	if shape:
		source.add_faces(shape.get_faces(), Transform3D.IDENTITY)
	if not source.has_data():
		push_warning("AiNav: no source geometry parsed; Listeners move in straight lines.")
		return null

	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	if mesh.get_polygon_count() == 0:
		push_warning("AiNav: navmesh bake produced no polygons; Listeners move in straight lines.")
		return null
	return mesh


## Finds the level's root "Cave" CSG shape (or null if there isn't one).
func _find_cave() -> CSGShape3D:
	var root := get_tree().current_scene
	if root == null:
		return null
	var found: Array[Node] = root.find_children("Cave", "CSGShape3D", true, false)
	for node in found:
		var shape := node as CSGShape3D
		if shape != null and shape.is_root_shape():
			return shape
	return null
