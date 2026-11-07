class_name EdTimelineView
extends Node
## The transition timeline panel of the window (milestone 6).
##
## The panel header is godot-uxml (the `tl-*` elements of
## editor_shell.uxml); the track area is an IMGUIContainer that this view
## draws (UxmlDocument.set_imgui_handler).
##
## A run is a state change of the selected element: From -> To, each a
## state of EdTimelineModel ({classes, states}). EdTransitionPlayer runs
## the change on the canvas render with the transitions of godot-uxml
## (request R7), and the tracks are the running transitions: one per
## element and property, with the delay, the duration and the easing as a
## bar. Without a run the tracks show the declared transitions of the
## computed style. A state toggle of the state preview and a class edit of
## the class editor start a run and play it, so the canvas shows the
## transitions live.
##
## Playback: play, pause, loop, speed; a press or a drag on the ruler or
## on an empty part of the tracks scrubs (seek_transitions). A drag of a
## bar changes the delay; a drag of its right end changes the duration;
## a double-click opens the easing picker. These edits go through the
## write targets of the inspector (EdInspectorView.gesture_target,
## commit_choice) as one undo step per drag; when more than one target is
## valid and none is remembered, the picker asks at the end of the drag.
##
## A drag writes once, at its end. During the drag the bar follows the
## pointer, and the run shows the new time on the canvas through a preview
## (EdTransitionPlayer.set_preview), without a patch and without a stylesheet
## reload. The reload of the end write waits for a pause of the gestures
## (EdMain._on_buffers_changed): only the timing of the transitions changed,
## and the preview shows it on the element of the run.
## During a run the targets come from the To state: the To state gives the
## transition of a state change. A `:hover` rule sets the duration of the
## change to `:hover`; without one, the rule without states gives it
## (EdStyleTargets.run_choices).

## The status line (refusals and hints).
signal status(message: String, is_error: bool)
## Select another element (a click on the label of its track).
signal select_requested(id: int)
## The render changed without a render of the source (a seek): the canvas
## overlay follows the element.
signal seeked
## A run stopped at a time: the computed values of the inspector are
## out of date.
signal settled

const LABEL_W := 190.0
const RULER_H := 18.0
const ROW_H := 22.0
const EDGE := 6.0
const FONT_SIZE := 11
const SPEED_LABELS := ["0.1×", "0.25×", "0.5×", "1×", "2×"]
const SCOPES := [["Selection", "selection"], ["Document", "document"]]

var shell: UxmlDocument
var state: EdEditorState
var host: EdRenderHost
var inspector: EdInspectorView
var settings: EdSettings
var model := EdTimelineModel.new()
var player: EdTransitionPlayer
## "selection": the tracks of the selected element; "document": every
## track of the run (or every declared transition of the document).
var scope := "selection"
var from_state: Dictionary = {}
var to_state: Dictionary = {}
## The selected element of the timeline (-1: none).
var node_id := -1
## Number of seeks and of draws (tests and the benchmark).
var seeks := 0
var draws := 0
var box: Control = null
## Pixels per second of the track area (kept during a drag).
var _pps := 100.0
var _x0 := 0.0
var _drag: Dictionary = {}
var _hover := -1
var _scroll := 0.0
## A run to start after the next render (a class edit).
var _queued: Dictionary = {}
var _menu_choices := {"from": [], "to": []}
var _counter := 0
var _shown := {}
## The authored tooltips of the From and To fields.
var _tips := {}
## The user set the From or the To text: a render keeps it.
var _custom_states := false
## The next buffer change comes from the end of a bar drag: the render
## waits (EdMain._on_buffers_changed).
var defer_next_render := false
## Runs the render that waits now (set by the main window).
var flush_render: Callable


func attach(p_shell: UxmlDocument, p_state: EdEditorState, p_host: EdRenderHost, p_inspector: EdInspectorView, p_settings: EdSettings) -> void:
	shell = p_shell
	state = p_state
	host = p_host
	inspector = p_inspector
	settings = p_settings
	player = EdTransitionPlayer.new(host)
	shell.set_imgui_handler("tl-tracks", _draw, _on_input)
	box = shell.get_element("tl-tracks")
	if box != null:
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.resized.connect(func(): box.queue_redraw())
		box.mouse_exited.connect(_on_mouse_left)
	shell.set_menu_items("tl-speed", SPEED_LABELS, func(i, _t): set_speed(EdTimelineModel.SPEEDS[i]))
	shell.set_menu_items("tl-scope", SCOPES.map(func(s): return s[0]), func(i, _t): set_scope(SCOPES[i][1]))
	model.loop = bool(settings.get_value("timeline", "loop", false))
	model.speed = float(settings.get_value("timeline", "speed", 1.0))
	scope = String(settings.get_value("timeline", "scope", "selection"))
	_set_toggle("tl-loop", model.loop)
	_menu_text("tl-speed", _speed_label(model.speed))
	_menu_text("tl-scope", _scope_label(scope))
	_refresh_header()


# ---------------------------------------------------------------------------
# Selection, renders, toggles
# ---------------------------------------------------------------------------

## The selection changed (or a render showed it again).
func show_selection(n: EdUxmlNode) -> void:
	var id := -1 if n == null else n.id
	if id == node_id:
		return
	stop()
	node_id = id
	_custom_states = false
	_default_states()
	_refresh_menus()
	_declared_tracks()
	_refresh_header()
	_redraw()


## Another document: node ids name other elements.
func reset() -> void:
	stop()
	node_id = -1
	_custom_states = false
	from_state = {}
	to_state = {}
	model.tracks = []
	_refresh_header()
	_redraw()


## The canvas rendered again: a run continues at the playhead (the edit
## may have changed its transitions); a queued run starts.
func rendered() -> void:
	player.source_classes = _source_classes()
	player.rendered()
	if not _queued.is_empty():
		var q := _queued
		_queued = {}
		if q["id"] == node_id:
			from_state = q["from"]
			to_state = q["to"]
			_arm()
			model.time = 0.0
			model.playing = model.length() > 0.0
			player.seek(0.0)
			_refresh_menus()
			_refresh_header()
			_redraw()
			return
	if player.armed:
		var t := model.time
		_arm()
		model.time = minf(t, model.length())
		player.seek(model.time)
		seeks += 1
	else:
		if node_id >= 0 and not _custom_states:
			_default_states()
		_declared_tracks()
	_refresh_menus()
	_refresh_header()
	_redraw()


## A state toggle of the state preview: play the change.
func states_toggled(id: int, before: Array, after: Array) -> void:
	if id != node_id:
		return
	var classes := _source_classes()
	_custom_states = false
	run({"classes": classes, "states": before}, {"classes": classes, "states": after}, true)


## A class edit of the class editor: play the change after the render of
## the edit.
func classes_toggled(id: int, before: Array, after: Array) -> void:
	if id != node_id:
		return
	var st := host.forced_of(id) if host != null else []
	_custom_states = false
	_queued = {"id": id, "from": {"classes": before, "states": st}, "to": {"classes": after, "states": st}}


## Run the change `from` -> `to` of the selection; `autoplay` plays it
## from the start.
func run(from: Dictionary, to: Dictionary, autoplay: bool = false) -> void:
	from_state = from.duplicate(true)
	to_state = to.duplicate(true)
	_arm()
	model.time = 0.0
	player.seek(0.0)
	model.playing = autoplay and model.length() > 0.0
	_refresh_menus()
	_refresh_header()
	_redraw()


## End the run: the canvas shows the source and the state preview again.
func stop() -> void:
	if flush_render.is_valid():
		flush_render.call()
	var was: bool = player != null and player.armed
	model.playing = false
	model.time = 0.0
	_drag = {}
	_queued = {}
	if player != null:
		player.disarm()
	if was:
		seeked.emit()
		settled.emit()


func _default_states() -> void:
	var classes := _source_classes()
	var st: Array = host.forced_of(node_id) if host != null and node_id >= 0 else []
	from_state = {"classes": classes, "states": st.duplicate()}
	var to_st := st.duplicate()
	if to_st.has("hover"):
		to_st.erase("hover")
	else:
		to_st.append("hover")
	to_state = {"classes": classes.duplicate(), "states": to_st}


func _source_classes() -> Array:
	if state == null or state.session == null or node_id < 0:
		return []
	var nodes: Array = state.session.tree().nodes
	return EdInspectorView.author_classes(nodes[node_id]) if node_id < nodes.size() else []


# ---------------------------------------------------------------------------
# Tracks
# ---------------------------------------------------------------------------

func _arm() -> void:
	if node_id < 0 or host == null:
		model.tracks = []
		return
	player.source_classes = _source_classes()
	var snap := player.arm(node_id, from_state, to_state)
	var out: Array = []
	for t in snap:
		var nid := host.node_of(t["element"])
		if scope == "selection" and nid != node_id:
			continue
		out.append({"node_id": nid, "label": _label(nid), "property": String(t["property"]),
			"delay": float(t["delay"]), "duration": float(t["duration"]), "easing": String(t["easing"]),
			"from": String(t["from"]), "to": String(t["to"]), "running": true})
	out.sort_custom(_track_less)
	model.tracks = out


func _declared_tracks() -> void:
	var out: Array = []
	if host != null and state != null and state.session != null and (node_id >= 0 or scope == "document"):
		var ids: Array = [node_id]
		if scope == "document":
			ids = state.session.tree().nodes.map(func(n): return n.id).filter(func(i): return host.element_for_node.has(i))
		for id in ids:
			for d in EdTransitionValues.declared(host.computed_style(id)):
				out.append({"node_id": id, "label": _label(id), "property": d["property"], "delay": d["delay"],
					"duration": d["duration"], "easing": d["easing"], "from": "", "to": "", "running": false})
	model.tracks = out
	model.time = minf(model.time, model.length())


static func _track_less(a: Dictionary, b: Dictionary) -> bool:
	if a["node_id"] != b["node_id"]:
		return int(a["node_id"]) < int(b["node_id"])
	return String(a["property"]) < String(b["property"])


func _label(id: int) -> String:
	if state == null or state.session == null or id < 0 or id >= state.session.tree().nodes.size():
		return "?"
	var n: EdUxmlNode = state.session.tree().nodes[id]
	var nm = n.get_attribute("name")
	return n.local + ("" if nm == null or String(nm).is_empty() else " #" + String(nm))


# ---------------------------------------------------------------------------
# Playback
# ---------------------------------------------------------------------------

func _process(dt: float) -> void:
	if not _drag.is_empty() and _drag.has("pending"):
		_preview_bar()
	if model.step(dt):
		player.seek(model.time)
		seeks += 1
		_refresh_header()
		_redraw()
		seeked.emit()
		if not model.playing:
			settled.emit()


## Play or pause. Without a run, the run of From -> To starts first.
func toggle_play() -> void:
	if node_id < 0:
		status.emit("Select an element to play its transitions.", false)
		return
	if not player.armed:
		_arm()
		model.time = 0.0
		player.seek(0.0)
	model.toggle_play()
	if not model.playing:
		settled.emit()
	if model.length() <= 0.0:
		status.emit("No transition runs from %s to %s." % [EdTimelineModel.state_text(from_state), EdTimelineModel.state_text(to_state)], false)
	_refresh_header()
	_redraw()


func restart() -> void:
	seek_to(0.0)


## Show the run `t` seconds after the change (the run starts first).
func seek_to(t: float) -> void:
	if node_id < 0:
		return
	if not player.armed:
		_arm()
	model.playing = false
	model.seek(t)
	player.seek(model.time)
	seeks += 1
	_refresh_header()
	_redraw()
	seeked.emit()


func set_speed(s: float) -> void:
	model.speed = s
	_menu_text("tl-speed", _speed_label(s))
	if settings.set_value("timeline", "speed", s):
		settings.save()


func set_loop(on: bool) -> void:
	model.loop = on
	_set_toggle("tl-loop", on)
	if settings.set_value("timeline", "loop", on):
		settings.save()


func set_scope(s: String) -> void:
	scope = s
	_menu_text("tl-scope", _scope_label(s))
	if settings.set_value("timeline", "scope", s):
		settings.save()
	if player.armed:
		var t := model.time
		_arm()
		model.time = minf(t, model.length())
		player.seek(model.time)
	else:
		_declared_tracks()
	_refresh_header()
	_redraw()


## The From or the To state as text (`.a:hover`); refused text changes
## nothing.
func set_state_text(which: String, text: String) -> bool:
	var st = EdTimelineModel.parse_state(text)
	if st is EdError:
		status.emit("Refused: %s" % st.message, true)
		_refresh_header()
		return false
	if which == "from":
		from_state = st
	else:
		to_state = st
	_custom_states = true
	if node_id >= 0:
		var t := model.time
		_arm()
		model.time = minf(t, model.length())
		player.seek(model.time)
	_refresh_header()
	_redraw()
	return true


## The shell sent a button press, a value or a menu choice of the panel.
func on_button(element_name: String) -> bool:
	match element_name:
		"tl-play":
			toggle_play()
		"tl-restart":
			restart()
		_:
			return false
	return true


func on_value(element_name: String, value: Variant) -> bool:
	match element_name:
		"tl-loop":
			set_loop(bool(value))
		"tl-from":
			set_state_text("from", String(value))
		"tl-to":
			set_state_text("to", String(value))
		_:
			return false
	return true


func _refresh_menus() -> void:
	var classes := _source_classes()
	var st: Array = host.forced_of(node_id) if host != null and node_id >= 0 else []
	var choices := EdTimelineModel.state_choices(classes, st, _known_classes())
	var texts: Array = choices.map(EdTimelineModel.state_text)
	if _changed("menus", texts):
		_menu_choices["from"] = choices
		_menu_choices["to"] = choices
		shell.set_menu_items("tl-from-menu", texts, func(i, _t): _choose_state("from", i))
		shell.set_menu_items("tl-to-menu", texts, func(i, _t): _choose_state("to", i))


func _choose_state(which: String, i: int) -> void:
	var cs: Array = _menu_choices[which]
	if i >= 0 and i < cs.size():
		set_state_text(which, EdTimelineModel.state_text(cs[i]))


## The classes that the rules of the document's stylesheets name.
func _known_classes() -> Array:
	var out: Array = []
	if state == null or state.session == null:
		return out
	var re := RegEx.create_from_string("\\.(-?[A-Za-z_][A-Za-z0-9_-]*)")
	for p in state.session.style_paths():
		var sheet = state.workspace.uss(p)
		if sheet == null:
			continue
		for it in sheet.items:
			if it.get("kind") != "rule":
				continue
			for m in re.search_all(String(it.get("selector_text", ""))):
				if not out.has(m.get_string(1)):
					out.append(m.get_string(1))
	return out


# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

func _refresh_header() -> void:
	if shell == null:
		return
	EdUi.set_label(shell, "tl-time", "%.2f s / %.2f s" % [model.time, model.length()])
	EdUi.set_label(shell, "tl-play", "❚❚" if model.playing else "▶")
	_field("tl-from", EdTimelineModel.state_text(from_state) if node_id >= 0 else "")
	_field("tl-to", EdTimelineModel.state_text(to_state) if node_id >= 0 else "")
	EdUi.set_label(shell, "tl-info", _info())


func _info() -> String:
	if node_id < 0:
		return "Select an element to see its transitions."
	if _hover >= 0 and _hover < model.tracks.size():
		var t: Dictionary = model.tracks[_hover]
		var s := "%s · %s · delay %s · %s · %s" % [t["label"], t["property"], EdTransitionValues.format_time(t["delay"]),
			EdTransitionValues.format_time(t["duration"]), t["easing"]]
		if t["running"]:
			s += " · %s → %s" % [t["from"], t["to"]]
		return s
	if model.tracks.is_empty():
		if player.armed:
			return "No transition runs from %s to %s." % [EdTimelineModel.state_text(from_state), EdTimelineModel.state_text(to_state)]
		return "No transition-* declaration applies to the selection."
	if not player.armed:
		return "Declared transitions. Play or scrub runs %s → %s." % [EdTimelineModel.state_text(from_state), EdTimelineModel.state_text(to_state)]
	return "%d transition%s" % [model.tracks.size(), "" if model.tracks.size() == 1 else "s"]


func _field(element_name: String, text: String) -> void:
	var c := shell.get_native(element_name) as LineEdit
	if c == null or c.has_focus() or c.text == text:
		return
	c.text = text
	# A long state can pass the width of the field.
	if not _tips.has(element_name):
		_tips[element_name] = c.tooltip_text
	c.tooltip_text = text + "
" + String(_tips[element_name])
	EdUi.set_silent(shell, element_name, "value", text)


func _set_toggle(element_name: String, on: bool) -> void:
	var el := shell.get_element_model(element_name)
	var v := "true" if on else "false"
	if el != null and str(el.get_attribute("value")) != v:
		el.set_attribute("value", v)


func _menu_text(element_name: String, text: String) -> void:
	if not _changed("menu:" + element_name, text):
		return
	var el := shell.get_element_model(element_name)
	if el != null:
		el.set_attribute("text", text)


func _changed(key: String, data: Variant) -> bool:
	if _shown.has(key) and _shown[key] == data:
		return false
	_shown[key] = data.duplicate(true) if data is Array or data is Dictionary else data
	return true


static func _speed_label(s: float) -> String:
	var i := EdTimelineModel.SPEEDS.find(s)
	return SPEED_LABELS[i] if i >= 0 else "%s×" % String.num(s, 2)


static func _scope_label(s: String) -> String:
	for e in SCOPES:
		if e[1] == s:
			return e[0]
	return s


func _redraw() -> void:
	if box != null:
		box.queue_redraw()


# ---------------------------------------------------------------------------
# Geometry (box coordinates)
# ---------------------------------------------------------------------------

func _area() -> Rect2:
	if box == null:
		return Rect2()
	var r: Rect2 = box.get("content_rect") if box.get("content_rect") != null else Rect2()
	return r if r.size != Vector2.ZERO else Rect2(Vector2.ZERO, box.size)


func _update_scale() -> void:
	var a := _area()
	_x0 = a.position.x + LABEL_W + 10.0
	if _drag.get("kind", "") != "bar":
		_pps = EdTimelineModel.scale_for(model.length(), a.end.x - _x0 - 14.0)


func time_x(t: float) -> float:
	return _x0 + t * _pps


func x_time(x: float) -> float:
	return (x - _x0) / _pps


func _row_y(i: int) -> float:
	return _area().position.y + RULER_H + i * ROW_H - _scroll


## The bar of track `i` in box coordinates.
func bar_rect(i: int) -> Rect2:
	_update_scale()
	var t: Dictionary = model.tracks[i]
	var x := time_x(float(t["delay"]))
	return Rect2(x, _row_y(i) + 3.0, maxf(2.0, float(t["duration"]) * _pps), ROW_H - 6.0)


## A point of the box in window (global) coordinates (tests).
func to_global(p: Vector2) -> Vector2:
	return box.get_global_transform() * p


func _track_at(p: Vector2) -> int:
	var i := int(floor((p.y - _area().position.y - RULER_H + _scroll) / ROW_H))
	return i if p.y >= _area().position.y + RULER_H and i >= 0 and i < model.tracks.size() else -1


## What is under point `p`: {kind: "ruler"|"label"|"bar"|"end"|"empty", track}.
func hit(p: Vector2) -> Dictionary:
	_update_scale()
	if p.y < _area().position.y + RULER_H:
		return {"kind": "ruler", "track": -1}
	var i := _track_at(p)
	if i < 0:
		return {"kind": "empty", "track": -1}
	if p.x < _area().position.x + LABEL_W:
		return {"kind": "label", "track": i}
	var r := bar_rect(i)
	if absf(p.x - r.end.x) <= EDGE and p.y >= r.position.y - 2 and p.y <= r.end.y + 2:
		return {"kind": "end", "track": i}
	if r.grow_individual(2, 2, 0, 2).has_point(p):
		return {"kind": "bar", "track": i}
	return {"kind": "empty", "track": i}


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_input(_b: Control, ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var rows := model.tracks.size() * ROW_H + RULER_H
				_scroll = clampf(_scroll + (ROW_H if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -ROW_H), 0.0, maxf(0.0, rows - _area().size.y))
				_redraw()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			box.grab_focus()
			_press(mb.position, mb.double_click, mb.alt_pressed or mb.is_command_or_control_pressed())
		else:
			_release()
		return
	var mm := ev as InputEventMouseMotion
	if mm != null:
		if _drag.is_empty():
			_hover_at(mm.position)
		else:
			_motion(mm.position, mm.alt_pressed or mm.is_command_or_control_pressed())
		return
	var k := ev as InputEventKey
	if k != null and k.pressed:
		if k.keycode == KEY_SPACE:
			toggle_play()
			box.accept_event()
		elif k.keycode == KEY_HOME:
			restart()
			box.accept_event()
		elif k.keycode == KEY_ESCAPE and _drag.get("kind", "") == "bar":
			_cancel_bar()
			box.accept_event()


func _on_mouse_left() -> void:
	if _hover >= 0:
		_hover = -1
		_refresh_header()
		_redraw()


func _hover_at(p: Vector2) -> void:
	var h := hit(p)
	var i: int = h["track"]
	box.mouse_default_cursor_shape = Control.CURSOR_HSIZE if h["kind"] == "end" else (Control.CURSOR_DRAG if h["kind"] == "bar" else Control.CURSOR_ARROW)
	if i != _hover:
		_hover = i
		_refresh_header()
		_redraw()


func _press(p: Vector2, double: bool, no_snap: bool) -> void:
	# A drag reads the computed lists: the end write of the last drag first.
	if flush_render.is_valid():
		flush_render.call()
	var h := hit(p)
	var i: int = h["track"]
	match String(h["kind"]):
		"label":
			var id: int = model.tracks[i]["node_id"]
			if id != node_id and id >= 0:
				select_requested.emit(id)
		"bar", "end":
			var tr: Dictionary = model.tracks[i]
			if int(tr["node_id"]) != node_id:
				status.emit("Select %s to edit its transitions." % tr["label"], false)
				_start_scrub(p)
			elif double:
				_easing_for(i)
			else:
				_start_bar(i, "end" if h["kind"] == "end" else "move", p)
		_:
			_start_scrub(p)


func _start_scrub(p: Vector2) -> void:
	_drag = {"kind": "scrub"}
	seek_to(maxf(0.0, x_time(p.x)))


func _motion(p: Vector2, no_snap: bool) -> void:
	match String(_drag.get("kind", "")):
		"scrub":
			seek_to(maxf(0.0, x_time(p.x)))
		"bar":
			var dt := (p.x - float(_drag["x"])) / _pps
			var nv := EdTimelineModel.drag_bar(_drag["delay0"], _drag["duration0"], _drag["part"], dt, not no_snap)
			var sec: float = nv["delay"] if _drag["part"] == "move" else nv["duration"]
			if absf(sec - float(_drag["last"])) > 0.0005:
				_drag["last"] = sec
				_drag["pending"] = sec
				var tr: Dictionary = model.tracks[_drag["track"]] if _drag["track"] < model.tracks.size() else {}
				if not tr.is_empty():
					tr["delay"] = nv["delay"]
					tr["duration"] = nv["duration"]
				_redraw()


func _release() -> void:
	var d := _drag
	if d.get("kind", "") == "bar":
		_finish_bar()
		_drag = {}
	elif d.get("kind", "") == "scrub":
		_drag = {}
		settled.emit()
	else:
		_drag = {}
	_redraw()


# ---------------------------------------------------------------------------
# Bar edits (transition-delay, transition-duration, the timing function)
# ---------------------------------------------------------------------------

## The list of `longhand` and the entry of track `tr` in it, from the
## computed style of its element: {names, list, k} or an EdError.
func _entry_of(tr: Dictionary, longhand: String) -> Variant:
	var cs := host.computed_style(int(tr["node_id"]))
	var names := EdTransitionValues.list_or_initial("transition-property", EdTransitionValues._v(cs, "transition-property"))
	var durs := EdTransitionValues.list_or_initial("transition-duration", EdTransitionValues._v(cs, "transition-duration"))
	var delays := EdTransitionValues.list_or_initial("transition-delay", EdTransitionValues._v(cs, "transition-delay"))
	var k := EdTransitionValues.entry_index(names, durs, delays, String(tr["property"]), UssTransitions.SHORTHANDS)
	if k < 0:
		return EdError.make("invalid-target", "No transition-property entry animates %s." % tr["property"])
	return {"names": names, "list": EdTransitionValues._v(cs, longhand), "k": k}


func _start_bar(i: int, part: String, p: Vector2) -> void:
	var tr: Dictionary = model.tracks[i]
	var prop := "transition-delay" if part == "move" else "transition-duration"
	var e = _entry_of(tr, prop)
	if e is EdError:
		status.emit("Refused: %s" % e.message, true)
		return
	var g := inspector.gesture_target(prop, _target_states())
	if g["choice"].is_empty():
		status.emit("Refused: %s has no write target (a pseudo-state needs a rule)." % prop, true)
		return
	model.playing = false
	_counter += 1
	_drag = {"kind": "bar", "track": i, "part": part, "x": p.x, "delay0": float(tr["delay"]), "duration0": float(tr["duration"]),
		"last": float(tr["delay"]) if part == "move" else float(tr["duration"]), "prop": prop, "entry": e,
		"id": String(g["choice"]["id"]), "first_id": String(g["choice"]["id"]), "ask": bool(g["ask"]), "choices": g["choices"],
		"key": "timeline:%d" % _counter, "value": ""}


## The pseudo-states of the write targets of an edit: the To state of a
## run, else the state preview (null).
func _target_states() -> Variant:
	return (to_state.get("states", []) as Array).duplicate() if player.armed else null


## The text of the edited list for a value of `sec` seconds.
func _bar_text(sec: float) -> String:
	var e: Dictionary = _drag["entry"]
	return EdTransitionValues.with_entry(_drag["prop"], e["list"], (e["names"] as Array).size(), int(e["k"]), EdTransitionValues.format_time(sec))


## Show the newest value of the drag on the run (one preview per frame). The
## value stays in `value` for the end write.
func _preview_bar() -> void:
	var sec: float = _drag["pending"]
	_drag.erase("pending")
	var text := _bar_text(sec)
	_drag["value"] = text
	if not player.armed:
		return
	var decl: Dictionary = _drag.get("preview", {})
	decl[_drag["prop"]] = text
	_drag["preview"] = decl
	player.set_preview(decl)
	var t := model.time
	var i: int = _drag["track"]
	_arm()
	model.time = minf(t, model.length())
	player.seek(model.time)
	seeks += 1
	seeked.emit()
	_refresh_header()
	if i < model.tracks.size():
		_redraw()


## The end of a drag: one write, one undo step. A remembered or only target
## keeps the preview: the render waits for a pause.
func _finish_bar() -> void:
	if _drag.has("pending"):
		_preview_bar()
	var d := _drag
	if d.is_empty() or String(d.get("value", "")).is_empty():
		_end_preview()
		return
	var ask: bool = d["ask"]
	if player.armed and not ask:
		defer_next_render = true
	else:
		_end_preview()
	var id := inspector.commit_choice(d["prop"], d["value"], d["id"], d["key"], _target_states())
	var h := state.workspace.history
	if id.is_empty():
		# Refused: no buffer change came.
		defer_next_render = false
		_end_preview()
		_arm_again()
		return
	d["id"] = id
	h.break_coalescing()
	if not ask:
		return
	var key: String = d["key"]
	var prop: String = d["prop"]
	var value: String = d["value"]
	var st = _target_states()
	var at := box.get_global_mouse_position() if box != null else Vector2.ZERO
	inspector.ask_target(prop, d["choices"], at, func(c: Dictionary) -> void:
		# A new rule is a rule after its first write: the memory names the rule.
		if c["id"] == d["first_id"]:
			inspector.remember_choice(prop, d["id"])
			return
		if h.undo_key() == key:
			state.undo()
		var nid := inspector.commit_choice(prop, value, c["id"], "", st)
		inspector.remember_choice(prop, c["id"] if nid.is_empty() else nid)
		h.break_coalescing(),
		func() -> void:
			if h.undo_key() == key:
				state.undo())


## Escape during a drag: nothing was written. The run shows the source again.
func _cancel_bar() -> void:
	_drag = {}
	_end_preview()
	if player.armed:
		_arm_again()
	else:
		_declared_tracks()
	_refresh_header()
	_redraw()


func _end_preview() -> void:
	if player != null and player.has_preview():
		player.clear_preview()


## The run again at the playhead, with the values of the source.
func _arm_again() -> void:
	if not player.armed:
		return
	var t := model.time
	_arm()
	model.time = minf(t, model.length())
	player.seek(model.time)
	seeks += 1
	seeked.emit()


## True while a reload would stop a gesture or playback.
func reload_blocked() -> bool:
	return not _drag.is_empty() or model.playing


## The render of the source runs next: the preview goes first, so the render
## and the source agree. Returns true when a preview showed.
func before_render() -> bool:
	var had: bool = player != null and player.has_preview()
	_end_preview()
	return had


## The easing picker for the timing function entry of track `i`.
func _easing_for(i: int) -> void:
	var tr: Dictionary = model.tracks[i]
	var e = _entry_of(tr, "transition-timing-function")
	if e is EdError:
		status.emit("Refused: %s" % e.message, true)
		return
	var prop := "transition-timing-function"
	inspector.open_easing_picker(prop, box, func(kw: String) -> void:
		set_track_easing(e, kw), String(tr["easing"]))


## Write keyword `kw` to the timing function entry `e` (_entry_of): the
## same targets as a bar edit, one undo step.
func set_track_easing(e: Dictionary, kw: String) -> void:
	var prop := "transition-timing-function"
	var text := EdTransitionValues.with_entry(prop, e["list"], (e["names"] as Array).size(), int(e["k"]), kw)
	var st = _target_states()
	var g := inspector.gesture_target(prop, st)
	if g["choice"].is_empty():
		status.emit("Refused: %s has no write target (a pseudo-state needs a rule)." % prop, true)
		return
	if not g["ask"]:
		inspector.commit_choice(prop, text, g["choice"]["id"], "", st)
		return
	inspector.ask_target(prop, g["choices"], box.get_global_mouse_position(), func(c: Dictionary) -> void:
		var nid := inspector.commit_choice(prop, text, c["id"], "", st)
		inspector.remember_choice(prop, c["id"] if nid.is_empty() else nid))


## The timing function entry of track `i` ({names, list, k}, or an EdError).
func easing_entry(i: int) -> Variant:
	return _entry_of(model.tracks[i], "transition-timing-function")


## Set the delay or the duration of track `i` as one edit (the same path
## as a drag; tests and the keyboard).
func edit_track(i: int, part: String, seconds: float) -> void:
	if i < 0 or i >= model.tracks.size():
		return
	_start_bar(i, part, Vector2.ZERO)
	if _drag.is_empty():
		return
	_drag["pending"] = seconds
	_finish_bar()
	_drag = {}


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw(b: Control, _rect: Rect2) -> void:
	draws += 1
	_update_scale()
	var a := _area()
	var font: Font = ThemeDB.fallback_font
	var fs := FONT_SIZE
	var text_c := Color(0.82, 0.82, 0.82)
	var dim := Color(0.55, 0.55, 0.55)
	# Ruler.
	b.draw_rect(Rect2(a.position, Vector2(a.size.x, RULER_H)), Color(0.2, 0.2, 0.2))
	var step := EdTimelineModel.tick_step(_pps)
	var t := 0.0
	var end_t := x_time(a.end.x)
	while t <= end_t + 0.0001:
		var x := time_x(t)
		b.draw_line(Vector2(x, a.position.y + RULER_H - 5), Vector2(x, a.position.y + RULER_H), dim, 1.0)
		b.draw_line(Vector2(x, a.position.y + RULER_H), Vector2(x, a.end.y), Color(1, 1, 1, 0.04), 1.0)
		b.draw_string(font, Vector2(x + 2, a.position.y + 12), _tick_text(t, step), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)
		t += step
	if model.length() > 0.0:
		var ex := time_x(model.length())
		b.draw_line(Vector2(ex, a.position.y), Vector2(ex, a.end.y), Color(1, 1, 1, 0.18), 1.0)
	# Tracks.
	for i in model.tracks.size():
		var y := _row_y(i)
		if y + ROW_H < a.position.y + RULER_H or y > a.end.y:
			continue
		var tr: Dictionary = model.tracks[i]
		var running: bool = tr["running"]
		if i == _hover:
			b.draw_rect(Rect2(a.position.x, y, a.size.x, ROW_H), Color(1, 1, 1, 0.05))
		var own: bool = int(tr["node_id"]) == node_id
		var label := "%s  %s" % [tr["property"], "" if own else "· " + String(tr["label"])]
		label = UxmlStyleApplier.elide_text(label, LABEL_W - 12, "end", font, fs)
		b.draw_string(font, Vector2(a.position.x + 6, y + 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_c if running else dim)
		var r := bar_rect(i)
		# The delay: a thin line from the change to the start of the bar.
		if float(tr["delay"]) > 0.0:
			b.draw_dashed_line(Vector2(time_x(0.0), r.get_center().y), Vector2(r.position.x, r.get_center().y), dim, 1.0, 3.0)
		var fill := Color(0.24, 0.47, 0.73) if running else Color(0.3, 0.36, 0.44)
		if not _drag.is_empty() and _drag.get("track", -1) == i:
			fill = Color(0.36, 0.58, 0.85)
		b.draw_rect(r, fill)
		b.draw_rect(r, Color(0, 0, 0, 0.5), false, 1.0)
		EdEasingCurve.draw(b, r.grow(-2), String(tr["easing"]), Color(1, 1, 1, 0.75 if running else 0.45), 1.2)
		var et := String(tr["easing"])
		var tw := font.get_string_size(et, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		if r.size.x > tw + 10:
			# A dark band under the name: the curve never crosses the text.
			b.draw_rect(Rect2(r.position.x + 2, r.end.y - 13, tw + 4, 12), fill.darkened(0.45))
			b.draw_string(font, Vector2(r.position.x + 4, r.end.y - 3), et, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.92))
		# The end handle.
		b.draw_rect(Rect2(r.end.x - 2, r.position.y, 3, r.size.y), Color(1, 1, 1, 0.5))
	b.draw_line(Vector2(a.position.x + LABEL_W, a.position.y), Vector2(a.position.x + LABEL_W, a.end.y), Color(0, 0, 0, 0.5), 1.0)
	# The playhead.
	if player != null and player.armed:
		var px := time_x(model.time)
		b.draw_line(Vector2(px, a.position.y), Vector2(px, a.end.y), Color(1.0, 0.62, 0.2), 1.5)
		b.draw_rect(Rect2(px - 4, a.position.y, 8, 6), Color(1.0, 0.62, 0.2))
	if model.tracks.is_empty():
		var msg := _info()
		b.draw_string(font, Vector2(a.position.x + LABEL_W + 16, a.position.y + RULER_H + 18), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)


static func _tick_text(t: float, step: float) -> String:
	if step >= 1.0:
		return "%ds" % int(roundf(t))
	if step >= 0.1:
		return "%.1fs" % t
	return "%.2fs" % t
