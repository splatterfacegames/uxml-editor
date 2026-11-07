class_name EdXml
extends RefCounted
## XML lexing and escaping helpers for source patches.

const XML_NS := "http://www.w3.org/XML/1998/namespace"
const XMLNS_NS := "http://www.w3.org/2000/xmlns/"


## Read an attribute lexeme `name = "value"` that spans exactly
## [start, end). Returns {name, quote, value_start, value_end} or null when
## the span is not exactly one quoted attribute.
static func read_attribute_lexeme(source: String, start: int, end: int) -> Variant:
	if start < 0 or end < start or end > source.length():
		return null
	var lex := source.substr(start, end - start)
	var i := 0
	while i < lex.length() and not is_space(lex.unicode_at(i)) and not "=/>".contains(lex[i]):
		i += 1
	if i == 0:
		return null
	var attr_name := lex.substr(0, i)
	while i < lex.length() and is_space(lex.unicode_at(i)):
		i += 1
	if i >= lex.length() or lex[i] != "=":
		return null
	i += 1
	while i < lex.length() and is_space(lex.unicode_at(i)):
		i += 1
	if i >= lex.length():
		return null
	var quote := lex[i]
	if quote != "\"" and quote != "'":
		return null
	var close := lex.find(quote, i + 1)
	if close != lex.length() - 1:
		return null
	return {"name": attr_name, "quote": quote, "value_start": start + i + 1, "value_end": end - 1}


## Escape `value` for an attribute quoted with `quote`. Returns null when
## the value has a character XML 1.0 cannot represent.
static func escape_attribute_value(value: String, quote: String) -> Variant:
	var out := PackedStringArray()
	for i in value.length():
		var cp := value.unicode_at(i)
		if not is_xml_code_point(cp):
			return null
		var ch := value[i]
		if ch == "&":
			out.append("&amp;")
		elif ch == "<":
			out.append("&lt;")
		elif ch == quote:
			out.append("&quot;" if quote == "\"" else "&apos;")
		elif cp == 9:
			out.append("&#x9;")
		elif cp == 10:
			out.append("&#xA;")
		elif cp == 13:
			out.append("&#xD;")
		else:
			out.append(ch)
	return "".join(out)


static func is_space(c: int) -> bool:
	return c == 32 or c == 9 or c == 10 or c == 13


static func is_space_char(ch: String) -> bool:
	return ch == " " or ch == "\t" or ch == "\n" or ch == "\r"


static func is_only_space(s: String) -> bool:
	for i in s.length():
		if not is_space(s.unicode_at(i)):
			return false
	return true


static func is_xml_code_point(cp: int) -> bool:
	return cp == 0x9 or cp == 0xA or cp == 0xD \
		or (cp >= 0x20 and cp <= 0xD7FF) \
		or (cp >= 0xE000 and cp <= 0xFFFD) \
		or (cp >= 0x10000 and cp <= 0x10FFFF)


static func is_nc_name(s: String) -> bool:
	if s.is_empty():
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		var start_ok := (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95
		if i == 0:
			if not start_ok:
				return false
		elif not (start_ok or (c >= 48 and c <= 57) or c == 46 or c == 45):
			return false
	return true


static func is_qualified_name(s: String) -> bool:
	var parts := s.split(":")
	if parts.size() > 2:
		return false
	for p in parts:
		if not is_nc_name(p):
			return false
	return true


## True when `fragment` is exactly one well-formed element whose prefixes
## are bound by `bindings` (prefix -> URI) or by declarations inside it.
static func is_element_fragment(fragment: String, bindings: Dictionary) -> bool:
	if fragment.is_empty() or fragment.strip_edges() != fragment:
		return false
	var parsed := EdUxmlSource.parse(fragment)
	if parsed.root == null or not parsed.problems.is_empty():
		return false
	if parsed.root.open_start != 0 or parsed.root.outer_end() != fragment.length():
		return false
	if not _strict_markup(fragment):
		return false
	for n in parsed.nodes:
		for a in n.attributes:
			if a["raw"].contains("<") or EdUxmlSource.decode_strict(a["raw"]) == null:
				return false
	return _names_bound(parsed.root, bindings)


## Reject markup the lenient scanner skips but XML forbids inside a fragment
## (stray `<`, `&` outside entities, `>` without a tag).
static func _strict_markup(fragment: String) -> bool:
	for k in fragment.length():
		if not is_xml_code_point(fragment.unicode_at(k)):
			return false
	var i := 0
	while true:
		var amp := fragment.find("&", i)
		if amp < 0:
			break
		var semi := fragment.find(";", amp)
		if semi < 0:
			return false
		if EdUxmlSource.decode_strict(fragment.substr(amp, semi - amp + 1)) == null:
			return false
		i = semi + 1
	return true


static func _names_bound(el: EdUxmlNode, inherited: Dictionary) -> bool:
	var scope := inherited.duplicate()
	for a in el.attributes:
		var n: String = a["name"]
		if n == "xmlns":
			scope[""] = a["value"]
		elif n.begins_with("xmlns:"):
			scope[n.substr(6)] = a["value"]
	if not is_qualified_name(el.name) or (not el.prefix.is_empty() and not scope.has(el.prefix)):
		return false
	for a in el.attributes:
		var n: String = a["name"]
		if not is_qualified_name(n):
			return false
		var colon := n.find(":")
		if colon > 0 and n.substr(0, colon) != "xmlns" and not scope.has(n.substr(0, colon)):
			return false
	for c in el.children:
		if not _names_bound(c, scope):
			return false
	return true


## The line indentation (tabs and spaces) before `offset`, or "" when other
## text precedes `offset` on its line.
static func line_indent_at(source: String, offset: int) -> String:
	var ls := line_start(source, offset)
	var indent := source.substr(ls, offset - ls)
	return indent if is_indent(indent) else ""


static func line_start(source: String, offset: int) -> int:
	var a := source.rfind("\n", offset - 1) if offset > 0 else -1
	var b := source.rfind("\r", offset - 1) if offset > 0 else -1
	return maxi(a, b) + 1


static func is_indent(s: String) -> bool:
	for i in s.length():
		if s[i] != " " and s[i] != "\t":
			return false
	return true


## The run of XML whitespace at the end of `s`.
static func trailing_space(s: String) -> String:
	var i := s.length()
	while i > 0 and is_space(s.unicode_at(i - 1)):
		i -= 1
	return s.substr(i)


## The first line break in `s`: "\r\n", "\r", "\n" or "".
static func first_newline(s: String) -> String:
	for i in s.length():
		if s[i] == "\r":
			return "\r\n" if i + 1 < s.length() and s[i + 1] == "\n" else "\r"
		if s[i] == "\n":
			return "\n"
	return ""
