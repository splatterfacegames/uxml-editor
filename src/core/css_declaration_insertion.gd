class_name EdCssInsertion
extends RefCounted
## Plan the patch that adds one `property: value;` declaration to an inline
## style or a rule block, in the layout the author already uses.
##
## Ported from main:src/core/commands/cssDeclarationInsertion.ts. Returns
## a patch Dictionary or an EdError ("ambiguous-source", "unsafe-source").


## `declarations` are EdUssSource declarations of [value_start, value_end).
static func plan_inline(path: String, src: String, value_start: int, value_end: int, declarations: Array, property: String, value: String) -> Variant:
	var last = null if declarations.is_empty() else declarations[-1]
	var tail_start: int = value_start
	if last != null:
		var e = declaration_content_end(path, src, last)
		if e is EdError:
			return e
		tail_start = e
	var tail_text := src.substr(tail_start, value_end - tail_start)
	var tail = _tokenize_tail(path, tail_text)
	if tail is EdError:
		return tail
	var decl := "%s: %s;" % [property, value]
	if last != null:
		var semi_end = null if tail["semicolon"] < 0 else tail["semicolon"] + 1
		var insertion: int = tail_start + (0 if semi_end == null else semi_end)
		var lead_from: int = 0 if semi_end == null else semi_end
		var lead_to: int = tail_text.length() if tail["comment"] < 0 else tail["comment"]
		var leading := tail_text.substr(lead_from, lead_to - lead_from)
		var layout = _multiline_layout(leading, src, last["start"])
		return EdSourcePatch.make(insertion, insertion, "%s%s%s" % [";" if semi_end == null else "", " " if layout == null else layout, decl])
	if tail["comment"] >= 0:
		var leading := tail_text.substr(0, tail["comment"])
		var layout = _multiline_layout(leading, src, value_start)
		var at: int = value_start + tail["comment"]
		return EdSourcePatch.make(at, at, decl + (" " if layout == null else layout))
	var nl := EdXml.first_newline(tail_text)
	if not nl.is_empty():
		var last_nl := maxi(tail_text.rfind("\n"), tail_text.rfind("\r"))
		var closing := tail_text.substr(last_nl + 1)
		var at := value_start + last_nl + 1
		var indent := closing if EdXml.is_indent(closing) else "  "
		return EdSourcePatch.make(at, at, indent + decl + nl)
	var end := value_start + tail_text.length()
	return EdSourcePatch.make(end, end, ("" if tail_text.is_empty() else " ") + decl)


## `rule` is an EdUssSource rule item. Returns an Array of patches (a
## missing `;` after the last declaration is added) or an EdError.
static func plan_rule(path: String, src: String, rule: Dictionary, property: String, value: String) -> Variant:
	var close: int = rule["block_end"] - 1
	if not rule["closed"] or close < 0 or src[close] != "}":
		return EdError.make("ambiguous-source", "Rule %d in %s has no exact closing brace." % [rule["item_index"], path])
	var decls: Array = rule["declarations"]
	var last = null if decls.is_empty() else decls[-1]
	var tail_start: int = rule["block_start"] + 1 if last == null else last["end"]
	var t = _tokenize_tail(path, src.substr(tail_start, close - tail_start))
	if t is EdError:
		return t
	var cls := EdXml.line_start(src, close)
	var closing_indent := src.substr(cls, close - cls)
	var nl := _newline_before(src, cls)
	if not nl.is_empty() and EdXml.is_indent(closing_indent) and cls > tail_start:
		var indent := closing_indent + "  "
		if last != null:
			var di = _declaration_indent(src, last["start"])
			if di != null:
				indent = di
		var out: Array = []
		if last != null and t["semicolon"] < 0:
			out.append(EdSourcePatch.make(last["end"], last["end"], ";"))
		out.append(EdSourcePatch.make(cls, cls, "%s%s: %s;%s" % [indent, property, value, nl]))
		return out
	var at := close
	while at > tail_start and _is_css_space(src[at - 1]):
		at -= 1
	var sep: String = ";" if last != null and t["semicolon"] < 0 else ""
	return [EdSourcePatch.make(at, at, "%s %s: %s;" % [sep, property, value])]


## The end of the declaration's value content, before trailing comments.
static func declaration_content_end(path: String, src: String, d: Dictionary) -> Variant:
	var t: String = src.substr(d["start"], d["end"] - d["start"])
	if not t.begins_with(d["property"]):
		return EdError.make("ambiguous-source", "Declaration %s does not start at its parser span." % d["property"])
	var i: int = d["property"].length()
	while i < t.length() and _is_css_space(t[i]):
		i += 1
	if i >= t.length() or t[i] != ":":
		return EdError.make("ambiguous-source", "Declaration %s has no exact value boundary." % d["property"])
	i += 1
	while i < t.length() and _is_css_space(t[i]):
		i += 1
	var raw: String = d["raw"]
	if t.substr(i, raw.length()) != raw:
		return EdError.make("ambiguous-source", "Declaration %s value does not match its parser span." % d["property"])
	var content = _trailing_trivia_start(path, raw)
	if content is EdError:
		return content
	return d["start"] + i + content


static func _trailing_trivia_start(path: String, v: String) -> Variant:
	var i := 0
	var content_end := 0
	var quote := ""
	while i < v.length():
		var ch := v[i]
		if not quote.is_empty():
			if ch == "\\":
				i += mini(2, v.length() - i)
				content_end = i
				continue
			i += 1
			content_end = i
			if ch == quote:
				quote = ""
			continue
		if ch == "\"" or ch == "'":
			quote = ch
			i += 1
			content_end = i
			continue
		if ch == "/" and i + 1 < v.length() and v[i + 1] == "*":
			var close := v.find("*/", i + 2)
			if close < 0:
				return _unsafe(path, "The trailing declaration trivia contains an unterminated block comment.")
			i = close + 2
			continue
		i += 1
		if not _is_css_space(ch):
			content_end = i
	if not quote.is_empty():
		return _unsafe(path, "The trailing declaration region ends inside a quoted value.")
	return content_end


## {semicolon: offset or -1, comment: offset of first comment or -1}
static func _tokenize_tail(path: String, t: String) -> Variant:
	var i := 0
	var semi := -1
	var comment := -1
	while i < t.length() and _is_css_space(t[i]):
		i += 1
	if i < t.length() and t[i] == ";":
		semi = i
		i += 1
	while i < t.length():
		if _is_css_space(t[i]):
			i += 1
			continue
		if t[i] == "/" and i + 1 < t.length() and t[i + 1] == "*":
			if comment < 0:
				comment = i
			var end := t.find("*/", i + 2)
			if end < 0:
				return _unsafe(path, "The trailing declaration trivia contains an unterminated block comment.")
			i = end + 2
			continue
		return _unsafe(path, "The trailing declaration region contains nontrivia tokens.")
	return {"semicolon": semi, "comment": comment}


static func _multiline_layout(leading: String, src: String, decl_start: int) -> Variant:
	var nl := EdXml.first_newline(leading)
	if nl.is_empty():
		return null
	var indent = _declaration_indent(src, decl_start)
	if indent == null:
		var start := maxi(leading.rfind("\n"), leading.rfind("\r")) + 1
		var tail := leading.substr(start)
		indent = tail if not tail.is_empty() and EdXml.is_indent(tail) else "  "
	return nl + indent


static func _declaration_indent(src: String, decl_start: int) -> Variant:
	var s := EdXml.line_start(src, decl_start)
	var indent := src.substr(s, decl_start - s)
	return indent if not indent.is_empty() and EdXml.is_indent(indent) else null


static func _newline_before(src: String, offset: int) -> String:
	if offset >= 2 and src.substr(offset - 2, 2) == "\r\n":
		return "\r\n"
	if offset >= 1 and src[offset - 1] == "\r":
		return "\r"
	if offset >= 1 and src[offset - 1] == "\n":
		return "\n"
	return ""


static func _is_css_space(ch: String) -> bool:
	return ch == " " or ch == "\t" or ch == "\r" or ch == "\n" or ch == "\f"


static func _unsafe(path: String, detail: String) -> EdError:
	return EdError.make("unsafe-source", "%s The style source %s was not changed." % [detail, path])
