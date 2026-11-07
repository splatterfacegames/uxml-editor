class_name EdStructureCommands
extends RefCounted
## Structure edits that the milestone 2 views need on top of the ported
## EdUxmlCommands: insert a palette element (and bind its namespace),
## unwrap, remove several elements, move to a drop position, and the
## placement rules for "insert at the selection".
##
## Each command returns an EdTransaction or an EdError, like EdUxmlCommands.


# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

## Where a new or pasted element goes for the current selection:
## {parent: EdUxmlNode, index: int}. A container gets the element as its
## last child; another element gets it as the next sibling; no selection
## puts it at the end of the root.
static func insertion_point(session: EdDocumentSession, selected: EdUxmlNode) -> Dictionary:
	var root := session.root()
	if selected == null or selected.parent == null:
		return {"parent": root, "index": 0 if root == null else root.children.size()}
	if EdElementCatalog.accepts_children(selected):
		return {"parent": selected, "index": selected.children.size()}
	return {"parent": selected.parent, "index": selected.index_in_parent + 1}


## The elements of `nodes` that no other element of `nodes` contains, in
## document order.
static func top_level(nodes: Array) -> Array:
	var out: Array = []
	for n in nodes:
		if n == null or out.has(n):
			continue
		var inside := false
		for m in nodes:
			if m != null and m != n and m.contains(n):
				inside = true
				break
		if not inside:
			out.append(n)
	out.sort_custom(func(a, b): return a.open_start < b.open_start)
	return out


# ---------------------------------------------------------------------------
# Insert from the palette
# ---------------------------------------------------------------------------

## The prefix bound to `uri` at `node` ("" for the default namespace), or
## null when no prefix is bound to it.
static func prefix_for(node: EdUxmlNode, uri: String) -> Variant:
	var b = EdUxmlNamespaces.bindings_at(node)
	if b is EdError:
		return null
	var preferred: String = EdElementCatalog.PREFERRED_PREFIX.get(uri, "")
	if not preferred.is_empty() and b.get(preferred) == uri:
		return preferred
	var keys: Array = b.keys()
	keys.sort()
	for k in keys:
		if b[k] == uri:
			return k
	return null


## Insert a new element `local` of namespace `uri` into `parent_loc` at
## child `index`, with `attributes` ([[name, value]]). When no prefix is
## bound to `uri` at the parent, the same transaction declares one on the
## root element (`xmlns:ui` or `xmlns:uie`, or a free variant).
static func insert_new_element(session: EdDocumentSession, parent_loc: Dictionary, index: int, local: String, uri: String, attributes: Array = []) -> Variant:
	if not EdXml.is_nc_name(local):
		return EdError.make("invalid-name", "%s is not a valid element name." % JSON.stringify(local))
	var parent := session.resolve(parent_loc)
	if parent == null:
		return EdError.make("unresolved-locator", "The insertion parent does not resolve uniquely in this session.")
	var prefix = prefix_for(parent, uri)
	var declare := ""
	if prefix == null:
		var b = EdUxmlNamespaces.bindings_at(parent)
		if b is EdError:
			return b
		var root := session.root()
		var rb = EdUxmlNamespaces.bindings_at(root)
		if rb is EdError:
			return rb
		var base: String = EdElementCatalog.PREFERRED_PREFIX.get(uri, "ns")
		prefix = base
		var k := 2
		while b.has(prefix) or rb.has(prefix) or _declared_below(root, prefix):
			prefix = "%s%d" % [base, k]
			k += 1
		declare = prefix
	var qname: String = local if prefix == "" else "%s:%s" % [prefix, local]
	var frag := "<%s" % qname
	for a in attributes:
		var v = EdXml.escape_attribute_value(String(a[1]), "\"")
		if v == null:
			return EdError.make("invalid-value", "Attribute %s contains a character XML 1.0 cannot represent." % a[0])
		frag += " %s=\"%s\"" % [a[0], v]
	frag += " />"
	var lbl := "Insert %s" % local
	if declare.is_empty():
		var tx = EdUxmlCommands.insert_element(session, parent_loc, index, frag)
		if tx is EdTransaction:
			tx.label = lbl
		return tx
	var root_loc := EdLocator.create(session.root())
	return EdStepComposer.compose(session, "uxml:insert-new-element", lbl, [
		func(s: EdDocumentSession): return EdUxmlCommands.set_attribute(s, root_loc, "xmlns:" + declare, uri),
		func(s: EdDocumentSession):
			var p := s.resolve(parent_loc)
			if p == null:
				return EdError.make("unresolved-locator", "The insertion parent does not resolve after the namespace declaration.")
			return EdUxmlCommands.insert_element(s, EdLocator.create(p), index, frag),
	])


## Wrap contiguous siblings `locs` in a new element `local` of namespace
## `uri` (a VisualElement by default). Binds the namespace on the root
## when needed, like insert_new_element. The wrapper is selected after.
static func wrap_in(session: EdDocumentSession, locs: Array, local: String = "VisualElement", uri: String = EdElementCatalog.RUNTIME) -> Variant:
	if locs.is_empty():
		return EdError.make("invalid-selection", "Wrapping requires at least one element.")
	var nodes: Array = []
	for l in locs:
		var n := session.resolve(l)
		if n == null:
			return EdError.make("unresolved-locator", "The element locator does not resolve uniquely in this session.")
		nodes.append(n)
	nodes.sort_custom(func(a, b): return a.open_start < b.open_start)
	var first: EdUxmlNode = nodes[0]
	var parent := first.parent
	if parent == null:
		return EdError.make("illegal-root", "The UXML root element cannot be wrapped.")
	var prefix = prefix_for(parent, uri)
	var steps: Array = []
	if prefix == null:
		var b = EdUxmlNamespaces.bindings_at(parent)
		if b is EdError:
			return b
		var root := session.root()
		var base: String = EdElementCatalog.PREFERRED_PREFIX.get(uri, "ns")
		prefix = base
		var k := 2
		while b.has(prefix) or _declared_below(root, prefix):
			prefix = "%s%d" % [base, k]
			k += 1
		var root_loc := EdLocator.create(root)
		var decl: String = "xmlns:" + prefix
		steps.append(func(s: EdDocumentSession): return EdUxmlCommands.set_attribute(s, root_loc, decl, uri))
	var qname: String = local if prefix == "" else "%s:%s" % [prefix, local]
	var keys: Array = nodes.map(func(n): return EdLocator.create(n))
	steps.append(func(s: EdDocumentSession):
		var now: Array = []
		for l in keys:
			var n := s.resolve(l)
			if n == null:
				return EdError.make("unresolved-locator", "A wrapped element does not resolve after the namespace declaration.")
			now.append(EdLocator.create(n))
		return EdUxmlCommands.wrap_elements(s, now, qname))
	var tx = EdStepComposer.compose(session, "uxml:wrap-elements", "Wrap in %s" % local, steps)
	if tx is EdTransaction:
		var ancestors: Array = parent.ancestor_tags()
		ancestors.append(parent.name)
		tx.selection_after = [{"qualified_tag": qname, "child_path": parent.child_path() + [first.index_in_parent],
			"ancestor_tags": ancestors, "attribute_hints": []}]
	return tx


## True when some element below `root` declares `prefix` (a root
## declaration of it would be shadowed there).
static func _declared_below(root: EdUxmlNode, prefix: String) -> bool:
	for n in root.walk():
		if n != root and not n.attributes_named("xmlns:" + prefix).is_empty():
			return true
	return false


# ---------------------------------------------------------------------------
# Remove, move
# ---------------------------------------------------------------------------

## Remove every element of `locs` (an element inside another removed
## element goes with it). One transaction; the selection moves to the
## parent of the first removed element.
static func remove_elements(session: EdDocumentSession, locs: Array) -> Variant:
	if locs.is_empty():
		return EdError.make("invalid-selection", "Removing requires at least one element locator.")
	var nodes: Array = []
	for l in locs:
		var n := session.resolve(l)
		if n == null:
			return EdError.make("unresolved-locator", "The element locator does not resolve uniquely in this session.")
		if n.parent == null:
			return EdError.make("illegal-root", "The UXML root element cannot be removed.")
		nodes.append(n)
	nodes = top_level(nodes)
	var patches: Array = []
	var first_parent: EdUxmlNode = nodes[0].parent
	for n in nodes:
		var tx = EdUxmlCommands.remove_element(session, EdLocator.create(n))
		if tx is EdError:
			return tx
		patches.append_array(tx.patches(session.entry_path))
	patches.sort_custom(func(a, b): return a["start"] < b["start"])
	var lbl := "Remove %s" % nodes[0].local if nodes.size() == 1 else "Remove %d elements" % nodes.size()
	var out := EdTransaction.make("uxml:remove-elements", lbl, session.entry_path, patches)
	out.document = session.entry_path
	out.selection_after = [EdLocator.create(first_parent)]
	return out


## Move contiguous siblings `locs` into `dest_loc` so that they land before
## the child that is now at `drop_index` of the destination (a drop
## position counted with the moved elements still in place). Wraps
## EdUxmlCommands.move_elements, whose index excludes the moved elements.
## The selection follows the moved elements.
static func move_to(session: EdDocumentSession, locs: Array, dest_loc: Dictionary, drop_index: int) -> Variant:
	var dest := session.resolve(dest_loc)
	if dest == null:
		return EdError.make("unresolved-locator", "The drop target does not resolve uniquely in this session.")
	var nodes: Array = []
	for l in locs:
		var n := session.resolve(l)
		if n == null:
			return EdError.make("unresolved-locator", "The element locator does not resolve uniquely in this session.")
		nodes.append(n)
	var index := drop_index
	for n in nodes:
		if n.parent == dest and n.index_in_parent < drop_index:
			index -= 1
	var tx = EdUxmlCommands.move_elements(session, locs, dest_loc, index)
	if tx is EdError:
		return tx
	nodes.sort_custom(func(a, b): return a.index_in_parent < b.index_in_parent)
	var after: Array = []
	var path: Array = dest.child_path()
	var ancestors: Array = dest.ancestor_tags()
	ancestors.append(dest.name)
	for k in nodes.size():
		var n: EdUxmlNode = nodes[k]
		var hints: Array = []
		for a in n.attributes:
			hints.append({"name": a["name"], "value": a["value"]})
		var loc := {"qualified_tag": n.name, "child_path": path + [index + k],
			"ancestor_tags": ancestors, "attribute_hints": hints}
		var nm = n.get_attribute("name")
		if nm != null:
			loc["authored_name"] = nm
		after.append(loc)
	# A move inside one parent changes the child paths of the parent's
	# later children only; a move to an ancestor or a later sibling
	# subtree can shift the destination path itself. Resolve the result
	# in a shadow to name the selection exactly.
	var shadow := EdStepComposer.shadow_of(session)
	if shadow.workspace.commit(tx) is Dictionary:
		var resolved: Array = []
		var by_open := {}
		var moved_sources: Array = []
		for n in nodes:
			moved_sources.append(session.source().substr(n.open_start, n.open_end - n.open_start))
		for n in shadow.root().walk():
			by_open[n.open_start] = n
		var ins_start := -1
		for p in tx.patches(session.entry_path):
			if not String(p["replacement"]).is_empty():
				ins_start = p["start"]
		if ins_start >= 0:
			# Map the insertion offset to the new text: removal patches
			# before it shift it left.
			var shift := 0
			for p in tx.patches(session.entry_path):
				if p["start"] < ins_start:
					shift += String(p["replacement"]).length() - (p["end"] - p["start"])
			var at := ins_start + shift
			var src := shadow.source()
			for k in nodes.size():
				var found := src.find(moved_sources[k], at)
				if found < 0 or not by_open.has(found):
					resolved.clear()
					break
				resolved.append(EdLocator.create(by_open[found]))
				at = found + 1
			if resolved.size() == nodes.size():
				after = resolved
	tx.selection_after = after
	return tx


# ---------------------------------------------------------------------------
# Unwrap
# ---------------------------------------------------------------------------

## Replace an element by its children: remove its open and close tags. A
## tag alone on its line takes its line with it, and the lines of the
## children lose one indent unit. Text inside open tags (attribute values)
## and the bytes of every child stay the same.
static func unwrap_element(session: EdDocumentSession, loc: Dictionary) -> Variant:
	var el := session.resolve(loc)
	if el == null:
		return EdError.make("unresolved-locator", "The element locator does not resolve uniquely in this session.")
	var b := session.workspace.buffer(session.entry_path)
	if b == null or not b.exact:
		return EdError.make("inexact-source", "%s does not decode to its exact bytes; the editor does not change it." % session.entry_path)
	var parent := el.parent
	if parent == null:
		return EdError.make("illegal-root", "The UXML root element cannot be unwrapped.")
	if el.local == "Style" or el.local == "Template":
		return EdError.make("illegal-hierarchy", "<%s> has no children to keep; remove it instead." % el.name)
	var src := session.source()
	if el.self_closing or el.children.is_empty():
		if not el.self_closing:
			var close = EdUxmlCommands.exact_closing_name_span(src, el)
			if close is EdError:
				return close
			var inner := src.substr(el.inner_start, el.inner_end - el.inner_start)
			if not EdXml.is_only_space(inner) and not inner.is_empty():
				return EdError.make("ambiguous-source", "%s holds text or comments but no elements; edit it in the source view." % el.name)
		var rm = EdUxmlCommands.remove_element(session, loc)
		if rm is EdTransaction:
			rm.label = "Unwrap %s" % el.local
		return rm
	var close = EdUxmlCommands.exact_closing_name_span(src, el)
	if close is EdError:
		return close
	if src.substr(el.open_start, el.name.length() + 1) != "<" + el.name:
		return EdError.make("ambiguous-source", "The open tag of %s is not safe to remove." % el.name)
	var sb = EdUxmlNamespaces.bindings_at(el)
	var db = EdUxmlNamespaces.bindings_at(parent)
	if sb is EdError:
		return sb
	if db is EdError:
		return db
	for c in el.children:
		if not EdUxmlNamespaces.preserves(c, sb, db):
			return EdError.make("illegal-hierarchy", "Unwrapping %s would unbind or change a namespace that a child uses." % el.name)
	var open_span := _line_span(src, el.open_start, el.open_end)
	var close_span := _line_span(src, el.close_start, el.close_end)
	var patches: Array = []
	patches.append(EdSourcePatch.make(open_span.x, open_span.y, ""))
	# Dedent: one unit per line start between the tags, outside open tags.
	var el_indent := EdXml.line_indent_at(src, el.open_start)
	var child_indent := EdXml.line_indent_at(src, el.children[0].open_start)
	if open_span.x != el.open_start and close_span.x != el.close_start \
			and child_indent.begins_with(el_indent) and child_indent.length() > el_indent.length():
		var unit := child_indent.substr(el_indent.length())
		var tags: Array = []
		for n in el.walk():
			if n != el:
				tags.append(Vector2i(n.open_start, n.open_end))
		var i := open_span.y
		while i < close_span.x:
			if src.substr(i, unit.length()) == unit and not _inside(tags, i):
				patches.append(EdSourcePatch.make(i, i + unit.length(), ""))
			var nl := _next_line(src, i)
			if nl < 0 or nl >= close_span.x:
				break
			i = nl
	patches.append(EdSourcePatch.make(close_span.x, close_span.y, ""))
	var tx := EdTransaction.make("uxml:unwrap-element", "Unwrap %s" % el.local, session.entry_path, patches)
	tx.document = session.entry_path
	var sel: Array = []
	var shadow := EdStepComposer.shadow_of(session)
	if shadow.workspace.commit(tx) is Dictionary:
		var by_open := {}
		for n in shadow.root().walk():
			by_open[n.open_start] = n
		for c in el.children:
			var removed_before := 0
			for p in patches:
				if p["end"] <= c.open_start:
					removed_before += p["end"] - p["start"]
			var n = by_open.get(c.open_start - removed_before)
			if n != null:
				sel.append(EdLocator.create(n))
	tx.selection_after = sel if not sel.is_empty() else [EdLocator.create(parent)]
	return tx


## [start, end) of a tag; widened to its whole line (with the line break)
## when only indentation precedes it and only whitespace follows it.
static func _line_span(src: String, start: int, end: int) -> Vector2i:
	var ls := EdXml.line_start(src, start)
	if not EdXml.is_indent(src.substr(ls, start - ls)):
		return Vector2i(start, end)
	var j := end
	while j < src.length() and (src[j] == " " or src[j] == "\t"):
		j += 1
	if j < src.length() and src[j] == "\r":
		j += 1
		if j < src.length() and src[j] == "\n":
			j += 1
		return Vector2i(ls, j)
	if j < src.length() and src[j] == "\n":
		return Vector2i(ls, j + 1)
	return Vector2i(start, end)


static func _next_line(src: String, from: int) -> int:
	var a := src.find("\n", from)
	var r := src.find("\r", from)
	if a < 0 and r < 0:
		return -1
	if r >= 0 and (a < 0 or r < a):
		return r + 2 if r + 1 < src.length() and src[r + 1] == "\n" else r + 1
	return a + 1


static func _inside(spans: Array, i: int) -> bool:
	for s in spans:
		if i > s.x and i < s.y:
			return true
	return false
