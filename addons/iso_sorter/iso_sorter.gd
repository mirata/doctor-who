@tool
class_name IsoSorter
extends Node

enum SortType { POINT, LINE }

@export_group("Sort Points")
@export var sort_type: SortType = SortType.POINT:
	set(v):
		sort_type = v
		update_configuration_warnings()
		notify_property_list_changed()

## World-space offset from parent's position for the sort point (POINT mode).
@export var sort_offset_1: Vector2 = Vector2.ZERO

## World-space offsets forming the sort polyline (LINE mode, minimum 2 points).
@export var sort_offsets: Array[Vector2] = [Vector2.ZERO, Vector2(50, 0)]

@export_group("Behavior")
## Turn off in scenes that sort by Y instead — a regular tile grid does not need
## topological sorting, and this writing z_index every frame would override it.
## Honoured whenever it is set, not just at _ready, so a level can stand its
## characters' sorters down after they have already registered.
@export var enabled: bool = true:
	set(value):
		enabled = value
		if Engine.is_editor_hint() or not is_inside_tree():
			return
		var mgr = _manager()
		if mgr == null:
			return
		if enabled:
			mgr.register_sorter(self)
		else:
			mgr.unregister_sorter(self)
			# Hand the parent back to whatever sorting the scene does use.
			var p = get_parent()
			if p is CanvasItem:
				(p as CanvasItem).z_index = 0
				(p as CanvasItem).z_as_relative = true
## Set true for sprites that move at runtime (player, enemies). Static sprites are cheaper.
@export var is_movable: bool = false
## Always render behind everything else (use for floor tiles).
@export var render_below_all: bool = false


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "sort_offset_1" and sort_type == SortType.LINE:
		property["usage"] = PROPERTY_USAGE_NO_EDITOR
	if property["name"] == "sort_offsets" and sort_type == SortType.POINT:
		property["usage"] = PROPERTY_USAGE_NO_EDITOR


func _ready() -> void:
	if Engine.is_editor_hint() or not enabled:
		return
	var mgr = _manager()
	if mgr:
		mgr.register_sorter(self)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	var mgr = _manager()
	if mgr:
		mgr.unregister_sorter(self)


## POINT mode: the single sort point in world space.
func get_sort_point_1() -> Vector2:
	return _parent_global_pos() + sort_offset_1


## LINE mode: all polyline points in world space.
func get_sort_points() -> Array[Vector2]:
	var parent_pos := _parent_global_pos()
	var result: Array[Vector2] = []
	for offset: Vector2 in sort_offsets:
		result.append(parent_pos + offset)
	return result


func get_bounds() -> Rect2:
	var sprite := _sprite()
	if sprite != null and sprite.texture:
		# One frame, not the whole sheet: a spritesheet's texture is the full
		# strip, so using it directly gives a bounds hundreds of pixels wide.
		var frame_size: Vector2 = sprite.texture.get_size() / Vector2(
			maxi(sprite.hframes, 1), maxi(sprite.vframes, 1))
		var size: Vector2 = frame_size * sprite.scale
		var corner: Vector2 = sprite.global_position + sprite.offset * sprite.scale
		if sprite.centered:
			corner -= size * 0.5
		return Rect2(corner, size)
	if sort_type == SortType.LINE and not sort_offsets.is_empty():
		var parent_pos := _parent_global_pos()
		var r := Rect2(parent_pos + sort_offsets[0], Vector2.ZERO)
		for offset: Vector2 in sort_offsets:
			r = r.expand(parent_pos + offset)
		return r.grow(48)
	var pt := get_sort_point_1()
	return Rect2(pt - Vector2(24, 24), Vector2(48, 48))


## The sprite this sorter stands for. Usually the parent, but characters hang
## the sorter off a CharacterBody2D with the sprite alongside it — without
## looking there too, such a sorter falls back to a small fixed box and stops
## being compared against anything more than ~24 px away, leaving its draw order
## down to registration order.
func _sprite() -> Sprite2D:
	var p = get_parent()
	if p is Sprite2D:
		return p as Sprite2D
	if p != null:
		for child in p.get_children():
			if child is Sprite2D:
				return child as Sprite2D
	return null


func _parent_global_pos() -> Vector2:
	var p = get_parent()
	if p is Node2D:
		return (p as Node2D).global_position
	return Vector2.ZERO


func _manager() -> Node:
	return get_node_or_null("/root/IsoSortingManager")


func _get_configuration_warnings() -> PackedStringArray:
	if not (get_parent() is Node2D):
		return ["IsoSorter must be a child of a Node2D."]
	if sort_type == SortType.LINE and sort_offsets.size() < 2:
		return ["LINE mode requires at least 2 points in sort_offsets."]
	return []
