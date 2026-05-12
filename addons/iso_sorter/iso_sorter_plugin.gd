@tool
extends EditorPlugin

const _SORTER_SCRIPT := preload("res://addons/iso_sorter/iso_sorter.gd")

var _sorter: Node = null

# -1 = not dragging; >= 0 = index into sort_offsets (LINE) or 0 for sort_offset_1 (POINT)
var _dragging: int = -1
var _drag_start_mouse: Vector2
var _drag_start_offset: Vector2

const HANDLE_R      := 8.0
const COLOR_P1      := Color(0.15, 0.95, 0.15, 1.0)
const COLOR_P2      := Color(0.95, 0.15, 0.15, 1.0)
const COLOR_OUTLINE := Color(0.0,  0.0,  0.0,  0.85)
const COLOR_LINE    := Color(1.0,  1.0,  0.0,  0.8)


func _enter_tree() -> void:
	get_editor_interface().get_selection().selection_changed.connect(_on_selection_changed)


func _exit_tree() -> void:
	var sel := get_editor_interface().get_selection()
	if sel.selection_changed.is_connected(_on_selection_changed):
		sel.selection_changed.disconnect(_on_selection_changed)


func _enable_plugin() -> void:
	add_autoload_singleton("IsoSortingManager", "res://addons/iso_sorter/iso_sorting_manager.gd")


func _disable_plugin() -> void:
	remove_autoload_singleton("IsoSortingManager")


func _process(_delta: float) -> void:
	if _sorter:
		update_overlays()


func _handles(obj: Object) -> bool:
	if not (obj is Node):
		return false
	var node := obj as Node
	if node.get_script() == _SORTER_SCRIPT:
		return true
	for child in node.get_children():
		if child.get_script() == _SORTER_SCRIPT:
			return true
	return false


func _on_selection_changed() -> void:
	_sorter = null
	_dragging = -1
	for node in get_editor_interface().get_selection().get_selected_nodes():
		var found := _find_sorter(node)
		if found:
			_sorter = found
			break
	update_overlays()


func _find_sorter(node: Node) -> Node:
	if node.get_script() == _SORTER_SCRIPT:
		return node
	for child in node.get_children():
		if child.get_script() == _SORTER_SCRIPT:
			return child
	return null


# ── World → screen transform ──────────────────────────────────────────────────
# Scene root is at the world origin (global_transform ≈ identity), so
# get_viewport_transform() gives the pure world→SubViewport-local mapping.
# SubViewport-local coords ARE the overlay's draw coordinate system.

func _world_to_screen_xf() -> Transform2D:
	if not _sorter or not is_instance_valid(_sorter):
		return Transform2D.IDENTITY
	var root := get_editor_interface().get_edited_scene_root()
	if root is CanvasItem:
		return (root as CanvasItem).get_viewport_transform()
	return Transform2D.IDENTITY


# ── Viewport drawing ──────────────────────────────────────────────────────────

func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if not _sorter or not is_instance_valid(_sorter):
		return

	var xf := _world_to_screen_xf()

	if int(_sorter.get("sort_type")) == 1:  # LINE
		var pts: Array = _sorter.call("get_sort_points")
		var spts: Array[Vector2] = []
		for pt in pts:
			spts.append(xf * (pt as Vector2))
		for i in range(spts.size() - 1):
			overlay.draw_line(spts[i], spts[i + 1], COLOR_LINE, 2.0)
		for i in range(spts.size()):
			_draw_handle(overlay, spts[i], COLOR_P1 if i == 0 else COLOR_P2)
	else:  # POINT
		var p1: Vector2 = _sorter.call("get_sort_point_1")
		_draw_handle(overlay, xf * p1, COLOR_P1)


func _forward_canvas_force_draw_over_viewport(overlay: Control) -> void:
	_forward_canvas_draw_over_viewport(overlay)


static func _draw_handle(overlay: Control, pos: Vector2, color: Color) -> void:
	overlay.draw_circle(pos, HANDLE_R + 2.5, COLOR_OUTLINE)
	overlay.draw_circle(pos, HANDLE_R, color)


# ── Viewport input ────────────────────────────────────────────────────────────
# event.position is in SubViewport-local space (same as the overlay).

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not _sorter or not is_instance_valid(_sorter):
		return false

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				return _try_begin_drag(mb.position)
			elif _dragging != -1:
				_commit_drag()
				return true

	if event is InputEventMouseMotion and _dragging != -1:
		var mm := event as InputEventMouseMotion
		var inv := _world_to_screen_xf().affine_inverse()
		var delta: Vector2 = (inv * mm.position) - (inv * _drag_start_mouse)

		if int(_sorter.get("sort_type")) == 1:  # LINE
			var offsets: Array = (_sorter.get("sort_offsets") as Array).duplicate()
			offsets[_dragging] = _drag_start_offset + delta
			_sorter.set("sort_offsets", offsets)
		else:  # POINT
			_sorter.set("sort_offset_1", _drag_start_offset + delta)

		update_overlays()
		return true

	return false


func _try_begin_drag(screen_mouse: Vector2) -> bool:
	var xf := _world_to_screen_xf()

	if int(_sorter.get("sort_type")) == 1:  # LINE
		var pts: Array = _sorter.call("get_sort_points")
		var offsets: Array = _sorter.get("sort_offsets")
		for i in range(pts.size()):
			var ps := xf * (pts[i] as Vector2)
			if screen_mouse.distance_to(ps) <= HANDLE_R + 6.0:
				_dragging = i
				_drag_start_mouse = screen_mouse
				_drag_start_offset = offsets[i]
				return true
	else:  # POINT
		var p1: Vector2 = _sorter.call("get_sort_point_1")
		if screen_mouse.distance_to(xf * p1) <= HANDLE_R + 6.0:
			_dragging = 0
			_drag_start_mouse = screen_mouse
			_drag_start_offset = _sorter.get("sort_offset_1")
			return true

	return false


func _commit_drag() -> void:
	var ur := get_undo_redo()
	ur.create_action("Move IsoSorter Handle")

	if int(_sorter.get("sort_type")) == 1:  # LINE
		var new_offsets: Array = _sorter.get("sort_offsets")
		var old_offsets: Array = new_offsets.duplicate()
		old_offsets[_dragging] = _drag_start_offset
		ur.add_do_property(_sorter, "sort_offsets", new_offsets)
		ur.add_undo_property(_sorter, "sort_offsets", old_offsets)
	else:  # POINT
		var new_val: Vector2 = _sorter.get("sort_offset_1")
		ur.add_do_property(_sorter, "sort_offset_1", new_val)
		ur.add_undo_property(_sorter, "sort_offset_1", _drag_start_offset)

	_dragging = -1
	ur.commit_action(false)
	update_overlays()
