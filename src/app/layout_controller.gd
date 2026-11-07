class_name EdLayoutController
extends RefCounted
## Turns canvas gestures (handle drags, arrow-key nudges) into layout
## transactions through EdLayoutCommands.
##
## A gesture freezes the start state of the element (computed style,
## rectangle, snap targets). Each pointer move plans the whole gesture from
## that start again and executes it with the gesture's coalesce key, so the
## history keeps one undo step per gesture and the canvas shows the real
## render after each step. At most one step runs per frame. A run of arrow
## keys is one gesture while each key comes less than NUDGE_PAUSE seconds
## (or NUDGE_FRAMES frames, for slow renders) after the render of the
## previous one, the selection stays the same and no other edit comes
## between them.
##
## Write targets (ADR 0004). A drag writes each property to the target that
## the inspector would use (EdInspectorView.gesture_target): the target
## the user chose for the property before (the same memory as the
## inspector fields), the only valid target, or, when more than one target
## is valid, the winning target during the drag and the write-target
## picker at the end of the drag. A choice of another target writes the
## end of the drag there instead (one undo step); Cancel undoes the drag.
## Arrow-key nudges use a remembered choice and else the winner, without
## the picker.

const NUDGE_PAUSE := 0.8
const NUDGE_FRAMES := 2
const SNAP_THRESHOLD_VIEW := 6.0
const GRIDS := [0, 1, 2, 4, 5, 8, 10, 16, 20]

var state: EdEditorState
var canvas: EdCanvasView
## The inspector: write targets of the selection and the picker (null: the
## winners, as in milestone 3).
var inspector: EdInspectorView = null
var snap_enabled := true
var grid := 8

var _counter := 0
var _gesture: Dictionary = {}
var _pending = null
var _flush_queued := false
var _error_shown := false
var _nudge: Dictionary = {}


func _init(s: EdEditorState, c: EdCanvasView) -> void:
	state = s
	canvas = c


func is_active() -> bool:
	return not _gesture.is_empty()


# ---------------------------------------------------------------------------
# Handle gestures
# ---------------------------------------------------------------------------

func begin(handle: String) -> void:
	_end_nudge()
	_gesture = {}
	var n := state.selected_node()
	if n == null or state.session == null:
		return
	var base = _base_for(n)
	if base is EdError:
		state.status.emit("Refused: %s" % base.message, true)
		return
	var id: int = n.id
	var host := canvas.host
	var pid := host.parent_id(id)
	var parent_rect := host.rect_of(pid) if pid >= 0 else Rect2(Vector2.ZERO, canvas.screen_size())
	_counter += 1
	_gesture = {
		"handle": handle, "base": base, "key": "gesture:%d" % _counter,
		"style": {id: host.style_facts(id)},
		"targets": EdSnap.targets(parent_rect, host.sibling_rects(id)),
		"label": ("Move %s" if handle == "move" else "Resize %s") % n.local,
		"steps": 0, "locator": EdLocator.create(n),
		# property -> {choice, ask, choices} (EdInspectorView.gesture_target)
		"choices": {}, "writes": [], "rules": {},
	}
	_error_shown = false


func update(handle: String, delta: Vector2, keep_ratio: bool, no_snap: bool) -> void:
	if _gesture.is_empty() or handle != _gesture["handle"]:
		return
	var d := delta
	var base: Dictionary = _gesture["base"]
	if snap_enabled and not no_snap:
		var s := EdSnap.snap_gesture(base["rect"], handle, delta, _gesture["targets"], float(grid), SNAP_THRESHOLD_VIEW / canvas.zoom)
		d = s["delta"]
		canvas.guides = {"x": s["guides_x"], "y": s["guides_y"]}
	else:
		canvas.guides = {}
	var writes = EdLayoutCommands.gesture_writes(base, handle, d, keep_ratio)
	if writes is EdError:
		_report(writes)
		return
	_gesture["writes"] = writes
	_queue({"writes": writes, "style": _gesture["style"], "label": _gesture["label"], "key": _gesture["key"],
		"targets": _targets_for(writes), "primary": _gesture["locator"]})


func finish(cancelled: bool) -> void:
	_flush()
	canvas.guides = {}
	if _gesture.is_empty():
		return
	var g := _gesture
	var key: String = g["key"]
	_gesture = {}
	if cancelled and state.workspace.history.undo_key() == key:
		state.undo()
	state.workspace.history.break_coalescing()
	if not cancelled and state.workspace.history.undo_key() == key:
		_ask_targets(g)


## The write targets of the gesture's properties, fixed at their first
## write: property -> layout target (EdLayoutCommands.target_of_choice).
func _targets_for(writes: Array) -> Dictionary:
	var out := {}
	if inspector == null:
		return out
	var cs: Dictionary = _gesture["choices"]
	for w in writes:
		var prop: String = w["property"]
		if not cs.has(prop):
			cs[prop] = inspector.gesture_target(prop)
		var choice: Dictionary = cs[prop]["choice"]
		if not choice.is_empty():
			out[prop] = _gesture["rules"].get(prop, EdLayoutCommands.target_of_choice(choice))
	return out


## `targets` named a new rule and a plan with them ran: the rule exists.
## The later steps of the gesture write to the rule, and the memory of the
## property names the rule. Returns property -> the rule target.
func _new_rules_written(targets: Dictionary) -> Dictionary:
	var out := {}
	for prop in targets:
		var t: Dictionary = targets[prop]
		if t["kind"] != "new-rule":
			continue
		var sheet := state.workspace.uss(t["path"])
		if sheet == null:
			continue
		var item: int = sheet.items.size() - 1
		out[prop] = {"kind": "rule", "path": t["path"], "item": item, "decl_index": -1}
		if inspector != null:
			inspector.remember_choice(prop, "rule:%s:%d" % [t["path"], item])
	return out


## After a drag: when a property had more than one valid target and no
## remembered choice, the picker asks. The choice is remembered for every
## asked property that offers it; another target than the one of the drag
## gets the end of the drag instead (the drag step is undone). Cancel
## undoes the drag.
func _ask_targets(g: Dictionary) -> void:
	if inspector == null:
		return
	var asked: Array = []
	for prop in g["choices"]:
		if g["choices"][prop]["ask"]:
			asked.append(prop)
	if asked.is_empty():
		return
	var first: String = asked[0]
	var key: String = g["key"]
	var at := canvas.get_global_mouse_position()
	inspector.ask_target(first, g["choices"][first]["choices"], at, func(c: Dictionary) -> void:
		var targets := {}
		var changed := false
		for prop in g["choices"]:
			var entry: Dictionary = g["choices"][prop]
			var pick: Dictionary = entry["choice"]
			if entry["ask"]:
				for o in entry["choices"]:
					if o["id"] == c["id"]:
						pick = o
				inspector.remember_choice(prop, pick["id"])
				if pick["id"] != entry["choice"]["id"]:
					changed = true
			targets[prop] = EdLayoutCommands.target_of_choice(pick)
		if not changed:
			return
		if state.workspace.history.undo_key() == key:
			state.undo()
		var tx = EdLayoutCommands.plan(state.session, g["writes"], func(node: EdUxmlNode): return g["style"].get(node.id, {}),
			g["label"], "", targets, g["locator"])
		if tx is EdError:
			_error_shown = false
			_report(tx)
			return
		state.execute(tx, "canvas")
		state.workspace.history.break_coalescing()
		_new_rules_written(targets),
		func() -> void:
			if state.workspace.history.undo_key() == key:
				state.undo()
				state.status.emit("Drag undone: no write target chosen.", false))


# ---------------------------------------------------------------------------
# Nudge
# ---------------------------------------------------------------------------

func nudge(delta: Vector2) -> void:
	if state.session == null or state.selection.is_empty() or not _gesture.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var top := state.workspace.history.undo_key()
	var paused: bool = not _nudge.is_empty() and now - float(_nudge["at"]) > NUDGE_PAUSE and Engine.get_process_frames() - int(_nudge["frame"]) > NUDGE_FRAMES
	var other_edit: bool = not _nudge.is_empty() and _nudge["delta"] != Vector2.ZERO and top != _nudge["key"]
	if _nudge.is_empty() or paused or other_edit or _nudge["selection"] != state.selection:
		_start_nudge()
		if _nudge.is_empty():
			return
	_nudge["at"] = now
	_nudge["frame"] = Engine.get_process_frames()
	_nudge["delta"] += delta
	var writes: Array = []
	for base in _nudge["bases"]:
		var w = EdLayoutCommands.gesture_writes(base, "move", _nudge["delta"])
		if w is EdError:
			_report(w)
			return
		writes.append_array(w)
	_queue({"writes": writes, "style": _nudge["style"], "label": _nudge["label"], "key": _nudge["key"],
		"targets": _nudge["targets"], "primary": _nudge["primary"]})


func _start_nudge() -> void:
	state.workspace.history.break_coalescing()
	_nudge = {}
	_error_shown = false
	var bases: Array = []
	var styles := {}
	var nodes: Array = []
	for loc in state.selection:
		var n := state.session.resolve(loc)
		if n == null or n.parent == null:
			continue
		var b = _base_for(n)
		if b is EdError:
			_report(b)
			return
		bases.append(b)
		styles[n.id] = canvas.host.style_facts(n.id)
		nodes.append(n)
	if bases.is_empty():
		return
	_counter += 1
	# One element: a remembered choice of the inspector applies.
	var targets := {}
	if inspector != null and nodes.size() == 1:
		for prop in EdLayoutCommands.MOVE_PROPS:
			var id = inspector.remembered_choice(prop)
			if id != null:
				for c in inspector.choices_for(prop):
					if c["id"] == id:
						targets[prop] = EdLayoutCommands.target_of_choice(c)
	_nudge = {"bases": bases, "style": styles, "delta": Vector2.ZERO, "at": 0.0, "frame": 0,
		"targets": targets, "primary": EdLocator.create(nodes[0]),
		"selection": state.selection.duplicate(true), "key": "nudge:%d" % _counter,
		"label": "Nudge %s" % nodes[0].local if nodes.size() == 1 else "Nudge %d elements" % nodes.size()}


func _end_nudge() -> void:
	_nudge = {}


## The canvas shows the newest render: a nudge run waits for the next key
## from now.
func rendered() -> void:
	if not _nudge.is_empty():
		_nudge["at"] = Time.get_ticks_msec() / 1000.0
		_nudge["frame"] = Engine.get_process_frames()


# ---------------------------------------------------------------------------

func _base_for(n: EdUxmlNode) -> Variant:
	var host := canvas.host
	var id: int = n.id
	if host.control_of(id) == null:
		return EdError.make("not-rendered", "%s is not drawn; it has no layout to change." % n.local)
	var pid := host.parent_id(id)
	var parent_rect := host.rect_of(pid) if pid >= 0 else Rect2(Vector2.ZERO, canvas.screen_size())
	var border := host.border_start(pid) if pid >= 0 else Vector2.ZERO
	return EdLayoutCommands.gesture_base(n, host.style_facts(id), host.rect_of(id), parent_rect, border)


func _queue(step: Dictionary) -> void:
	_pending = step
	if not _flush_queued:
		_flush_queued = true
		_flush.call_deferred()


## Plan and run the newest pending step (one per frame at most).
func _flush() -> void:
	_flush_queued = false
	if _pending == null or state.session == null:
		_pending = null
		return
	var step: Dictionary = _pending
	_pending = null
	var styles: Dictionary = step["style"]
	var tx = EdLayoutCommands.plan(state.session, step["writes"], func(node: EdUxmlNode): return styles.get(node.id, {}), step["label"], step["key"],
		step.get("targets", {}), step.get("primary"))
	if tx is EdError:
		_report(tx)
		return
	if (tx as EdTransaction).is_empty():
		return
	state.execute(tx, "canvas")
	var rules := _new_rules_written(step.get("targets", {}))
	if not _gesture.is_empty() and _gesture["key"] == step["key"]:
		_gesture["rules"].merge(rules, true)


func _report(e: EdError) -> void:
	if not _error_shown:
		_error_shown = true
		state.status.emit("Refused: %s" % e.message, true)
