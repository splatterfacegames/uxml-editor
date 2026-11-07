extends SceneTree
## Frame cost benchmark of the editor window.
##
##   godot --headless --path . -s res://bench/frame_cost.gd [-- options]
##
## Options (after `--`):
##   --gdscript          disable the godot-uxml native core (GDScript path)
##   --fixture=<name>    menu (default), a fixture project, or large (a
##                       generated document of about 600 elements)
##   --frames=<n>        frames per scenario (default 60)
##
## Each scenario runs the real editor scene and measures the wall time of
## each frame (input, process, layout and draw; the headless renderer
## draws nothing). The table lists the median, the 95th
## percentile and the maximum in milliseconds.

const MENU := "Assets/UI/Menu.uxml"

var _frames := 60
var _dir := ""
var _m: EdMain
var _rows: Array = []
## Full renders, render patches and inspector builds before a scenario.
var _counts := [0, 0, 0]
var _render_ms: Array = []


## [full renders, render patches, inspector builds] so far (0 for a
## counter that the editor build does not have).
func _now_counts() -> Array:
	var h := _m.canvas.host
	return [int(h.get("renders") if h.get("renders") != null else 0), int(h.get("patches") if h.get("patches") != null else 0),
		int(_m.inspector.get("builds") if _m.inspector.get("builds") != null else 0)]


func _on_rendered() -> void:
	_render_ms.append(_m.canvas.host.last_render_ms)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fixture := "menu"
	for a in OS.get_cmdline_user_args():
		if a == "--gdscript":
			UxmlParser.use_native = false
			UssParser.use_native = false
			UssCascade.use_native = false
			UxmlDocument.use_native_layout = false
		elif a.begins_with("--fixture="):
			fixture = a.substr(10)
		elif a.begins_with("--frames="):
			_frames = int(a.substr(9))
	var native := ClassDB.class_exists("UxmlNativeParser") and UxmlParser.use_native
	# No frame cap: a frame takes as long as its work.
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	# A headless main loop waits up to this long per frame (the window
	# cannot draw); without the wait the wall time is the work time.
	OS.low_processor_usage_mode_sleep_usec = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_dir = ProjectSettings.globalize_path("user://bench-%d" % Time.get_ticks_usec())
	var entry := MENU
	if fixture == "large":
		entry = _make_large(_dir)
	else:
		_copy_tree(ProjectSettings.globalize_path("res://fixtures/projects/" + fixture), _dir)
	root.size = Vector2i(1600, 1000)
	var t0 := Time.get_ticks_usec()
	_m = load("res://src/app/main.tscn").instantiate()
	root.add_child(_m)
	await _wait(3)
	print("window: %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	t0 = Time.get_ticks_usec()
	_m.state.open_project(_dir)
	if _m.state.session == null or _m.state.session.entry_path != entry:
		_m.state.open_document(entry)
	await _wait(2)
	print("open: %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var count := _m.state.session.tree().nodes.size()
	print("godot-uxml core: %s, fixture %s (%d elements), %d frames per scenario" % ["native" if native else "GDScript", fixture, count, _frames])
	await _wait(10)
	_counts = _now_counts()

	await _measure("idle", func(_i): pass)
	await _measure("hover canvas", func(i): _move(_rect_point(_m.canvas.get_global_rect(), i)))
	await _measure("hover shell (hierarchy)", func(i): _move(_rect_point(_m.shell.get_element("hierarchy-tree").get_global_rect(), i)))
	_move(Vector2(-100, -100))
	var nodes := _drawn()
	await _measure("selection (one change per frame)", func(i): _m.state.select_node(nodes[i % nodes.size()], "canvas"))
	_m.state.select_node(nodes[0], "canvas")
	await _wait(3)
	await _measure("idle with selection", func(_i): pass)
	# Typing: one character per frame into the source view, then the commit.
	_m.source.grab_focus()
	_m.source.set_caret_line(1)
	_m.source.set_caret_column(0)
	_m.source.deselect()
	var before := _m.source.text.length()
	await _measure("typing in the source view", func(i): _type(i))
	print("typed %d characters; focus %s" % [_m.source.text.length() - before, _m.get_viewport().gui_get_focus_owner()])
	await _measure("source commit and settle (1 s)", func(_i): pass, 1.0)
	print("history after typing: %s; pending %s; status %s" % [_m.state.workspace.history.undo_label(), _m.source.has_pending_edit(), _m.shell.get_native("status-label").text])
	_m.canvas.grab_focus()
	# The typing re-parsed the document: find the target again.
	await _wait(3)
	var target: EdUxmlNode = null
	for n in _drawn():
		if n.local == "Button" or target == null:
			target = n
			if n.local == "Button":
				break
	_m.state.select_node(target, "canvas")
	await _wait(5)
	# Drag: a move gesture on the selected element.
	var c := _m.canvas.screen_to_global(_m.canvas.host.rect_of(target.id).get_center())
	_button(c, true)
	await _wait(1)
	_m.canvas.host.rendered.connect(_on_rendered)
	await _measure("drag (move gesture)", func(i): _move(c + Vector2(4 + i, 2 + i * 0.5), true))
	_m.canvas.host.rendered.disconnect(_on_rendered)
	print("render and patch times during the drag (ms): %s" % ", ".join(_render_ms.map(func(x): return "%.1f" % x)))
	_button(c + Vector2(4 + _frames, 2 + _frames * 0.5), false)
	await _wait(3)
	print("history after the drag: %s" % _m.state.workspace.history.undo_label())

	print("")
	print("%-36s %8s %8s %8s %8s %8s %8s" % ["scenario (ms per frame)", "median", "p95", "max", "renders", "patches", "builds"])
	for r in _rows:
		print("%-36s %8.2f %8.2f %8.2f %8d %8d %8d" % r)
	_m.queue_free()
	await _wait(2)
	_rm(_dir)
	quit(0)


## Run `step` before each of `_frames` frames (or for `seconds` of frames)
## and record the wall time of each frame.
func _measure(label: String, step: Callable, seconds: float = 0.0) -> void:
	var times: Array = []
	var start := Time.get_ticks_usec()
	var i := 0
	await process_frame
	var last := Time.get_ticks_usec()
	while (seconds > 0.0 and (Time.get_ticks_usec() - start) < seconds * 1e6) or (seconds <= 0.0 and i < _frames):
		step.call(i)
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		i += 1
	times.sort()
	if ResourceLoader.exists("res://src/ed_prof.gd"):
		load("res://src/ed_prof.gd").dump(label, i)
	var med: float = times[times.size() / 2]
	var p95: float = times[mini(times.size() - 1, int(times.size() * 0.95))]
	var now := _now_counts()
	_rows.append([label, med, p95, times[-1], now[0] - _counts[0], now[1] - _counts[1], now[2] - _counts[2]])
	_counts = now


## The drawn elements of the active document (not the root).
func _drawn() -> Array:
	return _m.state.session.tree().nodes.filter(func(n): return n.parent != null and _m.canvas.host.rect_of(n.id).has_area())


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _rect_point(r: Rect2, i: int) -> Vector2:
	var t := float(i % 30) / 30.0
	return r.position + Vector2(r.size.x * (0.2 + 0.6 * t), r.size.y * (0.3 + 0.4 * t))


func _move(p: Vector2, held: bool = false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	e.relative = Vector2(1, 1)
	_m.get_viewport().push_input(e)


func _button(p: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_m.get_viewport().push_input(e)


## One key press and release of a space (whitespace keeps the elements).
func _type(_i: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_SPACE
		e.unicode = 32 if pressed else 0
		e.pressed = pressed
		_m.get_viewport().push_input(e)


## A project with one document of about 600 elements: panels of rows with
## labels, buttons, toggles and fields, styled by one sheet.
func _make_large(dir: String) -> String:
	DirAccess.make_dir_recursive_absolute(dir + "/Assets/UI")
	var u := PackedStringArray()
	u.append("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">")
	u.append("  <Style src=\"Large.uss\" />")
	u.append("  <ui:VisualElement name=\"root\" class=\"root\">")
	for p in 12:
		u.append("    <ui:VisualElement name=\"panel-%d\" class=\"panel\">" % p)
		u.append("      <ui:Label class=\"title\" text=\"Panel %d\" />" % p)
		for r in 8:
			u.append("      <ui:VisualElement class=\"row\">")
			u.append("        <ui:Label class=\"cell\" text=\"Row %d\" />" % r)
			u.append("        <ui:Button class=\"cell button\" text=\"Go\" />")
			u.append("        <ui:Toggle class=\"cell\" label=\"On\" />")
			u.append("        <ui:TextField class=\"cell\" value=\"text %d\" />" % r)
			u.append("      </ui:VisualElement>")
		u.append("    </ui:VisualElement>")
	u.append("  </ui:VisualElement>")
	u.append("</ui:UXML>")
	var s := ".root { flex-direction: row; flex-wrap: wrap; padding: 4px; }\n" \
		+ ".panel { width: 300px; margin: 2px; background-color: #303030; border-width: 1px; border-color: #555; }\n" \
		+ ".title { -unity-font-style: bold; }\n.row { flex-direction: row; height: 18px; }\n" \
		+ ".cell { flex-grow: 1; font-size: 10px; }\n.button:hover { background-color: #4a4a4a; }\n"
	var f := FileAccess.open(dir + "/Assets/UI/Large.uxml", FileAccess.WRITE)
	f.store_string("\n".join(u) + "\n")
	f.close()
	f = FileAccess.open(dir + "/Assets/UI/Large.uss", FileAccess.WRITE)
	f.store_string(s)
	f.close()
	return "Assets/UI/Large.uxml"


static func _copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from + "/" + f, to + "/" + f)
	for d in DirAccess.get_directories_at(from):
		_copy_tree(from + "/" + d, to + "/" + d)


static func _rm(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_rm(dir + "/" + d)
	DirAccess.remove_absolute(dir)
