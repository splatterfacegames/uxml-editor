class_name EdSourceView
extends CodeEdit
## The source view: the exact text of one buffer, kept in sync with every
## other view through the one history.
##
## Native Godot control: CodeEdit gives text editing, IME, search and
## gutters that a godot-uxml TextField does not.
## The CodeEdit holds a "\n" copy of the buffer (EdNewlineMap). A pause in
## typing turns the change into one buffer patch, made into a transaction
## that coalesces with the previous keystrokes. Ctrl+Z and Ctrl+Y go to the
## editor history, not to the CodeEdit undo stack.

signal edited(tx: EdTransaction)
## The caret moved by the user to buffer offset `offset`.
signal caret_moved_to(offset: int)
signal undo_requested
signal redo_requested

const COMMIT_DELAY := 0.35

var path: String = ""
var _map: EdNewlineMap = null
var _ws: EdWorkspace = null
var _timer: Timer
var _applying := false
var _highlighter := EdSourceHighlighter.new()
var _mark: Vector2i = Vector2i(-1, -1)
## Typed text that is not a transaction yet.
var _dirty := false


func _init() -> void:
	syntax_highlighter = _highlighter
	gutters_draw_line_numbers = true
	gutters_zero_pad_line_numbers = false
	highlight_current_line = true
	draw_tabs = true
	indent_automatic = true
	scroll_smooth = false
	minimap_draw = false
	caret_blink = true
	wrap_mode = TextEdit.LINE_WRAPPING_NONE
	add_theme_font_size_override("font_size", 13)
	add_theme_color_override("background_color", Color(0.12, 0.12, 0.13))
	add_theme_color_override("current_line_color", Color(1, 1, 1, 0.04))
	add_theme_color_override("line_number_color", Color(0.45, 0.45, 0.48))
	add_theme_color_override("font_color", EdSourceHighlighter.C_TEXT)
	add_theme_color_override("selection_color", Color(0.25, 0.42, 0.65, 0.6))
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = COMMIT_DELAY
	_timer.timeout.connect(flush)
	add_child(_timer)
	text_changed.connect(_on_text_changed)
	caret_changed.connect(_on_caret_changed)


func set_workspace(ws: EdWorkspace) -> void:
	_ws = ws


## Show buffer `p` (or nothing when p is empty).
func show_file(p: String) -> void:
	flush()
	path = p
	_highlighter.mode = "uss" if p.to_lower().ends_with(".uss") else "uxml"
	reload_from_buffer(true)


## Bring the view up to date with the buffer, keeping caret and scroll.
func reload_from_buffer(reset_view: bool = false) -> void:
	if _ws == null or path.is_empty() or not _ws.has(path):
		_applying = true
		text = ""
		_applying = false
		editable = false
		_map = null
		return
	var b := _ws.buffer(path)
	var m := EdNewlineMap.make(b.text, b.newline())
	editable = b.exact
	if _map != null and _map.display == m.display and not reset_view:
		_map = m
		return
	var line := get_caret_line()
	var col := get_caret_column()
	var vscroll := scroll_vertical
	_applying = true
	_dirty = false
	if reset_view or _map == null or not _replace_changed(_map.display, m.display):
		text = m.display
	clear_undo_history()
	_applying = false
	_map = m
	if reset_view:
		set_caret_line(0)
		set_caret_column(0)
		scroll_vertical = 0
	else:
		set_caret_line(mini(line, get_line_count() - 1))
		set_caret_column(col)
		scroll_vertical = vscroll
	if _mark.x >= 0:
		mark_range(_mark.x, _mark.y, false)


## Replace only the changed middle of the text (a whole-text set re-lays
## out and highlights every line). `old` must be the current text.
func _replace_changed(old: String, now: String) -> bool:
	if text != old:
		return false
	var n := mini(old.length(), now.length())
	# Common prefix and suffix lengths by bisection (native compares).
	var lo := 0
	var hi := n
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if old.substr(0, mid) == now.substr(0, mid):
			lo = mid
		else:
			hi = mid - 1
	var a := lo
	lo = 0
	hi = n - a
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if old.substr(old.length() - mid) == now.substr(now.length() - mid):
			lo = mid
		else:
			hi = mid - 1
	var b := lo
	var from := _line_col(a)
	var to := _line_col(old.length() - b)
	begin_complex_operation()
	if to != from:
		remove_text(from.x, from.y, to.x, to.y)
	var ins := now.substr(a, now.length() - b - a)
	if not ins.is_empty():
		insert_text(ins, from.x, from.y)
	end_complex_operation()
	return text == now


func has_pending_edit() -> bool:
	return _dirty


func _on_text_changed() -> void:
	# TextEdit emits text_changed at the end of the frame, also after a
	# programmatic change; the display copy tells the two apart.
	if _applying or (_map != null and text == _map.display):
		return
	_dirty = true
	_timer.start()


## Turn the typed change into a transaction now. (The pause timer calls
## this too; a one-shot timer is already stopped when it times out, so the
## pending state is a flag of its own.)
func flush() -> void:
	if not _dirty:
		return
	_dirty = false
	if _timer != null:
		_timer.stop()
	if _map == null or _ws == null:
		return
	var patch = _map.to_buffer_patch(text)
	if patch == null:
		return
	var tx := EdTransaction.make("source:edit", "Edit %s" % path.get_file(), path, [patch])
	tx.coalesce_key = "source:" + path
	_map = EdNewlineMap.make(EdSourcePatch.apply(_map.buffer_text, [patch]), _map.newline)
	edited.emit(tx)


func _on_caret_changed() -> void:
	if _applying or _map == null or not has_focus():
		return
	caret_moved_to.emit(_map.to_buffer(_offset_of(get_caret_line(), get_caret_column())))


func _offset_of(line: int, col: int) -> int:
	var off := 0
	for i in line:
		off += get_line(i).length() + 1
	return off + col


func _line_col(display_offset: int) -> Vector2i:
	var off := 0
	for i in get_line_count():
		var n := get_line(i).length()
		if display_offset <= off + n:
			return Vector2i(i, display_offset - off)
		off += n + 1
	return Vector2i(get_line_count() - 1, get_line(get_line_count() - 1).length())


## Show buffer range [start, end) as the element selection: select it and
## scroll it into view (when `reveal`).
func mark_range(start: int, end: int, reveal: bool = true) -> void:
	_mark = Vector2i(start, end)
	if _map == null or start < 0:
		deselect()
		return
	var a := _line_col(_map.to_display(start))
	var b := _line_col(_map.to_display(end))
	_applying = true
	# The caret goes to the selection start (origin = end), so the view
	# scrolls to the start of the tag. Moving the caret after select()
	# would collapse the selection.
	select(b.x, b.y, a.x, a.y)
	_applying = false
	if reveal:
		set_line_as_center_visible(a.x)


func clear_mark() -> void:
	_mark = Vector2i(-1, -1)
	deselect()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed:
		var k := ev as InputEventKey
		if k.is_command_or_control_pressed() and k.keycode == KEY_Z:
			flush()
			if k.shift_pressed:
				redo_requested.emit()
			else:
				undo_requested.emit()
			accept_event()
		elif k.is_command_or_control_pressed() and k.keycode == KEY_Y:
			flush()
			redo_requested.emit()
			accept_event()
		elif k.is_command_or_control_pressed() and k.keycode == KEY_S:
			flush()
	if ev is InputEventMouseButton and ev.pressed:
		_mark = Vector2i(-1, -1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_EXIT:
		flush()
