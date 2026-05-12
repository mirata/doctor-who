@tool
extends EditorPlugin

const _SORTER_SCRIPT := preload("res://addons/iso_sorter/iso_sorter.gd")

var _sorter: Node = null

var _dragging: int = 0
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
	_dragging = 0
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
# In Godot 4 the CanvasItemEditor stores zoom/pan in vp_final (the viewport
# final transform), NOT in Viewport.canvas_transform (which is always identity).
# So: get_viewport_transform() = vp_final × global_transform
# And: get_viewport_transform() × global_transform⁻¹ = vp_final
#
# vp_final maps world → editor-window pixels, which is correct for zoom/pan
# tracking but includes the SubViewport panel's offset within the window.
# The overlay and input events use SubViewportContainer-local coords, so we
# subtract overlay.get_global_rect().position (cached each draw) to correct.

func _world_to_screen_xf() -> Transform2D:
	if not _sorter or not is_instance_valid(_sorter):
		return Transform2D.IDENTITY
	# Scene root is at the world origin (global_transform ≈ identity), so
	# get_viewport_transform() gives the pure world→SubViewport-local mapping.
	# SubViewport-local coords ARE the overlay's draw coordinate system, so
	# no further correction is needed.
	var root := get_editor_interface().get_edited_scene_root()
	if root is CanvasItem:
		return (root as CanvasItem).get_viewport_transform()
	return Transform2D.IDENTITY


# ── Viewport drawing ─────────────────────────────────────────────────────────

func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if not _sorter or not is_instance_valid(_sorter):
		return

	var xf := _world_to_screen_xf()
	var p1: Vector2 = _sorter.call("get_sort_point_1")
	var p1s := xf * p1

	if int(_sorter.get("sort_type")) == 1:  # LINE
		var p2: Vector2 = _sorter.call("get_sort_point_2")
		var p2s := xf * p2
		overlay.draw_line(p1s, p2s, COLOR_LINE, 2.0)
		_draw_handle(overlay, p2s, COLOR_P2)

	_draw_handle(overlay, p1s, COLOR_P1)


func _forward_canvas_force_draw_over_viewport(overlay: Control) -> void:
	_forward_canvas_draw_over_viewport(overlay)


static func _draw_handle(overlay: Control, pos: Vector2, color: Color) -> void:
	overlay.draw_circle(pos, HANDLE_R + 2.5, COLOR_OUTLINE)
	overlay.draw_circle(pos, HANDLE_R, color)


# ── Viewport input ───────────────────────────────────────────────────────────
# event.position is in screen space (same as the overlay).

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not _sorter or not is_instance_valid(_sorter):
		return false

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				return _try_begin_drag(mb.position)
			elif _dragging != 0:
				_commit_drag()
				return true

	if event is InputEventMouseMotion and _dragging != 0:
		var mm := event as InputEventMouseMotion
		var inv := _world_to_screen_xf().affine_inverse()
		# Both positions are screen-space; inverse maps to world-space delta.
		var delta: Vector2 = (inv * mm.position) - (inv * _drag_start_mouse)
		var prop := "sort_offset_1" if _dragging == 1 else "sort_offset_2"
		_sorter.set(prop, _drag_start_offset + delta)
		update_overlays()
		return true

	return false


func _try_begin_drag(screen_mouse: Vector2) -> bool:
	var xf := _world_to_screen_xf()

	var p1: Vector2 = _sorter.call("get_sort_point_1")
	if screen_mouse.distance_to(xf * p1) <= HANDLE_R + 6.0:
		_dragging = 1
		_drag_start_mouse = screen_mouse
		_drag_start_offset = _sorter.get("sort_offset_1")
		return true

	if int(_sorter.get("sort_type")) == 1:  # LINE
		var p2: Vector2 = _sorter.call("get_sort_point_2")
		if screen_mouse.distance_to(xf * p2) <= HANDLE_R + 6.0:
			_dragging = 2
			_drag_start_mouse = screen_mouse
			_drag_start_offset = _sorter.get("sort_offset_2")
			return true

	return false


func _commit_drag() -> void:
	var prop := "sort_offset_1" if _dragging == 1 else "sort_offset_2"
	var new_val: Vector2 = _sorter.get(prop)
	var old_val: Vector2 = _drag_start_offset
	_dragging = 0

	var ur := get_undo_redo()
	ur.create_action("Move IsoSorter Handle")
	ur.add_do_property(_sorter, prop, new_val)
	ur.add_undo_property(_sorter, prop, old_val)
	ur.commit_action(false)
	update_overlays()
