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

## World-space offset from parent's position for the primary sort point (green handle).
@export var sort_offset_1: Vector2 = Vector2.ZERO

## World-space offset for the secondary sort point (red handle). Only used in LINE mode.
@export var sort_offset_2: Vector2 = Vector2(50, 0)

@export_group("Behavior")
## Set true for sprites that move at runtime (player, enemies). Static sprites are cheaper.
@export var is_movable: bool = false
## Always render behind everything else (use for floor tiles).
@export var render_below_all: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
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


func get_sort_point_1() -> Vector2:
	return _parent_global_pos() + sort_offset_1


func get_sort_point_2() -> Vector2:
	return _parent_global_pos() + sort_offset_2


func get_bounds() -> Rect2:
	var p = get_parent()
	if p is Sprite2D:
		var s := p as Sprite2D
		if s.texture:
			var sz: Vector2 = s.texture.get_size() * s.scale
			return Rect2(s.global_position - sz * 0.5 + s.offset * s.scale, sz)
	# Fallback: small box around sort point 1
	var pt := get_sort_point_1()
	return Rect2(pt - Vector2(24, 24), Vector2(48, 48))


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
	return []
