class_name EdSourceHighlighter
extends SyntaxHighlighter
## UXML and USS colouring for the source view.

const C_TEXT := Color(0.83, 0.83, 0.83)
const C_TAG := Color(0.45, 0.68, 0.98)
const C_ATTR := Color(0.6, 0.84, 0.98)
const C_STRING := Color(0.84, 0.6, 0.47)
const C_COMMENT := Color(0.42, 0.6, 0.33)
const C_PUNCT := Color(0.55, 0.55, 0.55)
const C_SELECTOR := Color(0.84, 0.73, 0.49)
const C_PROPERTY := Color(0.6, 0.84, 0.98)
const C_AT := Color(0.77, 0.53, 0.75)
const C_NUMBER := Color(0.71, 0.81, 0.66)

var mode: String = "uxml"
## Per line: state at the line start. 0 = normal, 1 = in comment,
## 2 = in a tag (UXML) / in a block (USS), 3 = in a string inside a tag.
var _start: PackedInt32Array = PackedInt32Array()


func _update_cache() -> void:
	var te := get_text_edit()
	_start.resize(te.get_line_count())
	var state := 0
	var depth := 0
	for i in te.get_line_count():
		_start[i] = state | (depth << 4)
		var r := _scan(te.get_line(i), state, depth, null)
		state = r.x
		depth = r.y


func _get_line_syntax_highlighting(line: int) -> Dictionary:
	var te := get_text_edit()
	var s := 0
	if line < _start.size():
		s = _start[line]
	var out := {}
	_scan(te.get_line(line), s & 15, s >> 4, out)
	return out


func _scan(t: String, state: int, depth: int, out) -> Vector2i:
	return _scan_uxml(t, state, out) if mode == "uxml" else _scan_uss(t, state, depth, out)


static func _put(out, col: int, c: Color) -> void:
	if out != null:
		out[col] = {"color": c}


func _scan_uxml(t: String, state: int, out) -> Vector2i:
	var i := 0
	var n := t.length()
	var quote := ""
	_put(out, 0, C_COMMENT if state == 1 else (C_STRING if state == 3 else C_TEXT))
	while i < n:
		if state == 1:
			var e := t.find("-->", i)
			if e < 0:
				return Vector2i(1, 0)
			i = e + 3
			state = 0
			_put(out, i, C_TEXT)
			continue
		if state == 3:
			var e := t.find(quote if not quote.is_empty() else "\"", i)
			if e < 0:
				return Vector2i(3, 0)
			i = e + 1
			state = 2
			_put(out, i, C_ATTR)
			continue
		var ch := t[i]
		if state == 0:
			if t.substr(i, 4) == "<!--":
				_put(out, i, C_COMMENT)
				state = 1
				i += 4
				continue
			if ch == "<":
				_put(out, i, C_PUNCT)
				var j := i + 1
				if j < n and (t[j] == "/" or t[j] == "?" or t[j] == "!"):
					j += 1
				_put(out, j, C_TAG)
				var k := j
				while k < n and not " \t/>".contains(t[k]):
					k += 1
				_put(out, k, C_ATTR)
				state = 2
				i = k
				continue
			i += 1
			continue
		# state == 2: inside a tag
		if ch == "\"" or ch == "'":
			quote = ch
			_put(out, i, C_STRING)
			var e := t.find(ch, i + 1)
			if e < 0:
				return Vector2i(3, 0)
			i = e + 1
			_put(out, i, C_ATTR)
			continue
		if ch == ">" or (ch == "/" and i + 1 < n and t[i + 1] == ">") or (ch == "?" and i + 1 < n and t[i + 1] == ">"):
			_put(out, i, C_PUNCT)
			i += 1 if ch == ">" else 2
			state = 0
			_put(out, i, C_TEXT)
			continue
		if ch == "=":
			_put(out, i, C_PUNCT)
			_put(out, i + 1, C_ATTR)
		i += 1
	return Vector2i(state, 0)


func _scan_uss(t: String, state: int, depth: int, out) -> Vector2i:
	var i := 0
	var n := t.length()
	var in_value := false
	_put(out, 0, C_COMMENT if state == 1 else (C_PROPERTY if depth > 0 else C_SELECTOR))
	while i < n:
		if state == 1:
			var e := t.find("*/", i)
			if e < 0:
				return Vector2i(1, depth)
			i = e + 2
			state = 0
			_put(out, i, (C_STRING if in_value else C_PROPERTY) if depth > 0 else C_SELECTOR)
			continue
		var ch := t[i]
		if ch == "/" and i + 1 < n and t[i + 1] == "*":
			_put(out, i, C_COMMENT)
			state = 1
			i += 2
			continue
		if ch == "\"" or ch == "'":
			_put(out, i, C_STRING)
			var e := t.find(ch, i + 1)
			i = n if e < 0 else e + 1
			_put(out, i, C_STRING if in_value else C_TEXT)
			continue
		if ch == "@" and depth == 0:
			_put(out, i, C_AT)
		elif ch == "{":
			_put(out, i, C_PUNCT)
			depth += 1
			in_value = false
			_put(out, i + 1, C_PROPERTY)
		elif ch == "}":
			_put(out, i, C_PUNCT)
			depth = maxi(0, depth - 1)
			in_value = false
			_put(out, i + 1, C_PROPERTY if depth > 0 else C_SELECTOR)
		elif ch == ":" and depth > 0 and not in_value:
			_put(out, i, C_PUNCT)
			in_value = true
			_put(out, i + 1, C_STRING)
		elif ch == ";" and depth > 0:
			_put(out, i, C_PUNCT)
			in_value = false
			_put(out, i + 1, C_PROPERTY)
		elif in_value and (ch >= "0" and ch <= "9") and (i == 0 or " (,-".contains(t[i - 1])):
			_put(out, i, C_NUMBER)
			var k := i
			while k < n and (t[k].is_valid_float() or t[k] == "." or (t[k] >= "a" and t[k] <= "z") or t[k] == "%"):
				k += 1
			_put(out, k, C_STRING)
			i = k
			continue
		i += 1
	return Vector2i(state, depth)
