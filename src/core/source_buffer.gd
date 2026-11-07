class_name EdSourceBuffer
extends RefCounted
## The exact text of one project file.
##
## A buffer is immutable: apply() returns a new buffer. `text` is the decoded
## UTF-8 text without the byte-order mark; `bom` records the mark, so
## to_bytes() gives back the original bytes. A file that does not decode to
## the same bytes (invalid UTF-8, NUL bytes) has `exact == false`; the
## editor shows such a file but never patches or saves it.

const BOM := [0xEF, 0xBB, 0xBF]

var path: String = ""
var text: String = ""
var bom: bool = false
var exact: bool = true
## "none", "lf", "crlf", "cr" or "mixed".
var newline_style: String = "none"


func _init(buffer_path: String = "", buffer_text: String = "", has_bom: bool = false) -> void:
	path = buffer_path
	text = buffer_text
	bom = has_bom
	newline_style = observe_newline_style(buffer_text)


static func from_bytes(buffer_path: String, bytes: PackedByteArray) -> EdSourceBuffer:
	var has_bom := bytes.size() >= 3 and bytes[0] == BOM[0] and bytes[1] == BOM[1] and bytes[2] == BOM[2]
	var body := bytes.slice(3) if has_bom else bytes
	var decoded := body.get_string_from_utf8()
	var buffer := EdSourceBuffer.new(buffer_path, decoded, has_bom)
	buffer.exact = buffer.to_bytes() == bytes
	return buffer


func to_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	if bom:
		out.append_array(PackedByteArray(BOM))
	out.append_array(text.to_utf8_buffer())
	return out


## A new buffer with `patches` applied, or null when the set is invalid.
func apply(patches: Array) -> EdSourceBuffer:
	var next = EdSourcePatch.apply(text, patches)
	if next == null:
		return null
	return with_text(next)


func with_text(new_text: String) -> EdSourceBuffer:
	var b := EdSourceBuffer.new(path, new_text, bom)
	b.exact = exact
	return b


## The newline to use for new lines in this buffer.
func newline() -> String:
	match newline_style:
		"crlf":
			return "\r\n"
		"cr":
			return "\r"
		"mixed":
			var last := maxi(text.rfind("\n"), text.rfind("\r"))
			if last < 0:
				return "\n"
			if text[last] == "\n" and last > 0 and text[last - 1] == "\r":
				return "\r\n"
			return text[last]
	return "\n"


static func observe_newline_style(s: String) -> String:
	var crlf := 0
	var lf := 0
	var cr := 0
	var i := 0
	var n := s.length()
	while i < n:
		var c := s.unicode_at(i)
		if c == 13:
			if i + 1 < n and s.unicode_at(i + 1) == 10:
				crlf += 1
				i += 2
				continue
			cr += 1
		elif c == 10:
			lf += 1
		i += 1
	var kinds := int(crlf > 0) + int(lf > 0) + int(cr > 0)
	if kinds == 0:
		return "none"
	if kinds > 1:
		return "mixed"
	if crlf > 0:
		return "crlf"
	if lf > 0:
		return "lf"
	return "cr"
