class_name EdClipboard
extends RefCounted
## Copy, paste and duplicate of element source.
##
## Ported from main:src/core/commands/ClipboardService.ts and
## clipboardPayload.ts. A copy takes the exact source of each element (its
## comments, attribute order, quotes and entities) and the namespace
## declarations in scope at it. A paste inserts the fragments as one patch:
## a prefix that the destination does not bind gets its declaration on the
## pasted element, a prefix bound to another URI refuses the paste, and an
## authored `name` that already exists in the document gets a `-copy`
## suffix.
##
## Payload (a Dictionary, JSON-safe):
##   {version: 1, source_path, fragments: [{source, namespaces: [{name, value}]}]}
## The plain text form is the fragment sources joined by "\n".

const VERSION := 1
const _WRAPPER := "uxml-editor-fragment"

## The last payload that copy_to_system() wrote. A paste whose system text
## equals its plain text uses it (with the namespace metadata).
static var last_payload: Dictionary = {}


static func copy(session: EdDocumentSession, locs: Array) -> Variant:
	if locs.is_empty():
		return EdError.make("invalid-selection", "Copy requires at least one element.")
	var src := session.source()
	var nodes: Array = []
	for l in locs:
		var n := session.resolve(l)
		if n == null:
			return EdError.make("unresolved-locator", "A copied element does not resolve uniquely in this session.")
		if n.parent == null:
			return EdError.make("illegal-root", "The UXML root element cannot be copied.")
		if nodes.has(n):
			return EdError.make("invalid-selection", "Copied elements must be distinct.")
		nodes.append(n)
	nodes.sort_custom(func(a, b): return a.open_start < b.open_start)
	var fragments: Array = []
	var prev_end := -1
	for n in nodes:
		var end = EdUxmlCommands.outer_end(src, n)
		if end is EdError:
			return end
		if n.open_start < prev_end:
			return EdError.make("invalid-selection", "Copied elements must not contain each other.")
		prev_end = end
		fragments.append({"source": src.substr(n.open_start, end - n.open_start), "namespaces": _namespace_metadata(n)})
	return {"version": VERSION, "source_path": session.entry_path, "fragments": fragments}


static func plain_text(payload: Dictionary) -> String:
	return "\n".join(payload["fragments"].map(func(f): return f["source"]))


## Put `payload` on the system clipboard (plain text) and remember it.
static func copy_to_system(payload: Dictionary) -> void:
	last_payload = payload.duplicate(true)
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(plain_text(payload))


## The text of the system clipboard ("" without a clipboard, as in a
## headless run).
static func system_text() -> String:
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		return DisplayServer.clipboard_get()
	return ""


## The payload for a paste of system clipboard `text`: the remembered
## payload when the text is its plain form; otherwise the elements of the
## text, without namespace metadata (the destination must bind their
## prefixes). Returns an EdError when the text is not element source.
static func payload_from_text(text: String) -> Variant:
	# The Windows clipboard may turn LF into CRLF: compare without CR.
	if not last_payload.is_empty() and plain_text(last_payload).replace("\r", "") == text.replace("\r", ""):
		return last_payload.duplicate(true)
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return EdError.make("invalid-fragment", "The clipboard holds no UXML elements.")
	var wrapper := "<%s>%s</%s>" % [_WRAPPER, trimmed, _WRAPPER]
	var parsed := EdUxmlSource.parse(wrapper)
	if parsed.root == null or not parsed.problems.is_empty() or parsed.root.children.is_empty():
		return EdError.make("invalid-fragment", "The clipboard text is not UXML element source.")
	var fragments: Array = []
	var cursor: int = parsed.root.inner_start
	for c in parsed.root.children:
		if not EdXml.is_only_space(wrapper.substr(cursor, c.open_start - cursor)) and c.open_start != cursor:
			return EdError.make("invalid-fragment", "The clipboard text has content between its elements.")
		var end: int = c.outer_end()
		fragments.append({"source": wrapper.substr(c.open_start, end - c.open_start), "namespaces": []})
		cursor = end
	if not EdXml.is_only_space(wrapper.substr(cursor, parsed.root.inner_end - cursor)) and cursor != parsed.root.inner_end:
		return EdError.make("invalid-fragment", "The clipboard text has content after its elements.")
	return {"version": VERSION, "source_path": "", "fragments": fragments}


static func is_valid_payload(p: Variant) -> bool:
	if typeof(p) != TYPE_DICTIONARY or p.get("version") != VERSION or typeof(p.get("fragments")) != TYPE_ARRAY:
		return false
	if (p["fragments"] as Array).is_empty():
		return false
	for f in p["fragments"]:
		if typeof(f) != TYPE_DICTIONARY or typeof(f.get("source")) != TYPE_STRING or typeof(f.get("namespaces")) != TYPE_ARRAY:
			return false
		if String(f["source"]).is_empty() or String(f["source"]).strip_edges() != f["source"]:
			return false
		for ns in f["namespaces"]:
			if typeof(ns) != TYPE_DICTIONARY or typeof(ns.get("name")) != TYPE_STRING or typeof(ns.get("value")) != TYPE_STRING:
				return false
			if ns["name"] != "xmlns" and not (String(ns["name"]).begins_with("xmlns:") and EdXml.is_nc_name(String(ns["name"]).substr(6))):
				return false
	return true


## Insert the fragments of `payload` into `parent_loc` at child `index`.
static func paste(session: EdDocumentSession, parent_loc: Dictionary, index: int, payload: Variant) -> Variant:
	if not is_valid_payload(payload):
		return EdError.make("invalid-fragment", "The clipboard data is malformed or has an unsupported version.")
	var parent := session.resolve(parent_loc)
	if parent == null or index < 0 or index > parent.children.size():
		return EdError.make("invalid-index", "Paste requires one current parent and a valid child index.")
	var dest_b = EdUxmlNamespaces.bindings_at(parent)
	if dest_b is EdError:
		return dest_b
	var occupied := {}
	for n in session.root().walk():
		for a in n.attributes_named("name"):
			occupied[a["value"]] = true
	var transformed: Array = []
	for f in payload["fragments"]:
		var t = _transform(f, occupied, dest_b)
		if t is EdError:
			return t
		transformed.append(t)
	var cur_parent := EdLocator.create(parent)
	for t in transformed:
		var check = EdUxmlCommands.insert_element(session, cur_parent, index, t["source"])
		if check is EdError:
			return check
	var first: EdTransaction = EdUxmlCommands.insert_element(session, cur_parent, index, transformed[0]["source"])
	var patches := first.patches(session.entry_path)
	if patches.size() != 1:
		return EdError.make("ambiguous-source", "The paste destination has no single safe insertion boundary.")
	var combined = _combine(patches[0], transformed.map(func(t): return t["source"]))
	if combined is EdError:
		return combined
	var lbl := "Paste element" if transformed.size() == 1 else "Paste %d elements" % transformed.size()
	var tx := EdTransaction.make("uxml:paste", lbl, session.entry_path, [combined])
	tx.document = session.entry_path
	var path: Array = parent.child_path()
	var ancestors: Array = parent.ancestor_tags()
	ancestors.append(parent.name)
	var sel: Array = []
	for k in transformed.size():
		var t: Dictionary = transformed[k]
		var loc := {"qualified_tag": t["tag"], "child_path": path + [index + k],
			"ancestor_tags": ancestors, "attribute_hints": t["hints"]}
		if t.has("authored_name"):
			loc["authored_name"] = t["authored_name"]
		sel.append(loc)
	tx.selection_after = sel
	return tx


## Copy `locs` and paste the copy after the last of them (same parent).
static func duplicate_elements(session: EdDocumentSession, locs: Array) -> Variant:
	var payload = copy(session, locs)
	if payload is EdError:
		return payload
	var parent: EdUxmlNode = null
	var last := -1
	for l in locs:
		var n := session.resolve(l)
		if parent == null:
			parent = n.parent
		elif n.parent != parent:
			return EdError.make("invalid-selection", "Duplication requires sibling elements with one parent.")
		last = maxi(last, n.index_in_parent)
	var tx = paste(session, EdLocator.create(parent), last + 1, payload)
	if tx is EdTransaction:
		tx.label = "Duplicate %d elements" % locs.size() if locs.size() > 1 else "Duplicate %s" % session.resolve(locs[0]).local
	return tx


# ---------------------------------------------------------------------------

static func _namespace_metadata(node: EdUxmlNode) -> Array:
	var lineage: Array = []
	var n := node
	while n != null:
		lineage.push_front(n)
		n = n.parent
	var b := {}
	for el in lineage:
		for a in el.attributes:
			var nm: String = a["name"]
			if nm == "xmlns" or nm.begins_with("xmlns:"):
				b[nm] = a["value"]
	var keys: Array = b.keys()
	keys.sort()
	return keys.map(func(k): return {"name": k, "value": b[k]})


## Parse one fragment, add the namespace declarations the destination
## lacks, rename taken names. Returns {source, tag, hints, authored_name?}.
static func _transform(f: Dictionary, occupied: Dictionary, dest_b: Dictionary) -> Variant:
	var ns_attrs := ""
	var meta := {}
	for ns in f["namespaces"]:
		var v = EdXml.escape_attribute_value(ns["value"], "\"")
		if v == null:
			return EdError.make("invalid-fragment", "A namespace URI in the clipboard data is not valid XML text.")
		ns_attrs += " %s=\"%s\"" % [ns["name"], v]
		meta["" if ns["name"] == "xmlns" else String(ns["name"]).substr(6)] = ns
	var prefix := "<%s%s>" % [_WRAPPER, ns_attrs]
	var wrapper := "%s%s</%s>" % [prefix, f["source"], _WRAPPER]
	var ws := EdWorkspace.new()
	ws.set_buffer("fragment.uxml", EdSourceBuffer.new("fragment.uxml", wrapper))
	var s := EdDocumentSession.new(ws, "fragment.uxml")
	var root := s.root()
	if root == null or root.children.size() != 1 or not s.tree().problems.is_empty():
		return EdError.make("invalid-fragment", "A clipboard fragment must be exactly one well-formed XML element.")
	var child: EdUxmlNode = root.children[0]
	if child.open_start != prefix.length() or child.outer_end() != prefix.length() + String(f["source"]).length():
		return EdError.make("invalid-fragment", "A clipboard fragment must be exactly one well-formed XML element.")
	var required := {}
	_collect_prefixes(child, {}, meta, required)
	var missing: Array = []
	var req_keys: Array = required.keys()
	req_keys.sort()
	for p in req_keys:
		var ns: Dictionary = meta[p]
		var dv = dest_b.get(p)
		if dv == null:
			if not (p == "" and ns["value"] == ""):
				missing.append(ns)
		elif dv != ns["value"]:
			return EdError.make("illegal-hierarchy", "The clipboard element uses %s, which the destination binds to another namespace." % ns["name"])
	for ns in missing:
		var r = EdUxmlCommands.set_attribute(s, EdLocator.create(s.root().children[0]), ns["name"], ns["value"])
		if r is EdError:
			return r
		var c = ws.commit(r)
		if c is EdError:
			return c
	var text := s.source()
	child = s.root().children[0]
	var start := child.open_start
	var end := child.outer_end()
	var renames: Array = []
	var root_name = null
	for n in child.walk():
		for a in n.attributes_named("name"):
			var lex = EdXml.read_attribute_lexeme(text, a["start"], a["end"])
			if lex == null or lex["name"] != "name":
				return EdError.make("ambiguous-source", "A copied name attribute has no exact quoted source boundary.")
			var wanted: String = a["value"]
			var given := _available_name(wanted, occupied)
			occupied[given] = true
			if n == child:
				root_name = given
			if given != wanted:
				renames.append({"start": lex["value_start"] - start, "end": lex["value_end"] - start,
					"replacement": EdXml.escape_attribute_value(given, lex["quote"])})
	var out := text.substr(start, end - start)
	renames.sort_custom(func(a, b): return a["start"] > b["start"])
	for r in renames:
		out = out.substr(0, r["start"]) + r["replacement"] + out.substr(r["end"])
	var hints: Array = []
	for a in child.attributes:
		hints.append({"name": a["name"], "value": root_name if a["name"] == "name" and root_name != null else a["value"]})
	var res := {"source": out, "tag": child.name, "hints": hints}
	if root_name != null:
		res["authored_name"] = root_name
	return res


static func _collect_prefixes(el: EdUxmlNode, local: Dictionary, meta: Dictionary, required: Dictionary) -> void:
	var scope := local.duplicate()
	for a in el.attributes:
		var n: String = a["name"]
		if n == "xmlns":
			scope[""] = true
		elif n.begins_with("xmlns:"):
			scope[n.substr(6)] = true
	var ep := el.prefix
	if not scope.has(ep) and meta.has(ep):
		required[ep] = true
	for a in el.attributes:
		var n: String = a["name"]
		if n == "xmlns" or n.begins_with("xmlns:"):
			continue
		var colon := n.find(":")
		if colon > 0:
			var ap := n.substr(0, colon)
			if not scope.has(ap) and meta.has(ap):
				required[ap] = true
	for c in el.children:
		_collect_prefixes(c, scope, meta, required)


static func _available_name(wanted: String, occupied: Dictionary) -> String:
	if not occupied.has(wanted):
		return wanted
	var base := wanted + "-copy"
	if not occupied.has(base):
		return base
	var k := 2
	while occupied.has("%s-%d" % [base, k]):
		k += 1
	return "%s-%d" % [base, k]


static func _combine(patch: Dictionary, fragments: Array) -> Variant:
	var first: String = fragments[0]
	var repl: String = patch["replacement"]
	var pos := repl.find(first)
	if pos < 0 or repl.find(first, pos + first.length()) >= 0:
		return EdError.make("ambiguous-source", "The planned insertion does not contain one exact fragment boundary.")
	var before := repl.substr(0, pos)
	var after := repl.substr(pos + first.length())
	var sep := EdXml.trailing_space(before)
	if sep.is_empty():
		var i := 0
		while i < after.length() and EdXml.is_space(after.unicode_at(i)):
			i += 1
		sep = after.substr(0, i)
	return EdSourcePatch.make(patch["start"], patch["end"], before + sep.join(fragments) + after)
