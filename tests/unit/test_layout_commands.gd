extends EdTestCase
## Milestone 3 layout writes: write targets (ADR 0004), gesture math,
## snapping, and one undo step per gesture.

const USS := "Assets/UI/screen.uss"
const UXML_ABS := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <Style src=\"screen.uss\" />\n  <ui:VisualElement name=\"box\" class=\"r\" />\n  <ui:VisualElement name=\"other\" class=\"r\" />\n</ui:UXML>\n"


static func _theme(value: String) -> Dictionary:
	return {"value": value, "origin": {"kind": "theme"}}


static func _rule(value: String, item: int, decl: int, states: Array = []) -> Dictionary:
	var o := {"kind": "rule", "path": USS, "item": item, "decl_index": decl}
	if not states.is_empty():
		o["states"] = states
	return {"value": value, "origin": o}


func _writes(s: EdDocumentSession, who: String, props: Dictionary) -> Array:
	var out: Array = []
	for p in props:
		out.append({"locator": with_name(s, who), "property": p, "value": props[p]})
	return out


func test_theme_or_default_values_go_to_a_new_inline_style() -> void:
	var s := open_session(UXML_ABS, {USS: ".r { color: red; }\n"})
	var style := {"position": _theme("absolute")}
	var tx = EdLayoutCommands.plan(s, _writes(s, "box", {"left": 30.0, "top": 40.4}), func(_n): return style, "Move", "g1")
	if not is_tx(tx):
		return
	eq(tx.coalesce_key, "g1")
	eq(tx.paths(), [ENTRY], "only the UXML file changes")
	run(s, tx)
	ok(text(s).contains("<ui:VisualElement name=\"box\" class=\"r\" style=\"left: 30px; top: 40.4px;\" />"), text(s))


func test_rule_winners_are_written_in_their_rule() -> void:
	var sheet := "#box {\r\n    position: absolute;\r\n    left: 10px;\r\n    top: 5%;\r\n}\r\n"
	var s := open_session(UXML_ABS, {USS: sheet})
	var style := {"left": _rule("10px", 0, 1), "top": _rule("5%", 0, 2)}
	var tx = EdLayoutCommands.plan(s, _writes(s, "box", {"left": 12.5, "top": -3.0}), func(_n): return style, "Move")
	if not is_tx(tx):
		return
	eq(tx.paths(), [USS])
	run(s, tx)
	eq(s.workspace.text(USS), "#box {\r\n    position: absolute;\r\n    left: 12.5px;\r\n    top: -3px;\r\n}\r\n", "values replaced in place, CRLF kept")
	eq(text(s), UXML_ABS)


func test_shorthand_winner_gets_a_longhand_after_it() -> void:
	var s := open_session(UXML_ABS, {USS: ".r { margin: 4px; }\n"})
	var style := {"margin-left": _rule("4px", 0, 0)}
	var tx = EdLayoutCommands.plan(s, _writes(s, "box", {"margin-left": 10.0}), func(_n): return style, "Move")
	run(s, tx)
	eq(s.workspace.text(USS), ".r { margin: 4px; margin-left: 10px; }\n")
	var s2 := open_session(UXML_ABS, {USS: ".r { margin-left: 2px; margin: 4px; }\n"})
	var style2 := {"margin-left": _rule("4px", 0, 1)}
	is_error(EdLayoutCommands.plan(s2, _writes(s2, "box", {"margin-left": 10.0}), func(_n): return style2, "Move"), "ambiguous-source", "an earlier longhand is overridden")


func test_refusals() -> void:
	var s := open_session(UXML_ABS, {USS: ".r:hover { left: 1px; }\n"})
	var hover := {"left": _rule("1px", 0, 0, ["hover"])}
	is_error(EdLayoutCommands.plan(s, _writes(s, "box", {"left": 3.0}), func(_n): return hover, "Move"), "ambiguous-source", "pseudo-state winner")
	var inh := {"left": {"value": "1px", "origin": {"kind": "inherited", "origin": {"kind": "inline", "decl_index": 0}}}}
	is_error(EdLayoutCommands.plan(s, _writes(s, "box", {"left": 3.0}), func(_n): return inh, "Move"), "ambiguous-source", "inherited authored value")
	is_error(EdLayoutCommands.plan(s, _writes(s, "box", {"left": INF}), func(_n): return {}, "Move"), "invalid-value")
	is_error(EdLayoutCommands.plan(s, [], func(_n): return {}, "Move"), "invalid-selection")


func test_inline_winner_is_replaced_in_place() -> void:
	var src := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Label name=\"box\" style='width: 3px ; color: red' /></ui:UXML>"
	var s := open_session(src)
	var style := {"width": {"value": "3px", "origin": {"kind": "inline", "decl_index": 0}}}
	run(s, EdLayoutCommands.plan(s, _writes(s, "box", {"width": 64.0}), func(_n): return style, "Resize"))
	eq(text(s), src.replace("width: 3px", "width: 64px"), "quote style and spacing kept")


func test_shared_rule_needs_one_value() -> void:
	var s := open_session(UXML_ABS, {USS: ".r { left: 0px; }\n"})
	var style := {"left": _rule("0px", 0, 0)}
	var writes := _writes(s, "box", {"left": 5.0}) + _writes(s, "other", {"left": 6.0})
	is_error(EdLayoutCommands.plan(s, writes, func(_n): return style, "Nudge"), "ambiguous-source")
	writes = _writes(s, "box", {"left": 5.0}) + _writes(s, "other", {"left": 5.0})
	var tx = EdLayoutCommands.plan(s, writes, func(_n): return style, "Nudge")
	run(s, tx)
	eq(s.workspace.text(USS), ".r { left: 5px; }\n", "one write through the shared rule")


# ---------------------------------------------------------------------------
# Gesture math
# ---------------------------------------------------------------------------

func test_gesture_writes_for_absolute_and_relative_elements() -> void:
	var s := open_session(UXML_ABS)
	var node := s.resolve(with_name(s, "box"))
	var abs_style := {"position": _theme("absolute"), "left": _theme("10px")}
	var base = EdLayoutCommands.gesture_base(node, abs_style, Rect2(110, 220, 100, 50), Rect2(100, 200, 500, 500), Vector2(0, 2))
	eq(base["left"], 10.0, "px left is read")
	eq(base["top"], 18.0, "top falls back to the layout (rect - parent - border - margin)")
	var w = EdLayoutCommands.gesture_writes(base, "move", Vector2(5.4, -3.0))
	eq(w.map(func(x): return [x["property"], x["value"]]), [["left", 15.0], ["top", 15.0]])
	w = EdLayoutCommands.gesture_writes(base, "nw", Vector2(10, 5))
	eq(w.map(func(x): return [x["property"], x["value"]]), [["width", 90.0], ["height", 45.0], ["left", 20.0], ["top", 23.0]], "the far corner stays")
	w = EdLayoutCommands.gesture_writes(base, "se", Vector2(100, 0), true)
	eq(w.map(func(x): return [x["property"], x["value"]]), [["width", 200.0], ["height", 100.0]], "Shift keeps the ratio")
	w = EdLayoutCommands.gesture_writes(base, "e", Vector2(-500, 0))
	eq(w.map(func(x): return [x["property"], x["value"]]), [["width", 0.0]], "sizes stop at zero")
	var rel = EdLayoutCommands.gesture_base(node, {"margin-left": _theme("4px")}, Rect2(0, 0, 10, 10), Rect2(), Vector2.ZERO)
	w = EdLayoutCommands.gesture_writes(rel, "move", Vector2(3, 7))
	eq(w.map(func(x): return [x["property"], x["value"]]), [["margin-left", 7.0], ["margin-top", 7.0]], "relative elements move by margins")
	var auto = EdLayoutCommands.gesture_base(node, {"margin-left": _theme("auto")}, Rect2(0, 0, 10, 10), Rect2(), Vector2.ZERO)
	is_error(EdLayoutCommands.gesture_writes(auto, "move", Vector2(3, 7)), "ambiguous-source", "auto margin")
	is_error(EdLayoutCommands.gesture_base(s.root(), {}, Rect2(), Rect2(), Vector2.ZERO), "illegal-root")


func test_format_px() -> void:
	eq(EdLayoutCommands.format_px(3.0), "3px")
	eq(EdLayoutCommands.format_px(-0.0), "0px")
	eq(EdLayoutCommands.format_px(1.23456), "1.235px")
	eq(EdLayoutCommands.px("12px"), 12.0)
	eq(EdLayoutCommands.px("-3.5"), -3.5)
	eq(EdLayoutCommands.px("50%"), null)
	eq(EdLayoutCommands.px({"value": "auto"}), null)


# ---------------------------------------------------------------------------
# Snapping
# ---------------------------------------------------------------------------

func test_snap_to_siblings_parent_and_grid() -> void:
	var tg := EdSnap.targets(Rect2(0, 0, 400, 300), [Rect2(200, 100, 50, 50)])
	var r := Rect2(10, 10, 40, 20)
	# Right edge 10+40+148 = 198 is 2 px from the sibling's left edge 200.
	var s := EdSnap.snap_gesture(r, "move", Vector2(148, 3), tg, 8.0, 5.0)
	eq(s["delta"].x, 150.0, "x snaps the right edge to the sibling")
	eq(s["guides_x"], [200.0])
	eq(s["delta"].y, 6.0, "y has no target near: the top edge snaps to the 8 px grid (10+3 -> 16)")
	eq(s["guides_y"], [])
	s = EdSnap.snap_gesture(r, "move", Vector2(-8.5, 0), tg, 0.0, 5.0)
	eq(s["delta"].x, -10.0, "the left edge snaps to the parent edge")
	s = EdSnap.snap_gesture(r, "e", Vector2(171, 0), tg, 0.0, 5.0)
	eq(s["delta"].x, 175.0, "a resize snaps the moving edge (to the sibling centre 225)")
	s = EdSnap.snap_gesture(r, "e", Vector2(0, 99), tg, 0.0, 5.0)
	eq(s["delta"].y, 99.0, "an axis the handle does not move stays")
	s = EdSnap.snap_gesture(r, "move", Vector2(30.4, 0), tg, 1.0, 0.0)
	ok(is_equal_approx(s["delta"].x, 30.0), "whole pixels without a grid")


# ---------------------------------------------------------------------------
# Coalescing
# ---------------------------------------------------------------------------

func test_a_gesture_is_one_undo_step() -> void:
	var s := open_session(UXML_ABS, {USS: ".r { color: red; }\n"})
	var original := text(s)
	var node := s.resolve(with_name(s, "box"))
	var style := {"position": _theme("absolute"), "left": _theme("0px"), "top": _theme("0px")}
	var base = EdLayoutCommands.gesture_base(node, style, Rect2(0, 0, 20, 20), Rect2(), Vector2.ZERO)
	for i in range(1, 6):
		var w = EdLayoutCommands.gesture_writes(base, "move", Vector2(i * 3, i))
		var tx = EdLayoutCommands.plan(s, w, func(_n): return style, "Move VisualElement", "gesture:1")
		if not is_tx(tx):
			return
		ok(not (run(s, tx) is EdError), "step %d commits" % i)
	ok(text(s).contains("style=\"left: 15px; top: 5px;\""), "the last step wins: " + text(s))
	eq(s.workspace.history.undo_depth(), 1, "five steps, one undo entry")
	var next = EdLayoutCommands.plan(s, EdLayoutCommands.gesture_writes(base, "move", Vector2(1, 1)), func(_n): return style, "Move", "gesture:2")
	run(s, next)
	eq(s.workspace.history.undo_depth(), 2, "a new gesture is a new step")
	s.workspace.history.undo()
	s.workspace.history.undo()
	eq(text(s), original, "undo restores the exact bytes")
	s.workspace.history.redo()
	ok(text(s).contains("style=\"left: 15px; top: 5px;\""), "redo replays the whole gesture")
