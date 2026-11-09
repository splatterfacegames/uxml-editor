class_name EdCanvasView
extends Control
## The canvas: the live godot-uxml render of the active document, drawn from
## a SubViewport at a pan offset and zoom, with the selection overlay, the
## move and resize handles, snap guides and drop hints.
##
## Edit mode input: a click selects the element under the pointer
## (hit-test); Shift+click adds or removes an element. A drag on the
## selected element moves it; a drag on a handle resizes it (the layout
## controller turns the gesture into style patches). Arrow keys nudge.
## The mouse wheel zooms around the pointer. Middle drag, or Space or Alt
## with a left drag, pans. F fits the screen into the view.
##
## Preview mode: input goes to the rendered document, so hovers, clicks,
## scrolling and text input work as at runtime. Ctrl+wheel zooms and the
## middle button pans.
##
## Units: the overlay, the hit test and the gesture signals use document
## pixels (the SubViewport). Under a scale preview (EdRenderHost
## panel_settings) a point of the layout is pixels_per_point() pixels; the
## size chip shows points, the units of the USS values. The layout
## controller turns pixels into points.
##
## Native Godot control: a SubViewport keeps the edited document apart from
## the editor's own godot-uxml documents (input, focus, theme).

signal picked(id: int, additive: bool)
signal view_changed
## A handle drag started: `handle` is "move" or a resize handle.
signal gesture_started(handle: String)
## Pointer travel since the start, in document pixels.
signal gesture_moved(handle: String, delta: Vector2, keep_ratio: bool, no_snap: bool)
signal gesture_finished(cancelled: bool)
signal nudged(delta: Vector2)

const ZOOM_MIN := 0.1
const ZOOM_MAX := 8.0
const ACCENT := Color(0.29, 0.6, 1.0)
const HOVER := Color(0.29, 0.6, 1.0, 0.55)
const GUIDE := Color(1.0, 0.27, 0.62)
const DROP := Color(1.0, 0.7, 0.2)
const HANDLE_SIZE := 7.0
const DRAG_START := 3.0
const HANDLES := ["nw", "n", "ne", "e", "se", "s", "sw", "w"]

var host: EdRenderHost
var zoom: float = 1.0
var pan: Vector2 = Vector2(24, 24)
## Selected editor node ids; the first one is the primary selection (the
## one with handles and the size chip).
var selected_ids: Array = []
var hover_id: int = -1
var preview: bool = false
## Snap guides in document pixels: {x: [..], y: [..]}.
var guides: Dictionary = {}
## Drop hint in document pixels: {rect: Rect2, line: [Vector2, Vector2]}.
var drop_hint: Dictionary = {}
var _dragging := false
var _space := false
var _fit_pending := true
var _label_font: Font
## Pending or active handle gesture: {handle, start, active, pick}.
var _press: Dictionary = {}
## Preview: true after a click in the canvas, until a click elsewhere.
## Keys then go to the document (EdMain routes them; a focused control
## inside the SubViewport takes the window focus from the canvas).
var keys_to_document := false

var selected_id: int:
	get:
		return -1 if selected_ids.is_empty() else selected_ids[0]
	set(v):
		selected_ids = [] if v < 0 else [v]


func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	host = EdRenderHost.new()
	add_child(host)
	_label_font = ThemeDB.fallback_font


func _ready() -> void:
	resized.connect(func():
		if _fit_pending:
			fit())
	set_process(true)


func _process(_dt: float) -> void:
	queue_redraw()


func screen_size() -> Vector2:
	return Vector2(host.size)


func set_screen_size(s: Vector2i) -> void:
	host.set_screen_size(s)
	fit()


func fit() -> void:
	var avail := size - Vector2(48, 48)
	if avail.x <= 0 or avail.y <= 0:
		_fit_pending = true
		return
	_fit_pending = false
	var s := screen_size()
	zoom = clampf(minf(avail.x / s.x, avail.y / s.y), ZOOM_MIN, ZOOM_MAX)
	pan = (size - s * zoom) * 0.5
	view_changed.emit()


func set_zoom(z: float, around: Vector2 = Vector2(-1, -1)) -> void:
	var anchor := size * 0.5 if around.x < 0 else around
	var nz := clampf(z, ZOOM_MIN, ZOOM_MAX)
	var doc_point := (anchor - pan) / zoom
	zoom = nz
	pan = anchor - doc_point * zoom
	_fit_pending = false
	view_changed.emit()


func set_preview(on: bool) -> void:
	if preview == on:
		return
	_cancel_press()
	preview = on
	keys_to_document = on
	hover_id = -1
	if not on:
		_forward_exit()
	mouse_default_cursor_shape = Control.CURSOR_ARROW


func view_to_screen(p: Vector2) -> Vector2:
	return (p - pan) / zoom


func screen_rect_to_view(r: Rect2) -> Rect2:
	return Rect2(pan + r.position * zoom, r.size * zoom)


## Document pixels -> global (window) coordinates.
func screen_to_global(p: Vector2) -> Vector2:
	return get_global_transform() * (pan + p * zoom)


## Global (window) coordinates -> document pixels.
func global_to_screen(p: Vector2) -> Vector2:
	return view_to_screen(get_global_transform().affine_inverse() * p)


## The element under a document point, or -1 outside the screen.
func hit(sp: Vector2) -> int:
	return host.hit_test(sp) if Rect2(Vector2.ZERO, screen_size()).has_point(sp) else -1


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.13, 0.14))
	var frame := Rect2(pan, screen_size() * zoom)
	draw_rect(frame.grow(6), Color(0, 0, 0, 0.25))
	if preview:
		draw_rect(frame.grow(2), Color(0.2, 0.75, 0.4), false, 2.0)
	else:
		draw_rect(frame.grow(1), Color(0.05, 0.05, 0.05))
	draw_texture_rect(host.get_texture(), frame, false)
	if preview:
		_draw_badge("Preview: input goes to the document")
		return
	if hover_id >= 0 and not selected_ids.has(hover_id):
		var hr := host.rect_of(hover_id)
		if hr.has_area():
			draw_rect(screen_rect_to_view(hr), HOVER, false, 1.0)
	for k in range(selected_ids.size() - 1, -1, -1):
		var id: int = selected_ids[k]
		var r := host.rect_of(id)
		if not r.has_area() and r.size == Vector2.ZERO:
			continue
		var v := screen_rect_to_view(r)
		draw_rect(v, Color(ACCENT, 0.08), true)
		draw_rect(v, ACCENT, false, 2.0 if k == 0 else 1.0)
		_draw_transformed(id)
		if k == 0:
			for h in HANDLES:
				var hr2 := _handle_rect(v, h)
				draw_rect(hr2, Color.WHITE)
				draw_rect(hr2, ACCENT, false, 1.0)
			_draw_chip(v, id)
	for gx in guides.get("x", []):
		var x: float = pan.x + float(gx) * zoom
		draw_line(Vector2(x, frame.position.y), Vector2(x, frame.end.y), GUIDE, 1.0)
	for gy in guides.get("y", []):
		var y: float = pan.y + float(gy) * zoom
		draw_line(Vector2(frame.position.x, y), Vector2(frame.end.x, y), GUIDE, 1.0)
	if not drop_hint.is_empty():
		var dr: Rect2 = drop_hint.get("rect", Rect2())
		if dr.size != Vector2.ZERO:
			draw_rect(screen_rect_to_view(dr), Color(DROP, 0.12), true)
			draw_rect(screen_rect_to_view(dr), DROP, false, 1.0)
		var line: Array = drop_hint.get("line", [])
		if line.size() == 2:
			draw_line(pan + line[0] * zoom, pan + line[1] * zoom, DROP, 3.0)


## The outline of a rotated, scaled or skewed element (its border box
## through its transform, request R14) over the bounding box.
func _draw_transformed(id: int) -> void:
	var b := host.local_box_of(id)
	if b.is_empty():
		return
	var t: Transform2D = b["transform"]
	# The transform includes the panel scale (points -> pixels); only a
	# transform of the element itself draws the outline.
	var ppp := host.pixels_per_point()
	if t.x.is_equal_approx(Vector2(ppp, 0)) and t.y.is_equal_approx(Vector2(0, ppp)):
		return
	var sz: Vector2 = b["size"]
	var pts := PackedVector2Array()
	for c in [Vector2.ZERO, Vector2(sz.x, 0), sz, Vector2(0, sz.y), Vector2.ZERO]:
		pts.append(pan + (t * c) * zoom)
	draw_polyline(pts, Color(ACCENT, 0.9), 1.5)


func _draw_badge(text: String) -> void:
	var fs := 12
	var w := _label_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12
	draw_rect(Rect2(Vector2(8, 8), Vector2(w, 18)), Color(0.2, 0.75, 0.4))
	draw_string(_label_font, Vector2(14, 21), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.BLACK)


func _draw_chip(v: Rect2, id: int) -> void:
	var el = host.element_for_node.get(id)
	if el == null:
		return
	var r := host.points_rect_of(id)
	var label := "%s  %s × %s" % [el.local, _num(r.size.x), _num(r.size.y)]
	if selected_ids.size() > 1:
		label += "  (+%d)" % (selected_ids.size() - 1)
	var fs := 12
	var w := _label_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10
	var pos := Vector2(v.position.x, v.position.y - 20)
	if pos.y < 2:
		pos.y = v.end.y + 6
	draw_rect(Rect2(pos, Vector2(w, 16)), ACCENT)
	draw_string(_label_font, pos + Vector2(5, 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


## A size in points: whole numbers as they are, others with two decimals
## (399.75 points at 1.333 pixels per point).
static func _num(v: float) -> String:
	var r := snappedf(v, 0.01)
	return str(int(r)) if is_equal_approx(r, roundf(r)) else String.num(r, 2)


static func _handle_point(v: Rect2, h: String) -> Vector2:
	var x := v.get_center().x
	var y := v.get_center().y
	if h.contains("w"):
		x = v.position.x
	elif h.contains("e"):
		x = v.end.x
	if h.contains("n"):
		y = v.position.y
	elif h.contains("s"):
		y = v.end.y
	return Vector2(x, y)


static func _handle_rect(v: Rect2, h: String) -> Rect2:
	var p := _handle_point(v, h)
	return Rect2(p - Vector2(HANDLE_SIZE, HANDLE_SIZE) * 0.5, Vector2(HANDLE_SIZE, HANDLE_SIZE))


## The handle of the primary selection at view point `p`: a resize handle,
## "move" inside the element, or "".
func handle_at(p: Vector2) -> String:
	if selected_ids.is_empty() or preview:
		return ""
	var r := host.rect_of(selected_ids[0])
	if r.size == Vector2.ZERO:
		return ""
	var v := screen_rect_to_view(r)
	# The nearest handle wins, so corners stay usable on small elements.
	var best := ""
	var best_d := INF
	for h in HANDLES:
		if _handle_rect(v, h).grow(3).has_point(p):
			var d := _handle_point(v, h).distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = h
	if not best.is_empty():
		return best
	return "move" if v.has_point(p) else ""


static func _cursor_for(h: String) -> int:
	match h:
		"n", "s":
			return Control.CURSOR_VSIZE
		"e", "w":
			return Control.CURSOR_HSIZE
		"nw", "se":
			return Control.CURSOR_FDIAGSIZE
		"ne", "sw":
			return Control.CURSOR_BDIAGSIZE
		"move":
			return Control.CURSOR_MOVE
	return Control.CURSOR_ARROW


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _gui_input(ev: InputEvent) -> void:
	if preview:
		_preview_input(ev)
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			set_zoom(zoom * 1.1, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			set_zoom(zoom / 1.1, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_LEFT and (_space or mb.alt_pressed) and _press.is_empty()):
			_dragging = mb.pressed
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			grab_focus()
			var h := handle_at(mb.position)
			if h != "" and not mb.shift_pressed:
				_press = {"handle": h, "start": mb.position, "active": false, "pick": h == "move"}
			else:
				picked.emit(hit(view_to_screen(mb.position)), mb.shift_pressed)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and not _press.is_empty():
			var p := _press
			_press = {}
			if p["active"]:
				gesture_finished.emit(false)
			elif p["pick"]:
				picked.emit(hit(view_to_screen(mb.position)), false)
			accept_event()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _dragging:
			pan += mm.relative
			_fit_pending = false
			view_changed.emit()
		elif not _press.is_empty():
			if not _press["active"] and mm.position.distance_to(_press["start"]) >= DRAG_START:
				_press["active"] = true
				gesture_started.emit(_press["handle"])
			if _press["active"]:
				gesture_moved.emit(_press["handle"], (mm.position - _press["start"]) / zoom, mm.shift_pressed, mm.alt_pressed or mm.is_command_or_control_pressed())
			accept_event()
		else:
			hover_id = hit(view_to_screen(mm.position))
			mouse_default_cursor_shape = _cursor_for(handle_at(mm.position))
	elif ev is InputEventKey:
		var k := ev as InputEventKey
		if k.keycode == KEY_SPACE:
			_space = k.pressed
			accept_event()
		elif k.pressed and k.keycode == KEY_ESCAPE and not _press.is_empty():
			_cancel_press()
			accept_event()
		elif k.pressed and k.keycode == KEY_F and not k.ctrl_pressed:
			fit()
			accept_event()
		elif k.pressed and not k.is_command_or_control_pressed() and not k.alt_pressed and [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN].has(k.keycode):
			var step := 10.0 if k.shift_pressed else 1.0
			var d := Vector2.ZERO
			match k.keycode:
				KEY_LEFT:
					d.x = -step
				KEY_RIGHT:
					d.x = step
				KEY_UP:
					d.y = -step
				KEY_DOWN:
					d.y = step
			nudged.emit(d)
			accept_event()


func _cancel_press() -> void:
	if not _press.is_empty() and _press["active"]:
		gesture_finished.emit(true)
	_press = {}


## Preview: pass the event to the rendered document in its own pixels.
func _preview_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.is_command_or_control_pressed() and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if mb.pressed:
				set_zoom(zoom * (1.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.1), mb.position)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			accept_event()
			return
		if mb.pressed:
			grab_focus()
			keys_to_document = true
	elif ev is InputEventMouseMotion and _dragging:
		pan += (ev as InputEventMouseMotion).relative
		_fit_pending = false
		view_changed.emit()
		accept_event()
		return
	elif ev is InputEventKey:
		if is_editor_key(ev):
			return
	forward_input(ev)
	accept_event()


## Editor shortcuts with Ctrl (save, undo, redo, preview, open) stay with
## the editor in preview.
static func is_editor_key(ev: InputEvent) -> bool:
	var k := ev as InputEventKey
	return k != null and k.is_command_or_control_pressed() and [KEY_S, KEY_Z, KEY_Y, KEY_P, KEY_O].has(k.keycode)


## Send an event to the rendered document (document pixels).
func forward_input(ev: InputEvent) -> void:
	var e := ev.duplicate() as InputEvent
	if e is InputEventMouse:
		var m := e as InputEventMouse
		m.position = view_to_screen(m.position)
		m.global_position = m.position
		if e is InputEventMouseMotion:
			var mm := e as InputEventMouseMotion
			mm.relative = mm.relative / zoom
	if host.is_inside_tree():
		host.push_input(e, true)


func _forward_exit() -> void:
	if not host.is_inside_tree():
		return
	var m := InputEventMouseMotion.new()
	m.position = Vector2(-10000, -10000)
	m.global_position = m.position
	host.push_input(m, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover_id = -1
		if preview:
			_forward_exit()
	elif what == NOTIFICATION_FOCUS_EXIT:
		_space = false
		_dragging = false
		_cancel_press()
