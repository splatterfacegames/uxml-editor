class_name EdSourcePatch
extends RefCounted
## Validate, apply and invert sets of source patches.
##
## A patch is a Dictionary {start: int, end: int, replacement: String}.
## Offsets are Godot String indices (Unicode code points). The old
## TypeScript editor used UTF-16 code units; code points cannot split a
## surrogate pair, so the surrogate checks of that version have no
## equivalent here.
##
## A patch set is valid when every patch is inside the source, no two
## patches overlap and no two patches start at the same offset (two
## insertions at one offset have no defined order). Patches are applied
## against the original text, as one set.


static func make(start: int, end: int, replacement: String) -> Dictionary:
	return {"start": start, "end": end, "replacement": replacement}


## Returns {ok: true, patches: Array (sorted copies)} or
## {ok: false, error: {code, patch_index, conflicting_patch_index?, message}}.
static func validate(source: String, patches: Array) -> Dictionary:
	var indexed: Array = []
	for i in patches.size():
		var p = patches[i]
		if typeof(p) != TYPE_DICTIONARY:
			return _invalid("invalid-patch", i, "Patch %d must be a Dictionary." % i)
		var start = p.get("start")
		var end = p.get("end")
		var replacement = p.get("replacement")
		if typeof(start) != TYPE_INT or typeof(end) != TYPE_INT:
			return _invalid("non-integer", i, "Patch %d has non-integer offsets." % i)
		if typeof(replacement) != TYPE_STRING:
			return _invalid("invalid-replacement", i, "Patch %d has a non-string replacement." % i)
		if start < 0 or end < 0:
			return _invalid("negative-offset", i, "Patch %d has a negative offset." % i)
		if end < start:
			return _invalid("reversed-span", i, "Patch %d ends before it starts." % i)
		if start > source.length() or end > source.length():
			return _invalid("out-of-range", i, "Patch %d ends at %d, outside source length %d." % [i, end, source.length()])
		indexed.append({"start": start, "end": end, "replacement": replacement, "patch_index": i})
	indexed.sort_custom(_compare)
	for k in range(1, indexed.size()):
		var prev: Dictionary = indexed[k - 1]
		var cur: Dictionary = indexed[k]
		if cur["start"] == prev["start"]:
			var err := _invalid("ambiguous-same-start", cur["patch_index"],
				"Patch %d has the same start %d as patch %d." % [cur["patch_index"], cur["start"], prev["patch_index"]])
			err["error"]["conflicting_patch_index"] = prev["patch_index"]
			return err
		if cur["start"] < prev["end"]:
			var err := _invalid("overlap", cur["patch_index"],
				"Patch %d overlaps patch %d." % [cur["patch_index"], prev["patch_index"]])
			err["error"]["conflicting_patch_index"] = prev["patch_index"]
			return err
	var out: Array = []
	for p in indexed:
		out.append(make(p["start"], p["end"], p["replacement"]))
	return {"ok": true, "patches": out}


## Apply a valid patch set. Returns the new text, or null when invalid.
static func apply(source: String, patches: Array) -> Variant:
	var v := validate(source, patches)
	if not v["ok"]:
		return null
	return apply_sorted(source, v["patches"])


## Apply patches already sorted and validated by validate().
static func apply_sorted(source: String, sorted: Array) -> String:
	var chunks := PackedStringArray()
	var cursor := 0
	for p in sorted:
		chunks.append(source.substr(cursor, p["start"] - cursor))
		chunks.append(p["replacement"])
		cursor = p["end"]
	chunks.append(source.substr(cursor))
	return "".join(chunks)


## The patch set that turns apply(source, patches) back into source.
## Adjacent patches merge into one inverse patch. Returns null when invalid.
static func invert(source: String, patches: Array) -> Variant:
	var v := validate(source, patches)
	if not v["ok"]:
		return null
	var sorted: Array = v["patches"]
	var inverse: Array = []
	var delta := 0
	var g := 0
	while g < sorted.size():
		var e := g
		var length: int = sorted[g]["replacement"].length()
		while e + 1 < sorted.size() and sorted[e + 1]["start"] == sorted[e]["end"]:
			e += 1
			length += sorted[e]["replacement"].length()
		var first: Dictionary = sorted[g]
		var last: Dictionary = sorted[e]
		var start: int = first["start"] + delta
		inverse.append(make(start, start + length, source.substr(first["start"], last["end"] - first["start"])))
		delta += length - (last["end"] - first["start"])
		g = e + 1
	return inverse


static func _compare(a: Dictionary, b: Dictionary) -> bool:
	if a["start"] != b["start"]:
		return a["start"] < b["start"]
	if a["end"] != b["end"]:
		return a["end"] < b["end"]
	return a["patch_index"] < b["patch_index"]


static func _invalid(code: String, index: int, message: String) -> Dictionary:
	return {"ok": false, "error": {"code": code, "patch_index": index, "message": message}}
