class_name EdSequentialPatchComposer
extends RefCounted
## Compose several patch sets, each against the text the previous set made,
## into one patch set against the original text. Commands that plan in
## steps (for example "insert, then reformat") use it.

var _original: String
## Segments: {kind: "o", start, end} (original text) or {kind: "i", text}.
var _segments: Array = []


func _init(original: String) -> void:
	_original = original
	if not original.is_empty():
		_segments = [{"kind": "o", "start": 0, "end": original.length()}]


## Returns OK or ERR_PARAMETER_RANGE_ERROR.
func apply(patches: Array) -> int:
	var ordered := patches.duplicate()
	ordered.sort_custom(func(a, b): return a["start"] > b["start"])
	for p in ordered:
		if p["start"] < 0 or p["end"] < p["start"] or p["end"] > length():
			return ERR_PARAMETER_RANGE_ERROR
		var s := _split_at(p["start"])
		var e := _split_at(p["end"])
		for k in e - s:
			_segments.remove_at(s)
		if not String(p["replacement"]).is_empty():
			_segments.insert(s, {"kind": "i", "text": p["replacement"]})
	return OK


func length() -> int:
	var n := 0
	for s in _segments:
		n += _seg_len(s)
	return n


func patches() -> Array:
	var out: Array = []
	var cursor := 0
	var replacement := ""
	for s in _segments:
		if s["kind"] == "i":
			replacement += s["text"]
			continue
		if s["start"] > cursor or not replacement.is_empty():
			_append(out, cursor, s["start"], replacement)
			replacement = ""
		cursor = s["end"]
	if cursor < _original.length() or not replacement.is_empty():
		_append(out, cursor, _original.length(), replacement)
	return out


func _append(out: Array, start: int, end: int, replacement: String) -> void:
	if _original.substr(start, end - start) == replacement:
		return
	out.append(EdSourcePatch.make(start, end, replacement))


func _split_at(offset: int) -> int:
	var cursor := 0
	for i in _segments.size():
		var s: Dictionary = _segments[i]
		var n := _seg_len(s)
		if offset == cursor:
			return i
		if offset < cursor + n:
			var rel := offset - cursor
			var left: Dictionary
			var right: Dictionary
			if s["kind"] == "o":
				left = {"kind": "o", "start": s["start"], "end": s["start"] + rel}
				right = {"kind": "o", "start": s["start"] + rel, "end": s["end"]}
			else:
				left = {"kind": "i", "text": s["text"].substr(0, rel)}
				right = {"kind": "i", "text": s["text"].substr(rel)}
			_segments[i] = left
			_segments.insert(i + 1, right)
			return i + 1
		cursor += n
	return _segments.size()


static func _seg_len(s: Dictionary) -> int:
	return s["end"] - s["start"] if s["kind"] == "o" else s["text"].length()
