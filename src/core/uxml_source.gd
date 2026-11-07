class_name EdUxmlSource
extends RefCounted
## UXML text -> EdUxmlNode tree with exact spans. Never fails hard.
##
## The grammar and the recovery follow godot-uxml `core/uxml_parser.gd`, so
## the editor tree and the rendered tree contain the same elements and each
## authored element has the same `open_start` as the rendered element's
## `open_tag_start`. tests/unit/test_uxml_alignment.gd checks this for every
## fixture. The editor parser adds what godot-uxml does not keep: the
## attribute value spans and quotes, the close tag spans and the problems
## that make an edit unsafe.
##
## Comments, CDATA, DOCTYPE and processing instructions are skipped. Text
## between tags is ignored, as in Unity. Elements after the root element are
## parsed for their extent and dropped, as godot-uxml drops them.

var root: EdUxmlNode = null
## Every kept element in preorder; nodes[i].id == i.
var nodes: Array = []
## {message, start, end}
var problems: Array = []
var text: String = ""

var _src: String = ""
var _pos: int = 0
var _keep := true


static func parse(source: String) -> EdUxmlSource:
	var p := EdUxmlSource.new()
	p._run(source)
	return p


func find_by_open_start(offset: int) -> EdUxmlNode:
	# Binary search: preorder ids are in increasing open_start order.
	var lo := 0
	var hi := nodes.size() - 1
	while lo <= hi:
		var mid := (lo + hi) >> 1
		var s: int = nodes[mid].open_start
		if s == offset:
			return nodes[mid]
		if s < offset:
			lo = mid + 1
		else:
			hi = mid - 1
	return null


## The deepest element whose outer span contains `offset`.
func element_at_offset(offset: int) -> EdUxmlNode:
	var best: EdUxmlNode = null
	for n in nodes:
		if n.open_start <= offset and offset < n.outer_end():
			best = n
		elif n.open_start > offset:
			break
	return best


func _run(source: String) -> void:
	text = source
	_src = source
	_pos = 0
	_seek_tag()
	if _pos < _src.length() and _is_name_start(_char(_pos + 1)):
		root = _parse_element(null, 0)
	else:
		_problem("no root element", 0, 0)
	while true:
		_seek_tag()
		if _pos >= _src.length():
			break
		var next := _char(_pos + 1)
		if next == 47:
			var gt := _src.find(">", _pos)
			var end := _src.length() if gt < 0 else gt + 1
			_problem("closing tag after the document root element", _pos, end)
			_pos = end
		elif _is_name_start(next):
			_problem("element after the document root element", _pos, _pos + 1)
			_keep = false
			_parse_element(null, 0)
			_keep = true
		else:
			_pos += 1


func _char(at: int) -> int:
	if at < 0 or at >= _src.length():
		return -1
	return _src.unicode_at(at)


static func _is_space(c: int) -> bool:
	return c == 32 or c == 9 or c == 10 or c == 13


static func _is_name_start(c: int) -> bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95


func _name_end(i: int) -> int:
	var n := _src.length()
	while i < n:
		var c := _src.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 65 and c <= 90) or (c >= 48 and c <= 58) or c == 95 or c == 46 or c == 45):
			return i
		i += 1
	return i


func _problem(message: String, start: int, end: int) -> void:
	problems.append({"message": message, "start": start, "end": end})


func _skip_space() -> void:
	var n := _src.length()
	while _pos < n and _is_space(_src.unicode_at(_pos)):
		_pos += 1


func _seek_tag() -> void:
	while true:
		var lt := _src.find("<", _pos)
		if lt < 0:
			_pos = _src.length()
			return
		var next := _char(lt + 1)
		if next == 33:
			if _src.substr(lt, 4) == "<!--":
				var end := _src.find("-->", lt + 4)
				_pos = _src.length() if end < 0 else end + 3
			elif _src.substr(lt, 9) == "<![CDATA[":
				var end := _src.find("]]>", lt + 9)
				_pos = _src.length() if end < 0 else end + 3
			else:
				var end := _src.find(">", lt)
				_pos = _src.length() if end < 0 else end + 1
			continue
		if next == 63:
			var end := _src.find("?>", lt + 2)
			_pos = _src.length() if end < 0 else end + 2
			continue
		_pos = lt
		return


func _read_attribute() -> Variant:
	var start := _pos
	_pos = _name_end(_pos)
	if _pos == start:
		return null
	var attr_name := _src.substr(start, _pos - start)
	var after_name := _pos
	_skip_space()
	if _char(_pos) != 61:
		_pos = after_name
		_problem('attribute "%s" has no value' % attr_name, start, after_name)
		return _attr(attr_name, "", start, after_name, after_name, after_name, "", false)
	_pos += 1
	_skip_space()
	var quote := _char(_pos)
	if quote != 34 and quote != 39:
		_problem('attribute "%s" has an unquoted value' % attr_name, start, _pos)
		return _attr(attr_name, "", start, _pos, _pos, _pos, "", false)
	_pos += 1
	var value_start := _pos
	var close := _src.find(char(quote), _pos)
	if close < 0:
		_problem('attribute "%s" has an unterminated value' % attr_name, start, _src.length())
		_pos = _src.length()
		return _attr(attr_name, _src.substr(value_start), start, _pos, value_start, _pos, char(quote), false)
	_pos = close + 1
	return _attr(attr_name, _src.substr(value_start, close - value_start), start, _pos, value_start, close, char(quote), true)


static func _attr(n: String, raw: String, start: int, end: int, vs: int, ve: int, quote: String, ok: bool) -> Dictionary:
	return {
		"name": n, "value": decode_entities(raw), "raw": raw,
		"start": start, "end": end, "value_start": vs, "value_end": ve,
		"quote": quote, "well_formed": ok,
	}


func _parse_element(parent: EdUxmlNode, depth: int) -> EdUxmlNode:
	var tag_start := _pos
	_pos += 1
	var name_start := _pos
	_pos = _name_end(_pos)
	var qname := _src.substr(name_start, _pos - name_start)
	var el := EdUxmlNode.new()
	el.name = qname
	var colon := qname.find(":")
	el.prefix = "" if colon < 0 else qname.substr(0, colon)
	el.local = qname if colon < 0 else qname.substr(colon + 1)
	el.depth = depth
	el.parent = parent
	if _keep:
		el.id = nodes.size()
		nodes.append(el)
		if parent != null:
			el.index_in_parent = parent.children.size()
			parent.children.append(el)
	var seen := {}
	while true:
		_skip_space()
		var c := _char(_pos)
		if c < 0:
			_problem("unterminated open tag", tag_start, _src.length())
			el.well_formed = false
			break
		if c == 62:
			_pos += 1
			break
		if c == 47 and _char(_pos + 1) == 62:
			_pos += 2
			el.self_closing = true
			break
		var attr = _read_attribute()
		if attr == null:
			_problem("unexpected character in tag", _pos, _pos + 1)
			el.well_formed = false
			_pos += 1
			continue
		if seen.has(attr["name"]):
			_problem('duplicate attribute "%s"' % attr["name"], attr["start"], _pos)
		seen[attr["name"]] = true
		if not attr["well_formed"]:
			el.well_formed = false
		el.attributes.append(attr)
	el.open_start = tag_start
	el.open_end = _pos
	el.inner_start = _pos
	el.inner_end = _pos
	if el.self_closing:
		return el
	while true:
		_seek_tag()
		if _pos >= _src.length():
			_problem("unterminated element <%s>" % qname, tag_start, _src.length())
			el.well_formed = false
			el.inner_end = _src.length()
			break
		var next := _char(_pos + 1)
		if next == 47:
			break
		if not _is_name_start(next):
			_pos += 1
			continue
		_parse_element(el, depth + 1)
	if _src.substr(_pos, 2) == "</":
		el.inner_end = _pos
		var close_start := _pos
		_pos += 2
		var cn_start := _pos
		_pos = _name_end(_pos)
		var close_name := _src.substr(cn_start, _pos - cn_start)
		_skip_space()
		var gt := _src.find(">", _pos)
		var end := _src.length() if gt < 0 else gt + 1
		if gt < 0:
			_problem("unterminated end tag", close_start, end)
			el.well_formed = false
		elif close_name != qname:
			_problem('closing tag "</%s>" does not match open tag "<%s>"' % [close_name, qname], close_start, end)
			el.well_formed = false
		_pos = end
		el.close_start = close_start
		el.close_end = end
	return el


## XML entity decoding with attribute-value normalization, as godot-uxml
## reads values (literal tab, CR, LF and CR LF become one space each).
static func decode_entities(raw: String) -> String:
	var t := raw
	if t.contains("\n") or t.contains("\r") or t.contains("\t"):
		t = t.replace("\r\n", " ").replace("\r", " ").replace("\n", " ").replace("\t", " ")
	if t.find("&") < 0:
		return t
	var out := ""
	var at := 0
	while true:
		var m := _entity_re().search(t, at)
		if m == null:
			break
		out += t.substr(at, m.get_start() - at) + _decode_one(m.get_string(1), m.get_string())
		at = m.get_end()
	return out + t.substr(at)


## Strict XML 1.0 decoding: null when the raw value has a `<`, a bare `&`
## or an unknown entity. Namespace checks use it.
static func decode_strict(raw: String) -> Variant:
	if raw.contains("<"):
		return null
	var i := 0
	while true:
		var amp := raw.find("&", i)
		if amp < 0:
			break
		var m := _entity_re().search(raw, amp)
		if m == null or m.get_start() != amp:
			return null
		if _decode_one(m.get_string(1), m.get_string()) == m.get_string():
			return null
		i = m.get_end()
	return decode_entities(raw)


static var _re: RegEx = null


static func _entity_re() -> RegEx:
	if _re == null:
		_re = RegEx.create_from_string("&(#x[0-9a-fA-F]+|#[0-9]+|lt|gt|quot|apos|amp);")
	return _re


static func _decode_one(body: String, raw: String) -> String:
	match body:
		"lt":
			return "<"
		"gt":
			return ">"
		"quot":
			return "\""
		"apos":
			return "'"
		"amp":
			return "&"
	var value := -1
	if body.begins_with("#x"):
		value = body.substr(2).hex_to_int()
	elif body.begins_with("#"):
		value = body.substr(1).to_int()
	if value >= 0 and value <= 0x10FFFF and not (value >= 0xD800 and value <= 0xDFFF):
		return char(value)
	return raw
