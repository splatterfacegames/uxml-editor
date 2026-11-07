class_name EdDiagnostics
extends RefCounted
## The entries of the diagnostics panel: godot-uxml diagnostics of the last
## render of each open document, the parse problems of the editor, and the
## editor refusals.
##
## Entry: {severity: "error"|"warning"|"info", source: "godot-uxml"|"editor",
##         file, start, end, line, column, kind, message}
## `start`/`end` are String offsets in the file (-1: no range). godot-uxml
## gives a start offset only (request R11); range_end() finds the end of
## the token or tag at the start.

const SEVERITIES := ["error", "warning", "info"]
const SOURCES := ["godot-uxml", "editor"]

## godot-uxml kinds that stop part of the document from loading.
const ERROR_KINDS := ["malformed", "import-unresolved", "import-cycle", "missing-file", "path-outside-root",
	"malformed-reference", "template-not-declared", "template-cycle", "template-depth-exceeded"]
const INFO_KINDS := ["version-dependent"]


static func severity_of(kind: String) -> String:
	if ERROR_KINDS.has(kind):
		return "error"
	if INFO_KINDS.has(kind):
		return "info"
	return "warning"


## Every entry for the open files. `render_diags`: document path -> the
## godot-uxml diagnostics of its last render. `root`: the project root, to
## make godot-uxml paths project-relative.
static func collect(state: EdEditorState, render_diags: Dictionary, root: String) -> Array:
	var out: Array = []
	var ws := state.workspace
	var files := state.open_files()
	for p in files:
		var b := ws.buffer(p)
		if b == null:
			continue
		if not b.exact:
			out.append(_entry("error", "editor", p, 0, 0, "inexact", "The file does not decode to its exact bytes; it is read only.", b.text))
		var uxml: bool = p.to_lower().ends_with(".uxml")
		var problems: Array = ws.uxml(p).problems if uxml else ws.uss(p).problems
		for pr in problems:
			out.append(_entry("error", "editor", p, int(pr["start"]), int(pr["end"]), "parse", pr["message"], b.text))
		if uxml:
			for n in ws.uxml(p).nodes:
				if n.parent != null and not EdElementCatalog.is_known(n.local) and n.local != "Style" and n.local != "Template" and n.local != "Instance" and n.local != "AttributeOverrides":
					out.append(_entry("warning", "editor", p, n.open_start, n.open_end, "unknown-element",
						"<%s> is not an element that godot-uxml knows. It stays in the document." % n.name, b.text))
	var seen := {}
	for doc in render_diags:
		for d in render_diags[doc]:
			var f := relative(String(d.get("file", "")), root)
			var key := "%s|%d|%s|%s" % [f, int(d.get("offset", 0)), d.get("kind", ""), d.get("message", "")]
			if seen.has(key):
				continue
			seen[key] = true
			var start := int(d.get("offset", -1))
			var text := ws.text(f) if ws.has(f) else ""
			var e := _entry(severity_of(String(d.get("kind", ""))), "godot-uxml", f, start, -1, String(d.get("kind", "")), String(d.get("message", "")), text)
			e["line"] = int(d.get("line", e["line"]))
			e["column"] = int(d.get("column", e["column"]))
			if ws.has(f):
				e["end"] = range_end(ws, f, start)
			out.append(e)
	# godot-uxml reports an unknown element of a rendered document itself
	# (unsupported-control): one entry is enough.
	var rendered := {}
	for e in out:
		if e["source"] == "godot-uxml":
			rendered["%s|%d" % [e["file"], e["start"]]] = true
	out = out.filter(func(e): return e["kind"] != "unknown-element" or not rendered.has("%s|%d" % [e["file"], e["start"]]))
	for r in state.refusals:
		var f := String(r.get("file", ""))
		out.append(_entry("warning", "editor", f, int(r.get("offset", -1)), int(r.get("end", -1)), "refused",
			"Refused: " + String(r.get("message", "")), ws.text(f) if ws.has(f) else ""))
	out.sort_custom(_before)
	return out


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var sa := SEVERITIES.find(a["severity"])
	var sb := SEVERITIES.find(b["severity"])
	if sa != sb:
		return sa < sb
	if a["file"] != b["file"]:
		return a["file"] < b["file"]
	return a["start"] < b["start"]


static func _entry(severity: String, source: String, file: String, start: int, end: int, kind: String, message: String, text: String) -> Dictionary:
	var lc := UxmlDiagnostic.line_col(text, start) if start >= 0 else Vector2i(0, 0)
	return {"severity": severity, "source": source, "file": file, "start": start, "end": end if end >= start else start,
		"line": lc.x, "column": lc.y, "kind": kind, "message": message}


## A godot-uxml file path relative to the project root.
static func relative(f: String, root: String) -> String:
	if root.is_empty():
		return f
	if EdBufferResolver.key(f).begins_with(EdBufferResolver.key(root) + "/"):
		return f.substr(root.length() + 1)
	return f


## The end of the range at `start` in `path`: the open tag of an element
## that starts there, the attribute that holds `start`, or the token.
static func range_end(ws: EdWorkspace, path: String, start: int) -> int:
	var text := ws.text(path)
	if start < 0 or start >= text.length():
		return start
	if path.to_lower().ends_with(".uxml"):
		var t := ws.uxml(path)
		var n := t.find_by_open_start(start)
		if n != null:
			return n.open_end
		n = t.element_at_offset(start)
		if n != null:
			for a in n.attributes:
				if start >= int(a["start"]) and start < int(a["end"]):
					return int(a["end"])
	var e := start
	while e < text.length() and not " \t\r\n;{}<>\"'".contains(text[e]):
		e += 1
	return maxi(e, start + 1)


## Entries that pass the filters ("" passes everything).
static func filter(entries: Array, severity: String, file: String, source: String) -> Array:
	var out: Array = []
	for e in entries:
		if (severity.is_empty() or e["severity"] == severity) and (file.is_empty() or e["file"] == file) and (source.is_empty() or e["source"] == source):
			out.append(e)
	return out


## One line of the list.
static func line(e: Dictionary) -> String:
	var where: String = String(e["file"]).get_file() if not String(e["file"]).is_empty() else "(no file)"
	if e["start"] >= 0:
		where += ":%d:%d" % [e["line"], e["column"]]
	var icons := {"error": "●", "warning": "▲", "info": "○"}
	var icon: String = icons[e["severity"]]
	return "%s %-7s  %-10s  %s  %s" % [icon, e["severity"], e["source"], where, e["message"]]
