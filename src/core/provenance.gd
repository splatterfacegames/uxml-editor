class_name EdProvenance
extends RefCounted
## What the provenance inspector shows: every candidate declaration of a
## property with its status, its origin and its place in the source, and
## the rules of the document's stylesheets that name a class.
##
## The candidates come from godot-uxml explain_style (request R5) through
## EdRenderHost.explain(), with normalized origins: {kind: "rule", path,
## item, decl_index, states}, {kind: "inline", decl_index}, {kind:
## "theme", file, item}, {kind: "inherited", origin, from_id}, {kind:
## "default"}.
##
## Row: {status, value, declared, property, where, path, line, start, end,
## select_id}. `path`/`start`/`end` name the declaration span for the jump
## to source ("" and -1 when the candidate has no authored source);
## `select_id` is the editor node to select for an inherited value (-1).


static func rows(session: EdDocumentSession, node: EdUxmlNode, entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		out.append(row(session, node, e))
	return out


static func row(session: EdDocumentSession, node: EdUxmlNode, e: Dictionary) -> Dictionary:
	var ws := session.workspace
	var o: Dictionary = e.get("origin", {})
	var r := {"status": String(e.get("status", "")), "value": _text(e.get("value")), "declared": _text(e.get("declared")),
		"property": String(e.get("property", "")), "where": "", "path": "", "line": -1, "start": -1, "end": -1, "select_id": -1}
	match String(o.get("kind", "")):
		"rule":
			var path := String(o["path"])
			var sheet := ws.uss(path)
			var it = sheet.item(int(o["item"])) if sheet != null else null
			if it == null or it["kind"] != "rule":
				r["where"] = path.get_file()
				return r
			var di := int(o.get("decl_index", -1))
			var decls: Array = it["declarations"]
			var span := Vector2i(int(it["start"]), int(it["selector_end"]))
			if di >= 0 and di < decls.size():
				span = Vector2i(int(decls[di]["start"]), int(decls[di]["end"]))
			r["path"] = path
			r["start"] = span.x
			r["end"] = span.y
			r["line"] = EdStyleTargets.line_of(sheet.text, span.x)
			r["where"] = "%s:%d  %s" % [path.get_file(), r["line"], String(it["selector_text"])]
		"inline":
			var styles := node.attributes_named("style")
			r["where"] = "inline style"
			if styles.size() == 1:
				var a: Dictionary = styles[0]
				var src := session.source()
				var decls := EdUssSource.parse_declarations(src, a["value_start"], a["value_end"])
				var di := int(o.get("decl_index", -1))
				r["path"] = session.entry_path
				if di >= 0 and di < decls.size():
					r["start"] = int(decls[di]["start"])
					r["end"] = int(decls[di]["end"])
				else:
					r["start"] = int(a["start"])
					r["end"] = int(a["end"])
				r["line"] = EdStyleTargets.line_of(src, r["start"])
				r["where"] = "%s:%d  inline style" % [session.entry_path.get_file(), r["line"]]
		"theme":
			r["where"] = "theme  %s" % String(o.get("file", "")).get_file()
		"inherited":
			var from := int(o.get("from_id", -1))
			r["select_id"] = from
			var t := session.tree()
			var label := "the parent"
			if from >= 0 and t != null and from < t.nodes.size():
				var p: EdUxmlNode = t.nodes[from]
				label = p.local + ("" if p.get_attribute("name") == null else " #" + String(p.get_attribute("name")))
			r["where"] = "inherited from " + label
		_:
			r["where"] = "initial value"
	return r


## One line of text for row `r`: the status, the origin and the value
## (the origin first: the inspector is narrow). `queried`: the longhand of
## the query; a declaration of another property (a shorthand) shows its
## name.
static func line(r: Dictionary, queried: String = "") -> String:
	var v: String = r["declared"] if not String(r["declared"]).is_empty() else r["value"]
	var prop: String = "" if r["property"].is_empty() or r["property"] == queried else r["property"] + ": "
	return "%s  %s  =  %s%s" % [r["status"], r["where"], prop, v]


static func _text(v: Variant) -> String:
	return "" if v == null else str(v)


# ---------------------------------------------------------------------------
# Classes
# ---------------------------------------------------------------------------

## The rules of the stylesheets `paths` whose selector names class `cls`:
## [{path, item, selector, line, start, end, properties: [declared
## property names]}].
static func class_rules(ws: EdWorkspace, paths: Array, cls: String) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("\\.%s(?![A-Za-z0-9_-])" % _escape(cls))
	for path in paths:
		var sheet := ws.uss(path)
		if sheet == null:
			continue
		for it in sheet.rules():
			var sel := String(it["selector_text"])
			if re.search(EdUssSource.strip_comments(sel)) == null:
				continue
			out.append({"path": path, "item": int(it["item_index"]) if it.has("item_index") else sheet.items.find(it),
				"selector": sel, "line": EdStyleTargets.line_of(sheet.text, int(it["start"])),
				"start": int(it["start"]), "end": int(it["selector_end"]),
				"properties": (it["declarations"] as Array).map(func(d): return String(d["property"]))})
	return out


static func _escape(s: String) -> String:
	var out := ""
	for ch in s:
		if "\\^$.|?*+()[]{}".contains(ch):
			out += "\\"
		out += ch
	return out


## A longhand that the declaration `property` sets, for an explain_style
## query (a shorthand gives its first longhand).
static func longhand_of(property: String) -> String:
	match property:
		"margin", "padding":
			return property + "-top"
		"border-width":
			return "border-top-width"
		"border-color":
			return "border-top-color"
		"border-radius":
			return "border-top-left-radius"
		"flex":
			return "flex-grow"
		"transition":
			return "transition-property"
		"background-position":
			return "background-position-x"
		"-unity-text-outline":
			return "-unity-text-outline-width"
		"-unity-background-scale-mode":
			return "background-size"
		"gap":
			return "row-gap"
	return property


# ---------------------------------------------------------------------------
# Class edits (byte-accurate: only the `class` value changes)
# ---------------------------------------------------------------------------

static func add_class(session: EdDocumentSession, loc: Dictionary, cls: String) -> Variant:
	var c := cls.strip_edges()
	if not EdStyleTargets._is_ident(c):
		return EdError.make("invalid-value", "\"%s\" is not a class name." % cls)
	var n := session.resolve(loc)
	if n == null:
		return EdError.make("stale-target", "The element no longer resolves.")
	if n.attributes_named("class").size() > 1:
		return EdError.make("ambiguous-source", "The class attribute occurs more than once on %s." % n.name)
	var cur = n.get_attribute("class")
	var v := "" if cur == null else String(cur)
	if v.split(" ", false).has(c):
		return EdError.make("invalid-value", "%s already has the class %s." % [n.local, c])
	var nv := c if v.strip_edges().is_empty() else (v + ("" if v.ends_with(" ") else " ") + c)
	var tx = EdUxmlCommands.set_attribute(session, loc, "class", nv)
	if tx is EdTransaction:
		tx.label = "Add class .%s" % c
	return tx


static func remove_class(session: EdDocumentSession, loc: Dictionary, cls: String) -> Variant:
	var n := session.resolve(loc)
	if n == null:
		return EdError.make("stale-target", "The element no longer resolves.")
	if n.attributes_named("class").size() > 1:
		return EdError.make("ambiguous-source", "The class attribute occurs more than once on %s." % n.name)
	var cur = n.get_attribute("class")
	if cur == null or not String(cur).split(" ", false).has(cls):
		return EdError.make("invalid-target", "%s has no class %s." % [n.local, cls])
	var v := String(cur)
	var nv := _without_token(v, cls)
	var tx
	if nv.strip_edges().is_empty():
		tx = EdUxmlCommands.remove_attribute(session, loc, "class")
	else:
		tx = EdUxmlCommands.set_attribute(session, loc, "class", nv)
	if tx is EdTransaction:
		tx.label = "Remove class .%s" % cls
	return tx


## `v` without the whitespace-separated token `tok`: the token and the
## white space after it (before it, for the last token) go; the other
## bytes stay.
static func _without_token(v: String, tok: String) -> String:
	var i := 0
	while i < v.length():
		while i < v.length() and v[i] == " ":
			i += 1
		var j := i
		while j < v.length() and v[j] != " ":
			j += 1
		if j > i and v.substr(i, j - i) == tok:
			var k := j
			while k < v.length() and v[k] == " ":
				k += 1
			if k < v.length():
				return v.substr(0, i) + v.substr(k)
			var b := i
			while b > 0 and v[b - 1] == " ":
				b -= 1
			return v.substr(0, b) + v.substr(j)
		i = j
	return v
