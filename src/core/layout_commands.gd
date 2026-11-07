class_name EdLayoutCommands
extends RefCounted
## Layout writes from the canvas (move, resize, nudge) as style patches.
##
## Ported from main:src/core/commands/layoutCommands.ts and
## layoutStyleWritePlanner.ts. Each written property goes where its winning
## value comes from (docs/adr/0004-style-write-targets.md):
##
##   winner from an authored USS rule   -> that rule's declaration
##   winner from the inline style       -> that inline declaration
##   theme, default or nothing authored -> a new inline declaration
##
## A rule winner from a pseudo-state rule (:hover) or a winner that is a
## shorthand declared after a longhand of the same rule is refused: a write
## there would not change the computed value.
##
## Computed style comes from the renderer through `style_of`, a
## Callable(node: EdUxmlNode) -> Dictionary of
##   property -> {value: String, origin: {kind, path, item, decl_index, states}}
## with origin kind "rule" (path: a workspace stylesheet), "theme",
## "inline", "inherited" or "default" (EdRenderHost.style_facts()).
##
## Values are written in px. A gesture (drag, a run of arrow keys) passes
## one coalesce key; the history merges its transactions into one step.
##
## A gesture can name the target of a property instead (`targets`, the
## write-target choice of the user, ADR 0004): {kind: "rule", path, item},
## {kind: "inline"} or {kind: "new-rule", path, selector}. A new rule that
## several properties of one plan name is inserted once; the later
## properties go into it.

const MOVE_PROPS := ["left", "top", "margin-left", "margin-top"]


## `writes`: [{locator, property, value: float}]. `targets`: property ->
## a target for the primary element (`primary`, a locator) that replaces
## the target of the winner.
static func plan(session: EdDocumentSession, writes: Array, style_of: Callable, tx_label: String, coalesce_key: String = "",
		targets: Dictionary = {}, primary: Variant = null) -> Variant:
	if writes.is_empty():
		return EdError.make("invalid-selection", "A layout edit needs at least one element.")
	var planned: Array = []
	var seen := {}
	for w in writes:
		var node := session.resolve(w["locator"])
		if node == null:
			return EdError.make("unresolved-locator", "A layout target no longer resolves uniquely.")
		if not is_finite(float(w["value"])):
			return EdError.make("invalid-value", "Layout values must be finite numbers.")
		var target = null
		if targets.has(w["property"]) and (primary == null or session.resolve(primary) == node):
			target = targets[w["property"]]
		else:
			target = choose_target(node, w["property"], style_of.call(node))
		if target is EdError:
			return target
		var value := format_px(float(w["value"]))
		var key := JSON.stringify([target["kind"], target.get("path", ""), target.get("item", -1), w["property"],
			"" if target["kind"] == "rule" else str(node.open_start), target.get("selector", "")])
		if seen.has(key):
			if seen[key] != value:
				return EdError.make("ambiguous-source", "Selected elements need different %s values through one shared rule." % w["property"])
			continue
		seen[key] = value
		planned.append({"locator": EdLocator.create(node), "property": w["property"], "value": value, "target": target})
	var steps: Array = []
	var created := {}
	for p in planned:
		steps.append(_step.bind(p, created))
	var tx = EdStepComposer.compose(session, "layout:write", tx_label, steps)
	if tx is EdTransaction:
		tx.coalesce_key = coalesce_key
		tx.selection_after = null
	return tx


## `created`: "path|selector" -> the item index of a new rule that an
## earlier step of the plan inserted.
static func _step(shadow: EdDocumentSession, p: Dictionary, created: Dictionary) -> Variant:
	var t: Dictionary = p["target"]
	var prop: String = p["property"]
	if t["kind"] == "new-rule":
		var key := "%s|%s" % [t["path"], t["selector"]]
		if created.has(key):
			var nt = EdUssCommands.rule_target(shadow.workspace, t["path"], created[key], prop)
			if nt is EdError:
				return nt
			return EdUssCommands.set_declaration(shadow.workspace, nt, p["value"])
		var sheet := shadow.workspace.uss(t["path"])
		if sheet == null:
			return EdError.make("stale-target", "Stylesheet %s is no longer open." % t["path"])
		created[key] = sheet.items.size()
		return EdUssCommands.insert_rule(shadow.workspace, EdUssCommands.new_rule_target(shadow.workspace, t["path"], t["selector"], prop), p["value"])
	if t["kind"] == "rule":
		var rt = EdUssCommands.rule_target(shadow.workspace, t["path"], t["item"], prop)
		if rt is EdError:
			return rt
		var ok = _check_index(rt["declaration_index"], int(t.get("decl_index", -1)), prop)
		if ok is EdError:
			return ok
		return EdUssCommands.set_declaration(shadow.workspace, rt, p["value"])
	var node := shadow.resolve(p["locator"])
	if node == null:
		return EdError.make("unresolved-locator", "A layout target no longer resolves uniquely.")
	var it = EdUssCommands.inline_target(shadow, EdLocator.create(node), prop)
	if it is EdError:
		return it
	if int(t.get("decl_index", -1)) >= 0:
		var ok = _check_index(it["declaration_index"], int(t["decl_index"]), prop)
		if ok is EdError:
			return ok
	return EdUssCommands.set_inline_style(shadow, it, p["value"])


## The declaration a write edits (`found`, -1 for a new one at the end)
## must be the winner or come after it; an earlier one is overridden.
static func _check_index(found: int, winner: int, prop: String) -> Variant:
	if found >= 0 and winner >= 0 and found < winner:
		return EdError.make("ambiguous-source", "A later shorthand overrides %s in its block; edit the shorthand in the source view." % prop)
	return true


## The write target of `property` on `node`: {kind: "inline", decl_index}
## or {kind: "rule", path, item, decl_index}, or an EdError.
static func choose_target(node: EdUxmlNode, property: String, style: Dictionary) -> Variant:
	var e = style.get(property)
	var origin: Dictionary = {} if typeof(e) != TYPE_DICTIONARY else e.get("origin", {})
	return _target_from(origin, property, node)


static func _target_from(origin: Dictionary, property: String, node: EdUxmlNode) -> Variant:
	match String(origin.get("kind", "")):
		"rule":
			if not (origin.get("states", []) as Array).is_empty():
				return EdError.make("ambiguous-source", "%s of %s comes from a :%s rule; edit it in the inspector." % [property, node.local, ":".join(origin["states"])])
			return {"kind": "rule", "path": origin["path"], "item": int(origin["item"]), "decl_index": int(origin.get("decl_index", -1))}
		"inline":
			return {"kind": "inline", "decl_index": int(origin.get("decl_index", -1))}
		"inherited":
			var inner: Dictionary = origin.get("origin", {})
			if inner.get("kind") == "rule" or inner.get("kind") == "inline":
				return EdError.make("ambiguous-source", "%s of %s is inherited from an authored value; set it on the element in the inspector." % [property, node.local])
	return {"kind": "inline", "decl_index": -1}


## The layout target of a write-target choice (EdStyleTargets): the
## location of the rule, the inline style or the new rule. A plan finds
## the declaration again in the current text, so the target stays valid
## through the steps of a gesture.
static func target_of_choice(choice: Dictionary) -> Dictionary:
	match String(choice.get("kind", "")):
		"rule":
			var t: Dictionary = choice["target"]
			return {"kind": "rule", "path": t["path"], "item": int(t["item_index"]), "decl_index": -1}
		"new-rule":
			return {"kind": "new-rule", "path": choice["path"], "selector": choice["target"]["selector"]}
	return {"kind": "inline", "decl_index": -1}


static func format_px(v: float) -> String:
	var r := snappedf(v, 0.001)
	if r == 0.0:
		r = 0.0
	if is_equal_approx(r, roundf(r)):
		return "%dpx" % int(roundf(r))
	return "%spx" % String.num(r, 3)


## "12px", "12", "-3.5px" -> float; anything else (auto, %, keywords) -> null.
static func px(v: Variant) -> Variant:
	if typeof(v) == TYPE_DICTIONARY:
		v = v.get("value")
	if v == null:
		return null
	var s := String(v).strip_edges()
	if s.ends_with("px"):
		s = s.substr(0, s.length() - 2)
	if s.is_valid_float():
		return s.to_float()
	return null


# ---------------------------------------------------------------------------
# Gestures
# ---------------------------------------------------------------------------

## The start state of a move or resize of `node`:
## {locator, position: "absolute"|"relative", rect, left, top,
##  margin_left, margin_top} (numbers in document px), or an EdError.
## `rect` is the border box; `parent_rect` and `parent_border` (left and top
## border widths) place an absolute element whose left/top are not px.
static func gesture_base(node: EdUxmlNode, style: Dictionary, rect: Rect2, parent_rect: Rect2, parent_border: Vector2) -> Variant:
	if node == null or node.parent == null:
		return EdError.make("illegal-root", "The UXML root element has no layout of its own.")
	var position := "absolute" if String(style.get("position", {}).get("value", "")) == "absolute" else "relative"
	var ml = px(style.get("margin-left"))
	var mt = px(style.get("margin-top"))
	if style.get("margin-left") == null:
		ml = 0.0
	if style.get("margin-top") == null:
		mt = 0.0
	var left = px(style.get("left"))
	var top = px(style.get("top"))
	if left == null and ml != null:
		left = rect.position.x - parent_rect.position.x - parent_border.x - ml
	if top == null and mt != null:
		top = rect.position.y - parent_rect.position.y - parent_border.y - mt
	return {"locator": EdLocator.create(node), "position": position, "rect": rect,
		"left": left, "top": top, "margin_left": ml, "margin_top": mt}


## The property writes for a gesture: `handle` is "move" or a resize
## handle ("n", "s", "e", "w", "ne", "nw", "se", "sw"); `delta` is the
## pointer travel in document px. `keep_ratio` keeps the aspect ratio for
## corner handles. Returns [{locator, property, value}] or an EdError.
static func gesture_writes(base: Dictionary, handle: String, delta: Vector2, keep_ratio: bool = false) -> Variant:
	var abs_pos: bool = base["position"] == "absolute"
	var hx := "left" if abs_pos else "margin-left"
	var vy := "top" if abs_pos else "margin-top"
	var bx = base["left"] if abs_pos else base["margin_left"]
	var by = base["top"] if abs_pos else base["margin_top"]
	var r: Rect2 = base["rect"]
	var out: Array = []
	var loc: Dictionary = base["locator"]
	if handle == "move":
		if bx == null or by == null:
			return EdError.make("ambiguous-source", "%s and %s are not pixel values; set them in the inspector first." % [hx, vy])
		out.append({"locator": loc, "property": hx, "value": roundf(bx + delta.x)})
		out.append({"locator": loc, "property": vy, "value": roundf(by + delta.y)})
		return out
	var dx := delta.x
	var dy := delta.y
	var west := handle.contains("w")
	var east := handle.contains("e")
	var north := handle.contains("n")
	var south := handle.contains("s")
	var w := r.size.x + (dx if east else (-dx if west else 0.0))
	var h := r.size.y + (dy if south else (-dy if north else 0.0))
	if keep_ratio and (west or east) and (north or south) and r.size.x > 0 and r.size.y > 0:
		var ratio := r.size.x / r.size.y
		if absf(w - r.size.x) / r.size.x >= absf(h - r.size.y) / r.size.y:
			h = w / ratio
		else:
			w = h * ratio
	w = maxf(0.0, roundf(w))
	h = maxf(0.0, roundf(h))
	if west or east:
		out.append({"locator": loc, "property": "width", "value": w})
	if north or south:
		out.append({"locator": loc, "property": "height", "value": h})
	if west:
		if bx == null:
			return EdError.make("ambiguous-source", "%s is not a pixel value; set it in the inspector first." % hx)
		out.append({"locator": loc, "property": hx, "value": roundf(bx + r.size.x - w)})
	if north:
		if by == null:
			return EdError.make("ambiguous-source", "%s is not a pixel value; set it in the inspector first." % vy)
		out.append({"locator": loc, "property": vy, "value": roundf(by + r.size.y - h)})
	return out


## The rectangle a gesture gives (for snapping and guides).
static func gesture_rect(r: Rect2, handle: String, delta: Vector2) -> Rect2:
	if handle == "move":
		return Rect2(r.position + delta, r.size)
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	if handle.contains("w"):
		x0 += delta.x
	if handle.contains("e"):
		x1 += delta.x
	if handle.contains("n"):
		y0 += delta.y
	if handle.contains("s"):
		y1 += delta.y
	return Rect2(x0, y0, x1 - x0, y1 - y0)
