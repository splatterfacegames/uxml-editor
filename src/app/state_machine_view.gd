class_name EdStateMachineView
extends Node
## The state-machine panel (milestone 7): the interaction states of the
## selected element as nodes, the state changes as edges (EdStateMachine).
##
## The panel header is godot-uxml (the `sm-*` elements of editor_shell.uxml);
## the graph is an IMGUIContainer that this view draws.
##
## A click on a node forces its states on the canvas (request R6) and shows
## its rules in the declaration list of the inspector. A click on an edge plays
## the state change on the timeline (EdTimelineView.run). The panel owns the
## state that it forces: another selection, a click on the empty graph, Escape
## and the end of the panel give the state preview its states back. A toggle of
## the state preview in the inspector takes the state over: the panel then
## gives nothing back. A render builds the graph again, so a source edit, an
## undo and a redo show at once.
##
## The panel costs nothing while it is closed.

const NODE_W := 76.0
const NODE_H := 18.0
const COLS := {"normal": [0, 1.5], "hover": [1, 0.0], "active": [2, 0.0], "focus": [1, 1.0], "checked": [1, 2.0], "disabled": [1, 3.0]}
const LANE := 2.5
const FONT_SIZE := 11
const ACCENT := Color(1.0, 0.62, 0.2)
const TRANSITION := Color(0.42, 0.68, 1.0)
const INSTANT := Color(0.62, 0.62, 0.62)
const DIM := Color(0.46, 0.46, 0.46)

var shell: UxmlDocument
var state: EdEditorState
var host: EdRenderHost
var inspector: EdInspectorView
var timeline: EdTimelineView
var settings: EdSettings
var box: Control = null
var open := false
## The selected element (-1: none).
var node_id := -1
var model: Dictionary = {"nodes": [], "edges": []}
## {kind: "node" | "edge", id}, or {}.
var selected: Dictionary = {}
## Number of model builds and of draws (tests and the benchmark).
var builds := 0
var draws := 0
var _hover: Dictionary = {}
var _dirty := false
var _dirty_at := 0
var _settling := false
## The state the panel forced: {loc, id, states, saved}, or {}. `id` is the
## node id in the element map of the render host.
var _owner: Dictionary = {}
var _width := 340.0


func attach(p_shell: UxmlDocument, p_state: EdEditorState, p_host: EdRenderHost, p_inspector: EdInspectorView, p_timeline: EdTimelineView, p_settings: EdSettings) -> void:
	shell = p_shell
	state = p_state
	host = p_host
	inspector = p_inspector
	timeline = p_timeline
	settings = p_settings
	shell.set_imgui_handler("sm-graph", _draw, _on_input)
	box = shell.get_element("sm-graph")
	if box != null:
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.focus_mode = Control.FOCUS_CLICK
		box.resized.connect(_redraw)
		box.mouse_exited.connect(_on_mouse_left)
	var w = settings.get_value("layout", "states-split")
	if w is float or w is int:
		_width = clampf(float(w), 120.0, 4000.0)
	set_open(bool(settings.get_value("panels", "states", false)))


# ---------------------------------------------------------------------------
# Open and close
# ---------------------------------------------------------------------------

func set_open(on: bool) -> void:
	var was := open
	open = on
	var t := shell.get_element_model("states-toggle")
	if t != null and str(t.get_attribute("value")) != ("true" if on else "false"):
		t.set_attribute("value", "true" if on else "false")
	if settings.set_value("panels", "states", on):
		settings.save()
	if not on:
		if was:
			save_width()
		release()
		_stop_own_run()
		inspector.clear_state_rules()
		selected = {}
		_hover = {}
		shell.set_class("states-split", "grow states-closed")
		shell.set_class("sm-panel", "panel hidden")
		shell.set_split_dimension("states-split", 0.0)
		return
	shell.set_class("states-split", "grow")
	shell.set_class("sm-panel", "panel")
	shell.set_split_dimension("states-split", _width)
	_mark_dirty()


## Keep the width of the open panel (at each mouse release and at close).
func save_width() -> void:
	if not open:
		return
	_width = snappedf(shell.get_split_dimension("states-split"), 1.0)
	if _width >= 120.0 and settings.set_value("layout", "states-split", _width):
		settings.save()


func on_button(element_name: String) -> bool:
	if element_name == "sm-close":
		set_open(false)
		return true
	return false


func on_value(element_name: String, value: Variant) -> bool:
	if element_name == "states-toggle":
		if bool(value) != open:
			set_open(bool(value))
		return true
	return false


# ---------------------------------------------------------------------------
# Selection and renders
# ---------------------------------------------------------------------------

## The selection changed (or a render showed it again).
func show_selection(n: EdUxmlNode) -> void:
	var id := -1 if n == null else n.id
	if not _owner.is_empty():
		var o: EdUxmlNode = state.session.resolve(_owner["loc"]) if state.session != null else null
		if o == n and n != null:
			# The same element after a change of the tree.
			node_id = id
			if host.is_mapped(state.session.tree()):
				_owner["id"] = id
			return
		_release_on(o)
	if id == node_id:
		return
	node_id = id
	selected = {}
	_hover = {}
	inspector.clear_state_rules()
	_mark_dirty()


## Another document: the load drops the forced states of the old one.
func reset() -> void:
	# The host still has the old document: the same entry path renders again
	# and would keep the states by id.
	if not _owner.is_empty():
		host.set_forced(_owner["id"], _owner["saved"])
	_owner = {}
	selected = {}
	_hover = {}
	node_id = -1
	model = {"nodes": [], "edges": []}
	inspector.clear_state_rules()
	_redraw()


## The canvas rendered again: the rules and the transitions may differ.
func rendered() -> void:
	_mark_dirty()


## The state preview of the inspector changed.
func states_changed() -> void:
	if not _owner.is_empty() and node_id >= 0 and host.forced_of(node_id) != _owner["states"]:
		# The user took the state over.
		_owner = {}
		selected = {}
		inspector.clear_state_rules()
	_redraw()


func _mark_dirty() -> void:
	if not open:
		return
	_dirty = true
	_dirty_at = Engine.get_process_frames()


## The graph waits for a frame without a change: a run of selections (keys
## in the hierarchy) builds once, at its end.
func _process(_dt: float) -> void:
	if _dirty and Engine.get_process_frames() > _dirty_at:
		refresh_now()
	# The transitions of a forced state ended: the inspector shows the
	# computed values of the state.
	if _settling and host.doc != null and not host.doc.has_running_transitions():
		_settling = false
		inspector.refresh()


## Build the model of the selection now (normally at the end of the frame).
func refresh_now() -> void:
	_dirty = false
	builds += 1
	var n := _node()
	if n == null or not host.element_for_node.has(n.id):
		model = {"nodes": [], "edges": []}
		_set_info("")
		_set_target("")
		_redraw()
		return
	var id := n.id
	model = EdStateMachine.build(state.session, n, func(prop: String, q: Dictionary) -> Array: return host.explain(id, prop, q), UssTransitions.SHORTHANDS)
	_set_target(n.local + ("" if n.get_attribute("name") == null else " #" + String(n.get_attribute("name"))))
	if selected.get("kind") == "node":
		_show_rules_of(EdStateMachine.node_of(model, selected["id"]), false)
	elif selected.get("kind") == "edge" and EdStateMachine.edge_of(model, selected["id"]).is_empty():
		selected = {}
	_set_info(_info())
	_redraw()


func _node() -> EdUxmlNode:
	if state == null or state.session == null or node_id < 0:
		return null
	var nodes: Array = state.session.tree().nodes
	return nodes[node_id] if node_id < nodes.size() else null


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

## Force the states of node `id` and show its rules in the inspector.
func select_node(id: String) -> void:
	var n := EdStateMachine.node_of(model, id)
	if n.is_empty() or node_id < 0:
		return
	_stop_own_run()
	timeline.stop()
	var el := _node()
	if _owner.is_empty():
		_owner = {"loc": EdLocator.create(el), "id": node_id, "saved": host.forced_of(node_id), "states": []}
	var want: Array = (n["states"] as Array).duplicate()
	host.set_forced(node_id, want)
	_owner["states"] = host.forced_of(node_id)
	selected = {"kind": "node", "id": id}
	timeline.states_forced()
	_show_rules_of(n, true)
	_set_info(_info())
	inspector.states_changed.emit(node_id, host.forced_of(node_id))
	inspector.refresh()
	_settling = true
	_redraw()


## Play the state change of edge `id` on the timeline, from the start.
func select_edge(id: String) -> void:
	var e := EdStateMachine.edge_of(model, id)
	if e.is_empty() or node_id < 0:
		return
	release()
	selected = {"kind": "edge", "id": id}
	var classes := EdInspectorView.author_classes(_node())
	timeline.run({"classes": classes, "states": (e["from_states"] as Array).duplicate()},
		{"classes": classes, "states": (e["to_states"] as Array).duplicate()}, true)
	var far := EdStateMachine.node_of(model, e["far"])
	inspector.show_state_rules("%s → %s" % [e["from_label"], e["to_label"]], EdStateMachine.rows(far.get("rules", [])), true)
	_set_info(_info())
	_redraw()


## Back to no selection in the panel: the state preview gets its states back,
## and a run of the panel ends.
func clear() -> void:
	release()
	_stop_own_run()
	selected = {}
	inspector.clear_state_rules()
	_set_info(_info())
	_redraw()


## Give the state preview its states back (nothing when the panel forced none).
func release() -> void:
	if _owner.is_empty():
		return
	_release_on(state.session.resolve(_owner["loc"]) if state.session != null else null)


func _release_on(n: EdUxmlNode) -> void:
	var o := _owner
	_owner = {}
	if selected.get("kind") == "node":
		selected = {}
	inspector.clear_state_rules()
	# Between an edit and its render, the host knows the old id: the render
	# then moves what stays with the element.
	var id: int = o["id"]
	if n != null and state.session != null and host.is_mapped(state.session.tree()):
		id = n.id
	host.set_forced(id, o["saved"])
	timeline.states_forced()
	inspector.states_changed.emit(id, host.forced_of(id))
	inspector.refresh()
	_settling = true


func _stop_own_run() -> void:
	if selected.get("kind") == "edge" and timeline.player.armed:
		timeline.stop()


func _show_rules_of(n: Dictionary, scroll: bool) -> void:
	if n.is_empty():
		return
	var rules: Array = n["rules"]
	var title: String = String(n["label"]) + ("  ·  no rule styles this state" if rules.is_empty() else "  ·  %d rule%s" % [rules.size(), "" if rules.size() == 1 else "s"])
	inspector.show_state_rules(title, EdStateMachine.rows(rules), scroll)


# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

func _set_info(text: String) -> void:
	EdUi.set_label(shell, "sm-info", text)


func _set_target(text: String) -> void:
	EdUi.set_label(shell, "sm-target", text)


func _info() -> String:
	var what := _hover if not _hover.is_empty() else selected
	if model["nodes"].is_empty():
		return ""
	match String(what.get("kind", "")):
		"node":
			return _node_text(EdStateMachine.node_of(model, what["id"]))
		"edge":
			return edge_text(EdStateMachine.edge_of(model, what["id"]))
	return "Click a state to force it. Click an arrow to play the change."


static func _node_text(n: Dictionary) -> String:
	if n.is_empty():
		return ""
	var rules: Array = n["rules"]
	if rules.is_empty():
		return "%s: no rule styles this state." % n["label"]
	var first: Dictionary = rules[0]
	return "%s: %s  %s:%d%s" % [n["label"], first["selector"], String(first["path"]).get_file(), int(first["line"]),
		"" if rules.size() == 1 else "  +%d" % (rules.size() - 1)]


## One line about edge `e`: instant, or the times of the transition.
static func edge_text(e: Dictionary) -> String:
	if e.is_empty():
		return ""
	var head := "%s → %s: " % [e["from_label"], e["to_label"]]
	match String(e["kind"]):
		"none":
			return head + "the rules change no value."
		"instant":
			return head + "instant, %s." % ", ".join(PackedStringArray((e["changes"] as Array).map(func(c): return String(c["property"]))))
	var props := PackedStringArray((e["timing"] as Array).map(func(t): return String(t["property"])))
	return head + "%s, %s." % [EdTransitionValues.format_time(e["length"]), ", ".join(props)]


func _redraw() -> void:
	if box != null and open:
		box.queue_redraw()


# ---------------------------------------------------------------------------
# Geometry (box coordinates)
# ---------------------------------------------------------------------------

func _area() -> Rect2:
	if box == null:
		return Rect2()
	var r: Rect2 = box.get("content_rect") if box.get("content_rect") != null else Rect2()
	return r if r.size != Vector2.ZERO else Rect2(Vector2.ZERO, box.size)


## The rectangle of node `id` in box coordinates: the states in three columns.
func node_rect(id: String) -> Rect2:
	var a := _area()
	var gap := clampf((a.size.x - 3.0 * NODE_W - 12.0) / 2.0, 16.0, 110.0)
	var pitch := clampf((a.size.y - 6.0) / 4.0, NODE_H + 2.0, 34.0)
	var top := a.position.y + maxf(3.0, (a.size.y - pitch * 4.0) * 0.5) + (pitch - NODE_H) * 0.5
	var c: Array = COLS[id]
	return Rect2(a.position.x + 6.0 + float(c[0]) * (NODE_W + gap), top + float(c[1]) * pitch, NODE_W, NODE_H)


## The line of edge `e`: [start, end]. Both directions of a pair have a lane
## of their own.
func edge_line(e: Dictionary) -> Array:
	var forward: bool = e["to"] == e["far"]
	var near_r := node_rect(e["from"] if forward else e["to"])
	var far_r := node_rect(e["far"])
	var a := Vector2(near_r.end.x, near_r.get_center().y)
	var b := Vector2(far_r.position.x, far_r.get_center().y)
	var n := (b - a).normalized().orthogonal() * LANE
	if forward:
		return [a + n, b + n]
	return [b - n, a - n]


## A point of a node or an edge in window (global) coordinates (tests).
func to_global(p: Vector2) -> Vector2:
	return box.get_global_transform() * p


## What is under point `p`: {kind: "node" | "edge", id}, or {}.
func hit(p: Vector2) -> Dictionary:
	for n in model["nodes"]:
		if node_rect(n["id"]).has_point(p):
			return {"kind": "node", "id": n["id"]}
	var best := 5.0
	var out := {}
	for e in model["edges"]:
		var l := edge_line(e)
		var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, l[0], l[1]))
		if d < best:
			best = d
			out = {"kind": "edge", "id": e["id"]}
	return out


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_input(_b: Control, ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null:
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			box.grab_focus()
			var h := hit(mb.position)
			match String(h.get("kind", "")):
				"node":
					select_node(h["id"])
				"edge":
					select_edge(h["id"])
				_:
					clear()
		return
	var mm := ev as InputEventMouseMotion
	if mm != null:
		var h := hit(mm.position)
		if h != _hover:
			_hover = h
			box.mouse_default_cursor_shape = Control.CURSOR_ARROW if h.is_empty() else Control.CURSOR_POINTING_HAND
			_set_info(_info())
			_redraw()
		return
	var k := ev as InputEventKey
	if k != null and k.pressed:
		match k.keycode:
			KEY_ESCAPE:
				clear()
				box.accept_event()
			KEY_UP, KEY_DOWN:
				_step_node(-1 if k.keycode == KEY_UP else 1)
				box.accept_event()


func _step_node(d: int) -> void:
	var nodes: Array = model["nodes"]
	if nodes.is_empty():
		return
	var i := -1
	for j in nodes.size():
		if selected.get("kind") == "node" and nodes[j]["id"] == selected["id"]:
			i = j
	select_node(nodes[posmod(i + d, nodes.size())]["id"])


func _on_mouse_left() -> void:
	if not _hover.is_empty():
		_hover = {}
		_set_info(_info())
		_redraw()


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw(b: Control, _rect: Rect2) -> void:
	draws += 1
	var font: Font = ThemeDB.fallback_font
	var a := _area()
	if model["nodes"].is_empty():
		b.draw_string(font, a.position + Vector2(8, 18), "Select an element to see its states.", HORIZONTAL_ALIGNMENT_LEFT, a.size.x - 16.0, FONT_SIZE, DIM)
		return
	for e in model["edges"]:
		_draw_edge(b, e, font)
	var forced: Array = host.forced_of(node_id)
	for n in model["nodes"]:
		_draw_node(b, n, font, forced)


func _edge_shown(e: Dictionary) -> bool:
	if selected.get("kind") != "edge" or selected["id"] != e["id"] or not timeline.player.armed:
		return false
	return _same(timeline.from_state.get("states", []), e["from_states"]) and _same(timeline.to_state.get("states", []), e["to_states"])


static func _same(a: Array, b: Array) -> bool:
	var x := a.duplicate()
	var y := b.duplicate()
	x.sort()
	y.sort()
	return x == y


func _draw_edge(b: Control, e: Dictionary, font: Font) -> void:
	var l := edge_line(e)
	var kind := String(e["kind"])
	var hot: bool = _hover.get("kind") == "edge" and _hover["id"] == e["id"]
	var on := _edge_shown(e)
	var c: Color = TRANSITION if kind == "transition" else (INSTANT if kind == "instant" else DIM)
	if on:
		c = ACCENT
	elif hot:
		c = c.lightened(0.3)
	if kind == "transition":
		b.draw_line(l[0], l[1], c, 2.0, true)
	else:
		b.draw_dashed_line(l[0], l[1], c, 1.0, 3.0 if kind == "instant" else 2.0)
	var dir: Vector2 = (l[1] - l[0]).normalized()
	var n := dir.orthogonal()
	var head: Vector2 = l[1]
	var size := 6.0 if kind == "transition" else 5.0
	b.draw_colored_polygon(PackedVector2Array([head, head - dir * size + n * size * 0.5, head - dir * size - n * size * 0.5]), c)
	if (on or hot) and kind == "transition":
		var text := EdTransitionValues.format_time(e["length"])
		var mid: Vector2 = (l[0] + l[1]) * 0.5
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		b.draw_rect(Rect2(mid.x - w * 0.5 - 2.0, mid.y - 7.0, w + 4.0, 13.0), Color(0.17, 0.17, 0.17))
		b.draw_string(font, Vector2(mid.x - w * 0.5, mid.y + 3.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, c)


func _draw_node(b: Control, n: Dictionary, font: Font, forced: Array) -> void:
	var r := node_rect(n["id"])
	var rules: int = (n["rules"] as Array).size()
	var hot: bool = _hover.get("kind") == "node" and _hover["id"] == n["id"]
	var on: bool = selected.get("kind") == "node" and selected["id"] == n["id"]
	var shows: bool = _same(forced, n["states"])
	if rules > 0:
		b.draw_rect(r, Color(0.24, 0.47, 0.73).lightened(0.14 if hot else 0.0))
	else:
		# A state without rules: no fill and a dashed outline.
		b.draw_rect(r, Color(1, 1, 1, 0.05 if hot else 0.0))
		var line := Color(0.5, 0.5, 0.5)
		b.draw_dashed_line(r.position, Vector2(r.end.x, r.position.y), line, 1.0, 3.0)
		b.draw_dashed_line(Vector2(r.position.x, r.end.y), r.end, line, 1.0, 3.0)
		b.draw_dashed_line(r.position, Vector2(r.position.x, r.end.y), line, 1.0, 3.0)
		b.draw_dashed_line(Vector2(r.end.x, r.position.y), r.end, line, 1.0, 3.0)
	if on:
		b.draw_rect(r.grow(1.0), ACCENT, false, 2.0)
	var text_c := Color(0.95, 0.95, 0.95) if rules > 0 else Color(0.6, 0.6, 0.6)
	var y := r.position.y + 13.0
	# A dot: the canvas shows this state.
	var x := r.position.x + 6.0
	if shows:
		b.draw_circle(Vector2(x, r.get_center().y), 2.5, ACCENT)
	b.draw_string(font, Vector2(x + 5.0, y), String(n["label"]), HORIZONTAL_ALIGNMENT_LEFT, NODE_W - 28.0, FONT_SIZE, text_c)
	if rules > 0:
		b.draw_string(font, Vector2(r.end.x - 11.0, y), str(rules), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.7))
