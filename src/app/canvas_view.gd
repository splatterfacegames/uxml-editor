class_name EdCanvasView
extends Control
## The canvas: the live godot-uxml render of the active document, drawn from
## a SubViewport at a pan offset and zoom, with the selection overlay.
##
## Input: left click selects the element under the pointer (hit-test). The
## mouse wheel zooms around the pointer. Middle drag, or Space or Alt with a
## left drag, pans. F fits the screen into the view.
## Native Godot control: a SubViewport keeps the edited document apart from
## the editor's own godot-uxml documents (input, focus, theme).

signal picked(id: int)
signal view_changed

const ZOOM_MIN := 0.1
const ZOOM_MAX := 8.0
const ACCENT := Color(0.29, 0.6, 1.0)
const HOVER := Color(0.29, 0.6, 1.0, 0.55)

var host: EdRenderHost
var zoom: float = 1.0
var pan: Vector2 = Vector2(24, 24)
var selected_id: int = -1
var hover_id: int = -1
var _dragging := false
var _space := false
var _fit_pending := true
var _label_font: Font


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


func view_to_screen(p: Vector2) -> Vector2:
	return (p - pan) / zoom


func screen_rect_to_view(r: Rect2) -> Rect2:
	return Rect2(pan + r.position * zoom, r.size * zoom)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.13, 0.14))
	var frame := Rect2(pan, screen_size() * zoom)
	draw_rect(frame.grow(6), Color(0, 0, 0, 0.25))
	draw_rect(frame.grow(1), Color(0.05, 0.05, 0.05))
	draw_texture_rect(host.get_texture(), frame, false)
	if hover_id >= 0 and hover_id != selected_id:
		var hr := host.rect_of(hover_id)
		if hr.has_area():
			draw_rect(screen_rect_to_view(hr), HOVER, false, 1.0)
	if selected_id >= 0:
		var r := host.rect_of(selected_id)
		if r.has_area() or r.size != Vector2.ZERO:
			var v := screen_rect_to_view(r)
			draw_rect(v, Color(ACCENT, 0.08), true)
			draw_rect(v, ACCENT, false, 2.0)
			for corner in [v.position, Vector2(v.end.x, v.position.y), v.end, Vector2(v.position.x, v.end.y)]:
				draw_rect(Rect2(corner - Vector2(3, 3), Vector2(6, 6)), Color.WHITE)
				draw_rect(Rect2(corner - Vector2(3, 3), Vector2(6, 6)), ACCENT, false, 1.0)
			_draw_chip(v)


func _draw_chip(v: Rect2) -> void:
	var el = host.element_for_node.get(selected_id)
	if el == null:
		return
	var r := host.rect_of(selected_id)
	var label := "%s  %d × %d" % [el.local, int(round(r.size.x)), int(round(r.size.y))]
	var fs := 12
	var w := _label_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10
	var pos := Vector2(v.position.x, v.position.y - 18)
	if pos.y < 2:
		pos.y = v.end.y + 2
	draw_rect(Rect2(pos, Vector2(w, 16)), ACCENT)
	draw_string(_label_font, pos + Vector2(5, 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			set_zoom(zoom * 1.1, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			set_zoom(zoom / 1.1, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_LEFT and (_space or mb.alt_pressed)):
			_dragging = mb.pressed
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			grab_focus()
			var sp := view_to_screen(mb.position)
			var id := host.hit_test(sp) if Rect2(Vector2.ZERO, screen_size()).has_point(sp) else -1
			picked.emit(id)
			accept_event()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _dragging:
			pan += mm.relative
			_fit_pending = false
			view_changed.emit()
		else:
			var sp := view_to_screen(mm.position)
			hover_id = host.hit_test(sp) if Rect2(Vector2.ZERO, screen_size()).has_point(sp) else -1
	elif ev is InputEventKey:
		var k := ev as InputEventKey
		if k.keycode == KEY_SPACE:
			_space = k.pressed
			accept_event()
		elif k.pressed and k.keycode == KEY_F and not k.ctrl_pressed:
			fit()
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover_id = -1
	elif what == NOTIFICATION_FOCUS_EXIT:
		_space = false
		_dragging = false
