extends NavigationRegion2D

## Floor navigation for a room.
##
## The walkable boundary is the NavigationPolygon's outline — select this node in
## the editor and drag its points to change where characters may walk. Everything
## inside it is then carved out by the room's static collision shapes, so moving
## a wall collider updates pathfinding without re-authoring anything.
##
## Source geometry is parsed from the `navigation_source` group rather than this
## node's children, because the colliders are siblings, not children. Getting
## that wrong makes the editor's "Bake NavigationPolygon" button quietly produce
## an unobstructed mesh.

## Re-bake from live collision geometry on load, so collider edits are picked up
## without remembering to bake in the editor.
@export var rebake_on_load: bool = true

## Node whose collider descendants count as obstacles. Empty means the parent,
## i.e. the whole room.
@export var source_geometry_root: NodePath

func _ready() -> void:
	if not rebake_on_load or navigation_polygon == null:
		return

	var source: Node = get_parent()
	if not source_geometry_root.is_empty():
		source = get_node_or_null(source_geometry_root)
	if source == null:
		push_warning("nav_region: source_geometry_root not found, keeping pre-baked mesh")
		return

	navigation_polygon = _bake_against(navigation_polygon, source)

## Returns a fresh NavigationPolygon with the template's settings and outline,
## re-baked against the colliders under source. The template resource is left
## untouched so the saved .tres stays as authored.
func _bake_against(template: NavigationPolygon, source: Node) -> NavigationPolygon:
	var baked := NavigationPolygon.new()
	baked.agent_radius = template.agent_radius
	baked.cell_size = template.cell_size
	baked.parsed_geometry_type = template.parsed_geometry_type
	baked.source_geometry_mode = template.source_geometry_mode
	baked.source_geometry_group_name = template.source_geometry_group_name
	baked.parsed_collision_mask = template.parsed_collision_mask
	for i in template.get_outline_count():
		baked.add_outline(template.get_outline(i))

	var geometry := NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.parse_source_geometry_data(baked, geometry, source)
	NavigationServer2D.bake_from_source_geometry_data(baked, geometry)
	return baked
