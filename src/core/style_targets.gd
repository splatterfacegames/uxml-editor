class_name EdStyleTargets
extends RefCounted
## The write targets of one style property of one element
## (docs/adr/0004-style-write-targets.md), from the cascade candidates of
## godot-uxml (explain_style, request R5).
##
## Valid targets, in this order:
##
## 1. every authored rule of a project stylesheet that applies to the
##    element and gives the property, when its pseudo-states equal the
##    requested states (the winner first, then the rules it overrides);
## 2. the inline `style` attribute, when no state is requested and the
##    element has at most one `style` attribute;
## 3. a new rule in each stylesheet of the document, for the selector
##    `#name` (a unique name) and `.class` (each class), with the states.
##
## Theme, inherited and default candidates are not targets: a theme value
## has no authored destination. A rule whose declaration of the longhand
## comes before the shorthand that wins is not a target either (the
## shorthand would override the write).
##
## Each choice holds a target of EdUssCommands. A target freezes the
## source it was made from; a commit after a change of that source is
## refused with "stale-target", never redirected.
##
## Choice: {id, kind, label, title, target, winner: bool, path, line}

const STATES := ["hover", "active", "inactive", "focus", "checked", "selected", "disabled", "enabled", "root"]


## The write targets of `property` on `node` for candidates `entries`
## (normalized explain entries: {origin: {kind, path, item, decl_index,
## states}, property, status, winner}) and the requested pseudo-states.
static func choices(session: EdDocumentSession, node: EdUxmlNode, property: String, entries: Array, states: Array = []) -> Array:
	var ws := session.workspace
	var want := _sorted(states)
	var out: Array = []
	var seen := {}
	for e in entries:
		var o: Dictionary = e.get("origin", {})
		if o.get("kind") != "rule":
			continue
		if _sorted(o.get("states", [])) != want:
			continue
		var path := String(o["path"])
		var key := "rule:%s:%d" % [path, int(o["item"])]
		if seen.has(key):
			continue
		var t = EdUssCommands.rule_target(ws, path, int(o["item"]), property)
		if t is EdError:
			continue
		# The longhand before the winning shorthand of the same block would
		# be overridden by the shorthand.
		if String(e.get("property", property)) != property and t["declaration_index"] >= 0 and t["declaration_index"] < int(o["decl_index"]):
			continue
		seen[key] = true
		var sheet := ws.uss(path)
		var it = sheet.item(int(o["item"]))
		var line := line_of(sheet.text, int(it["start"]))
		var label := "%s · %s" % [path.get_file(), String(it["selector_text"])]
		if e.get("winner", false):
			label += "  (wins)"
		elif String(e.get("status", "")) == "overridden":
			label += "  (overridden)"
		out.append({"id": key, "kind": "rule", "label": label, "title": "%s:%d" % [path, line], "target": t,
			"winner": bool(e.get("winner", false)), "path": path, "line": line})
	if want.is_empty() and node.attributes_named("style").size() <= 1:
		var it = EdUssCommands.inline_target(session, EdLocator.create(node), property)
		if not it is EdError:
			var won := false
			for e in entries:
				if e.get("winner", false) and e.get("origin", {}).get("kind") == "inline":
					won = true
			out.append({"id": "inline", "kind": "inline", "label": "Inline style" + ("  (wins)" if won else ""), "title": session.entry_path,
				"target": it, "winner": won, "path": session.entry_path, "line": line_of(session.source(), node.open_start)})
	for sel in selectors_for(session, node, want):
		for path in session.style_paths():
			if not ws.has(path) or not ws.buffer(path).exact:
				continue
			var t := EdUssCommands.new_rule_target(ws, path, sel, property)
			out.append({"id": "new:%s:%s" % [path, sel], "kind": "new-rule", "label": "New rule %s in %s" % [sel, path.get_file()],
				"title": path, "target": t, "winner": false, "path": path, "line": -1})
	return out


## The selectors of a new rule for `node`: `#name` when the name is a
## unique identifier, then `.class` for each class; with the states.
static func selectors_for(session: EdDocumentSession, node: EdUxmlNode, states: Array) -> Array:
	var suffix := ""
	for s in _sorted(states):
		suffix += ":" + String(s)
	var out: Array = []
	var nm = node.get_attribute("name")
	if nm != null and _is_ident(String(nm)):
		var count := 0
		for n in session.root().walk():
			if n.get_attribute("name") == nm:
				count += 1
		if count == 1:
			out.append("#%s%s" % [nm, suffix])
	var cls = node.get_attribute("class")
	if cls != null:
		for c in String(cls).split(" ", false):
			if _is_ident(c) and not out.has(".%s%s" % [c, suffix]):
				out.append(".%s%s" % [c, suffix])
	return out


## Write `value` to the target of `choice`. An empty value removes the
## declaration of a rule or inline target. Returns a transaction or an
## EdError (a stale target, an invalid value, nothing to remove).
static func commit(session: EdDocumentSession, choice: Dictionary, value: String) -> Variant:
	var t: Dictionary = choice["target"]
	var v := value.strip_edges()
	if not v.is_empty():
		var bad = EdStyleTypes.check(t["property"], v)
		if bad is EdError:
			return bad
	match String(t["kind"]):
		"inline":
			if v.is_empty():
				if t["declaration"] == null:
					return EdError.make("invalid-target", "%s has no inline declaration to remove." % t["property"])
				return EdUssCommands.remove_inline_style(session, t)
			return EdUssCommands.set_inline_style(session, t, v)
		"rule":
			if v.is_empty():
				return EdUssCommands.remove_declaration(session.workspace, t)
			return EdUssCommands.set_declaration(session.workspace, t, v)
		"new-rule":
			if v.is_empty():
				return EdError.make("invalid-value", "A new rule needs a value.")
			return EdUssCommands.insert_rule(session.workspace, t, v)
	return EdError.make("invalid-target", "Unknown style target.")


## The 1-based line of offset `at` in `text`.
static func line_of(text: String, at: int) -> int:
	if at < 0:
		return -1
	return text.substr(0, at).count("\n") + 1


static func _sorted(states: Variant) -> Array:
	var a: Array = (states as Array).duplicate() if states is Array else Array(states)
	a.sort()
	return a


static func _is_ident(s: String) -> bool:
	return RegEx.create_from_string("^-?[A-Za-z_][A-Za-z0-9_-]*$").search(s) != null
