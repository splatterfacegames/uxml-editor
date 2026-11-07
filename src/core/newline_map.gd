class_name EdNewlineMap
extends RefCounted
## A display copy of a buffer with every line break as "\n", and the offset
## map back to the buffer.
##
## Text controls work in "\n" lines. The source view edits the display text;
## to_buffer_patch() turns a display edit into a buffer patch that keeps
## every untouched "\r\n" and "\r" exactly and writes new line breaks in the
## buffer's own newline style.

var buffer_text: String = ""
var display: String = ""
var newline: String = "\n"
## Display offsets of the line breaks that are two characters ("\r\n") in
## the buffer, ascending.
var _crlf_at: PackedInt32Array = PackedInt32Array()


static func make(text: String, buffer_newline: String = "") -> EdNewlineMap:
	var m := EdNewlineMap.new()
	m.buffer_text = text
	m.newline = buffer_newline if not buffer_newline.is_empty() else EdSourceBuffer.new("", text).newline()
	var out := PackedStringArray()
	var i := 0
	var last := 0
	var removed := 0
	var n := text.length()
	while i < n:
		var c := text.unicode_at(i)
		if c == 13:
			out.append(text.substr(last, i - last))
			out.append("\n")
			if i + 1 < n and text.unicode_at(i + 1) == 10:
				m._crlf_at.append(i - removed)
				removed += 1
				i += 2
			else:
				i += 1
			last = i
			continue
		i += 1
	out.append(text.substr(last))
	m.display = "".join(out)
	return m


func to_buffer(d: int) -> int:
	# Count the CRLF breaks strictly before display offset d.
	var lo := 0
	var hi := _crlf_at.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if _crlf_at[mid] < d:
			lo = mid + 1
		else:
			hi = mid
	return d + lo


func to_display(b: int) -> int:
	# The "\r" of the k-th CRLF is at buffer offset _crlf_at[k] + k.
	var removed := 0
	for k in _crlf_at.size():
		if _crlf_at[k] + k < b:
			removed += 1
		else:
			break
	return b - removed


## The buffer patch for a change of the display text to `new_display`, or
## null when nothing changed.
func to_buffer_patch(new_display: String) -> Variant:
	var old := display
	if old == new_display:
		return null
	var p := 0
	var max_p := mini(old.length(), new_display.length())
	while p < max_p and old.unicode_at(p) == new_display.unicode_at(p):
		p += 1
	var s := 0
	var max_s := max_p - p
	while s < max_s and old.unicode_at(old.length() - 1 - s) == new_display.unicode_at(new_display.length() - 1 - s):
		s += 1
	var inserted := new_display.substr(p, new_display.length() - s - p)
	if newline != "\n":
		inserted = inserted.replace("\n", newline)
	return EdSourcePatch.make(to_buffer(p), to_buffer(old.length() - s), inserted)
