class_name EdUxmlCommands
extends RefCounted
## UXML structure and attribute edits as source patches.
##
## Ported from the TypeScript editor (main:src/core/commands/uxmlCommands.ts,
## uxmlInsertion.ts, uxmlSourceSpans.ts). Each command returns an
## EdTransaction, or an EdError when the edit cannot be expressed exactly.
## Error codes: invalid-locator, unresolved-locator, invalid-name,
## invalid-value, invalid-index, invalid-fragment, invalid-selection,
## illegal-hierarchy, illegal-root, ambiguous-source, missing-attribute,
## inexact-source.


# ---------------------------------------------------------------------------
# Attributes
# ---------------------------------------------------------------------------

static func set_attribute(session: EdDocumentSession, loc: Dictionary, attr_name: String, value: String) -> Variant:
	if not EdXml.is_qualified_name(attr_name):
		return EdError.make("invalid-name", "%s is not a valid XML qualified name." % JSON.stringify(attr_name))
	var el = _require(session, loc)
	if el is EdError:
		return el
	var ns = EdUxmlNamespaces.require_attribute_namespace(el, attr_name, value)
	if ns is EdError:
		return ns
	var matches: Array = el.attributes_named(attr_name)
	if matches.is_empty():
		return _insert_attribute(session, el, attr_name, value)
	if matches.size() > 1:
		return EdError.make("ambiguous-source", "Attribute %s occurs more than once on %s." % [attr_name, el.name])
	var src := session.source()
	var a: Dictionary = matches[0]
	var lex = EdXml.read_attribute_lexeme(src, a["start"], a["end"])
	if lex == null or lex["name"] != attr_name:
		return EdError.make("ambiguous-source", "The source span for attribute %s is not safe to edit." % attr_name)
	var escaped = EdXml.escape_attribute_value(value, lex["quote"])
	if escaped == null:
		return EdError.make("invalid-value", "Attribute %s contains a character XML 1.0 cannot represent." % attr_name)
	return _tx("set-attribute", "Set %s attribute" % attr_name, session, [
		EdSourcePatch.make(lex["value_start"], lex["value_end"], escaped)])


static func remove_attribute(session: EdDocumentSession, loc: Dictionary, attr_name: String) -> Variant:
	if not EdXml.is_qualified_name(attr_name):
		return EdError.make("invalid-name", "%s is not a valid XML qualified name." % JSON.stringify(attr_name))
	var el = _require(session, loc)
	if el is EdError:
		return el
	var matches: Array = el.attributes_named(attr_name)
	if matches.is_empty():
		return EdError.make("missing-attribute", "Attribute %s is not authored on %s." % [attr_name, el.name])
	if matches.size() > 1:
		return EdError.make("ambiguous-source", "Attribute %s occurs more than once on %s." % [attr_name, el.name])
	var a: Dictionary = matches[0]
	if attr_name == "xmlns" or attr_name.begins_with("xmlns:"):
		var safe = EdUxmlNamespaces.require_safe_removal(el, attr_name, a["raw"])
		if safe is EdError:
			return safe
	var src := session.source()
	var lex = EdXml.read_attribute_lexeme(src, a["start"], a["end"])
	var lower: int = el.open_start + 1 + el.name.length()
	var start: int = a["start"]
	while start > lower and EdXml.is_space_char(src[start - 1]):
		start -= 1
	if lex == null or lex["name"] != attr_name or start == a["start"]:
		return EdError.make("ambiguous-source", "The source span for attribute %s is not safe to remove." % attr_name)
	return _tx("remove-attribute", "Remove %s attribute" % attr_name, session, [
		EdSourcePatch.make(start, a["end"], "")])


static func _insert_attribute(session: EdDocumentSession, el: EdUxmlNode, attr_name: String, value: String) -> Variant:
	var src := session.source()
	var authored: Array = el.attributes.duplicate()
	authored.sort_custom(func(x, y): return x["start"] < y["start"])
	var name_end: int = el.open_start + 1 + el.name.length()
	var last = null if authored.is_empty() else authored[-1]
	var insertion: int = name_end if last == null else last["end"]
	var tail := src.substr(insertion, el.open_end - insertion)
	if src.substr(el.open_start, name_end - el.open_start) != "<" + el.name or not _is_tag_tail(tail):
		return EdError.make("ambiguous-source", "The open tag for %s is not safe to extend." % el.name)
	var quote := "\""
	if last != null:
		var lex = EdXml.read_attribute_lexeme(src, last["start"], last["end"])
		if lex == null:
			return EdError.make("ambiguous-source", "The final attribute on %s is not safe to extend." % el.name)
		quote = lex["quote"]
	var observed: String = ""
	if last == null:
		var i := name_end
		while i < el.open_end and EdXml.is_space_char(src[i]):
			i += 1
		observed = src.substr(name_end, i - name_end)
	else:
		var from: int = name_end if authored.size() == 1 else authored[-2]["end"]
		observed = src.substr(from, last["start"] - from)
	var sep := observed if not observed.is_empty() and EdXml.is_only_space(observed) else " "
	var escaped = EdXml.escape_attribute_value(value, quote)
	if escaped == null:
		return EdError.make("invalid-value", "Attribute %s contains a character XML 1.0 cannot represent." % attr_name)
	return _tx("set-attribute", "Set %s attribute" % attr_name, session, [
		EdSourcePatch.make(insertion, insertion, "%s%s=%s%s%s" % [sep, attr_name, quote, escaped, quote])])


## `[ws]*>` or `[ws]*/>`
static func _is_tag_tail(t: String) -> bool:
	var i := 0
	while i < t.length() and EdXml.is_space_char(t[i]):
		i += 1
	var rest := t.substr(i)
	return rest == ">" or rest == "/>"


# ---------------------------------------------------------------------------
# Elements
# ---------------------------------------------------------------------------

static func insert_element(session: EdDocumentSession, parent_loc: Dictionary, index: int, fragment: String) -> Variant:
	var parent = _require(session, parent_loc)
	if parent is EdError:
		return parent
	if index < 0 or index > parent.children.size():
		return EdError.make("invalid-index", "Child index %d is outside %s." % [index, parent.name])
	var b = EdUxmlNamespaces.bindings_at(parent)
	if b is EdError:
		return b
	if not EdXml.is_element_fragment(fragment, b):
		return EdError.make("invalid-fragment", "Inserted source must be exactly one XML element fragment.")
	var p = plan_destination_insertion(session.source(), parent, index, fragment, parent.children)
	if p is EdError:
		return p
	var tx := _tx("insert-element", "Insert element in %s" % parent.name, session, [p])
	var inserted := EdUxmlSource.parse(fragment).root
	var child_path: Array = parent.child_path()
	child_path.append(index)
	var ancestors: Array = parent.ancestor_tags()
	ancestors.append(parent.name)
	tx.selection_after = [{"qualified_tag": inserted.name, "child_path": child_path,
		"ancestor_tags": ancestors, "attribute_hints": []}]
	return tx


static func remove_element(session: EdDocumentSession, loc: Dictionary) -> Variant:
	var el = _require(session, loc)
	if el is EdError:
		return el
	var parent: EdUxmlNode = el.parent
	if parent == null:
		return EdError.make("illegal-root", "The UXML root element cannot be removed.")
	var src := session.source()
	var oe = outer_end(src, el)
	if oe is EdError:
		return oe
	var index: int = el.index_in_parent
	var lower = parent.inner_start if index == 0 else outer_end(src, parent.children[index - 1])
	if lower is EdError:
		return lower
	var gap := src.substr(lower, el.open_start - lower)
	var start: int = lower if not gap.is_empty() and EdXml.is_only_space(gap) else el.open_start
	if src.substr(el.open_start, el.name.length() + 1) != "<" + el.name or oe > parent.inner_end:
		return EdError.make("ambiguous-source", "The outer source span for %s is not safe to remove." % el.name)
	var tx := _tx("remove-element", "Remove %s" % el.local, session, [EdSourcePatch.make(start, oe, "")])
	tx.selection_after = [EdLocator.create(parent)]
	return tx


static func duplicate_element(session: EdDocumentSession, loc: Dictionary) -> Variant:
	var el = _require(session, loc)
	if el is EdError:
		return el
	var parent: EdUxmlNode = el.parent
	if parent == null:
		return EdError.make("illegal-root", "The UXML root element cannot be duplicated.")
	var src := session.source()
	var start: int = el.open_start
	var end = outer_end(src, el)
	if end is EdError:
		return end
	var fragment := src.substr(start, end - start)
	var index: int = el.index_in_parent
	if index + 1 < parent.children.size():
		var next: EdUxmlNode = parent.children[index + 1]
		var sep := EdXml.trailing_space(src.substr(end, next.open_start - end))
		return _tx("duplicate-element", "Duplicate %s" % el.local, session, [
			EdSourcePatch.make(next.open_start, next.open_start, fragment + sep)])
	var lower = parent.inner_start if index == 0 else outer_end(src, parent.children[index - 1])
	if lower is EdError:
		return lower
	var sep2 := EdXml.trailing_space(src.substr(lower, start - lower))
	return _tx("duplicate-element", "Duplicate %s" % el.local, session, [
		EdSourcePatch.make(end, end, sep2 + fragment)])


## Move contiguous siblings `locs` into `dest_loc` at child `index` (an
## index among the destination's children without the moved elements).
static func move_elements(session: EdDocumentSession, locs: Array, dest_loc: Dictionary, index: int) -> Variant:
	if locs.is_empty():
		return EdError.make("invalid-selection", "Moving requires at least one element locator.")
	var els: Array = []
	for l in locs:
		var e = _require(session, l)
		if e is EdError:
			return e
		if els.has(e):
			return EdError.make("invalid-selection", "Moving the same element more than once is ambiguous.")
		els.append(e)
	var dest = _require(session, dest_loc)
	if dest is EdError:
		return dest
	var sp: EdUxmlNode = els[0].parent
	if sp == null:
		return EdError.make("illegal-root", "The UXML root element cannot be moved.")
	for e in els:
		if e.parent != sp:
			return EdError.make("invalid-selection", "Moved elements must share one direct parent.")
	els.sort_custom(func(a, b): return a.index_in_parent < b.index_in_parent)
	for k in range(1, els.size()):
		if els[k].index_in_parent != els[k - 1].index_in_parent + 1:
			return EdError.make("invalid-selection", "Moved elements must be contiguous siblings.")
	for e in els:
		if e.contains(dest):
			return EdError.make("illegal-hierarchy", "An element cannot be moved into itself or its descendant.")
	var same: bool = sp == dest
	var dest_children: Array = []
	for c in dest.children:
		if not (same and els.has(c)):
			dest_children.append(c)
	if index < 0 or index > dest_children.size():
		return EdError.make("invalid-index", "Child index %d is outside %s." % [index, dest.name])
	if same and els[0].index_in_parent == index:
		return EdError.make("illegal-hierarchy", "The moved selection is already at child index %d." % index)
	var sb = EdUxmlNamespaces.bindings_at(sp)
	var db = EdUxmlNamespaces.bindings_at(dest)
	if sb is EdError:
		return sb
	if db is EdError:
		return db
	for e in els:
		if not EdUxmlNamespaces.preserves(e, sb, db):
			return EdError.make("illegal-hierarchy", "The move would lose or change a namespace binding used by the moved selection.")
	var src := session.source()
	for e in els:
		var c = exact_closing_name_span(src, e)
		if c is EdError:
			return c
	var start: int = els[0].open_start
	var end = outer_end(src, els[-1])
	if end is EdError:
		return end
	var fragment := src.substr(start, end - start)
	var ins = plan_destination_insertion(src, dest, index, fragment, dest_children)
	if ins is EdError:
		return ins
	var patches := [EdSourcePatch.make(start, end, ""), ins]
	patches.sort_custom(func(a, b): return a["start"] < b["start"])
	var lbl := "Move %s" % els[0].local if els.size() == 1 else "Move %d elements" % els.size()
	return _tx("move-element", lbl, session, patches)


static func move_element(session: EdDocumentSession, loc: Dictionary, dest_loc: Dictionary, index: int) -> Variant:
	return move_elements(session, [loc], dest_loc, index)


static func wrap_elements(session: EdDocumentSession, locs: Array, wrapper: String) -> Variant:
	if not EdXml.is_qualified_name(wrapper):
		return EdError.make("invalid-name", "%s is not a valid XML qualified name." % JSON.stringify(wrapper))
	if locs.is_empty():
		return EdError.make("invalid-selection", "Wrapping requires at least one element locator.")
	var els: Array = []
	for l in locs:
		var e = _require(session, l)
		if e is EdError:
			return e
		if els.has(e):
			return EdError.make("invalid-selection", "Wrapping the same element more than once is ambiguous.")
		els.append(e)
	var parent: EdUxmlNode = els[0].parent
	if parent == null:
		return EdError.make("illegal-root", "The UXML root element cannot be wrapped.")
	for e in els:
		if e.parent != parent:
			return EdError.make("invalid-selection", "Wrapped elements must share one direct parent.")
	els.sort_custom(func(a, b): return a.index_in_parent < b.index_in_parent)
	for k in range(1, els.size()):
		if els[k].index_in_parent != els[k - 1].index_in_parent + 1:
			return EdError.make("invalid-selection", "Wrapped elements must be contiguous siblings.")
	var bound = EdUxmlNamespaces.require_bound(parent, wrapper, false)
	if bound is EdError:
		return bound
	var src := session.source()
	for e in els:
		var c = exact_closing_name_span(src, e)
		if c is EdError:
			return c
	var start: int = els[0].open_start
	var end = outer_end(src, els[-1])
	if end is EdError:
		return end
	return _tx("wrap-elements", "Wrap in %s" % wrapper, session, plan_wrapper_patches(src, parent, start, end, wrapper))


static func rename_element(session: EdDocumentSession, loc: Dictionary, qname: String) -> Variant:
	if not EdXml.is_qualified_name(qname):
		return EdError.make("invalid-name", "%s is not a valid XML qualified name." % JSON.stringify(qname))
	var el = _require(session, loc)
	if el is EdError:
		return el
	if el.parent == null:
		return EdError.make("illegal-root", "The UXML root element cannot be renamed.")
	var bound = EdUxmlNamespaces.require_bound(el, qname, false)
	if bound is EdError:
		return bound
	var src := session.source()
	var os: int = el.open_start + 1
	if src.substr(os, el.name.length()) != el.name:
		return EdError.make("ambiguous-source", "The opening name for %s is not safe to edit." % el.name)
	var patches := [EdSourcePatch.make(os, os + el.name.length(), qname)]
	var close = exact_closing_name_span(src, el)
	if close is EdError:
		return close
	if close != null:
		patches.append(EdSourcePatch.make(close.x, close.y, qname))
	return _tx("rename-element", "Rename %s" % el.local, session, patches)


# ---------------------------------------------------------------------------
# Spans and insertion planning
# ---------------------------------------------------------------------------

## End of the element's source, or an EdError when its close tag is not
## exactly `</name ws* >`.
static func outer_end(src: String, el: EdUxmlNode) -> Variant:
	var c = exact_closing_name_span(src, el)
	if c is EdError:
		return c
	if c == null:
		return maxi(el.open_end, el.inner_end)
	return el.close_end


## The close tag name span as Vector2i, null for a self-closing element,
## or an EdError.
static func exact_closing_name_span(src: String, el: EdUxmlNode) -> Variant:
	if el.self_closing:
		return null
	if el.close_start < 0:
		return EdError.make("ambiguous-source", "%s has no close tag in the source." % el.name)
	var start := el.close_start + 2
	var end := start + el.name.length()
	if el.inner_end != el.close_start or src.substr(el.close_start, 2) != "</" \
			or src.substr(start, el.name.length()) != el.name or not _is_close_tail(src.substr(end, el.close_end - end)):
		return EdError.make("ambiguous-source", "The recovered closing tag for %s does not match its source span exactly." % el.name)
	return Vector2i(start, end)


static func _is_close_tail(t: String) -> bool:
	var i := 0
	while i < t.length() and EdXml.is_space_char(t[i]):
		i += 1
	return t.substr(i) == ">"


static func plan_destination_insertion(src: String, parent: EdUxmlNode, index: int, fragment: String, children: Array) -> Variant:
	if parent.self_closing:
		return _plan_self_closing(src, parent, fragment)
	var c = exact_closing_name_span(src, parent)
	if c is EdError:
		return c
	return _plan_paired(src, parent, index, fragment, children)


static func _plan_self_closing(src: String, parent: EdUxmlNode, fragment: String) -> Variant:
	var slash := parent.open_end - 2
	if src.substr(slash, 2) != "/>":
		return EdError.make("ambiguous-source", "The self-closing delimiter for %s is not safe to edit." % parent.name)
	var f := _child_formatting(src, parent)
	var inner := ""
	if f["newline"].is_empty():
		inner = "%s</%s>" % [fragment, parent.name]
	else:
		inner = "%s%s%s%s%s</%s>" % [f["newline"], f["child_indent"], fragment, f["newline"], f["parent_indent"], parent.name]
	# `<VisualElement />` becomes `<VisualElement>`, not `<VisualElement >`:
	# the spaces before `/>` go too. White space with a line break stays
	# (a `/>` on its own line becomes a `>` on its own line).
	var start := slash
	while start > parent.open_start and (src[start - 1] == " " or src[start - 1] == "\t"):
		start -= 1
	if src[start - 1] == "\n" or src[start - 1] == "\r":
		start = slash
	return EdSourcePatch.make(start, parent.open_end, ">" + inner)


static func _plan_paired(src: String, parent: EdUxmlNode, index: int, fragment: String, children: Array) -> Variant:
	if index < children.size():
		var current: EdUxmlNode = children[index]
		var lower = parent.inner_start if index == 0 else outer_end(src, children[index - 1])
		if lower is EdError:
			return lower
		var sep := EdXml.trailing_space(src.substr(lower, current.open_start - lower))
		return EdSourcePatch.make(current.open_start, current.open_start, fragment + sep)
	if index > 0:
		var prev: EdUxmlNode = children[index - 1]
		var lower = parent.inner_start if index == 1 else outer_end(src, children[index - 2])
		if lower is EdError:
			return lower
		var sep := EdXml.trailing_space(src.substr(lower, prev.open_start - lower))
		var start = outer_end(src, prev)
		if start is EdError:
			return start
		return EdSourcePatch.make(start, start, sep + fragment)
	var tail := EdXml.trailing_space(src.substr(parent.inner_start, parent.inner_end - parent.inner_start))
	var at := parent.inner_end - tail.length()
	var f := _child_formatting(src, parent)
	var prefix: String = "" if f["newline"].is_empty() else f["newline"] + f["child_indent"]
	return EdSourcePatch.make(at, at, prefix + fragment)


static func plan_wrapper_patches(src: String, parent: EdUxmlNode, start: int, end: int, wrapper: String) -> Array:
	var f := _child_formatting(src, parent)
	var wrapper_indent := EdXml.line_indent_at(src, start)
	var observed: String = wrapper_indent.substr(f["parent_indent"].length()) if wrapper_indent.begins_with(f["parent_indent"]) else ""
	var unit: String = observed if not observed.is_empty() else ("\t" if wrapper_indent.contains("\t") else "  ")
	var before := "<%s>" % wrapper
	var after := "</%s>" % wrapper
	if not f["newline"].is_empty():
		before = "<%s>%s%s%s" % [wrapper, f["newline"], wrapper_indent, unit]
		after = "%s%s</%s>" % [f["newline"], wrapper_indent, wrapper]
	return [EdSourcePatch.make(start, start, before), EdSourcePatch.make(end, end, after)]


static func _child_formatting(src: String, parent: EdUxmlNode) -> Dictionary:
	var ls := EdXml.line_start(src, parent.open_start)
	var before_tag := src.substr(ls, parent.open_start - ls)
	var parent_indent := before_tag if EdXml.is_indent(before_tag) else ""
	var inner_nl := EdXml.first_newline(src.substr(parent.inner_start, parent.inner_end - parent.inner_start))
	var nl := ""
	if ls == 0:
		nl = inner_nl
	elif src[ls - 1] == "\n" and ls >= 2 and src[ls - 2] == "\r":
		nl = "\r\n"
	else:
		nl = src[ls - 1]
	if nl.is_empty():
		return {"newline": "", "parent_indent": parent_indent, "child_indent": ""}
	var ancestor := parent.parent
	var ancestor_indent := "" if ancestor == null else EdXml.line_indent_at(src, ancestor.open_start)
	var observed: String = parent_indent.substr(ancestor_indent.length()) if parent_indent.begins_with(ancestor_indent) else ""
	var unit: String = observed if not observed.is_empty() else ("\t" if parent_indent.contains("\t") else "  ")
	return {"newline": nl, "parent_indent": parent_indent, "child_indent": parent_indent + unit}


# ---------------------------------------------------------------------------

static func _require(session: EdDocumentSession, loc: Variant) -> Variant:
	var b := session.workspace.buffer(session.entry_path)
	if b == null:
		return EdError.make("unresolved-locator", "The document %s is not open." % session.entry_path)
	if not b.exact:
		return EdError.make("inexact-source", "%s does not decode to its exact bytes; the editor does not change it." % session.entry_path)
	if not EdLocator.is_valid(loc):
		return EdError.make("invalid-locator", "The element locator is malformed.")
	var el := EdLocator.resolve(session.root(), loc)
	if el == null:
		return EdError.make("unresolved-locator", "The element locator does not resolve uniquely in this session.")
	return el


static func _tx(op: String, lbl: String, session: EdDocumentSession, patches: Array) -> EdTransaction:
	var tx := EdTransaction.make("uxml:" + op, lbl, session.entry_path, patches)
	tx.document = session.entry_path
	return tx
