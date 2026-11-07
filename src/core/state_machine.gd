class_name EdStateMachine
extends RefCounted
## The interaction states of an element as a graph (milestone 7).
##
## The nodes are the interaction states: normal, hover, pressed, focused,
## checked and disabled. The edges are the state changes of a user: normal
## and hover, hover and pressed, normal and focused, normal and checked,
## normal and disabled, in both directions.
##
## The rules of a node are the rules of the document's stylesheets that apply
## to the element in that state and name the state in the selector. The
## cascade of godot-uxml decides (explain_style through the `explain` Callable,
## request R5), so this class does not match selectors. `:selected` is the old
## name of `:checked` in Unity, so one node has the rules of both. The rules of
## the normal node apply without a state.
##
## An edge exists when its far state (the one with more pseudo-states) has
## rules. Its `changes` are the properties of those rules, and the properties
## that `transition-property` names (a theme rule can change those), with
## another computed value in the other state. Its `timing` is what godot-uxml
## starts for the change (`preview` Callable, request R26: the real rules,
## without the change and without the history of earlier runs, so also a
## property that only the theme changes through `all`). Edge `kind`:
##
##   "transition"  the change starts a transition
##   "instant"     a property changes, without a transition
##   "none"        the rules give the values of the other state already

## Model: {nodes: [node], edges: [edge]}
## Node: {id, label, states, rules: [rule]}
## Rule: {path, item, selector, line, start, end, declarations: [declaration]}
## Declaration: {property, value, status, line, start, end}
## Edge: {id, from, to, from_states, to_states, far, rules, changes:
##        [{property, from, to}], timing: [{property, delay, duration, easing}],
##        kind, length}
##
## No godot-uxml dependency: `explain`, `preview` and the shorthand table come
## from the caller. `explain.call(property, query)` returns the normalized
## candidates of EdRenderHost.explain(); `preview.call(from_states, to_states)`
## the entries of EdRenderHost.preview_transitions() ({property, delay,
## duration, easing, from, to}).

const NODES := [
	{"id": "normal", "label": "normal", "states": [], "names": []},
	{"id": "hover", "label": "hover", "states": ["hover"], "names": ["hover"]},
	{"id": "active", "label": "pressed", "states": ["hover", "active"], "names": ["active"]},
	{"id": "focus", "label": "focused", "states": ["focus"], "names": ["focus"]},
	{"id": "checked", "label": "checked", "states": ["checked"], "names": ["checked", "selected"]},
	{"id": "disabled", "label": "disabled", "states": ["disabled"], "names": ["disabled"]},
]
## The state changes of a user: [near, far].
const PAIRS := [["normal", "hover"], ["hover", "active"], ["normal", "focus"], ["normal", "checked"], ["normal", "disabled"]]
## Every state, off: a query names each state, so the states that the element
## has now (the state preview, the mouse) do not count.
const OFF := {"hover": false, "active": false, "focus": false, "checked": false, "disabled": false}

static var _pseudo := RegEx.create_from_string(":([a-z-]+)")
static var _token := RegEx.create_from_string("[.#]?-?[A-Za-z_][A-Za-z0-9_-]*")


## The explain_style query of `states`.
static func query(states: Array) -> Dictionary:
	var q := OFF.duplicate()
	for s in states:
		q[s] = true
	return q


static func build(session: EdDocumentSession, node: EdUxmlNode, explain: Callable, shorthands: Dictionary = {}, preview: Callable = Callable()) -> Dictionary:
	var cache := {}
	var ask := func(prop: String, states: Array) -> Array:
		var key := prop + "|" + ",".join(PackedStringArray(states))
		if not cache.has(key):
			cache[key] = explain.call(prop, query(states))
		return cache[key]
	var nodes: Array = []
	var by_id := {}
	for spec in NODES:
		var n := {"id": spec["id"], "label": spec["label"], "states": spec["states"], "rules": _rules_of(session, node, spec, ask)}
		nodes.append(n)
		by_id[spec["id"]] = n
	var edges: Array = []
	for pair in PAIRS:
		var near: Dictionary = by_id[pair[0]]
		var far: Dictionary = by_id[pair[1]]
		if (far["rules"] as Array).is_empty():
			continue
		edges.append(_edge(near, far, far, ask, shorthands, preview))
		edges.append(_edge(far, near, far, ask, shorthands, preview))
	return {"nodes": nodes, "edges": edges}


## The node with `id` in `model`, or {}.
static func node_of(model: Dictionary, id: String) -> Dictionary:
	for n in model.get("nodes", []):
		if n["id"] == id:
			return n
	return {}


## The edge with `id` in `model`, or {}.
static func edge_of(model: Dictionary, id: String) -> Dictionary:
	for e in model.get("edges", []):
		if e["id"] == id:
			return e
	return {}


## The rows of the declaration list of the inspector (EdProvenance rows) for
## `rules`.
static func rows(rules: Array) -> Array:
	var out: Array = []
	for r in rules:
		for d in r["declarations"]:
			out.append({"status": d["status"], "value": d["value"], "declared": d["value"], "property": d["property"],
				"where": "%s:%d  %s" % [String(r["path"]).get_file(), int(d["line"]), r["selector"]],
				"path": r["path"], "line": d["line"], "start": d["start"], "end": d["end"], "select_id": -1})
	return out


## The node of `spec`: the rules whose selector names its state (or, for the
## normal node, no state) and that the cascade applies to the element.
static func _rules_of(session: EdDocumentSession, node: EdUxmlNode, spec: Dictionary, ask: Callable) -> Array:
	var out: Array = []
	var names: Array = spec["names"]
	var tokens := _element_tokens(node)
	for path in session.style_paths():
		var sheet = session.workspace.uss(path)
		if sheet == null:
			continue
		for it in sheet.rules():
			var selector := EdUssSource.strip_comments(String(it["selector_text"]))
			var pseudo := _pseudo_names(selector)
			if names.is_empty():
				# A state rule is not a rule of the normal state.
				if not pseudo.is_empty() and _subject_has_state(selector) and not _has_stateless_part(selector):
					continue
				if not _names_element(selector, tokens):
					continue
			elif not names.any(func(x): return pseudo.has(x)):
				continue
			var rule := _rule(sheet, path, it, spec, ask)
			if not rule.is_empty():
				out.append(rule)
	return out


## The rule row, or {} when the cascade does not apply the rule in the state
## of `spec`. A declaration of a property that the cascade has no candidate
## for (an unsupported property) stays in the list as "dropped".
static func _rule(sheet: Variant, path: String, it: Dictionary, spec: Dictionary, ask: Callable) -> Dictionary:
	var item: int = int(it["item_index"]) if it.has("item_index") else (sheet.items as Array).find(it)
	var decls: Array = []
	var applies := false
	var names: Array = spec["names"]
	var decl_list: Array = it["declarations"]
	for i in decl_list.size():
		var d: Dictionary = decl_list[i]
		var prop := String(d["property"])
		var status := "dropped"
		for e in ask.call(EdProvenance.longhand_of(prop), spec["states"]):
			var o: Dictionary = e.get("origin", {})
			if o.get("kind") != "rule" or o.get("path") != path or int(o.get("item", -1)) != item:
				continue
			# Of a state node: the selector of the rule that names the state.
			var st: Array = o.get("states", [])
			if not names.is_empty() and not names.any(func(x): return st.has(x)):
				continue
			if names.is_empty() and not st.is_empty():
				continue
			applies = true
			if int(o.get("decl_index", -1)) == i:
				status = String(e.get("status", ""))
				break
			status = "overridden"
		decls.append({"property": prop, "value": String(d["raw"]).strip_edges(), "status": status,
			"line": EdStyleTargets.line_of(sheet.text, int(d["start"])), "start": int(d["start"]), "end": int(d["end"])})
	if not applies:
		return {}
	return {"path": path, "item": item, "selector": String(it["selector_text"]).strip_edges(),
		"line": EdStyleTargets.line_of(sheet.text, int(it["start"])), "start": int(it["start"]), "end": int(it["selector_end"]),
		"declarations": decls}


static func _edge(from: Dictionary, to: Dictionary, far: Dictionary, ask: Callable, shorthands: Dictionary, preview: Callable) -> Dictionary:
	var names := _list("transition-property", to["states"], ask)
	var props: Array = []
	for r in far["rules"]:
		for d in r["declarations"]:
			if d["status"] != "dropped":
				props.append(String(d["property"]))
	for nm in names:
		if nm != "all" and nm != "none":
			props.append(String(nm))
	var changes: Array = []
	var seen := {}
	for prop in props:
		var longhands: Array = shorthands.get(prop, [EdProvenance.longhand_of(prop)])
		for lh in longhands:
			if seen.has(lh) or String(lh).begins_with("transition"):
				continue
			seen[lh] = true
			var a := _winner(ask.call(lh, from["states"]))
			var b := _winner(ask.call(lh, to["states"]))
			if a != b:
				changes.append({"property": lh, "from": a, "to": b})
	var timing: Array = []
	var length := 0.0
	var tracks: Array = preview.call(from["states"], to["states"]) if preview.is_valid() else []
	for t in tracks:
		var prop := String(t["property"])
		var delay := float(t.get("delay", 0.0))
		var dur := float(t.get("duration", 0.0))
		timing.append({"property": prop, "delay": delay, "duration": dur, "easing": String(t.get("easing", ""))})
		length = maxf(length, delay + dur)
		# A property that only the theme changes is a change too.
		if not seen.has(prop):
			seen[prop] = true
			changes.append({"property": prop, "from": str(t.get("from", "")), "to": str(t.get("to", ""))})
	timing.sort_custom(func(x, y): return String(x["property"]) < String(y["property"]))
	var kind := "transition" if not timing.is_empty() else ("instant" if not changes.is_empty() else "none")
	return {"id": "%s>%s" % [from["id"], to["id"]], "from": from["id"], "to": to["id"], "from_label": from["label"], "to_label": to["label"],
		"from_states": from["states"], "to_states": to["states"], "far": far["id"], "rules": far["rules"],
		"changes": changes, "timing": timing, "kind": kind, "length": length}


static func _winner(entries: Array) -> String:
	return "" if entries.is_empty() else str(entries[0].get("value", ""))


static func _list(longhand: String, states: Array, ask: Callable) -> Array:
	return EdTransitionValues.list_or_initial(longhand, _winner(ask.call(longhand, states)))


static func _pseudo_names(selector: String) -> Array:
	var out: Array = []
	for m in _pseudo.search_all(selector):
		out.append(m.get_string(1))
	return out


## The last compound of each selector of the list has a pseudo-state: the
## rule styles a state of the subject.
static func _subject_has_state(selector: String) -> bool:
	for part in selector.split(","):
		var compounds := String(part).strip_edges().replace(">", " ").split(" ", false)
		if not compounds.is_empty() and String(compounds[-1]).contains(":"):
			return true
	return false


## One selector of the list has no pseudo-state on its subject
## (`.a, .a:hover`): the rule is also a rule of the normal state.
static func _has_stateless_part(selector: String) -> bool:
	for part in selector.split(","):
		var compounds := String(part).strip_edges().replace(">", " ").split(" ", false)
		if not compounds.is_empty() and not String(compounds[-1]).contains(":"):
			return true
	return false


## What a selector of the element can name: its type, `#name` and `.class`.
static func _element_tokens(node: EdUxmlNode) -> Dictionary:
	var out := {node.local: true, "*": true}
	var nm = node.get_attribute("name")
	if nm != null:
		out["#" + String(nm)] = true
	var cls = node.get_attribute("class")
	if cls != null:
		for c in String(cls).split(" ", false):
			out["." + c] = true
	return out


## The selector names the element (a cheap filter before the cascade asks).
static func _names_element(selector: String, tokens: Dictionary) -> bool:
	if selector.contains("*"):
		return true
	for m in _token.search_all(selector):
		if tokens.has(m.get_string()):
			return true
	return false
