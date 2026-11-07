class_name EdUssCommands
extends RefCounted
## Style edits as source patches: inline `style` declarations, rule
## declarations, and new rules.
##
## Ported from main:src/core/commands/ussCommands.ts and
## ussSourceEditing.ts. A style target freezes the source it was made from
## (`source_snapshot`) and the exact spans it names; a commit against a
## changed source is refused with "stale-target", never redirected
## (docs/adr/0004-style-write-targets.md).
##
## Target shapes (plain Dictionaries, made by the target functions below):
##   inline:   {kind: "inline", path, locator, property, source_snapshot,
##              attribute: {start, end} or null, declaration_index (-1 new),
##              declaration: {start, end, raw} or null}
##   rule:     {kind: "rule", path, item_index, property, source_snapshot,
##              rule_span: Vector2i, selector_span: Vector2i,
##              declaration_index (-1 new), declaration: {start, end, raw}}
##   new-rule: {kind: "new-rule", path, selector, property, source_snapshot}


# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------

## The inline target of `property` on the element at `loc`. Names the last
## inline declaration of the property when one exists (the one that wins).
static func inline_target(session: EdDocumentSession, loc: Dictionary, property: String) -> Variant:
	var el := session.resolve(loc)
	if el == null:
		return EdError.make("stale-target", "The element no longer resolves.")
	var src := session.source()
	var t := {"kind": "inline", "path": session.entry_path, "locator": EdLocator.create(el),
		"property": property, "source_snapshot": src, "attribute": null,
		"declaration_index": -1, "declaration": null}
	var styles := el.attributes_named("style")
	if styles.size() > 1:
		return EdError.make("ambiguous-source", "The style attribute occurs more than once on %s." % el.name)
	if styles.size() == 1:
		var a: Dictionary = styles[0]
		t["attribute"] = {"start": a["start"], "end": a["end"]}
		for d in EdUssSource.parse_declarations(src, a["value_start"], a["value_end"]):
			if d["property"] == property:
				t["declaration_index"] = d["index"]
				t["declaration"] = {"start": d["start"], "end": d["end"], "raw": d["raw"]}
	return t


static func rule_target(ws: EdWorkspace, path: String, item_index: int, property: String) -> Variant:
	var sheet := ws.uss(path)
	if sheet == null:
		return EdError.make("stale-target", "Stylesheet %s is not open." % path)
	var it = sheet.item(item_index)
	if it == null or it["kind"] != "rule":
		return EdError.make("invalid-target", "Item %d of %s is not a rule." % [item_index, path])
	var t := {"kind": "rule", "path": path, "item_index": item_index, "property": property,
		"source_snapshot": sheet.text,
		"rule_span": Vector2i(it["start"], it["end"]),
		"selector_span": Vector2i(it["selector_start"], it["selector_end"]),
		"declaration_index": -1, "declaration": null}
	for d in it["declarations"]:
		if d["property"] == property:
			t["declaration_index"] = d["index"]
			t["declaration"] = {"start": d["start"], "end": d["end"], "raw": d["raw"]}
	return t


static func new_rule_target(ws: EdWorkspace, path: String, selector: String, property: String) -> Dictionary:
	return {"kind": "new-rule", "path": path, "selector": selector, "property": property,
		"source_snapshot": ws.text(path)}


# ---------------------------------------------------------------------------
# Rule declarations
# ---------------------------------------------------------------------------

static func set_declaration(ws: EdWorkspace, target: Dictionary, value: String) -> Variant:
	var cur = _current_rule(ws, target)
	if cur is EdError:
		return cur
	var ok = require_value(target["property"], value)
	if ok is EdError:
		return ok
	var path: String = target["path"]
	if cur["declaration"] == null:
		var patches = EdCssInsertion.plan_rule(path, cur["source"], cur["rule"], target["property"], value)
		if patches is EdError:
			return patches
		return _tx("set-declaration", "Set %s" % target["property"], path, patches)
	var lex = declaration_lexeme(cur["source"], cur["declaration"])
	if lex is EdError:
		return lex
	return _tx("set-declaration", "Set %s" % target["property"], path, [
		EdSourcePatch.make(lex.x, lex.y, value)])


static func remove_declaration(ws: EdWorkspace, target: Dictionary) -> Variant:
	var cur = _current_rule(ws, target)
	if cur is EdError:
		return cur
	if cur["declaration"] == null:
		return EdError.make("invalid-target", "Cannot remove %s because this target has no authored declaration." % target["property"])
	var src: String = cur["source"]
	var d: Dictionary = cur["declaration"]
	var p = _removal_patch(src, d, cur["rule"]["block_start"] + 1)
	return _tx("remove-declaration", "Remove %s" % target["property"], target["path"], [p])


static func insert_rule(ws: EdWorkspace, target: Dictionary, value: String) -> Variant:
	var path: String = target["path"]
	var b := ws.buffer(path)
	if b == null:
		return EdError.make("stale-target", "Stylesheet %s is no longer open." % path)
	if target["source_snapshot"] != b.text:
		return EdError.make("stale-target", "Stylesheet %s changed after this target was created." % path)
	var ok = require_value(target["property"], value)
	if ok is EdError:
		return ok
	var safe = assert_safe_append(path, b.text)
	if safe is EdError:
		return safe
	var nl := b.newline()
	var indent := _sheet_indent(b.text, ws.uss(path))
	var final_nl := b.text.ends_with("\n") or b.text.ends_with("\r")
	var sep := "" if b.text.is_empty() else nl + ("" if final_nl else nl)
	var rule := "%s {%s%s%s: %s;%s}" % [target["selector"], nl, indent, target["property"], value, nl]
	return _tx("insert-rule", "Add %s rule" % target["property"], path, [
		EdSourcePatch.make(b.text.length(), b.text.length(), sep + rule + (nl if final_nl else ""))])


# ---------------------------------------------------------------------------
# Inline declarations
# ---------------------------------------------------------------------------

static func set_inline_style(session: EdDocumentSession, target: Dictionary, value: String) -> Variant:
	var cur = _current_inline(session, target)
	if cur is EdError:
		return cur
	var property: String = target["property"]
	var ok = require_value(property, value)
	if ok is EdError:
		return ok
	var src: String = cur["source"]
	if cur["attribute"] == null:
		var planned = EdUxmlCommands.set_attribute(session, target["locator"], "style", "%s: %s;" % [property, value])
		if planned is EdError:
			return planned
		return _inline_tx("set-inline-style", "Set inline %s" % property, session, planned.patches(session.entry_path))
	var a: Dictionary = cur["attribute"]
	var escaped = EdXml.escape_attribute_value(value, a["quote"])
	if escaped == null:
		return EdError.make("invalid-value", "Inline value for %s is not valid XML 1.0 text." % property)
	if cur["declaration"] == null:
		var p = EdCssInsertion.plan_inline(session.entry_path, src, a["value_start"], a["value_end"], cur["declarations"], property, escaped)
		if p is EdError:
			return p
		return _inline_tx("set-inline-style", "Set inline %s" % property, session, [p])
	var lex = declaration_lexeme(src, cur["declaration"])
	if lex is EdError:
		return lex
	return _inline_tx("set-inline-style", "Set inline %s" % property, session, [
		EdSourcePatch.make(lex.x, lex.y, escaped)])


## Remove the inline declaration; remove the whole `style` attribute when
## nothing but whitespace would remain.
static func remove_inline_style(session: EdDocumentSession, target: Dictionary) -> Variant:
	var cur = _current_inline(session, target)
	if cur is EdError:
		return cur
	if cur["declaration"] == null:
		return EdError.make("invalid-target", "%s has no inline declaration to remove." % target["property"])
	var src: String = cur["source"]
	var a: Dictionary = cur["attribute"]
	var p := _removal_patch(src, cur["declaration"], a["value_start"])
	var value_after: String = EdSourcePatch.apply(src.substr(0, a["value_end"]), [p]).substr(a["value_start"])
	if EdUssSource.strip_comments(value_after).replace(";", "").strip_edges().is_empty() and not value_after.contains("/*"):
		var removed = EdUxmlCommands.remove_attribute(session, target["locator"], "style")
		if removed is EdError:
			return removed
		return _inline_tx("remove-inline-style", "Remove inline %s" % target["property"], session, removed.patches(session.entry_path))
	return _inline_tx("remove-inline-style", "Remove inline %s" % target["property"], session, [p])


# ---------------------------------------------------------------------------
# Shared
# ---------------------------------------------------------------------------

## A value must be exactly one declaration value for `property`.
static func require_value(property: String, value: String) -> Variant:
	if value.is_empty():
		return EdError.make("invalid-value", "A USS declaration value must be a nonempty single value.")
	var text := "%s: %s;" % [property, value]
	var decls := EdUssSource.parse_declarations(text)
	if decls.size() != 1 or decls[0]["property"] != property or decls[0]["raw"] != value or value.contains("/*"):
		return EdError.make("invalid-value", "The value for %s is not one complete USS declaration value." % property)
	return true


## The raw value span (Vector2i) of a declaration {start, end, raw}.
static func declaration_lexeme(src: String, d: Dictionary) -> Variant:
	var t: String = src.substr(d["start"], d["end"] - d["start"])
	var colon := t.find(":")
	if colon <= 0:
		return EdError.make("ambiguous-source", "Declaration has no safe value boundary.")
	var i := colon + 1
	while i < t.length() and EdXml.is_space_char(t[i]):
		i += 1
	var raw: String = d["raw"]
	if t.substr(i) != raw:
		return EdError.make("ambiguous-source", "Declaration value does not match its parser span.")
	if raw.contains("/*"):
		return EdError.make("ambiguous-source", "The declaration value has a comment; edit it in the source view so the comment is kept.")
	return Vector2i(d["start"] + i, d["start"] + i + raw.length())


## The declaration and its `;` terminator (main:ussCommands.ts). When the
## declaration is alone on its line, the whole line goes. When it is first
## in a one-line list, the spaces after it go too.
static func _removal_patch(src: String, d: Dictionary, lower: int) -> Dictionary:
	var term: int = d["end"]
	while term < src.length() and EdXml.is_space_char(src[term]):
		term += 1
	var end: int = term + 1 if term < src.length() and src[term] == ";" else d["end"]
	var start: int = d["start"]
	var s := start
	while s > lower and (src[s - 1] == " " or src[s - 1] == "\t"):
		s -= 1
	var e := end
	while e < src.length() and (src[e] == " " or src[e] == "\t"):
		e += 1
	var line_before := s > lower and (src[s - 1] == "\n" or src[s - 1] == "\r")
	var line_after := e < src.length() and (src[e] == "\n" or src[e] == "\r")
	if line_before and line_after:
		if src[e] == "\r" and e + 1 < src.length() and src[e + 1] == "\n":
			e += 1
		return EdSourcePatch.make(s, e + 1, "")
	if s == lower and e > end:
		return EdSourcePatch.make(start, e, "")
	return EdSourcePatch.make(start, end, "")


static func assert_safe_append(path: String, src: String) -> Variant:
	var depth := 0
	var quote := ""
	var comment := false
	var i := 0
	while i < src.length():
		var ch := src[i]
		var next := src[i + 1] if i + 1 < src.length() else ""
		if comment:
			if ch == "*" and next == "/":
				comment = false
				i += 1
		elif not quote.is_empty():
			if ch == "\\":
				i += 1
			elif ch == quote:
				quote = ""
		elif ch == "/" and next == "*":
			comment = true
			i += 1
		elif ch == "\"" or ch == "'":
			quote = ch
		elif ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth < 0:
				return EdError.make("unsafe-source", "Stylesheet %s has an unmatched closing brace; a rule cannot be appended safely." % path)
		i += 1
	if depth != 0 or not quote.is_empty() or comment:
		return EdError.make("unsafe-source", "Stylesheet %s ends inside a block, comment, or quoted value; a rule cannot be appended safely." % path)
	return true


static func _sheet_indent(src: String, sheet: EdUssSource) -> String:
	var rules := sheet.rules() if sheet != null else []
	for r in range(rules.size() - 1, -1, -1):
		var decls: Array = rules[r]["declarations"]
		for k in range(decls.size() - 1, -1, -1):
			var start: int = decls[k]["start"]
			var ls := EdXml.line_start(src, start)
			var indent := src.substr(ls, start - ls)
			if not indent.is_empty() and EdXml.is_indent(indent):
				return indent
	return "  "


static func _current_rule(ws: EdWorkspace, t: Dictionary) -> Variant:
	if t.get("kind") != "rule":
		return EdError.make("invalid-target", "The target is not a rule target.")
	var path: String = t["path"]
	var b := ws.buffer(path)
	if b == null:
		return EdError.make("stale-target", "Stylesheet %s is no longer open." % path)
	if not b.exact:
		return EdError.make("inexact-source", "%s does not decode to its exact bytes; the editor does not change it." % path)
	if t["source_snapshot"] != b.text:
		return EdError.make("stale-target", "Stylesheet %s changed after this target was created." % path)
	var it = ws.uss(path).item(t["item_index"])
	if it == null or it["kind"] != "rule" or Vector2i(it["start"], it["end"]) != t["rule_span"] \
			or Vector2i(it["selector_start"], it["selector_end"]) != t["selector_span"]:
		return EdError.make("stale-target", "The rule no longer matches its exact source spans in %s." % path)
	var decl = null
	if t["declaration_index"] >= 0:
		var decls: Array = it["declarations"]
		if t["declaration_index"] >= decls.size():
			return EdError.make("stale-target", "Declaration %s is no longer in its rule." % t["property"])
		decl = decls[t["declaration_index"]]
		var want: Dictionary = t["declaration"]
		if decl["property"] != t["property"] or decl["start"] != want["start"] or decl["end"] != want["end"] or decl["raw"] != want["raw"]:
			return EdError.make("stale-target", "Declaration %s no longer matches its exact source span." % t["property"])
	return {"source": b.text, "rule": it, "declaration": decl}


static func _current_inline(session: EdDocumentSession, t: Dictionary) -> Variant:
	if t.get("kind") != "inline" or t.get("path") != session.entry_path:
		return EdError.make("invalid-target", "The target is not an inline target of this document.")
	var b := session.workspace.buffer(session.entry_path)
	if b == null:
		return EdError.make("stale-target", "The document is no longer open.")
	if t["source_snapshot"] != b.text:
		return EdError.make("stale-target", "The UXML entry changed after this inline target was created.")
	var el := session.resolve(t["locator"])
	if el == null:
		return EdError.make("stale-target", "The inline style target no longer resolves to the same element.")
	var styles := el.attributes_named("style")
	if t["attribute"] == null:
		if not styles.is_empty():
			return EdError.make("stale-target", "The target element now has an authored inline style attribute.")
		return {"source": b.text, "attribute": null, "declarations": [], "declaration": null}
	if styles.size() != 1 or styles[0]["start"] != t["attribute"]["start"] or styles[0]["end"] != t["attribute"]["end"]:
		return EdError.make("stale-target", "The inline style attribute no longer matches its exact source span.")
	var a: Dictionary = styles[0]
	var lex = EdXml.read_attribute_lexeme(b.text, a["start"], a["end"])
	if lex == null or lex["name"] != "style":
		return EdError.make("ambiguous-source", "The inline style attribute has no safe quoted value boundary.")
	var decls := EdUssSource.parse_declarations(b.text, a["value_start"], a["value_end"])
	var decl = null
	if t["declaration_index"] >= 0:
		if t["declaration_index"] >= decls.size():
			return EdError.make("stale-target", "Inline declaration %s no longer matches its parser index." % t["property"])
		decl = decls[t["declaration_index"]]
		var want: Dictionary = t["declaration"]
		if decl["property"] != t["property"] or decl["start"] != want["start"] or decl["end"] != want["end"] or decl["raw"] != want["raw"]:
			return EdError.make("stale-target", "Inline declaration %s no longer matches its parser index." % t["property"])
	return {"source": b.text, "attribute": a, "declarations": decls, "declaration": decl}


static func _tx(op: String, lbl: String, path: String, patches: Array) -> EdTransaction:
	return EdTransaction.make("uss:" + op, lbl, path, patches)


static func _inline_tx(op: String, lbl: String, session: EdDocumentSession, patches: Array) -> EdTransaction:
	var tx := EdTransaction.make("uss:" + op, lbl, session.entry_path, patches)
	tx.document = session.entry_path
	return tx
