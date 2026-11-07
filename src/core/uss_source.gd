class_name EdUssSource
extends RefCounted
## USS text -> items with exact spans. Never fails hard.
##
## The item sequence follows godot-uxml `core/uss_parser.gd`: one item per
## rule, @import or other at-rule, in source order. Thus `item_index` here is
## the index of the same item in the godot-uxml sheet, and a cascade origin
## (sheet, item, declaration) maps to the exact source text.
##
## Item shapes:
##   {kind: "rule", item_index, start, end, selector_start, selector_end,
##    block_start (the "{"), block_end (past "}"), closed: bool,
##    selector_text, declarations: Array}
##   {kind: "import", item_index, start, end, url}
##   {kind: "unknown", item_index, start, end, at_rule}
## Declaration:
##   {index, property, value (comments removed), raw (as written, trimmed),
##    start (property start), end (value end), colon, value_start,
##    value_end, has_comment}

var items: Array = []
var problems: Array = []
var text: String = ""

var _src: String = ""
var _pos: int = 0


static func parse(source: String) -> EdUssSource:
	var p := EdUssSource.new()
	p._run(source)
	return p


## The declarations of [start, end) in `source`: an inline `style` value or
## a rule block. Offsets are offsets into `source`.
static func parse_declarations(source: String, start: int = 0, end: int = -1) -> Array:
	var p := EdUssSource.new()
	p._src = source
	var e := source.length() if end < 0 else end
	return p._declarations(start, e)


func rules() -> Array:
	var out: Array = []
	for it in items:
		if it["kind"] == "rule":
			out.append(it)
	return out


func item(index: int) -> Variant:
	return items[index] if index >= 0 and index < items.size() else null


func _run(source: String) -> void:
	text = source
	_src = source
	_pos = 0
	while true:
		_skip_trivia()
		if _pos >= _src.length():
			break
		var it: Dictionary = _at_rule() if _char(_pos) == 64 else _rule()
		it["item_index"] = items.size()
		items.append(it)


func _char(at: int) -> int:
	if at < 0 or at >= _src.length():
		return -1
	return _src.unicode_at(at)


static func _is_space(c: int) -> bool:
	return c == 32 or c == 9 or c == 10 or c == 13 or c == 12


static func _is_ident(c: int) -> bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95 or c == 45


func _problem(message: String, start: int, end: int) -> void:
	problems.append({"message": message, "start": start, "end": end})


static func find_quote_close(t: String, i: int) -> int:
	var q := t.unicode_at(i)
	var j := i + 1
	while j < t.length():
		var c := t.unicode_at(j)
		if c == 92:
			j += 2
			continue
		if c == q:
			return j + 1
		j += 1
	return -1


func _scan_to(from: int, stops: String, limit: int = -1) -> int:
	var n := _src.length()
	var lim := n if limit < 0 or limit > n else limit
	var i := from
	var depth := 0
	while i < lim:
		var c := _src.unicode_at(i)
		if c == 34 or c == 39:
			var close := find_quote_close(_src, i)
			i = n if close < 0 else close
			continue
		if c == 47 and i + 1 < n and _src.unicode_at(i + 1) == 42:
			var close := _src.find("*/", i + 2)
			i = n if close < 0 else close + 2
			continue
		if c == 40 or c == 91:
			depth += 1
		elif c == 41 or c == 93:
			if depth > 0:
				depth -= 1
		elif depth == 0 and stops.contains(char(c)):
			return i
		i += 1
	return n if lim == n else lim


func _trim(start: int, end: int) -> Vector2i:
	var s := start
	var e := end
	while s < e and _is_space(_src.unicode_at(s)):
		s += 1
	while e > s and _is_space(_src.unicode_at(e - 1)):
		e -= 1
	return Vector2i(s, e)


func _skip_trivia() -> void:
	while true:
		while _is_space(_char(_pos)):
			_pos += 1
		if _src.substr(_pos, 2) == "/*":
			var end := _src.find("*/", _pos + 2)
			_pos = _src.length() if end < 0 else end + 2
			continue
		return


func _end_of_block(from: int) -> int:
	var i := from + 1
	var depth := 1
	while i < _src.length():
		var c := _src.unicode_at(i)
		if c == 34 or c == 39:
			var close := find_quote_close(_src, i)
			i = _src.length() if close < 0 else close
			continue
		if c == 47 and _char(i + 1) == 42:
			var close := _src.find("*/", i + 2)
			i = _src.length() if close < 0 else close + 2
			continue
		if c == 123:
			depth += 1
		elif c == 125:
			depth -= 1
			if depth == 0:
				return i + 1
		i += 1
	return _src.length()


func _read_ident(i: int) -> int:
	var j := i
	while j < _src.length() and _is_ident(_src.unicode_at(j)):
		j += 1
	return j


func _declarations(start: int, end: int) -> Array:
	var out: Array = []
	var pos := start
	while pos < end:
		while pos < end and (_is_space(_char(pos)) or _src.substr(pos, 2) == "/*"):
			if _src.substr(pos, 2) == "/*":
				var close := _src.find("*/", pos + 2)
				pos = end if close < 0 else close + 2
			else:
				pos += 1
		if pos >= end:
			break
		if _char(pos) == 59:
			pos += 1
			continue
		var from := pos
		var colon := _scan_to(from, ":;}")
		if colon >= end or _char(colon) != 58:
			var to := mini(colon, end)
			_problem("declaration without a value", from, to)
			pos = to + 1
			continue
		var stop := mini(_scan_to(colon + 1, ";}", end), end)
		var v := _trim(colon + 1, stop)
		var raw := _src.substr(v.x, v.y - v.x)
		out.append({
			"index": out.size(),
			"property": _src.substr(from, colon - from).strip_edges(),
			"value": strip_comments(raw),
			"raw": raw,
			"start": from,
			"end": v.y,
			"colon": colon,
			"value_start": v.x,
			"value_end": v.y,
			"has_comment": raw.contains("/*"),
		})
		pos = stop + 1
	return out


## A value without its comments (quoted strings kept), trimmed.
static func strip_comments(t: String) -> String:
	if t.find("/*") < 0:
		return t.strip_edges()
	var out := ""
	var i := 0
	while i < t.length():
		var c := t.unicode_at(i)
		if c == 34 or c == 39:
			var close := find_quote_close(t, i)
			if close < 0:
				return (out + t.substr(i)).strip_edges()
			out += t.substr(i, close - i)
			i = close
			continue
		if c == 47 and i + 1 < t.length() and t.unicode_at(i + 1) == 42:
			var close := t.find("*/", i + 2)
			if close < 0:
				return out.strip_edges()
			out += " "
			i = close + 2
			continue
		out += char(c)
		i += 1
	return out.strip_edges()


func _at_rule() -> Dictionary:
	var start := _pos
	var name_end := _read_ident(_pos + 1)
	var at_name := _src.substr(_pos + 1, name_end - _pos - 1)
	var brace := _scan_to(name_end, "{;")
	if brace < _src.length() and _char(brace) == 123:
		var end := _end_of_block(brace)
		_pos = end
		return {"kind": "unknown", "at_rule": at_name, "start": start, "end": end}
	var end := brace + 1 if brace < _src.length() else _src.length()
	_pos = end
	if at_name == "import":
		var body := _src.substr(name_end, end - name_end)
		var quoted = _first_quoted(body)
		if quoted == null:
			_problem("@import without a quoted path", start, end)
			return {"kind": "unknown", "at_rule": at_name, "start": start, "end": end}
		return {"kind": "import", "url": quoted, "start": start, "end": end}
	return {"kind": "unknown", "at_rule": at_name, "start": start, "end": end}


static func _first_quoted(t: String) -> Variant:
	for i in t.length():
		var c := t.unicode_at(i)
		if c == 34 or c == 39:
			var close := find_quote_close(t, i)
			if close < 0:
				return null
			return t.substr(i + 1, close - i - 2)
	return null


func _rule() -> Dictionary:
	var start := _pos
	var brace := _scan_to(start, "{")
	if brace >= _src.length():
		_problem("rule without a block", start, _src.length())
		_pos = _src.length()
		return {"kind": "unknown", "at_rule": "", "start": start, "end": _src.length()}
	var sel := _trim(start, brace)
	var block_end := _end_of_block(brace)
	var closed := block_end <= _src.length() and _char(block_end - 1) == 125
	if not closed:
		_problem("unterminated rule block", start, block_end)
	_pos = block_end
	return {
		"kind": "rule",
		"start": sel.x,
		"end": block_end,
		"selector_start": sel.x,
		"selector_end": sel.y,
		"selector_text": _src.substr(sel.x, sel.y - sel.x),
		"block_start": brace,
		"block_end": block_end,
		"closed": closed,
		"declarations": _declarations(brace + 1, block_end - 1),
	}
